// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeRetainedTimelineUITests: XCTestCase {
    private func start() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture", "--native-reaction-sheet-fixture", "--native-retained-timeline-fixture"]
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["GRIDSPACE_FEED_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic retained '")).firstMatch.waitForExistence(timeout: 15))
        return app
    }
    private func anchor(_ app: XCUIApplication) throws -> XCUIElement {
        try XCTUnwrap(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic retained '")).allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.minY > app.buttons["native-feed-tab:local"].frame.maxY + 30 && $0.frame.maxY < app.buttons["native-tab:通知"].frame.minY - 30
        })
    }
    private func retained(_ element: XCUIElement, y: CGFloat) async {
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable && abs(element.frame.minY - y) < 4
        }, object: nil)
        await fulfillment(of: [stable], timeout: 10)
        XCTAssertEqual(element.frame.minY, y, accuracy: 4)
    }
    private func send(_ text: String, app: XCUIApplication) async {
        app.buttons["native-floating-compose"].tap()
        let editor = app.textViews["native-compose-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText(text)
        let button = app.buttons["native-compose-send"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.exists && button.isEnabled }, object: nil)
        await fulfillment(of: [enabled], timeout: 10); button.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !editor.exists }, object: nil)
        await fulfillment(of: [closed], timeout: 15)
    }
    func testPostingKeepsTheReadPositionAndOldRowsAndOnlyQueuesTheAcknowledgedNote() async throws {
        let app = start(); defer { app.terminate() }
        let originalTop = try anchor(app).label
        let list = app.collectionViews["native-timeline"]
        list.swipeUp(); list.swipeUp()
        let before = try anchor(app), label = before.label, y = before.frame.minY
        await send("Synthetic retained first post", app: app)
        await retained(app.staticTexts[label], y: y)
        XCTAssertTrue(app.buttons["native-timeline-new-notes"].exists)
        app.buttons["native-tab:タイムライン"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic retained first post"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[originalTop].exists)
        await send("Synthetic retained second post", app: app)
        XCTAssertTrue(app.staticTexts["Synthetic retained second post"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[originalTop].exists)
        XCTAssertFalse(app.buttons["native-timeline-new-notes"].exists)
    }
    func testSwipingAcrossDistantFeedsRestoresRowsAndPositionWithoutReadingAnotherHead() async throws {
        let app = start(); defer { app.terminate() }
        let home = app.buttons["native-feed-tab:home"]
        let tappable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in home.exists && home.isEnabled && home.isHittable }, object: nil)
        await fulfillment(of: [tappable], timeout: 10)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let onHome = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in home.isSelected }, object: nil)
        await fulfillment(of: [onHome], timeout: 10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic retained timeline '")).firstMatch.waitForExistence(timeout: 15))
        let list = app.collectionViews["native-timeline"]
        list.swipeUp(); list.swipeUp()
        let before = try anchor(app), label = before.label, y = before.frame.minY
        for (left, selection) in [(true, "local"), (true, "global"), (false, "local"), (false, "home")] {
            if left { list.swipeLeft() } else { list.swipeRight() }
            let tab = app.buttons["native-feed-tab:" + selection]
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.exists && tab.isSelected }, object: nil)
            await fulfillment(of: [selected], timeout: 10)
        }
        await retained(app.staticTexts[label], y: y)
        XCTAssertFalse(app.buttons["native-timeline-new-notes"].exists)
    }
}
