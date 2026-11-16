// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import CoreGraphics

@MainActor
final class NativeEmojiUITests: XCTestCase {
    private func start() async throws -> (XCUIApplication, PairedParityControl.State, [String: String]) {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GRIDSPACE_PARITY_") }
        guard environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1" else { throw XCTSkip("An isolated paired backend is required") }
        continueAfterFailure = false
        let fixture = try await PairedParityControl.perform("native-emoji-prepare", environment: environment)
        let auth = try await PairedParityControl.perform("native-auth", environment: environment)
        environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"] = try XCTUnwrap(auth.session)
        environment["GRIDSPACE_PARITY_STORE"] = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--local-parity-server", "--native-client-fixture"]
        app.launchEnvironment = environment; app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["native-tab:プロフィール"].exists)
        XCTAssertFalse(app.buttons["native-tab:Web"].exists)
        XCTAssertFalse(app.textFields["server-address"].exists)
        if app.tabBars.count != 0 { diagnose(app) }
        XCTAssertEqual(app.tabBars.count, 0, "Only the native fixed icon bar should be visible")
        return (app, fixture, environment)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.6))
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.22))
            bottom.press(forDuration: 0.05, thenDragTo: top)
        }
        diagnose(app); XCTAssertTrue(element.exists && element.isHittable)
    }
    private func diagnose(_ app: XCUIApplication) {
        if app.state == .runningForeground { add(XCTAttachment(string: app.debugDescription)) }
        #if targetEnvironment(simulator)
        if app.state == .runningForeground { add(XCTAttachment(screenshot: app.screenshot())) }
        #endif
    }
    private func capture(_ app: XCUIApplication, name: String) {
        #if targetEnvironment(simulator)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        #endif
    }
    private func assertSyntheticPreview(_ element: XCUIElement, app: XCUIApplication) async {
        #if targetEnvironment(simulator)
        // The owned fixture is a yellow PNG. Confirm actual downloaded pixels,
        // rather than allowing a generic loading/error icon to pass this test.
        for _ in 0..<20 {
            guard app.state == .runningForeground else { XCTFail("Keep image QA inside the synthetic foreground app"); return }
            if hasYellowPreview(element, app: app) { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        diagnose(app); XCTFail("The synthetic custom emoji image must render")
        #endif
    }
    #if targetEnvironment(simulator)
    private func hasYellowPreview(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        guard let image = app.screenshot().image.cgImage, element.exists else { return false }
        let frame = element.frame, bounds = app.frame
        let region = CGRect(x: frame.minX * CGFloat(image.width) / bounds.width,
                            y: frame.minY * CGFloat(image.height) / bounds.height,
                            width: frame.width * CGFloat(image.width) / bounds.width,
                            height: frame.height * CGFloat(image.height) / bounds.height)
        guard let cropped = image.cropping(to: region), cropped.width > 0, cropped.height > 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: cropped.width, height: cropped.height,
                bitsPerComponent: 8, bytesPerRow: cropped.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)); return true
        }
        guard rendered else { return false }
        return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 210 && bytes[$0 + 1] > 140 && bytes[$0 + 1] < 235 && bytes[$0 + 2] < 120 && bytes[$0 + 3] > 200 }.count > 30
    }
    #endif
    private func searchPicker(_ app: XCUIApplication, text: String) {
        let search = app.textFields["native-emoji-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(text)
    }
    private func waitPickerClosed(_ app: XCUIApplication) async {
        let bar = app.navigationBars["絵文字"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !bar.exists }, object: app)
        await fulfillment(of: [gone], timeout: 15)
        XCTAssertFalse(bar.exists)
    }
    func testCustomAndUnicodeReactionsSearchRestrictionsChangeAndRemoval() async throws {
        let (app, fixture, environment) = try await start(); defer { app.terminate() }
        let id = try XCTUnwrap(fixture.emojiNoteID)
        capture(app, name: "Native feed with underline tabs")
        app.buttons["native-tab:検索"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap()
        search.typeText("Synthetic emoji picker target " + (try XCTUnwrap(fixture.emojiTag)) + "\n")
        let picker = app.buttons["native-note-reaction:" + id]
        XCTAssertTrue(picker.waitForExistence(timeout: 30)); reveal(picker, app: app)
        picker.tap()
        app.segmentedControls.buttons["カスタム"].tap()
        let wave = app.buttons["native-emoji:native_wave"]
        if !wave.waitForExistence(timeout: 20) { diagnose(app) }
        XCTAssertTrue(wave.exists)
        XCTAssertTrue(wave.isEnabled)
        await assertSyntheticPreview(wave, app: app)
        XCTAssertFalse(app.buttons["native-emoji:native_locked"].isEnabled)
        XCTAssertFalse(app.buttons["native-emoji:native_sensitive"].exists)
        app.descendants(matching: .any).matching(identifier: "native-emoji-sensitive").firstMatch.tap()
        XCTAssertTrue(app.buttons["native-emoji:native_sensitive"].waitForExistence(timeout: 5))
        searchPicker(app, text: "拍手")
        capture(app, name: "Native custom emoji picker")
        wave.tap(); await waitPickerClosed(app)
        let chip = app.buttons["native-reaction:" + id + ":" + ":native_wave@.:"]
        if !chip.waitForExistence(timeout: 20) { diagnose(app) }
        XCTAssertTrue(chip.exists)
        var state = try await PairedParityControl.perform("native-emoji-status", environment: environment)
        XCTAssertEqual(state.emojiReaction, ":native_wave@.:"); XCTAssertEqual(state.emojiReactionCount, 1); XCTAssertEqual(state.emojiWrites, 1)
        picker.tap(); app.segmentedControls.buttons["標準"].tap()
        searchPicker(app, text: "嬉し泣き")
        let unicode = app.buttons["native-emoji:😂"]
        XCTAssertTrue(unicode.waitForExistence(timeout: 10)); unicode.tap(); await waitPickerClosed(app)
        let updated = app.buttons["native-reaction:" + id + ":😂"]
        XCTAssertTrue(updated.waitForExistence(timeout: 20))
        state = try await PairedParityControl.perform("native-emoji-status", environment: environment)
        XCTAssertEqual(state.emojiReaction, "😂"); XCTAssertEqual(state.emojiReactionCount, 1); XCTAssertEqual(state.emojiWrites, 2)
        picker.tap(); app.buttons["native-emoji-remove"].tap(); await waitPickerClosed(app)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !updated.exists }, object: app)
        await fulfillment(of: [removed], timeout: 20)
        state = try await PairedParityControl.perform("native-emoji-status", environment: environment)
        XCTAssertNil(state.emojiReaction); XCTAssertEqual(state.emojiReactionCount, 0); XCTAssertEqual(state.emojiWrites, 2)
    }
    func testComposerInsertsCustomAndUnicodeThenRestoresAndPostsTheExactDraft() async throws {
        let (app, _, environment) = try await start(); defer { app.terminate() }
        let compose = app.buttons["native-floating-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in compose.isEnabled }, object: app)
        await fulfillment(of: [enabled], timeout: 15)
        XCTAssertTrue(compose.isEnabled); compose.tap()
        let editor = app.textViews["native-compose-text"]
        if !editor.waitForExistence(timeout: 10) { diagnose(app) }
        XCTAssertTrue(editor.exists); editor.tap(); editor.typeText("Synthetic native emoji ")
        let emoji = app.buttons["native-compose-emoji"]
        reveal(emoji, app: app); emoji.tap()
        searchPicker(app, text: "native_wave")
        let wave = app.buttons["native-emoji:native_wave"]
        if !wave.waitForExistence(timeout: 20) { diagnose(app) }
        XCTAssertTrue(wave.exists); wave.tap(); await waitPickerClosed(app)
        XCTAssertEqual(editor.value as? String, "Synthetic native emoji :native_wave:")
        reveal(emoji, app: app); emoji.tap(); app.segmentedControls.buttons["標準"].tap()
        searchPicker(app, text: "嬉し泣き"); app.buttons["native-emoji:😂"].tap(); await waitPickerClosed(app)
        let expected = "Synthetic native emoji :native_wave:😂"
        XCTAssertEqual(editor.value as? String, expected)
        capture(app, name: "Native composer with emoji insertion")
        app.navigationBars.buttons["閉じる"].tap(); app.buttons["保存して閉じる"].tap()
        XCTAssertTrue(compose.waitForExistence(timeout: 10)); compose.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); XCTAssertEqual(editor.value as? String, expected)
        app.buttons["native-compose-send"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !editor.exists }, object: app)
        await fulfillment(of: [gone], timeout: 30)
        let state = try await PairedParityControl.perform("native-emoji-status", environment: environment)
        XCTAssertTrue(state.emojiComposedTexts?.contains(expected) == true)
    }
}
