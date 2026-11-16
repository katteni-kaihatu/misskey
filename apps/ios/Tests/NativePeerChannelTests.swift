// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativePeerChannelTests: XCTestCase {
    func testNewPeerHeadIsPrependedWithoutReplacingTheOpaqueHistoryCursorAndRevocationStillErasesIt() async throws {
        let api = PeerReadStub(), model = NativePeerChannelModel(); model.activate(UUID())
        await model.load(id: "channel1", origin: "https://peer.example", reset: true, api: api, accepts: { true })
        await api.setHead(["newPeer", "note1"])
        await model.refreshHead(id: "channel1", origin: "https://peer.example", api: api, accepts: { true })
        XCTAssertEqual(model.notes.map(\.id), ["newPeer", "note1"])
        await model.load(id: "channel1", origin: "https://peer.example", reset: false, api: api, accepts: { true })
        let calls = await api.calls
        XCTAssertEqual(calls.last?.0, "opaque+/cursor=")
        await api.setRevoked()
        await model.refreshHead(id: "channel1", origin: "https://peer.example", api: api, accepts: { true })
        XCTAssertTrue(model.notes.isEmpty); XCTAssertNotNil(model.error)
    }
    func testOpaquePagingRevalidatesLoadedIDsAndRevocationErasesEverything() async throws {
        let api = PeerReadStub(), model = NativePeerChannelModel(), generation = UUID(); model.activate(generation)
        await model.load(id: "channel1", origin: "https://peer.example", reset: true, api: api, accepts: { true })
        model.activate(generation)
        XCTAssertEqual(model.notes.map(\.id), ["note1"]); XCTAssertTrue(model.hasMore)
        await model.load(id: "channel1", origin: "https://peer.example", reset: false, api: api, accepts: { true })
        XCTAssertEqual(model.notes.map(\.id), ["note1", "note2"]); XCTAssertFalse(model.hasMore)
        let calls = await api.calls
        XCTAssertEqual(calls.count, 3); XCTAssertEqual(calls[1].1, ["note1"]); XCTAssertEqual(calls[2].0, "opaque+/cursor=")
        await api.setRevoked()
        await model.revalidate(id: "channel1", origin: "https://peer.example", api: api, accepts: { true })
        XCTAssertTrue(model.notes.isEmpty); XCTAssertNotNil(model.error); XCTAssertFalse(model.hasMore)
    }
    func testDeletedIDsDisappearDuringValidationAndFailedRefreshDoesNotRetainOldText() async {
        let api = PeerReadStub(), model = NativePeerChannelModel(); model.activate(UUID())
        await model.load(id: "channel1", origin: "https://peer.example", reset: true, api: api, accepts: { true })
        await api.setDeleted()
        await model.revalidate(id: "channel1", origin: "https://peer.example", api: api, accepts: { true })
        XCTAssertTrue(model.notes.isEmpty); XCTAssertNil(model.error)
        await api.setRevoked()
        await model.load(id: "channel1", origin: "https://peer.example", reset: true, api: api, accepts: { true })
        XCTAssertTrue(model.notes.isEmpty); XCTAssertFalse(model.loading)
        model.clear(); XCTAssertNil(model.generation)
    }
    func testClearingRejectsAnOlderOwnerResponse() async {
        let api = PeerLateStub(), model = NativePeerChannelModel(); model.activate(UUID())
        let task = Task { await model.load(id: "channel1", origin: "https://peer.example", reset: true, api: api, accepts: { true }) }
        await api.wait(); model.clear(); await api.finish(); await task.value
        XCTAssertTrue(model.notes.isEmpty); XCTAssertNil(model.generation); XCTAssertFalse(model.loading)
    }
    func testPeerCatalogCanContinueAfterLocalPagesEndAndRejectsSourceChanges() async {
        let api = PeerPagingCatalogStub(), model = NativeChannelBrowserModel()
        await model.load(query: "", reset: true, includePeer: true, api: api, accepts: { true })
        XCTAssertFalse(model.hasMore); XCTAssertTrue(model.peerHasMore)
        XCTAssertEqual(model.peerChannels.count, 1)
        await model.load(query: "", reset: false, includePeer: true, api: api, accepts: { true })
        let calls = await api.cursors
        XCTAssertEqual(calls.count, 2); XCTAssertNil(calls[0]); XCTAssertEqual(calls[1], "next1")
        XCTAssertTrue(model.peerChannels.isEmpty); XCTAssertNotNil(model.peerError)
        XCTAssertEqual(model.channels.first?.id, "local1")
    }
    func testLatePreviousLocalSearchCannotStartAnOldPeerSearch() async {
        let api = PeerSearchRaceStub(), model = NativeChannelBrowserModel()
        let old = Task { await model.load(query: "old", reset: true, includePeer: true, api: api, accepts: { true }) }
        await api.wait("old")
        let current = Task { await model.load(query: "new", reset: true, includePeer: true, api: api, accepts: { true }) }
        await api.wait("new"); await api.finish("new"); await current.value
        await api.finish("old"); await old.value
        let queries = await api.peerQueries
        XCTAssertEqual(queries, ["new"])
        XCTAssertEqual(model.peerChannels.first?.channel.id, "new")
    }
    func testPeerFailureKeepsLocalCatalogAndExplainsMissingPermission() async {
        let api = PeerCatalogStub(), model = NativeChannelBrowserModel()
        await model.load(query: "music", reset: true, includePeer: true, api: api, accepts: { true })
        XCTAssertEqual(model.channels.map(\.id), ["collision1"]); XCTAssertTrue(model.peerChannels.isEmpty)
        XCTAssertTrue(model.peerNeedsLogin); XCTAssertNotNil(model.peerError)
        await api.enablePeer()
        await model.loadPeer(query: "music", reset: true, api: api, accepts: { true })
        XCTAssertEqual(model.peerChannels.first?.channel.id, "collision1")
        XCTAssertNotEqual(model.peerChannels.first?.id, "channel:collision1"); XCTAssertNil(model.peerError)
        model.clear(); XCTAssertTrue(model.peerChannels.isEmpty); XCTAssertTrue(model.channels.isEmpty)
    }
}
private func peerPage(_ ids: [String], cursor: String? = nil) throws -> ClientPeerChannelNotePage {
    let notes = ids.map { ["id": $0, "origin": "https://peer.example", "createdAt": "2026-11-16T00:00:00Z", "text": "Synthetic private note", "channelId": "channel1", "files": [], "author": ["username": "synthetic", "host": "peer.example"]] as [String: Any] }
    return try JSONDecoder().decode(ClientPeerChannelNotePage.self, from: JSONSerialization.data(withJSONObject: ["notes": notes, "cursor": cursor as Any? ?? NSNull(), "observedAt": "2026-11-16T00:00:00Z"]))
}
private actor PeerReadStub: NativePeerChannelAPI {
    var calls: [(String?, [String]?)] = []
    var revoked = false, deleted = false
    var head = ["note1"]
    func setHead(_ ids: [String]) { head = ids }
    func setRevoked() { revoked = true }
    func setDeleted() { deleted = true }
    func peerChannelNotes(_ id: String, expectedOrigin: String, cursor: String?, validating: [String]?) throws -> ClientPeerChannelNotePage {
        calls.append((cursor, validating))
        if revoked { throw ClientAPIError.rejected(status: 400, code: "GRIDSPACE_PRIVATE_UNAVAILABLE") }
        if let validating { return try peerPage(deleted ? [] : validating) }
        return try cursor == nil ? peerPage(head, cursor: "opaque+/cursor=") : peerPage(["note2"])
    }
}
private actor PeerLateStub: NativePeerChannelAPI {
    var continuation: CheckedContinuation<ClientPeerChannelNotePage, Error>?
    var waiter: CheckedContinuation<Void, Never>?
    func peerChannelNotes(_ id: String, expectedOrigin: String, cursor: String?, validating: [String]?) async throws -> ClientPeerChannelNotePage {
        try await withCheckedThrowingContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func wait() async { if continuation == nil { await withCheckedContinuation { waiter = $0 } } }
    func finish() { continuation?.resume(returning: try! peerPage(["note1"])); continuation = nil }
}
private actor PeerCatalogStub: NativeChannelAPI {
    var enabled = false
    func enablePeer() { enabled = true }
    func channels(query: String, until: String?) throws -> [ClientChannel] { [try JSONDecoder().decode(ClientChannel.self, from: Data(#"{"id":"collision1","name":"Local"}"#.utf8))] }
    func peerChannels(query: String, before: String?) throws -> ClientPeerChannelPage {
        if !enabled { throw ClientAPIError.rejected(status: 403, code: "PERMISSION_DENIED") }
        return try JSONDecoder().decode(ClientPeerChannelPage.self, from: Data(#"{"origin":"https://peer.example","channels":[{"id":"collision1","name":"Peer"}],"next":null}"#.utf8))
    }
}

private actor PeerPagingCatalogStub: NativeChannelAPI {
    var cursors: [String?] = []
    func channels(query: String, until: String?) throws -> [ClientChannel] {
        [try JSONDecoder().decode(ClientChannel.self, from: Data(#"{"id":"local1","name":"Local"}"#.utf8))]
    }
    func peerChannels(query: String, before: String?) throws -> ClientPeerChannelPage {
        cursors.append(before)
        let body = before == nil ? #"{"origin":"https://peer.example","channels":[{"id":"peer1","name":"Peer"}],"next":"next1"}"# : #"{"origin":"https://changed.example","channels":[{"id":"peer2","name":"Wrong source"}],"next":null}"#
        return try JSONDecoder().decode(ClientPeerChannelPage.self, from: Data(body.utf8))
    }
}
private actor PeerSearchRaceStub: NativeChannelAPI {
    var pending: [String: CheckedContinuation<[ClientChannel], Error>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    var peerQueries: [String] = []
    func channels(query: String, until: String?) async throws -> [ClientChannel] {
        try await withCheckedThrowingContinuation { pending[query] = $0; waiters.removeValue(forKey: query)?.resume() }
    }
    func peerChannels(query: String, before: String?) throws -> ClientPeerChannelPage {
        peerQueries.append(query)
        return try JSONDecoder().decode(ClientPeerChannelPage.self, from: JSONSerialization.data(withJSONObject: ["origin": "https://peer.example", "channels": [["id": query, "name": "Peer"]], "next": NSNull()]))
    }
    func wait(_ query: String) async { if pending[query] == nil { await withCheckedContinuation { waiters[query] = $0 } } }
    func finish(_ query: String) { pending.removeValue(forKey: query)?.resume(returning: []) }
}
