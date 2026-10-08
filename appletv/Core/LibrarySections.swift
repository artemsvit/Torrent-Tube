import Foundation

/// The Library screen's chips, the same on every device: one per type of
/// title on the server (with its count), then Favorites.
enum LibrarySections {
    static let kinds = [("movie", "Movies"), ("tv", "TV Shows"), ("cartoon", "Cartoons")]
    static func chips(_ library: [LibraryTitle], favorites: Int) -> [(String, String)] {
        kinds.map { kind, label in
            let count = library.filter { $0.kind == kind }.count
            return (kind, count > 0 ? "\(L(label)) · \(count)" : label)
        } + [("favorites", favorites > 0 ? "\(L("Favorites")) · \(favorites)" : "Favorites")]
    }
    /// The first type the server has, else Favorites.
    static func defaultSection(_ library: [LibraryTitle]) -> String {
        kinds.first { kind, _ in library.contains { $0.kind == kind } }?.0 ?? "favorites"
    }
}

/// Keep the hero varied without repeating a film from multiple catalog shelves.
enum HomeFeaturedSelection {
    static let limit = 10
    static func pick(new: [MediaItem], movies: [MediaItem], tv: [MediaItem], cartoons: [MediaItem]) -> [MediaItem] {
        var result: [MediaItem] = []
        func append(_ item: MediaItem?) {
            guard let item, result.count < limit,
                  !result.contains(where: { LibrarySearchResults.sameTitle($0, item) || $0.id == item.id }) else { return }
            result.append(item)
        }
        func newest(in feed: [MediaItem]) -> MediaItem? {
            let ids = Set(feed.map(\.id))
            let identities = Set(feed.compactMap { item -> String? in
                guard let id = item.tmdbId, let type = item.mediaType else { return nil }
                return "\(type):\(id)"
            })
            let unmatched = feed.filter { $0.tmdbId == nil || $0.mediaType == nil }
            return new.first { recent in
                if ids.contains(recent.id) { return true }
                if let id = recent.tmdbId, let type = recent.mediaType {
                    if identities.contains("\(type):\(id)") { return true }
                    return unmatched.contains { LibrarySearchResults.sameTitle(recent, $0) }
                }
                return feed.contains { LibrarySearchResults.sameTitle(recent, $0) }
            } ?? feed.first
        }
        append(new.first ?? movies.first)
        append(newest(in: movies))
        append(newest(in: tv))
        append(newest(in: cartoons))
        for feed in [new, movies, tv, cartoons] {
            for item in feed {
                append(item)
                if result.count == limit { return result }
            }
        }
        return result
    }
}
