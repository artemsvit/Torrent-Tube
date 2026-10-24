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
            item.metadataLanguage = title.metadataLanguage
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
        var matches = words.isEmpty ? [] : library.filter { item in
            let names = [item.title, item.displayTitle] + (item.releases ?? []).map(\.title)
            let text = Self.normalized(names.joined(separator: " "))
            return words.allSatisfy { text.contains($0) }
        }
        var remaining: [MediaItem] = []
        // Only inspect possible matches, rather than scanning the library for every result.
        // Retain the original order when several local copies match.
        let keys = torrents.isEmpty ? [] : library.map(Key.init)
        var sources: [PlaybackSource: [Int]] = [:]
        var identities: [Identity: [Int]] = [:]
        var names: [DatedTitle: [Int]] = [:]
        if !torrents.isEmpty {
            for (index, item) in library.enumerated() {
                if item.source.isPlayable { sources[item.source, default: []].append(index) }
                if let id = item.tmdbId, let type = item.mediaType {
                    identities[Identity(id: id, type: type), default: []].append(index)
                }
                if let year = keys[index].year {
                    for title in keys[index].titles {
                        names[DatedTitle(year: year, title: title), default: []].append(index)
                    }
                }
            }
        }
        var matchedIDs = Set(matches.map(\.id))
        for torrent in torrents {
            let key = Key(torrent)
            var candidates = Set(sources[torrent.source] ?? [])
            if let id = torrent.tmdbId, let type = torrent.mediaType {
                candidates.formUnion(identities[Identity(id: id, type: type)] ?? [])
            }
            if let year = key.year {
                for title in key.titles {
                    candidates.formUnion(names[DatedTitle(year: year, title: title)] ?? [])
                }
            }
            if let index = candidates.filter({ Self.sameTitle(library[$0], keys[$0], torrent, key) }).min() {
                let local = library[index]
                if matchedIDs.insert(local.id).inserted { matches.append(local) }
            } else { remaining.append(torrent) }
        }
        self.library = matches
        self.torrents = remaining
    }

    static func sameTitle(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        // Known sources and IDs need no title normalization or year parsing.
        if let match = identityMatch(lhs, rhs) { return match }
        return sameTitle(lhs, Key(lhs), rhs, Key(rhs))
    }

    private struct Identity: Hashable { let id: Int; let type: String }
    private struct DatedTitle: Hashable { let year: String; let title: String }

    private struct Key {
        let year: String?
        let titles: Set<String>
        init(_ item: MediaItem) {
            year = LibrarySearchResults.year(item.title)
            titles = Set([item.title, item.displayTitle].map(LibrarySearchResults.titleKey).filter { !$0.isEmpty })
        }
    }

    private static func identityMatch(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool? {
        if lhs.source.isPlayable && lhs.source == rhs.source { return true }
        if let x = lhs.tmdbId, let y = rhs.tmdbId {
            // IDs can be shared by a movie and a TV series.
            return x == y && lhs.mediaType != nil && lhs.mediaType == rhs.mediaType
        }
        if let x = lhs.mediaType, let y = rhs.mediaType, x != y { return false }
        return nil
    }

    private static func sameTitle(_ lhs: MediaItem, _ a: Key, _ rhs: MediaItem, _ b: Key) -> Bool {
        if let match = identityMatch(lhs, rhs) { return match }
        // Without a reliable ID, require a year on both sides. Do not hide remakes
        // or guess that an unmatched title is the same film.
        guard let year = a.year, year == b.year else { return false }
        return !a.titles.isDisjoint(with: b.titles)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// The first standalone 19xx/20xx in the title, without a regex.
    private static func yearRange(_ title: String) -> Range<String.Index>? {
        let chars = Array(title.indices)
        var i = 0
        while i + 4 <= chars.count {
            let start = chars[i]
            let end = i + 4 < chars.count ? chars[i + 4] : title.endIndex
            let word = title[start..<end]
            let digits = word.allSatisfy { $0.isASCII && $0.isNumber }
            let prefix = word.hasPrefix("19") || word.hasPrefix("20")
            let leftOK = i == 0 || !isWordChar(title[chars[i - 1]])
            let rightOK = i + 4 >= chars.count || !isWordChar(title[chars[i + 4]])
            if digits && prefix && leftOK && rightOK { return start..<end }
            i += 1
        }
        return nil
    }
    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
    private static func year(_ title: String) -> String? {
        yearRange(title).map { String(title[$0]) }
    }
    private static func titleKey(_ title: String) -> String {
        let text = yearRange(title).map { String(title[..<$0.lowerBound]) } ?? title
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
