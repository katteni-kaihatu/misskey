// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

/// Opt-in tests use a synthetic server and a separate named WebKit store.
@MainActor
final class LocalPWAParityTests: XCTestCase {
    private func configuration() throws -> [String: String] {
        #if !DEBUG
        throw XCTSkip("Local PWA tests require a Debug build")
        #else
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_ORIGIN"] != nil,
              environment["GRIDSPACE_PARITY_USERNAME"] != nil,
              environment["GRIDSPACE_PARITY_PASSWORD"] != nil else {
            throw XCTSkip("Local PWA fixture environment is not configured")
        }
        // A rerun must start at the actual fresh-login UI. The same ID is then
        // retained across process restart within this individual test.
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        return environment
        #endif
    }

    private func launch(_ environment: [String: String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server"]
        app.launchEnvironment = environment
        app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["許可", "Allow"] {
            let permission = system.alerts.buttons[label]
            if permission.waitForExistence(timeout: 1) { permission.tap(); break }
        }
        return app
    }

    private func openFixtureFolder(in app: XCUIApplication, named name: String) {
        let title = NSPredicate(format: "label BEGINSWITH %@", name)
        for _ in 0..<16 {
            if app.navigationBars.buttons.matching(title).firstMatch.exists
                || app.navigationBars.staticTexts.matching(title).firstMatch.exists { return }
            let local = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "このiPhone内", "On My iPhone")).firstMatch
            let fixture = app.cells.matching(title).firstMatch
            if fixture.waitForExistence(timeout: 2) {
                // Target the actual icon. XCTest can scroll this element into
                // view; an absolute point in an offscreen cell can hit Browse.
                let icon = fixture.images.firstMatch
                if icon.exists { icon.tap() } else { fixture.tap() }
                continue
            }
            let directory = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "ぐりすぺ")).firstMatch
            if directory.exists && directory.isHittable {
                let icon = directory.images.firstMatch
                if icon.exists { icon.tap() } else { directory.tap() }
                continue
            }
            // Files virtualizes rows. Repeated runs leave older synthetic
            // folders above the fresh one, so it may not exist in AX yet.
            let documents = app.otherElements.matching(NSPredicate(format: "identifier ENDSWITH %@", "Title: ぐりすぺ")).firstMatch
            let contents = documents.collectionViews["File View"].firstMatch
            // The browsingRoot identifier retains its first title even after
            // entering a child folder. Use the current navigation title.
            let atDocuments = documents.navigationBars.buttons.matching(NSPredicate(format: "identifier != %@ AND label BEGINSWITH %@",
                "BackButton", "ぐりすぺ,")).firstMatch.exists || documents.navigationBars.staticTexts["ぐりすぺ"].exists
            if atDocuments && contents.exists {
                contents.swipeUp()
                continue
            }
            if local.exists && local.isHittable { local.tap(); continue }
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            if back.exists && back.isHittable { back.tap(); continue }
            let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["ブラウズ", "Browse"])).firstMatch
            if browse.exists && browse.isHittable { browse.tap(); continue }
        }
        let state = XCTAttachment(string: app.debugDescription)
        state.lifetime = .keepAlways
        add(state)
        XCTFail("The native picker must open the dedicated synthetic fixture folder")
    }

    private func chooseArchive(in app: XCUIApplication, folder: String, prefix: String) {
        app.webViews.buttons["移行ファイルを選択"].tap()
        XCTAssertTrue(app.buttons["ファイル"].waitForExistence(timeout: 5))
        app.buttons["ファイル"].tap()
        openFixtureFolder(in: app, named: folder)
        let archive = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 5), "The synthetic archive must be visible in its fixture folder")
        archive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
    }

    private func submitPassword(in app: XCUIApplication, username name: String, password secret: String) {
        // Protected deep links open the normal sign-in dialog automatically.
        let username = app.webViews.textFields["ユーザー名"].firstMatch
        let signin = app.webViews.buttons["ログイン"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            username.exists || signin.exists
        }, object: app)
        let result = XCTWaiter.wait(for: [ready], timeout: 45)
        if result != .completed {
            add(XCTAttachment(string: app.debugDescription))
            add(XCTAttachment(screenshot: app.screenshot()))
        }
        XCTAssertEqual(result, .completed, "Synthetic PWA did not load")
        if !username.exists { signin.tap() }
        fillPasswordDialog(in: app, username: name, password: secret)
    }

    private func fillPasswordDialog(in app: XCUIApplication, username name: String, password secret: String) {
        let username = app.webViews.textFields["ユーザー名"].firstMatch
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        username.tap()
        username.typeText(name)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name), object: username)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 5), .completed)
        continueButton(in: app).tap()
        let password = app.webViews.secureTextFields["パスワード"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap()
        password.typeText(secret)
        continueButton(in: app).tap()
    }

    private func continueButton(in app: XCUIApplication) -> XCUIElement {
        app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "続ける")).firstMatch
    }

    private func accountMenuAction(in app: XCUIApplication, endingWith label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label ENDSWITH %@", label)
        let item = app.webViews.menuItems.matching(predicate).firstMatch
        let button = app.webViews.buttons.matching(predicate).firstMatch
        // The Web menu exposes menu items in a popup and buttons in its
        // mobile drawer. Accept either actual action, never its static text.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            item.exists || button.exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        return item.exists ? item : button
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "Toolbar Done Button", ["完了", "Done"])).firstMatch
        if done.waitForExistence(timeout: 1) {
            done.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        } else if app.keyboards.firstMatch.exists {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("Dismiss the software keyboard before tapping controls below the code input")
        }
    }

    private func finishAccountSetup(in app: XCUIApplication) {
        if app.webViews.staticTexts["初期設定"].waitForExistence(timeout: 10) {
            let closeSetup = app.webViews.buttons["閉じる"].firstMatch
            XCTAssertTrue(closeSetup.waitForExistence(timeout: 5))
            closeSetup.tap()
            let confirm = app.webViews.buttons["OK"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
        }
        dismissSourceNotice(in: app)
    }

    private func dismissSourceNotice(in app: XCUIApplication) {
        // The source-availability notice can appear after the page controls.
        // Dismiss it as a user would; do not write its localStorage flag.
        let source = app.webViews.links["Misskeyについて"].firstMatch
        if source.waitForExistence(timeout: 3) {
            let notice = app.webViews.buttons["わかった"].firstMatch
            if notice.waitForExistence(timeout: 3) {
                notice.tap()
                let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: source)
                XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
            }
        }
    }

    private func confirmAccountAfterRestart(in app: XCUIApplication, environment: inout [String: String], userID: String) {
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/profiles"
        app.launchEnvironment = environment
        app.launch()
        let prepare = app.webViews.buttons["書き出す内容を確認"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 30))
        dismissSourceNotice(in: app)
        prepare.tap()
        let identity = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "書き出し元:", userID)).firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10), "The intended synthetic account must survive restart")
    }

    private func prepareRecoveryFixture(in app: XCUIApplication, environment: inout [String: String], mode: String) throws {
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        finishAccountSetup(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/__ios-recovery/" + mode
        app.launchEnvironment = environment
        app.launch()
    }

    private func assertScratchpad(in app: XCUIApplication, equals value: String) {
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }

    func testBackgroundResumePreservesOrdinaryScratchpadInput() throws {
        var environment = try configuration()
        environment["GRIDSPACE_PARITY_PATH"] = "/scratchpad"
        let app = launch(environment)
        defer { app.terminate() }
        dismissSourceNotice(in: app)
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        let document = app.webViews.firstMatch.identifier
        XCTAssertTrue(document.hasPrefix("web-session-"))
        let input = "// Synthetic ordinary input kept across foreground transitions"
        editor.tap()
        editor.typeText(input)
        dismissKeyboard(in: app)
        assertScratchpad(in: app, equals: input)
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            assertScratchpad(in: app, equals: input)
            XCTAssertEqual(app.webViews.firstMatch.identifier, document)
            XCTAssertFalse(app.buttons["renderer-resume-retry"].exists)
        }
    }

    func testPairedChannelQuoteReauthorizesAfterBackgroundWithoutLosingDraft() async throws {
        var environment = try configuration()
        guard let channel = environment["GRIDSPACE_PARITY_CHANNEL_ID"],
              let note = environment["GRIDSPACE_PARITY_CHANNEL_NOTE_ID"] else {
            throw XCTSkip("The isolated paired backend fixture is required")
        }
        let state = try await PairedParityControl.perform("status", environment: environment)
        if state.granted != true {
            let restored = try await PairedParityControl.perform("authorize", environment: environment)
            XCTAssertEqual(restored.granted, true)
        }
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        finishAccountSetup(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/gridspace/private?noteId=" + note + "&channelId=" + channel
        app.launchEnvironment = environment
        app.launch()
        let target = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic paired channel target"))
        XCTAssertTrue(target.firstMatch.waitForExistence(timeout: 30))
        dismissSourceNotice(in: app)
        app.webViews.buttons["リノート"].firstMatch.tap()
        let quoteLabel = NSPredicate(format: "label CONTAINS %@", "チャンネル内引用")
        let quoteItem = app.webViews.menuItems.matching(quoteLabel).firstMatch
        let quoteButton = app.webViews.buttons.matching(quoteLabel).firstMatch
        let quoteReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            quoteItem.exists || quoteButton.exists
        }, object: app)
        let menuResult = XCTWaiter.wait(for: [quoteReady], timeout: 10)
        if menuResult != .completed {
            add(XCTAttachment(string: app.debugDescription))
            add(XCTAttachment(screenshot: app.screenshot()))
        }
        XCTAssertEqual(menuResult, .completed)
        (quoteItem.exists ? quoteItem : quoteButton).tap()
        let editor = app.webViews.textViews["テキスト"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        // WebKit exposes the modal's target; its covered parent page is absent
        // from the accessibility tree while the quote dialog is open.
        XCTAssertEqual(target.count, 1)
        let document = app.webViews.firstMatch.identifier
        let draft = "Synthetic own paired quote draft"
        editor.tap()
        editor.typeText(draft)
        dismissKeyboard(in: app)
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                target.count == 1 && editor.exists && editor.value as? String == draft
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 30), .completed,
                           "The quote must reread the actual peer target while retaining the user's input")
            XCTAssertEqual(app.webViews.firstMatch.identifier, document)
            XCTAssertFalse(app.buttons["renderer-resume-retry"].exists)
        }
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        let renamed = try await PairedParityControl.perform("rename", environment: environment)
        XCTAssertEqual(renamed.name, "Updated paired author native")
        app.activate()
        let author = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Updated paired author native")).firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 30), "A resumed quote must reread fresh author data")
        XCTAssertEqual(editor.value as? String, draft)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        let revoked = try await PairedParityControl.perform("revoke", environment: environment)
        XCTAssertEqual(revoked.granted, false)
        XCTAssertEqual(revoked.canPostChannel, true)
        app.activate()
        let unavailable = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "元の投稿か権限を確認できませんでした")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 30))
        XCTAssertEqual(target.count, 0)
        XCTAssertFalse(author.exists)
        let submit = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "引用")).firstMatch
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        let authorized = try await PairedParityControl.perform("authorize", environment: environment)
        XCTAssertEqual(authorized.granted, true)
        app.activate()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.count == 1 && author.exists && editor.exists && editor.value as? String == draft
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 30), .completed)
        XCTAssertEqual(app.webViews.firstMatch.identifier, document)
    }

    func testInterruptedMigrationRecoversBeforeEditorBoot() throws {
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        try prepareRecoveryFixture(in: app, environment: &environment, mode: "interrupted")
        assertScratchpad(in: app, equals: "// Synthetic recovery before <b>literal</b>")
        XCTAssertFalse(app.webViews.staticTexts["中断したデータ移行の確認"].exists)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/scratchpad"
        app.launchEnvironment = environment
        app.launch()
        assertScratchpad(in: app, equals: "// Synthetic recovery before <b>literal</b>")
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
    }

    private func assertFailedRecoveryBeforeBoot(in app: XCUIApplication) {
        XCTAssertTrue(app.webViews.staticTexts["中断したデータ移行の確認"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["復旧できませんでした。ほかの画面を閉じ、空き容量と保存設定を確認してから再試行してください。復元記録は削除していません。"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.textViews.firstMatch.exists)
        XCTAssertFalse(app.webViews.buttons["選んだ内容で復旧して起動"].exists)
        XCTAssertFalse(app.webViews.buttons["現在のデータを残して起動"].exists)
        XCTAssertFalse(app.webViews.buttons["書き出す内容を確認"].exists)
        XCTAssertFalse(app.webViews.staticTexts["// Synthetic recovery before <b>literal</b>"].exists)
    }

    func testCorruptRecoveryRetainsEvidenceAcrossRetryAndRestart() throws {
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        try prepareRecoveryFixture(in: app, environment: &environment, mode: "corrupt")
        assertFailedRecoveryBeforeBoot(in: app)
        app.webViews.buttons["再試行"].tap()
        assertFailedRecoveryBeforeBoot(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/scratchpad"
        app.launchEnvironment = environment
        app.launch()
        assertFailedRecoveryBeforeBoot(in: app)
        // Inspect the actual stored journal/marker/value through an isolated
        // fixture page. No product boot bypass or automatic repair is added.
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/__ios-recovery/corrupt-audit"
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Synthetic damaged recovery journal retained"].waitForExistence(timeout: 30))
        app.webViews.buttons["Repair synthetic journal"].tap()
        assertScratchpad(in: app, equals: "// Synthetic recovery before <b>literal</b>")
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/__ios-recovery/corrupt-complete"
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Synthetic recovery completed without leftover journal"].waitForExistence(timeout: 30))
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
    }

    private func selectRecoveryRestore(in app: XCUIApplication, label: String) {
        let choice = app.webViews.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@ AND value IN %@",
            label, ["現在の値を残す", "移行前の値に戻す"])).firstMatch
        XCTAssertTrue(choice.exists)
        choice.tap()
        let wheel = app.pickerWheels.firstMatch
        let option = app.buttons["移行前の値に戻す"].firstMatch
        let menuOption = app.menuItems["移行前の値に戻す"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            wheel.exists || option.exists || menuOption.exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        if wheel.exists {
            wheel.adjust(toPickerWheelValue: "移行前の値に戻す")
            dismissKeyboard(in: app)
            XCTAssertFalse(wheel.exists)
        } else {
            (menuOption.exists ? menuOption : option).tap()
        }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "移行前の値に戻す"), object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    private func completeRecovery(in app: XCUIApplication, differentAccount: Bool, restore: Bool = false, extraRestoreLabel: String? = nil) {
        XCTAssertTrue(app.webViews.staticTexts["中断したデータ移行の確認"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.webViews.textViews.firstMatch.exists, "The editor must not boot before recovery is reviewed")
        let apply = app.webViews.buttons[differentAccount ? "現在のデータを残して起動" : "選んだ内容で復旧して起動"].firstMatch
        XCTAssertTrue(apply.exists)
        XCTAssertFalse(apply.isEnabled)
        let preview = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "値の一部を確認")).firstMatch
        if differentAccount {
            XCTAssertTrue(app.webViews.staticTexts["移行時とログイン状態が異なるため、移行前の内容は表示・復元しません。現在のデータを残して起動できます。以前の復元記録は、そのアカウント用に退避します。"].exists)
            XCTAssertFalse(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic recovery before")).firstMatch.exists)
            XCTAssertFalse(preview.exists)
        } else {
            XCTAssertTrue(preview.exists)
            preview.tap()
            XCTAssertTrue(app.webViews.staticTexts["// Synthetic recovery before <b>literal</b>"].waitForExistence(timeout: 5),
                          "Recovered source values must render as literal text")
            XCTAssertTrue(app.webViews.staticTexts["// Synthetic recovery current"].exists)
        }
        if restore {
            selectRecoveryRestore(in: app, label: "スクラッチパッド")
        }
        if let extraRestoreLabel { selectRecoveryRestore(in: app, label: extraRestoreLabel) }
        let state = XCTAttachment(string: app.debugDescription)
        state.name = "Synthetic recovery before ordinary editor boot"
        add(state)
        app.webViews.staticTexts["選んだ内容で復旧します。変更前の復元記録はこのブラウザに退避し、起動後の「プロファイル管理」から保存できます。"].tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        assertScratchpad(in: app, equals: restore ? "// Synthetic recovery before <b>literal</b>" : "// Synthetic recovery current")
    }

    func testRecoveryConflictKeepsCurrentValueAndPersistsAfterRestart() throws {
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        try prepareRecoveryFixture(in: app, environment: &environment, mode: "conflict")
        completeRecovery(in: app, differentAccount: false)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/scratchpad"
        app.launchEnvironment = environment
        app.launch()
        assertScratchpad(in: app, equals: "// Synthetic recovery current")
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
        app.webViews.buttons["キャンセル"].tap()
        let history = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "退避した復元記録")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        XCTAssertTrue(app.webViews.buttons["ダウンロード"].waitForExistence(timeout: 5))
        let remove = app.webViews.buttons["削除"].firstMatch
        remove.tap()
        let cancel = app.webViews.buttons["キャンセル"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(history.exists)
        remove.tap()
        let confirm = app.webViews.buttons["OK"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: history)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
    }

    func testRecoveryConflictRestoresPriorValueAndPersistsAfterRestart() throws {
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        try prepareRecoveryFixture(in: app, environment: &environment, mode: "conflict")
        completeRecovery(in: app, differentAccount: false, restore: true)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/scratchpad"
        app.launchEnvironment = environment
        app.launch()
        assertScratchpad(in: app, equals: "// Synthetic recovery before <b>literal</b>")
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
    }

    func testRecoveryForDifferentAccountHidesPriorValues() throws {
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        try prepareRecoveryFixture(in: app, environment: &environment, mode: "different-account")
        completeRecovery(in: app, differentAccount: true)
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
        app.webViews.buttons["キャンセル"].tap()
        XCTAssertFalse(app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "退避した復元記録")).firstMatch.exists)
    }

    private func saveSharedArchive(in app: XCUIApplication, folder: String) {
        let save = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@",
            ["“ファイル”に保存", "ファイルに保存", "\"ファイル\"に保存", "Save to Files"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15), "The archive must reach the native share sheet")
        save.tap()
        openFixtureFolder(in: app, named: folder)
        let saveFile = app.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        XCTAssertTrue(saveFile.waitForExistence(timeout: 5))
        XCTAssertTrue(saveFile.isEnabled)
        saveFile.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveFile)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
    }

    func testBlobRecoveryRestoresValuesAndExportsRecord() throws {
        guard #available(iOS 18.4, *) else { throw XCTSkip("Native recovery archive saving requires iOS 18.4") }
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        let folder = try XCTUnwrap(environment["GRIDSPACE_PARITY_RECOVERY_FOLDER"])
        try prepareRecoveryFixture(in: app, environment: &environment, mode: "conflict-blob")
        completeRecovery(in: app, differentAccount: false, restore: true,
                         extraRestoreLabel: "AvatarWalkの画像と保存データ")
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
        app.webViews.buttons["キャンセル"].tap()
        let history = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "退避した復元記録")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        app.webViews.buttons["ダウンロード"].tap()
        saveSharedArchive(in: app, folder: folder)
        // Drop the temporary WKDownload, then reopen only the saved recovery
        // archive. It must not be accepted as an ordinary migration file.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.webViews.buttons["移行ファイルを選択"].waitForExistence(timeout: 30))
        dismissSourceNotice(in: app)
        chooseArchive(in: app, folder: folder, prefix: "gridspace-")
        XCTAssertTrue(app.webViews.staticTexts["対応する移行ファイルではないか、内容が壊れています。書き出し元で新しくファイルを作成してください。"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.webViews.buttons["取り込んで再読み込み"].exists)
        app.webViews.buttons["わかった"].tap()
        XCTAssertTrue(app.webViews.buttons["書き出す内容を確認"].waitForExistence(timeout: 10))
        app.webViews.buttons["書き出す内容を確認"].tap()
        app.webViews.buttons["エクスポート"].tap()
        saveSharedArchive(in: app, folder: folder)
    }

    func testHTTPRedirectPreservesRouteAndConfirmsExternalDestination() throws {
        var environment = try configuration()
        environment["GRIDSPACE_PARITY_PATH"] = "/__ios-navigation/start"
        let app = launch(environment)
        defer { app.terminate() }
        let internalLink = app.webViews.links["Open internal redirect"].firstMatch
        XCTAssertTrue(internalLink.waitForExistence(timeout: 30))
        internalLink.tap()
        XCTAssertTrue(app.webViews.staticTexts["Internal redirect result"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.staticTexts["?tag=one%2Btwo&tag=two|#section%202"].exists,
                      "A real HTTP redirect must retain repeated query parameters, encoding and fragment")
        app.webViews.links["Open external redirect"].tap()
        let confirmation = app.alerts["外部リンクを開きますか？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 15), "A redirected external main frame must require confirmation")
        XCTAssertTrue(confirmation.staticTexts["example.com"].exists)
        XCTAssertFalse(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "synthetic-private-navigation")).firstMatch.exists)
        confirmation.buttons["取消"].tap()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.webViews.staticTexts["Internal redirect result"].exists,
                      "Cancelling must keep the previous page without rendering the external response")
    }

    func testReauthenticationCancelAndTokenRevocationAfterReload() throws {
        var environment = try configuration()
        let username = try XCTUnwrap(environment["GRIDSPACE_PARITY_REVOCATION_USERNAME"])
        let password = try XCTUnwrap(environment["GRIDSPACE_PARITY_REVOCATION_PASSWORD"])
        let userID = try XCTUnwrap(environment["GRIDSPACE_PARITY_REVOCATION_USER_ID"])
        let notePath = "/notes/" + (try XCTUnwrap(environment["GRIDSPACE_PARITY_REVOCATION_NOTE_ID"]))
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: username, password: password)
        finishAccountSetup(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = notePath
        app.launchEnvironment = environment
        app.launch()
        let body = app.webViews.staticTexts["Synthetic revocable note"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 30))
        dismissSourceNotice(in: app)
        app.webViews.links["Open security settings"].tap()

        func openReauthentication() {
            dismissSourceNotice(in: app)
            let regenerate = app.webViews.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "ログイントークンを再生成")).firstMatch
            for _ in 0..<10 {
                if regenerate.exists && regenerate.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3)))
            }
            XCTAssertTrue(regenerate.exists && regenerate.isHittable)
            regenerate.tap()
            XCTAssertTrue(app.webViews.staticTexts["続けるには認証を行ってください"].waitForExistence(timeout: 10))
        }

        openReauthentication()
        app.webViews.buttons["閉じる"].firstMatch.tap()
        confirmAccountAfterRestart(in: app, environment: &environment, userID: userID)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/security"
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.webViews.buttons["パスワードを変更"].firstMatch.waitForExistence(timeout: 30))
        openReauthentication()
        let field = app.webViews.secureTextFields["パスワード"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(password)
        dismissKeyboard(in: app)
        let authenticate = app.webViews.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "続ける")).firstMatch
        XCTAssertTrue(authenticate.isEnabled)
        authenticate.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        // The existing PWA discovers invalid credentials on refresh. Exercise
        // that ordinary path; no native code reads or replaces the Web token.
        app.toolbars.buttons["再読み込み"].tap()
        let reload = app.alerts["現在のページを再読み込みしますか？"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        reload.buttons["再読み込み"].tap()
        let revoked = app.webViews.staticTexts["トークンが無効です"].firstMatch
        if !revoked.waitForExistence(timeout: 30) {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("The existing first-party credential must be rejected after regeneration")
            return
        }
        app.webViews.buttons["わかった"].firstMatch.tap()
        XCTAssertTrue(app.webViews.buttons["ログイン"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.toolbars.buttons["戻る"].isEnabled)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = notePath
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["(非公開)"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(body.exists)
        // A normal fresh password login must recover the same identity.
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/"
        app.launchEnvironment = environment
        app.launch()
        submitPassword(in: app, username: username, password: password)
        finishAccountSetup(in: app)
        confirmAccountAfterRestart(in: app, environment: &environment, userID: userID)
    }

    func testPasswordLoginAndPersistentRestart() throws {
        guard #available(iOS 18.4, *) else {
            throw XCTSkip("The native Files adapter and named-store restart test require iOS 18.4")
        }
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        // Completing setup updates the synthetic server account, so later
        // fresh-store reruns can correctly go straight to the timeline.
        finishAccountSetup(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/profiles"
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.webViews.buttons["書き出す内容を確認"].waitForExistence(timeout: 30), "The isolated login must survive process restart")
        dismissSourceNotice(in: app)
        app.webViews.buttons["書き出す内容を確認"].tap()
        XCTAssertTrue(app.webViews.buttons["エクスポート"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic PWA migration review after restart"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Exercise the actual native Files picker, rather than injecting a
        // File into the Web document as the browser-only tests do.
        app.webViews.buttons["キャンセル"].tap()
        let fixtureName = try XCTUnwrap(environment["GRIDSPACE_PARITY_FIXTURE_FOLDER"])
        chooseArchive(in: app, folder: fixtureName, prefix: "parity-import")
        let apply = app.webViews.buttons["取り込んで再読み込み"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        XCTAssertFalse(apply.isEnabled)
        app.webViews.staticTexts["このファイルの提供元を信頼し、含まれるCSS・プラグイン・スクリプト設定の適用を許可します。"].tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        apply.tap()
        let confirmImport = app.webViews.buttons["OK"].firstMatch
        XCTAssertTrue(confirmImport.waitForExistence(timeout: 5))
        confirmImport.tap()
        let reloaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [reloaded], timeout: 30), .completed, "Wait for import and the actual document reload before terminating")
        XCTAssertTrue(app.webViews.buttons["書き出す内容を確認"].waitForExistence(timeout: 30))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.webViews.buttons["書き出す内容を確認"].waitForExistence(timeout: 30))
        dismissSourceNotice(in: app)
        app.webViews.buttons["書き出す内容を確認"].tap()
        app.webViews.buttons["エクスポート"].tap()
        // Match the system action exactly: the Web privacy warning also
        // contains the words "file" and "save", and must never satisfy this.
        let save = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["“ファイル”に保存", "ファイルに保存", "\"ファイル\"に保存", "Save to Files"])).firstMatch
        if !save.waitForExistence(timeout: 10) {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("The exported archive must reach the native share sheet")
            return
        }
        let shared = XCTAttachment(screenshot: app.screenshot())
        shared.name = "Synthetic migrated archive in native share sheet"
        shared.lifetime = .keepAlways
        add(shared)
        save.tap()
        openFixtureFolder(in: app, named: fixtureName)
        let saveFile = app.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        XCTAssertTrue(saveFile.waitForExistence(timeout: 5))
        XCTAssertTrue(saveFile.isEnabled)
        saveFile.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveFile)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
        // Restart removes the temporary WKDownload file. Reopening the copy
        // through Files must still work independently of that temporary URL.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.webViews.buttons["移行ファイルを選択"].waitForExistence(timeout: 30))
        dismissSourceNotice(in: app)
        chooseArchive(in: app, folder: fixtureName, prefix: "gridspace-")
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        XCTAssertFalse(apply.isEnabled, "A reopened archive still requires explicit trust")
    }

    func testTwoAccountsSwitchBothWaysAndKeepSelectedIdentityAfterRestart() throws {
        var environment = try configuration()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/accounts"
        let app = launch(environment)
        defer { app.terminate() }
        let primaryName = try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"])
        let secondName = try XCTUnwrap(environment["GRIDSPACE_PARITY_SECOND_USERNAME"])
        submitPassword(in: app, username: primaryName,
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        finishAccountSetup(in: app)
        // The Web's unauthenticated route guard can return to Home before
        // sign-in. Reopen the protected destination with the persisted login.
        app.terminate()
        app.launch()
        let add = app.webViews.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "アカウントを追加")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        dismissSourceNotice(in: app)
        add.tap()
        let existing = accountMenuAction(in: app, endingWith: "既存のアカウント")
        existing.tap()
        fillPasswordDialog(in: app, username: secondName,
                           password: try XCTUnwrap(environment["GRIDSPACE_PARITY_SECOND_PASSWORD"]))
        let submitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.webViews.secureTextFields["パスワード"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [submitted], timeout: 15), .completed)
        // Adding an existing account does not switch automatically. Reopen the
        // real account-management page to obtain the newly persisted card.
        app.terminate()
        app.launch()
        let second = app.webViews.staticTexts["@" + secondName].firstMatch
        if !second.waitForExistence(timeout: 20) {
            self.add(XCTAttachment(string: app.debugDescription))
            XCTFail("The second account must be retained without replacing the selected account")
            return
        }
        dismissSourceNotice(in: app)
        second.tap()
        let change = accountMenuAction(in: app, endingWith: "切り替え")
        change.tap()
        finishAccountSetup(in: app)
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_SECOND_USER_ID"]))
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/accounts"
        app.launchEnvironment = environment
        app.launch()
        let primary = app.webViews.staticTexts["@" + primaryName].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 20))
        dismissSourceNotice(in: app)
        primary.tap()
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_USER_ID"]))
    }

    func testLogoutRemovesWebLoginAndKeepsItRemovedAfterRestart() throws {
        var environment = try configuration()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings"
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        finishAccountSetup(in: app)
        app.terminate()
        app.launch()
        performLogout(in: app)
        let signin = app.webViews.buttons["ログイン"].firstMatch
        XCTAssertTrue(signin.waitForExistence(timeout: 30), "Logout must return to the anonymous PWA")
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/profiles"
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.webViews.textFields["ユーザー名"].firstMatch.waitForExistence(timeout: 30),
                      "A protected route must require sign-in again")
        XCTAssertFalse(app.webViews.buttons["書き出す内容を確認"].exists,
                       "Restart must not restore the logged-out account")
    }

    private func performLogout(in app: XCUIApplication) {
        dismissSourceNotice(in: app)
        let logout = app.webViews.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "ログアウト")).firstMatch
        for _ in 0..<8 {
            if logout.exists && logout.isHittable { break }
            // Use the visible content viewport. WebKit can expose a document
            // frame taller than the screen, making element-relative swipes miss.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !logout.waitForExistence(timeout: 10) || !logout.isHittable {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("The settings page must expose logout")
            return
        }
        logout.tap()
        let confirm = app.webViews.buttons["OK"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    func testSelfOnlyNoteStaysHiddenAfterLogoutBackNavigationAndRestart() throws {
        var environment = try configuration()
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        finishAccountSetup(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/notes/" + (try XCTUnwrap(environment["GRIDSPACE_PARITY_PRIVATE_NOTE_ID"]))
        app.launchEnvironment = environment
        app.launch()
        let body = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic account-isolated note")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 30), "The owner must first see the actual restricted body")
        dismissSourceNotice(in: app)
        let previousDocument = app.webViews.firstMatch.identifier
        XCTAssertTrue(previousDocument.hasPrefix("web-session-"))
        let settings = app.webViews.links["Open synthetic settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        performLogout(in: app)
        XCTAssertTrue(app.webViews.buttons["ログイン"].firstMatch.waitForExistence(timeout: 30))
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let identifier = app.webViews.firstMatch.identifier
            return identifier.hasPrefix("web-session-") && identifier != previousDocument
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 10), .completed,
                       "Logout must replace the actual WebView, not only disable a toolbar")
        let back = app.toolbars.buttons["戻る"].firstMatch
        XCTAssertFalse(back.isEnabled, "The previous account's navigation history must be discarded")
        for _ in 0..<2 {
            if !back.isEnabled { break }
            back.tap()
            // Allow history restoration and the Web's authorization check to
            // finish; an empty provisional frame must not satisfy this check.
            let anonymous = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.webViews.buttons["ログイン"].firstMatch.exists
                    || app.webViews.textFields["ユーザー名"].firstMatch.exists
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [anonymous], timeout: 20), .completed)
            XCTAssertFalse(body.exists, "History must not restore the previous account's restricted body")
            XCTAssertFalse(settings.exists)
        }
        app.terminate()
        app.launch()
        let hidden = app.webViews.staticTexts["(非公開)"].firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 30), "A fresh restricted URL must render the hidden result")
        XCTAssertFalse(body.exists)
        XCTAssertFalse(settings.exists)
    }

    func testTOTPRejectsInvalidCodeThenLogsInAndRestarts() throws {
        #if DEBUG
        var environment = try configuration()
        let secret = try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_SECRET"])
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_PASSWORD"]))
        let field = app.webViews.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "確認コード")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let now = Date().timeIntervalSince1970
        let possible = try Set([-30.0, 0, 30.0].map { try SyntheticTOTP.code(secret: secret, at: now + $0) })
        var wrong = "000000"
        while possible.contains(wrong) { wrong = String(format: "%06d", Int(wrong)! + 1) }
        field.tap()
        app.typeText(wrong)
        dismissKeyboard(in: app)
        continueButton(in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["ワンタイムパスワードが間違っているか、期限切れになっています。"].waitForExistence(timeout: 10))
        app.webViews.buttons["わかった"].tap()
        // Restart the same named store without clearing app data. The rejected
        // code must not have established a session. A new ordinary sign-in also
        // avoids depending on the OS edit menu to replace the previous input.
        app.terminate()
        app.launch()
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_PASSWORD"]))
        let retryField = app.webViews.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "確認コード")).firstMatch
        XCTAssertTrue(retryField.waitForExistence(timeout: 10))
        XCTAssertEqual(retryField.value as? String ?? "", "")
        // Use the next period, preserving the server's real replay protection.
        let instant = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: (floor(instant / 30) + 1) * 30 + 1 - instant)
        let code = try SyntheticTOTP.code(secret: secret, at: Date().timeIntervalSince1970)
        retryField.tap()
        app.typeText(code)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", code), object: retryField)
        if XCTWaiter.wait(for: [typed], timeout: 5) != .completed {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Synthetic TOTP retry input"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTFail("The replacement TOTP must be committed before submitting")
            return
        }
        dismissKeyboard(in: app)
        continueButton(in: app).tap()
        finishAccountSetup(in: app)
        confirmAccountAfterRestart(in: app, environment: &environment, userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USER_ID"]))
        #else
        throw XCTSkip("Local PWA tests require Debug")
        #endif
    }

    func testTOTPAllowsCorrectingRejectedCodeInSameField() throws {
        #if DEBUG
        var environment = try configuration()
        let secret = try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_SECRET"])
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_PASSWORD"]))
        let field = app.webViews.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "確認コード")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let now = Date().timeIntervalSince1970
        let possible = try Set([-30.0, 0, 30.0].map { try SyntheticTOTP.code(secret: secret, at: now + $0) })
        var wrong = "000000"
        while possible.contains(wrong) { wrong = String(format: "%06d", Int(wrong)! + 1) }
        field.tap()
        app.typeText(wrong)
        dismissKeyboard(in: app)
        continueButton(in: app).tap()
        XCTAssertTrue(app.webViews.staticTexts["ワンタイムパスワードが間違っているか、期限切れになっています。"].waitForExistence(timeout: 10))
        app.webViews.buttons["わかった"].tap()
        XCTAssertEqual(field.value as? String, wrong)
        let instant = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: (floor(instant / 30) + 1) * 30 + 1 - instant)
        let code = try SyntheticTOTP.code(secret: secret, at: Date().timeIntervalSince1970)
        // Focusing raises the keyboard and moves the centered sign-in form.
        // Finish that layout change before pressing to open the edit menu.
        field.tap()
        field.press(forDuration: 1.1)
        let labels = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH[c] %@", "すべて", "Select All")
        let selectAll = app.buttons.matching(labels).firstMatch
        let selectAllMenu = app.menuItems.matching(labels).firstMatch
        let copyLabels = NSPredicate(format: "label IN %@", ["コピー", "Copy"])
        let copy = app.buttons.matching(copyLabels).firstMatch
        let copyMenu = app.menuItems.matching(copyLabels).firstMatch
        let selecting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            selectAll.exists || selectAllMenu.exists || copy.exists || copyMenu.exists
        }, object: app)
        if XCTWaiter.wait(for: [selecting], timeout: 5) != .completed {
            add(XCTAttachment(string: app.debugDescription))
            XCTFail("The native editor must expose its selection menu")
            return
        }
        let selectionState = XCTAttachment(string: app.debugDescription)
        selectionState.name = "Synthetic rejected-code selection menu"
        selectionState.lifetime = .keepAlways
        add(selectionState)
        if selectAll.exists { selectAll.tap() } else if selectAllMenu.exists { selectAllMenu.tap() }
        app.typeText(code)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", code), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 5), .completed,
                       "Editing must replace the rejected code rather than append to it")
        dismissKeyboard(in: app)
        continueButton(in: app).tap()
        finishAccountSetup(in: app)
        confirmAccountAfterRestart(in: app, environment: &environment,
                                   userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USER_ID"]))
        #else
        throw XCTSkip("Local PWA tests require Debug")
        #endif
    }

    func testBackupCodeLogsInOnceAndRejectsReuse() throws {
        var environment = try configuration()
        let name = try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USERNAME"])
        let password = try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_PASSWORD"])
        let backup = try XCTUnwrap(environment["GRIDSPACE_PARITY_BACKUP_CODE"])
        var app = launch(environment)
        defer { app.terminate() }
        func submitBackup() {
            submitPassword(in: app, username: name, password: password)
            let mode = app.webViews.buttons["バックアップコードを使う"]
            XCTAssertTrue(mode.waitForExistence(timeout: 10))
            dismissKeyboard(in: app)
            mode.tap()
            let field = app.webViews.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "確認コード")).firstMatch
            if !field.waitForExistence(timeout: 5) {
                add(XCTAttachment(string: app.debugDescription))
                XCTFail("The backup-code mode must expose its labelled input")
                return
            }
            field.tap()
            app.typeText(backup)
            let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", backup), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: 5), .completed)
            dismissKeyboard(in: app)
            continueButton(in: app).tap()
        }
        submitBackup()
        finishAccountSetup(in: app)
        confirmAccountAfterRestart(in: app, environment: &environment, userID: try XCTUnwrap(environment["GRIDSPACE_PARITY_TOTP_USER_ID"]))
        app.terminate()
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        environment.removeValue(forKey: "GRIDSPACE_PARITY_PATH")
        app = launch(environment)
        submitBackup()
        XCTAssertTrue(app.webViews.staticTexts["ワンタイムパスワードが間違っているか、期限切れになっています。"].waitForExistence(timeout: 10))
    }

    func testFirstPartySecureAppListAndRevocation() throws {
        var environment = try configuration()
        let name = try XCTUnwrap(environment["GRIDSPACE_PARITY_APP_NAME"])
        let app = launch(environment)
        defer { app.terminate() }
        submitPassword(in: app, username: try XCTUnwrap(environment["GRIDSPACE_PARITY_USERNAME"]),
                       password: try XCTUnwrap(environment["GRIDSPACE_PARITY_PASSWORD"]))
        finishAccountSetup(in: app)
        app.terminate()
        environment["GRIDSPACE_PARITY_PATH"] = "/settings/apps"
        app.launchEnvironment = environment
        app.launch()
        let fixture = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 30), "The secure i/apps response must reach the first-party Web UI")
        app.webViews.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "削除")).firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["ありません"].waitForExistence(timeout: 10))
        XCTAssertFalse(fixture.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["ありません"].waitForExistence(timeout: 30))
        XCTAssertFalse(fixture.exists, "Revoking the synthetic application must persist across restart")
    }

    func testWrongCertificatePinCannotOpenPWA() throws {
        var environment = try configuration()
        environment["GRIDSPACE_PARITY_CERT_SHA256"] = String(repeating: "0", count: 64)
        let app = launch(environment)
        defer { app.terminate() }
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ページを読み込めませんでした。")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 30))
        XCTAssertFalse(app.webViews.buttons["ログイン"].exists)
    }
}
