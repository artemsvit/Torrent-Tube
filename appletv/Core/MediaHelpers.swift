import Foundation

func libraryItem(_ title: LibraryTitle) -> MediaItem {
    // Several copies on the server: "Choose version" lists them (folder, files, size).
    let versions: [Release]? = title.versions.count > 1 ? title.versions.map { version in
        let size = ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file)
        let detail = version.files > 1 ? L("%ld files", version.files) + " · " + size : size
        return Release(title: "\(version.category) / \(version.name)", magnet: nil, downloadLink: nil,
                       sizeLabel: detail, seeders: nil, path: version.id)
    } : nil
    var item = MediaItem(title: title.name, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: versions)
    item.sourceOverride = title.source
    if !title.isTorrent {
        item.mediaType = title.kind == "tv" ? "tv" : "movie"
        item.cleanTitle = title.title
        // The server's match - used unless "Posters and details" is off.
        if CatalogStore.libraryMetadataEnabled, title.tmdbId != nil {
            item.cleanTitle = title.displayTitle ?? title.title
            item.poster = title.poster; item.rating = title.rating; item.overview = title.overview
            item.tmdbId = title.tmdbId; item.mediaType = title.mediaType ?? item.mediaType
        }
    }
    return item
}

func higherResolution(_ url: String, backdrop: Bool) -> String {
    guard url.hasPrefix("https://image.tmdb.org/t/p/") else { return url }
    return url.replacingOccurrences(of: "/w200/", with: backdrop ? "/w1280/" : "/w500/")
        .replacingOccurrences(of: "/w342/", with: backdrop ? "/w1280/" : "/w500/")
}

/// Shared search composition. A local copy wins over the same catalog title.
struct LibrarySearchResults {
    let library: [MediaItem]
    let torrents: [MediaItem]

    init(query: String, library: [MediaItem], torrents: [MediaItem]) {
        let words = Self.normalized(query).split(separator: " ")
        var matches = library.filter { item in
            let names = [item.title, item.displayTitle] + (item.releases ?? []).map(\.title)
            let text = Self.normalized(names.joined(separator: " "))
            return !words.isEmpty && words.allSatisfy { text.contains($0) }
        }
        var remaining: [MediaItem] = []
        for torrent in torrents {
            if let local = library.first(where: { Self.sameTitle($0, torrent) }) {
                if !matches.contains(where: { $0.id == local.id }) { matches.append(local) }
            } else { remaining.append(torrent) }
        }
        self.library = matches
        self.torrents = remaining
    }

    static func sameTitle(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        if lhs.source.isPlayable && lhs.source == rhs.source { return true }
        if let a = lhs.tmdbId, let b = rhs.tmdbId {
            // IDs can be shared by a movie and a TV series.
            return a == b && lhs.mediaType != nil && lhs.mediaType == rhs.mediaType
        }
        if let a = lhs.mediaType, let b = rhs.mediaType, a != b { return false }
        // Without a reliable ID, require a year on both sides. Do not hide remakes
        // or guess that an unmatched title is the same film.
        guard let year = Self.year(lhs.title), year == Self.year(rhs.title) else { return false }
        let a = Set([lhs.title, lhs.displayTitle].map(Self.titleKey).filter { !$0.isEmpty })
        let b = Set([rhs.title, rhs.displayTitle].map(Self.titleKey).filter { !$0.isEmpty })
        return !a.isDisjoint(with: b)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func year(_ title: String) -> String? {
        guard let range = title.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) else { return nil }
        return String(title[range])
    }
    private static func titleKey(_ title: String) -> String {
        let text = title.replacingOccurrences(of: #"\b(?:19|20)\d{2}\b.*$"#, with: "", options: .regularExpression)
        return normalized(text)
    }
}

/// The banner's small lines, the same on every platform (in the way of the
/// Apple TV app): "Фільм · Драма · Комедія", "2023 · 2 год 19 хв", and the
/// credits beside the buttons.
enum BannerText {
    static func subtitle(kind: String?, details: Details?) -> String {
        ([kind].compactMap { $0 } + (details?.genres ?? []).prefix(2)).joined(separator: " · ")
    }
    static func facts(details: Details?) -> String {
        var list: [String] = []
        if let year = details?.year, !year.isEmpty { list.append(year) }
        if let runtime = details?.runtime, runtime > 0 { list.append(runtime >= 60 ? L("%ld h %ld min", runtime / 60, runtime % 60) : L("%ld min", runtime)) }
        return list.joined(separator: " · ")
    }
    /// "Режисер …" or "Автор …", then "У ролях …" (three names).
    static func credits(details: Details?) -> [(label: String, names: String)] {
        let people = details?.people ?? []
        let jobs: Set<String> = ["Director", "Creator", "Writer", "Screenplay", "Producer", "Novel", "Author"]
        var lines: [(String, String)] = []
        let cast = people.filter { !jobs.contains($0.role ?? "") }.prefix(3).map(\.name)
        if !cast.isEmpty { lines.append((L("Starring"), cast.joined(separator: ", "))) }
        for job in ["Director", "Creator"] {
            let names = people.filter { $0.role == job }.prefix(2).map(\.name)
            if !names.isEmpty { lines.append((L(job), names.joined(separator: ", "))); break }
        }
        return lines
    }
}
