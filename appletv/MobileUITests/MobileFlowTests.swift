import XCTest

final class MobileFlowTests: XCTestCase {
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
