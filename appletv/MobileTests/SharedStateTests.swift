import XCTest
import UIKit
@testable import TorrentTubeMobile

@MainActor
final class SharedStateTests: XCTestCase {
    func testIndexedSearchPreservesFirstMatchAndIdentityRules() {
        var library: [MediaItem] = []
        for index in 0..<80 {
            var item = MediaItem(title: "Film \(index % 20) (\(2000 + index % 3))", magnet: nil,
                                 downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
            item.sourceOverride = PlaybackSource(path: "library/\(index)")
            item.cleanTitle = "Localized \(index % 20)"
            if index % 3 != 0 { item.tmdbId = index % 20 }
            if index % 4 != 0 { item.mediaType = index % 2 == 0 ? "movie" : "tv" }
            library.append(item)
        }
        var torrents = library.enumerated().map { index, local in
            var item = local
            item.sourceOverride = PlaybackSource(magnet: "magnet:\(index)")
            if index % 5 == 0 { item.tmdbId = nil }
            if index % 7 == 0 { item.mediaType = nil }
            return item
        }
        // An exact playable source wins even when title and metadata disagree.
        var sameSource = torrents[0]
        sameSource.sourceOverride = library[0].source
        sameSource.tmdbId = 999; sameSource.cleanTitle = "Different title"
        torrents.append(sameSource)
        var expected: [MediaItem] = []
        var remaining: [MediaItem] = []
        var seen: Set<String> = []
        for item in torrents {
            if let match = library.first(where: { LibrarySearchResults.sameTitle($0, item) }) {
                if seen.insert(match.id).inserted { expected.append(match) }
            } else { remaining.append(item) }
        }
        let result = LibrarySearchResults(query: "", library: library, torrents: torrents)
        XCTAssertEqual(result.library, expected)
        XCTAssertEqual(result.torrents, remaining)
        XCTAssertTrue(LibrarySearchResults(query: "", library: library, torrents: []).library.isEmpty)
    }

    func testPosterArtworkSharesRequestsAndReleasesCachedImages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeroImageProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = PosterArtworkCache(session: session)
        let url = URL(string: "https://hero-test/\(UUID()).png")!
        async let first = cache.image(url: url, width: 64, height: 128, fit: false)
        async let second = cache.image(url: url, width: 64, height: 128, fit: false)
        let (a, b) = try await (first, second)
        let original = try XCTUnwrap(a)
        XCTAssertTrue(original === b)
        XCTAssertEqual(HeroImageProtocol.requests(for: url), 1)
        await cache.clear()
        let reloaded = try await cache.image(url: url, width: 64, height: 128, fit: false)
        XCTAssertNotNil(reloaded)
        XCTAssertFalse(original === reloaded)
        XCTAssertEqual(HeroImageProtocol.requests(for: url), 2)
    }

    func testClearDuringInitialLoadDoesNotRestoreOldData() async {
        let server = URL(string: "http://cache-race-\(UUID())/")!
        let item = MediaItem(title: "Old movie", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        let original = MetadataCache(server: server)
        original.storeFeed([item], for: "old")
        await original.flush()
        let restored = MetadataCache(server: server)
        restored.clear()
        restored.storeFeed([item], for: "new")
        await restored.load()
        XCTAssertNil(restored.feed(for: "old"))
        XCTAssertEqual(restored.feed(for: "new")?.first?.title, item.title)
        await restored.flush()
        let next = MetadataCache(server: server)
        await next.load()
        XCTAssertNil(next.feed(for: "old"))
        XCTAssertNotNil(next.feed(for: "new"))
        next.clear()
        await next.flush()
    }

    func testPosterDecodePreservesPixelsForFillAndRetina() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800), format: format).image { _ in
            UIColor.systemBlue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
        }
        let data = try XCTUnwrap(source.pngData())
        let retina = try XCTUnwrap(PosterArtworkCache.decode(data, width: 400, height: 600, fit: false)?.cgImage)
        XCTAssertGreaterThanOrEqual(retina.width, 400)
        XCTAssertGreaterThanOrEqual(retina.height, 600)
        XCTAssertLessThanOrEqual(retina.height, 601)
        // A square crop must retain enough width, rather than downsample only to its height.
        let crop = try XCTUnwrap(PosterArtworkCache.decode(data, width: 400, height: 400, fit: false)?.cgImage)
        XCTAssertGreaterThanOrEqual(crop.width, 400)
        XCTAssertGreaterThanOrEqual(crop.height, 400)
        let full = try XCTUnwrap(PosterArtworkCache.decode(data, width: 2400, height: 3600, fit: false)?.cgImage)
        XCTAssertEqual(full.width, 1200)
        XCTAssertEqual(full.height, 1800)
    }

    func testCacheWritesClearAndReloadRemainOrdered() async throws {
        let server = URL(string: "http://cache-test-\(UUID())/")!
        let cache = MetadataCache(server: server)
        let item = MediaItem(title: "Saved movie", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        let details = try JSONDecoder().decode(Details.self, from: Data(#"{"title":"Saved movie","overview":"Cached details"}"#.utf8))
        for _ in 0..<30 { cache.store(details, for: item.title, permanent: true) }
        cache.storeFeed([item], for: "new")
        await cache.flush()
        let restored = MetadataCache(server: server)
        await restored.load()
        XCTAssertEqual(restored.details(for: item.title)?.overview, "Cached details")
        XCTAssertEqual(restored.feed(for: "new")?.first?.title, item.title)
        XCTAssertTrue(restored.isFeedFresh(for: "new"))
        cache.clear()
        await cache.flush()
        let empty = MetadataCache(server: server)
        await empty.load()
        XCTAssertNil(empty.details(for: item.title))
        XCTAssertNil(empty.feed(for: "new"))
        // A write queued after Clear Cache must survive; older snapshots must not.
        cache.storeFeed([item], for: "movies")
        cache.clear()
        cache.storeFeed([item], for: "tv")
        await cache.flush()
        let afterClear = MetadataCache(server: server)
        await afterClear.load()
        XCTAssertNil(afterClear.feed(for: "movies"))
        XCTAssertEqual(afterClear.feed(for: "tv")?.first?.title, item.title)
        cache.clear()
        await cache.flush()
    }

    func testHeroArtworkSharesRequestsReusesDecodeAndClears() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeroImageProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = HeroArtworkCache(session: session)
        let url = URL(string: "https://hero-test/\(UUID()).png")!
        async let first = cache.image(for: url)
        async let second = cache.image(for: url)
        let (a, b) = try await (first, second)
        let original = try XCTUnwrap(a)
        XCTAssertTrue(original === b)
        XCTAssertEqual(HeroImageProtocol.requests(for: url), 1)
        let cached = try await cache.image(for: url)
        XCTAssertTrue(original === cached)
        XCTAssertEqual(HeroImageProtocol.requests(for: url), 1)
        await cache.clear()
        let reloaded = try await cache.image(for: url)
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(HeroImageProtocol.requests(for: url), 2)
    }
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp()
        suite = "TorrentTubeTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }
    func testLibrarySearchWinsOverTorrentAndMatchesLocalizedTitle() {
        var local = MediaItem(title: "Arrival.2016.mkv", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        local.cleanTitle = "Прибуття"; local.tmdbId = 329865; local.mediaType = "movie"
        local.sourceOverride = PlaybackSource(path: "movies/arrival")
        var remote = MediaItem(title: "Arrival.2016.1080p", magnet: "magnet:arrival", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        remote.tmdbId = 329865; remote.mediaType = "movie"
        let results = LibrarySearchResults(query: "arrival", library: [local], torrents: [remote])
        XCTAssertEqual(results.library.map(\.source), [local.source])
        XCTAssertTrue(results.torrents.isEmpty)
        XCTAssertEqual(LibrarySearchResults(query: "прибуття", library: [local], torrents: []).library.count, 1)
        // The remote match finds a local copy even when its title is in another language.
        local = MediaItem(title: "Прибуття", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        local.tmdbId = 329865; local.mediaType = "movie"; local.sourceOverride = PlaybackSource(path: "arrival")
        XCTAssertEqual(LibrarySearchResults(query: "arrival", library: [local], torrents: [remote]).library.count, 1)
    }
    func testSearchKeepsRemakesAndUnknownIdentities() {
        func item(_ title: String) -> MediaItem {
            MediaItem(title: title, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        }
        XCTAssertTrue(LibrarySearchResults.sameTitle(item("Dune.2021.mkv"), item("Dune (2021) 2160p")))
        XCTAssertFalse(LibrarySearchResults.sameTitle(item("Dune 1984"), item("Dune 2021")))
        XCTAssertFalse(LibrarySearchResults.sameTitle(item("Dune"), item("Dune 2021")))
        var movie = item("Movie"); movie.tmdbId = 42; movie.mediaType = "movie"
        var tv = item("Show"); tv.tmdbId = 42; tv.mediaType = "tv"
        XCTAssertFalse(LibrarySearchResults.sameTitle(movie, tv))
        XCTAssertTrue(LibrarySearchResults(query: "nothing", library: [movie], torrents: [tv]).library.isEmpty)
        XCTAssertEqual(LibrarySearchResults(query: "nothing", library: [movie], torrents: [tv]).torrents.count, 1)
    }
    func testNextSeasonComesFromAnotherFolder() {
        let playing = EpisodeIdentity(season: 1, episode: 10)
        func folder(_ path: String, _ names: [String]) -> (PlaybackSource, PreparedPlayback) {
            (PlaybackSource(path: path), PreparedPlayback(id: "lib:" + path, selected: 0,
                files: names.enumerated().map { VideoFile(index: $0.offset, name: $0.element, size: 100) }))
        }
        let copyOfSeason1 = folder("TV/Show S01 4K", ["Show.S01E01.mkv", "Show.S01E10.mkv"])
        let season3 = folder("TV/Show S03", ["Show.S03E02.mkv", "Show.S03E01.mkv"])
        let season2 = folder("TV/Show S02", ["Show.S02E02.mkv", "Show.S02E01.mkv", "Sample.mkv"])
        // Season 2's first episode, wherever the folders and files are listed.
        let next = PlaybackCoordinator.nextSeasonStart(after: playing, in: [copyOfSeason1, season3, season2])
        XCTAssertEqual(next?.folder, 2)
        XCTAssertEqual(next?.file, 1)
        // A gap in the seasons: the next one there is.
        XCTAssertEqual(PlaybackCoordinator.nextSeasonStart(after: playing, in: [copyOfSeason1, season3])?.file, 1)
        // Only copies of the season just watched: nothing to play on.
        XCTAssertNil(PlaybackCoordinator.nextSeasonStart(after: playing, in: [copyOfSeason1]))
        XCTAssertNil(PlaybackCoordinator.nextSeasonStart(after: EpisodeIdentity(season: 3, episode: 2), in: [season2, season3]))
    }

    func testVersionsKeepOnlyTheTitleAndPutTheSeasonFirst() {
        let titles = ["Deep Rising (1998) BDRip 1080p H.265 2xUkr/Eng | Sub Eng",
                      "VA - . (1997) [MP3, Tape rip] | Ethno / Folk",
                      "Below (S2) (2027) WEB-DL 1080p Ukr/Eng",
                      "Below (S1) (2026) WEB-DL 1080p Ukr/Eng | Sub Ukr/Eng (S1)",
                      "З глибини / Below (2026) Сезон 1 WEB-DL",
                      "Відьмак: Сирени з глибин / The Witcher: Sirens of the Deep (2025)"]
        let results = titles.map { MediaItem(title: $0, magnet: "magnet:?xt=\($0.count)", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil) }
        let ranked = ReleaseChoice.rank(results, names: ["З глибини", "Below"], season: 1).map(\.title)
        XCTAssertEqual(ranked, [titles[3], titles[4], titles[2]], "only the title's releases, season 1 first")
        XCTAssertEqual(ReleaseChoice.rank(results, names: ["Nothing like this"], season: nil).count, titles.count, "no match keeps the search")
    }

    func testAutomaticEpisodeReleasePrefersSeededMatchingSeason() {
        func release(_ title: String, _ seeds: Int) -> Release {
            Release(title: title, magnet: "magnet:?xt=\(title)", downloadLink: nil, sizeLabel: nil, seeders: seeds)
        }
        let wrongSeason = release("Nobody Wants This S02", 100)
        let wrongEpisode = release("Nobody Wants This S01E04", 200)
        let unseeded = release("Nobody Wants This S01 2160p", 0)
        let seeded = release("Nobody Wants This (S1) 1080p", 22)
        XCTAssertEqual(ReleaseChoice.automaticRelease([wrongSeason, wrongEpisode, unseeded, seeded], season: 1, episode: 3), seeded)
        XCTAssertNil(ReleaseChoice.automaticRelease([wrongSeason, wrongEpisode], season: 1, episode: 3))
        XCTAssertNil(ReleaseChoice.automaticRelease([release("Unknown show", 300)], season: 1, episode: 3))
        let unrelated = MediaItem(title: "Other show S01", magnet: "magnet:test", downloadLink: nil, sizeLabel: nil, seeders: 100, releases: nil)
        XCTAssertTrue(ReleaseChoice.rank([unrelated], names: ["Nobody Wants This"], season: 1, allowUnmatched: false).isEmpty)
    }

    func testReleaseNamesTellTheirSeasons() {
        XCTAssertEqual(ReleaseChoice.seasons(in: "Nobody Wants This S02E07 (2026) NF WEB-DL 1080p"), [2])
        XCTAssertEqual(ReleaseChoice.seasons(in: "Below (S1) (2026) WEB-DL 1080p Ukr/Eng (S1)"), [1])
        XCTAssertEqual(ReleaseChoice.seasons(in: "Reacher (Seasons 2-4) (2023-2026)"), [2, 3, 4])
        XCTAssertEqual(ReleaseChoice.seasons(in: "Друзі (Сезон 3) WEB-DL"), [3])
        XCTAssertEqual(ReleaseChoice.seasons(in: "The Last of Us S01-S02 BDRip"), [1, 2])
        XCTAssertTrue(ReleaseChoice.covers("Columbo 1080p complete", season: 5), "no season named: the whole series")
        XCTAssertFalse(ReleaseChoice.covers("Nobody Wants This S02 (2026)", season: 1))
    }

    func testPlayOnASeriesStartsAtItsFirstEpisode() {
        let files = ["Show S02E07.mkv", "Show S02E02.mkv", "Show S02E10.mkv"].enumerated().map { VideoFile(index: $0.offset, name: $0.element, size: 1) }
        let request = PlaybackRequest(source: PlaybackSource(magnet: "magnet:?x"), title: "Show")
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: request, prepared: PreparedPlayback(id: "t", selected: 0, files: files)), 1)
    }

    func testFavoritesPersistAndStayScopedToServer() throws {
        let server = URL(string: "http://nas/tube/")!
        let other = URL(string: "http://other/")!
        let item = MediaItem(title: "Movie", magnet: "magnet:test", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        let store = FavoritesStore(defaults: defaults)
        store.toggle(item, details: nil, server: server)
        XCTAssertTrue(FavoritesStore(defaults: defaults).contains(item, server: server))
        XCTAssertFalse(store.contains(item, server: other))
        XCTAssertEqual(store.entries(server: server).first?.item.source, item.source)
        store.toggle(item, details: nil, server: server)
        XCTAssertTrue(FavoritesStore(defaults: defaults).entries.isEmpty)
        XCTAssertFalse(store.contains(item, server: server))
        XCTAssertTrue(store.entries(server: server).isEmpty)
    }
    func testHistoryRetainsFileAndRemovesCompletedTitle() {
        let server = URL(string: "http://nas/")!
        let session = PlaybackSession(session: "viewer-one", id: "torrent", file: 2, name: "Episode", url: "stream", heartbeatInterval: 20)
        let history = ResumeHistory(defaults: defaults)
        history.save(server: server, session: session, title: "Episode", source: PlaybackSource(id: "torrent"), seconds: 40, duration: 100)
        let saved = ResumeHistory(defaults: defaults).entry(server: server, torrentID: "torrent", file: 2)
        XCTAssertEqual(saved?.source.file, 2)
        XCTAssertEqual(saved?.seconds, 40)
        history.clear(server: URL(string: "http://other/")!)
        XCTAssertEqual(history.entries.count, 1)
        history.save(server: server, session: session, title: "Episode", source: PlaybackSource(id: "torrent"), seconds: 99, duration: 100, completed: true)
        XCTAssertTrue(ResumeHistory(defaults: defaults).entries.isEmpty)
    }
    func testEpisodeSelectionDoesNotGuessAcrossMultipleEncodes() {
        let request = PlaybackRequest(source: PlaybackSource(id: "torrent"), title: "Show", season: 2, episode: 3)
        let file = VideoFile(index: 4, name: "Show.S02E03.mkv", size: 100)
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: request, prepared: PreparedPlayback(id: "torrent", selected: 0, files: [file])), 4)
        let duplicate = VideoFile(index: 5, name: "Show.S02E03.4K.mkv", size: 100)
        XCTAssertNil(PlaybackCoordinator.selectedFile(request: request, prepared: PreparedPlayback(id: "torrent", selected: 0, files: [file, duplicate])))
        XCTAssertNil(PlaybackCoordinator.selectedFile(request: request, prepared: PreparedPlayback(id: "torrent", selected: 0, files: [VideoFile(index: 0, name: "Unknown.mkv", size: 100)])))
    }
    func testServerEpisodeFieldsWinAndDoubleFilesPlayForBothEpisodes() throws {
        // The server's reading (episodes.py) is used as sent, even where the name alone says nothing.
        let data = Data(#"{"id":"library:Cartoon/Bluey","selected":0,"files":[{"index":0,"name":"1-1-2 Ксилофон & Лікарня.mp4","path":"Cartoon/Bluey/1-1-2 Ксилофон & Лікарня.mp4","size":100,"season":1,"episode":1,"last_episode":2},{"index":1,"name":"Untitled.mp4","path":"Cartoon/Bluey/Untitled.mp4","size":100,"season":1,"episode":3,"last_episode":4}]}"#.utf8)
        // Decoded the way TorrentTubeAPI decodes every answer.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let prepared = try decoder.decode(PreparedPlayback.self, from: data)
        let source = PlaybackSource(path: "Cartoon/Bluey")
        XCTAssertEqual(prepared.files[1].episodeIdentity, EpisodeIdentity(season: 1, episode: 3, lastEpisode: 4))
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Bluey", season: 1, episode: 2), prepared: prepared), 0)
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Bluey", season: 1, episode: 4), prepared: prepared), 1)
        XCTAssertEqual(PlaybackCoordinator.nextFile(after: 0, in: prepared.files), 1)
        XCTAssertNil(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Bluey", season: 1, episode: 5), prepared: prepared))
    }
    func testCyrillicAndUnusualEpisodeNames() {
        XCTAssertEqual(EpisodeIdentity.parse("Гільда С01Е01.mkv"), EpisodeIdentity(season: 1, episode: 1))
        XCTAssertEqual(EpisodeIdentity.parse("Пантеон - S02EP05 [1080p].mkv"), EpisodeIdentity(season: 2, episode: 5))
        XCTAssertEqual(EpisodeIdentity.parse("S010E1.mp4"), EpisodeIdentity(season: 10, episode: 1))
        XCTAssertEqual(EpisodeIdentity.parse(name: "Кармен - Серія 05 - Витівка.mkv", path: "Cartoon/Кармен Сезон 1/Кармен - Серія 05 - Витівка.mkv"), EpisodeIdentity(season: 1, episode: 5))
        XCTAssertNil(EpisodeIdentity.parse(name: "[01] Toy Story (1995).mkv", path: "Cartoon/Toy Story. Collection (1995-2022)/[01] Toy Story (1995).mkv"))
    }
    func testNumberedLibraryEpisodesMatchTheirSeasonFolder() throws {
        let data = Data(#"{"id":"library:TV Shows/Show","selected":0,"files":[{"index":0,"name":"03 The Fuzzyboots Corollary (HD).m4v","path":"TV Shows/Show/Season 1/03 The Fuzzyboots Corollary (HD).m4v","size":100},{"index":27,"name":"03 The Procreation Calculation (HD).m4v","path":"TV Shows/Show/Season 12/03 The Procreation Calculation (HD).m4v","size":100}]}"#.utf8)
        let prepared = try JSONDecoder().decode(PreparedPlayback.self, from: data)
        let source = PlaybackSource(path: "TV Shows/Show")
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Show", season: 12, episode: 3), prepared: prepared), 27)
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Show", season: 1, episode: 3), prepared: prepared), 0)
        XCTAssertNil(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Show", season: 2, episode: 3), prepared: prepared))
        let duplicate = prepared.files + [VideoFile(index: 28, name: prepared.files[1].name, size: 100, path: prepared.files[1].path)]
        XCTAssertNil(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Show", season: 12, episode: 3), prepared: PreparedPlayback(id: prepared.id, selected: 0, files: duplicate)))
        let legacy = PreparedPlayback(id: "legacy", selected: 0, files: [VideoFile(index: 4, name: "03 Episode.m4v", size: 100)])
        XCTAssertNil(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: source, title: "Show", season: 12, episode: 3), prepared: legacy))
        XCTAssertEqual(PlaybackCoordinator.selectedFile(request: PlaybackRequest(source: PlaybackSource(path: "TV Shows/Show/Season 12"), title: "Show", season: 12, episode: 3), prepared: legacy), 4)
    }
    func testBackgroundReacquiresSessionAndOffersSavedPosition() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlaybackProtocol.self]
        let api = TorrentTubeAPI(baseURL: URL(string: "http://fixture/")!, session: URLSession(configuration: config))
        let model = PlaybackCoordinator(request: PlaybackRequest(source: PlaybackSource(id: "torrent"), title: "Movie"), api: api)
        model.history = ResumeHistory(defaults: defaults)
        await model.prepare()
        XCTAssertNotNil(model.controller)
        let first = try XCTUnwrap(model.session?.session)
        model.controller?.seconds = 35; model.controller?.duration = 100
        model.savePosition()
        model.suspend()
        XCTAssertNil(model.session)
        XCTAssertNil(model.controller)
        XCTAssertTrue(model.suspended)
        await model.prepare()
        XCTAssertNotEqual(model.session?.session, first)
        XCTAssertEqual(model.resumeEntry?.seconds, 35)
        XCTAssertNil(model.controller, "Resume requires a user choice")
        model.close()
    }
}

/// A library title's episode plays from the folder that has it - not from
/// whichever folder the title opens with.
final class LibraryEpisodeSourceTests: XCTestCase {
    private func api() -> TorrentTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryFoldersProtocol.self]
        return TorrentTubeAPI(baseURL: URL(string: "http://library-test/")!, session: URLSession(configuration: config))
    }
    private let season1 = PlaybackSource(path: "Cartoon/Bluey (2018)")
    private let season2 = PlaybackSource(path: "Cartoon/Bluey S02")

    func testTheFolderWithTheEpisodeIsChosen() async throws {
        let folder = try await ReleaseChoice.libraryFolder(holding: 2, episode: 3, in: [season1, season2], api: api())
        XCTAssertEqual(folder, season2)
        let double = try await ReleaseChoice.libraryFolder(holding: 1, episode: 2, in: [season1, season2], api: api())
        XCTAssertEqual(double, season1, "1-1-2 holds episode 2 as well")
    }

    func testAnEpisodeNoFolderHasIsNotSentToTheLibrary() async throws {
        let folder = try await ReleaseChoice.libraryFolder(holding: 3, episode: 1, in: [season1, season2], api: api())
        XCTAssertNil(folder)
    }

    func testAnUnreadableFolderIsReportedNotSkipped() async {
        do {
            _ = try await ReleaseChoice.libraryFolder(holding: 3, episode: 1, in: [PlaybackSource(path: "Cartoon/Broken")], api: api())
            XCTFail("expected the server error")
        } catch {}
    }

    func testFoldersStartWithTheOneTheTitleOpensWith() {
        let item = MediaItem(title: "Bluey", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil,
                             releases: [Release(title: "Bluey S02", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, path: season2.path),
                                        Release(title: "Bluey", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, path: season1.path)],
                             sourceOverride: season1)
        XCTAssertEqual(ReleaseChoice.libraryFolders(of: item), [season1, season2])
    }
}

private final class LibraryFoldersProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "library-test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            return data
        } ?? Data()
        let text = String(decoding: body, as: UTF8.self)
        let status: Int, json: String
        if text.contains("Bluey S02") {
            status = 200; json = #"{"id":"library:Cartoon/Bluey S02","selected":0,"files":[{"index":0,"name":"Bluey S02E03.mp4","size":1,"season":2,"episode":3,"last_episode":3}]}"#
        } else if text.contains("Bluey (2018)") {
            status = 200; json = #"{"id":"library:Cartoon/Bluey (2018)","selected":0,"files":[{"index":0,"name":"1-1-2 Name.mp4","size":1,"season":1,"episode":1,"last_episode":2}]}"#
        } else {
            status = 500; json = #"{"error":"Could not read the folder"}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class PlaybackProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let json: String
        if path.hasSuffix("prepare") {
            json = #"{"id":"torrent","selected":0,"files":[{"index":0,"name":"Movie.mkv","size":100}]}"#
        } else if path.hasSuffix("sessions") {
            json = "{\"session\":\"\(UUID())\",\"id\":\"torrent\",\"file\":0,\"name\":\"Movie\",\"url\":\"stream/movie\",\"heartbeat_interval\":20}"
        } else if request.httpMethod == "DELETE" { json = #"{"ok":true}"# }
        else { json = #"{"ready":true,"progress":100}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class HeroImageProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var counts: [URL: Int] = [:]
    static func requests(for url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[url, default: 0]
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "hero-test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.lock.lock(); Self.counts[url, default: 0] += 1; Self.lock.unlock()
        // A real PNG exercises ImageIO decoding, rather than just testing cache keys.
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
