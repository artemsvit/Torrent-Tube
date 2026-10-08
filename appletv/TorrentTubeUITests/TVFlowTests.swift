import XCTest

final class TVFlowTests: XCTestCase {
    func testConnectionScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", ""]
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect to your server"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["server-address"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Connection screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLocalServerAndEmbeddedPlayback() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"] else {
            throw XCTSkip("Set TORRENTTUBE_TEST_SERVER to the isolated playback fixture server.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address, "-resumeHistory", ""]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native playback test"].firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(app.buttons["Download"].exists)
        XCTAssertFalse(app.buttons["Pause download"].exists)
        let play = app.buttons["hero-play"]
        for _ in 0..<8 {
            if play.hasFocus { break }
            if app.buttons["Details"].hasFocus { XCUIRemote.shared.press(.left) }
            else if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch.hasFocus { XCUIRemote.shared.press(.up) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCTAssertTrue(play.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        let episode = app.buttons.containing(.staticText, identifier: "Episode 1.mkv").firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 15))
        for _ in 0..<3 { if episode.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(episode.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Embedded MKV player"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        // Pause longer than the legacy socket cleanup window.
        let pause = expectation(description: "pause retains native session")
        DispatchQueue.main.asyncAfter(deadline: .now() + 35) { pause.fulfill() }
        wait(for: [pause], timeout: 40)
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        let forward = app.buttons["seek-forward"]
        for _ in 0..<4 {
            if forward.hasFocus { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(forward.hasFocus)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.select)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement else { return false }
            let components = element.label.split(separator: ":").compactMap { Int($0) }
            return components.count == 2 && (components[0] > 0 || components[1] >= 12)
        }, object: app.staticTexts["playback-position"])
        wait(for: [advanced], timeout: 20)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Native playback test"].firstMatch.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(episode.waitForExistence(timeout: 15))
        for _ in 0..<3 { if episode.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(episode.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 15))
        let resumeShot = XCTAttachment(screenshot: app.screenshot())
        resumeShot.name = "Resume saved position"
        resumeShot.lifetime = .keepAlways
        add(resumeShot)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
    }

    func testChangeServerReturnsToConnectionScreen() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native playback test"].firstMatch.waitForExistence(timeout: 25))
        let settings = app.buttons["Settings"]
        XCUIRemote.shared.press(.up)
        for _ in 0..<6 { if settings.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(settings.hasFocus)
        let storage = app.buttons["Server & Storage"]
        for _ in 0..<6 { if storage.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(storage.hasFocus)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.right)
        let change = app.buttons["setting-Change server"]
        XCTAssertTrue(change.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            if change.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(change.hasFocus)
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "Settings gear and server controls"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Connect to your server"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Change server"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testTitleDetailsAndStreamingOnlyNavigation() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        let details = app.buttons["Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 25))
        for _ in 0..<6 {
            if details.hasFocus { break }
            if app.buttons["hero-play"].hasFocus { XCUIRemote.shared.press(.right) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCTAssertTrue(details.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Download"].exists)
        XCTAssertFalse(app.buttons["Pause download"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Streaming title details"
        shot.lifetime = .keepAlways
        add(shot)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 10))
    }

    func testReferenceServerHomeAndDetails() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else {
            throw XCTSkip("Provide TORRENTTUBE_REFERENCE_SERVER to inspect a real catalog without playing media.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        let details = app.buttons["Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 50))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "TMDB"), object: app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "TMDB")).firstMatch)
        wait(for: [loaded], timeout: 35)
        let homeShot = XCTAttachment(screenshot: app.screenshot())
        homeShot.name = "Real server cinematic Home"
        homeShot.lifetime = .keepAlways
        add(homeShot)
        for _ in 0..<6 {
            if details.hasFocus { break }
            if app.buttons["hero-play"].hasFocus { XCUIRemote.shared.press(.right) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCTAssertTrue(details.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Download"].exists)
        let titleShot = XCTAttachment(screenshot: app.screenshot())
        titleShot.name = "Real server title details"
        titleShot.lifetime = .keepAlways
        add(titleShot)
        XCUIRemote.shared.press(.menu)
    }

    func testPosterFocusReturnsAfterDetails() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address, "-resumeHistory", ""]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        for _ in 0..<6 { if card.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(card.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.hasFocus)
    }

    func testTrailerPlaysInsideTorrentTube() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        let details = app.buttons["Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 25))
        for _ in 0..<6 {
            if details.hasFocus { break }
            if app.buttons["hero-play"].hasFocus { XCUIRemote.shared.press(.right) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCUIRemote.shared.press(.select)
        let trailers = app.buttons["show-trailers"]
        XCTAssertTrue(trailers.waitForExistence(timeout: 15))
        for _ in 0..<5 {
            if trailers.hasFocus { break }
            if app.buttons["title-play"].hasFocus { XCUIRemote.shared.press(.right) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCTAssertTrue(trailers.hasFocus)
        // One press: the English trailer starts at once - no picker screen.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 75))
        let playing = XCTAttachment(screenshot: app.screenshot())
        playing.name = "Trailer playing inside Torrent Tube"
        playing.lifetime = .keepAlways
        add(playing)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement else { return false }
            let parts = element.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && (parts[0] > 0 || parts[1] >= 2)
        }, object: app.staticTexts["playback-position"])
        wait(for: [advanced], timeout: 6)
        let audio = app.buttons["Audio"]
        for _ in 0..<5 { if audio.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(audio.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No tracks available yet."].exists)
        let audioShot = XCTAttachment(screenshot: app.screenshot())
        audioShot.name = "Native trailer audio tracks"
        audioShot.lifetime = .keepAlways
        add(audioShot)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        let subtitles = app.buttons["Subtitles"]
        for _ in 0..<6 { if subtitles.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(subtitles.hasFocus)
        XCUIRemote.shared.press(.select)
        // Subtitles are on from the start now, so Off is a choice, not the focus.
        let off = app.buttons["Off"]
        XCTAssertTrue(off.waitForExistence(timeout: 10))
        let subtitleShot = XCTAttachment(screenshot: app.screenshot())
        subtitleShot.name = "Compact subtitle picker"; subtitleShot.lifetime = .keepAlways; add(subtitleShot)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 15), "closing the trailer returns to the title")
    }

    func testCartoonsNavigationAndTVIcon() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("A real catalog server is needed.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        XCTAssertTrue(app.buttons["Details"].waitForExistence(timeout: 50))
        XCTAssertFalse(app.buttons["Library"].exists)
        let tv = app.buttons["TV Shows"]
        XCUIRemote.shared.press(.up)
        for _ in 0..<6 { if tv.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(tv.hasFocus)
        let tvShot = XCTAttachment(screenshot: app.screenshot())
        tvShot.name = "Focused TV Shows icon"
        tvShot.lifetime = .keepAlways
        add(tvShot)
        XCUIRemote.shared.press(.right)
        let cartoons = app.buttons["Cartoons"]
        XCTAssertTrue(cartoons.hasFocus)
        XCTAssertTrue(app.staticTexts["Cartoons"].firstMatch.waitForExistence(timeout: 10))
        let cartoonShot = XCTAttachment(screenshot: app.screenshot())
        cartoonShot.name = "Cartoons after TV Shows"
        cartoonShot.lifetime = .keepAlways
        add(cartoonShot)
    }

    func testRefinedPosterAndVersionPicker() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 40))
        for _ in 0..<8 { if card.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(card.hasFocus)
        let poster = XCTAttachment(screenshot: app.screenshot())
        poster.name = "Refined focused poster"; poster.lifetime = .keepAlways; add(poster)
        XCUIRemote.shared.press(.select)
        let versions = app.buttons["Choose version"]
        XCTAssertTrue(versions.waitForExistence(timeout: 15))
        for _ in 0..<5 {
            if versions.hasFocus { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(versions.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 15))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "seeders")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40))
        for _ in 0..<4 { if row.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(row.hasFocus)
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "Wide version picker"; picker.lifetime = .keepAlways; add(picker)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(versions.waitForExistence(timeout: 10))
    }

    func testSettingsAndNewTopShelf() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        XCTAssertTrue(app.buttons["Details"].waitForExistence(timeout: 40))
        XCUIRemote.shared.press(.up)
        let settings = app.buttons["Settings"]
        for _ in 0..<7 { if settings.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(settings.hasFocus)
        let shelf = app.buttons["setting-Top Shelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.down)
        if !shelf.hasFocus { XCUIRemote.shared.press(.right) }
        XCTAssertTrue(shelf.hasFocus)
        if shelf.label.contains("Brand artwork") { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(shelf.label.contains("New titles"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home and Top Shelf settings"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCUIRemote.shared.press(.left)
        let playback = app.buttons["Playback"]
        for _ in 0..<4 { if playback.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCTAssertTrue(playback.hasFocus)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.right)
        let skip = app.buttons["setting-Skip"]
        XCTAssertTrue(skip.hasFocus)
        let previous = skip.label
        XCUIRemote.shared.press(.select)
        XCTAssertNotEqual(skip.label, previous)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(skip.label, previous)
        let playerShot = XCTAttachment(screenshot: app.screenshot())
        playerShot.name = "Playback settings"; playerShot.lifetime = .keepAlways; add(playerShot)
        XCUIRemote.shared.press(.home)
        let exited = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.state != .runningForeground }, object: nil)
        wait(for: [exited], timeout: 10)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        // Home may focus Settings after the app is reinstalled. Focus our
        // icon before moving into its shelf instead of assuming the position.
        let appIcon = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Torrent Tube")).firstMatch
        XCTAssertTrue(appIcon.waitForExistence(timeout: 10), springboard.debugDescription)
        for _ in 0..<6 { if appIcon.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(appIcon.hasFocus, springboard.debugDescription)
        let shelfLoaded = expectation(description: "System refreshes the focused app shelf")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { shelfLoaded.fulfill() }
        wait(for: [shelfLoaded], timeout: 5)
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "System Top Shelf"; home.lifetime = .keepAlways; add(home)
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 25))
        let opened = XCTAttachment(screenshot: app.screenshot())
        opened.name = "Title opened from Top Shelf"; opened.lifetime = .keepAlways; add(opened)
    }

    /// Leaving a tab resets it: open a title from Home, switch to Movies and
    /// back, and Home is at its top level again (not on the title).
    func testSwitchingTabsResetsToTopLevel() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address, "-resumeHistory", ""]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        for _ in 0..<6 { if card.hasFocus { break }; XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 15))
        let movies = app.tabBars.buttons["Movies"]
        for _ in 0..<10 { if movies.hasFocus { break }; XCUIRemote.shared.press(.up); if app.tabBars.buttons["Home"].hasFocus { XCUIRemote.shared.press(.right) } }
        XCTAssertTrue(movies.hasFocus, "the tab bar is reachable from a title page")
        XCUIRemote.shared.press(.left)  // back to Home
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["title-play"].exists, "Home is back at its top level")
    }

    /// Search shows results while typing - no Search button to press.
    func testSearchShowsResultsWhileTyping() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("Search needs a real catalog server.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        openSearch(app)
        typeOnKeyboard(app, "dune")
        XCTAssertEqual(app.staticTexts["search-query"].label, "dune")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "results appear while typing")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }

    /// Our keyboard: letters picked with the remote reach the query, the
    /// language key switches to Ukrainian, and focus stays on the keys.
    func testSearchKeyboardWithRemote() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("Search needs a real catalog server.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        openSearch(app)
        XCTAssertTrue(app.buttons["key-a"].hasFocus, "the keyboard has focus first")
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(app.staticTexts["search-query"].label, "ab")
        XCTAssertTrue(app.buttons["key-b"].hasFocus, "typing keeps focus on the key")
        let language = app.buttons["key-language"]
        // 26 letters fill 5 rows of 6; the next row down has space, delete, 123 and the language key.
        for _ in 0..<5 { XCUIRemote.shared.press(.down) }
        for _ in 0..<4 where !language.hasFocus { XCUIRemote.shared.press(.right) }
        XCTAssertTrue(language.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["key-б"].waitForExistence(timeout: 5), "Ukrainian letters")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }

    /// The heart on a title page adds it to Favorites, which lists it.
    func testFavoriteFromTitlePage() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("A real catalog server is needed.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address, "-favorites", ""]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Movies")
        add(keep(app, "Movies"))
        XCUIRemote.shared.press(.right)   // from the tab bar's Movies into the grid
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.select)
        let heart = app.buttons["favorite-toggle"]
        XCTAssertTrue(heart.waitForExistence(timeout: 15))
        XCTAssertEqual(heart.label, "Add to Favorites")
        for _ in 0..<4 { if heart.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(heart.label, "Remove from Favorites")
        XCUIRemote.shared.press(.menu)
        openTab(app, "Library")
        // With nothing on the server yet, Library opens on Favorites; otherwise pick its chip.
        if !app.staticTexts["Movies"].exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch.exists {
            let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch
            if chip.exists && !chip.isSelected {
                for _ in 0..<3 where !chip.hasFocus { XCUIRemote.shared.press(.down) }
                for _ in 0..<4 where !chip.hasFocus { XCUIRemote.shared.press(.right) }
                XCUIRemote.shared.press(.select)
            }
        }
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the favorite is listed")
        add(keep(app, "Favorites"))
    }

    /// Settings and Favorites render with their tabs and columns (screenshots kept).
    func testSettingsAndFavoritesScreens() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("A real catalog server is needed.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", address]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Налаштування")
        add(keep(app, "Settings"))
        openTab(app, "Медіатека")
        add(keep(app, "Library"))
    }

    private func keep(_ app: XCUIApplication, _ name: String) -> XCTAttachment {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; return shot
    }
    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        for _ in 0..<6 { if app.tabBars.buttons.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { break }; XCUIRemote.shared.press(.up) }
        for _ in 0..<8 where !tab.hasFocus {
            let focused = app.tabBars.buttons.allElementsBoundByIndex.first { $0.hasFocus }
            XCUIRemote.shared.press((focused?.frame.minX ?? 0) < tab.frame.minX ? .right : .left)
        }
        XCUIRemote.shared.press(.select)
        sleep(2)
    }
    private func openSearch(_ app: XCUIApplication) {
        let search = app.tabBars.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        for _ in 0..<4 { if app.tabBars.firstMatch.buttons.element(boundBy: 0).hasFocus || search.hasFocus { break }; XCUIRemote.shared.press(.up) }
        for _ in 0..<8 { if search.hasFocus { break }; XCUIRemote.shared.press(.right) }
        XCTAssertTrue(search.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["key-a"].waitForExistence(timeout: 10))  // Select lands on "a"
    }
    /// Walks the 6-column English grid from "a" with the remote.
    private func typeOnKeyboard(_ app: XCUIApplication, _ word: String) {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var current = 0
        for character in word {
            let target = letters.firstIndex(of: character)!
            let rows = target / 6 - current / 6, columns = target % 6 - current % 6
            for _ in 0..<abs(rows) { XCUIRemote.shared.press(rows > 0 ? .down : .up) }
            for _ in 0..<abs(columns) { XCUIRemote.shared.press(columns > 0 ? .right : .left) }
            XCUIRemote.shared.press(.select)
            current = target
        }
    }
}
