// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativePeerChannelUITests: XCTestCase {
    private func start(_ flag: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture", "--native-peer-channels-fixture"]
        if let flag { app.launchArguments.append(flag) }
        app.launchEnvironment["GRIDSPACE_FEED_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 20))
        app.buttons["native-feed-edit"].tap(); app.buttons["native-feed-add-channel"].tap()
        XCTAssertTrue(app.buttons["native-channel-add:collision1"].waitForExistence(timeout: 10))
        return app
    }
    private func addPeer(_ app: XCUIApplication) {
        app.segmentedControls.buttons["連携先"].tap()
        let peer = app.buttons["native-peer-channel-add:collision1"]
        XCTAssertTrue(peer.waitForExistence(timeout: 15)); peer.tap()
        app.buttons["native-feed-editor-done"].tap()
        let loaded = app.staticTexts["PEER CHANNEL NOTE peerNote0"].waitForExistence(timeout: 15)
        if !loaded {
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Synthetic peer initial accessibility"; state.lifetime = .keepAlways; add(state)
        }
        XCTAssertTrue(loaded)
        XCTAssertFalse(app.staticTexts["LOCAL CHANNEL NOTE"].exists)
    }
    func testPeerAndLocalSameIDRemainDistinctAndPeerTabRestores() async {
        let app = start(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["peer.ios.test"].waitForExistence(timeout: 10))
        addPeer(app)
        let originalY = app.staticTexts["PEER CHANNEL NOTE peerNote0"].frame.minY
        let list = app.collectionViews["native-peer-channel-timeline"]
        let extra = app.staticTexts["PEER CHANNEL NOTE peerNote11"]
        for _ in 0..<8 { if extra.exists && extra.isHittable { break }; list.swipeUp() }
        let loaded = extra.waitForExistence(timeout: 10)
        let structure = XCTAttachment(string: app.debugDescription)
        structure.name = "Synthetic peer pagination accessibility"; structure.lifetime = .keepAlways; add(structure)
        XCTAssertTrue(loaded)
        XCTAssertFalse(app.buttons["native-peer-channel-more"].exists)
        app.buttons["native-tab:タイムライン"].tap()
        let backAtTop = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let first = app.staticTexts["PEER CHANNEL NOTE peerNote0"]
            return first.exists && first.isHittable && abs(first.frame.minY - originalY) < 4
        }, object: nil)
        await fulfillment(of: [backAtTop], timeout: 10)
        XCTAssertTrue(app.buttons["native-feed-tab:peer-channel:https://peer.ios.test/:collision1"].isSelected)
        app.terminate(); app.launch()
        let tab = app.buttons["native-feed-tab:peer-channel:https://peer.ios.test/:collision1"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        app.scrollViews.containing(.button, identifier: "native-feed-tab:local").firstMatch.swipeLeft()
        tab.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.isSelected }, object: nil)
        await fulfillment(of: [selected], timeout: 10)
        let restored = app.staticTexts["PEER CHANNEL NOTE peerNote0"].waitForExistence(timeout: 15)
        if !restored {
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Synthetic peer restored accessibility"; state.lifetime = .keepAlways; add(state)
        }
        XCTAssertTrue(restored)
    }
    func testPermissionFailureLeavesLocalCatalogAndShowsLoginUpdate() {
        let app = start("--native-peer-permission-fixture"); defer { app.terminate() }
        XCTAssertTrue(app.buttons["native-peer-channel-login"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["native-channel-add:collision1"].isEnabled)
        app.buttons["native-channel-add:collision1"].tap(); app.buttons["native-feed-editor-done"].tap()
        XCTAssertTrue(app.staticTexts["LOCAL CHANNEL NOTE"].waitForExistence(timeout: 15))
    }
    func testRevocationDuringDisplayErasesPeerText() async {
        let app = start("--native-peer-revocation-fixture"); defer { app.terminate() }
        addPeer(app)
        let erased = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.staticTexts["PEER CHANNEL NOTE peerNote0"].exists }, object: nil)
        await fulfillment(of: [erased], timeout: 25)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'native-note-reaction:'")).firstMatch.exists)
    }
}
