// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

private func profileUser(following: Bool = false, pending: Bool = false, locked: Bool = false) throws -> ClientUser {
    let data: [String: Any] = ["id": "target", "username": "synthetic", "isFollowing": following, "hasPendingFollowRequestFromYou": pending, "isLocked": locked]
    return try JSONDecoder().decode(ClientUser.self, from: JSONSerialization.data(withJSONObject: data))
}
private func profileNote(_ id: String) throws -> ClientNote {
    try JSONDecoder().decode(ClientNote.self, from: Data("{\"id\":\"\(id)\",\"createdAt\":\"2026-11-16T00:00:00Z\",\"visibility\":\"public\",\"user\":{\"id\":\"target\",\"username\":\"synthetic\"}}".utf8))
}

@MainActor
final class NativeProfileStateTests: XCTestCase {
    func testAcknowledgedPostIsMergedIntoItsProfileWithoutResettingThePageCursor() async throws {
        let api = ProfileAPIStub(), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        let first = model.notes.first
        model.receivePosted(try profileNote("posted")); model.receivePosted(try profileNote("posted"))
        XCTAssertEqual(model.notes.count, 31); XCTAssertEqual(model.notes.first?.id, "posted")
        XCTAssertTrue(model.notes[1] === first)
        await model.loadMore(api: api, accepts: { true })
        let calls = await api.pageCalls; XCTAssertEqual(calls.map(\.1), [nil, "note-29"])
        XCTAssertEqual(model.notes.first?.id, "posted")
        await model.load("target", filter: .media, api: api, accepts: { true })
        model.receivePosted(try profileNote("without-media"))
        XCTAssertFalse(model.notes.contains { $0.id == "without-media" })
    }
    func testProfilePaginationPreservesCursorAndAFilterChangeStartsANewPage() async throws {
        let api = ProfileAPIStub(), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        XCTAssertEqual(model.notes.count, 30); XCTAssertTrue(model.more)
        await model.loadMore(api: api, accepts: { true })
        XCTAssertEqual(model.notes.count, 31); XCTAssertFalse(model.more)
        await model.load("target", filter: .media, api: api, accepts: { true })
        let calls = await api.pageCalls
        XCTAssertEqual(calls.map(\.0), [.posts, .posts, .media]); XCTAssertEqual(calls.map(\.1), [nil, "note-29", nil])
        XCTAssertEqual(model.notes.count, 30)
    }
    func testDeniedLaterPageClearsPreviouslyFetchedPosts() async throws {
        let api = ProfileAPIStub(), model = NativeProfileModel()
        await model.load("target", filter: .replies, api: api, accepts: { true })
        await api.denyPages()
        await model.loadMore(api: api, accepts: { true })
        XCTAssertTrue(model.notes.isEmpty); XCTAssertNotNil(model.notesError); XCTAssertFalse(model.more)
        XCTAssertNotNil(model.user)
    }
    func testLockedAccountRequestAndCancellationUseConfirmedServerState() async throws {
        let api = ProfileAPIStub(locked: true), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        await model.change(.request, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        XCTAssertEqual(model.user?.hasPendingFollowRequestFromYou, true)
        await model.change(.cancelRequest, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        XCTAssertEqual(model.user?.hasPendingFollowRequestFromYou, false)
        let calls = await api.changes; XCTAssertEqual(calls, [.request, .cancelRequest])
    }
    func testChangedRelationshipDoesNotToggleTheOppositeOperation() async throws {
        let api = ProfileAPIStub(), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        await api.setFollowing()
        await model.change(.follow, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        let calls = await api.changes; XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.user?.isFollowing, true); XCTAssertNotNil(model.relationshipError)
    }
    func testLostCommittedResponseIsReadWithoutAnotherWriteAndOldLeaseCannotAct() async throws {
        let api = ProfileAPIStub(loseResponse: true), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        let oldLease = model.lease
        await model.change(.follow, viewer: "viewer", api: api, expectedLease: oldLease, accepts: { true })
        XCTAssertEqual(model.user?.isFollowing, true); XCTAssertFalse(model.uncertain)
        model.clear(); await model.load("target", filter: .posts, api: api, accepts: { true })
        await model.change(.unfollow, viewer: "viewer", api: api, expectedLease: oldLease, accepts: { true })
        let calls = await api.changes; XCTAssertEqual(calls, [.follow])
    }
    func testUnverifiableWriteCannotBeRepeatedUntilRelationshipIsRead() async throws {
        let api = ProfileAPIStub(loseResponse: true, loseReads: true), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        await model.change(.follow, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        XCTAssertTrue(model.uncertain)
        XCTAssertTrue(model.notes.isEmpty)
        await model.change(.follow, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        await api.enableReads()
        await model.refreshRelationship(api: api, expectedLease: model.lease, accepts: { true })
        XCTAssertFalse(model.uncertain); XCTAssertEqual(model.user?.isFollowing, true)
        XCTAssertEqual(model.notes.count, 30)
        let calls = await api.changes; XCTAssertEqual(calls.count, 1)
    }
    func testClearingAProfileDiscardsALatePageAndDoesNotKeepItsBody() async throws {
        let api = ProfileAPIStub(holdPage: true), model = NativeProfileModel()
        let load = Task { await model.load("target", filter: .posts, api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        model.clear(); await api.releasePage(); await load.value
        XCTAssertNil(model.user); XCTAssertTrue(model.notes.isEmpty)
    }
    func testDeniedRelationshipRefreshDropsCachedPersonAndPostBodies() async throws {
        let api = ProfileAPIStub(), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        await api.denyUserReads()
        await model.refreshRelationship(api: api, expectedLease: model.lease, accepts: { true })
        XCTAssertNil(model.user); XCTAssertTrue(model.notes.isEmpty); XCTAssertNotNil(model.error)
    }
    func testRelationshipChangeReloadsPostsAndDiscardsAPreviousPendingPage() async throws {
        let api = ProfileAPIStub(), model = NativeProfileModel()
        await model.load("target", filter: .posts, api: api, accepts: { true })
        await api.holdNextPage()
        let page = Task { await model.loadMore(api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        await model.change(.follow, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        await api.releasePage(); await page.value
        XCTAssertEqual(model.user?.isFollowing, true)
        XCTAssertEqual(model.notes.count, 30); XCTAssertFalse(model.notes.contains { $0.id == "late" })
        let calls = await api.pageCalls; XCTAssertEqual(calls.map(\.1), [nil, "note-29", nil])
        await api.denyPages()
        await model.change(.unfollow, viewer: "viewer", api: api, expectedLease: model.lease, accepts: { true })
        XCTAssertEqual(model.user?.isFollowing, false)
        XCTAssertTrue(model.notes.isEmpty); XCTAssertNotNil(model.notesError)
    }
}

private actor ProfileAPIStub: NativeProfileAPI {
    var following = false, pending = false
    let locked: Bool, loseResponse: Bool, loseReads: Bool
    var holdPage: Bool
    var deny = false, readFailure = false, deniedUser = false
    var continuation: CheckedContinuation<[ClientNote], Error>?
    var waiting: Bool { continuation != nil }
    private(set) var changes: [ClientFollowAction] = []
    private(set) var pageCalls: [(ClientProfileFilter, String?)] = []
    init(locked: Bool = false, loseResponse: Bool = false, loseReads: Bool = false, holdPage: Bool = false) {
        self.locked = locked; self.loseResponse = loseResponse; self.loseReads = loseReads; self.holdPage = holdPage
    }
    func user(_ id: String) throws -> ClientUser {
        if deniedUser { throw ClientAPIError.rejected(status: 400, code: "NO_SUCH_USER") }
        if readFailure { throw URLError(.notConnectedToInternet) }
        return try profileUser(following: following, pending: pending, locked: locked)
    }
    func userNotes(_ id: String, filter: ClientProfileFilter, until: String?) async throws -> [ClientNote] {
        pageCalls.append((filter, until))
        if holdPage { holdPage = false; return try await withCheckedThrowingContinuation { continuation = $0 } }
        if deny { throw ClientAPIError.rejected(status: 403, code: "FORBIDDEN") }
        return try (until == nil ? Array(0..<30) : [29, 30]).map { try profileNote("note-\($0)") }
    }
    func changeFollowing(_ id: String, action: ClientFollowAction) throws {
        changes.append(action)
        switch action { case .follow: following = true; case .request: pending = true; case .unfollow: following = false; case .cancelRequest: pending = false }
        if loseReads { readFailure = true }
        if loseResponse { throw URLError(.networkConnectionLost) }
    }
    func denyPages() { deny = true }
    func holdNextPage() { holdPage = true }
    func denyUserReads() { deniedUser = true }
    func setFollowing() { following = true }
    func enableReads() { readFailure = false }
    func releasePage() { continuation?.resume(returning: (try? [profileNote("late")]) ?? []); continuation = nil }
}

@MainActor
final class NativePeopleStateTests: XCTestCase {
    func testPaginationUsesRelationshipIDsAndDenialClearsTheListInsteadOfShowingZero() async throws {
        let api = PeopleAPIStub(), model = NativePeopleModel()
        await model.load("owner", kind: .following, reset: true, api: api, accepts: { true })
        XCTAssertEqual(model.entries.count, 30); XCTAssertTrue(model.more)
        await model.load("owner", kind: .following, reset: false, api: api, accepts: { true })
        XCTAssertEqual(model.entries.count, 31)
        let cursors = await api.cursors; XCTAssertEqual(cursors, [nil, "edge-29"])
        await api.deny()
        await model.load("owner", kind: .following, reset: false, api: api, accepts: { true })
        XCTAssertTrue(model.entries.isEmpty); XCTAssertNotNil(model.error)
    }
    func testWrongRelationshipOwnerDoesNotDisplayAUserFromAnotherList() async throws {
        let api = PeopleAPIStub(wrongOwner: true), model = NativePeopleModel()
        await model.load("owner", kind: .following, reset: true, api: api, accepts: { true })
        XCTAssertTrue(model.entries.isEmpty); XCTAssertNotNil(model.error)
    }
}

private actor PeopleAPIStub: NativePeopleAPI {
    let wrongOwner: Bool
    var denied = false
    private(set) var cursors: [String?] = []
    init(wrongOwner: Bool = false) { self.wrongOwner = wrongOwner }
    func people(_ id: String, kind: ClientPeopleKind, until: String?) throws -> [ClientFollowing] {
        cursors.append(until)
        if denied { throw ClientAPIError.rejected(status: 400, code: "FORBIDDEN") }
        return try (until == nil ? Array(0..<30) : [29, 30]).map { index in
            let object: [String: Any] = ["id": "edge-\(index)", "followerId": wrongOwner ? "other" : id, "followeeId": "person-\(index)", "followee": ["id": "person-\(index)", "username": "synthetic"]]
            return try JSONDecoder().decode(ClientFollowing.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
    func deny() { denied = true }
}
