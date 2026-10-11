import XCTest

final class TVFlowTests: XCTestCase {
    func testHomeDownFocusesPlayBeforeDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        let play = app.buttons["hero-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-tab-"))
        for _ in 0..<3 {
            if tabs.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(tabs.allElementsBoundByIndex.contains { $0.hasFocus })
        XCUIRemote.shared.press(.down)
        let focusedPlay = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.hasFocus }, object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [focusedPlay], timeout: 3), .completed)
        XCUIRemote.shared.press(.right)
        let details = app.buttons["Деталі"]
        let focusedDetails = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in details.hasFocus }, object: details)
        XCTAssertEqual(XCTWaiter.wait(for: [focusedDetails], timeout: 3), .completed)
    }

    func testLibraryBackKeepsCategoryBeforeReturningHome() {
        checkLibraryBack(sections: ["movie", "tv", "cartoon", "favorites"])
    }

    func testLibraryTVShowBackFocusesCategoryWithoutExtraPress() {
        checkLibraryBack(sections: ["tv"])
    }

    private func checkLibraryBack(sections: [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 45))
        for section in sections {
            openTab(app, "Медіатека")
            let tv = app.buttons["library-chip-\(section)"]
            XCTAssertTrue(tv.waitForExistence(timeout: 20))
            for _ in 0..<10 {
                if tv.hasFocus { break }
                let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-chip-")).allElementsBoundByIndex.first { $0.hasFocus }
                if let focused { XCUIRemote.shared.press(focused.frame.midX < tv.frame.midX ? .right : .left) }
                else if app.buttons["main-tab-library"].hasFocus { XCUIRemote.shared.press(.down) }
                else { XCUIRemote.shared.press(.up) }
            }
            XCTAssertTrue(tv.hasFocus, app.debugDescription)
            XCUIRemote.shared.press(.select)
            XCUIRemote.shared.press(.down)
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-"))
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
            XCTAssertTrue(cards.allElementsBoundByIndex.contains { $0.hasFocus }, app.debugDescription)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 30))
            // Back may first scroll the title to its top, then must pop to its Library category.
            for _ in 0..<3 {
                if !app.buttons["title-play"].exists { break }
                XCUIRemote.shared.press(.menu)
                // Let the pop finish before sending another remote press.
                if tv.waitForExistence(timeout: 2) { break }
            }
            XCTAssertTrue(app.buttons["main-tab-library"].isSelected)
            XCTAssertTrue(tv.exists)
            XCTAssertTrue(tv.isSelected)
            let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-chip-"))
            let focusedCategory = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                chips.allElementsBoundByIndex.contains { $0.hasFocus }
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [focusedCategory], timeout: 5), .completed)
            XCTAssertTrue(chips.allElementsBoundByIndex.contains { $0.hasFocus }, app.debugDescription)
            XCTAssertTrue(app.buttons["main-tab-library"].isSelected)
            add(keep(app, "Back preserves Library \(section) category"))
            XCUIRemote.shared.press(.menu)
            let homeSelected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["main-tab-home"].isSelected }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [homeSelected], timeout: 3), .completed)
        }
    }

    func testFinalEpisodeClosesPlayerAndKeepsTitleScreen() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_COMPLETION_SERVER"] else {
            throw XCTSkip("Set TORRENTTUBE_COMPLETION_SERVER to smoke_server.py with an eight-second sample.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address, "-resumeHistory", "",
                               "-seekInterval", "30", "-autoplayHomeTrailers", "NO", "-showContinueWatching", "NO"]
        app.launch()
        let details = app.buttons["Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 30))
        for _ in 0..<8 {
            if details.hasFocus { break }
            if app.buttons["hero-play"].hasFocus { XCUIRemote.shared.press(.right) }
            else if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch.hasFocus { XCUIRemote.shared.press(.up) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCTAssertTrue(details.hasFocus)
        XCUIRemote.shared.press(.select)
        let titlePlay = app.buttons["title-play"]
        XCTAssertTrue(titlePlay.waitForExistence(timeout: 15))
        for _ in 0..<5 where !titlePlay.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(titlePlay.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        let toggle = app.buttons["toggle-playback"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        func waitForPosition(_ minimum: Int) {
            let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let position = app.staticTexts["playback-position"]
                guard position.exists else { return false }
                return position.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) } >= minimum
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 20), .completed)
        }
        waitForPosition(3)
        add(keep(app, "Episode before completion"))
        let next = app.staticTexts["playback-episode"]
        let continued = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            next.exists && next.label == "Season 1 · Episode 2"
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [continued], timeout: 25), .completed, app.debugDescription)
        add(keep(app, "Automatic next episode"))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            titlePlay.exists && titlePlay.isHittable && !app.buttons["playback-timeline"].exists &&
                !app.buttons["Show playback controls"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 25), .completed)
        XCTAssertTrue(titlePlay.exists)
        XCTAssertFalse(app.buttons["hero-play"].isHittable)
        XCTAssertFalse(app.buttons["resume-playback"].exists)
        add(keep(app, "Final episode returns to title details"))
    }

    func testResumePromptLayoutAndRemoteActions() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        func openPlayback() {
            let play = app.buttons["hero-play"]
            XCTAssertTrue(play.waitForExistence(timeout: 30))
            for _ in 0..<8 {
                if play.hasFocus { break }
                if app.buttons["Деталі"].exists && app.buttons["Деталі"].hasFocus { XCUIRemote.shared.press(.left) }
                else if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch.hasFocus { XCUIRemote.shared.press(.up) }
                else { XCUIRemote.shared.press(.down) }
            }
            XCTAssertTrue(play.hasFocus, app.debugDescription)
            XCUIRemote.shared.press(.select)
        }
        func positionAtLeast(_ seconds: Int) {
            let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let text = app.staticTexts["playback-position"]
                guard text.exists else { return false }
                return text.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) } >= seconds
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 20), .completed)
        }
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", address,
                               "-resumeHistory", "", "-seekInterval", "10", "-autoplayHomeTrailers", "NO", "-showContinueWatching", "NO"]
        app.launch()
        openPlayback()
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 20))
        positionAtLeast(3)
        XCUIRemote.shared.press(.up)
        for _ in 0..<3 { XCUIRemote.shared.press(.right) }
        positionAtLeast(25)
        XCUIRemote.shared.press(.menu)
        app.terminate()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", address, "-autoplayHomeTrailers", "NO", "-showContinueWatching", "NO"]
        app.launch()
        openPlayback()
        let resume = app.buttons["resume-playback"]
        let restart = app.buttons["restart-playback"]
        let back = app.buttons["resume-back"]
        let timestamp = app.staticTexts["resume-position"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCTAssertTrue(resume.hasFocus, app.debugDescription)
        XCTAssertTrue(timestamp.exists)
        XCTAssertFalse(app.buttons["resume-position"].exists)
        XCTAssertLessThan(timestamp.frame.maxY, resume.frame.minY)
        XCTAssertGreaterThan(back.frame.minY, max(resume.frame.maxY, restart.frame.maxY) + 15)
        XCTAssertEqual((resume.frame.minX + restart.frame.maxX) / 2, app.frame.midX, accuracy: 40)
        add(keep(app, "Centered Ukrainian resume prompt"))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(restart.hasFocus)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(back.hasFocus)
        add(keep(app, "Resume Back action focus"))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 10))
        openPlayback()
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.select)
        positionAtLeast(25)
        XCUIRemote.shared.press(.menu)
        openPlayback()
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(restart.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["toggle-playback"].waitForExistence(timeout: 15))
        let start = app.staticTexts["playback-position"].label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        XCTAssertLessThan(start, 10)
        XCUIRemote.shared.press(.menu)
    }

    func testPlayerTimelineFocusAndRemoteSeeking() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["TORRENTTUBE_TEST_SERVER"])
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address,
                               "-resumeHistory", "", "-seekInterval", "10", "-autoplayHomeTrailers", "NO"]
        app.launch()
        let play = app.buttons["hero-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        for _ in 0..<8 {
            if play.hasFocus { break }
            if app.buttons["Details"].hasFocus { XCUIRemote.shared.press(.left) }
            else if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-")).firstMatch.hasFocus { XCUIRemote.shared.press(.up) }
            else { XCUIRemote.shared.press(.down) }
        }
        XCTAssertTrue(play.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        let episode = app.buttons.containing(.staticText, identifier: "Episode 1.mkv").firstMatch
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            episode.exists || app.buttons["Pause"].exists || app.buttons["Resume"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 20), .completed, app.debugDescription)
        if episode.exists {
            for _ in 0..<4 where !episode.hasFocus { XCUIRemote.shared.press(.down) }
            XCTAssertTrue(episode.hasFocus)
            XCUIRemote.shared.press(.select)
        }
        if app.buttons["Resume"].exists {
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20))
        let running = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let parts = app.staticTexts["playback-position"].label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 3
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 15), .completed)
        let timeline = app.descendants(matching: .any).matching(identifier: "playback-timeline").firstMatch
        guard timeline.waitForExistence(timeout: 5) else {
            XCTFail("The player needs a focusable timeline")
            return
        }
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(timeline.hasFocus, app.debugDescription)
        add(keep(app, "Focused playback timeline"))
        let position = app.staticTexts["playback-position"]
        func seconds() -> Int {
            position.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        }
        func waitForPosition(_ condition: @escaping (Int) -> Bool) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition(seconds()) }, object: position)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        }
        let start = seconds()
        XCUIRemote.shared.press(.right)
        waitForPosition { $0 >= start + 8 }
        let first = seconds()
        XCUIRemote.shared.press(.right)
        waitForPosition { $0 >= first + 8 }
        let second = seconds()
        XCUIRemote.shared.press(.left)
        waitForPosition { $0 <= second - 8 }
        XCTAssertTrue(timeline.hasFocus)

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.buttons["toggle-playback"].hasFocus)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(app.buttons["seek-backward"].hasFocus)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["toggle-playback"].hasFocus)
        // Once controls hide, a direction press must both seek and focus the timeline.
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !timeline.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 12), .completed)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        let refocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in timeline.hasFocus }, object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [refocused], timeout: 5), .completed)
        let revealed = seconds()
        XCUIRemote.shared.press(.right)
        waitForPosition { $0 >= revealed + 8 }
        let advanced = seconds()
        XCUIRemote.shared.press(.left)
        waitForPosition { $0 <= advanced - 6 }
        XCTAssertTrue(timeline.hasFocus)
        add(keep(app, "Remote seeking after controls hide"))
        XCUIRemote.shared.press(.playPause)
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["toggle-playback"].label == "Play"
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
        let pausedStart = seconds()
        XCUIRemote.shared.press(.right)
        waitForPosition { $0 >= pausedStart + 8 }
        XCUIRemote.shared.press(.right)
        waitForPosition { $0 >= pausedStart + 18 }
        XCUIRemote.shared.press(.left)
        waitForPosition { $0 >= pausedStart + 8 && $0 <= pausedStart + 12 }
        XCTAssertEqual(app.buttons["toggle-playback"].label, "Play")
        let selected = seconds()
        add(keep(app, "Paused timeline selection"))
        XCUIRemote.shared.press(.select)
        waitForPosition { $0 >= selected + 2 }
        XCTAssertEqual(app.buttons["toggle-playback"].label, "Pause")
        XCUIRemote.shared.press(.menu)
    }

    func testBackScrollsUpThenReturnsHomeThenExits() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Library")
        for _ in 0..<8 { XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["main-tab-library"].isSelected)
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-chip-"))
        let categoryFocused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in chips.allElementsBoundByIndex.contains { $0.hasFocus } }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [categoryFocused], timeout: 5), .completed)
        let heading = app.staticTexts["library-heading"]
        expectation(for: NSPredicate { _, _ in heading.frame.minY > 100 && heading.frame.minY < 300 }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        add(keep(app, "Back returns Library to top"))
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["main-tab-home"].isSelected)
        XCTAssertTrue(app.buttons["main-tab-home"].hasFocus)
        XCUIRemote.shared.press(.menu)
        expectation(for: NSPredicate { _, _ in app.state != .runningForeground }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
    }

    func testBackFromScrolledHomeUsesThreePresses() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        for _ in 0..<9 { XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["main-tab-home"].hasFocus)
        let hero = app.staticTexts["hero-title"]
        expectation(for: NSPredicate { _, _ in hero.frame.minY > 100 && hero.frame.minY < 750 }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.state, .runningForeground)
        XCUIRemote.shared.press(.menu)
        expectation(for: NSPredicate { _, _ in app.state != .runningForeground }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
    }

    func testHomeShelvesCanMoveBackUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", "http://192.168.0.102:5058"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        for _ in 0..<9 { XCUIRemote.shared.press(.down) }
        let focused = app.buttons.allElementsBoundByIndex.first { $0.hasFocus }
        XCTAssertNotNil(focused, app.debugDescription)
        let lowerID = focused?.identifier
        XCUIRemote.shared.press(.up)
        let moved = NSPredicate { _, _ in
            guard let next = app.buttons.allElementsBoundByIndex.first(where: { $0.hasFocus }) else { return false }
            return next.identifier != lowerID
        }
        expectation(for: moved, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let upperID = app.buttons.allElementsBoundByIndex.first { $0.hasFocus }?.identifier
        // A released key must not pull focus back to the lower shelf.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.buttons.allElementsBoundByIndex.first { $0.hasFocus }?.identifier, upperID)
        add(keep(app, "Home moves up without returning to lower shelf"))
    }

    func testPlayerLicenseLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058"]
        app.launch()
        XCTAssertTrue(app.buttons["main-tab-settings"].waitForExistence(timeout: 30))
        openTab(app, "Settings")
        let playback = app.buttons["Playback"]
        for _ in 0..<8 {
            if playback.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(playback.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.right)
        let licenses = app.buttons["Player licenses"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if licenses.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(licenses.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        let heading = app.staticTexts["license-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(heading.frame.minY, app.buttons["main-tab-settings"].frame.maxY + 30)
        add(keep(app, "Readable player license"))
        let back = app.buttons["license-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if back.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(back.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
        XCTAssertFalse(heading.exists)
        for _ in 0..<5 {
            if licenses.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(licenses.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["settings-heading"].waitForExistence(timeout: 5))
        XCTAssertFalse(heading.exists)
    }

    func testSearchFocusKeepsCustomKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058"]
        app.launch()
        XCTAssertTrue(app.buttons["main-tab-search"].waitForExistence(timeout: 30))
        openTab(app, "Search")
        let field = app.descendants(matching: .any).matching(identifier: "search-query").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if field.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(field.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let firstKey = app.buttons["key-a"]
        XCTAssertTrue(firstKey.exists)
        XCUIRemote.shared.press(.down)
        let focusedKey = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "key-")).allElementsBoundByIndex.first { $0.hasFocus }
        XCTAssertNotNil(focusedKey, app.debugDescription)
        let letter = focusedKey?.label
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(field.label, letter)
        add(keep(app, "Search focus with custom keyboard"))
    }

    func testSingleNavigationMenuAndUkrainianScreenSpacing() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", "http://192.168.0.102:5058"]
        app.launch()
        let settings = app.buttons["main-tab-settings"], search = app.buttons["main-tab-search"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        let home = app.buttons["main-tab-home"], library = app.buttons["main-tab-library"]
        XCTAssertLessThan(home.frame.maxX, library.frame.minX)
        XCTAssertLessThan(search.frame.maxX, settings.frame.minX)
        XCTAssertLessThan(library.frame.maxX, search.frame.minX)
        XCTAssertEqual(home.label, "Головна")
        add(keep(app, "Ukrainian navigation"))
        openTab(app, "Фільми")
        XCTAssertTrue(app.buttons["main-tab-movies"].isSelected)
        openTab(app, "Медіатека")
        XCTAssertTrue(app.buttons["main-tab-library"].isSelected)
        openTab(app, "Пошук")
        XCTAssertTrue(app.buttons["key-а"].waitForExistence(timeout: 10) || app.buttons["key-a"].exists)
        let firstKey = app.buttons["key-а"].exists ? app.buttons["key-а"] : app.buttons["key-a"]
        XCTAssertGreaterThan(firstKey.frame.minY, search.frame.maxY + 40)
        add(keep(app, "Search below navigation"))
        openTab(app, "Налаштування")
        let heading = app.staticTexts["settings-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(heading.frame.minY, settings.frame.maxY + 20)
        add(keep(app, "Settings below navigation"))
    }

    func testConnectionScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", ""]
        app.launch()
        XCTAssertTrue(app.textFields["server-address"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["scan-network"].exists)
        XCTAssertTrue(app.buttons["connect"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Connection screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNetworkScanOnAppleTV() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", ""]
        app.launch()
        let scan = app.buttons["scan-network"]
        XCTAssertTrue(scan.waitForExistence(timeout: 15))
        for _ in 0..<3 {
            if scan.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(scan.hasFocus)
        XCUIRemote.shared.press(.select)
        // If server is found, focus shifts to connect button and text field is pre-populated
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        let populated = app.textFields["server-address"].value as? String ?? ""
        if !populated.isEmpty {
            XCTAssertTrue(connect.hasFocus)
        }
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
        XCTAssertTrue(app.staticTexts["hero-rating"].waitForExistence(timeout: 35))
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

    func testHomeInlineTrailerControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://127.0.0.1:5069", "-autoplayHomeTrailers", "NO"]
        app.launch()
        let play = app.buttons["hero-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        let trailer = app.buttons["hero-trailer"]
        for _ in 0..<4 where !play.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(play.hasFocus, app.debugDescription)
        for _ in 0..<4 where !trailer.hasFocus { XCUIRemote.shared.press(.right) }
        XCTAssertTrue(trailer.hasFocus)
        XCUIRemote.shared.press(.select)
        let mute = app.buttons["hero-preview-mute"]
        XCTAssertTrue(mute.waitForExistence(timeout: 20))
        XCTAssertEqual(mute.label, "Unmute preview")
        let running = expectation(description: "Inline clip renders")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { running.fulfill() }
        wait(for: [running], timeout: 6)
        add(keep(app, "Home Inline Trailer"))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(mute.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(mute.label, "Mute preview")
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(trailer.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(mute.exists)
        XCTAssertEqual(trailer.label, "Trailer")
    }

    func testHomeFeaturedCarouselAdvancesEveryFiveSeconds() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("A catalog server with ten titles is needed.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        let next = app.buttons["hero-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        let tenItems = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "of 10"), object: next)
        wait(for: [tenItems], timeout: 40)
        let play = app.buttons["hero-play"]
        for _ in 0..<4 where !play.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(play.hasFocus)
        XCTAssertGreaterThan(next.frame.minX, app.buttons["hero-trailer"].frame.maxX + 200)
        XCTAssertGreaterThan(next.frame.maxX, app.frame.maxX - 160)
        add(keep(app, "Home Ten Titles Right Aligned"))
        let first = next.label
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: next)], timeout: 7)
        let second = next.label
        let started = Date()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", second), object: next)], timeout: 7)
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 3.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 7)
        XCTAssertTrue(play.hasFocus, "Automatic rotation keeps focus on the same action")
        add(keep(app, "Home Automatic Carousel Rotation"))
    }

    func testHomeFeaturedCarouselWithRemote() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("A real catalog server is needed.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", address, "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-next"].waitForExistence(timeout: 40))
        let play = app.buttons["hero-play"]
        for _ in 0..<4 where !play.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(play.hasFocus)
        add(keep(app, "Home Featured Carousel First"))
        let firstTitle = app.staticTexts["hero-title"].label
        let next = app.buttons["hero-next"]
        for _ in 0..<4 where !next.hasFocus { XCUIRemote.shared.press(.right) }
        XCTAssertTrue(next.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        let updated = expectation(description: "Second featured title")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updated.fulfill() }
        wait(for: [updated], timeout: 5)
        add(keep(app, "Home Featured Carousel Second"))
        XCTAssertNotEqual(app.staticTexts["hero-title"].label, firstTitle)
        XCTAssertTrue(next.hasFocus, "Changing the banner keeps remote focus")
    }

    func testBannerTopShelfPresentation() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("A real catalog server is needed.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "uk", "-serverAddress", address]
        app.launch()
        guard app.buttons["hero-play"].waitForExistence(timeout: 40) else { XCTFail("Home did not load"); return }
        XCUIRemote.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        XCTAssertTrue(home.wait(for: .runningForeground, timeout: 10))
        // PineBoard can restore either the Dock or its full-screen carousel.
        XCUIRemote.shared.press(.menu)
        let settled = expectation(description: "Top Shelf loads")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { settled.fulfill() }
        wait(for: [settled], timeout: 10)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Banner Top Shelf Home"; shot.lifetime = .keepAlways; add(shot)
        XCUIRemote.shared.press(.up)
        let full = expectation(description: "Full screen carousel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { full.fulfill() }
        wait(for: [full], timeout: 5)
        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expanded.name = "Banner Top Shelf Full Screen"; expanded.lifetime = .keepAlways; add(expanded)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["title-play"].waitForExistence(timeout: 25), "More Info opens the selected title")
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
        let movies = app.buttons["Movies"]
        for _ in 0..<10 { if movies.hasFocus { break }; XCUIRemote.shared.press(.up); if app.buttons["Home"].hasFocus { XCUIRemote.shared.press(.right) } }
        XCTAssertTrue(movies.hasFocus, "the tab bar is reachable from a title page")
        XCUIRemote.shared.press(.left)  // back to Home
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["title-play"].exists, "Home is back at its top level")
    }

    func testSearchEmptyLayoutStaysWide() throws {
        guard let address = ProcessInfo.processInfo.environment["TORRENTTUBE_REFERENCE_SERVER"], address.hasPrefix("http") else { throw XCTSkip("Search needs a real catalog server.") }
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", address]
        app.launch()
        openSearch(app)
        let keyboardX = app.buttons["key-language"].frame.minX
        typeOnKeyboard(app, "zzzzzz")
        let empty = app.staticTexts["search-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 45))
        XCTAssertEqual(app.buttons["key-language"].frame.minX, keyboardX, accuracy: 2, "Empty results must not move the keyboard")
        XCTAssertGreaterThan(empty.frame.minX, app.staticTexts["search-query"].frame.maxX)
        XCTAssertFalse(app.staticTexts["Torrents"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Search Empty Layout"; shot.lifetime = .keepAlways; add(shot)
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
        XCUIRemote.shared.press(.down)   // from the tab bar to the chips
        XCUIRemote.shared.press(.down)   // to the first poster
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

    /// Up from a scrolled tab lands on that tab in the bar, not on Home.
    func testUpFromScrolledTabFocusesThatTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Movies")
        for _ in 0..<4 { XCUIRemote.shared.press(.down); usleep(400_000) }
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-tab-"))
        for _ in 0..<8 where !tabs.allElementsBoundByIndex.contains(where: { $0.hasFocus }) {
            XCUIRemote.shared.press(.up); usleep(400_000)
        }
        XCTAssertTrue(app.buttons["main-tab-movies"].hasFocus, app.debugDescription)
    }

    /// Down reaches the posters from a chip far to the right (Favorites).
    func testLibraryDownFromFavoritesChip() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Library")
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        // Opening the Library focuses its first chip.
        for _ in 0..<6 where !chip.hasFocus { XCUIRemote.shared.press(.right); usleep(400_000) }
        XCTAssertTrue(chip.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select); usleep(800_000)
        XCUIRemote.shared.press(.down); usleep(600_000)
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "title-"))
        XCTAssertTrue(posters.allElementsBoundByIndex.contains { $0.hasFocus }, "Down from the Favorites chip reaches no poster")
        // One flat grid: no group headings.
        XCTAssertFalse(app.staticTexts["TV Shows"].exists)
    }

    /// Switching between a long and a short Library list keeps the page at
    /// its top; it used to drift down past the top with each switch.
    func testLibraryChipSwitchesKeepPageAtTop() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Library")
        let heading = app.staticTexts["library-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
        let top = heading.frame.minY
        let chips = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " · "))
        for _ in 0..<4 { XCUIRemote.shared.press(.down); usleep(500_000) }
        for _ in 0..<8 where !chips.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { XCUIRemote.shared.press(.up); usleep(500_000) }
        let favorites = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch
        for round in 0..<4 {
            // Over to Favorites and pick it, then back to the first chip and pick it.
            for _ in 0..<5 where !favorites.hasFocus { XCUIRemote.shared.press(.right); usleep(350_000) }
            XCUIRemote.shared.press(.select); usleep(900_000)
            print("PROBE round \(round) favorites heading=\(heading.frame.minY) top=\(top)")
            XCTAssertLessThan(abs(heading.frame.minY - top), 80, "Favorites moved the page")
            for _ in 0..<5 { XCUIRemote.shared.press(.left); usleep(350_000) }
            XCUIRemote.shared.press(.select); usleep(900_000)
            print("PROBE round \(round) movies heading=\(heading.frame.minY)")
            XCTAssertLessThan(abs(heading.frame.minY - top), 80, "Movies moved the page")
        }
        add(keep(app, "Library after chip switches"))
    }

    /// Controls hide after a timeline seek too; Back hides them first and
    /// closes the player only on the second press.
    func testPlayerControlsHideAfterSeekAndBackHidesFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Library")
        XCUIRemote.shared.press(.down); sleep(1)
        XCUIRemote.shared.press(.select)
        let play = app.buttons["title-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        for _ in 0..<4 where !play.hasFocus { XCUIRemote.shared.press(.up) }
        XCUIRemote.shared.press(.select)
        if app.buttons["restart-playback"].waitForExistence(timeout: 8) { XCUIRemote.shared.press(.right); XCUIRemote.shared.press(.select) }
        let timeline = app.descendants(matching: .any)["playback-timeline"]
        sleep(3)
        for _ in 0..<4 where !(timeline.exists && timeline.hasFocus) { XCUIRemote.shared.press(.up); usleep(600_000) }
        XCTAssertTrue(timeline.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.right); XCUIRemote.shared.press(.right)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !timeline.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 14), .completed, "Controls stayed after a timeline seek")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        let hiddenByBack = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !timeline.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenByBack], timeout: 3), .completed, "Back did not hide the controls")
        // Still playing: Up shows the controls again.
        sleep(1)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), "Back closed the player instead of hiding the controls")
        XCUIRemote.shared.press(.menu); sleep(1)
        XCUIRemote.shared.press(.menu)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.exists && play.isHittable }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed, "The second Back did not close the player")
        XCUIRemote.shared.press(.up); sleep(1)
        XCTAssertFalse(timeline.exists, "The player is still open")
    }

    /// The resume prompt starts from the beginning by itself after its
    /// countdown; any press stops the countdown.
    func testResumePromptCountdownStartsFromBeginning() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Library")
        XCUIRemote.shared.press(.down); sleep(1)
        XCUIRemote.shared.press(.select)
        let play = app.buttons["title-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        func focusPlay() {
            sleep(2)  // focus settles after the player closes
            let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-tab-"))
            for _ in 0..<6 where !play.hasFocus {
                let direction: XCUIRemote.Button = tabs.allElementsBoundByIndex.contains { $0.hasFocus } ? .down
                    : app.buttons["show-trailers"].hasFocus || app.buttons["favorite-toggle"].hasFocus ? .left : .up
                XCUIRemote.shared.press(direction)
                usleep(500_000)
            }
            XCTAssertTrue(play.hasFocus, "Play has no focus")
        }
        focusPlay()
        // Play a little, so the title has a saved place, then leave.
        XCUIRemote.shared.press(.select)
        if app.buttons["resume-playback"].waitForExistence(timeout: 8) { XCUIRemote.shared.press(.select) }
        let position = app.staticTexts["playback-position"]
        sleep(15)
        XCUIRemote.shared.press(.menu); usleep(500_000)
        if position.exists { XCUIRemote.shared.press(.menu) }
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)

        // Untouched: the countdown runs out and playback starts from 0.
        focusPlay()
        XCUIRemote.shared.press(.select)
        let countdown = app.descendants(matching: .any)["restart-countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 15), "No countdown on the resume prompt")
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.buttons["resume-playback"].exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 11), .completed, "The countdown did not start playback")
        sleep(20)  // long enough for a saved place, so the prompt comes back below
        XCUIRemote.shared.press(.up); usleep(800_000)
        let seconds = position.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        print("PROBE after countdown position=\(position.label)")
        XCTAssertLessThan(seconds, 35, "Playback did not start from the beginning")
        // Controls are showing: Back hides them, the second Back closes.
        XCUIRemote.shared.press(.menu); sleep(1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)

        // A press stops the countdown: the prompt stays.
        focusPlay()
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(countdown.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.right)
        sleep(9)
        XCTAssertTrue(app.buttons["resume-playback"].exists, "The prompt went away after a press")
        XCTAssertFalse(countdown.exists)
        XCUIRemote.shared.press(.menu)
    }

    /// Back from an episode keeps the page where it was: focus on that
    /// episode, no jump up to Play.
    func testBackFromEpisodeKeepsPageAtEpisodes() {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-serverAddress", "http://192.168.0.102:5058", "-autoplayHomeTrailers", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["hero-play"].waitForExistence(timeout: 30))
        openTab(app, "Library")
        let tvChip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "TV Shows · ")).firstMatch
        XCTAssertTrue(tvChip.waitForExistence(timeout: 15)); sleep(1)
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-tab-"))
        for _ in 0..<8 where !tvChip.hasFocus { XCUIRemote.shared.press(tabs.allElementsBoundByIndex.contains { $0.hasFocus } ? .down : .right); usleep(500_000) }
        XCUIRemote.shared.press(.select); sleep(2)
        XCUIRemote.shared.press(.down); usleep(600_000)
        func focused() -> XCUIElement? { app.buttons.allElementsBoundByIndex.first { $0.hasFocus } }
        for i in 0..<30 { if focused()?.label == "Доктор Хаус" { break }; XCUIRemote.shared.press(i % 12 == 11 ? .down : .right); usleep(350_000) }
        XCUIRemote.shared.press(.select)
        let season = app.buttons["season-1"]
        XCTAssertTrue(season.waitForExistence(timeout: 20)); sleep(2)
        for _ in 0..<4 { XCUIRemote.shared.press(.down); usleep(500_000); if focused()?.label.hasPrefix("1.") == true { break } }
        XCUIRemote.shared.press(.right); usleep(600_000)
        let episodeLabel = focused()?.label ?? ""
        let seasonY = season.frame.minY
        XCUIRemote.shared.press(.select)
        let timeline = app.descendants(matching: .any)["playback-timeline"]
        let resume = app.buttons["resume-playback"]
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in resume.exists || timeline.exists }, object: app)], timeout: 30)
        if resume.exists { XCUIRemote.shared.press(.select) }
        sleep(10)  // controls hide
        XCUIRemote.shared.press(.menu)
        for _ in 0..<8 {
            usleep(250_000)
            XCTAssertEqual(focused()?.label, episodeLabel, "Focus left the episode")
            XCTAssertEqual(season.frame.minY, seasonY, accuracy: 2, "The page moved")
        }
    }

    private func keep(_ app: XCUIApplication, _ name: String) -> XCTAttachment {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; return shot
    }
    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        for _ in 0..<6 { if app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-tab-")).allElementsBoundByIndex.contains(where: { $0.hasFocus }) { break }; XCUIRemote.shared.press(.up) }
        for _ in 0..<8 where !tab.hasFocus {
            let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main-tab-")).allElementsBoundByIndex.first { $0.hasFocus }
            XCUIRemote.shared.press((focused?.frame.minX ?? 0) < tab.frame.minX ? .right : .left)
        }
        XCUIRemote.shared.press(.select)
        sleep(2)
    }
    private func openSearch(_ app: XCUIApplication) {
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        for _ in 0..<4 { if app.buttons["main-tab-home"].hasFocus || search.hasFocus { break }; XCUIRemote.shared.press(.up) }
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
