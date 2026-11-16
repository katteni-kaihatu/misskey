// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeFeedPreferencesTests: XCTestCase {
    func testOrderingAndChannelSelectionPersistWithoutCrossingAccountOriginOrAnonymousScopes() throws {
        let suite = "FeedPreferences." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NativeFeedStore(defaults: defaults), origin = try ServerOrigin("https://synthetic.example")
        let preferences = NativeFeedPreferences(store: store)
        preferences.activate(origin: origin, account: "first")
        let custom: [ClientFeedTab] = [.channel(id: "channel-a", name: "Synthetic channel"), .timeline(.global)]
        preferences.replace(custom)
        let restored = NativeFeedPreferences(store: store)
        restored.activate(origin: origin, account: "first"); XCTAssertEqual(restored.tabs, custom)
        restored.activate(origin: origin, account: "second"); XCTAssertEqual(restored.tabs, ClientFeedTab.defaults(signedIn: true))
        restored.activate(origin: origin, account: "anonymous"); restored.replace([.timeline(.global)])
        restored.activate(origin: origin, account: nil); XCTAssertEqual(restored.tabs.map(\.id), ["local", "global"])
        restored.activate(origin: try ServerOrigin("https://other.example"), account: "first")
        XCTAssertEqual(restored.tabs, ClientFeedTab.defaults(signedIn: true))
        restored.activate(origin: origin, account: "first"); XCTAssertEqual(restored.tabs, custom)
    }
    func testDuplicateAdditionLastTabRemovalAndAnonymousHomeAreBounded() throws {
        let suite = "FeedPreferences." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NativeFeedPreferences(store: NativeFeedStore(defaults: defaults))
        model.activate(origin: try ServerOrigin("https://synthetic.example"), account: "owner")
        XCTAssertFalse(model.add(.timeline(.local))); XCTAssertFalse(model.add(.channel(id: "../wrong", name: "Invalid")))
        model.replace([]); XCTAssertEqual(model.tabs, [.timeline(.local)])
        model.replace([.timeline(.home)])
        XCTAssertEqual(model.visible(signedIn: false), [.timeline(.local)])
        model.replace((0..<20).map { .channel(id: "c\($0)", name: "Channel") })
        XCTAssertFalse(model.add(.timeline(.global))); XCTAssertEqual(model.tabs.count, 20)
    }
    func testDamagedStoredDataRestoresDefaults() throws {
        let suite = "FeedPreferences." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NativeFeedStore(defaults: defaults), origin = try ServerOrigin("https://synthetic.example")
        store.write([.timeline(.global)], origin: origin, account: "owner")
        let key = try XCTUnwrap(defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("gridspace.feedTabs.v1.") })
        defaults.set(Data("damaged".utf8), forKey: key)
        XCTAssertEqual(store.read(origin: origin, account: "owner"), ClientFeedTab.defaults(signedIn: true))
    }
}
