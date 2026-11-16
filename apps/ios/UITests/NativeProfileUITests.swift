// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeProfileUITests: XCTestCase {
    private func start() async throws -> (XCUIApplication, PairedParityControl.State, [String: String]) {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let fixture = try await PairedParityControl.perform("native-profile-prepare", environment: environment)
        let auth = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(auth.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        return (app, fixture, environment)
    }
    private func open(_ kind: String, id: String, tag: String, app: XCUIApplication) {
        app.buttons["native-tab:検索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let length = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length) + "Synthetic " + kind + " profile marker " + tag + "\n")
        let author = app.buttons["native-note-author:" + id]
        reveal(author, app: app); author.tap()
        XCTAssertTrue(app.segmentedControls["native-profile-filter"].waitForExistence(timeout: 20))
    }
    private func scroll(_ app: XCUIApplication, up: Bool) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.55 : 0.72))
        if up { b.press(forDuration: 0.05, thenDragTo: a) } else { a.press(forDuration: 0.05, thenDragTo: b) }
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true, attempts: Int = 12) {
        for _ in 0..<attempts { if element.exists && element.isHittable { return }; scroll(app, up: up) }
        if app.state == .runningForeground { add(XCTAttachment(string: app.debugDescription)) }
        #if targetEnvironment(simulator)
        if app.state == .runningForeground { add(XCTAttachment(screenshot: app.screenshot())) }
        #endif
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func confirm(_ title: String, app: XCUIApplication) {
        if app.sheets.firstMatch.waitForExistence(timeout: 2) { app.sheets.firstMatch.buttons[title].tap() }
        else {
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", title))
            XCTAssertGreaterThan(choices.count, 0); choices.element(boundBy: choices.count - 1).tap()
        }
    }
    private func relationship(_ text: String, app: XCUIApplication) async {
        let action = app.buttons["native-profile-follow-action"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in action.exists && action.label.contains(text) && action.isEnabled }, object: app)
        await fulfillment(of: [ready], timeout: 20)
        XCTAssertTrue(action.label.contains(text))
    }
    func testPostsRepliesMediaAndNotePaginationRemainNative() async throws {
        let (app, fixture, _) = try await start(); defer { app.terminate() }
        open("public", id: try XCTUnwrap(fixture.profilePublicID), tag: try XCTUnwrap(fixture.profileTag), app: app)
        XCTAssertTrue(app.staticTexts["Synthetic native profile description"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic profile field"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        let more = app.buttons["native-profile-more"]
        reveal(more, app: app, attempts: 35); more.tap()
        reveal(app.staticTexts["Synthetic profile post 00"], app: app)
        let filter = app.segmentedControls["native-profile-filter"]
        reveal(filter, app: app, up: false, attempts: 30)
        filter.buttons["返信を含む"].tap()
        reveal(app.staticTexts["Synthetic profile reply item"], app: app)
        reveal(filter, app: app, up: false)
        filter.buttons["メディア"].tap()
        reveal(app.staticTexts["Synthetic profile media item"], app: app)
        XCTAssertFalse(app.buttons["native-profile-more"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic profile reply item"].exists)
    }
    func testFollowUnfollowAndPeopleListPaginationUseServerRelationships() async throws {
        let (app, fixture, environment) = try await start(); defer { app.terminate() }
        open("public", id: try XCTUnwrap(fixture.profilePublicID), tag: try XCTUnwrap(fixture.profileTag), app: app)
        let action = app.buttons["native-profile-follow-action"]
        reveal(action, app: app); action.tap(); confirm("フォロー", app: app)
        await relationship("解除", app: app)
        var state = try await PairedParityControl.perform("native-profile-status", environment: environment)
        XCTAssertEqual(state.profileFollowing, true); XCTAssertEqual(state.profilePending, false)
        app.buttons["native-profile-followers"].tap()
        let more = app.buttons["native-people-more"]
        reveal(more, app: app); more.tap()
        let fan = app.buttons["native-person:" + (try XCTUnwrap(fixture.profileFirstFanID))]
        reveal(fan, app: app); fan.tap()
        XCTAssertTrue(app.segmentedControls["native-profile-filter"].waitForExistence(timeout: 15))
        app.navigationBars.buttons["フォロワー"].firstMatch.tap()
        app.navigationBars.buttons["プロフィール"].firstMatch.tap()
        await relationship("解除", app: app)
        reveal(action, app: app); action.tap(); confirm("フォロー解除", app: app)
        await relationship("フォロー", app: app)
        state = try await PairedParityControl.perform("native-profile-status", environment: environment)
        XCTAssertEqual(state.profileFollowing, false)
        app.buttons["native-profile-following"].tap()
        XCTAssertTrue(fan.waitForExistence(timeout: 15))
    }
    func testLockedRequestCancellationAndPrivateListsAreDistinctFromEmpty() async throws {
        let (app, fixture, environment) = try await start(); defer { app.terminate() }
        let tag = try XCTUnwrap(fixture.profileTag)
        open("locked", id: try XCTUnwrap(fixture.profileLockedID), tag: tag, app: app)
        let action = app.buttons["native-profile-follow-action"]
        reveal(action, app: app); action.tap(); confirm("フォロー申請", app: app)
        await relationship("申請中", app: app)
        var state = try await PairedParityControl.perform("native-profile-status", environment: environment)
        XCTAssertEqual(state.lockedFollowing, false); XCTAssertEqual(state.lockedPending, true)
        action.tap(); confirm("申請を取り消す", app: app)
        await relationship("フォロー申請", app: app)
        state = try await PairedParityControl.perform("native-profile-status", environment: environment)
        XCTAssertEqual(state.lockedPending, false)
        app.navigationBars.buttons["検索"].firstMatch.tap()
        open("private", id: try XCTUnwrap(fixture.profilePrivateID), tag: tag, app: app)
        app.buttons["native-profile-followers"].tap()
        let denied = app.staticTexts["この一覧は閲覧できません。公開設定とログイン状態を確認してください。"]
        XCTAssertTrue(denied.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["表示できるユーザーはいません"].exists)
        app.navigationBars.buttons["プロフィール"].firstMatch.tap()
        app.buttons["native-profile-following"].tap()
        XCTAssertTrue(denied.waitForExistence(timeout: 15))
    }
}
