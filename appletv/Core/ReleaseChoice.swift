import Foundation

/// Choosing a release for a series: which search results are its releases,
/// and the one picked before, so its other episodes play at once.
enum ReleaseChoice {
    /// Only releases named after the title (anything else the search matched,
    /// like an album, goes); for an episode, those with its season first.
    static func rank(_ results: [MediaItem], names: [String], season: Int?) -> [MediaItem] {
        func plain(_ text: String) -> String {
            text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let wanted = names.map(plain).filter { !$0.isEmpty }
        let named = results.filter { result in let title = " " + plain(result.title) + " "; return wanted.contains { title.contains(" " + $0 + " ") } }
        let kept = named.isEmpty ? results : named
        guard let season else { return kept }
        func hasSeason(_ title: String) -> Bool {
            let text = title.lowercased()
            return text.range(of: String(format: "s%02d", season)) != nil || text.range(of: "s\(season)\\b", options: .regularExpression) != nil
                || text.range(of: "сезон \(season)") != nil || text.range(of: "season \(season)") != nil
        }
        return kept.filter { hasSeason($0.title) } + kept.filter { !hasSeason($0.title) }
    }

    static func remembered(for tmdbID: Int?) -> PlaybackSource? {
        guard let tmdbID, let data = UserDefaults.standard.data(forKey: "release-\(tmdbID)") else { return nil }
        return try? JSONDecoder().decode(PlaybackSource.self, from: data)
    }
    static func remember(_ source: PlaybackSource?, for tmdbID: Int?) {
        guard let tmdbID else { return }
        var source = source; source?.file = nil
        UserDefaults.standard.set(source.flatMap { try? JSONEncoder().encode($0) }, forKey: "release-\(tmdbID)")
    }

    /// Search by the Ukrainian and the original title, then rank.
    static func search(title: String, original: String?, season: Int?, api: TorrentTubeAPI) async throws -> [Release] {
        var names = [title]
        if let original, !original.isEmpty, original.lowercased() != title.lowercased() { names.append(original) }
        var found: [MediaItem] = []
        for name in names {
            let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: name), .init(name: "enrich", value: "0")])
            try Task.checkCancellation()
            found += result.results.filter { new in !found.contains { $0.id == new.id } }
        }
        return rank(found, names: names, season: season)
            .map { Release(title: $0.title, magnet: $0.magnet, downloadLink: $0.downloadLink, sizeLabel: $0.sizeLabel, seeders: $0.seeders) }
    }
}
