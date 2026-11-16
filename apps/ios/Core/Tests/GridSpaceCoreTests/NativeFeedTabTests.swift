// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativeFeedTabTests: XCTestCase {
    func testStableIDsDeduplicateChannelsAndKeepTheChosenOrderAcrossEncoding() throws {
        let tabs: [ClientFeedTab] = [.channel(id: "a", name: " Music "), .timeline(.home), .channel(id: "a", name: "Duplicate"), .timeline(.home), .timeline(.global)]
        let normalized = ClientFeedTab.normalized(tabs)
        XCTAssertEqual(normalized.map(\.id), ["channel:a", "home", "global"])
        XCTAssertEqual(normalized.first?.title, "Music")
        XCTAssertEqual(try JSONDecoder().decode([ClientFeedTab].self, from: JSONEncoder().encode(normalized)), normalized)
    }
    func testBadIdentifiersLimitsAndEmptyConfigurationHaveSafeFallbacks() {
        XCTAssertFalse(ClientFeedTab.validChannelID("../wrong")); XCTAssertFalse(ClientFeedTab.validChannelID(""))
        XCTAssertEqual(ClientFeedTab.normalized([.channel(id: "../wrong", name: "Bad")]), [.timeline(.local)])
        XCTAssertEqual(ClientFeedTab.normalized([]), [.timeline(.local)])
        XCTAssertEqual(ClientFeedTab.normalized((0..<25).map { .channel(id: "c\($0)", name: "Channel") }).count, 20)
        XCTAssertEqual(ClientFeedTab.normalized([.channel(id: "safe", name: " \n")]).first?.title, "チャンネル")
    }
    func testPeerTabsKeepSourceIdentityAndPreserveExistingLocalRecords() throws {
        let local = ClientFeedTab.channel(id: "same", name: "Local")
        let peer = ClientFeedTab.peerChannel(origin: "https://PEER.example", id: "same", name: "Peer")
        let tabs = ClientFeedTab.normalized([local, peer])
        XCTAssertEqual(tabs.count, 2); XCTAssertNotEqual(tabs[0].id, tabs[1].id)
        XCTAssertEqual(peer.id, tabs[1].id)
        XCTAssertTrue(tabs[1].title.contains("peer.example"))
        XCTAssertEqual(try JSONDecoder().decode([ClientFeedTab].self, from: JSONEncoder().encode(tabs)), tabs)
        XCTAssertEqual(ClientFeedTab.normalized([.peerChannel(origin: "http://peer.example", id: "same", name: "Bad")]), [.timeline(.local)])
        XCTAssertEqual(ClientFeedTab.normalized([.peerChannel(origin: "https://peer.example", id: "../id", name: "Bad")]), [.timeline(.local)])
    }
    func testAnonymousDefaultsExcludeHomeAndChannelDecodingKeepsSensitiveAndArchivedState() throws {
        XCTAssertEqual(ClientFeedTab.defaults(signedIn: false).map(\.id), ["local", "global"])
        XCTAssertEqual(ClientFeedTab.defaults(signedIn: true).map(\.id), ["home", "local", "global"])
        let channel = try JSONDecoder().decode(ClientChannel.self, from: Data(#"{"id":"synthetic","name":"Channel","isSensitive":true,"isArchived":true}"#.utf8))
        XCTAssertTrue(channel.isSensitive == true); XCTAssertTrue(channel.isArchived == true)
    }
}
