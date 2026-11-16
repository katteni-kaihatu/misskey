// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

final class NativeDraftStoreTests: XCTestCase {
    func testQuoteDraftUsesItsOwnTargetScopeAndKeepsTheUnknownResultAcrossRestart() throws {
        let name = "NativeQuoteDraftTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = NativeDraftStore(defaults: defaults), origin = try ServerOrigin("https://synthetic.example")
        let draft = NativeDraft(text: "Own synthetic quotation", outcomeUnknown: true)
        store.write(draft, origin: origin, account: "owner", reply: nil, renote: "target")
        let reopened = NativeDraftStore(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
        XCTAssertEqual(reopened.read(origin: origin, account: "owner", reply: nil, renote: "target"), draft)
        XCTAssertNil(reopened.read(origin: origin, account: "owner", reply: "target"))
        XCTAssertNil(reopened.read(origin: origin, account: "owner", reply: nil))
        XCTAssertNil(reopened.read(origin: origin, account: "other", reply: nil, renote: "target"))
        XCTAssertNil(reopened.read(origin: origin, account: "owner", reply: nil, renote: "other"))
        reopened.remove(origin: origin, account: "owner", reply: "target")
        XCTAssertEqual(reopened.read(origin: origin, account: "owner", reply: nil, renote: "target"), draft)
        reopened.remove(origin: origin, account: "owner", reply: nil, renote: "target")
        XCTAssertNil(reopened.read(origin: origin, account: "owner", reply: nil, renote: "target"))
    }
    func testOwnDraftAndUnknownOutcomeSurviveRestartWithoutCrossingAccountOrReplyScope() throws {
        let name = "NativeDraftTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let origin = try ServerOrigin("https://synthetic.example")
        let store = NativeDraftStore(defaults: preferences)
        let draft = NativeDraft(text: "synthetic own draft", cw: "synthetic CW", useCW: true, visibility: "followers", outcomeUnknown: true)
        store.write(draft, origin: origin, account: "one", reply: "target")
        let reopened = NativeDraftStore(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
        XCTAssertEqual(reopened.read(origin: origin, account: "one", reply: "target"), draft)
        XCTAssertNil(reopened.read(origin: origin, account: "two", reply: "target"))
        XCTAssertNil(reopened.read(origin: origin, account: "one", reply: nil))
        XCTAssertNil(reopened.read(origin: try ServerOrigin("https://synthetic.example:8443"), account: "one", reply: "target"))
        reopened.remove(origin: origin, account: "two", reply: "target")
        XCTAssertEqual(reopened.read(origin: origin, account: "one", reply: "target"), draft)
        reopened.remove(origin: origin, account: "one", reply: "target")
        XCTAssertNil(reopened.read(origin: origin, account: "one", reply: "target"))
    }
}

@MainActor
final class NativeClientSessionTests: XCTestCase {
    func testBackgroundInvalidatesOldResultsAndAnotherBackgroundCannotBeOvertakenByResume() async throws {
        let session = NativeClientSession(origin: try ServerOrigin("https://synthetic.example"))
        let before = session.revision
        await session.visibility(false)
        XCTAssertFalse(session.active); XCTAssertFalse(session.accepts(before))
        let resume = Task { await session.visibility(true) }
        await Task.yield()
        await session.visibility(false)
        await resume.value
        XCTAssertFalse(session.active); XCTAssertFalse(session.accepts(before)); XCTAssertNil(session.user)
        await session.visibility(true)
        XCTAssertTrue(session.active); XCTAssertFalse(session.accepts(before)); XCTAssertTrue(session.accepts(session.revision))
    }
}
