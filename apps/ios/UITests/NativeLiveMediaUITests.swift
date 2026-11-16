// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeLiveMediaUITests: XCTestCase {
    private func start(_ extra: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-refresh-fixture", extra]
        app.launch(); return app
    }
    func testLivePeerAndLocalPostsFlowAtTopButHistoryDoesNotMoveUntilNewNotesAreOpened() async {
        let app = start("--native-live-fixture"); defer { app.terminate() }
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        let peer = app.staticTexts["Synthetic live 2"]
        XCTAssertTrue(peer.waitForExistence(timeout: 20), "Paired-server posts must pass the LTL stream filter")
        XCTAssertTrue(peer.isHittable)
        XCTAssertTrue(app.staticTexts["Synthetic live 4"].waitForExistence(timeout: 10))
        list.swipeUp()
        let anchor = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic refresh row ")).allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 170 }
        XCTAssertNotNil(anchor)
        guard let anchor else { return }
        let y = anchor.frame.minY
        let pending = app.buttons["native-timeline-new-notes"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertEqual(anchor.frame.minY, y, accuracy: 3)
        pending.tap()
        let topLimit = app.buttons["native-feed-tab:local"].frame.maxY + 90
        let flowing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !pending.exists && app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic live ")).allElementsBoundByIndex.contains { $0.isHittable && $0.frame.minY < topLimit }
        }, object: nil)
        await fulfillment(of: [flowing], timeout: 10)
    }
    func testImageHeightAndEmojiTextStayStableWhileLoadingAndAfterScrollingAwayAndBack() async {
        let app = start("--native-media-cache-fixture"); defer { app.terminate() }
        let preview = app.buttons["native-file-preview:owned-photo"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        XCTAssertEqual(preview.frame.height, 240, accuracy: 1)
        let y = preview.frame.minY
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(preview.frame.height, 240, accuracy: 1)
        XCTAssertEqual(preview.frame.minY, y, accuracy: 2)
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        list.swipeUp(); list.swipeUp(); list.swipeDown(); list.swipeDown()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in preview.exists && preview.isHittable }, object: nil)
        await fulfillment(of: [returned], timeout: 10)
        XCTAssertEqual(preview.frame.height, 240, accuracy: 1)
        XCTAssertFalse(app.activityIndicators["本文を読み込み中"].exists)
    }
}
