// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

/// Explicit opt-in only: drive the normal, signed-in app without fixture
/// arguments, changing account data, or attaching screenshots/note contents.
@MainActor
final class NativeLiveScrollProfiling: XCTestCase {
    func testNormalTimelineScrollingMetrics() throws {
        guard ProcessInfo.processInfo.environment["GRIDSPACE_PROFILE_LIVE_APP"] == "1" else {
            throw XCTSkip("Explicit normal-app profiling only")
        }
        let app = XCUIApplication(); app.activate()
        guard app.buttons["native-tab:タイムライン"].waitForExistence(timeout: 20) else { throw XCTSkip("Normal app unavailable") }
        app.buttons["native-tab:タイムライン"].tap()
        let list = app.collectionViews["native-timeline"]
        guard list.waitForExistence(timeout: 15) else { throw XCTSkip("Select a normal timeline before profiling") }
        let rect = list.frame, base = app.coordinate(withNormalizedOffset: .zero)
        let lower = base.withOffset(CGVector(dx: rect.minX + rect.width * 0.45, dy: rect.minY + rect.height * 0.75))
        let upper = base.withOffset(CGVector(dx: rect.minX + rect.width * 0.45, dy: rect.minY + rect.height * 0.3))
        let options = XCTMeasureOptions(); options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            lower.press(forDuration: 0.02, thenDragTo: upper, withVelocity: .fast, thenHoldForDuration: 0)
            upper.press(forDuration: 0.02, thenDragTo: lower, withVelocity: .fast, thenHoldForDuration: 0)
        }
    }
    func testScrollNormalTimelineForInstruments() async throws {
        guard ProcessInfo.processInfo.environment["GRIDSPACE_PROFILE_LIVE_APP"] == "1" else {
            throw XCTSkip("Set GRIDSPACE_PROFILE_LIVE_APP=1 in the test runner to profile the normal app")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.activate()
        let timeline = app.buttons["native-tab:タイムライン"]
        guard timeline.waitForExistence(timeout: 20) else { throw XCTSkip("Normal app navigation unavailable") }
        timeline.tap()
        let list = app.collectionViews["native-timeline"]
        guard list.waitForExistence(timeout: 15) else { throw XCTSkip("Select a normal timeline before profiling") }
        // Resolve the viewport once. Resolving the whole timeline's AX tree
        // for each coordinate adds sizeable main-thread work to the recording.
        let rect = list.frame, base = app.coordinate(withNormalizedOffset: .zero)
        let lower = base.withOffset(CGVector(dx: rect.minX + rect.width * 0.45, dy: rect.minY + rect.height * 0.75))
        let upper = base.withOffset(CGVector(dx: rect.minX + rect.width * 0.45, dy: rect.minY + rect.height * 0.3))
        print("GRIDSPACE_PROFILE_DEVICE low_power=\(ProcessInfo.processInfo.isLowPowerModeEnabled) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
        print("GRIDSPACE_PROFILE_READY")
        // Give the host time to attach Instruments to the normal app process.
        try await Task.sleep(nanoseconds: 12_000_000_000)
        for pass in 0..<18 {
            let from = pass % 6 < 4 ? lower : upper, to = pass % 6 < 4 ? upper : lower
            from.press(forDuration: 0.02, thenDragTo: to,
                withVelocity: .default, thenHoldForDuration: 0.05)
        }
        print("GRIDSPACE_PROFILE_FINISHED")
    }
}
