import Foundation
#if os(tvOS)
import TVServices
#endif
import Observation

@MainActor @Observable
final class CatalogStore {
    var rows: [String: [MediaItem]] = [:] {
        didSet {
            homeFeatured = HomeFeaturedSelection.pick(new: rows["new"] ?? [], movies: rows["movies"] ?? [],
                                                      tv: rows["tv"] ?? [], cartoons: rows["cartoons"] ?? [])
        }
    }
    /// Derived once when a feed changes, never during a five-second hero update.
    private(set) var homeFeatured: [MediaItem] = []
    var loading: Set<String> = []
    var errors: [String: String] = [:]
    var metadata: [String: Metadata] = [:]
    var details: [String: Details] = [:]
    var library: [LibraryTitle] = []
    var libraryError: String?
    var libraryLoading = false
    /// The server matches library titles itself (and says how many are left);
    /// then the apps never look those titles up on their own.
    var libraryMatchedByServer = false
    var libraryPending = 0
    /// Library sync: details and images saved on the device, new titles only.
    var syncing = false
    var syncDone = 0
    var syncTotal = 0
    private var enriching: Set<String> = []
    private var fetchingDetails: Set<String> = []

    func resolved(_ item: MediaItem) -> MediaItem {
        var value = item
        // A library title the server matched carries its own metadata.
        if item.sourceOverride?.path != nil && libraryMatchedByServer { return value }
        if let meta = metadata[item.title] {
            value.cleanTitle = meta.cleanTitle ?? value.cleanTitle
            value.poster = meta.poster ?? value.poster
            value.overview = meta.overview ?? value.overview
            value.rating = meta.rating ?? value.rating
            value.tmdbId = meta.tmdbId ?? value.tmdbId
            value.mediaType = meta.mediaType ?? value.mediaType
        }
        return value
    }
    func loadFeed(_ feed: String, api: TorrentTubeAPI, config: ServerConfig, refresh: Bool = false) async {
        guard config.searchEnabled, !loading.contains(feed) else { return }
        let cache = metadataCache(api.baseURL)
        await cache.load()
        guard !Task.isCancelled, !loading.contains(feed) else { return }

        // Show cached feed snapshot immediately (instant UI on cold start & tab switch):
        if rows[feed] == nil, let cached = cache.feed(for: feed) {
            rows[feed] = cached
            Task { await enrich(Array(cached.prefix(12)), api: api, config: config) }
            if !refresh && cache.isFeedFresh(for: feed) {
                #if os(tvOS)
                if feed == "new" { await publishTopShelf(cached, api: api, config: config) }
                #endif
                return
            }
        } else if !refresh && rows[feed] != nil && cache.isFeedFresh(for: feed) {
            #if os(tvOS)
            if feed == "new", let items = rows[feed] { await publishTopShelf(items, api: api, config: config) }
            #endif
            return
        }

        loading.insert(feed); errors[feed] = nil
        defer { loading.remove(feed) }
        do {
            let response: CatalogResponse = try await api.request("api/discover", query: [.init(name: "feed", value: feed)])
            try Task.checkCancellation()
            rows[feed] = response.results
            cache.storeFeed(response.results, for: feed)
            await enrich(Array(response.results.prefix(12)), api: api, config: config)
            #if os(tvOS)
            if feed == "new" { await publishTopShelf(response.results, api: api, config: config) }
            #endif
        } catch is CancellationError {} catch { errors[feed] = error.localizedDescription }
    }
    #if os(tvOS)
    private var publishingShelf: Set<URL> = []
    private var shelfPreviewWarmup: Task<Void, Never>?
    private func publishTopShelf(_ items: [MediaItem], api: TorrentTubeAPI, config: ServerConfig) async {
        guard TopShelfStore.defaults.bool(forKey: "showNewInTopShelf"),
              !publishingShelf.contains(api.baseURL), !Task.isCancelled, TopShelfStore.defaults.string(forKey: "activeServer") == api.baseURL.absoluteString else { return }
        publishingShelf.insert(api.baseURL)
        defer { publishingShelf.remove(api.baseURL) }
        var titles: [ShelfTitle] = []
        for item in items.prefix(30) {
            if titles.count == 10 || Task.isCancelled { break }
            let value = resolved(item)
            guard let poster = value.poster else { continue }
            await loadDetails(value, api: api, config: config)
            guard let detail = details[item.title], let backdrop = detail.backdrop else { continue }
            var title = ShelfTitle(id: ShelfTitle.identifier(api.baseURL.absoluteString + item.id), title: value.displayTitle,
                                   rawTitle: item.title, poster: higherResolution(poster, backdrop: false),
                                   magnet: item.magnet, downloadLink: item.downloadLink, tmdbID: value.tmdbId, mediaType: value.mediaType)
            title.backdrop = higherResolution(backdrop, backdrop: true).replacingOccurrences(of: "/w780/", with: "/w1280/")
            let series = (detail.mediaType ?? value.mediaType) == "tv"
            title.kind = L(detail.kind == "Cartoon" ? (series ? "Animated Series" : "Cartoon") : (series ? "TV Show" : "Movie"))
            title.year = detail.year
            title.rating = value.rating
            title.genres = detail.genres
            title.overview = detail.overview ?? value.overview
            if config.capabilities?.topShelfPreviews == true, let trailer = TrailerChoice.pick(detail.trailers ?? []) {
                title.previewURL = try? api.mediaURL("api/trailer/preview/" + trailer.key).absoluteString
            }
            titles.append(title)
        }
        if !items.isEmpty && titles.isEmpty { return }  // retain the cached shelf if details are temporarily unavailable
        let snapshot = await TopShelfArtwork.prepare(ShelfSnapshot(server: api.baseURL.absoluteString, titles: titles))
        guard !Task.isCancelled, TopShelfStore.defaults.string(forKey: "activeServer") == snapshot.server else { return }
        TopShelfStore.save(snapshot)
        TVTopShelfContentProvider.topShelfContentDidChange()
        shelfPreviewWarmup?.cancel()
        shelfPreviewWarmup = Task(priority: .utility) {
            for title in snapshot.titles {
                guard !Task.isCancelled, TopShelfStore.defaults.string(forKey: "activeServer") == snapshot.server else { return }
                guard let preview = title.previewURL, let url = URL(string: preview) else { continue }
                var request = URLRequest(url: url, timeoutInterval: 75)
                request.httpMethod = "HEAD"
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }
    #endif
    private var caches: [URL: MetadataCache] = [:]
    /// What is saved on this device for a server (posters, titles, details).
    func metadataCache(_ server: URL) -> MetadataCache {
        if let cache = caches[server] { return cache }
        let cache = MetadataCache(server: server)
        caches[server] = cache
        return cache
    }
    /// Settings: forget the saved matches and details, so they are looked up again.
    func refreshMetadata(api: TorrentTubeAPI) async {
        try? await api.command("api/library/metadata", method: "DELETE")  // the server's matches too
        metadataCache(api.baseURL).clear()
        metadata = [:]
        details = [:]
    }
    /// Settings: "Sync now" saves what is missing; "Rescan" has the server match
    /// every title again first, waits for it, then saves everything anew.
    func syncNow(api: TorrentTubeAPI, config: ServerConfig, rescan: Bool) async {
        if rescan { await refreshMetadata(api: api) }
        await loadLibrary(api: api)
        var waited = 0
        while libraryPending > 0 && waited < 600 && !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            waited += 3
            await loadLibrary(api: api)
        }
        await syncLibrary(api: api, config: config)
    }
    /// One line for Settings: when, how many titles, how much space.
    func syncSummary(_ server: URL) -> String {
        if syncing { return L("Saving %ld of %ld…", syncDone, syncTotal) }
        if libraryPending > 0 { return L("The server is matching %ld titles…", libraryPending) }
        let cache = metadataCache(server)
        let images = ByteCountFormatter.string(fromByteCount: Int64(URLCache.shared.currentDiskUsage), countStyle: .file)
        let data = ByteCountFormatter.string(fromByteCount: Int64(cache.bytes), countStyle: .file)
        guard let synced = cache.library?.synced else { return L("Not synced yet") }
        let when = synced.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Localizer.shared.language.locale))
        return L("Synced %@ · %ld titles · data %@ · images %@", when, cache.library?.titles.count ?? 0, data, images)
    }

    /// When the Library was last saved on this device.
    func lastSync(_ server: URL) -> Date? { metadataCache(server).library?.synced }

    /// Saves everything a Library title page shows - details, poster, backdrop,
    /// cast photos - for every title not saved yet. Run after each list load,
    /// it does nothing once all are saved, so only new titles cost requests.
    func syncLibrary(api: TorrentTubeAPI, config: ServerConfig) async {
        guard !syncing, config.tmdbEnabled, Self.libraryMetadataEnabled, libraryPending == 0 else { return }
        syncing = true
        defer { syncing = false }
        let cache = metadataCache(api.baseURL)
        await cache.load()
        guard !Task.isCancelled else { return }
        let items = library.filter { !$0.isTorrent && $0.tmdbId != nil }.map(libraryItem)
        let missing = items.filter { !cache.hasDetails($0.title) }
        syncDone = 0
        syncTotal = missing.count
        for chunk in stride(from: 0, to: missing.count, by: 3).map({ Array(missing[$0..<min($0 + 3, missing.count)]) }) {
            await withTaskGroup(of: Void.self) { group in
                for item in chunk { group.addTask(priority: .utility) { await self.loadDetails(item, api: api, config: config) } }
            }
            syncDone += chunk.count
            if Task.isCancelled { return }
        }
        // Images go to the on-device image cache; ones already there cost nothing.
        var urls: [URL] = []
        for item in items {
            if let poster = item.poster { urls.append(contentsOf: [URL(string: higherResolution(poster, backdrop: false))].compactMap { $0 }) }
            let saved = details[item.title] ?? cache.details(for: item.title)
            if let backdrop = saved?.backdrop, let url = URL(string: higherResolution(backdrop, backdrop: true)) { urls.append(url) }
            for person in (saved?.people ?? []).prefix(12) { if let photo = person.photo, let url = URL(string: photo) { urls.append(url) } }
        }
        // Disk-backed cache inspection and URL deduplication do not belong on the UI thread.
        let candidates = urls
        let needed = await Task.detached(priority: .utility) {
            var seen: Set<URL> = []
            return candidates.filter {
                seen.insert($0).inserted && URLCache.shared.cachedResponse(for: URLRequest(url: $0)) == nil
            }
        }.value
        if Task.isCancelled { return }
        syncTotal += needed.count
        for chunk in stride(from: 0, to: needed.count, by: 6).map({ Array(needed[$0..<min($0 + 6, needed.count)]) }) {
            await withTaskGroup(of: Void.self) { group in
                for url in chunk {
                    group.addTask(priority: .utility) { _ = try? await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)) }
                }
            }
            syncDone += chunk.count
            if Task.isCancelled { return }
        }
        cache.storeLibrary(library)
        await cache.flush()
    }

    /// Library titles are looked up only while "Posters and details" is on.
    nonisolated static var libraryMetadataEnabled: Bool { UserDefaults.standard.object(forKey: "libraryMetadata") as? Bool ?? true }

    func enrich(_ items: [MediaItem], api: TorrentTubeAPI, config: ServerConfig) async {
        guard config.tmdbEnabled else { return }
        let cache = metadataCache(api.baseURL)
        await cache.load()
        guard !Task.isCancelled else { return }
        var titles: [String] = []
        for item in items where metadata[item.title] == nil && !enriching.contains(item.title) && !titles.contains(item.title) {
            if item.sourceOverride?.path != nil && (!Self.libraryMetadataEnabled || libraryMatchedByServer) { continue }
            if let saved = cache.match(for: item.title) {
                if let found = saved.metadata { metadata[item.title] = found }
                continue  // a match, or a recent "no match" - nothing to ask
            }
            titles.append(item.title)
        }
        guard !titles.isEmpty else { return }
        enriching.formUnion(titles)
        defer { enriching.subtract(titles) }
        let asked = Array(titles.prefix(64))
        if let result: [String: Metadata] = try? await api.post("api/discover/enrich", body: ["titles": asked]), !Task.isCancelled {
            metadata.merge(result) { _, new in new }
            cache.store(result, asked: asked)
        }
    }
    func loadDetails(_ item: MediaItem, api: TorrentTubeAPI, config: ServerConfig, refresh: Bool = false) async {
        guard config.tmdbEnabled, refresh || details[item.title] == nil, !fetchingDetails.contains(item.title) else { return }
        if item.sourceOverride?.path != nil && !Self.libraryMetadataEnabled { return }
        let cache = metadataCache(api.baseURL)
        await cache.load()
        guard !Task.isCancelled, !fetchingDetails.contains(item.title), refresh || details[item.title] == nil else { return }
        // A copy saved before cast photos opened a person's page has no ids: fetch it again.
        if !refresh, let saved = cache.details(for: item.title), !(saved.people ?? []).contains(where: { $0.id == nil }) {
            details[item.title] = saved; return
        }
        fetchingDetails.insert(item.title)
        defer { fetchingDetails.remove(item.title) }
        let resolved = resolved(item)
        var query = [URLQueryItem(name: "title", value: item.title)]
        if let id = resolved.tmdbId, let type = resolved.mediaType {
            query = [.init(name: "type", value: type), .init(name: "id", value: String(id))]
        }
        if let result: Details = try? await api.request("api/details", query: query), !Task.isCancelled {
            details[item.title] = result
            cache.store(result, for: item.title, permanent: item.sourceOverride?.path != nil)
        }
    }
    func loadLibrary(api: TorrentTubeAPI) async {
        guard !libraryLoading else { return }
        let cache = metadataCache(api.baseURL)
        await cache.load()
        guard !Task.isCancelled, !libraryLoading else { return }
        // The list saved at the last sync shows at once; the server's answer replaces it.
        if library.isEmpty, let saved = cache.library {
            library = saved.titles
            libraryMatchedByServer = true
        }
        libraryLoading = true
        defer { libraryLoading = false }
        do {
            // Everything in the category folders; an older server only knows its finished torrents.
            if let result: LibraryResponse = try? await api.request("api/library") {
                library = result.items
                libraryMatchedByServer = result.metadataPending != nil
                libraryPending = result.metadataPending ?? 0
                if libraryMatchedByServer && libraryPending == 0 { cache.storeLibrary(result.items) }
            } else {
                try Task.checkCancellation()
                let result: TorrentListResponse = try await api.request("api/torrents")
                library = result.torrents.filter { $0.hasMetadata && $0.progress >= 100 }
                    .map { LibraryTitle(id: $0.id, name: $0.name, isTorrent: true) }
            }
            try Task.checkCancellation()
            libraryError = nil
        } catch is CancellationError {} catch { libraryError = error.localizedDescription }
    }
}
