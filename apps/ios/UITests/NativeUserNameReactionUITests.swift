// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeUserNameReactionUITests: XCTestCase {
    private func start(live: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture", "--native-reaction-sheet-fixture", "--native-name-emoji-fixture"]
        if live { app.launchArguments.append("--native-live-reactions-fixture") }
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["Short synthetic note"].waitForExistence(timeout: 20))
        return app
    }
    func testCustomEmojiNamesRemainSingleLineAndProfileAndComposerStillOpen() async {
        let app = start(); defer { app.terminate() }
        let names = app.descendants(matching: .any).matching(identifier: "native-user-name")
        let author = app.buttons["native-note-author:synthetic-composer"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 10))
        XCTAssertTrue(author.label.contains("Compose :synthetic_animation: QA"))
        author.tap()
        XCTAssertTrue(app.navigationBars["プロフィール"].waitForExistence(timeout: 10))
        XCTAssertTrue(names.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(names.allElementsBoundByIndex.contains { $0.label == "Compose :synthetic_animation: QA" && $0.frame.height > 20 })
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let compose = app.buttons["native-floating-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10)); compose.tap()
        XCTAssertTrue(app.textViews["native-compose-text"].waitForExistence(timeout: 10))
        XCTAssertTrue(names.firstMatch.exists)
        XCTAssertEqual(names.firstMatch.label, "Compose :synthetic_animation: QA")
    }
    func testLiveReactionsAppearChangeTheirActorAtTheSameCountAndDisappearWithoutRefreshing() async {
        let app = start(live: true); defer { app.terminate() }
        let joy = app.buttons["native-reaction:synthetic-reaction-sheet:😂"]
        XCTAssertTrue(joy.waitForExistence(timeout: 15))
        let first = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (joy.value as? String)?.contains("@live-first") == true }, object: nil)
        await fulfillment(of: [first], timeout: 5)
        XCTAssertTrue(joy.label.contains("1件")); XCTAssertFalse(joy.isSelected)
        let second = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            joy.exists && (joy.value as? String)?.contains("@live-second") == true && joy.label.contains("1件")
        }, object: nil)
        await fulfillment(of: [second], timeout: 10)
        let thumbs = app.buttons["native-reaction:synthetic-reaction-sheet:👍"]
        XCTAssertTrue(thumbs.waitForExistence(timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !joy.exists && thumbs.exists }, object: nil)
        await fulfillment(of: [removed], timeout: 10)
        XCTAssertEqual(app.activityIndicators.count, 0)
    }
}
