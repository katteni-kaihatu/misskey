// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
import UIKit
@testable import GridSpace

@MainActor
final class NativeEmojiTests: XCTestCase {
    private func seed() throws -> ClientNote { try reactionNote(nil) }
    func testCustomSelectionPreflightsThenReplacesWithOneCreateAndReadsTheActualResult() async throws {
        let original = try seed()
        let api = EmojiAPIStub(current: "👍"), model = NativeReactionModel(), custom = try reactionEmoji()
        await model.apply(NativeEmojiChoice(value: custom.shortcode, custom: custom), to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertEqual(model.note?.myReaction, ":synthetic@.:"); XCTAssertFalse(model.unknown); XCTAssertNil(model.error)
        let writes = await api.writes; XCTAssertEqual(writes, ["DELETE", ":synthetic:"])
        let reads = await api.metadataReads; XCTAssertEqual(reads, 1)
    }
    func testLocalReactionChipUsesFreshMetadataAndTheCanonicalShortcode() async throws {
        let original = try seed(), api = EmojiAPIStub(), model = NativeReactionModel()
        await model.apply(NativeEmojiChoice(value: ":synthetic@.:", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertEqual(writes, [":synthetic:"])
        let reads = await api.metadataReads; XCTAssertEqual(reads, 1)
    }
    func testSameEmojiTogglesRemovalButStaleRemovalDoesNotEraseAnotherReaction() async throws {
        let original = try reactionNote(":synthetic@.:")
        let api = EmojiAPIStub(current: ":synthetic@.:"), model = NativeReactionModel(), custom = try reactionEmoji()
        await model.apply(NativeEmojiChoice(value: custom.shortcode, custom: custom), to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertNil(model.note?.myReaction)
        let writes = await api.writes; XCTAssertEqual(writes, ["DELETE"])
        await api.setCurrent("👍")
        await model.apply(nil, to: try seed(), owner: "owner", api: api, accepts: { true })
        let after = await api.writes; XCTAssertEqual(after, writes); XCTAssertNotNil(model.error)
    }
    func testAnAddAlreadyAppliedElsewhereNeverTurnsIntoAnUnexpectedRemoval() async throws {
        let original = try seed(), api = EmojiAPIStub(current: "👍"), model = NativeReactionModel()
        await model.apply(NativeEmojiChoice(value: "👍", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(model.note?.myReaction, "👍")
    }
    func testPickingTheDisplayedReactionCannotReplaceANewerReactionFromAnotherClient() async throws {
        let original = try reactionNote("👍"), api = EmojiAPIStub(current: "😂"), model = NativeReactionModel()
        await model.apply(NativeEmojiChoice(value: "👍", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(model.note?.myReaction, "😂"); XCTAssertNotNil(model.error)
    }
    func testChangedEmojiRestrictionStopsTheWriteAfterFreshMetadata() async throws {
        let original = try seed()
        let api = EmojiAPIStub(restricted: true), model = NativeReactionModel(), custom = try reactionEmoji()
        await model.apply(NativeEmojiChoice(value: custom.shortcode, custom: custom), to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty); XCTAssertNotNil(model.error)
    }
    func testChangedAccountStopsSelectionBeforeAnyWrite() async throws {
        let original = try seed()
        let api = EmojiAPIStub(owner: "different"), model = NativeReactionModel()
        await model.apply(NativeEmojiChoice(value: "👍", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testLostAcknowledgementBlocksReplayUntilExplicitReadAndShowsServerState() async throws {
        let original = try seed()
        let api = EmojiAPIStub(loseResponse: true), model = NativeReactionModel(), choice = NativeEmojiChoice(value: "👍", custom: nil)
        await model.apply(choice, to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertTrue(model.unknown)
        await model.apply(choice, to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertEqual(writes, ["👍"])
        await model.refresh(id: "note", api: api, accepts: { true })
        XCTAssertFalse(model.unknown); XCTAssertEqual(model.note?.myReaction, "👍")
    }
    func testLateReadAndSelectionAfterClearCannotWrite() async throws {
        let original = try seed()
        let api = EmojiAPIStub(holdRead: true), model = NativeReactionModel()
        let task = Task { await model.apply(NativeEmojiChoice(value: "👍", custom: nil), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        model.clear(); await api.release(); await task.value
        XCTAssertNil(model.note)
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testRevokedVisibilityReplacesTheOldBodyWithTheHiddenEnvelope() async throws {
        let api = EmojiAPIStub(), model = NativeReactionModel()
        await model.refresh(id: "note", api: api, accepts: { true })
        await api.hide()
        await model.refresh(id: "note", api: api, accepts: { true })
        XCTAssertEqual(model.note?.isHidden, true)
    }
    func testExpiredAuthenticationRequestsSignInWithoutSendingAReaction() async throws {
        let original = try seed(), api = EmojiAPIStub(), model = NativeReactionModel()
        await api.expire()
        await model.apply(NativeEmojiChoice(value: "👍", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertTrue(model.requiresSignIn)
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testComposerKeepsTheInsertionPositionWhenTheFormRecyclesItsEditor() throws {
        let state = NativeComposerTextState(), view = UITextView()
        state.view = view; view.text = "AB"; view.selectedRange = NSRange(location: 1, length: 0)
        state.remember(view); state.view = nil
        XCTAssertTrue(state.prepareEmoji(expectedText: "AB"))
        XCTAssertEqual(state.insert(":synthetic:", expectedText: "AB"), "A:synthetic:B")
        XCTAssertEqual(state.selection(for: "A:synthetic:B"), NSRange(location: 12, length: 0))
        XCTAssertTrue(state.prepareEmoji(expectedText: "A:synthetic:B"))
        XCTAssertEqual(state.insert("😂", expectedText: "A:synthetic:B"), "A:synthetic:😂B")
    }
    func testComposerReplacesUTF16SelectionWithoutBreakingFamilyEmojiAndRejectsChangedText() throws {
        let state = NativeComposerTextState(), view = UITextView()
        state.view = view; view.text = "A👨‍👨‍👧‍👧B"
        view.selectedRange = NSRange(location: 1, length: ("👨‍👨‍👧‍👧" as NSString).length)
        state.prepareEmoji()
        XCTAssertEqual(state.insert(":synthetic:", expectedText: "A👨‍👨‍👧‍👧B"), "A:synthetic:B")
        XCTAssertEqual(view.selectedRange.location, 12)
        state.prepareEmoji(); view.text = "changed"
        XCTAssertNil(state.insert("👍", expectedText: "A:synthetic:B")); XCTAssertEqual(view.text, "changed")
        state.clear(); XCTAssertNil(state.insert("👍", expectedText: "changed"))
    }
}

private func reactionEmoji(restricted: Bool = false) throws -> ClientCustomEmoji {
    try JSONDecoder().decode(ClientCustomEmoji.self, from: Data("{\"name\":\"synthetic\",\"aliases\":[],\"url\":\"https://synthetic.example/emoji.png\",\"roleIdsThatCanBeUsedThisEmojiAsReaction\":\(restricted ? "[\"restricted\"]" : "[]")}".utf8))
}
private func reactionNote(_ current: String?, hidden: Bool = false) throws -> ClientNote {
    var body: [String: Any] = ["id": "note", "createdAt": "2026-11-16T00:00:00Z", "visibility": "home", "gridspaceReactions": false, "user": ["id": "author", "username": "synthetic", "host": "ordinary.example"], "reactions": [:]]
    if hidden { body["isHidden"] = true }
    if let current { body["myReaction"] = current }
    return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: body))
}
private actor EmojiAPIStub: NativeEmojiAPI {
    var current: String?, owner: String
    var hidden = false, expired = false
    let restricted: Bool, loseResponse: Bool, holdRead: Bool
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    private(set) var writes: [String] = []
    private(set) var metadataReads = 0
    init(current: String? = nil, owner: String = "owner", restricted: Bool = false, loseResponse: Bool = false, holdRead: Bool = false) {
        self.current = current; self.owner = owner; self.restricted = restricted; self.loseResponse = loseResponse; self.holdRead = holdRead
    }
    func emojis() throws -> [ClientCustomEmoji] { [try reactionEmoji()] }
    func emoji(_ name: String) throws -> ClientCustomEmoji { metadataReads += 1; return try reactionEmoji(restricted: restricted) }
    func note(_ id: String) async throws -> ClientNote {
        if holdRead { await withCheckedContinuation { continuation = $0 } }
        if expired { throw ClientAPIError.rejected(status: 401, code: "AUTHENTICATION_FAILED") }
        return try reactionNote(current, hidden: hidden)
    }
    func account() throws -> ClientUser { try JSONDecoder().decode(ClientUser.self, from: JSONSerialization.data(withJSONObject: ["id": owner, "username": "synthetic", "roles": []])) }
    func react(note: String, reaction: String, extended: Bool) throws {
        writes.append(reaction); current = reaction.hasPrefix(":") ? ":synthetic@.:" : reaction
        if loseResponse { throw URLError(.networkConnectionLost) }
    }
    func removeReaction(note: String, reaction: String?, extended: Bool) { writes.append("DELETE"); current = nil }
    func hide() { hidden = true }
    func expire() { expired = true }
    func setCurrent(_ value: String) { current = value }
    func release() { continuation?.resume(); continuation = nil }
}
