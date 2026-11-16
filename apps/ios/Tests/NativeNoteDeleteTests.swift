// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeNoteDeleteTests: XCTestCase {
    func testDeletionReadsTheOwnerThenSendsOneExactID() async throws {
        let api = DeleteAPIStub(), model = NativeNoteDeleteModel()
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertTrue(model.deleted)
        let ids = await api.deletedIDs; XCTAssertEqual(ids, ["outer"])
    }
    func testAnotherAuthorOrHiddenNoteCannotBeDeleted() async throws {
        for api in [DeleteAPIStub(owner: "other"), DeleteAPIStub(hidden: true)] {
            let model = NativeNoteDeleteModel()
            await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
            XCTAssertFalse(model.deleted); XCTAssertNotNil(model.error)
            let ids = await api.deletedIDs; XCTAssertTrue(ids.isEmpty)
        }
    }
    func testLostDeletionResponseNeverResendsAndMissingDoesNotClaimAConfirmedDeletion() async throws {
        let api = DeleteAPIStub(loseResponse: true), model = NativeNoteDeleteModel()
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertTrue(model.unknown); XCTAssertFalse(model.deleted)
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        await model.refresh("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertTrue(model.unavailable); XCTAssertFalse(model.deleted); XCTAssertFalse(model.unknown)
        let ids = await api.deletedIDs; XCTAssertEqual(ids.count, 1)
    }
    func testFailedUncommittedDeleteRequiresAnExplicitReadBeforeAnotherConfirmation() async throws {
        let api = DeleteAPIStub(loseResponse: true, commit: false), model = NativeNoteDeleteModel()
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        var ids = await api.deletedIDs; XCTAssertEqual(ids.count, 1)
        await model.refresh("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertFalse(model.unknown); XCTAssertFalse(model.deleted); XCTAssertFalse(model.unavailable)
        ids = await api.deletedIDs; XCTAssertEqual(ids.count, 1)
    }
    func testARejectedDeleteDoesNotClaimSuccessOrAutomaticallyRetry() async throws {
        let api = DeleteAPIStub(reject: true), model = NativeNoteDeleteModel()
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { true })
        XCTAssertFalse(model.deleted); XCTAssertFalse(model.unknown); XCTAssertNotNil(model.error)
        let ids = await api.deletedIDs; XCTAssertEqual(ids.count, 1)
    }
    func testClearingDuringPreflightPreventsTheWriteAndAnOldConfirmationCannotAct() async throws {
        let api = DeleteAPIStub(holdRead: true), model = NativeNoteDeleteModel(), lease = model.lease
        let deletion = Task { await model.delete("outer", owner: "owner", expectedLease: lease, api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        model.clear(); await api.release(); await deletion.value
        await model.delete("outer", owner: "owner", expectedLease: lease, api: api, accepts: { true })
        let ids = await api.deletedIDs; XCTAssertTrue(ids.isEmpty); XCTAssertFalse(model.deleted)
    }
    func testAnExpiredAccountDoesNotSendADeletion() async throws {
        let api = DeleteAPIStub(), model = NativeNoteDeleteModel()
        await model.delete("outer", owner: "owner", expectedLease: model.lease, api: api, accepts: { false })
        let ids = await api.deletedIDs; XCTAssertTrue(ids.isEmpty)
    }
}

private actor DeleteAPIStub: NativeNoteDeleteAPI {
    let owner: String, hidden: Bool, loseResponse: Bool, commit: Bool, reject: Bool, holdRead: Bool
    var removed = false
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    private(set) var deletedIDs: [String] = []
    init(owner: String = "owner", hidden: Bool = false, loseResponse: Bool = false, commit: Bool = true, reject: Bool = false, holdRead: Bool = false) {
        self.owner = owner; self.hidden = hidden; self.loseResponse = loseResponse; self.commit = commit; self.reject = reject; self.holdRead = holdRead
    }
    func note(_ id: String) async throws -> ClientNote {
        if holdRead { await withCheckedContinuation { continuation = $0 } }
        if removed { throw ClientAPIError.rejected(status: 400, code: "NO_SUCH_NOTE") }
        let body: [String: Any] = ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "home", "isHidden": hidden, "user": ["id": owner, "username": "synthetic"], "renoteId": "original"]
        return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func deleteNote(_ id: String) throws {
        deletedIDs.append(id)
        if reject { throw ClientAPIError.rejected(status: 403, code: "ACCESS_DENIED") }
        if commit { removed = true }
        if loseResponse { throw URLError(.networkConnectionLost) }
    }
    func release() { continuation?.resume(); continuation = nil }
}
