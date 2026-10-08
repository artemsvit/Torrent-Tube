import XCTest
import TVServices
@testable import TorrentTubeTV

final class TopShelfTests: XCTestCase {
    func testOptInContentAndSafeDeepLink() throws {
        let old = TopShelfStore.snapshot
        let oldServer = TopShelfStore.defaults.string(forKey: "activeServer")
        let oldPreference = TopShelfStore.defaults.object(forKey: "showNewInTopShelf")
        defer {
            TopShelfStore.defaults.set(oldServer, forKey: "activeServer")
            if let old { TopShelfStore.save(old) } else { TopShelfStore.clear() }
            if let oldPreference { TopShelfStore.defaults.set(oldPreference, forKey: "showNewInTopShelf") }
            else { TopShelfStore.defaults.removeObject(forKey: "showNewInTopShelf") }
        }
        let title = ShelfTitle(id: ShelfTitle.identifier("server|title"), title: "A film", rawTitle: "A film (2026)",
                               poster: "https://image.tmdb.org/t/p/w500/example.jpg", magnet: "magnet:?xt=private", downloadLink: nil,
                               tmdbID: 1, mediaType: "movie")
        TopShelfStore.defaults.set("http://nas.local/", forKey: "activeServer")
        TopShelfStore.save(ShelfSnapshot(server: "http://nas.local/", titles: [title]))
        XCTAssertEqual(TopShelfStore.snapshot?.titles.first?.title, "A film")
        XCTAssertFalse(title.url.absoluteString.contains("magnet"))
        TopShelfStore.defaults.set(false, forKey: "showNewInTopShelf")
        ContentProvider().loadTopShelfContent { XCTAssertNil($0) }
        TopShelfStore.defaults.set(true, forKey: "showNewInTopShelf")
        ContentProvider().loadTopShelfContent { content in
            let section = content as? TVTopShelfSectionedContent
            XCTAssertEqual(section?.sections.first?.items.first?.title, "A film")
            XCTAssertEqual(section?.sections.first?.items.first?.displayAction?.url, title.url)
        }
        TopShelfStore.clear()
        ContentProvider().loadTopShelfContent { XCTAssertNil($0) }
    }
}
