// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeTimelineTests: XCTestCase {
    private func page(_ prefix: String, count: Int = 30) throws -> [ClientNote] {
        try (0..<count).map { index in
            try JSONDecoder().decode(ClientNote.self, from: Data("{\"id\":\"\(prefix)-\(index)\",\"createdAt\":\"2026-11-16T00:00:00Z\",\"visibility\":\"public\",\"text\":\"Synthetic timeline\",\"user\":{\"id\":\"synthetic-author\",\"username\":\"synthetic\"}}".utf8))
        }
    }
    func testPostAcknowledgedDuringAnOlderHeadReadSurvivesWithoutAnotherRequest() async throws {
        let first = try page("first"), posted = try XCTUnwrap(page("posted", count: 1).first)
        let api = TimelineStub(first: first), model = NativeTimelineModel(); model.activate("owner/local")
        await model.load(.local, reset: true, api: api, accepts: { true })
        let pull = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 1)
        model.receivePosted(posted, feed: .timeline(.local), owner: "synthetic-author")
        XCTAssertEqual(model.pendingCount, 1); XCTAssertTrue(model.notes.first === first.first)
        await api.finish(1, with: .success(first)); await pull.value
        XCTAssertEqual(model.notes.map(\.id), [posted.id] + first.map(\.id))
        let reads = await api.cursors; XCTAssertEqual(reads.count, 2)
    }
    func testRefreshingKeepsVisibleRowsAndFooterAndDoesNotStartDuplicatePulls() async throws {
        let first = try page("first"), updated = try page("updated"), api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let pull = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 1)
        XCTAssertEqual(model.notes.map(\.id), first.map(\.id)); XCTAssertTrue(model.loading)
        XCTAssertFalse(model.loadingMore); XCTAssertTrue(model.hasMore)
        await model.load(.local, reset: true, api: api, accepts: { true })
        let requests = await api.cursors; XCTAssertEqual(requests.count, 2)
        await api.finish(1, with: .success(updated)); await pull.value
        XCTAssertEqual(model.notes.map(\.id), updated.map(\.id)); XCTAssertFalse(model.loading)
    }
    func testFailedPullKeepsRowsAndReleasesLoading() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let pull = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 1); await api.finish(1, with: .failure(URLError(.notConnectedToInternet))); await pull.value
        XCTAssertEqual(model.notes.count, 30); XCTAssertFalse(model.loading); XCTAssertFalse(model.loadingMore)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.retryResets)
    }
    func testPaginationCoalescesRequestsAndStopsAtTheLastPage() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let more = Task { await model.load(.local, reset: false, api: api, accepts: { true }) }
        await api.wait(for: 1)
        await model.load(.local, reset: false, api: api, accepts: { true })
        let during = await api.cursors; XCTAssertEqual(during.count, 2)
        await api.finish(1, with: .success(try page("last", count: 1))); await more.value
        XCTAssertEqual(model.notes.count, 31); XCTAssertFalse(model.hasMore)
        await model.load(.local, reset: false, api: api, accepts: { true })
        let after = await api.cursors; XCTAssertEqual(after.count, 2); XCTAssertEqual(after[1], "first-29")
    }
    func testDuplicateFullPageStopsWithoutMovingTheCursor() async throws {
        let first = try page("first"), api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let more = Task { await model.load(.local, reset: false, api: api, accepts: { true }) }
        await api.wait(for: 1); await api.finish(1, with: .success(first)); await more.value
        XCTAssertEqual(model.notes.count, 30); XCTAssertFalse(model.hasMore); XCTAssertNil(model.error)
    }
    func testFailedPaginationRetainsRowsAndRetriesTheSameCursor() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let more = Task { await model.load(.local, reset: false, api: api, accepts: { true }) }
        await api.wait(for: 1); await api.finish(1, with: .failure(URLError(.notConnectedToInternet))); await more.value
        XCTAssertEqual(model.notes.count, 30); XCTAssertFalse(model.loading); XCTAssertNotNil(model.error)
        XCTAssertFalse(model.retryResets); XCTAssertTrue(model.hasMore)
        let retry = Task { await model.load(.local, reset: model.retryResets, api: api, accepts: { true }) }
        await api.wait(for: 2); await api.finish(2, with: .success(try page("retry", count: 1))); await retry.value
        let calls = await api.cursors; XCTAssertEqual(calls[1], "first-29"); XCTAssertEqual(calls[2], "first-29")
        XCTAssertEqual(model.notes.count, 31); XCTAssertEqual(model.notes.first?.id, "first-0"); XCTAssertNil(model.error)
    }
    func testCancelledRefreshCannotClearRowsOrLeaveLoadingStuck() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let pull = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 1); pull.cancel()
        await api.finish(1, with: .failure(URLError(.cancelled))); await pull.value
        XCTAssertEqual(model.notes.count, 30); XCTAssertFalse(model.loading); XCTAssertNil(model.error)
        let retry = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 2); await api.finish(2, with: .success(try page("retry"))); await retry.value
        XCTAssertEqual(model.notes.first?.id, "retry-0"); XCTAssertFalse(model.loading)
    }
    func testChangedContextRejectsOldResponseWithoutEndingTheNewRefresh() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        model.activate("account-a/local")
        await model.load(.local, reset: true, api: api, accepts: { true })
        let old = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 1)
        model.activate("account-b/home"); model.activate("account-b/home")
        XCTAssertTrue(model.notes.isEmpty)
        let new = Task { await model.load(.home, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 2)
        await api.finish(1, with: .success(try page("old"))); await old.value
        XCTAssertTrue(model.notes.isEmpty); XCTAssertTrue(model.loading)
        await api.finish(2, with: .success(try page("new"))); await new.value
        XCTAssertEqual(model.notes.first?.id, "new-0"); XCTAssertFalse(model.loading)
    }
    func testRefreshSupersedesPaginationAndLatePageCannotAppendOrStopTheSpinner() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.local, reset: true, api: api, accepts: { true })
        let more = Task { await model.load(.local, reset: false, api: api, accepts: { true }) }
        await api.wait(for: 1); XCTAssertTrue(model.loadingMore)
        let pull = Task { await model.load(.local, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 2); XCTAssertFalse(model.loadingMore)
        await api.finish(1, with: .success(try page("old-page"))); await more.value
        XCTAssertEqual(model.notes.count, 30); XCTAssertTrue(model.loading)
        await api.finish(2, with: .success(try page("fresh"))); await pull.value
        XCTAssertEqual(model.notes.count, 30); XCTAssertEqual(model.notes.first?.id, "fresh-0")
        let cursors = await api.cursors; XCTAssertEqual(cursors[1], "first-29"); XCTAssertNil(cursors[2])
    }
    func testChannelPageKeepsItsOwnCursorAndRefreshUsesTheChannelEndpoint() async throws {
        let api = ChannelTimelineStub(first: try page("channel")), model = NativeTimelineModel()
        let feed = ClientFeedTab.channel(id: "music", name: "Music")
        model.activate("owner/channel:music")
        await model.load(feed: feed, reset: true, api: api, accepts: { true })
        await model.load(feed: feed, reset: false, api: api, accepts: { true })
        let calls = await api.calls
        XCTAssertEqual(calls.map { $0.0 }, ["music", "music"])
        XCTAssertEqual(calls[1].1, "channel-29"); XCTAssertFalse(model.hasMore)
        await model.load(feed: feed, reset: true, api: api, accepts: { true })
        let refreshed = await api.calls; XCTAssertNil(refreshed.last?.1)
    }
    func testAuthorizationFailureClearsOldRowsAndRequiresSignIn() async throws {
        let api = TimelineStub(first: try page("first")), model = NativeTimelineModel()
        await model.load(.home, reset: true, api: api, accepts: { true })
        let pull = Task { await model.load(.home, reset: true, api: api, accepts: { true }) }
        await api.wait(for: 1); await api.finish(1, with: .failure(ClientAPIError.rejected(status: 401, code: "AUTHENTICATION_FAILED"))); await pull.value
        XCTAssertTrue(model.notes.isEmpty); XCTAssertTrue(model.requiresSignIn); XCTAssertFalse(model.loading)
    }
}

private actor TimelineStub: NativeTimelineAPI {
    let first: [ClientNote]
    var cursors: [String?] = []
    var pending: [Int: CheckedContinuation<[ClientNote], Error>] = [:]
    var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    init(first: [ClientNote]) { self.first = first }
    func timeline(_ kind: ClientTimeline, until: String?) async throws -> [ClientNote] {
        let index = cursors.count; cursors.append(until)
        if index == 0 { return first }
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation; waiters.removeValue(forKey: index)?.resume()
        }
    }
    func wait(for index: Int) async {
        if pending[index] == nil { await withCheckedContinuation { waiters[index] = $0 } }
    }
    func finish(_ index: Int, with result: Result<[ClientNote], Error>) { pending.removeValue(forKey: index)?.resume(with: result) }
}

private actor ChannelTimelineStub: NativeTimelineAPI {
    let first: [ClientNote]
    var calls: [(String, String?)] = []
    init(first: [ClientNote]) { self.first = first }
    func timeline(_ kind: ClientTimeline, until: String?) throws -> [ClientNote] { throw ClientAPIError.invalidResponse }
    func channelTimeline(_ id: String, until: String?) -> [ClientNote] { calls.append((id, until)); return until == nil ? first : [] }
}
