// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

struct NativeFeedStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    @MainActor static func current() -> Self {
        if AppSession.isTesting {
            let scope = ProcessInfo.processInfo.environment["GRIDSPACE_FEED_TEST_STORE"] ?? "unit"
            return Self(defaults: UserDefaults(suiteName: "GridSpaceFeedTests." + scope)!)
        }
        return Self()
    }
    private func key(origin: ServerOrigin, account: String?) -> String {
        let scope = try! JSONEncoder().encode([origin.url.absoluteString, account] as [String?])
        return "gridspace.feedTabs.v1." + scope.base64EncodedString()
    }
    func read(origin: ServerOrigin, account: String?) -> [ClientFeedTab] {
        guard let data = defaults.data(forKey: key(origin: origin, account: account)), data.count < 64 * 1024,
              let tabs = try? JSONDecoder().decode([ClientFeedTab].self, from: data) else { return ClientFeedTab.defaults(signedIn: account != nil) }
        return ClientFeedTab.normalized(tabs)
    }
    func write(_ tabs: [ClientFeedTab], origin: ServerOrigin, account: String?) {
        guard let data = try? JSONEncoder().encode(ClientFeedTab.normalized(tabs)) else { return }
        defaults.set(data, forKey: key(origin: origin, account: account))
    }
}

@MainActor
final class NativeFeedPreferences: ObservableObject {
    @Published private(set) var tabs = ClientFeedTab.defaults(signedIn: false)
    private let store: NativeFeedStore
    private var scope: (ServerOrigin, String?)?
    init(store: NativeFeedStore) { self.store = store }
    func activate(origin: ServerOrigin, account: String?) {
        if let scope, scope.0 == origin, scope.1 == account { return }
        scope = (origin, account); tabs = store.read(origin: origin, account: account)
    }
    func replace(_ value: [ClientFeedTab]) {
        guard let scope else { return }
        tabs = ClientFeedTab.normalized(value)
        store.write(tabs, origin: scope.0, account: scope.1)
    }
    @discardableResult func add(_ tab: ClientFeedTab) -> Bool {
        guard scope != nil, tabs.count < 20, ClientFeedTab.normalized([tab]).first?.id == tab.id, !tabs.contains(where: { $0.id == tab.id }) else { return false }
        replace(tabs + [tab]); return true
    }
    func visible(signedIn: Bool) -> [ClientFeedTab] {
        let values = tabs.filter { signedIn || $0 != .timeline(.home) }
        return values.isEmpty ? [.timeline(.local)] : values
    }
}
