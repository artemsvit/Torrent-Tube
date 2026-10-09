import Foundation

/// Choosing a release for a series: which search results are its releases,
/// and the one picked before, so its other episodes play at once.
enum ReleaseChoice {
    /// Only releases named after the title (anything else the search matched,
    /// like an album, goes); for an episode, those with its season first.
    static func rank(_ results: [MediaItem], names: [String], season: Int?, allowUnmatched: Bool = true) -> [MediaItem] {
        func plain(_ text: String) -> String {
            text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let wanted = names.map(plain).filter { !$0.isEmpty }
        let named = results.filter { result in let title = " " + plain(result.title) + " "; return wanted.contains { title.contains(" " + $0 + " ") } }
        let kept = named.isEmpty && allowUnmatched ? results : named
        guard let season else { return kept }
        func hasSeason(_ title: String) -> Bool {
            let text = title.lowercased()
            return text.range(of: String(format: "s%02d", season)) != nil || text.range(of: "s\(season)\\b", options: .regularExpression) != nil
                || text.range(of: "сезон \(season)") != nil || text.range(of: "season \(season)") != nil
        }
        return kept.filter { hasSeason($0.title) } + kept.filter { !hasSeason($0.title) }
    }

    /// A release chosen before, with its name (which tells its seasons).
    struct Saved: Codable { let title: String; let source: PlaybackSource }
    static func remembered(for tmdbID: Int?) -> Saved? {
        guard let tmdbID, let data = UserDefaults.standard.data(forKey: "release-v2-\(tmdbID)") else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }
    static func remember(_ source: PlaybackSource, title: String, for tmdbID: Int?) {
        guard let tmdbID else { return }
        var source = source; source.file = nil
        UserDefaults.standard.set(try? JSONEncoder().encode(Saved(title: title, source: source)), forKey: "release-v2-\(tmdbID)")
    }

    /// The seasons a release's name mentions ("S02", "Сезон 2", "Seasons 2-4");
    /// empty when it names none (often the whole series).
    static func seasons(in title: String) -> Set<Int> {
        let text = title.lowercased()
        var found = Set<Int>()
        func numbers(_ pattern: String) -> [[Int]] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
                (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            }
        }
        for range in numbers(#"(?:^|[^a-zа-яіїє0-9])s(\d{1,2})\s*[-–]\s*s?(\d{1,2})(?!\d)"#)
            + numbers(#"(?:seasons?|сезон[иі]?)\s*(\d{1,2})\s*[-–]\s*(\d{1,2})(?!\d)"#) where range.count == 2 && range[0] <= range[1] {
            found.formUnion(range[0]...range[1])
        }
        for single in numbers(#"(?:^|[^a-zа-яіїє0-9])s(\d{1,2})(?:e\d{1,3})?(?![\d])"#)
            + numbers(#"(?:season|сезон)\s*(\d{1,2})(?!\d)"#) + numbers(#"(\d{1,2})\s*(?:-?й\s*)?сезон"#) {
            if let season = single.first { found.insert(season) }
        }
        return found
    }
    static func covers(_ title: String, season: Int) -> Bool {
        let mentioned = seasons(in: title)
        return mentioned.isEmpty || mentioned.contains(season)
    }

    /// Where an episode plays from without asking: the library folder, else
    /// the release chosen before, else the torrent the page came from - when
    /// its name does not leave out that season. Nil: let the viewer choose.
    static func episodeSource(for item: MediaItem, tmdbID: Int?, season: Int) -> PlaybackSource? {
        if item.sourceOverride != nil { return item.source }
        if let saved = remembered(for: tmdbID), covers(saved.title, season: season) { return saved.source }
        if item.source.isPlayable, covers(item.title, season: season) { return item.source }
        return nil
    }

    /// Prefer a seeded season pack; never select a different season or episode.
    static func automaticRelease(_ releases: [Release], season: Int, episode: Int) -> Release? {
        releases.enumerated().filter { _, release in
            guard release.source.isPlayable, seasons(in: release.title).contains(season) else { return false }
            if let identity = EpisodeIdentity.parse(release.title) {
                return identity.covers(season: season, episode: episode)
            }
            return true
        }.sorted { lhs, rhs in
            let left = lhs.element.seeders ?? -1, right = rhs.element.seeders ?? -1
            return left == right ? lhs.offset < rhs.offset : left > right
        }.first?.element
    }

    static func resolveEpisodeSource(for item: MediaItem, title: String, original: String?, tmdbID: Int?,
                                     season: Int, episode: Int, api: TorrentTubeAPI) async throws -> PlaybackSource {
        // A library title: the folder (of all its copies) that really has this
        // episode - a folder named without a season is not proof it has them all.
        if item.sourceOverride?.path != nil {
            if let folder = try await libraryFolder(holding: season, episode: episode, in: libraryFolders(of: item), api: api) {
                return folder
            }
            // Not downloaded: stream it from a release, as for any title not in the library.
            do {
                return try await releaseSource(title: title, original: original, tmdbID: tmdbID, season: season, episode: episode, api: api)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw APIError(message: L("This episode is not in your library, and no release was found for it."))
            }
        }
        if let source = episodeSource(for: item, tmdbID: tmdbID, season: season) {
            // A remembered individual episode must not be reused for another episode.
            let sourceTitle = remembered(for: tmdbID).flatMap { $0.source == source ? $0.title : nil } ?? item.title
            if item.sourceOverride != nil || EpisodeIdentity.parse(sourceTitle).map({ $0.covers(season: season, episode: episode) }) != false { return source }
        }
        return try await releaseSource(title: title, original: original, tmdbID: tmdbID, season: season, episode: episode, api: api)
    }

    /// The release chosen before when it has this episode, else the best search result.
    private static func releaseSource(title: String, original: String?, tmdbID: Int?, season: Int, episode: Int,
                                      api: TorrentTubeAPI) async throws -> PlaybackSource {
        if let saved = remembered(for: tmdbID), covers(saved.title, season: season),
           EpisodeIdentity.parse(saved.title).map({ $0.covers(season: season, episode: episode) }) != false {
            return saved.source
        }
        let releases = try await search(title: title, original: original, season: season, api: api, allowUnmatched: false)
        try Task.checkCancellation()
        guard let release = automaticRelease(releases, season: season, episode: episode) else {
            throw APIError(message: L("No playable source was found for this episode."))
        }
        remember(release.source, title: release.title, for: tmdbID)
        return release.source
    }

    /// A library title's folders: the one it opens with first, then its other copies.
    static func libraryFolders(of item: MediaItem) -> [PlaybackSource] {
        var folders = [item.source]
        for source in item.librarySources where !folders.contains(source) { folders.append(source) }
        return folders
    }

    /// The first folder whose files hold the episode (the server reads each
    /// file's season and episode), or nil when none has it.
    static func libraryFolder(holding season: Int, episode: Int, in folders: [PlaybackSource], api: TorrentTubeAPI) async throws -> PlaybackSource? {
        var failure: Error?
        for folder in folders {
            do {
                let prepared: PreparedPlayback = try await api.post("api/playback/prepare", body: folder)
                try Task.checkCancellation()
                if holds(prepared, season: season, episode: episode, in: folder) { return folder }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failure = error
            }
        }
        // A folder could not be read (server unreachable): say so, rather than look elsewhere.
        if let failure { throw failure }
        return nil
    }

    static func holds(_ prepared: PreparedPlayback, season: Int, episode: Int, in folder: PlaybackSource) -> Bool {
        prepared.files.contains { PlaybackCoordinator.identity(of: $0, in: folder)?.covers(season: season, episode: episode) == true }
    }

    /// Search by the Ukrainian and the original title, then rank.
    static func search(title: String, original: String?, season: Int?, api: TorrentTubeAPI, allowUnmatched: Bool = true) async throws -> [Release] {
        var names = [title]
        if let original, !original.isEmpty, original.lowercased() != title.lowercased() { names.append(original) }
        var found: [MediaItem] = []
        for name in names {
            let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: name), .init(name: "enrich", value: "0")])
            try Task.checkCancellation()
            found += result.results.filter { new in !found.contains { $0.id == new.id } }
        }
        return rank(found, names: names, season: season, allowUnmatched: allowUnmatched)
            .map { Release(title: $0.title, magnet: $0.magnet, downloadLink: $0.downloadLink, sizeLabel: $0.sizeLabel, seeders: $0.seeders) }
    }
}
