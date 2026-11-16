// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

@MainActor
final class NativeNotificationsUITests: XCTestCase {
    func testCompactNotificationsKeepFilteringReadConfirmationAndNoteNavigation() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture", "--native-notifications-fixture"]
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 20))
        let notifications = app.buttons["native-tab:通知"]
        await ready(notifications, app: app)
        notifications.tap()
        guard app.navigationBars["通知"].waitForExistence(timeout: 10) else { XCTFail("Notification navigation did not complete"); return }
        await unread(5, app: app)
        XCTAssertTrue(app.buttons["native-notification-note:notification-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["native-notification-person:notification-person-3"].exists)
        XCTAssertFalse(app.staticTexts["SYNTHETIC HIDDEN SPOILER"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "分前")).firstMatch.exists)
        XCTAssertFalse(app.buttons["native-note-renote:notification-note-0"].exists)
        XCTAssertFalse(app.staticTexts["開いたり絞り込んだりしても、自動では既読にしません。"].exists)
        #if targetEnvironment(simulator)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic compact notifications"; screenshot.lifetime = .keepAlways; add(screenshot)
        #endif
        filter("フォロー", app: app)
        XCTAssertTrue(app.buttons["native-notification-detail:notification-3"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["native-notification-note:notification-0"].exists)
        await unread(5, app: app)
        app.buttons["native-notification-person:notification-person-3"].tap()
        XCTAssertTrue(app.segmentedControls["native-profile-filter"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["通知"].firstMatch.tap()
        await unread(5, app: app)
        let readAll = app.buttons["native-notification-read-all"]
        await ready(readAll, app: app); readAll.tap(); confirm("キャンセル", app: app)
        await unread(5, app: app)
        readAll.tap(); confirm("すべて既読にする", app: app); await unread(0, app: app)
        XCTAssertFalse(readAll.isEnabled)
        filter("すべて", app: app)
        let note = app.buttons["native-notification-note:notification-0"]
        XCTAssertTrue(note.waitForExistence(timeout: 10)); note.tap()
        XCTAssertTrue(app.buttons["native-note-renote:notification-note-0"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.webViews.count, 0)
    }
    private func start(readOnly: Bool = false) async throws -> (XCUIApplication, PairedParityControl.State, [String: String]) {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let fixture = try await PairedParityControl.perform("native-notifications-prepare", environment: environment)
        let auth = try await PairedParityControl.perform(readOnly ? "native-auth-notifications-read-only" : "native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(auth.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        return (app, fixture, environment)
    }
    private func diagnose(_ app: XCUIApplication) {
        guard app.state == .runningForeground else { return }
        add(XCTAttachment(string: app.debugDescription))
        #if targetEnvironment(simulator)
        add(XCTAttachment(screenshot: app.screenshot()))
        #endif
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true, attempts: Int = 25) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.55 : 0.22))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.22 : 0.72))
            a.press(forDuration: 0.05, thenDragTo: b)
        }
        diagnose(app); XCTAssertTrue(element.exists && element.isHittable)
    }
    private func confirm(_ title: String, app: XCUIApplication) {
        if title == "キャンセル" {
            XCTAssertTrue(app.buttons["すべて既読にする"].waitForExistence(timeout: 5))
            let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "キャンセル", "Cancel")).firstMatch
            if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap() }
        } else {
            XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5))
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", title))
            XCTAssertGreaterThan(choices.count, 0); choices.element(boundBy: choices.count - 1).tap()
        }
    }
    private func ready(_ element: XCUIElement, app: XCUIApplication) async {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isEnabled && element.isHittable }, object: app)
        await fulfillment(of: [enabled], timeout: 20)
    }
    private func unread(_ count: Int, app: XCUIApplication) async {
        let label = app.staticTexts["native-notification-unread"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in label.exists && label.label == "このサーバーの未読 \(count)件" }, object: app)
        await fulfillment(of: [ready], timeout: 20)
        if !label.exists { diagnose(app) }
        XCTAssertEqual(label.label, "このサーバーの未読 \(count)件")
    }
    private func filter(_ title: String, app: XCUIApplication) {
        let picker = app.buttons["native-notification-filter"]
        reveal(picker, app: app, up: false); picker.tap()
        app.buttons[title].firstMatch.tap()
    }
    func testPagingFilteringBackgroundAndReadAllKeepTheirServerSemantics() async throws {
        let (app, fixture, environment) = try await start(); defer { app.terminate() }
        let before = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        let original = try XCTUnwrap(before.notificationUnreadCount); XCTAssertGreaterThan(original, 0)
        app.buttons["native-tab:通知"].tap(); await unread(original, app: app)
        filter("アプリ通知", app: app)
        let header = app.staticTexts["Synthetic native notice header " + (try XCTUnwrap(fixture.notificationTag))].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        filter("フォロー", app: app)
        let more = app.buttons["native-notification-more"]
        reveal(more, app: app); more.tap()
        let oldest = app.buttons["native-notification-person:" + (try XCTUnwrap(fixture.notificationFirstFollowerID))]
        reveal(oldest, app: app); oldest.tap()
        XCTAssertTrue(app.segmentedControls["native-profile-filter"].waitForExistence(timeout: 15))
        app.navigationBars.buttons["通知"].firstMatch.tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10)); app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let readAll = app.buttons["native-notification-read-all"]
        reveal(readAll, app: app, up: false)
        await unread(original, app: app)
        await ready(readAll, app: app)
        let untouched = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        XCTAssertEqual(untouched.notificationUnreadCount, original)
        XCTAssertEqual(untouched.notificationReadAttempts, before.notificationReadAttempts)
        readAll.tap(); confirm("キャンセル", app: app)
        let cancelled = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        XCTAssertEqual(cancelled.notificationUnreadCount, original)
        XCTAssertEqual(cancelled.notificationReadAttempts, before.notificationReadAttempts)
        readAll.tap(); confirm("すべて既読にする", app: app)
        var after = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        for _ in 0..<20 {
            if after.notificationUnreadCount == 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
            after = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        }
        XCTAssertEqual(after.notificationUnreadCount, 0)
        XCTAssertEqual(after.notificationReadAttempts, (before.notificationReadAttempts ?? 0) + 1)
        XCTAssertEqual(after.notificationReadWrites, (before.notificationReadWrites ?? 0) + 1)
        app.buttons["native-notification-menu"].tap(); app.buttons["未読状態を再取得"].tap(); await unread(0, app: app)
        XCTAssertFalse(readAll.isEnabled); XCTAssertEqual(app.webViews.count, 0)
    }
    func testAnOlderTokenCanReadButNeedsReauthorizationToMarkAllRead() async throws {
        let (app, fixture, environment) = try await start(readOnly: true); defer { app.terminate() }
        let before = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        let count = try XCTUnwrap(before.notificationUnreadCount); XCTAssertGreaterThan(count, 0)
        app.buttons["native-tab:通知"].tap(); await unread(count, app: app)
        let readAll = app.buttons["native-notification-read-all"]
        await ready(readAll, app: app); readAll.tap(); confirm("すべて既読にする", app: app)
        let error = app.staticTexts["既読操作の権限を確認してください。アカウントメニューからログインし直すと権限を追加できます。"]
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        let after = try await PairedParityControl.perform("native-notifications-status", environment: environment)
        XCTAssertEqual(after.notificationUnreadCount, count)
        XCTAssertEqual(after.notificationReadAttempts, (before.notificationReadAttempts ?? 0) + 1)
        XCTAssertEqual(after.notificationReadWrites, before.notificationReadWrites)
        let header = app.staticTexts["Synthetic native notice header " + (try XCTUnwrap(fixture.notificationTag))].firstMatch
        reveal(header, app: app); XCTAssertTrue(header.exists)
    }
}
