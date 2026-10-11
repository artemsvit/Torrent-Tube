import XCTest
import UIKit
import SwiftUI
#if os(tvOS)
@testable import TorrentTubeTV
#else
@testable import TorrentTubeMobile
#endif

final class APITests: XCTestCase {
    @MainActor
    func testNetworkErrorsUseSelectedLanguageAndTimeoutsAreExtended() async throws {
        XCTAssertEqual(TorrentTubeAPI.requestTimeout(for: "api/playback/sessions"), 86.25, accuracy: 0.001)
        XCTAssertEqual(TorrentTubeAPI.requestTimeout(for: "api/config"), 11.5, accuracy: 0.001)
        XCTAssertEqual(TorrentTubeAPI.requestTimeout(for: "api/library"), 46, accuracy: 0.001)
        XCTAssertEqual(PlaybackCoordinator.networkFailureGrace, 51.75, accuracy: 0.001)
        let original = Localizer.shared.language
        defer { Localizer.shared.language = original }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TimeoutResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = TorrentTubeAPI(baseURL: URL(string: "http://timeout.test/")!, session: session)
        for language in AppLanguage.allCases {
            Localizer.shared.language = language
            do {
                let _: ServerConfig = try await api.request("api/config")
                XCTFail("Expected timeout")
            } catch {
                XCTAssertTrue(error is NetworkRequestError)
                XCTAssertEqual(error.localizedDescription, language == .uk ? "Сервер не відповів вчасно. Спробуйте ще раз." : "The server took too long to respond. Try again.")
            }
            for code in [URLError.networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed, .unknown] {
                XCTAssertFalse(TorrentTubeAPI.networkErrorMessage(code).isEmpty)
                if language == .uk { XCTAssertNotEqual(TorrentTubeAPI.networkErrorMessage(code), URLError(code).localizedDescription) }
            }
            #if os(tvOS)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let host = UIHostingController(rootView: ZStack {
                Color.appBase
                TVPlaybackErrorPrompt(title: "Playback interrupted", message: TorrentTubeAPI.networkErrorMessage(.timedOut), retry: {}, close: {})
            }.preferredColorScheme(.dark))
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let picture = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: picture)
            attachment.name = "Timeout prompt \(language.rawValue)"; attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            #endif
        }
    }
    @MainActor
    func testOnlyRecognizedEpisodesContinueAutomatically() throws {
        let decoder = JSONDecoder()
        let movies = try decoder.decode([VideoFile].self, from: Data(#"[{"index":0,"name":"Feature.mkv","size":100},{"index":1,"name":"Behind the scenes.mkv","size":20}]"#.utf8))
        XCTAssertNil(PlaybackCoordinator.nextFile(after: 0, in: movies))
        let episodes = try decoder.decode([VideoFile].self, from: Data(#"[{"index":2,"name":"Show.S01E02.mkv","size":100},{"index":0,"name":"Show.S01E01.mkv","size":100},{"index":3,"name":"Bonus.mkv","size":20}]"#.utf8))
        XCTAssertEqual(PlaybackCoordinator.nextFile(after: 0, in: episodes), 2)
        XCTAssertNil(PlaybackCoordinator.nextFile(after: 2, in: episodes))
        XCTAssertNil(PlaybackCoordinator.nextFile(after: 3, in: episodes))
        let legacy = [VideoFile(index: 0, name: "Episode 1.mkv", size: 100), VideoFile(index: 1, name: "Episode 2.mkv", size: 100)]
        XCTAssertEqual(PlaybackCoordinator.nextFile(after: 0, in: legacy), 1)
    }
    @MainActor
    func testCompletedFileEndFallbackDoesNotFinishPausedOrIncompletePlayback() {
        XCTAssertTrue(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 99.8, duration: 100, stationaryTicks: 3, complete: true, paused: false))
        XCTAssertFalse(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 99.8, duration: 100, stationaryTicks: 3, complete: true, paused: true))
        XCTAssertFalse(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 99.8, duration: 100, stationaryTicks: 3, complete: false, paused: false))
        XCTAssertFalse(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 97.5, duration: 100, stationaryTicks: 3, complete: true, paused: false))
        // VLC stops about a second short of the stated length (Friends S8E4: 22:26 of 22:27).
        XCTAssertTrue(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 1346.2, duration: 1347.3, stationaryTicks: 3, complete: true, paused: false))
        XCTAssertFalse(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 99.8, duration: 100, stationaryTicks: 2, complete: true, paused: false))
        XCTAssertFalse(PlaybackCoordinator.reachedCompletedFileEnd(seconds: 0, duration: 0, stationaryTicks: 3, complete: true, paused: false))
    }

    func testAddressNormalizationPreservesProxyPrefix() throws {
        let base = try TorrentTubeAPI.serverURL(" 192.168.0.102:5058/tube ")
        XCTAssertEqual(base.absoluteString, "http://192.168.0.102:5058/tube/")
        let api = TorrentTubeAPI(baseURL: base)
        XCTAssertEqual(try api.url("api/search", query: [.init(name: "q", value: "a & b")]).path, "/tube/api/search")
        XCTAssertEqual(try api.mediaURL("/stream/hash/1/My%20video.mkv").absoluteString, "http://192.168.0.102:5058/tube/stream/hash/1/My%20video.mkv")
    }
    func testRejectsCredentialsAndForeignPlaybackURL() throws {
        for address in ["", "ftp://nas.local", "http://user:pass@nas.local", "http://nas.local/?token=secret", "http://nas.local/#part"] {
            XCTAssertThrowsError(try TorrentTubeAPI.serverURL(address))
        }
        let api = TorrentTubeAPI(baseURL: try TorrentTubeAPI.serverURL("https://nas.example/tube"))
        XCTAssertThrowsError(try api.mediaURL("https://elsewhere.example/movie.mkv"))
        XCTAssertThrowsError(try api.mediaURL("../movie.mkv"))
    }
    func testDecodesLegacyConfigButRequiresSessionCapabilitiesForPlayback() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let legacy = Data(#"{"categories":["Movies"],"search_enabled":true,"tmdb_enabled":false}"#.utf8)
        XCTAssertFalse(try decoder.decode(ServerConfig.self, from: legacy).supportsPlayback)
        let modern = Data(#"{"server":"torrenttube","api_version":1,"categories":[],"search_enabled":false,"tmdb_enabled":false,"capabilities":{"file_selection":true,"playback_sessions":true}}"#.utf8)
        XCTAssertTrue(try decoder.decode(ServerConfig.self, from: modern).supportsPlayback)
    }
    func testEpisodeSourceEncodingUsesServerKeys() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(PlaybackSource(downloadLink: "https://tracker.example/item", file: 3))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["file"] as? Int, 3)
        XCTAssertEqual(body["download_link"] as? String, "https://tracker.example/item")
    }
    func testDecodesRealCatalogOptionalFields() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = Data(#"{"results":[{"title":"Example","magnet":"magnet:?xt=urn:btih:abc","download_link":null,"poster":null,"rating":null,"seeders":4,"tmdb_id":12,"media_type":"movie","releases":null}]}"#.utf8)
        let item = try decoder.decode(CatalogResponse.self, from: data).results[0]
        XCTAssertEqual(item.tmdbId, 12)
        XCTAssertEqual(item.displayTitle, "Example")
    }
}

private final class TimeoutResponseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
    override func stopLoading() {}
}

final class EpisodeIdentityTests: XCTestCase {
    func testNumberedEpisodesUseTheirOwnFolderSeason() {
        for folder in ["Season 12", "S12", "Сезон 12", "12 сезон", "The Big Bang Theory - Season 12"] {
            XCTAssertEqual(EpisodeIdentity.parse(name: "03 Episode title (HD).m4v", path: "TV Shows/Show/\(folder)/03 Episode title (HD).m4v"), EpisodeIdentity(season: 12, episode: 3))
        }
        XCTAssertEqual(EpisodeIdentity.parse(name: "E03 Title.mkv", path: #"Show\Season 2\E03 Title.mkv"#), EpisodeIdentity(season: 2, episode: 3))
        XCTAssertEqual(EpisodeIdentity.parse(name: "Show.S02E03.mkv", path: "Show/Season 1/Show.S02E03.mkv"), EpisodeIdentity(season: 2, episode: 3))
        XCTAssertEqual(EpisodeIdentity.parse(name: "03-04 Combined.m4v", path: "Show/Season 12/03-04 Combined.m4v"), EpisodeIdentity(season: 12, episode: 3, lastEpisode: 4))
        XCTAssertEqual(EpisodeIdentity.parse(name: "E03-E04 Combined.mkv", path: "Show/Season 12/E03-E04 Combined.mkv"), EpisodeIdentity(season: 12, episode: 3, lastEpisode: 4))
        for name in ["03-10 Not a range.m4v", "1080p Episode.mkv", "Unknown.mkv"] {
            XCTAssertNil(EpisodeIdentity.parse(name: name, path: "Show/Season 12/\(name)"))
        }
        XCTAssertNil(EpisodeIdentity.parse(name: "03 Title.m4v", path: "Show/03 Title.m4v"))
    }
    func testMapsKnownEpisodeNamesAndRejectsAmbiguousFiles() {
        XCTAssertEqual(EpisodeIdentity.parse("Show.S02E03.1080p.mkv"), EpisodeIdentity(season: 2, episode: 3))
        XCTAssertEqual(EpisodeIdentity.parse("Show 1x04.mp4"), EpisodeIdentity(season: 1, episode: 4))
        XCTAssertNil(EpisodeIdentity.parse("Episode 4.mkv"))
        XCTAssertEqual(EpisodeIdentity.parse("Show.S01E01-E02.mkv"), EpisodeIdentity(season: 1, episode: 1, lastEpisode: 2))
        XCTAssertEqual(EpisodeIdentity.parse("Show.S01E01E02.mkv"), EpisodeIdentity(season: 1, episode: 1, lastEpisode: 2))
        XCTAssertEqual(EpisodeIdentity.parse("Show S01E05 720p.mkv"), EpisodeIdentity(season: 1, episode: 5))
        XCTAssertNil(EpisodeIdentity.parse("2019-01-02 Vlog.mp4"))
    }
    func testDoubleEpisodeFilesPlayForEitherEpisode() {
        let bluey = EpisodeIdentity.parse("1-1-2 Чарівний ксилофон & Лікарня.mp4")
        XCTAssertEqual(bluey, EpisodeIdentity(season: 1, episode: 1, lastEpisode: 2))
        XCTAssertEqual(bluey?.covers(season: 1, episode: 2), true)
        XCTAssertEqual(bluey?.covers(season: 1, episode: 3), false)
        XCTAssertEqual(EpisodeIdentity.parse("1-51-52 Татків вечір.mp4"), EpisodeIdentity(season: 1, episode: 51, lastEpisode: 52))
    }
    func testExistingResumeEntriesRemainReadable() throws {
        let data = Data(#"[{"id":"server|hash|0","server":"http://nas/","torrentID":"hash","file":0,"title":"Movie","source":{"id":"hash"},"seconds":25,"duration":100,"updatedAt":0}]"#.utf8)
        let entry = try JSONDecoder().decode([ResumeEntry].self, from: data)[0]
        XCTAssertEqual(entry.seconds, 25)
        XCTAssertNil(entry.artwork)
    }
}

final class TrailerModelTests: XCTestCase {
    func testServerTrailerMetadataAndSeparateAudioDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(TrailerResponse.self, from: Data(#"{"videos":[{"key":"uLtkt8BonwM","name":"Official trailer","lang":"en"}]}"#.utf8))
        XCTAssertTrue(response.videos[0].isValid)
        XCTAssertEqual(response.videos[0].lang, "en")
        XCTAssertNotNil(response.videos[0].thumbnailURL)
        let source = try decoder.decode(TrailerStreamResponse.self, from: Data(#"{"url":"/trailer-stream/token/0","audio_url":"/trailer-stream/token/1"}"#.utf8))
        XCTAssertEqual(source.audioUrl, "/trailer-stream/token/1")
        XCTAssertFalse(Trailer(key: "invalid/link", name: "Invalid", lang: nil).isValid)
    }
}

