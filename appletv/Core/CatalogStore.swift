import Foundation
#if os(tvOS)
import TVServices
#endif
import Observation

@MainActor @Observable
final class CatalogStore {
    var rows: [String: [MediaItem]] = [:]
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
        guard config.searchEnabled, !loading.contains(feed), refresh || rows[feed] == nil else { return }
        loading.insert(feed); errors[feed] = nil
        defer { loading.remove(feed) }
        do {
            let response: CatalogResponse = try await api.request("api/discover", query: [.init(name: "feed", value: feed)])
            try Task.checkCancellation()
            rows[feed] = response.results
            await enrich(Array(response.results.prefix(12)), api: api, config: config)
            #if os(tvOS)
            if feed == "new", !Task.isCancelled, TopShelfStore.defaults.string(forKey: "activeServer") == api.baseURL.absoluteString {
                let titles = response.results.prefix(12).compactMap { item -> ShelfTitle? in
                    let value = resolved(item)
                    guard let poster = value.poster else { return nil }
                    return ShelfTitle(id: ShelfTitle.identifier(api.baseURL.absoluteString + item.id), title: value.displayTitle,
                                      rawTitle: item.title, poster: higherResolution(poster, backdrop: false),
                                      magnet: item.magnet, downloadLink: item.downloadLink,
                                      tmdbID: value.tmdbId, mediaType: value.mediaType)
                }
                TopShelfStore.save(ShelfSnapshot(server: api.baseURL.absoluteString, titles: titles))
                TVTopShelfContentProvider.topShelfContentDidChange()
            }
            #endif
        } catch is CancellationError {} catch { errors[feed] = error.localizedDescription }
    }
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
    /// Library titles are looked up only while "Posters and details" is on.
    nonisolated static var libraryMetadataEnabled: Bool { UserDefaults.standard.object(forKey: "libraryMetadata") as? Bool ?? true }

    func enrich(_ items: [MediaItem], api: TorrentTubeAPI, config: ServerConfig) async {
        guard config.tmdbEnabled else { return }
        let cache = metadataCache(api.baseURL)
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
    func loadDetails(_ item: MediaItem, api: TorrentTubeAPI, config: ServerConfig) async {
        guard config.tmdbEnabled, details[item.title] == nil, !fetchingDetails.contains(item.title) else { return }
        if item.sourceOverride?.path != nil && !Self.libraryMetadataEnabled { return }
        let cache = metadataCache(api.baseURL)
        if let saved = cache.details(for: item.title) { details[item.title] = saved; return }
        fetchingDetails.insert(item.title)
        defer { fetchingDetails.remove(item.title) }
        let resolved = resolved(item)
        var query = [URLQueryItem(name: "title", value: item.title)]
        if let id = resolved.tmdbId, let type = resolved.mediaType {
            query = [.init(name: "type", value: type), .init(name: "id", value: String(id))]
        }
        if let result: Details = try? await api.request("api/details", query: query), !Task.isCancelled {
            details[item.title] = result
            cache.store(result, for: item.title)
        }
    }
    func loadLibrary(api: TorrentTubeAPI) async {
        guard !libraryLoading else { return }
        libraryLoading = true
        defer { libraryLoading = false }
        do {
            // Everything in the category folders; an older server only knows its finished torrents.
            if let result: LibraryResponse = try? await api.request("api/library") {
                library = result.items
                libraryMatchedByServer = result.metadataPending != nil
                libraryPending = result.metadataPending ?? 0
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
