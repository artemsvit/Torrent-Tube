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

    /// A second number only counts as the end of a range just after the first
    /// ("01-02"), never a resolution or a year ("S01E01 - 720p").
    private static func range(_ first: Int, _ last: Int?) -> Int? {
        guard let last, last > first, last - first <= 4 else { return nil }
        return last
    }

    /// Numbered files need a season from their own folder, never the selected UI season.
    static func parse(name: String, path: String?) -> EpisodeIdentity? {
        if let explicit = parse(name) { return explicit }
        guard let path else { return nil }
        let folders = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").dropLast()
        let seasonPatterns = [#"(?i)(?:^|[^\p{L}\d])(?:season|сезон|s)[ ._-]*(\d{1,2})(?!\d)"#,
                              #"(?i)(?:^|[^\p{L}\d])(\d{1,2})[ ._-]+(?:season|сезон)(?:$|[^\p{L}])"#]
        guard let season = folders.reversed().lazy.compactMap({ folder in
            seasonPatterns.lazy.compactMap { numbers(in: String(folder), pattern: $0).first ?? nil }.first
        }).first else { return nil }
        // "03 Title", "E03 Title", or two episodes in one: "03-04 Title", "E03-E04 Title".
        let found = numbers(in: name, pattern: #"(?i)^(?:(?:episode|ep|e)[ ._-]*)?(\d{1,3})(?:[ ._]*[-+&][ ._]*e?(\d{1,3}))?(?=[ ._-]|$)"#)
        guard let episode = found.first ?? nil, episode > 0 else { return nil }
        let second = found.count > 1 ? found[1] : nil
        if second != nil, range(episode, second) == nil { return nil }  // not a sensible range: do not guess
        return EpisodeIdentity(season: season, episode: episode, lastEpisode: range(episode, second))
    }

    /// The capture groups of the first match, nil where a group did not take part.
    private static func numbers(in text: String, pattern: String) -> [Int?] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return [] }
        return (1..<match.numberOfRanges).map { group in
            Range(match.range(at: group), in: text).flatMap { Int(text[$0]) }
        }
    }

    static func parse(_ name: String) -> EpisodeIdentity? {
        // S01E01, S01E01-E02, S01E01E02, S01E01-02
        let sxe = numbers(in: name, pattern: #"(?i)(?:^|[^a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?:[ ._]*-?[ ._]*e?(\d{1,3}))?(?!\d)"#)
        if sxe.count == 3, let season = sxe[0], let episode = sxe[1] {
            if let second = sxe[2], range(episode, second) == nil {
                // "S01E01 720p" style noise after the episode: the single episode only.
                return EpisodeIdentity(season: season, episode: episode)
            }
            return EpisodeIdentity(season: season, episode: episode, lastEpisode: range(episode, sxe[2]))
        }
        // 1x04
        let x = numbers(in: name, pattern: #"(?i)(?:^|[^a-z0-9])(\d{1,2})x(\d{1,3})(?!\d)"#)
        if x.count == 2, let season = x[0], let episode = x[1] { return EpisodeIdentity(season: season, episode: episode) }
        // "1-1-2 Name": season, then the first and last episode.
        let dashed = numbers(in: name, pattern: #"^(\d{1,2})-(\d{1,3})-(\d{1,3})(?=[ ._])"#)
        if dashed.count == 3, let season = dashed[0], let episode = dashed[1], let last = range(episode, dashed[2]) {
            return EpisodeIdentity(season: season, episode: episode, lastEpisode: last)
        }
        return nil
    }
}
