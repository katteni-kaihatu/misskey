// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import CryptoKit

@MainActor
final class NativeClientTests: XCTestCase {
    func testNativeAttachmentsSurviveDraftRestoreAndPostInOrderWithoutReupload() async throws {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let authorization = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(authorization.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let before = try await PairedParityControl.perform("native-attachment-status", environment: environment)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment; app.launch()
        defer { app.terminate() }
        let compose = app.buttons["native-floating-compose"]
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        XCTAssertTrue(compose.waitForExistence(timeout: 30)); compose.tap()
        let options = app.buttons["native-add-attachment"]
        options.tap(); app.buttons["native-synthetic-attachment"].tap()
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "native-attachment-edit:"))
        XCTAssertTrue(edit.firstMatch.waitForExistence(timeout: 10)); edit.firstMatch.tap()
        let first = app.textFields["native-attachment-name"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10)); replace(first, with: "native-first.txt")
        replace(app.descendants(matching: .any).matching(identifier: "native-attachment-comment").firstMatch, with: "Synthetic description")
        let sensitive = app.switches["native-attachment-sensitive"].firstMatch
        sensitive.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.navigationBars["添付を編集"].buttons["完了"].tap()
        options.tap(); app.buttons["native-synthetic-attachment"].tap()
        let two = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in edit.count == 2 }, object: nil)
        await fulfillment(of: [two], timeout: 10)
        edit.element(boundBy: 1).tap()
        replace(app.textFields["native-attachment-name"].firstMatch, with: "native-second.txt")
        app.navigationBars["添付を編集"].buttons["完了"].tap()
        app.navigationBars["投稿"].buttons["閉じる"].tap(); app.buttons["保存して閉じる"].tap()
        app.terminate()
        let restartedAuthorization = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(restartedAuthorization.session)
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        XCTAssertTrue(compose.waitForExistence(timeout: 30)); compose.tap()
        // Hide the keyboard with the outer scroll margin, preserving the draft.
        scrollForm(in: app, up: true)
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "native-attachment-actions:")).firstMatch
        reveal(actions, in: app); actions.tap(); app.buttons["後へ"].tap()
        for _ in 0..<3 { scrollForm(in: app, up: false) }
        app.buttons["native-compose-visibility"].tap(); app.buttons["フォロワー"].firstMatch.tap()
        let send = app.buttons["native-compose-send"]
        XCTAssertTrue(send.isEnabled); send.tap()
        await waitForBarToClose("投稿", app: app)
        XCTAssertTrue(compose.waitForExistence(timeout: 30))
        let after = try await PairedParityControl.perform("native-attachment-status", environment: environment)
        XCTAssertEqual(after.attachmentNoteCount, (before.attachmentNoteCount ?? 0) + 1)
        XCTAssertEqual(after.attachmentDriveCount, (before.attachmentDriveCount ?? 0) + 2)
        XCTAssertEqual(after.attachmentNames, ["native-second.txt", "native-first.txt"])
        XCTAssertEqual(after.attachmentSensitive, [false, true])
        XCTAssertEqual(after.attachmentComments?.map { $0 ?? "" }, ["", "Synthetic description"])
        let expectedHash = Insecure.MD5.hash(data: Data("Synthetic native attachment bytes\n".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(after.attachmentHashes, [expectedHash, expectedHash])
        compose.tap()
        let attach = app.buttons["native-add-attachment"]
        reveal(attach, in: app); attach.tap()
        let driveChoice = app.buttons["ドライブから選ぶ"]
        let hasDriveChoice = driveChoice.waitForExistence(timeout: 5)
        if !hasDriveChoice { diagnose(app) }
        XCTAssertTrue(hasDriveChoice); driveChoice.tap()
        let driveFile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "native-first.txt")).firstMatch
        XCTAssertTrue(driveFile.waitForExistence(timeout: 20)); driveFile.tap()
        await waitForBarToClose("ドライブから添付", app: app)
        XCTAssertTrue(app.staticTexts["native-first.txt"].waitForExistence(timeout: 10))
        app.navigationBars["投稿"].buttons["閉じる"].tap()
        let discard = app.buttons["破棄して閉じる"]
        if !discard.waitForExistence(timeout: 5) { diagnose(app) }
        XCTAssertTrue(discard.exists); discard.tap()
        let final = try await PairedParityControl.perform("native-attachment-status", environment: environment)
        XCTAssertEqual(final.attachmentDriveCount, after.attachmentDriveCount)
    }

    private func waitForBarToClose(_ title: String, app: XCUIApplication) async {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.navigationBars[title].exists }, object: app)
        await fulfillment(of: [closed], timeout: 30)
        if app.navigationBars[title].exists { diagnose(app) }
        XCTAssertFalse(app.navigationBars[title].exists)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // Repeated runs add synthetic posts; scroll the target above the
        // floating composer and lower controls before interacting with it.
        for _ in 0..<9 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.height * 0.68 { return }
            scrollForm(in: app, up: true)
        }
        if !element.exists || !element.isHittable { diagnose(app) }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func scrollForm(in app: XCUIApplication, up: Bool) {
        // The centre can belong to the nested TextEditor or the keyboard on a
        // smaller phone. Scroll in the Form's margin, above the keyboard.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.55))
        if up { bottom.press(forDuration: 0.05, thenDragTo: top) }
        else { top.press(forDuration: 0.05, thenDragTo: bottom) }
    }
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let count = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
    }

    func testNativeMFMLinksBlurAndLiteralMath() async throws {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let authorization = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(authorization.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        let body = app.textViews.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic MFM bold")).firstMatch
        reveal(body, in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 30))
        XCTAssertFalse(body.label.contains("Synthetic hidden MFM"))
        XCTAssertFalse(body.label.contains("**"))
        XCTAssertEqual(app.webViews.count, 0)
        let external = app.links["外部リンク"].firstMatch
        if !external.waitForExistence(timeout: 5) { diagnose(app) }
        XCTAssertTrue(external.exists)
        reveal(external, in: app); external.tap()
        if !app.buttons["ブラウザで開く"].waitForExistence(timeout: 5) { diagnose(app) }
        XCTAssertTrue(app.buttons["ブラウザで開く"].exists)
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "キャンセル", "Cancel")).firstMatch
        if cancel.exists { cancel.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap() }
        XCTAssertFalse(app.buttons["ブラウザで開く"].exists)
        let blur = app.links["［ぼかした内容を表示］"].firstMatch
        XCTAssertTrue(blur.waitForExistence(timeout: 5)); blur.tap()
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in body.label.contains("Synthetic hidden MFM") }, object: app)
        await fulfillment(of: [revealed], timeout: 5)
        XCTAssertTrue(body.label.contains("Synthetic hidden MFM"))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        reveal(body, in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 30))
        XCTAssertFalse(body.label.contains("Synthetic hidden MFM"))
        #if targetEnvironment(simulator)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native MFM"; screenshot.lifetime = .keepAlways; add(screenshot)
        #endif
        XCTAssertTrue(body.label.contains("x^2"))
        XCTAssertEqual(app.webViews.count, 0)
    }

    func testNativeTimelineSearchAndFollowerPostUseActualMiAuthAPIs() async throws {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let authorization = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(authorization.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let before = try await PairedParityControl.perform("native-status", environment: environment)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment
        app.launch()
        defer { app.terminate() }
        let home = app.buttons["native-feed-tab:home"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in home.exists || app.alerts.firstMatch.exists }, object: app)
        await fulfillment(of: [ready], timeout: 30)
        let authenticated = home.exists
        if !authenticated { diagnose(app) }
        XCTAssertTrue(authenticated, "The native client must exchange the actual one-time MiAuth session")
        let seed = app.staticTexts["Synthetic native timeline seed"]
        reveal(seed, in: app)
        XCTAssertTrue(seed.waitForExistence(timeout: 30))
        XCTAssertEqual(app.webViews.count, 0, "The visible timeline must be a native List")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "paired_other")).firstMatch.tap()
        XCTAssertTrue(app.segmentedControls["native-profile-filter"].waitForExistence(timeout: 15))
        app.navigationBars.buttons["ぐりすぺ"].tap()
        reveal(seed, in: app)
        XCTAssertTrue(seed.waitForExistence(timeout: 15))
        app.buttons.matching(NSPredicate(format: "label == %@", "ノートの詳細")).firstMatch.tap()
        let hasDetail = app.navigationBars["ノート"].waitForExistence(timeout: 15)
        if !hasDetail { diagnose(app) }
        XCTAssertTrue(hasDetail)
        app.navigationBars.buttons["ぐりすぺ"].tap()
        reveal(seed, in: app)
        XCTAssertTrue(seed.waitForExistence(timeout: 15))
        #if targetEnvironment(simulator)
        let timelineImage = XCTAttachment(screenshot: app.screenshot())
        timelineImage.name = "Native timeline"; timelineImage.lifetime = .keepAlways; add(timelineImage)
        #endif
        app.buttons["native-floating-compose"].tap()
        let editor = app.textViews["native-compose-text"]
        let hasEditor = editor.waitForExistence(timeout: 15)
        if !hasEditor { diagnose(app) }
        XCTAssertTrue(hasEditor)
        app.buttons["native-add-attachment"].tap()
        app.buttons["内容の警告（CW）"].tap()
        let cw = app.descendants(matching: .any).matching(identifier: "native-compose-cw").firstMatch
        let hasCW = cw.waitForExistence(timeout: 5)
        if !hasCW { diagnose(app) }
        XCTAssertTrue(hasCW)
        cw.tap(); cw.typeText("Synthetic native CW")
        app.buttons["native-compose-visibility"].tap()
        app.buttons["フォロワー"].firstMatch.tap()
        editor.tap(); editor.typeText("Synthetic native device draft")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertEqual(editor.value as? String, "Synthetic native device draft")
        let send = app.buttons["native-compose-send"]
        let canSend = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in send.isEnabled }, object: app)
        await fulfillment(of: [canSend], timeout: 20)
        XCTAssertTrue(send.isEnabled); send.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !editor.exists }, object: app)
        await fulfillment(of: [dismissed], timeout: 30)
        let after = try await PairedParityControl.perform("native-status", environment: environment)
        XCTAssertEqual(after.nativeNoteCount, (before.nativeNoteCount ?? 0) + 1)
        XCTAssertEqual(after.nativeNoteVisibility, "followers")
        XCTAssertEqual(after.nativeNoteCW, "Synthetic native CW")
        app.buttons["native-tab:通知"].tap()
        reveal(app.buttons["native-notification-read-all"], in: app)
        app.buttons["native-tab:検索"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Synthetic native timeline seed\n")
        XCTAssertTrue(seed.waitForExistence(timeout: 30))
        app.buttons["native-tab:タイムライン"].tap()
        home.tap()
        XCTAssertTrue(app.staticTexts["Synthetic native CW"].waitForExistence(timeout: 20))
        app.buttons["アカウント"].tap()
        app.buttons["アプリからログアウト"].tap()
        XCTAssertTrue(app.buttons["ログインしてホームを読む"].waitForExistence(timeout: 10))
        XCTAssertFalse(home.exists)
        XCTAssertFalse(app.staticTexts["Synthetic native CW"].exists)
    }

    private func diagnose(_ app: XCUIApplication) {
        #if targetEnvironment(simulator)
        add(XCTAttachment(string: app.debugDescription))
        if app.state == .runningForeground { add(XCTAttachment(screenshot: app.screenshot())) }
        #else
        // A physical device can receive personal notification banners. Do not
        // capture its screen or another app when a banner interrupts a test.
        add(XCTAttachment(string: "Native fixture application state: \(app.state.rawValue)"))
        if app.state == .runningForeground { add(XCTAttachment(string: app.debugDescription)) }
        #endif
    }
}
