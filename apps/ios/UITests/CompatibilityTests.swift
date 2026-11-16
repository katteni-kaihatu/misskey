// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class CompatibilityTests: XCTestCase {
    private func fixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--compatibility-fixture"]
        app.launch()
        let address = app.textFields["server-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("https://example.com")
        XCTAssertEqual(address.value as? String, "https://example.com")
        app.buttons["connect-server"].tap()
        XCTAssertTrue(app.webViews.staticTexts["互換性テスト"].waitForExistence(timeout: 10))
        return app
    }

    func testNegotiationAndJavaScriptDialogs() {
        let app = fixture()
        app.webViews.buttons["ブリッジを確認"].tap()
        XCTAssertTrue(app.webViews.staticTexts["ブリッジ接続済み"].waitForExistence(timeout: 5))
        app.webViews.buttons["alertを確認"].tap()
        XCTAssertTrue(app.alerts.staticTexts["ダイアログの確認"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        app.webViews.buttons["confirmを確認"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.webViews.staticTexts["取消済み"].waitForExistence(timeout: 3))
    }

    func testNativeUploadMenuCancellationKeepsWebInputEmpty() {
        let app = fixture()
        app.webViews.buttons["添付を選択"].tap()
        XCTAssertTrue(app.buttons["写真・動画"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ファイル"].exists)
        cancelUploadMenu(app)
        XCTAssertTrue(app.webViews.staticTexts["添付なし"].exists)
        // A second request proves cancellation released WebKit's pending callback.
        app.webViews.buttons["添付を選択"].tap()
        XCTAssertTrue(app.buttons["写真・動画"].waitForExistence(timeout: 3))
        cancelUploadMenu(app)
    }

    func testBackgroundCancelsPendingSelection() {
        let app = fixture()
        app.webViews.buttons["添付を選択"].tap()
        XCTAssertTrue(app.buttons["写真・動画"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.webViews.staticTexts["添付なし"].waitForExistence(timeout: 5))
        app.webViews.buttons["添付を選択"].tap()
        XCTAssertTrue(app.buttons["写真・動画"].waitForExistence(timeout: 3))
        cancelUploadMenu(app)
    }

    private func cancelUploadMenu(_ app: XCUIApplication) {
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        else {
            // iOS 27 can present the sheet as a popover, which dismisses by
            // tapping outside instead of displaying its cancel action.
            app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        }
    }
}
