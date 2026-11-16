// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import CoreGraphics

@MainActor
final class NativeComposerUITests: XCTestCase {
    private var dedicatedSimulator: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "GridSpace Composer QA"
        #else
        return false
        #endif
    }
    private func start() throws -> XCUIApplication {
        guard dedicatedSimulator else {
            throw XCTSkip("Photo UI QA requires the dedicated GridSpace Composer QA Simulator with its two synthetic PNGs; it never opens the user's library")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--native-client-fixture", "--native-composer-fixture"]
        app.launchEnvironment["GRIDSPACE_COMPOSER_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["native-feed-tab:home"].waitForExistence(timeout: 20))
        let compose = app.buttons["native-floating-compose"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: compose)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        compose.tap()
        XCTAssertTrue(app.textViews["native-compose-text"].waitForExistence(timeout: 10))
        return app
    }
    private func cancelPhotoPicker(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        let back = app.navigationBars["投稿"].buttons["閉じる"]
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists && back.exists && back.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
    }
    func testPhotoButtonOpensSystemPickerDirectlyAndCancelKeepsTheText() throws {
        let app = try start(); defer { app.terminate() }
        let editor = app.textViews["native-compose-text"]
        editor.tap(); editor.typeText("Synthetic photo compose")
        let photos = app.buttons["native-compose-photos"]
        XCTAssertTrue(photos.isHittable); photos.tap()
        cancelPhotoPicker(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); XCTAssertEqual(editor.value as? String, "Synthetic photo compose")
    }
    #if targetEnvironment(simulator)
    private func syntheticPhotoPoints(_ app: XCUIApplication) -> [CGPoint]? {
        guard let image = app.screenshot().image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        guard drawn else { return nil }
        let colors = [(140, 103, 226), (44, 169, 175)]
        var points: [CGPoint] = []
        for color in colors {
            var count = 0, xSum = 0, ySum = 0
            for y in stride(from: 0, to: image.height, by: 3) {
                for x in stride(from: 0, to: image.width, by: 3) {
                    let offset = (y * image.width + x) * 4
                    if abs(Int(bytes[offset]) - color.0) < 4 && abs(Int(bytes[offset + 1]) - color.1) < 4 && abs(Int(bytes[offset + 2]) - color.2) < 4 {
                        count += 1; xSum += x; ySum += y
                    }
                }
            }
            guard count > 1000 else { return nil }
            points.append(CGPoint(x: CGFloat(xSum) / CGFloat(count) * app.frame.width / CGFloat(image.width),
                                  y: CGFloat(ySum) / CGFloat(count) * app.frame.height / CGFloat(image.height)))
        }
        return points
    }
    #endif

    func testTwoPhotosCanBeEditedReorderedAndPostedWithoutAManualUploadStep() async throws {
        #if targetEnvironment(simulator)
        let app = try start(); defer { app.terminate() }
        let text = "Synthetic photos posted together"
        app.textViews["native-compose-text"].typeText(text)
        app.buttons["native-compose-photos"].tap()
        // A dedicated Simulator contains two solid-color QA PNGs. Identify
        // their actual rendered pixels: iOS 26's remote PhotosPicker reports
        // stale/non-hittable accessibility grid items across presentations.
        let library = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photospicker")
        var points: [CGPoint]?
        for _ in 0..<30 {
            if library.buttons["OK"].exists { library.buttons["OK"].tap() }
            points = syntheticPhotoPoints(app)
            if points != nil { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let selected = try XCTUnwrap(points, "Seed the dedicated Simulator with the two known QA PNGs")
        for point in selected { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap() }
        let confirm = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label IN %@", "追加", "Add", ["Done", "完了"]))
        let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in confirm.allElementsBoundByIndex.contains { $0.isHittable } }, object: nil)
        await fulfillment(of: [confirmed], timeout: 10)
        confirm.allElementsBoundByIndex.first { $0.isHittable }?.tap()
        let edits = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "native-attachment-edit:"))
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in edits.count == 2 }, object: nil)
        await fulfillment(of: [imported], timeout: 20)
        XCTAssertEqual(edits.count, 2)
        edits.firstMatch.tap()
        let alt = app.descendants(matching: .any).matching(identifier: "native-attachment-comment").firstMatch
        XCTAssertTrue(alt.waitForExistence(timeout: 10)); alt.tap(); alt.typeText("Synthetic image description")
        app.navigationBars["添付を編集"].buttons["完了"].tap()
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "native-attachment-actions:")).firstMatch
        actions.tap(); app.buttons["後へ"].tap()
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.name = "Composer image previews"; preview.lifetime = .keepAlways; add(preview)
        app.navigationBars["投稿"].buttons["閉じる"].tap(); app.buttons["保存して閉じる"].tap()
        app.buttons["native-floating-compose"].tap()
        XCTAssertTrue(app.textViews["native-compose-text"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textViews["native-compose-text"].value as? String, text)
        app.buttons["native-compose-photos"].tap()
        cancelPhotoPicker(app)
        let send = app.buttons["native-compose-send"]
        XCTAssertTrue(send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 20))
        #else
        throw XCTSkip("Photo library selection uses only the two owned synthetic Simulator images")
        #endif
    }

}
