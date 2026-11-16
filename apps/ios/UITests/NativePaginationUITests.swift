// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativePaginationUITests: XCTestCase {
    private func start(failing: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-refresh-fixture", "--native-pagination-fixture"]
        app.launchEnvironment["GRIDSPACE_FEED_TEST_STORE"] = UUID().uuidString
        if failing { app.launchArguments.append("--native-pagination-failure") }
        app.launch()
        XCTAssertTrue(app.staticTexts["Auto timeline row 0"].waitForExistence(timeout: 15))
        return app
    }
    private func scroll(_ list: XCUIElement, to element: XCUIElement) {
        // Use a short controlled drag so the requested row cannot fly past
        // the viewport between accessibility snapshots when a page arrives.
        for _ in 0..<24 {
            if element.exists { return }
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05,
                thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        if !element.exists {
            let state = XCTAttachment(string: XCUIApplication().debugDescription)
            state.name = "Synthetic pagination accessibility"; state.lifetime = .keepAlways; add(state)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10))
    }
    func testScrollingLoadsBothPagesWithoutTappingAndStopsAtTheEnd() {
        let app = start(); defer { app.terminate() }
        XCTAssertFalse(app.staticTexts["Auto timeline row 30"].waitForExistence(timeout: 2), "Offscreen List prefetch must not fetch history")
        let list = app.collectionViews["native-timeline"]
        scroll(list, to: app.staticTexts["Auto timeline row 30"])
        scroll(list, to: app.staticTexts["Auto timeline row 60"])
        XCTAssertFalse(app.buttons["もっと見る"].exists)
        XCTAssertFalse(app.progressIndicators["続きを読み込み中"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["再試行"].exists)
    }
    func testFailedPageWaitsForRetryAndKeepsTheExistingRows() {
        let app = start(failing: true); defer { app.terminate() }
        let list = app.collectionViews["native-timeline"]
        scroll(list, to: app.buttons["再試行"])
        let retained = app.staticTexts["Auto timeline row 29"]
        XCTAssertTrue(retained.exists)
        let originalY = retained.frame.minY
        XCTAssertFalse(app.staticTexts["Auto timeline row 30"].waitForExistence(timeout: 2))
        app.buttons["再試行"].tap()
        XCTAssertTrue(app.staticTexts["Auto timeline row 30"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["再試行"].exists)
        XCTAssertTrue(retained.exists)
        XCTAssertEqual(retained.frame.minY, originalY, accuracy: 4, "Appending the retried page must preserve the reading position")
    }
    func testAddedLocalChannelAlsoLoadsOnScroll() {
        let app = start(); defer { app.terminate() }
        app.buttons["native-feed-edit"].tap(); app.buttons["native-feed-add-channel"].tap()
        let search = app.textFields["native-channel-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("music")
        let add = app.buttons["native-channel-add:fixture-music"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        app.buttons["native-feed-editor-done"].tap()
        XCTAssertTrue(app.buttons["native-feed-tab:channel:fixture-music"].isSelected)
        XCTAssertTrue(app.staticTexts["Auto timeline row 0"].waitForExistence(timeout: 15))
        scroll(app.collectionViews["native-timeline"], to: app.staticTexts["Auto timeline row 30"])
        XCTAssertFalse(app.buttons["もっと見る"].exists)
    }
}
