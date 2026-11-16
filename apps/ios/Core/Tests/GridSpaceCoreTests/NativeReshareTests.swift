// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativeReshareTests: XCTestCase {
    private func note(_ extra: [String: Any] = [:]) throws -> ClientNote {
        var data: [String: Any] = ["id": "target", "createdAt": "2026-11-16T00:00:00Z", "user": ["id": "author", "username": "synthetic"], "visibility": "public", "text": "Synthetic target"]
        data.merge(extra) { _, new in new }
        return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func testReshareAudienceDoesNotWidenHomeOrFollowersNotes() throws {
        XCTAssertEqual(try note().reshareVisibilities(viewer: "viewer"), ["public", "home", "followers"])
        XCTAssertEqual(try note(["visibility": "home"]).reshareVisibilities(viewer: "viewer"), ["home", "followers"])
        let followers = try note(["visibility": "followers"])
        XCTAssertTrue(followers.reshareVisibilities(viewer: "viewer").isEmpty)
        XCTAssertEqual(followers.reshareVisibilities(viewer: "author"), ["followers"])
    }
    func testHiddenSpecifiedAndChannelNotesDoNotOfferAnOrdinaryNativeReshare() throws {
        for extra: [String: Any] in [["isHidden": true], ["visibility": "specified"], ["channelId": "channel"]] {
            XCTAssertTrue(try note(extra).reshareVisibilities(viewer: "author").isEmpty)
        }
        XCTAssertNil(try note(["isHidden": true]).reshareTarget)
    }
    func testPureReshareUsesTheOriginalIDButAQuoteKeepsItsOwnID() throws {
        let original: [String: Any] = ["id": "original", "createdAt": "2026-11-16T00:00:00Z", "user": ["id": "other", "username": "synthetic"], "visibility": "home", "text": "Synthetic original", "localOnly": true]
        let pure = try note(["text": NSNull(), "renoteId": "original", "renote": original])
        XCTAssertTrue(pure.isPureRenote); XCTAssertEqual(pure.reshareTarget?.id, "original"); XCTAssertEqual(pure.reshareTarget?.localOnly, true)
        let quote = try note(["renoteId": "original", "renote": original])
        XCTAssertFalse(quote.isPureRenote); XCTAssertEqual(quote.reshareTarget?.id, "target")
        var hidden = original; hidden["isHidden"] = true
        XCTAssertNil(try note(["text": NSNull(), "renote": hidden]).reshareTarget)
        XCTAssertNil(try note(["text": NSNull(), "renoteId": "mismatched", "renote": original]).reshareTarget)
    }
    func testWebQuoteHandoffRetainsTheTargetAndLocalOnlyWithoutMixingAReply() throws {
        let url = ClientWebEditor.url(origin: try ServerOrigin("https://synthetic.example"), text: "Own & text", cw: nil, visibility: "home", replyId: nil, renoteId: "target", localOnly: true)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "renoteId" }?.value, "target")
        XCTAssertEqual(items.first { $0.name == "localOnly" }?.value, "1")
        XCTAssertFalse(items.contains { $0.name == "replyId" })
        let federated = ClientWebEditor.url(origin: try ServerOrigin("https://synthetic.example"), text: "", cw: nil, visibility: "home", replyId: nil, renoteId: "target", localOnly: false)
        XCTAssertEqual(URLComponents(url: federated, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "localOnly" }?.value, "0")
        let unspecified = ClientWebEditor.url(origin: try ServerOrigin("https://synthetic.example"), text: "", cw: nil, visibility: "home", replyId: nil)
        XCTAssertFalse(URLComponents(url: unspecified, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "localOnly" } ?? true)
    }
}
