import XCTest
import TVServices
import UIKit
@testable import TorrentTubeTV

final class TopShelfTests: XCTestCase {
    func testLongArtworkTitleWrapsWithoutTruncation() {
        let title = "Людина-павук: Абсолютно новий день"
        let text = TopShelfArtwork.titleText(title)
        XCTAssertEqual(text.string, title)
        let paragraph = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.lineBreakMode, .byWordWrapping)
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as! UIFont
        let bounds = text.boundingRect(with: CGSize(width: 1150, height: CGFloat.greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        XCTAssertGreaterThan(bounds.height, font.lineHeight)
        XCTAssertLessThanOrEqual(bounds.height, 220)
        let banner = UIGraphicsImageRenderer(size: CGSize(width: 1920, height: 1080)).image { _ in
            UIColor.darkGray.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        }
        let attachment = XCTAttachment(image: TopShelfArtwork.render(banner: banner, kind: "Movie", title: title))
        attachment.name = "Full Ukrainian Top Shelf Title"; attachment.lifetime = .keepAlways
        add(attachment)
    }
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
        var title = ShelfTitle(id: ShelfTitle.identifier("server|title"), title: "A film", rawTitle: "A film (2026)",
                               poster: "https://image.tmdb.org/t/p/w500/example.jpg", magnet: "magnet:?xt=private", downloadLink: nil,
                               tmdbID: 1, mediaType: "movie")
        title.artworkID = ShelfTitle.identifier("test-artwork")
        title.previewURL = "http://nas.local/api/trailer/preview/abcdefghijk"
        let directory = try XCTUnwrap(TopShelfStore.artworkDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let artworkFile = directory.appendingPathComponent(title.artworkID! + ".jpg")
        let poster = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { _ in
            UIColor.systemBlue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        let art = TopShelfArtwork.render(banner: poster, kind: "Movie", title: title.title)
        XCTAssertEqual(art.size, CGSize(width: 1920, height: 1080))
        try XCTUnwrap(art.jpegData(compressionQuality: 0.8)).write(to: artworkFile)
        defer { try? FileManager.default.removeItem(at: artworkFile) }
        TopShelfStore.defaults.set("http://nas.local/", forKey: "activeServer")
        TopShelfStore.save(ShelfSnapshot(server: "http://nas.local/", titles: [title]))
        XCTAssertEqual(TopShelfStore.snapshot?.titles.first?.title, "A film")
        XCTAssertFalse(title.url.absoluteString.contains("magnet"))
        TopShelfStore.defaults.set(false, forKey: "showNewInTopShelf")
        ContentProvider().loadTopShelfContent { XCTAssertNil($0) }
        TopShelfStore.defaults.set(true, forKey: "showNewInTopShelf")
        ContentProvider().loadTopShelfContent { content in
            let carousel = content as? TVTopShelfCarouselContent
            XCTAssertEqual(carousel?.style, .actions)
            XCTAssertEqual(carousel?.items.first?.identifier, title.id)
            XCTAssertEqual(carousel?.items.first?.previewVideoURL?.absoluteString, title.previewURL)
            XCTAssertNil(carousel?.items.first?.title)
            XCTAssertEqual(carousel?.items.first?.imageURL(for: .screenScale1x), artworkFile)
            XCTAssertEqual(carousel?.items.first?.displayAction?.url, title.url)
        }
        let many = (0..<6).map { index -> ShelfTitle in
            var copy = ShelfTitle(id: String(index), title: "Film", rawTitle: "Film", poster: title.poster,
                                  magnet: nil, downloadLink: nil, tmdbID: index, mediaType: "movie")
            copy.artworkID = title.artworkID
            return copy
        }
        TopShelfStore.save(ShelfSnapshot(server: "http://nas.local/", titles: many))
        ContentProvider().loadTopShelfContent { content in
            XCTAssertEqual((content as? TVTopShelfCarouselContent)?.items.count, 4)
        }
        TopShelfStore.clear()
        ContentProvider().loadTopShelfContent { XCTAssertNil($0) }
    }
}
