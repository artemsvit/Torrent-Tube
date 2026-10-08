import XCTest
@testable import TorrentTubeTV

@MainActor
final class HomeCarouselTests: XCTestCase {
    func testLargeCatalogSelectionCost() {
        func feed(_ start: Int) -> [MediaItem] {
            (start..<(start + 720)).map { id in
                var item = MediaItem(title: "Title \(id)", magnet: "magnet:\(id)", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
                item.tmdbId = id; item.mediaType = "movie"
                return item
            }
        }
        let recent = feed(0), movies = feed(720), tv = feed(1440), cartoons = feed(2160)
        let before = Date()
        for category in [movies, tv, cartoons] {
            _ = recent.first { item in category.contains { LibrarySearchResults.sameTitle(item, $0) || item.id == $0.id } } ?? category.first
        }
        let oldCost = Date().timeIntervalSince(before)
        let after = Date()
        let picks = HomeFeaturedSelection.pick(new: recent, movies: movies, tv: tv, cartoons: cartoons)
        let newCost = Date().timeIntervalSince(after)
        print("Carousel selection for 2,880 titles: previous scans \(oldCost * 1000) ms; indexed selection \(newCost * 1000) ms")
        XCTAssertEqual(picks.count, 10)
        XCTAssertEqual(Array(picks.prefix(4)).map(\.id), [recent[0].id, movies[0].id, tv[0].id, cartoons[0].id])
    }
    func testFeaturedSelectionIncludesTenUniqueTitles() {
        let items = (1...14).map { number in
            MediaItem(title: "Film \(number)", magnet: "magnet:\(number)", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        }
        let picks = HomeFeaturedSelection.pick(new: [items[0], items[0]] + items, movies: items, tv: [], cartoons: [])
        XCTAssertEqual(picks.count, 10)
        XCTAssertEqual(Set(picks.map(\.id)).count, 10)
        XCTAssertEqual(picks.map(\.id), Array(items.prefix(10)).map(\.id))
    }
    func testFeaturedSelectionMixesKindsAndHidesDuplicateTitles() {
        func item(_ title: String, _ id: Int, _ type: String) -> MediaItem {
            var item = MediaItem(title: title, magnet: "magnet:\(title)", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
            item.tmdbId = id; item.mediaType = type
            return item
        }
        let movie = item("New movie", 1, "movie")
        let duplicate = item("Localized movie", 1, "movie")
        let tv = item("New series", 2, "tv")
        let cartoon = item("New cartoon", 3, "movie")
        let next = item("Another movie", 4, "movie")
        let picks = HomeFeaturedSelection.pick(new: [movie, duplicate, next], movies: [movie], tv: [tv], cartoons: [cartoon])
        XCTAssertEqual(picks.map(\.title), [movie.title, tv.title, cartoon.title, next.title])
        let seriesFirst = HomeFeaturedSelection.pick(new: [tv, next], movies: [movie], tv: [tv], cartoons: [cartoon])
        XCTAssertEqual(seriesFirst.map(\.title), [tv.title, movie.title, cartoon.title, next.title])
        let oldSeries = item("Older series", 5, "tv")
        let newest = HomeFeaturedSelection.pick(new: [movie, tv], movies: [movie], tv: [oldSeries, tv], cartoons: [cartoon])
        XCTAssertEqual(newest[1].title, tv.title, "Prefer a new release over the first catalog item")
        XCTAssertTrue(HomeFeaturedSelection.pick(new: [], movies: [], tv: [], cartoons: []).isEmpty)
    }

    func testInlinePreviewStartsMutedAndStopsWithoutMovieSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeroTrailerProtocol.self]
        let api = TorrentTubeAPI(baseURL: URL(string: "http://fixture/")!, session: URLSession(configuration: configuration))
        let item = MediaItem(title: "Featured film", magnet: "magnet:test", downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        let preview = HomeTrailerPreview()
        preview.start(item: item, details: nil, api: api)
        for _ in 0..<40 {
            if preview.controller != nil || preview.error != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(preview.error)
        XCTAssertNotNil(preview.controller)
        XCTAssertTrue(preview.muted)
        XCTAssertEqual(preview.controller?.player.audio?.isMuted, true)
        preview.toggleMute()
        XCTAssertFalse(preview.muted)
        preview.stop()
        XCTAssertNil(preview.controller)
        XCTAssertFalse(preview.loading)
        // A cancelled preparation must not install a player after leaving Home.
        preview.start(item: item, details: nil, api: api)
        preview.stop()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(preview.controller)
    }
}

private final class HeroTrailerProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let json: String
        if request.url!.path.hasSuffix("/api/trailer") {
            json = #"{"videos":[{"key":"abcdefghijk","name":"Trailer","lang":"en"}]}"#
        } else if request.url!.path.hasSuffix("/api/trailer/stream") {
            json = #"{"url":"/fixture-trailer","audio_url":null}"#
        } else { XCTFail("Hero preview must not create a movie session"); json = "{}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
