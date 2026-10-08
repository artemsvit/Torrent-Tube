import Foundation

struct EpisodeIdentity: Equatable {
    let season: Int
    let episode: Int
    /// Numbered files need a season from their own folder, never the selected UI season.
    static func parse(name: String, path: String?) -> EpisodeIdentity? {
        if let explicit = parse(name) { return explicit }
        guard let path else { return nil }
        let folders = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").dropLast()
        let seasonPatterns = [#"(?i)(?:^|[^\p{L}\d])(?:season|сезон|s)[ ._-]*(\d{1,2})(?!\d)"#,
                              #"(?i)(?:^|[^\p{L}\d])(\d{1,2})[ ._-]+(?:season|сезон)(?:$|[^\p{L}])"#]
        guard let season = folders.reversed().lazy.compactMap({ folder in
            seasonPatterns.lazy.compactMap { number(in: String(folder), pattern: $0) }.first
        }).first,
              let episode = number(in: name, pattern: #"(?i)^(?:(?:episode|ep|e)[ ._-]*)?(\d{1,3})(?=[ ._-])"#),
              episode > 0 else { return nil }
        // Do not turn combined episodes into a single-episode match.
        guard name.range(of: #"(?i)^(?:(?:episode|ep|e)[ ._-]*)?\d{1,3}[ ._]*[-+&][ ._]*(?:e)?\d{1,3}(?!\d)"#, options: .regularExpression) == nil,
              name.range(of: #"(?i)e\d{1,3}[ ._-]*e\d{1,3}"#, options: .regularExpression) == nil else { return nil }
        return EpisodeIdentity(season: season, episode: episode)
    }

    private static func number(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    static func parse(_ name: String) -> EpisodeIdentity? {
        // Multi-episode files require an explicit choice instead of an assumed match.
        if name.range(of: #"(?i)e\d{1,3}[ ._-]*e\d{1,3}"#, options: .regularExpression) != nil { return nil }
        for pattern in [#"(?i)(?:^|[^a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?!\d)"#, #"(?i)(?:^|[^a-z0-9])(\d{1,2})x(\d{1,3})(?!\d)"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let seasonRange = Range(match.range(at: 1), in: name), let episodeRange = Range(match.range(at: 2), in: name),
                  let season = Int(name[seasonRange]), let episode = Int(name[episodeRange]) else { continue }
            return EpisodeIdentity(season: season, episode: episode)
        }
        return nil
    }
}
