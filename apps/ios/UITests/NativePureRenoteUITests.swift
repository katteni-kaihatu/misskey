// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativePureRenoteUITests: XCTestCase {
    func testPureRenoteHasNoFalseServerErrorAndResharingStillOpensTheOriginal() async {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture", "--native-reaction-sheet-fixture", "--native-pure-renote-fixture"]
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launch(); defer { app.terminate() }
        let wrapper = app.buttons["native-note-renote:synthetic-pure-renote"]
        XCTAssertTrue(wrapper.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["サーバーからの応答を確認できませんでした。"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["状態を再取得"].exists)
        wrapper.tap()
        XCTAssertTrue(app.navigationBars["リノート・引用"].waitForExistence(timeout: 10))
        let send = app.buttons["native-compose-send"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in send.exists && send.isEnabled }, object: nil)
        await fulfillment(of: [ready], timeout: 10)
        XCTAssertFalse(app.staticTexts["native-compose-error"].exists)
        // No notes/create call: opening the original is enough to check routing.
    }
}
