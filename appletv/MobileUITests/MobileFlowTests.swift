import XCTest
import UIKit

final class MobileFlowTests: XCTestCase {
    func testIPadPersonNameBesideBack() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad header layout") }
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"] else { throw XCTSkip("Set reference server") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(server: server, language: "uk")
        let details = app.buttons["featured-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 60))
        details.tap()
        let person = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "person-")).firstMatch
        for _ in 0..<8 {
            if person.exists && person.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(person.isHittable)
        person.tap()
        app.scrollViews.firstMatch.swipeUp()
        let name = app.staticTexts["person-floating-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertLessThan(name.frame.midX, app.frame.width / 2)
        XCTAssertLessThan(name.frame.maxY, 150)
        capture("iPad actor name beside Back")
    }

    func testInformationUsesAvailableWidth() throws {
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], !server.isEmpty else { throw XCTSkip("Set reference server") }
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(server: server, language: "uk")
        let details = app.buttons["featured-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 60))
        details.tap()
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 15))
        let scroll = app.scrollViews.firstMatch
        let information = app.otherElements["title-information"]
        for _ in 0..<8 {
            if information.exists, information.frame.maxY < scroll.frame.maxY - 80 { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(information.exists)
        // iPad's sidebar can overlap the scroll view's accessibility frame.
        let available = scroll.frame.maxX - information.frame.minX
        XCTAssertGreaterThan(information.frame.width, available * 0.9)
        capture("Full Width Information Ukrainian")
    }
    func testPlaybackReconnectAndResumeDesign() {
        let app = launch()
        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Native playback test"].firstMatch.tap()
        app.buttons["title-play"].tap()
        XCTAssertTrue(app.buttons["video-file-0"].waitForExistence(timeout: 15))
        capture("Playback File Selection")
        app.buttons["video-file-0"].tap()
        if app.buttons["resume-playback"].waitForExistence(timeout: 3) { app.buttons["resume-playback"].tap() }
        let position = app.staticTexts["playback-position"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in position.exists && position.label != "0:00" }, object: nil)], timeout: 30)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        XCTAssertTrue(app.buttons["reconnect-playback"].waitForExistence(timeout: 10))
        capture("Playback Reconnect Screen")
        app.buttons["reconnect-playback"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 15))
        capture("Playback Resume Screen")
        app.buttons["resume-playback"].tap()
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 15))
        app.buttons["close-player"].tap()
    }
    func testPlayerTrackPanelsMatchDarkDesignAndDismissAfterSelection() {
        let app = launch()
        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Native playback test"].firstMatch.tap()
        app.buttons["title-play"].tap()
        XCTAssertTrue(app.buttons["video-file-0"].waitForExistence(timeout: 15))
        app.buttons["video-file-0"].tap()
        if app.buttons["resume-playback"].waitForExistence(timeout: 3) { app.buttons["resume-playback"].tap() }
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 20))
        // Keep controls visible while the simulator rotates and opens the sheet.
        let toggle = app.buttons["toggle-playback"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: toggle)], timeout: 15)
        toggle.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Play"), object: toggle)], timeout: 5)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["audio-tracks"].tap()
        XCTAssertTrue(app.buttons["track-panel-done"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5) // Capture the settled sheet, after its presentation animation.
        capture("Dark Audio Track Panel")
        let audio = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "audio-track-", "audio-track--1")).firstMatch
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        audio.tap()
        XCTAssertFalse(app.buttons["track-panel-done"].exists)
        app.buttons["subtitle-tracks"].tap()
        let off = app.buttons["subtitle-track--1"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        capture("Dark Subtitle Track Panel")
        off.tap()
        XCTAssertFalse(app.buttons["track-panel-done"].exists)
        XCTAssertTrue(app.buttons["toggle-playback"].isHittable)
        app.buttons["close-player"].tap()
    }
    func testHeroSwipesChangePaginationAndVerticalSwipeScrolls() throws {
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], !server.isEmpty else { throw XCTSkip("Set reference catalog server") }
        let app = launch(server: server)
        let next = app.buttons["hero-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "of 10"), object: next)], timeout: 40)
        let first = next.label
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.35))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.35))
        left.press(forDuration: 0.05, thenDragTo: right)
        XCTAssertNotEqual(next.label, first)
        right.press(forDuration: 0.05, thenDragTo: left)
        XCTAssertEqual(next.label, first)
        capture("Taller Home Hero After Both Swipe Directions")
        let playY = app.buttons["hero-play"].frame.midY
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        bottom.press(forDuration: 0.05, thenDragTo: top)
        XCTAssertLessThan(app.buttons["hero-play"].frame.midY, playY - 40)
    }
    func testHomeCarouselRotatesWithoutTouch() throws {
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], !server.isEmpty else { throw XCTSkip("Set reference catalog server") }
        let app = launch(server: server)
        let next = app.buttons["hero-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        let tenItems = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "of 10"), object: next)
        wait(for: [tenItems], timeout: 40)
        capture("Mobile Home Ten Item Carousel")
        let first = next.label
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: next)], timeout: 7)
        XCTAssertTrue(app.buttons["hero-play"].isHittable)
        XCTAssertTrue(app.buttons["featured-details"].isHittable)
        capture("Mobile Home Automatic Rotation")
    }
    /// iPhone: turning the phone keeps the trailer playing, and the title
    /// page's banner runs edge to edge in landscape.
    func testIPhoneTrailerSurvivesRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone rotation") }
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], !server.isEmpty else { throw XCTSkip("Set reference server") }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(server: server, language: "uk")
        let details = app.buttons["featured-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 60))
        details.tap()
        let trailers = app.buttons["show-trailers"]
        XCTAssertTrue(trailers.waitForExistence(timeout: 30))
        trailers.tap()
        XCTAssertTrue(app.buttons["close-player"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 4)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3)
        capture("Trailer after rotation")
        // The controls hide while it plays: a tap shows them again.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["close-player"].waitForExistence(timeout: 5), "the trailer closed when the phone turned")
        app.buttons["close-player"].tap()
        Thread.sleep(forTimeInterval: 2)
        capture("Title page in landscape")
    }
    private func launch(server: String? = nil, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", server ?? ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"] ?? "http://127.0.0.1:5069", "-appLanguage", language]
        app.launch()
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testConnectionScreenAndScan() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "", "-appLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.textFields["server-address"].waitForExistence(timeout: 15))
        let scan = app.buttons["scan-network"]
        XCTAssertTrue(scan.exists)
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.exists)
        capture("Mobile Connection Screen")
        scan.tap()
        // Wait for scan to finish or populate
        let populated = app.textFields["server-address"].value as? String ?? ""
        if !populated.isEmpty {
            XCTAssertTrue(connect.isEnabled)
        }
    }

    @MainActor func testNumberedEpisodeFixturePlaysSelectedSeasonDirectly() async throws {
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"],
              let base = URL(string: server + "/") else { throw XCTSkip("Set reference server to smoke_server.py --episode-library") }
        let (configData, _) = try await URLSession.shared.data(from: base.appendingPathComponent("api/config"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        guard config["numbered_episode_fixture"] as? Bool == true else { throw XCTSkip("Requires numbered episode fixture") }
        let app = launch(server: server)
        XCUIDevice.shared.orientation = .landscapeLeft
        let show = app.buttons["Numbered episode playback test"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 30))
        show.tap()
        let season = app.buttons["season-12"]
        if !season.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(season.waitForExistence(timeout: 10))
        if !season.isHittable { app.swipeUp() }
        season.tap()
        let episode = app.buttons["episode-3"]
        XCTAssertTrue(episode.waitForExistence(timeout: 10))
        if !episode.isHittable { app.swipeUp() }
        episode.tap()
        if app.buttons["resume-playback"].waitForExistence(timeout: 2) { app.buttons["resume-playback"].tap() }
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["video-file-0"].exists)
        let position = app.staticTexts["playback-position"]
        let started = expectation(for: NSPredicate { _, _ in position.exists && position.label != "0:00" }, evaluatedWith: nil)
        await fulfillment(of: [started], timeout: 30)
        let (sessionData, _) = try await URLSession.shared.data(from: base.appendingPathComponent("fixture-selected-episode"))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: sessionData) as? [String: Any])
        let sessions = try XCTUnwrap(payload["sessions"] as? [[String: Any]])
        XCTAssertTrue(sessions.contains { $0["file"] as? Int == 5 && ($0["torrent_id"] as? String)?.contains("Numbered episode playback test") == true })
        capture("Season 12 Episode 3 Direct Playback")
        app.buttons["close-player"].tap()
        XCUIDevice.shared.orientation = .portrait
    }

    func testSearchPresentation() {
        let app = launch(language: "uk")
        XCTAssertTrue(app.buttons["open-search"].firstMatch.waitForExistence(timeout: 25))
        app.buttons["open-search"].firstMatch.tap()
        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 10))
        capture("iPhone Search Screen Pinned")
        let close = app.buttons["close-search"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.buttons["open-search"].firstMatch.waitForExistence(timeout: 5))
        capture("iPhone Returned To Home")
    }

    func testSettingsAndVersionSheetStyling() {
        let app = launch(language: "uk")
        XCTAssertTrue(app.buttons["settings"].firstMatch.waitForExistence(timeout: 25))
        app.buttons["settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["done-settings"].waitForExistence(timeout: 8))
        capture("Settings Screen Translucent Blocks")
        app.buttons["done-settings"].tap()

        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Native playback test"].firstMatch.tap()
        XCTAssertTrue(app.buttons["choose-version"].waitForExistence(timeout: 10))
        app.buttons["choose-version"].tap()
        XCTAssertTrue(app.buttons["cancel-version"].waitForExistence(timeout: 8))
        capture("Choose Version Screen Custom Cards")
        app.buttons["cancel-version"].tap()
    }

    func testConnectionAndLibraryDetails() {
        let app = launch()
        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 30))
        capture("iPhone Home")
        app.buttons["Native playback test"].firstMatch.tap()
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["favorite-toggle"].exists)
        capture("iPhone Details")
        app.buttons["favorite-toggle"].tap()
        XCTAssertEqual(app.buttons["favorite-toggle"].label, "Remove from Favorites")
        app.buttons["favorite-toggle"].tap()
    }
    func testAudioActivationPlaybackLifecycle() {
        let app = launch()
        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Native playback test"].firstMatch.tap()
        for _ in 0..<2 {
            app.buttons["show-trailers"].tap()
            let toggle = app.buttons["toggle-playback"]
            let position = app.staticTexts["playback-position"]
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                toggle.exists && toggle.isEnabled && toggle.label == "Pause" && position.label != "0:00"
            }, object: nil)], timeout: 30)
            toggle.tap()
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Play"), object: toggle)], timeout: 5)
            let pausedPosition = position.label
            toggle.tap()
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                toggle.isEnabled && toggle.label == "Pause" && position.label != pausedPosition
            }, object: nil)], timeout: 15)
            capture("Audio Session Playback After Resume")
            app.buttons["close-player"].tap()
            XCTAssertTrue(app.buttons["show-trailers"].waitForExistence(timeout: 10))
        }
    }

    func testEmbeddedPlaybackAndResume() {
        let app = launch()
        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Native playback test"].firstMatch.tap()
        app.buttons["title-play"].tap()
        XCTAssertTrue(app.buttons["video-file-0"].waitForExistence(timeout: 15))
        app.buttons["video-file-0"].tap()
        if app.buttons["resume-playback"].waitForExistence(timeout: 3) { app.buttons["resume-playback"].tap() }
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 20))
        let position = app.staticTexts["playback-position"]
        let started = NSPredicate { _, _ in position.exists && position.label != "0:00" }
        expectation(for: started, evaluatedWith: nil)
        waitForExpectations(timeout: 30)
        app.buttons["seek-forward"].tap()
        app.buttons["seek-forward"].tap()
        app.buttons["toggle-playback"].tap()
        capture("Native MKV Playback")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("Landscape Playback")
        XCUIDevice.shared.press(.home)
        let expired = expectation(description: "Background longer than the server lease")
        DispatchQueue.main.asyncAfter(deadline: .now() + 95) { expired.fulfill() }
        wait(for: [expired], timeout: 100)
        app.activate()
        XCTAssertTrue(app.buttons["Reconnect and resume"].waitForExistence(timeout: 10))
        app.buttons["Reconnect and resume"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 15))
        capture("Resume after background")
        XCUIDevice.shared.orientation = .portrait
    }
    func testTrailerAndSettings() {
        let app = launch()
        XCTAssertTrue(app.buttons["Native playback test"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Native playback test"].firstMatch.tap()
        app.buttons["show-trailers"].tap()
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 20))
        capture("Trailer")
        app.buttons["close-player"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Skip interval"].waitForExistence(timeout: 5))
        capture("Settings")
        app.buttons["Change server"].tap()
        XCTAssertTrue(app.textFields["server-address"].waitForExistence(timeout: 10))
    }
    func testReferenceCatalogScreens() throws {
        guard let server = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], !server.isEmpty else { throw XCTSkip("Set reference server for artwork checks") }
        let app = launch(server: server, language: "uk")
        XCTAssertTrue(app.buttons["settings"].firstMatch.waitForExistence(timeout: 30))
        // Wait for network-backed shelves before capturing the real catalog.
        let details = app.buttons["featured-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 90))
        capture("Reference Catalog Ukrainian")
        details.tap()
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 10))
        capture("Reference Details Ukrainian")
    }
}
