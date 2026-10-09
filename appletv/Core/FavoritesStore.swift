import Foundation
import Observation

/// A title kept with the heart: enough to show its card and play it again,
/// stored on this device for the server it came from.
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

@MainActor @Observable
final class FavoritesStore {
    private(set) var entries: [FavoriteEntry] {
        didSet { rebuildIndex() }
    }
    private var identifiers: Set<String> = []
    private var byServer: [String: [FavoriteEntry]] = [:]
    private static let storageKey = "favorites"
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([FavoriteEntry].self, from: $0) } ?? []
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
        return identifiers.contains(key)
    }
    /// Newest first.
    func entries(server: URL) -> [FavoriteEntry] {
        byServer[server.absoluteString] ?? []
    }
    /// `item` should be the resolved one (clean title, poster), `details`
    /// what is known about it - together they decide its tab.
    func toggle(_ item: MediaItem, details: Details?, server: URL) {
        let key = Self.key(server: server, item: item)
        if identifiers.contains(key) {
            entries.removeAll { $0.id == key }
        } else {
            let type = details?.mediaType ?? item.mediaType
            let kind = details?.kind == "Cartoon" ? "cartoon" : (type == "tv" ? "tv" : "movie")
            entries.append(FavoriteEntry(id: key, server: server.absoluteString, title: item.title,
                                         cleanTitle: details?.title ?? item.cleanTitle, poster: item.poster,
                                         tmdbId: details?.tmdbId ?? item.tmdbId, mediaType: type, kind: kind,
                                         magnet: item.magnet, downloadLink: item.downloadLink,
                                         sourceOverride: item.sourceOverride, addedAt: Date()))
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.storageKey) }
    }
}
