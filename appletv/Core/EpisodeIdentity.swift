import Foundation

/// A file's season and episode. A file with two episodes in it (Bluey's
/// "1-1-2 Name.mp4", "S01E01-E02") covers `episode...lastEpisode`.
struct EpisodeIdentity: Equatable {
    let season: Int
    let episode: Int
    let lastEpisode: Int

    init(season: Int, episode: Int, lastEpisode: Int? = nil) {
        self.season = season
        self.episode = episode
        self.lastEpisode = max(episode, lastEpisode ?? episode)
    }

    var isRange: Bool { lastEpisode > episode }

    func covers(season: Int, episode: Int) -> Bool {
        self.season == season && (self.episode...lastEpisode).contains(episode)
    }

    /// "Season 1 · Episode 3", or "Season 1 · Episodes 1–2" for a double file.
    var label: String {
        isRange ? L("Season %ld · Episodes %ld–%ld", season, episode, lastEpisode) : L("Season %ld · Episode %ld", season, episode)
    }

    // The same rules as the server's episodes.py - the server's reading comes
    // with each file; this one is for older servers and release titles.
    private static let e = "(?:ep|e|е)"          // Latin e, "ep", Cyrillic е
    private static let s = "[sс]"                // Latin s, Cyrillic с
    private static let rangePart = #"(?:[ ._]*-[ ._]*"# + e + "?|" + e + #")(\d{1,3})"#
    private static let sxe = #"(?i)(?:^|[^a-zа-яіїєґ0-9])"# + s + #"0*(\d{1,2})[ ._-]*"# + e + #"[ ._-]*(\d{1,3})(?:"# + rangePart + #")?(?!\d)"#
    private static let words = #"(?i)season[ ._-]*(\d{1,2})[ ._-]*episode[ ._-]*(\d{1,3})(?!\d)"#
    private static let nxm = #"(?i)(?:^|[^a-z0-9])(\d{1,2})x(\d{1,3})(?!\d)"#
    private static let dashed = #"^(\d{1,2})-(\d{1,3})-(\d{1,3})(?=[ ._])"#
    private static let seasonFolders = [#"(?i)(?:^|[^\w])(?:season|сезон|"# + s + #")[ ._-]*0*(\d{1,2})(?!\d)"#,
                                        #"(?i)(?:^|[^\w])(\d{1,2})[ ._-]+(?:season|сезон)(?:$|[^\w])"#]
    private static let leading = #"(?i)^(?:(?:episode|"# + e + #")[ ._-]*)?(\d{1,3})(?:[ ._]*[-+&][ ._]*"# + e + #"?(\d{1,3}))?(?=[ ._-]|$)"#
    private static let episodeWord = #"(?i)(?:^|[^\w])(?:episode|серія|серия|епізод|эпизод)[ ._-]*(\d{1,3})(?!\d)"#

    /// The end of a range only when it is just after the first episode -
    /// never a resolution, a year or noise ("S01E05 4K").
    private static func last(_ first: Int, _ second: Int?) -> Int? {
        guard let second else { return first }
        return second > first && second <= first + 4 ? second : nil
    }

    private static func make(_ season: Int, _ episode: Int, _ last: Int? = nil) -> EpisodeIdentity? {
        episode > 0 ? EpisodeIdentity(season: season, episode: episode, lastEpisode: last) : nil
    }

    /// The capture groups of the first match, nil where a group did not take part.
    private static func numbers(in text: String, pattern: String) -> [Int?] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return [] }
        return (1..<match.numberOfRanges).map { group in
            Range(match.range(at: group), in: text).flatMap { Int(text[$0]) }
        }
    }

    /// Season and episode from the file name alone.
    static func parse(_ name: String) -> EpisodeIdentity? {
        let found = numbers(in: name, pattern: sxe)
        if found.count == 3, let season = found[0], let episode = found[1] {
            return make(season, episode, last(episode, found[2]))  // not a sensible range: the first episode only
        }
        for pattern in [words, nxm] {
            let found = numbers(in: name, pattern: pattern)
            if found.count == 2, let season = found[0], let episode = found[1] { return make(season, episode) }
        }
        let dash = numbers(in: name, pattern: dashed)
        if dash.count == 3, let season = dash[0], let episode = dash[1], let end = last(episode, dash[2]), end > episode {
            return make(season, episode, end)
        }
        return nil
    }

    /// With the folders above the file, where the season may be ("Season 1",
    /// "Сезон 1", "Show (Сезон 2)"). Numbered files never take the selected UI season.
    static func parse(name: String, path: String?) -> EpisodeIdentity? {
        if let explicit = parse(name) { return explicit }
        let folders = (path ?? "").replacingOccurrences(of: "\\", with: "/").split(separator: "/").dropLast()
        let season = folders.reversed().lazy.compactMap { folder in
            seasonFolders.lazy.compactMap { numbers(in: String(folder), pattern: $0).first ?? nil }.first
        }.first
        if let season {
            let found = numbers(in: name, pattern: leading)
            if found.count == 2, let episode = found[0] {
                guard let second = found[1] else { return make(season, episode) }
                guard let end = last(episode, second) else { return nil }  // "03-10": do not guess
                return make(season, episode, end)
            }
        }
        let word = numbers(in: name, pattern: episodeWord)
        if let episode = word.first ?? nil { return make(season ?? 1, episode) }
        return nil
    }
}
