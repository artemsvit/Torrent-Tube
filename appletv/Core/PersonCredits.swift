import Foundation

/// A tap on a cast photo: which person to open.
struct PersonRoute: Hashable, Sendable {
    let id: Int
    let name: String
    let photo: String?
}

/// What `/api/person` sends: the person and every film and show they are in, most popular first.
struct PersonCredits: Decodable, Sendable {
    let id: Int
    let name: String
    let photo: String?
    let department: String?
    let titles: [Title]
    struct Title: Decodable, Hashable, Sendable {
        let tmdbId: Int
        let mediaType: String
        let title: String
        let year: String?
        let poster: String?
        let rating: Double?
    }

    /// The titles as catalog items, so a card opens the same details page as anywhere else.
    var items: [MediaItem] {
        titles.map { credit in
            var item = MediaItem(title: credit.title, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
            item.cleanTitle = credit.title; item.poster = credit.poster; item.tmdbId = credit.tmdbId; item.mediaType = credit.mediaType
            return item
        }
    }
}

extension Details.Person {
    var route: PersonRoute? { id.map { PersonRoute(id: $0, name: name, photo: photo) } }
}
