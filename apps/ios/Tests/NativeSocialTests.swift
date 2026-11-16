// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

private func socialNote(_ id: String, reply: String? = nil, hidden: Bool = false, voted: Set<Int>? = nil, multiple: Bool = false) throws -> ClientNote {
    var object: [String: Any] = ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "followers", "text": "synthetic",
                               "user": ["id": "owner", "username": "synthetic"], "isHidden": hidden]
    if let reply { object["replyId"] = reply }
    if let voted { object["poll"] = ["multiple": multiple, "expiresAt": NSNull(), "choices": (0..<2).map { ["text": "choice-\($0)", "votes": voted.contains($0) ? 1 : 0, "isVoted": voted.contains($0)] as [String: Any] }] }
    return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: object))
}

@MainActor
final class NativeThreadTests: XCTestCase {
    func testAcknowledgedReplyIsMergedWithoutReloadingTheConversationOrResettingItsCursor() async throws {
        let api = try ThreadAPIStub(), model = NativeThreadModel()
        await model.load("main", api: api, accepts: { true })
        let original = model.note, parent = model.parents.first
        let created = try socialNote("created", reply: "main")
        model.receivePosted(created); model.receivePosted(created)
        model.receivePosted(try socialNote("other-thread", reply: "other"))
        XCTAssertTrue(model.note === original); XCTAssertTrue(model.parents.first === parent)
        XCTAssertEqual(model.replies.first?.id, "created"); XCTAssertEqual(model.replies.count, 31)
        await model.loadReplies(api: api, accepts: { true })
        let cursors = await api.cursors; XCTAssertEqual(cursors, [nil, "reply-29"])
        XCTAssertEqual(model.replies.first?.id, "created")
    }
    func testPaginationUsesRawOffsetAndReplyCursorWhileDeduplicatingBoundaries() async throws {
        let api = try ThreadAPIStub()
        let model = NativeThreadModel()
        await model.load("main", api: api, accepts: { true })
        XCTAssertEqual(model.parents.count, 20); XCTAssertEqual(model.replies.count, 30)
        XCTAssertTrue(model.moreParents); XCTAssertTrue(model.moreReplies)
        await model.loadParents(api: api, accepts: { true }); await model.loadReplies(api: api, accepts: { true })
        XCTAssertEqual(model.parents.count, 21); XCTAssertEqual(model.replies.count, 31)
        XCTAssertFalse(model.moreParents); XCTAssertFalse(model.moreReplies)
        let offsets = await api.offsets, cursors = await api.cursors
        XCTAssertEqual(offsets, [0, 20]); XCTAssertEqual(cursors, [nil, "reply-29"])
    }
    func testHiddenTargetDoesNotStartConversationOrReplyRequests() async throws {
        let api = try ThreadAPIStub(hidden: true)
        let model = NativeThreadModel()
        await model.load("main", api: api, accepts: { true })
        XCTAssertEqual(model.note?.isHidden, true)
        let offsets = await api.offsets, cursors = await api.cursors
        XCTAssertTrue(offsets.isEmpty); XCTAssertTrue(cursors.isEmpty)
    }
    func testReplyFailureKeepsTheAuthorizedMainNoteAndOtherConversationSection() async throws {
        let api = try ThreadAPIStub(replyError: true)
        let model = NativeThreadModel()
        await model.load("main", api: api, accepts: { true })
        XCTAssertEqual(model.note?.id, "main"); XCTAssertEqual(model.parents.count, 20)
        XCTAssertNotNil(model.repliesError); XCTAssertNil(model.parentsError)
    }
    func testClearingAViewDiscardsLateMainResponseAndDoesNotRequestChildren() async throws {
        let api = try ThreadAPIStub(delayed: true), model = NativeThreadModel()
        let operation = Task { await model.load("main", api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        model.clear(); await api.release(); await operation.value
        XCTAssertNil(model.note); XCTAssertTrue(model.parents.isEmpty); XCTAssertTrue(model.replies.isEmpty)
        let offsets = await api.offsets; XCTAssertTrue(offsets.isEmpty)
    }
}

private actor ThreadAPIStub: NativeThreadAPI {
    let main: ClientNote
    let delayed: Bool
    let replyError: Bool
    private var continuation: CheckedContinuation<ClientNote, Error>?
    var waiting: Bool { continuation != nil }
    private(set) var offsets: [Int] = []
    private(set) var cursors: [String?] = []
    init(hidden: Bool = false, replyError: Bool = false, delayed: Bool = false) throws {
        main = try socialNote("main", reply: "parent", hidden: hidden); self.delayed = delayed; self.replyError = replyError
    }
    func note(_ id: String) async throws -> ClientNote {
        if delayed { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return main
    }
    func release() { continuation?.resume(returning: main); continuation = nil }
    func conversation(_ id: String, offset: Int) throws -> [ClientNote] {
        offsets.append(offset)
        return try (offset == 0 ? Array(0..<20) : [19, 20]).map { try socialNote("parent-\($0)") }
    }
    func replies(_ id: String, until: String?) throws -> [ClientNote] {
        cursors.append(until)
        if replyError { throw URLError(.notConnectedToInternet) }
        return try (until == nil ? Array(0..<30) : [29, 30]).map { try socialNote("reply-\($0)") }
    }
}

@MainActor
final class NativePollStateTests: XCTestCase {
    func testLostVoteResponseReadsCommittedStateWithoutPostingAgain() async throws {
        let api = PollAPIStub(mode: .committedLostResponse), initial = try socialNote("poll", voted: [])
        let model = NativePollModel(poll: try XCTUnwrap(initial.poll))
        await model.vote("poll", choice: 0, expectedText: "choice-0", api: api, accepts: { true })
        XCTAssertEqual(model.poll?.choices[0].isVoted, true); XCTAssertFalse(model.unknown)
        XCTAssertTrue(model.error?.contains("再取得しました") == true)
        await model.vote("poll", choice: 1, expectedText: "choice-1", api: api, accepts: { true })
        let calls = await api.voteCalls; XCTAssertEqual(calls, [0])
    }
    func testMultiplePollAllowsDistinctVotesButNeverRepostsAnExistingChoice() async throws {
        let api = PollAPIStub(mode: .success, multiple: true), initial = try socialNote("poll", voted: [], multiple: true)
        let model = NativePollModel(poll: try XCTUnwrap(initial.poll))
        for choice in [0, 1, 1] { await model.vote("poll", choice: choice, expectedText: "choice-\(choice)", api: api, accepts: { true }) }
        let calls = await api.voteCalls; XCTAssertEqual(calls, [0, 1]); XCTAssertEqual(model.poll?.totalVotes, 2)
    }
    func testChangedChoiceTextDoesNotSendThePreviouslyConfirmedVote() async throws {
        let api = PollAPIStub(mode: .success), initial = try socialNote("poll", voted: [])
        let model = NativePollModel(poll: try XCTUnwrap(initial.poll))
        await model.vote("poll", choice: 0, expectedText: "old text", api: api, accepts: { true })
        let calls = await api.voteCalls; XCTAssertTrue(calls.isEmpty); XCTAssertNotNil(model.error)
    }
    func testAQueuedConfirmationCannotVoteAfterItsViewWasClearedAndReopened() async throws {
        let api = PollAPIStub(mode: .success), initial = try socialNote("poll", voted: [])
        let poll = try XCTUnwrap(initial.poll), model = NativePollModel(poll: poll)
        let previous = model.lease
        model.clear(); model.replace(poll)
        await model.vote("poll", choice: 0, expectedText: "choice-0", api: api, lease: previous, accepts: { true })
        let calls = await api.voteCalls; XCTAssertTrue(calls.isEmpty)
    }
    func testUnverifiableOutcomeBlocksAnotherWriteUntilAnExplicitReadSucceeds() async throws {
        let api = PollAPIStub(mode: .lostAndUnreadable), initial = try socialNote("poll", voted: [])
        let model = NativePollModel(poll: try XCTUnwrap(initial.poll))
        await model.vote("poll", choice: 0, expectedText: "choice-0", api: api, accepts: { true })
        XCTAssertTrue(model.unknown)
        await model.vote("poll", choice: 0, expectedText: "choice-0", api: api, accepts: { true })
        var calls = await api.voteCalls; XCTAssertEqual(calls.count, 1)
        await api.enableReads(); await model.refresh("poll", api: api, accepts: { true })
        XCTAssertFalse(model.unknown); calls = await api.voteCalls; XCTAssertEqual(calls.count, 1)
        model.clear(); XCTAssertNil(model.poll)
    }
}

private actor PollAPIStub: NativePollAPI {
    enum Mode { case success, committedLostResponse, lostAndUnreadable }
    let mode: Mode
    let multiple: Bool
    var unreadable = false
    var voted = Set<Int>()
    private(set) var voteCalls: [Int] = []
    init(mode: Mode, multiple: Bool = false) { self.mode = mode; self.multiple = multiple }
    func note(_ id: String) throws -> ClientNote {
        if unreadable { throw URLError(.networkConnectionLost) }
        return try socialNote(id, voted: voted, multiple: multiple)
    }
    func vote(_ id: String, choice: Int) throws {
        voteCalls.append(choice)
        switch mode {
        case .success: voted.insert(choice)
        case .committedLostResponse: voted.insert(choice); throw URLError(.networkConnectionLost)
        case .lostAndUnreadable: unreadable = true; throw URLError(.networkConnectionLost)
        }
    }
    func enableReads() { unreadable = false }
}
