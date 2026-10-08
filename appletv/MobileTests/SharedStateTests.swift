import XCTest
@testable import TorrentTubeMobile

@MainActor
final class SharedStateTests: XCTestCase {
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
