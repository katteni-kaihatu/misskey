// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeLiveReactionTests: XCTestCase {
    private func note(remote: Bool = false, replies: Int = 0) throws -> ClientNote {
        var user = ["id": "author", "username": "synthetic"]
        if remote { user["host"] = "other.ios.test" }
        return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: ["id": "note", "createdAt": "2026-11-16T00:00:00Z", "visibility": "public", "user": user, "repliesCount": replies, "reactions": [:]]))
    }
    func testPostOnlyReconcilesItsTargetAndALateReadCannotOverwriteALiveReactionOrClearedSession() async throws {
        let original = try note(remote: true), fresh = try note(remote: true, replies: 1)
        let model = NativeReactionModel(); model.receive(original)
        await model.refreshAfterPost(id: "note", api: ReactionStreamAPI(target: fresh), accepts: { true })
        model.receive(original)
        XCTAssertEqual(model.note?.repliesCount, 1); XCTAssertNil(model.error); XCTAssertFalse(model.busy)
        for clear in [false, true] {
            let api = ReactionStreamAPI(held: true, target: fresh), held = NativeReactionModel(); held.receive(original)
            let read = Task { await held.refreshAfterPost(id: "note", api: api, accepts: { true }) }
            for _ in 0..<500 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 2_000_000) }
            let waiting = await api.waiting; XCTAssertTrue(waiting)
            if clear { held.clear() }
            else { XCTAssertTrue(held.receiveLive(try reactionState(count: 2), expectedVersion: held.version)) }
            await api.release(); await read.value
            if clear { XCTAssertNil(held.note) }
            else { XCTAssertEqual(held.note?.reactions?["😂"], 2); XCTAssertEqual(held.note?.repliesCount, 0) }
            XCTAssertNil(held.error)
        }
        await model.refreshAfterPost(id: "note", api: ReactionStreamAPI(), accepts: { true })
        XCTAssertEqual(model.note?.repliesCount, 1); XCTAssertNil(model.error)
    }
    func testLiveSnapshotPreservesRemoteSingleReactionCapabilityAndRejectsAnOlderWriteVersion() throws {
        let model = NativeReactionModel(); model.receive(try note(remote: true))
        let before = model.version
        XCTAssertTrue(model.receiveLive(try reactionState(count: 2), expectedVersion: before))
        XCTAssertFalse(try XCTUnwrap(model.note).supportsExtendedReactions)
        XCTAssertEqual(model.note?.reactions?["😂"], 2)
        XCTAssertFalse(model.receiveLive(try reactionState(count: 1), expectedVersion: before))
        XCTAssertEqual(model.note?.reactions?["😂"], 2)
    }
    private func pureRenote() throws -> ClientNote {
        try JSONDecoder().decode(ClientNote.self, from: Data(#"{"id":"wrapper","createdAt":"2026-11-16T00:00:00Z","visibility":"public","user":{"id":"owner","username":"synthetic"},"renoteId":"original","renote":{"id":"original","createdAt":"2026-11-16T00:00:00Z","visibility":"public","text":"Owned synthetic original","user":{"id":"author","username":"synthetic"}}}"#.utf8))
    }
    func testPureRenoteRefreshDoesNotMistakeIntentionallyMissingReactionStateForAServerFailure() async throws {
        let wrapper = try pureRenote(), model = NativeReactionModel(), api = ReactionStreamAPI(target: try pureRenote())
        XCTAssertTrue(wrapper.isPureRenote); XCTAssertTrue(wrapper.supportsExtendedReactions)
        XCTAssertNil(wrapper.reactionStateComplete)
        model.receive(wrapper)
        await model.refresh(id: wrapper.id, api: api, accepts: { true })
        XCTAssertNil(model.error); XCTAssertFalse(model.busy); XCTAssertFalse(model.unknown)
        XCTAssertEqual(model.note?.id, "wrapper"); XCTAssertNil(model.note?.reactionStateComplete)
        XCTAssertFalse(model.receiveLive(try reactionState(count: 1, note: "wrapper"), expectedVersion: model.version))
    }
    func testPureRenoteRemainsSubscribedForDeletionWithoutReadingItsReactionState() async throws {
        let wrapper = NativeReactionModel(), normal = NativeReactionModel(), service = NativeLiveReactions(), api = ReactionStreamAPI()
        service.start(api: api, accepts: { true }, catalogChanged: {})
        _ = service.observe("wrapper", model: wrapper) // onAppear precedes the row's receive task.
        wrapper.receive(try pureRenote()); normal.receive(try note())
        _ = service.observe("note", model: normal); defer { service.clear() }
        for _ in 0..<500 { if normal.note?.reactions?["😂"] == 1 { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        let ids = await api.ids; XCTAssertFalse(ids.isEmpty); XCTAssertTrue(ids.allSatisfy { $0 == ["note"] })
        let reads = await api.reads
        await api.emit(.noteChanged(id: "wrapper", deleted: false))
        try await Task.sleep(nanoseconds: 350_000_000)
        let after = await api.reads; XCTAssertEqual(after, reads)
        await api.emit(.noteChanged(id: "wrapper", deleted: true))
        for _ in 0..<200 { if wrapper.note?.isHidden == true { break }; await Task.yield() }
        XCTAssertEqual(wrapper.note?.isHidden, true)
        XCTAssertNil(wrapper.error)
    }
    func testQuoteKeepsItsOwnReactionUpdates() throws {
        let quote = try JSONDecoder().decode(ClientNote.self, from: Data(#"{"id":"note","createdAt":"2026-11-16T00:00:00Z","visibility":"public","text":"Owned synthetic quote","user":{"id":"owner","username":"synthetic"},"renoteId":"original"}"#.utf8))
        let model = NativeReactionModel(); model.receive(quote)
        XCTAssertFalse(quote.isPureRenote)
        XCTAssertTrue(model.receiveLive(try reactionState(count: 2), expectedVersion: model.version))
        XCTAssertEqual(model.note?.reactions?["😂"], 2)
    }
    func testDuplicateStreamNotificationsCoalesceAndSameCountSnapshotStillRefreshesActorVersion() async throws {
        let model = NativeReactionModel(), service = NativeLiveReactions(), api = ReactionStreamAPI()
        model.receive(try note()); service.start(api: api, accepts: { true }, catalogChanged: {})
        let token = service.observe("note", model: model)
        defer { service.clear() }
        for _ in 0..<500 { if await api.reads >= 1 && model.note?.reactions?["😂"] == 1 { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        let version = model.version, baseline = await api.reads
        await api.emit(.noteChanged(id: "note", deleted: false)); await api.emit(.noteChanged(id: "note", deleted: false))
        await api.emit(.noteChanged(id: "unwatched", deleted: false))
        for _ in 0..<500 { if model.version > version { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertGreaterThan(model.version, version); XCTAssertEqual(model.note?.reactions?["😂"], 1)
        let reads = await api.reads; XCTAssertEqual(reads, baseline + 1)
        let pages = await api.ids; XCTAssertTrue(pages.allSatisfy { $0 == ["note"] })
        service.remove("note", token: token)
    }
    func testDeletedEventHidesTheNoteAndAnOldFeedObjectCannotRestoreIt() async throws {
        let original = try note(), model = NativeReactionModel(), service = NativeLiveReactions(), api = ReactionStreamAPI()
        model.receive(original); service.start(api: api, accepts: { true }, catalogChanged: {})
        _ = service.observe("note", model: model); defer { service.clear() }
        for _ in 0..<500 { if await api.ready { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        await api.emit(.noteChanged(id: "note", deleted: true))
        for _ in 0..<500 { if model.note?.isHidden == true { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(model.note?.isHidden, true)
        model.receive(original); XCTAssertEqual(model.note?.isHidden, true)
    }
    func testOldSessionReadCannotRepopulateAfterClear() async throws {
        let model = NativeReactionModel(), service = NativeLiveReactions(), api = ReactionStreamAPI(held: true)
        model.receive(try note()); service.start(api: api, accepts: { true }, catalogChanged: {})
        _ = service.observe("note", model: model)
        for _ in 0..<500 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        service.clear(); model.clear(); await api.release()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(model.note)
    }
    func testWireRecognizesLegacyExtendedAndCatalogUpdatesWithoutAcceptingOtherEvents() throws {
        for type in ["reacted", "unreacted", "extendedReactionUpdated", "deleted"] {
            let data = try JSONSerialization.data(withJSONObject: ["type": "noteUpdated", "body": ["id": "note", "type": type, "body": [:]]])
            guard case .noteChanged(let id, let deleted) = try NativeTimelineSocket.decode(data, id: "channel") else { return XCTFail("Missing update") }
            XCTAssertEqual(id, "note"); XCTAssertEqual(deleted, type == "deleted")
        }
        guard case .emojiCatalogChanged = try NativeTimelineSocket.decode(Data(#"{"type":"emojiUpdated","body":{"emojis":[]}}"#.utf8), id: "channel") else { return XCTFail("Missing catalog update") }
        XCTAssertNil(try NativeTimelineSocket.decode(Data(#"{"type":"noteUpdated","body":{"id":"note","type":"pollVoted"}}"#.utf8), id: "channel"))
    }
}
private func reactionState(count: Int, note: String = "note") throws -> ClientReactionState {
    try JSONDecoder().decode(ClientReactionState.self, from: JSONSerialization.data(withJSONObject: ["noteId": note, "reactions": ["😂": count], "reactionEmojis": [:], "myReactions": [], "complete": true]))
}
private actor ReactionStreamAPI: NativeLiveReactionAPI {
    var continuation: AsyncThrowingStream<NativeTimelineEvent, Error>.Continuation?
    var ready: Bool { continuation != nil }
    var reads = 0, ids: [[String]] = []
    let held: Bool
    let target: ClientNote?
    var gate: CheckedContinuation<Void, Never>?
    var waiting: Bool { gate != nil }
    init(held: Bool = false, target: ClientNote? = nil) { self.held = held; self.target = target }
    func emit(_ event: NativeTimelineEvent) { continuation?.yield(event) }
    func release() { gate?.resume(); gate = nil }
    func noteEvents() -> NativeTimelineSubscription {
        NativeTimelineSubscription(events: AsyncThrowingStream { continuation = $0; $0.yield(.connected) }, cancel: {})
    }
    func reactionStates(_ ids: [String]) async throws -> [ClientReactionState] {
        reads += 1; self.ids.append(ids)
        if held { await withCheckedContinuation { gate = $0 } }
        return [try reactionState(count: 1)]
    }
    func emojis() -> [ClientCustomEmoji] { [] }
    func emoji(_ name: String) throws -> ClientCustomEmoji { throw ClientAPIError.invalidResponse }
    func note(_ id: String) async throws -> ClientNote {
        if held { await withCheckedContinuation { gate = $0 } }
        guard let target, target.id == id else { throw ClientAPIError.invalidResponse }; return target
    }
    func account() throws -> ClientUser { throw ClientAPIError.invalidResponse }
    func react(note: String, reaction: String, extended: Bool) {}
    func removeReaction(note: String, reaction: String?, extended: Bool) {}
}
