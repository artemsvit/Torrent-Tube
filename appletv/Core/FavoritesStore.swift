import Foundation
import Observation

/// A title kept with the heart: enough to show its card and play it again.
/// The server keeps the list for every app and the web page; this device
/// keeps a copy for each server, so the tab still shows offline.
struct FavoriteEntry: Codable, Identifiable {
    let id: String
    let server: String
    let title: String
    var cleanTitle: String?
    var poster: String?
    var tmdbId: Int?
    var mediaType: String?
    /// "movie", "tv" or "cartoon" - the Favorites tabs.
    var kind: String
    let magnet: String?
    let downloadLink: String?
    var sourceOverride: PlaybackSource?
    let addedAt: Date
    var item: MediaItem {
        var item = MediaItem(title: title, magnet: magnet, downloadLink: downloadLink, sizeLabel: nil, seeders: nil, releases: nil)
        item.cleanTitle = cleanTitle; item.poster = poster; item.tmdbId = tmdbId; item.mediaType = mediaType
        item.sourceOverride = sourceOverride
        return item
    }
}

/// One favorite as the server sends it (GET/POST /api/favorites). Its id is
/// the item's own id, with no server address in front.
struct RemoteFavorite: Codable, Sendable {
    let id: String
    let title: String
    var cleanTitle: String?
    var poster: String?
    var tmdbId: Int?
    var mediaType: String?
    var kind: String?
    var magnet: String?
    var downloadLink: String?
    var sourceOverride: PlaybackSource?
    var addedAt: Double?
}
private struct RemoteFavorites: Codable { let items: [RemoteFavorite] }
private struct RemovedFavorites: Encodable { let ids: [String] }

@MainActor @Observable
final class FavoritesStore {
    private(set) var entries: [FavoriteEntry] {
        didSet { rebuildIndex() }
    }
    private var identifiers: Set<String> = []
    private var byServer: [String: [FavoriteEntry]] = [:]
    private static let storageKey = "favorites"
    /// Changes not on the server yet (offline, or an older server), by entry id.
    private static let addsKey = "favorites.pendingAdds", removalsKey = "favorites.pendingRemovals"
    /// Set once the list kept only on this device is queued for upload.
    private static let migratedKey = "favorites.migrated"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingAdds: Set<String>
    @ObservationIgnored private var pendingRemovals: Set<String>
    @ObservationIgnored private var api: TorrentTubeAPI?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([FavoriteEntry].self, from: $0) } ?? []
        pendingAdds = Set(defaults.stringArray(forKey: Self.addsKey) ?? [])
        pendingRemovals = Set(defaults.stringArray(forKey: Self.removalsKey) ?? [])
        if !defaults.bool(forKey: Self.migratedKey) {
            // Favorites from before the server kept them: upload each once.
            pendingAdds.formUnion(entries.map(\.id))
            defaults.set(true, forKey: Self.migratedKey)
            savePending()
        }
        rebuildIndex()
    }
    private func rebuildIndex() {
        identifiers = Set(entries.map(\.id))
        byServer = Dictionary(grouping: entries, by: \.server)
            .mapValues { $0.sorted { $0.addedAt > $1.addedAt } }
    }
    static func key(server: URL, item: MediaItem) -> String { "\(server.absoluteString)|\(item.id)" }
    func contains(_ item: MediaItem, server: URL) -> Bool {
        let key = Self.key(server: server, item: item)
        return identifiers.contains(key) || entries(server: server).contains { sameTitle($0, item) }
    }
    private func sameTitle(_ entry: FavoriteEntry, _ item: MediaItem) -> Bool {
        guard let id = item.tmdbId, id > 0, let type = item.mediaType,
              type == "movie" || type == "tv" else { return false }
        return entry.tmdbId == id && entry.mediaType == type
    }
    /// Newest first.
    func entries(server: URL) -> [FavoriteEntry] {
        byServer[server.absoluteString] ?? []
    }
    /// `item` should be the resolved one (clean title, poster), `details`
    /// what is known about it - together they decide its tab.
    func toggle(_ item: MediaItem, details: Details?, server: URL) {
        let key = Self.key(server: server, item: item)
        var resolved = item
        resolved.tmdbId = details?.tmdbId ?? item.tmdbId
        resolved.mediaType = details?.mediaType ?? item.mediaType
        let matches = Set(entries(server: server).filter { $0.id == key || sameTitle($0, resolved) }.map(\.id))
        if !matches.isEmpty {
            entries.removeAll { matches.contains($0.id) }
            pendingAdds.subtract(matches); pendingRemovals.formUnion(matches)
        } else {
            let type = details?.mediaType ?? item.mediaType
            let kind = details?.kind == "Cartoon" ? "cartoon" : (type == "tv" ? "tv" : "movie")
            entries.append(FavoriteEntry(id: key, server: server.absoluteString, title: item.title,
                                         cleanTitle: details?.title ?? item.cleanTitle, poster: item.poster,
                                         tmdbId: details?.tmdbId ?? item.tmdbId, mediaType: type, kind: kind,
                                         magnet: item.magnet, downloadLink: item.downloadLink,
                                         sourceOverride: item.sourceOverride, addedAt: Date()))
            pendingRemovals.remove(key); pendingAdds.insert(key)
        }
        saveEntries(); savePending()
        if api?.baseURL == server { sync() }
    }

    // MARK: Server

    /// Uses this server's list from now on, when it keeps one (older servers
    /// do not: then favorites stay on this device, as before).
    func connect(_ api: TorrentTubeAPI, config: ServerConfig) {
        self.api = config.capabilities?.favorites == true ? api : nil
        sync()
    }
    /// Sends changes made here, then takes the server's list. Runs one at a time.
    @discardableResult
    func sync() -> Task<Void, Never> {
        let previous = syncTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.performSync()
        }
        syncTask = task
        return task
    }
    private func performSync() async {
        guard let api else { return }
        let server = api.baseURL.absoluteString
        let prefix = server + "|"
        func remoteID(_ key: String) -> String { String(key.dropFirst(prefix.count)) }
        let adds = entries.filter { $0.server == server && pendingAdds.contains($0.id) }
        let removals = pendingRemovals.filter { $0.hasPrefix(prefix) }
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        do {
            if !adds.isEmpty {
                let body = RemoteFavorites(items: adds.map { entry in
                    RemoteFavorite(id: remoteID(entry.id), title: entry.title, cleanTitle: entry.cleanTitle, poster: entry.poster,
                                   tmdbId: entry.tmdbId, mediaType: entry.mediaType, kind: entry.kind, magnet: entry.magnet,
                                   downloadLink: entry.downloadLink, sourceOverride: entry.sourceOverride,
                                   addedAt: entry.addedAt.timeIntervalSince1970)
                })
                let _: RemoteFavorites = try await api.request("api/favorites", method: "POST", body: encoder.encode(body))
                pendingAdds.subtract(adds.map(\.id))
            }
            if !removals.isEmpty {
                let _: RemoteFavorites = try await api.request("api/favorites/remove", method: "POST",
                                                               body: encoder.encode(RemovedFavorites(ids: removals.map(remoteID))))
                pendingRemovals.subtract(removals)
            }
            savePending()
            let list: RemoteFavorites = try await api.request("api/favorites")
            // Keep what changed here while the request ran; it goes up next time.
            let local = entries.filter { $0.server == server && pendingAdds.contains($0.id) }
            let localIDs = Set(local.map(\.id))
            let fromServer = list.items.compactMap { remote -> FavoriteEntry? in
                let key = prefix + remote.id
                guard !pendingRemovals.contains(key), !localIDs.contains(key) else { return nil }
                return FavoriteEntry(id: key, server: server, title: remote.title, cleanTitle: remote.cleanTitle,
                                     poster: remote.poster, tmdbId: remote.tmdbId, mediaType: remote.mediaType,
                                     kind: remote.kind ?? "movie", magnet: remote.magnet, downloadLink: remote.downloadLink,
                                     sourceOverride: remote.sourceOverride,
                                     addedAt: Date(timeIntervalSince1970: remote.addedAt ?? 0))
            }
            entries = entries.filter { $0.server != server } + local + fromServer
            saveEntries()
        } catch {
            // Offline or a server error: the changes stay queued for the next sync.
            savePending()
        }
    }
    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.storageKey) }
    }
    private func savePending() {
        defaults.set(Array(pendingAdds), forKey: Self.addsKey)
        defaults.set(Array(pendingRemovals), forKey: Self.removalsKey)
    }
}
