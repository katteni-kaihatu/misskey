// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeLiveTimelineTests: XCTestCase {
    private func note(_ id: String, host: String? = nil, shared: Bool = false) throws -> ClientNote {
        var user: [String: Any] = ["id": "author", "username": "synthetic"]
        if let host { user["host"] = host }
        return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "public", "gridspaceShared": shared, "user": user]))
    }
    func testAcknowledgedPostUsesThePendingQueueAndDoesNotMoveOrReplaceReadRows() throws {
        let model = NativeTimelineModel(); model.activate("owner/local")
        let old = try note("old"), created = try note("created")
        model.receiveLive([old]); model.setAtTop(false)
        model.receivePosted(created, feed: .timeline(.local), owner: "author")
        XCTAssertTrue(model.notes.first === old); XCTAssertEqual(model.pendingCount, 1)
        XCTAssertFalse(model.loading)
        model.receiveLive([created])
        XCTAssertEqual(model.pendingCount, 1)
        model.setAtTop(true)
        XCTAssertEqual(model.notes.map(\.id), ["created", "old"]); XCTAssertTrue(model.notes.last === old)
        model.receiveLive([created]); XCTAssertEqual(model.notes.count, 2)
    }
    func testLocalPostCannotBeInjectedIntoAnUnrelatedFeedOrAnotherAccount() throws {
        func created(_ extra: [String: Any]) throws -> ClientNote {
            var value: [String: Any] = ["id": "created", "createdAt": "2026-11-17T00:00:00Z", "visibility": "public", "user": ["id": "author", "username": "synthetic"]]
            value.merge(extra) { _, new in new }
            return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let model = NativeTimelineModel(); model.activate("owner/local")
        model.receivePosted(try created(["visibility": "followers"]), feed: .timeline(.local), owner: "author")
        model.receivePosted(try created([:]), feed: .timeline(.local), owner: "other")
        model.receivePosted(try created(["channelId": "channel"]), feed: .timeline(.home), owner: "author")
        model.receivePosted(try created(["replyId": "parent"]), feed: .timeline(.local), owner: "author")
        model.receivePosted(try created(["visibility": "specified"]), feed: .timeline(.home), owner: "author")
        model.receivePosted(try created([:]), feed: .peerChannel(origin: "https://peer.ios.test", id: "channel", name: "Peer"), owner: "author")
        XCTAssertTrue(model.notes.isEmpty)
        model.receivePosted(try created(["visibility": "followers"]), feed: .timeline(.home), owner: "author")
        XCTAssertEqual(model.notes.map(\.id), ["created"])
    }
    func testCancelledOldPageCannotStopTheCurrentPagesStreamAfterItsLoadFinishes() async throws {
        let api = RetainedStreamAPI(), model = NativeTimelineModel(); model.activate("owner/local")
        await model.load(.local, reset: true, api: api, accepts: { true })
        let current = Task { await model.listen(feed: .timeline(.local), api: api, accepts: { true }) }
        for _ in 0..<500 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        let retired = Task { await Task.yield(); await model.listen(feed: .timeline(.local), api: api, accepts: { true }) }
        retired.cancel(); await retired.value
        await api.emit(.note(try note("incoming")))
        for _ in 0..<500 { if model.notes.contains(where: { $0.id == "incoming" }) { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(model.notes.map(\.id), ["incoming"])
        model.stopLive(); current.cancel(); await current.value
    }
    func testRetainedFeedDoesNotReadTheHeadOnTabReturnButReconnectStillReconciles() async throws {
        let api = RetainedStreamAPI(), model = NativeTimelineModel()
        model.activate("owner/local")
        await model.load(.local, reset: true, api: api, accepts: { true })
        XCTAssertTrue(model.initialized); XCTAssertTrue(model.notes.isEmpty)
        for _ in 0..<2 {
            let task = Task { await model.listen(feed: .timeline(.local), api: api, accepts: { true }) }
            for _ in 0..<500 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 2_000_000) }
            // The connected event has passed through the same stream executor.
            try await Task.sleep(nanoseconds: 20_000_000)
            let reads = await api.reads; XCTAssertEqual(reads, 1)
            model.stopLive(); task.cancel(); await task.value
            await api.disconnect()
        }
        let task = Task { await model.listen(feed: .timeline(.local), api: api, accepts: { true }) }
        for _ in 0..<500 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        await api.disconnect()
        for _ in 0..<1000 { if await api.reads > 1 { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        let reads = await api.reads; XCTAssertEqual(reads, 2)
        model.stopLive(); task.cancel(); await task.value
    }
    func testFeedStoreSurvivesPageRecreationButPrunesRemovedTabsAndClearsOnInvalidation() throws {
        let store = NativeTimelineStore(), local = store.model("local"), home = store.model("home")
        local.activate("owner/local"); home.activate("owner/home")
        local.receiveLive([try note("local")]); home.receiveLive([try note("home")])
        XCTAssertTrue(store.model("local") === local); XCTAssertEqual(store.model("home").notes.count, 1)
        store.retain(["local"]); XCTAssertTrue(home.notes.isEmpty); XCTAssertTrue(store.model("local") === local)
        store.clear(); XCTAssertTrue(local.notes.isEmpty); XCTAssertFalse(local.initialized)
    }
    func testAtTopPrependsImmediatelyButReadingHistoryOnlyQueuesUntilReturning() throws {
        let model = NativeTimelineModel()
        model.receiveLive([try note("first")])
        XCTAssertEqual(model.notes.map(\.id), ["first"])
        model.setAtTop(false)
        model.receiveLive([try note("peer", host: "peer.ios.test", shared: true)])
        model.receiveLive([try note("newest"), try note("peer", host: "peer.ios.test", shared: true)])
        XCTAssertEqual(model.notes.map(\.id), ["first"]); XCTAssertEqual(model.pendingCount, 2)
        model.setAtTop(true)
        XCTAssertEqual(model.notes.map(\.id), ["newest", "peer", "first"]); XCTAssertEqual(model.pendingCount, 0)
        model.receiveLive([try note("newest")]); XCTAssertEqual(model.notes.count, 3)
    }
    func testOverflowAndLargeReconnectGapReplaceHeadOnlyWhenUserJumpsBack() throws {
        let model = NativeTimelineModel(); model.receiveLive([try note("old")]); model.setAtTop(false)
        model.receiveLive(try (0..<110).map { try note("new-\($0)") })
        XCTAssertEqual(model.notes.map(\.id), ["old"]); XCTAssertLessThanOrEqual(model.pendingCount, 100)
        model.setAtTop(true)
        XCTAssertEqual(model.notes.count, 30); XCTAssertFalse(model.notes.contains { $0.id == "old" })
    }
    func testPairedLocalStreamIsIncludedButOtherRemoteNotesAndPeerProxyChannelsAreExcluded() throws {
        let peer = try note("peer", host: "peer.ios.test", shared: true), remote = try note("remote", host: "other.ios.test")
        XCTAssertTrue(NativeTimelineModel.matches(peer, feed: .timeline(.local)))
        XCTAssertFalse(NativeTimelineModel.matches(remote, feed: .timeline(.local)))
        XCTAssertTrue(NativeTimelineModel.matches(remote, feed: .timeline(.global)))
        XCTAssertFalse(NativeTimelineModel.matches(peer, feed: .peerChannel(origin: "https://peer.ios.test", id: "channel", name: "Peer")))
        let connect = try NativeTimelineSocket.subscription(.timeline(.local), id: "test")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(connect.utf8)) as? [String: Any])
        let body = try XCTUnwrap(value["body"] as? [String: Any])
        XCTAssertEqual(body["channel"] as? String, "localTimeline"); XCTAssertEqual(body["pong"] as? Bool, true)
        XCTAssertThrowsError(try NativeTimelineSocket.subscription(.peerChannel(origin: "https://peer.ios.test", id: "channel", name: "Peer"), id: "test"))
    }
    func testWireDecoderRoutesOnlyTheSubscribedChannelAndPreservesPeerFlags() throws {
        let raw = #"{"type":"channel","body":{"id":"own","type":"note","body":{"id":"peer-note","createdAt":"2026-11-16T00:00:00Z","visibility":"public","gridspaceShared":true,"user":{"id":"peer","username":"synthetic","host":"peer.ios.test"}}}}"#
        guard case .note(let value) = try NativeTimelineSocket.decode(Data(raw.utf8), id: "own") else { return XCTFail("Expected the paired note") }
        XCTAssertEqual(value.gridspaceShared, true); XCTAssertTrue(value.supportsExtendedReactions)
        XCTAssertNil(try NativeTimelineSocket.decode(Data(raw.utf8), id: "different"))
        XCTAssertThrowsError(try NativeTimelineSocket.decode(Data(repeating: 0, count: 2 * 1024 * 1024 + 1), id: "own"))
    }
    func testPendingHydrationAfterAccountChangeCannotReinsertAnOldPrivateNote() async throws {
        let api = LiveAPI(note: try note("incoming")), model = NativeTimelineModel()
        model.activate("old")
        let task = Task { await model.listen(feed: .timeline(.local), api: api, accepts: { true }) }
        for _ in 0..<500 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        model.activate("new"); await api.release(); task.cancel(); await task.value
        XCTAssertTrue(model.notes.isEmpty); XCTAssertEqual(model.pendingCount, 0)
    }
}
private actor LiveAPI: NativeTimelineLiveAPI {
    let value: ClientNote
    var gate: CheckedContinuation<Void, Never>?
    var waiting: Bool { gate != nil }
    init(note: ClientNote) { value = note }
    func release() { gate?.resume(); gate = nil }
    func timeline(_ kind: ClientTimeline, until: String?) -> [ClientNote] { [] }
    func timelineEvents(_ feed: ClientFeedTab) -> NativeTimelineSubscription {
        NativeTimelineSubscription(events: AsyncThrowingStream { $0.yield(.note(value)) }, cancel: {})
    }
    func prepareLiveNotes(_ notes: [ClientNote]) async -> [ClientNote] { await withCheckedContinuation { gate = $0 }; return notes }
}

private actor RetainedStreamAPI: NativeTimelineLiveAPI {
    private var continuation: AsyncThrowingStream<NativeTimelineEvent, Error>.Continuation?
    var waiting: Bool { continuation != nil }
    private(set) var reads = 0
    func timeline(_ kind: ClientTimeline, until: String?) -> [ClientNote] { reads += 1; return [] }
    func timelineEvents(_ feed: ClientFeedTab) -> NativeTimelineSubscription {
        let (events, continuation) = AsyncThrowingStream<NativeTimelineEvent, Error>.makeStream()
        self.continuation = continuation; continuation.yield(.connected)
        return NativeTimelineSubscription(events: events, cancel: { continuation.finish() })
    }
    func emit(_ event: NativeTimelineEvent) { continuation?.yield(event) }
    func disconnect() { continuation?.finish(); continuation = nil }
    func prepareLiveNotes(_ notes: [ClientNote]) -> [ClientNote] { notes }
}
