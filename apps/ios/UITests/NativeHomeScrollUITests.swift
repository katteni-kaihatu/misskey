// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeHomeScrollUITests: XCTestCase {
    private func start(live: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-refresh-fixture"]
        if live { app.launchArguments.append("--native-live-fixture") }
        app.launchEnvironment["GRIDSPACE_FEED_TEST_STORE"] = UUID().uuidString
        app.launch(); return app
    }
    private func waitAtTop(_ top: XCUIElement, y: CGFloat) async {
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            top.exists && top.isHittable && abs(top.frame.minY - y) < 4
        }, object: nil)
        await fulfillment(of: [returned], timeout: 10)
        XCTAssertEqual(top.frame.minY, y, accuracy: 4)
    }
    func testHomeTapReturnsOnlyTheSelectedFeedAndWorksAfterChangingBottomTabs() async {
        let app = start(); defer { app.terminate() }
        let top = app.staticTexts["Synthetic refresh batch 1"]
        XCTAssertTrue(top.waitForExistence(timeout: 15)); let y = top.frame.minY
        let list = app.collectionViews["native-timeline"], home = app.buttons["native-tab:タイムライン"]
        list.swipeUp(); list.swipeUp()
        XCTAssertFalse(top.exists && top.isHittable)
        app.buttons["native-feed-tab:global"].tap()
        XCTAssertTrue(top.waitForExistence(timeout: 15))
        list.swipeUp(); list.swipeUp(); home.tap()
        await waitAtTop(top, y: y)
        XCTAssertTrue(app.buttons["native-feed-tab:global"].isSelected)
        app.buttons["native-feed-tab:local"].tap()
        XCTAssertFalse(top.exists && top.isHittable, "The global feed's request must not reset the local feed")
        home.tap(); await waitAtTop(top, y: y)
        list.swipeUp(); app.buttons["native-tab:検索"].tap(); home.tap()
        await waitAtTop(top, y: y)
    }
    func testHomeTapPopsANoteDetailAndReturnsTheTimelineToTheTop() async {
        let app = start(); defer { app.terminate() }
        let top = app.staticTexts["Synthetic refresh batch 1"]
        XCTAssertTrue(top.waitForExistence(timeout: 15)); let y = top.frame.minY
        app.collectionViews["native-timeline"].swipeUp()
        guard let detail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'native-note-detail:'")).allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("A visible synthetic note must be available"); return
        }
        detail.tap()
        XCTAssertTrue(app.navigationBars["ノート"].waitForExistence(timeout: 10))
        app.buttons["native-tab:タイムライン"].tap()
        XCTAssertTrue(app.collectionViews["native-timeline"].waitForExistence(timeout: 10))
        await waitAtTop(top, y: y)
    }
    func testHomeTapReleasesPendingLiveNotesAtTheTop() async {
        let app = start(live: true); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Synthetic live 2"].waitForExistence(timeout: 15))
        let list = app.collectionViews["native-timeline"]
        list.swipeUp()
        let pending = app.buttons["native-timeline-new-notes"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        app.buttons["native-tab:タイムライン"].tap()
        let topLimit = app.buttons["native-feed-tab:local"].frame.maxY + 90
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !pending.exists && app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic live '")).allElementsBoundByIndex.contains {
                $0.isHittable && $0.frame.minY < topLimit
            }
        }, object: nil)
        await fulfillment(of: [returned], timeout: 10)
    }
}
