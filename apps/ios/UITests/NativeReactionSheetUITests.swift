// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeReactionSheetUITests: XCTestCase {
    private func start(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture", "--native-reaction-sheet-fixture"]
        app.launchArguments += extra
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Short synthetic note"].waitForExistence(timeout: 15))
        let layout = XCTAttachment(string: app.debugDescription)
        layout.name = "Compact synthetic note layout"; layout.lifetime = .keepAlways; add(layout)
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        return app
    }
    func testDelayedWriteImmediatelyShowsSelectionAndOwnAvatarThenAllowsQueuedRemoval() async {
        let app = start(extra: ["--native-reaction-avatars-fixture", "--native-reaction-delay-fixture"])
        defer { app.terminate() }
        await half(app)
        app.navigationBars["絵文字"].buttons["閉じる"].tap()
        let chip = app.buttons["native-reaction:synthetic-reaction-sheet:👍"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let actors = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (chip.value as? String)?.contains("@other") == true && (chip.value as? String)?.contains("@peer@peer.ios.test") == true
        }, object: nil)
        await fulfillment(of: [actors], timeout: 10)
        chip.tap()
        let optimistic = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            chip.isSelected && (chip.value as? String)?.contains("@compose-fixture") == true && chip.label.contains("3件")
        }, object: nil)
        await fulfillment(of: [optimistic], timeout: 2)
        XCTAssertEqual(app.activityIndicators.count, 0)
        XCTAssertTrue(app.buttons["native-note-reaction:synthetic-reaction-sheet"].isEnabled)
        chip.tap() // Removal queues behind the still unacknowledged add.
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !chip.isSelected && (chip.value as? String)?.contains("@compose-fixture") != true && chip.label.contains("2件")
        }, object: nil)
        await fulfillment(of: [removed], timeout: 2)
        app.buttons["native-tab:検索"].tap()
        XCTAssertTrue(app.navigationBars["検索"].waitForExistence(timeout: 5))
        app.buttons["native-tab:タイムライン"].tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        // Wait for both four-second acknowledgements, then verify the actual
        // server state through a fresh picker read rather than the projection.
        try? await Task.sleep(nanoseconds: 9_000_000_000)
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        XCTAssertFalse(app.buttons["native-emoji-remove"].exists)
        app.navigationBars["絵文字"].buttons["閉じる"].tap()
        XCTAssertFalse(chip.isSelected)
        XCTAssertTrue((chip.value as? String)?.contains("@peer@peer.ios.test") == true)
    }
    private func half(_ app: XCUIApplication) async {
        let bar = app.navigationBars["絵文字"]
        let half = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            bar.exists && bar.frame.minY > app.frame.height * 0.35 && bar.frame.minY < app.frame.height * 0.7 && !app.keyboards.firstMatch.exists
        }, object: nil)
        await fulfillment(of: [half], timeout: 10)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
    func testRecentsOpenFirstInUseOrderAndCachedCatalogSurvivesOfflineRestart() async {
        let app = start(); defer { app.terminate() }
        await half(app)
        XCTAssertTrue(app.segmentedControls.buttons["最近"].isSelected)
        XCTAssertFalse(app.staticTexts["絵文字を取得中"].exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
        let search = app.textFields["native-emoji-search"]
        search.tap(); search.typeText("嬉し泣き") // Search all emoji from Recent.
        let joy = app.buttons["native-emoji:😂"]
        XCTAssertTrue(joy.waitForExistence(timeout: 10)); joy.tap()
        XCTAssertTrue(app.buttons["native-reaction:synthetic-reaction-sheet:😂"].waitForExistence(timeout: 10))
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        XCTAssertTrue(app.segmentedControls.buttons["最近"].isSelected)
        XCTAssertTrue(joy.exists)
        app.segmentedControls.buttons["カスタム"].tap()
        let custom = app.buttons["native-emoji:synthetic_animation"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10)); custom.tap()
        XCTAssertTrue(app.buttons["native-reaction:synthetic-reaction-sheet::synthetic_animation@.:"].waitForExistence(timeout: 10))
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        XCTAssertTrue(custom.exists); XCTAssertTrue(joy.exists)
        search.tap(); search.typeText("👍")
        let thumbs = app.buttons["native-emoji:👍"]
        XCTAssertTrue(thumbs.waitForExistence(timeout: 10)); thumbs.tap()
        XCTAssertTrue(app.buttons["native-reaction:synthetic-reaction-sheet:👍"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.append("--native-emoji-catalog-offline-fixture")
        app.launch()
        XCTAssertTrue(app.staticTexts["Short synthetic note"].waitForExistence(timeout: 20))
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        XCTAssertTrue(app.segmentedControls.buttons["最近"].isSelected)
        XCTAssertTrue(custom.waitForExistence(timeout: 2)); XCTAssertTrue(thumbs.exists); XCTAssertTrue(joy.exists)
        XCTAssertTrue(custom.isEnabled)
        XCTAssertLessThan(thumbs.frame.minX, custom.frame.minX)
        XCTAssertLessThan(custom.frame.minX, joy.frame.minX)
        XCTAssertEqual(app.activityIndicators.count, 0)
        XCTAssertFalse(app.staticTexts["絵文字を取得中"].exists)
        XCTAssertFalse(app.staticTexts["通信できませんでした。接続を確認して再試行してください。"].exists)
    }
    private func expanded(_ app: XCUIApplication) async {
        let bar = app.navigationBars["絵文字"]
        let full = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bar.exists && bar.frame.minY < app.frame.height * 0.2 }, object: nil)
        await fulfillment(of: [full], timeout: 10)
    }
    func testTwoReactionsCoexistAndRemovingThePrimaryKeepsTheAnimatedCustomReaction() async {
        let app = start(); defer { app.terminate() }
        await half(app)
        app.segmentedControls.buttons["標準"].tap()
        let search = app.textFields["native-emoji-search"]; search.tap(); search.typeText("嬉し泣き")
        let first = app.buttons["native-emoji:😂"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let firstChip = app.buttons["native-reaction:synthetic-reaction-sheet:😂"]
        XCTAssertTrue(firstChip.waitForExistence(timeout: 10))
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        app.segmentedControls.buttons["カスタム"].tap()
        let custom = app.buttons["native-emoji:synthetic_animation"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10)); custom.tap()
        let extra = app.buttons["native-reaction:synthetic-reaction-sheet::synthetic_animation@.:"]
        XCTAssertTrue(extra.waitForExistence(timeout: 10)); XCTAssertTrue(firstChip.exists)
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        app.buttons["native-emoji-remove"].tap()
        let removeFirst = app.buttons["native-emoji-remove:😂"]
        XCTAssertTrue(removeFirst.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["native-emoji-remove::synthetic_animation@.:"].exists)
        removeFirst.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !firstChip.exists && extra.exists }, object: nil)
        await fulfillment(of: [removed], timeout: 10)
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        let remove = app.buttons["native-emoji-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); remove.tap()
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !extra.exists }, object: nil)
        await fulfillment(of: [empty], timeout: 10)
    }
    func testReactionStartsAtHalfAndDraggingExpands() async {
        let app = start(); defer { app.terminate() }
        await half(app)
        let bar = app.navigationBars["絵文字"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        await expanded(app)
        app.navigationBars["絵文字"].buttons["閉じる"].tap()
        XCTAssertTrue(app.staticTexts["Short synthetic note"].exists)
    }
    func testSearchFocusExpandsAndChoiceClosesThenReopensAtHalf() async {
        let app = start(); defer { app.terminate() }
        await half(app)
        app.segmentedControls.buttons["標準"].tap()
        let search = app.textFields["native-emoji-search"]
        XCTAssertTrue(search.exists); search.tap()
        await expanded(app)
        search.typeText("嬉し泣き")
        let choice = app.buttons["native-emoji:😂"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); choice.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.navigationBars["絵文字"].exists }, object: nil)
        await fulfillment(of: [closed], timeout: 10)
        XCTAssertTrue(app.buttons["native-reaction:synthetic-reaction-sheet:😂"].waitForExistence(timeout: 10))
        app.buttons["native-note-reaction:synthetic-reaction-sheet"].tap()
        await half(app)
        app.navigationBars["絵文字"].buttons["閉じる"].tap()
    }
}
