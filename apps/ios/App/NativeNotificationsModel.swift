// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativeNotificationsAPI: Sendable {
    func notifications(until: String?, kind: ClientNotificationKind?) async throws -> [ClientNotification]
    func account() async throws -> ClientUser
    func markAllNotificationsRead() async throws
}

@MainActor
final class NativeNotificationsModel: ObservableObject {
    @Published private(set) var items: [ClientNotification] = []
    @Published private(set) var loading = false
    @Published private(set) var more = false
    @Published private(set) var refreshingStatus = false
    @Published private(set) var marking = false
    @Published private(set) var markUnknown = false
    @Published private(set) var requiresSignIn = false
    @Published private(set) var unreadCount: Int?
    @Published private(set) var hasUnread: Bool?
    @Published private(set) var error: String?
    @Published private(set) var statusError: String?
    @Published private(set) var operationError: String?
    @Published private(set) var notice: String?
    private(set) var lease = UUID()
    private var owner: String?
    private var kind: ClientNotificationKind?
    private var cursor: String?

    func clear() {
        lease = UUID(); owner = nil; kind = nil; cursor = nil; items = []
        loading = false; more = false; refreshingStatus = false; marking = false; markUnknown = false
        requiresSignIn = false
        unreadCount = nil; hasUnread = nil; error = nil; statusError = nil; operationError = nil; notice = nil
    }
    func load(owner: String, kind: ClientNotificationKind?, api: any NativeNotificationsAPI, accepts: @escaping @MainActor @Sendable () -> Bool) async {
        clear()
        guard accepts(), !Task.isCancelled else { return }
        self.owner = owner; self.kind = kind
        async let page: Void = loadMore(api: api, accepts: accepts)
        async let state: Void = refreshStatus(api: api, accepts: accepts)
        _ = await (page, state)
    }
    func loadMore(api: any NativeNotificationsAPI, accepts: () -> Bool) async {
        guard owner != nil, !loading, !marking, accepts(), !Task.isCancelled else { return }
        let token = lease, previous = cursor, filter = kind
        loading = true; error = nil
        defer { if token == lease { loading = false } }
        do {
            let page = try await api.notifications(until: previous, kind: filter)
            guard token == lease, accepts(), !Task.isCancelled else { return }
            if let filter { guard page.allSatisfy({ $0.type == filter.rawValue }) else { throw ClientAPIError.invalidResponse } }
            var known = Set(items.map(\.id)); items += page.filter { known.insert($0.id).inserted }
            cursor = page.last?.id ?? previous
            // The server filters each raw page and can return fewer than the
            // requested limit even though older matching notifications remain.
            more = !page.isEmpty && cursor != previous
        } catch {
            if token == lease, accepts(), !Task.isCancelled, !clearIfDenied(error) { self.error = NativeClientSession.explain(error) }
        }
    }
    func refreshStatus(api: any NativeNotificationsAPI, accepts: () -> Bool) async {
        guard !marking else { return }
        await readStatus(api: api, resolvesUnknown: true, accepts: accepts)
    }
    private func readStatus(api: any NativeNotificationsAPI, resolvesUnknown: Bool, accepts: () -> Bool) async {
        guard let owner, !refreshingStatus, accepts(), !Task.isCancelled else { return }
        let token = lease; refreshingStatus = true; statusError = nil
        defer { if token == lease { refreshingStatus = false } }
        do {
            let account = try await api.account()
            guard token == lease, accepts(), !Task.isCancelled else { return }
            try apply(account, owner: owner)
            if resolvesUnknown, markUnknown { markUnknown = false; operationError = nil; notice = "最新の未読状態を取得しました。表示を確認してください。" }
        } catch {
            if token == lease, accepts(), !Task.isCancelled, !clearIfDenied(error) {
                unreadCount = nil; hasUnread = nil; statusError = NativeClientSession.explain(error)
            }
        }
    }
    func markAll(expectedLease: UUID, api: any NativeNotificationsAPI, accepts: () -> Bool) async {
        guard let owner, expectedLease == lease, !loading, !refreshingStatus, !marking, !markUnknown, accepts(), !Task.isCancelled else { return }
        let token = lease; marking = true; operationError = nil; notice = nil
        defer { if token == lease { marking = false } }
        do {
            let account = try await api.account()
            guard token == lease, accepts(), !Task.isCancelled else { return }
            try apply(account, owner: owner)
            guard hasUnread != false else { notice = "未読の通知はありません。"; return }
            do {
                try await api.markAllNotificationsRead()
                guard token == lease, accepts(), !Task.isCancelled else { return }
                notice = "既読操作を受け付けました。現在の未読状態を確認してください。"
            } catch {
                guard token == lease, accepts(), !Task.isCancelled else { return }
                if case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 {
                    if status == 401 { _ = clearIfDenied(error); return }
                    operationError = status == 403 ? "既読操作の権限を確認してください。アカウントメニューからログインし直すと権限を追加できます。" : NativeClientSession.explain(error)
                } else { markUnknown = true; operationError = "既読操作の結果が不明です。未読状態を再取得してください。自動では再送しません。" }
            }
            await readStatus(api: api, resolvesUnknown: false, accepts: accepts)
        } catch {
            if token == lease, accepts(), !Task.isCancelled, !clearIfDenied(error) { operationError = NativeClientSession.explain(error) }
        }
    }
    private func apply(_ account: ClientUser, owner: String) throws {
        guard account.id == owner, account.unreadNotificationsCount.map({ $0 >= 0 }) ?? true,
              account.unreadNotificationsCount != nil || account.hasUnreadNotification != nil else { throw ClientAPIError.invalidResponse }
        unreadCount = account.unreadNotificationsCount
        hasUnread = account.unreadNotificationsCount.map { $0 > 0 } ?? account.hasUnreadNotification
    }
    private func clearIfDenied(_ error: Error) -> Bool {
        if case ClientAPIError.rejected(let status, let code) = error,
           [401, 403, 404].contains(status) || code == "FORBIDDEN" {
            clear(); requiresSignIn = status == 401; self.error = NativeClientSession.explain(error); return true
        }
        if case ClientAPIError.invalidResponse = error { clear(); self.error = NativeClientSession.explain(error); return true }
        return false
    }
}
