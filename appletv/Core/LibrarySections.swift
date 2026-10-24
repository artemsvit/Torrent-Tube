import Foundation

/// Films of one TMDB collection on the server - two or more, never shows -
/// in release order: Harry Potter 1, 2, 3.
struct LibraryCollection: Identifiable, Hashable {
    let info: TitleCollection
    let titles: [LibraryTitle]
    var id: Int { info.id }
    var name: String { info.name }
    var poster: String? { info.poster ?? titles.first?.poster }
    /// "3 films", or "3 of 8 films" when the series has more.
    var count: String {
        if let total = info.total, total > titles.count { return L("%ld of %ld films", titles.count, total) }
        return L("%ld films", titles.count)
    }
    /// "Part 2 · 2002" under each film.
    static func line(_ title: LibraryTitle) -> String {
        [title.collection?.part.map { L("Part %ld", $0) }, title.year].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The Library screen's chips, the same on every device: one per type of
/// title on the server (with its count), then Collections and Favorites.
enum LibrarySections {
    static let kinds = [("movie", "Movies"), ("tv", "TV Shows"), ("cartoon", "Cartoons")]
    static func chips(_ library: [LibraryTitle], favorites: Int) -> [(String, String)] {
        let collections = collections(library).count
        return kinds.map { kind, label in
            let count = library.filter { $0.kind == kind }.count
            return (kind, count > 0 ? "\(L(label)) · \(count)" : label)
        } + [("collections", collections > 0 ? "\(L("Collections")) · \(collections)" : "Collections"),
             ("favorites", favorites > 0 ? "\(L("Favorites")) · \(favorites)" : "Favorites")]
    }
    static func collections(_ library: [LibraryTitle]) -> [LibraryCollection] {
        let films = library.filter { $0.kind != "tv" && $0.mediaType == "movie" && $0.collection != nil }
        return Dictionary(grouping: films) { $0.collection!.id }.values.compactMap { titles -> LibraryCollection? in
            guard titles.count >= 2, let info = titles.first?.collection else { return nil }
            let ordered = titles.sorted {
                ($0.collection?.part ?? 99, $0.year ?? "9999") < ($1.collection?.part ?? 99, $1.year ?? "9999")
            }
            return LibraryCollection(info: info, titles: ordered)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
