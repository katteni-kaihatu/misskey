// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeNotificationsTests: XCTestCase {
    func testCompactPreviewKeepsCWAndHiddenContentPrivateIncludingNestedRenotes() throws {
        func note(_ extra: [String: Any]) throws -> ClientNote {
            var body: [String: Any] = ["id": "notice-note", "visibility": "public", "createdAt": "2026-11-17T00:00:00Z", "user": ["id": "person", "username": "synthetic"], "text": "PRIVATE SPOILER"]
            body.merge(extra) { _, new in new }
            return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(NativeNotificationAppearance.summary(try note(["cw": "映画の感想"])), "映画の感想")
        XCTAssertEqual(NativeNotificationAppearance.summary(try note(["cw": ""])), "ノートを見る")
        XCTAssertEqual(NativeNotificationAppearance.summary(try note(["isHidden": true])), "このノートは表示できません")
        let original: [String: Any] = ["id": "original", "visibility": "public", "createdAt": "2026-11-17T00:00:00Z", "user": ["id": "person", "username": "synthetic"], "text": "PRIVATE SPOILER", "cw": "映画の感想"]
        let renote = try note(["text": NSNull(), "renoteId": "original", "renote": original])
        XCTAssertTrue(renote.isPureRenote)
        XCTAssertEqual(NativeNotificationAppearance.summary(renote), "映画の感想")
    }
    func testShortFilteredPagesContinueUntilAnEmptyPageAndUseNotificationIDs() async throws {
        let api = NotificationAPIStub(), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: .follow, api: api, accepts: { true })
        XCTAssertEqual(model.items.count, 2); XCTAssertTrue(model.more)
        await model.loadMore(api: api, accepts: { true })
        XCTAssertEqual(model.items.count, 3); XCTAssertTrue(model.more)
        await model.loadMore(api: api, accepts: { true })
        XCTAssertFalse(model.more)
        let cursors = await api.cursors; XCTAssertEqual(cursors, [nil, "notice-1", "notice-2"])
        let writes = await api.writes; XCTAssertEqual(writes, 0)
    }
    func testChangingFiltersRestartsAtTheHeadWithoutMarkingAnythingRead() async throws {
        let api = NotificationAPIStub(), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: .follow, api: api, accepts: { true })
        await model.loadMore(api: api, accepts: { true })
        await model.load(owner: "owner", kind: .app, api: api, accepts: { true })
        XCTAssertEqual(model.items.count, 2); XCTAssertTrue(model.items.allSatisfy { $0.type == "app" })
        let kinds = await api.kinds; XCTAssertEqual(kinds, [.follow, .follow, .app])
        let cursors = await api.cursors; XCTAssertEqual(cursors.last!, nil)
        let writes = await api.writes; XCTAssertEqual(writes, 0); XCTAssertEqual(model.unreadCount, 3)
    }
    func testDeniedLaterPageClearsFetchedBodiesAndUnreadState() async throws {
        let api = NotificationAPIStub(), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        await api.denyPages()
        await model.loadMore(api: api, accepts: { true })
        XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.unreadCount); XCTAssertNotNil(model.error)
    }
    func testAnExpiredTokenDropsTheDataAndRequestsReauthentication() async throws {
        let api = NotificationAPIStub(), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        await api.denyPages(status: 401)
        await model.loadMore(api: api, accepts: { true })
        XCTAssertTrue(model.requiresSignIn); XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.unreadCount)
        let writes = await api.writes; XCTAssertEqual(writes, 0)
    }
    func testReadAllUsesTheServerCountIncludingNewArrivalsInsteadOfAssumingZero() async throws {
        let api = NotificationAPIStub(afterWrite: 1), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: .follow, api: api, accepts: { true })
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertEqual(model.unreadCount, 1); XCTAssertEqual(model.hasUnread, true); XCTAssertNotNil(model.notice)
        let writes = await api.writes; XCTAssertEqual(writes, 1)
    }
    func testLostAcknowledgementDoesNotReplayAndNeedsAnExplicitReadToUnlock() async throws {
        let api = NotificationAPIStub(loseResponse: true), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertTrue(model.markUnknown); XCTAssertEqual(model.unreadCount, 0)
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        let writes = await api.writes; XCTAssertEqual(writes, 1)
        await model.refreshStatus(api: api, accepts: { true })
        XCTAssertFalse(model.markUnknown)
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        let final = await api.writes; XCTAssertEqual(final, 1)
    }
    func testAReadFailureKeepsAnUncertainWriteBlockedUntilAReadSucceeds() async throws {
        let api = NotificationAPIStub(loseResponse: true, failReadsAfterWrite: true), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertTrue(model.markUnknown); XCTAssertNil(model.unreadCount)
        await model.refreshStatus(api: api, accepts: { true })
        XCTAssertTrue(model.markUnknown)
        await api.enableReads(); await model.refreshStatus(api: api, accepts: { true })
        XCTAssertFalse(model.markUnknown); XCTAssertEqual(model.unreadCount, 0)
        let writes = await api.writes; XCTAssertEqual(writes, 1)
    }
    func testLegacyReadOnlyPermissionKeepsTheNotificationsAndDoesNotReportZero() async throws {
        let api = NotificationAPIStub(rejectWrite: true), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertEqual(model.items.count, 2); XCTAssertEqual(model.unreadCount, 3)
        XCTAssertFalse(model.markUnknown); XCTAssertTrue(model.operationError?.contains("ログインし直す") == true)
    }
    func testAChangedAccountCannotMarkAnotherAccountsNotificationsRead() async throws {
        let api = NotificationAPIStub(), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        await api.changeOwner()
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.unreadCount)
        let writes = await api.writes; XCTAssertEqual(writes, 0)
    }
    func testClearingRejectsAnOldConfirmationAndALateNotificationPage() async throws {
        let api = NotificationAPIStub(holdPage: true), model = NativeNotificationsModel()
        let load = Task { await model.load(owner: "owner", kind: nil, api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        let old = model.lease; model.clear(); await api.releasePage(); await load.value
        await model.markAll(expectedLease: old, api: api, accepts: { true })
        XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.unreadCount)
        let writes = await api.writes; XCTAssertEqual(writes, 0)
    }
    func testLegacyBooleanUnreadStateRemainsUsableWhenTheCountIsUnavailable() async throws {
        let api = NotificationAPIStub(legacy: true), model = NativeNotificationsModel()
        await model.load(owner: "owner", kind: nil, api: api, accepts: { true })
        XCTAssertNil(model.unreadCount); XCTAssertEqual(model.hasUnread, true)
        await model.markAll(expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertNil(model.unreadCount); XCTAssertEqual(model.hasUnread, false)
    }
}

private actor NotificationAPIStub: NativeNotificationsAPI {
    let afterWrite: Int, loseResponse: Bool, failReadsAfterWrite: Bool, rejectWrite: Bool, holdPage: Bool, legacy: Bool
    var owner = "owner", unread = 3, denied = false, readFailure = false
    var deniedStatus = 403
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    private(set) var writes = 0
    private(set) var cursors: [String?] = []
    private(set) var kinds: [ClientNotificationKind?] = []
    init(afterWrite: Int = 0, loseResponse: Bool = false, failReadsAfterWrite: Bool = false, rejectWrite: Bool = false, holdPage: Bool = false, legacy: Bool = false) {
        self.afterWrite = afterWrite; self.loseResponse = loseResponse; self.failReadsAfterWrite = failReadsAfterWrite
        self.rejectWrite = rejectWrite; self.holdPage = holdPage; self.legacy = legacy
    }
    func account() throws -> ClientUser {
        if readFailure { throw URLError(.notConnectedToInternet) }
        var body: [String: Any] = ["id": owner, "username": "synthetic", "hasUnreadNotification": unread > 0]
        if !legacy { body["unreadNotificationsCount"] = unread }
        return try JSONDecoder().decode(ClientUser.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func notifications(until: String?, kind: ClientNotificationKind?) async throws -> [ClientNotification] {
        cursors.append(until); kinds.append(kind)
        if holdPage { await withCheckedContinuation { continuation = $0 } }
        if denied { throw ClientAPIError.rejected(status: deniedStatus, code: "FORBIDDEN") }
        let indices = until == nil ? [0, 1] : until == "notice-1" ? [1, 2] : []
        return try indices.map { index in
            let body: [String: Any] = ["id": "notice-\(index)", "type": kind?.rawValue ?? "follow", "createdAt": "2026-11-16T00:00:00Z", "user": ["id": "synthetic", "username": "synthetic"]]
            return try JSONDecoder().decode(ClientNotification.self, from: JSONSerialization.data(withJSONObject: body))
        }
    }
    func markAllNotificationsRead() throws {
        writes += 1
        if rejectWrite { throw ClientAPIError.rejected(status: 403, code: "PERMISSION_DENIED") }
        unread = afterWrite
        if failReadsAfterWrite { readFailure = true }
        if loseResponse { throw URLError(.networkConnectionLost) }
    }
    func denyPages(status: Int = 403) { denied = true; deniedStatus = status }
    func changeOwner() { owner = "other" }
    func enableReads() { readFailure = false }
    func releasePage() { continuation?.resume(); continuation = nil }
}
