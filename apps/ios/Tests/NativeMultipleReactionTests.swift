// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeMultipleReactionTests: XCTestCase {
    func testLiveSnapshotCannotUndoAPendingOptimisticReactionAndCanApplyAfterItSettles() async throws {
        let api = MultiReactionAPI(own: ["👍"]), model = NativeReactionModel(), original = try await api.note("note")
        model.receive(original); await api.holdNextRead()
        let task = Task { await model.apply(.init(value: "😂", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; await Task.yield() }
        let stale = try JSONDecoder().decode(ClientReactionState.self, from: Data(#"{"noteId":"note","reactions":{"👍":1},"reactionEmojis":{},"myReactions":["👍"],"complete":true}"#.utf8))
        XCTAssertFalse(model.receiveLive(stale, expectedVersion: model.version))
        XCTAssertTrue(model.note?.hasOwnReaction("😂") == true)
        await api.release(); await task.value
        let current = try JSONDecoder().decode(ClientReactionState.self, from: Data(#"{"noteId":"note","reactions":{"👍":1,"😂":2},"reactionEmojis":{},"myReactions":["👍","😂"],"complete":true}"#.utf8))
        XCTAssertTrue(model.receiveLive(current, expectedVersion: model.version))
        XCTAssertEqual(model.note?.reactions?["😂"], 2); XCTAssertTrue(model.note?.hasOwnReaction("😂") == true)
    }
    func testSessionStoreKeepsDetachedRowWritesAndDoesNotUndoThemWhenTheSameFeedRowRemounts() async throws {
        let api = MultiReactionAPI(own: ["👍"]), store = NativeReactionStore(), original = try await api.note("note")
        let model = store.model("note"); model.receive(original)
        await api.holdNextRead()
        let task = Task { await model.apply(.init(value: "😂", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; await Task.yield() }
        let remounted = store.model("note")
        XCTAssertTrue(model === remounted); XCTAssertTrue(remounted.note?.hasOwnReaction("😂") == true)
        await api.release(); await task.value
        remounted.receive(original)
        XCTAssertTrue(remounted.note?.hasOwnReaction("😂") == true)
        await api.setOwn(["❤"])
        remounted.receive(try await api.note("note"))
        XCTAssertEqual(remounted.note?.ownReactions, ["❤"])
        for id in 0..<260 { _ = store.model("other-\(id)") }
        XCTAssertTrue(model === store.model("note"), "Cache eviction must not split the queue of a still-mounted row")
        store.clear(); XCTAssertNil(model.note); XCTAssertTrue(model === store.model("note"))
    }
    func testSessionStoreInvalidationReleasesQueuedOperationsAndPreventsLateWrites() async throws {
        let api = MultiReactionAPI(own: []), store = NativeReactionStore(), original = try await api.note("note"), model = store.model("note")
        await api.holdNextRead()
        let first = Task { await model.apply(.init(value: "😂", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; await Task.yield() }
        let second = Task { await model.apply(.init(value: "❤", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if model.note?.hasOwnReaction("❤") == true { break }; await Task.yield() }
        store.clear(); await api.release(); await first.value; await second.value
        XCTAssertNil(model.note); XCTAssertFalse(model.busy)
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testHiddenFeedEnvelopeDiscardsPendingProjectionAndCannotBeReplacedByALateRead() async throws {
        let api = MultiReactionAPI(own: []), model = NativeReactionModel(), original = try await api.note("note")
        await api.holdNextRead()
        let task = Task { await model.apply(.init(value: "😂", custom: nil), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; await Task.yield() }
        let hidden = try JSONDecoder().decode(ClientNote.self, from: Data(#"{"id":"note","createdAt":"2026-11-16T00:00:00Z","visibility":"specified","isHidden":true,"user":{"id":"author","username":"synthetic"}}"#.utf8))
        model.receive(hidden)
        await api.release(); await task.value
        XCTAssertTrue(model.note?.isHidden == true); XCTAssertFalse(model.busy)
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testOptimisticAddRemoveAndQueuedChoicesAppearBeforeAnyNetworkReadFinishes() async throws {
        let api = MultiReactionAPI(own: ["👍"]), model = NativeReactionModel(), original = try await api.note("note")
        await api.holdNextRead()
        let first = Task { await model.apply(.init(value: "😂", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; await Task.yield() }
        XCTAssertTrue(model.busy); XCTAssertTrue(model.note?.hasOwnReaction("😂") == true)
        XCTAssertEqual(model.note?.reactions?["😂"], 1)
        let snapshot = try XCTUnwrap(model.note)
        let second = Task { await model.apply(.init(value: "👍", custom: nil, intent: .remove), to: snapshot, owner: "owner", api: api, accepts: { true }) }
        for _ in 0..<200 { if model.note?.hasOwnReaction("👍") == false { break }; await Task.yield() }
        XCTAssertFalse(try XCTUnwrap(model.note).hasOwnReaction("👍")); XCTAssertNil(model.note?.reactions?["👍"])
        let earlyWrites = await api.writes; XCTAssertTrue(earlyWrites.isEmpty)
        await api.release(); await first.value; await second.value
        XCTAssertEqual(model.note?.ownReactions, ["😂"]); XCTAssertFalse(model.busy)
        let writes = await api.writes; XCTAssertEqual(writes, ["ADD:😂:true", "REMOVE:👍:true"])
    }
    func testDefiniteRejectionRollsBackOptimisticCountAndOwnSelection() async throws {
        let api = MultiReactionAPI(own: ["👍"]), model = NativeReactionModel(), original = try await api.note("note")
        await api.rejectWrites()
        await model.apply(.init(value: "😂", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertEqual(model.note?.ownReactions, ["👍"]); XCTAssertNil(model.note?.reactions?["😂"])
        XCTAssertNotNil(model.error); XCTAssertFalse(model.unknown); XCTAssertFalse(model.busy)
    }
    func testSecondReactionAddsWithoutReplacingAndPrimaryRemovalKeepsTheExtra() async throws {
        let api = MultiReactionAPI(own: ["👍"]), model = NativeReactionModel()
        let original = try await api.note("note")
        await model.apply(.init(value: "😂", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertEqual(model.note?.ownReactions, ["👍", "😂"])
        await model.apply(.init(value: "👍", custom: nil, intent: .remove), to: try XCTUnwrap(model.note), owner: "owner", api: api, accepts: { true })
        XCTAssertEqual(model.note?.ownReactions, ["😂"]); XCTAssertNil(model.note?.myReaction)
        let writes = await api.writes; XCTAssertEqual(writes, ["ADD:😂:true", "REMOVE:👍:true"])
    }
    func testConcurrentAddIsNotInvertedAndRemovingAbsentEmojiLeavesOtherChoices() async throws {
        let api = MultiReactionAPI(own: ["👍"]), model = NativeReactionModel(), original = try await api.note("note")
        await api.setOwn(["👍", "😂"])
        await model.apply(.init(value: "😂", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true })
        await api.setOwn(["😂", "❤"])
        await model.apply(.init(value: "👍", custom: nil, intent: .remove), to: original, owner: "owner", api: api, accepts: { true })
        let writes = await api.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(model.note?.ownReactions, ["😂", "❤"])
    }
    func testLimitStillAllowsIndividualRemovalAndPartialReadCannotDowngradeTheWrite() async throws {
        let api = MultiReactionAPI(own: (0..<16).map { "emoji-\($0)" }), model = NativeReactionModel()
        await model.apply(.init(value: "😂", custom: nil), to: try await api.note("note"), owner: "owner", api: api, accepts: { true })
        var writes = await api.writes; XCTAssertTrue(writes.isEmpty); XCTAssertNotNil(model.error)
        await model.apply(.init(value: "emoji-1", custom: nil, intent: .remove), to: try await api.note("note"), owner: "owner", api: api, accepts: { true })
        writes = await api.writes; XCTAssertEqual(writes, ["REMOVE:emoji-1:true"])
        await api.setComplete(false)
        await model.apply(.init(value: "😂", custom: nil), to: try await api.note("note"), owner: "owner", api: api, accepts: { true })
        writes = await api.writes; XCTAssertEqual(writes.count, 1)
    }
    func testRetiredCustomEmojiCanBeRemovedWithoutRecheckingAddPermissions() async throws {
        let api = MultiReactionAPI(own: [":retired@.:", "😂"]), model = NativeReactionModel()
        await model.apply(.init(value: ":retired@.:", custom: nil, intent: .remove), to: try await api.note("note"), owner: "owner", api: api, accepts: { true })
        XCTAssertEqual(model.note?.ownReactions, ["😂"]); XCTAssertNil(model.error)
        let writes = await api.writes; XCTAssertEqual(writes, ["REMOVE::retired::true"])
    }
    func testAmbiguousExtendedWriteBlocksReplayUntilTheCompleteSetIsRead() async throws {
        let api = MultiReactionAPI(own: ["👍"], loseReply: true), model = NativeReactionModel(), original = try await api.note("note")
        await model.apply(.init(value: "😂", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        XCTAssertTrue(model.unknown)
        await model.apply(.init(value: "😂", custom: nil), to: original, owner: "owner", api: api, accepts: { true })
        var writes = await api.writes; XCTAssertEqual(writes.count, 1)
        await model.refresh(id: "note", api: api, accepts: { true })
        XCTAssertFalse(model.unknown); XCTAssertEqual(model.note?.ownReactions, ["👍", "😂"])
        await model.apply(.init(value: "😂", custom: nil, intent: .add), to: original, owner: "owner", api: api, accepts: { true })
        writes = await api.writes; XCTAssertEqual(writes.count, 1)
    }
}
private actor MultiReactionAPI: NativeEmojiAPI {
    var own: [String], primary: String?, complete = true
    let loseReply: Bool
    var writes: [String] = []
    var hold = false, rejected = false
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func holdNextRead() { hold = true }
    func release() { continuation?.resume(); continuation = nil }
    func rejectWrites() { rejected = true }
    init(own: [String], loseReply: Bool = false) { self.own = own; primary = own.first; self.loseReply = loseReply }
    func setOwn(_ value: [String]) { own = value; if let primary, !own.contains(primary) { self.primary = nil } }
    func setComplete(_ value: Bool) { complete = value }
    func note(_ id: String) async throws -> ClientNote {
        if hold { hold = false; await withCheckedContinuation { continuation = $0 } }
        var body: [String: Any] = ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "home", "user": ["id": "author", "username": "synthetic"],
            "myReactions": own, "reactions": Dictionary(uniqueKeysWithValues: own.map { ($0, 1) }), "extendedReactions": true, "reactionStateComplete": complete]
        if let primary { body["myReaction"] = primary }
        return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func account() throws -> ClientUser { try JSONDecoder().decode(ClientUser.self, from: Data(#"{"id":"owner","username":"synthetic","roles":[]}"#.utf8)) }
    func emojis() -> [ClientCustomEmoji] { [] }
    func emoji(_ name: String) throws -> ClientCustomEmoji { throw ClientAPIError.invalidResponse }
    func react(note: String, reaction: String, extended: Bool) throws {
        if rejected { throw ClientAPIError.rejected(status: 403, code: "PERMISSION_DENIED") }
        writes.append("ADD:\(reaction):\(extended)"); own.append(reaction); if loseReply { throw URLError(.networkConnectionLost) }
    }
    func removeReaction(note: String, reaction: String?, extended: Bool) { writes.append("REMOVE:\(reaction ?? "nil"):\(extended)"); own.removeAll { ClientEmojiSearch.equivalent($0, reaction) }; if ClientEmojiSearch.equivalent(primary, reaction) { primary = nil } }
}
