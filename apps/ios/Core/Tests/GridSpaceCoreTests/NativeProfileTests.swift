// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativeProfileTests: XCTestCase {
    private func user(_ values: [String: Any] = [:]) throws -> ClientUser {
        let base: [String: Any] = ["id": "target", "username": "synthetic", "isFollowing": false, "hasPendingFollowRequestFromYou": false, "isLocked": false]
        return try JSONDecoder().decode(ClientUser.self, from: JSONSerialization.data(withJSONObject: base.merging(values) { _, next in next }))
    }
    func testFollowRequestFollowingAndCancellationHaveDistinctExplicitActions() throws {
        XCTAssertEqual(try user().followAction(viewer: "viewer"), .follow)
        XCTAssertEqual(try user(["isLocked": true]).followAction(viewer: "viewer"), .request)
        XCTAssertEqual(try user(["isFollowing": true]).followAction(viewer: "viewer"), .unfollow)
        XCTAssertEqual(try user(["hasPendingFollowRequestFromYou": true]).followAction(viewer: "viewer"), .cancelRequest)
        XCTAssertEqual(ClientFollowAction.request.endpoint, "following/create")
        XCTAssertEqual(ClientFollowAction.cancelRequest.endpoint, "following/requests/cancel")
    }
    func testSelfBlockedMovedAndMissingRelationsDoNotOfferANewFollow() throws {
        XCTAssertNil(try user().followAction(viewer: "target"))
        for values: [String: Any] in [["isBlocked": true], ["isBlocking": true], ["movedTo": "https://remote.example/@new"], ["isFollowing": NSNull()]] {
            XCTAssertNil(try user(values).followAction(viewer: "viewer"))
        }
        XCTAssertEqual(try user(["isFollowing": true, "movedTo": "https://remote.example/@new"]).followAction(viewer: "viewer"), .unfollow)
    }
    func testPeopleAreResolvedByTheRelationshipDirectionAndExactOwner() throws {
        let object: [String: Any] = ["id": "relationship", "followerId": "owner", "followeeId": "target", "followee": ["id": "target", "username": "synthetic"]]
        let entry = try JSONDecoder().decode(ClientFollowing.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(entry.person(owner: "owner", kind: .following)?.id, "target")
        XCTAssertNil(entry.person(owner: "other", kind: .following))
        XCTAssertNil(entry.person(owner: "target", kind: .followers))
    }
}
