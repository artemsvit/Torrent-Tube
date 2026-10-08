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
