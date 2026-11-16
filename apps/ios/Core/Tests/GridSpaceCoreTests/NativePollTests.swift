// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativePollTests: XCTestCase {
    private func poll(multiple: Bool, expires: String? = nil) throws -> ClientPoll {
        let object: [String: Any] = ["multiple": multiple, "expiresAt": expires as Any? ?? NSNull(),
                                   "choices": [["text": "one", "votes": 2, "isVoted": true], ["text": "two", "votes": 1, "isVoted": false]]]
        return try JSONDecoder().decode(ClientPoll.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testSingleVoteLocksAllChoicesWhileMultipleAllowsAnotherChoice() throws {
        let single = try poll(multiple: false), multiple = try poll(multiple: true)
        XCTAssertFalse(single.canVote(0, at: Date())); XCTAssertFalse(single.canVote(1, at: Date()))
        XCTAssertFalse(multiple.canVote(0, at: Date())); XCTAssertTrue(multiple.canVote(1, at: Date()))
        XCTAssertFalse(multiple.canVote(-1, at: Date())); XCTAssertFalse(multiple.canVote(2, at: Date()))
        XCTAssertEqual(multiple.totalVotes, 3)
    }
    func testExpirationIsClosedAtTheExactBoundaryAndAnUnknownDateDoesNotOpenVoting() throws {
        let value = try poll(multiple: true, expires: "2026-11-16T00:00:00.123Z")
        let end = try XCTUnwrap(value.expiration)
        XCTAssertFalse(value.closed(at: end.addingTimeInterval(-0.001)))
        XCTAssertTrue(value.closed(at: end))
        XCTAssertFalse(value.canVote(1, at: end))
        XCTAssertTrue(try poll(multiple: true, expires: "invalid-date").closed(at: Date()))
        XCTAssertFalse(try poll(multiple: true).closed(at: Date()))
    }
}
