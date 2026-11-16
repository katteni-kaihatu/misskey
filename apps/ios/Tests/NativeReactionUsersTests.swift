// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeReactionUsersTests: XCTestCase {
    func testTenUniqueAvatarsAndImmediateOptimisticOwnerInsertionAndRemoval() async throws {
        let api = ReactorAPI(), model = NativeReactionUsersModel()
        await model.load(note: "note", reaction: "😂", extended: true, api: api, accepts: { true })
        XCTAssertEqual(model.users.count, 10)
        let owner = try await api.account()
        let selected = model.previews(owner: owner, selected: true)
        XCTAssertEqual(selected.count, 10); XCTAssertEqual(selected.first?.id, owner.id)
        XCTAssertEqual(Set(selected.map(\.id)).count, selected.count)
        XCTAssertFalse(model.previews(owner: owner, selected: false).contains { $0.id == owner.id })
    }
    func testActorPageAfterSessionClearCannotRepopulateOldAccountState() async throws {
        let api = ReactorAPI(hold: true), model = NativeReactionUsersModel()
        let task = Task { await model.load(note: "note", reaction: "😂", extended: true, api: api, accepts: { true }) }
        for _ in 0..<200 { if await api.waiting { break }; await Task.yield() }
        let waiting = await api.waiting; XCTAssertTrue(waiting)
        model.clear(); await api.release(); await task.value
        XCTAssertTrue(model.users.isEmpty)
    }
}
private actor ReactorAPI: NativeEmojiAPI {
    let hold: Bool
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    init(hold: Bool = false) { self.hold = hold }
    func release() { continuation?.resume(); continuation = nil }
    func reactionUsers(note: String, reaction: String, extended: Bool) async throws -> [ClientUser] {
        if hold { await withCheckedContinuation { continuation = $0 } }
        return try (0..<12).map { try user(String($0 % 11)) }
    }
    func user(_ id: String) throws -> ClientUser {
        try JSONDecoder().decode(ClientUser.self, from: JSONSerialization.data(withJSONObject: ["id": id, "username": "synthetic-" + id]))
    }
    func account() throws -> ClientUser { try user("0") }
    func emojis() -> [ClientCustomEmoji] { [] }
    func emoji(_ name: String) throws -> ClientCustomEmoji { throw ClientAPIError.invalidResponse }
    func note(_ id: String) throws -> ClientNote { throw ClientAPIError.invalidResponse }
    func react(note: String, reaction: String, extended: Bool) {}
    func removeReaction(note: String, reaction: String?, extended: Bool) {}
}
