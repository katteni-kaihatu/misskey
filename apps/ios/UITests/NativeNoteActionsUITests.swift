// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeNoteActionsUITests: XCTestCase {
    private func start() async throws -> (XCUIApplication, PairedParityControl.State, [String: String]) {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let fixture = try await PairedParityControl.perform("native-actions-prepare", environment: environment)
        let auth = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(auth.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        return (app, fixture, environment)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, attempts: Int = 15) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.55))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22))
            a.press(forDuration: 0.05, thenDragTo: b)
        }
        diagnose(app)
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func diagnose(_ app: XCUIApplication) {
        if app.state == .runningForeground { add(XCTAttachment(string: app.debugDescription)) }
        #if targetEnvironment(simulator)
        if app.state == .runningForeground { add(XCTAttachment(screenshot: app.screenshot())) }
        #endif
    }
    private func confirm(_ title: String, app: XCUIApplication) {
        if title == "キャンセル" {
            let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "キャンセル", "Cancel")).firstMatch
            if cancel.exists { cancel.tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap() }
            return
        }
        if app.sheets.firstMatch.waitForExistence(timeout: 2) { app.sheets.firstMatch.buttons[title].tap() }
        else {
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", title))
            XCTAssertGreaterThan(choices.count, 0); choices.element(boundBy: choices.count - 1).tap()
        }
    }
    private func waitForComposerToClose(_ app: XCUIApplication) async {
        let bar = app.navigationBars["リノート・引用"]
        let error = app.staticTexts["native-compose-error"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !bar.exists || error.exists }, object: app)
        await fulfillment(of: [finished], timeout: 30)
        if bar.exists { diagnose(app) }
        XCTAssertFalse(bar.exists)
    }
    private func compose(_ fixture: PairedParityControl.State, app: XCUIApplication) throws {
        app.buttons["native-tab:検索"].tap()
        let field = app.searchFields.firstMatch
        let searchReady = field.waitForExistence(timeout: 15)
        if !searchReady { diagnose(app) }
        XCTAssertTrue(searchReady); field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String)?.count ?? 0) + "Synthetic native reshare target " + (try XCTUnwrap(fixture.actionTag)) + "\n")
        let button = app.buttons["native-note-renote:" + (try XCTUnwrap(fixture.actionTargetID))]
        let disconnected = app.staticTexts["通信エラー（隔離試験コード: -1005）"]
        for attempt in 0..<3 {
            expectation(for: NSPredicate { _, _ in button.exists || disconnected.exists }, evaluatedWith: nil)
            waitForExpectations(timeout: 25)
            if button.exists { break }
            if attempt < 2, disconnected.exists {
                add(XCTAttachment(string: "Retried the search read after isolated USB connection loss (-1005)"))
                app.buttons["再試行"].tap()
            } else { break }
        }
        reveal(button, app: app); button.tap()
        XCTAssertTrue(app.navigationBars["リノート・引用"].waitForExistence(timeout: 15))
        let send = app.buttons["native-compose-send"]
        let ready = NSPredicate { _, _ in send.exists && send.isEnabled }
        expectation(for: ready, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
    }
    func testReshareQuoteDraftAndDeletionPreserveTheOriginalAndServerState() async throws {
        let (app, fixture, environment) = try await start(); defer { app.terminate() }
        try compose(fixture, app: app)
        app.buttons["native-compose-send"].tap(); confirm("キャンセル", app: app)
        var state = try await PairedParityControl.perform("native-actions-status", environment: environment)
        XCTAssertEqual(state.actionReshareIDs, []); XCTAssertEqual(state.actionQuoteIDs, [])
        app.buttons["native-compose-send"].tap(); confirm("送信する", app: app)
        await waitForComposerToClose(app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 15))
        state = try await PairedParityControl.perform("native-actions-status", environment: environment)
        let outer = try XCTUnwrap(state.actionReshareIDs?.first)
        XCTAssertEqual(state.actionReshareIDs?.count, 1); XCTAssertEqual(state.actionQuoteIDs, [])
        XCTAssertEqual(state.actionVisibilities, ["home"]); XCTAssertEqual(state.actionLocalOnly, [true])
        try compose(fixture, app: app)
        let body = app.textViews["native-compose-text"]
        body.tap(); body.typeText("Synthetic own quotation")
        app.navigationBars.buttons["閉じる"].tap(); confirm("保存して閉じる", app: app)
        try compose(fixture, app: app)
        XCTAssertEqual(body.value as? String, "Synthetic own quotation")
        app.buttons["native-compose-send"].tap(); confirm("送信する", app: app)
        await waitForComposerToClose(app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 15))
        state = try await PairedParityControl.perform("native-actions-status", environment: environment)
        XCTAssertEqual(state.actionReshareIDs?.count, 1); XCTAssertEqual(state.actionQuoteIDs?.count, 1)
        XCTAssertTrue(state.actionTexts?.contains("Synthetic own quotation") == true)
        XCTAssertEqual(state.actionVisibilities, ["home", "home"]); XCTAssertEqual(state.actionLocalOnly, [true, true])
        app.buttons["native-tab:タイムライン"].tap()
        XCTAssertTrue(app.buttons["アカウント"].waitForExistence(timeout: 15))
        app.buttons["アカウント"].tap(); app.buttons["自分のプロフィール"].tap()
        let detail = app.buttons["native-note-detail:" + outer]
        reveal(detail, app: app); detail.tap()
        let delete = app.buttons["native-note-delete"]
        reveal(delete, app: app); delete.tap(); confirm("キャンセル", app: app)
        state = try await PairedParityControl.perform("native-actions-status", environment: environment)
        XCTAssertEqual(state.actionReshareIDs?.count, 1)
        delete.tap(); confirm("削除する", app: app)
        XCTAssertTrue(app.segmentedControls["native-profile-filter"].waitForExistence(timeout: 15))
        state = try await PairedParityControl.perform("native-actions-status", environment: environment)
        XCTAssertEqual(state.actionReshareIDs, []); XCTAssertEqual(state.actionQuoteIDs?.count, 1)
        XCTAssertEqual(state.actionTargetExists, true); XCTAssertEqual(app.webViews.count, 0)
    }
    func testARestrictedTargetCannotBeQuotedAfterTheComposerWasOpened() async throws {
        let (app, fixture, environment) = try await start(); defer { app.terminate() }
        try compose(fixture, app: app)
        let body = app.textViews["native-compose-text"]
        body.tap(); body.typeText("Synthetic retained own draft")
        _ = try await PairedParityControl.perform("native-actions-restrict", environment: environment)
        app.buttons["native-compose-send"].tap(); confirm("送信する", app: app)
        let message = app.staticTexts["対象の公開範囲や状態が変わったため、送信を止めました。画面を開き直して確認してください。"]
        reveal(message, app: app)
        XCTAssertFalse(app.buttons["native-compose-send"].isEnabled)
        XCTAssertEqual(body.value as? String, "Synthetic retained own draft")
        let state = try await PairedParityControl.perform("native-actions-status", environment: environment)
        XCTAssertEqual(state.actionReshareIDs, []); XCTAssertEqual(state.actionQuoteIDs, [])
        XCTAssertEqual(state.actionTargetExists, true)
    }
}
