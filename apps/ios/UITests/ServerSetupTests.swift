// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

final class ServerSetupTests: XCTestCase {
    @MainActor
    func testRejectsInsecureServerWithoutLoadingWebContent() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let address = app.textFields["server-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("http://example.com")
        XCTAssertEqual(address.value as? String, "http://example.com")
        app.buttons["connect-server"].tap()
        XCTAssertTrue(app.staticTexts["server-error"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.webViews.count, 0)
    }
}
