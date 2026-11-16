// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeFeedTabsUITests: XCTestCase {
    func testChannelSearchAdditionSwipeRefreshPersistenceReorderAndRemoval() async {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-refresh-fixture"]
        app.launchEnvironment["GRIDSPACE_FEED_TEST_STORE"] = UUID().uuidString
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Synthetic refresh batch 1"].waitForExistence(timeout: 20))
        app.buttons["native-feed-edit"].tap()
        XCTAssertTrue(app.buttons["native-feed-add-channel"].isEnabled)
        app.buttons["native-feed-add-channel"].tap()
        let initialLayout = XCTAttachment(string: app.debugDescription)
        initialLayout.name = "Synthetic channel browser accessibility"; initialLayout.lifetime = .keepAlways; add(initialLayout)
        let search = app.textFields["native-channel-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("music")
        let addButton = app.buttons["native-channel-add:fixture-music"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10)); addButton.tap()
        app.buttons["native-feed-editor-done"].tap()
        let channel = app.buttons["native-feed-tab:channel:fixture-music"]
        XCTAssertTrue(channel.waitForExistence(timeout: 10)); XCTAssertTrue(channel.isSelected)
        XCTAssertTrue(app.staticTexts["Synthetic channel timeline batch 1"].waitForExistence(timeout: 15))
        let list = app.descendants(matching: .any).matching(identifier: "native-timeline").firstMatch
        list.swipeRight()
        let global = app.buttons["native-feed-tab:global"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in global.exists && global.isSelected }, object: nil)
        await fulfillment(of: [selected], timeout: 10)
        channel.tap()
        let channelTop = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic channel timeline batch '")).firstMatch
        XCTAssertTrue(channelTop.waitForExistence(timeout: 15))
        let beforeRefresh = channelTop.label
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).press(forDuration: 0.05,
            thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in channelTop.exists && channelTop.label != beforeRefresh }, object: nil)
        await fulfillment(of: [refreshed], timeout: 15)
        app.terminate(); app.launch()
        XCTAssertTrue(channel.waitForExistence(timeout: 20)); channel.tap()
        XCTAssertTrue(app.staticTexts["Synthetic channel timeline batch 1"].waitForExistence(timeout: 15))
        app.buttons["native-feed-edit"].tap()
        let channelRow = app.cells.containing(.any, identifier: "native-feed-editor:channel:fixture-music").firstMatch
        let localRow = app.cells.containing(.any, identifier: "native-feed-editor:local").firstMatch
        XCTAssertTrue(channelRow.waitForExistence(timeout: 10)); XCTAssertTrue(localRow.exists)
        let handle = channelRow.buttons.matching(NSPredicate(format: "label CONTAINS 'Reorder' OR label CONTAINS '並べ替え'")).firstMatch
        XCTAssertTrue(handle.exists)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5,
            thenDragTo: localRow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.05)), withVelocity: .slow, thenHoldForDuration: 0.5)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in channelRow.frame.minY < localRow.frame.minY }, object: nil)
        await fulfillment(of: [moved], timeout: 5)
        app.buttons["native-feed-editor-done"].tap()
        XCTAssertLessThan(channel.frame.minX, app.buttons["native-feed-tab:local"].frame.minX)
        app.terminate(); app.launch()
        XCTAssertTrue(channel.waitForExistence(timeout: 20))
        XCTAssertLessThan(channel.frame.minX, app.buttons["native-feed-tab:local"].frame.minX)
        app.buttons["native-feed-edit"].tap()
        let layout = XCTAttachment(string: app.debugDescription)
        layout.name = "Synthetic feed editor accessibility"; layout.lifetime = .keepAlways; add(layout)
        channelRow.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let delete = app.buttons.matching(NSPredicate(format: "label == 'Delete' OR label == '削除'")).firstMatch
        let deletionReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !channelRow.exists || delete.exists }, object: nil)
        await fulfillment(of: [deletionReady], timeout: 5)
        if delete.exists { delete.tap() }
        app.buttons["native-feed-editor-done"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !channel.exists }, object: nil)
        await fulfillment(of: [removed], timeout: 10)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:local"].waitForExistence(timeout: 20)); XCTAssertFalse(channel.exists)
    }
}
