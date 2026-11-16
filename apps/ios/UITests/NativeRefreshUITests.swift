// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeRefreshUITests: XCTestCase {
    private func launch(failing: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-refresh-fixture"]
        if failing { app.launchArguments.append("--native-refresh-failure") }
        app.launch()
        return app
    }
    private func pull(_ list: XCUIElement) {
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    private func settled(_ text: XCUIElement, at y: CGFloat) async {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            text.exists && text.isHittable && abs(text.frame.minY - y) < 4
        }, object: nil)
        await fulfillment(of: [settled], timeout: 12)
        XCTAssertEqual(text.frame.minY, y, accuracy: 4, "Refresh must release its extra top inset")
    }
    func testRepeatedPullsSettleAtTheOriginalOffsetAndScrollingStillWorks() async {
        let app = launch(); defer { app.terminate() }
        let top = app.staticTexts["Synthetic refresh batch 1"]
        XCTAssertTrue(top.waitForExistence(timeout: 15))
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        XCTAssertTrue(list.exists)
        let originalY = top.frame.minY
        let tabsY = app.buttons["native-feed-tab:local"].frame.minY
        for batch in 2...3 {
            pull(list)
            let updated = app.staticTexts["Synthetic refresh batch \(batch)"]
            XCTAssertTrue(updated.waitForExistence(timeout: 15))
            await settled(updated, at: originalY)
            XCTAssertEqual(app.buttons["native-feed-tab:local"].frame.minY, tabsY, accuracy: 1)
        }
        let currentTop = app.staticTexts["Synthetic refresh batch 3"]
        list.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !currentTop.exists || !currentTop.isHittable }, object: nil)
        await fulfillment(of: [scrolled], timeout: 5)
    }
    func testFailedPullKeepsRowsAndTheNextPullCanRefresh() async {
        let app = launch(failing: true); defer { app.terminate() }
        let top = app.staticTexts["Synthetic refresh batch 1"]
        XCTAssertTrue(top.waitForExistence(timeout: 15))
        let originalY = top.frame.minY
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        pull(list)
        await settled(top, at: originalY)
        pull(list)
        let recovered = app.staticTexts["Synthetic refresh batch 3"]
        XCTAssertTrue(recovered.waitForExistence(timeout: 15))
        await settled(recovered, at: originalY)
    }
    private func waitSelected(_ kind: String, app: XCUIApplication) async {
        let tab = app.buttons["native-feed-tab:" + kind]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.exists && tab.isSelected }, object: nil)
        await fulfillment(of: [selected], timeout: 10)
        XCTAssertTrue(tab.isSelected)
    }
    func testFeedSwipeKeepsVerticalScrollingAndPullToRefresh() async {
        let app = launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Synthetic refresh batch 1"].waitForExistence(timeout: 15))
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        list.swipeLeft()
        await waitSelected("global", app: app)
        XCTAssertTrue(app.buttons["native-tab:タイムライン"].isSelected)
        let top = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic refresh batch ")).firstMatch
        XCTAssertTrue(top.waitForExistence(timeout: 15))
        let before = top.label, originalY = top.frame.minY
        pull(list)
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in top.exists && top.label != before }, object: nil)
        await fulfillment(of: [refreshed], timeout: 15)
        await settled(top, at: originalY)
        XCTAssertTrue(app.buttons["native-feed-tab:global"].isSelected)
        list.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !top.exists || !top.isHittable }, object: nil)
        await fulfillment(of: [scrolled], timeout: 5)
        XCTAssertTrue(app.buttons["native-feed-tab:global"].isSelected)
        list.swipeRight()
        await waitSelected("local", app: app)
        XCTAssertFalse(app.buttons["native-feed-tab:home"].exists)
        XCTAssertEqual(app.tabBars.count, 0)
    }
    func testSignedInPagingHasHomeAndStopsAtBothEndsAndHeaderTapsStillWork() async {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture"]
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 20))
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        list.swipeRight()
        await waitSelected("home", app: app)
        list.swipeRight()
        await waitSelected("home", app: app)
        list.swipeLeft()
        await waitSelected("local", app: app)
        list.swipeLeft()
        await waitSelected("global", app: app)
        list.swipeLeft()
        await waitSelected("global", app: app)
        app.buttons["native-feed-tab:local"].tap()
        await waitSelected("local", app: app)
        XCTAssertTrue(app.buttons["native-tab:タイムライン"].isSelected)
        XCTAssertEqual(app.tabBars.count, 0)
    }

}
