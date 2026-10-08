import Foundation

struct EpisodeIdentity: Equatable {
    let season: Int
    let episode: Int
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
