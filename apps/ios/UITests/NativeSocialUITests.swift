// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeSocialUITests: XCTestCase {
    private func start() async throws -> (XCUIApplication, PairedParityControl.State, [String: String]) {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let fixture = try await PairedParityControl.perform("native-social-prepare", environment: environment)
        let auth = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(auth.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        return (app, fixture, environment)
    }
    private func search(_ text: String, app: XCUIApplication) {
        app.buttons["native-tab:検索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        // The first empty search field may expose its prompt as its value.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text + "\n")
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, attempts: Int = 10) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.55))
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22))
            bottom.press(forDuration: 0.05, thenDragTo: top)
        }
        diagnose(app)
        XCTAssertTrue(element.exists && element.isHittable)
    }
    func testConversationHidesUnauthorizedAncestorPaginatesRepliesAndSendsANativeReply() async throws {
        let (app, fixture, environment) = try await start()
        defer { app.terminate() }
        let id = try XCTUnwrap(fixture.socialTargetID)
        let before = try await PairedParityControl.perform("native-social-status", environment: environment)
        search("Synthetic conversation target", app: app)
        let detail = app.buttons["native-note-detail:" + id]
        XCTAssertTrue(detail.waitForExistence(timeout: 20)); reveal(detail, app: app); detail.tap()
        XCTAssertTrue(app.staticTexts["Synthetic visible conversation ancestor"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["このノートは表示できません"].exists || app.otherElements["このノートは表示できません"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic hidden conversation ancestor"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        let more = app.buttons["native-more-replies"]
        reveal(more, app: app, attempts: 35); more.tap()
        let oldest = app.staticTexts["Synthetic conversation reply 00"]
        reveal(oldest, app: app)
        XCTAssertTrue(oldest.exists)
        let reply = app.buttons["native-note-reply:" + id]
        // Return to the target row above the replies.
        for _ in 0..<35 {
            if reply.exists && reply.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.72)))
        }
        XCTAssertTrue(reply.exists && reply.isHittable); reply.tap()
        let editor = app.textViews["native-compose-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15)); editor.tap(); editor.typeText("Synthetic native conversation device reply")
        let send = app.buttons["native-compose-send"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in send.isEnabled }, object: app)
        await fulfillment(of: [ready], timeout: 20); send.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !editor.exists }, object: app)
        await fulfillment(of: [done], timeout: 25)
        let after = try await PairedParityControl.perform("native-social-status", environment: environment)
        XCTAssertEqual(after.deviceReplies, (before.deviceReplies ?? 0) + 1)
    }
    func testSingleMultipleAndExpiredPollsUseActualVoteState() async throws {
        let (app, fixture, environment) = try await start()
        defer { app.terminate() }
        let tag = try XCTUnwrap(fixture.socialTag)
        let first = app.buttons["native-poll-choice-0"].firstMatch
        let second = app.buttons["native-poll-choice-1"].firstMatch
        search("Synthetic native single poll " + tag, app: app)
        reveal(first, app: app); first.tap()
        let confirm = app.buttons["投票する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "キャンセル", "Cancel")).firstMatch
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap() }
        let untouched = try await PairedParityControl.perform("native-social-status", environment: environment)
        XCTAssertEqual(untouched.singleVotes, [0, 0])
        first.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        await voted(first, app: app)
        XCTAssertFalse(first.isEnabled); XCTAssertFalse(second.isEnabled)
        search("Synthetic native multiple poll " + tag, app: app)
        reveal(first, app: app); first.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap(); await voted(first, app: app)
        XCTAssertTrue(second.isEnabled); second.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap(); await voted(second, app: app)
        search("Synthetic native expired poll " + tag, app: app)
        reveal(app.staticTexts["投票終了"], app: app)
        XCTAssertFalse(first.isEnabled); XCTAssertFalse(second.isEnabled)
        XCTAssertTrue(app.staticTexts["投票終了"].exists)
        let status = try await PairedParityControl.perform("native-social-status", environment: environment)
        XCTAssertEqual(status.singleVotes, [1, 0]); XCTAssertEqual(status.multipleVotes, [1, 1]); XCTAssertEqual(status.expiredVotes, [0, 0])
    }
    private func voted(_ element: XCUIElement, app: XCUIApplication) async {
        let result = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.label.contains("投票済み") }, object: app)
        await fulfillment(of: [result], timeout: 20)
        if !element.label.contains("投票済み") { diagnose(app) }
        XCTAssertTrue(element.label.contains("投票済み"))
    }
    private func diagnose(_ app: XCUIApplication) {
        if app.state == .runningForeground { add(XCTAttachment(string: app.debugDescription)) }
        #if targetEnvironment(simulator)
        if app.state == .runningForeground { add(XCTAttachment(screenshot: app.screenshot())) }
        #endif
    }
}
