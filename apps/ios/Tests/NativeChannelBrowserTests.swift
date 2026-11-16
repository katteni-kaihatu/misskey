// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeChannelBrowserTests: XCTestCase {
    func testNewSearchRejectsLatePreviousResultsAndClearRejectsInFlightResponse() async throws {
        let api = ChannelSearchStub(), model = NativeChannelBrowserModel()
        let old = Task { await model.load(query: "old", reset: true, api: api, accepts: { true }) }
        await api.wait(for: "old")
        let new = Task { await model.load(query: "new", reset: true, api: api, accepts: { true }) }
        await api.wait(for: "new")
        await api.finish("old"); await old.value
        XCTAssertTrue(model.channels.isEmpty); XCTAssertTrue(model.loading)
        await api.finish("new"); await new.value
        XCTAssertEqual(model.channels.map(\.id), ["new"]); XCTAssertFalse(model.loading)
        let cleared = Task { await model.load(query: "cleared", reset: true, api: api, accepts: { true }) }
        await api.wait(for: "cleared"); model.clear(); await api.finish("cleared"); await cleared.value
        XCTAssertTrue(model.channels.isEmpty); XCTAssertFalse(model.loading)
    }
    func testPagingUsesTheLastChannelIDAndDeduplicatesTheBoundary() async {
        let api = PagedChannelSearchStub(), model = NativeChannelBrowserModel()
        await model.load(query: "", reset: true, api: api, accepts: { true })
        XCTAssertEqual(model.channels.count, 30); XCTAssertTrue(model.hasMore)
        await model.load(query: "", reset: false, api: api, accepts: { true })
        XCTAssertEqual(model.channels.count, 31); XCTAssertEqual(model.channels.last?.id, "c30"); XCTAssertFalse(model.hasMore)
        await model.load(query: "", reset: false, api: api, accepts: { true })
        let cursors = await api.cursors; XCTAssertEqual(cursors.count, 2); XCTAssertNil(cursors[0]); XCTAssertEqual(cursors[1], "c29")
    }
    func testFailedSearchCanRetryAndDoesNotApplyToHiddenSession() async throws {
        let api = ChannelSearchStub(), model = NativeChannelBrowserModel()
        let fail = Task { await model.load(query: "offline", reset: true, api: api, accepts: { true }) }
        await api.wait(for: "offline"); await api.finish("offline", fail: true); await fail.value
        XCTAssertNotNil(model.error); XCTAssertFalse(model.loading)
        let retry = Task { await model.load(query: "retry", reset: true, api: api, accepts: { true }) }
        await api.wait(for: "retry"); await api.finish("retry"); await retry.value
        XCTAssertNil(model.error); XCTAssertEqual(model.channels.first?.id, "retry")
        await model.load(query: "hidden", reset: true, api: api, accepts: { false })
        XCTAssertEqual(model.channels.first?.id, "retry")
    }
}
private actor ChannelSearchStub: NativeChannelAPI {
    var pending: [String: CheckedContinuation<[ClientChannel], Error>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func channels(query: String, until: String?) async throws -> [ClientChannel] {
        try await withCheckedThrowingContinuation { continuation in pending[query] = continuation; waiters.removeValue(forKey: query)?.resume() }
    }
    func wait(for query: String) async { if pending[query] == nil { await withCheckedContinuation { waiters[query] = $0 } } }
    func finish(_ query: String, fail: Bool = false) {
        let channel = try! JSONDecoder().decode(ClientChannel.self, from: JSONSerialization.data(withJSONObject: ["id": query, "name": "Synthetic channel"]))
        if fail { pending.removeValue(forKey: query)?.resume(throwing: URLError(.notConnectedToInternet)) }
        else { pending.removeValue(forKey: query)?.resume(returning: [channel]) }
    }
}

private actor PagedChannelSearchStub: NativeChannelAPI {
    var cursors: [String?] = []
    func channels(query: String, until: String?) throws -> [ClientChannel] {
        cursors.append(until)
        return try (until == nil ? Array(0..<30) : [29, 30]).map { index in
            try JSONDecoder().decode(ClientChannel.self, from: JSONSerialization.data(withJSONObject: ["id": "c\(index)", "name": "Synthetic channel \(index)"]))
        }
    }
}
