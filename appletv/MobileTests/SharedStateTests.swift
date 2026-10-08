import XCTest
import UIKit
@testable import TorrentTubeMobile

@MainActor
final class SharedStateTests: XCTestCase {
    func testCacheWritesClearAndReloadRemainOrdered() async throws {
        let server = URL(string: "http://cache-test-\(UUID())/")!
        let cache = MetadataCache(server: server)
        let item = MediaItem(title: "Saved movie", magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        let details = try JSONDecoder().decode(Details.self, from: Data(#"{"title":"Saved movie","overview":"Cached details"}"#.utf8))
        for _ in 0..<30 { cache.store(details, for: item.title, permanent: true) }
        cache.storeFeed([item], for: "new")
        await cache.flush()
        let restored = MetadataCache(server: server)
        XCTAssertEqual(restored.details(for: item.title)?.overview, "Cached details")
        XCTAssertEqual(restored.feed(for: "new")?.first?.title, item.title)
        XCTAssertTrue(restored.isFeedFresh(for: "new"))
        cache.clear()
        await cache.flush()
        XCTAssertNil(MetadataCache(server: server).details(for: item.title))
        XCTAssertNil(MetadataCache(server: server).feed(for: "new"))
        // A write queued after Clear Cache must survive; older snapshots must not.
        cache.storeFeed([item], for: "movies")
        cache.clear()
        cache.storeFeed([item], for: "tv")
        await cache.flush()
        let afterClear = MetadataCache(server: server)
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
