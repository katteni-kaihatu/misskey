// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

private func profileReadDenied(_ error: Error) -> Bool {
    guard case ClientAPIError.rejected(let status, let code) = error else { return false }
    // Misskey endpoint errors can use HTTP 400 with a semantic denial code.
    return [401, 403, 404].contains(status) || ["FORBIDDEN", "NO_SUCH_USER"].contains(code)
}

protocol NativeProfileAPI: Sendable {
    func user(_ id: String) async throws -> ClientUser
    func userNotes(_ id: String, filter: ClientProfileFilter, until: String?) async throws -> [ClientNote]
    func changeFollowing(_ id: String, action: ClientFollowAction) async throws
}

@MainActor
final class NativeProfileModel: ObservableObject {
    @Published private(set) var user: ClientUser?
    @Published private(set) var notes: [ClientNote] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingNotes = false
    @Published private(set) var more = false
    @Published private(set) var mutating = false
    @Published private(set) var uncertain = false
    @Published private(set) var error: String?
    @Published private(set) var notesError: String?
    @Published private(set) var relationshipError: String?
    private(set) var lease = UUID()
    private var filter: ClientProfileFilter = .posts
    private var cursor: String?
    private var notesGeneration = UUID()

    func clear() {
        lease = UUID(); user = nil; invalidateNotes()
        loading = false; loadingNotes = false; mutating = false; more = false; uncertain = false
        error = nil; notesError = nil; relationshipError = nil
    }
    func load(_ id: String, filter: ClientProfileFilter, api: any NativeProfileAPI, accepts: @escaping @MainActor () -> Bool) async {
        clear(); self.filter = filter
        guard accepts(), !Task.isCancelled else { return }
        let token = lease; loading = true
        do {
            let result = try await api.user(id)
            guard token == lease, accepts(), !Task.isCancelled else { return }
            guard result.id == id else { throw ClientAPIError.invalidResponse }
            user = result; loading = false
            await loadMore(api: api, accepts: accepts)
        } catch { if token == lease, accepts(), !Task.isCancelled { self.error = NativeClientSession.explain(error); loading = false } }
    }
    func loadMore(api: any NativeProfileAPI, accepts: () -> Bool) async {
        guard !mutating else { return }
        await fetchMore(api: api, accepts: accepts)
    }
    private func fetchMore(api: any NativeProfileAPI, accepts: () -> Bool) async {
        guard let user, !loadingNotes, accepts(), !Task.isCancelled else { return }
        let token = lease, pageToken = notesGeneration, previous = cursor, mode = filter
        loadingNotes = true; notesError = nil
        do {
            let page = try await api.userNotes(user.id, filter: mode, until: previous)
            guard token == lease, pageToken == notesGeneration, accepts(), !Task.isCancelled else { return }
            notes = appendClientNotes(page, to: notes); cursor = page.last?.id ?? previous
            more = page.count == 30 && cursor != previous
        } catch {
            if token == lease, pageToken == notesGeneration, accepts(), !Task.isCancelled {
                if profileReadDenied(error) { notes = []; cursor = nil; more = false }
                notesError = NativeClientSession.explain(error)
            }
        }
        if token == lease, pageToken == notesGeneration { loadingNotes = false }
    }
    func receivePosted(_ note: ClientNote) {
        guard let user, note.user.id == user.id, note.isHidden != true,
              note.channelId == nil, note.channel == nil,
              filter == .replies || note.replyId == nil,
              filter != .media || !(note.files ?? []).isEmpty else { return }
        notes = appendClientNotes(notes, to: [note])
    }
    func change(_ action: ClientFollowAction, viewer: String, api: any NativeProfileAPI, expectedLease: UUID, accepts: () -> Bool) async {
        guard let id = user?.id, expectedLease == lease, !mutating, !uncertain, accepts(), !Task.isCancelled else { return }
        let token = lease; mutating = true; relationshipError = nil
        defer { if lease == token { mutating = false } }
        do {
            let fresh = try await api.user(id)
            guard token == lease, accepts(), !Task.isCancelled else { return }
            guard fresh.id == id else { throw ClientAPIError.invalidResponse }
            replaceUser(fresh)
            guard fresh.followAction(viewer: viewer) == action else { relationshipError = "関係の状態が変わりました。最新の表示を確認してください。"; return }
            invalidateNotes(); notesError = "操作後の投稿を再取得してください。"
            do { try await api.changeFollowing(id, action: action) }
            catch {
                guard token == lease, accepts(), !Task.isCancelled else { return }
                uncertain = true
                if case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 {
                    uncertain = false
                    relationshipError = status == 403 ? "フォローの権限を確認してください。アカウントメニューからログインし直すと権限を追加できます。" : NativeClientSession.explain(error)
                } else { relationshipError = "操作結果が不明です。関係を再取得してください。自動では再送しません。" }
            }
            guard token == lease, accepts(), !Task.isCancelled else { return }
            let wasUnknown = uncertain
            do {
                let result = try await api.user(id)
                guard token == lease, accepts(), !Task.isCancelled else { return }
                guard result.id == id else { throw ClientAPIError.invalidResponse }
                replaceUser(result); uncertain = false
                if wasUnknown { relationshipError = "最新の関係を再取得しました。表示を確認してください。" }
                await fetchMore(api: api, accepts: accepts)
            } catch {
                if token == lease, accepts(), !Task.isCancelled, !clearIfDenied(error) { uncertain = true; relationshipError = "最新の関係を確認できませんでした。再取得してください。" }
            }
        } catch { if token == lease, accepts(), !Task.isCancelled, !clearIfDenied(error) { relationshipError = NativeClientSession.explain(error) } }
    }
    func refreshRelationship(api: any NativeProfileAPI, expectedLease: UUID, accepts: () -> Bool) async {
        guard let id = user?.id, lease == expectedLease, !mutating, accepts(), !Task.isCancelled else { return }
        mutating = true
        defer { if lease == expectedLease { mutating = false } }
        do {
            let result = try await api.user(id)
            guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
            guard result.id == id else { throw ClientAPIError.invalidResponse }
            let changed = user?.isFollowing != result.isFollowing
            replaceUser(result); uncertain = false; relationshipError = nil
            if changed || notesError != nil {
                await fetchMore(api: api, accepts: accepts)
            }
        } catch { if lease == expectedLease, accepts(), !Task.isCancelled, !clearIfDenied(error) { relationshipError = NativeClientSession.explain(error) } }
    }
    private func clearIfDenied(_ error: Error) -> Bool {
        guard profileReadDenied(error) else { return false }
        clear(); self.error = NativeClientSession.explain(error)
        return true
    }
    private func invalidateNotes() {
        notesGeneration = UUID(); notes = []; cursor = nil; more = false; loadingNotes = false; notesError = nil
    }
    private func replaceUser(_ result: ClientUser) {
        if let user, user.isFollowing != result.isFollowing {
            invalidateNotes(); notesError = "関係が変わりました。投稿を再取得してください。"
        }
        user = result
    }
}

protocol NativePeopleAPI: Sendable {
    func people(_ id: String, kind: ClientPeopleKind, until: String?) async throws -> [ClientFollowing]
}

@MainActor
final class NativePeopleModel: ObservableObject {
    @Published private(set) var entries: [ClientFollowing] = []
    @Published private(set) var loading = false
    @Published private(set) var more = false
    @Published private(set) var error: String?
    private var generation = UUID()
    private var cursor: String?
    func clear() { generation = UUID(); entries = []; cursor = nil; loading = false; more = false; error = nil }
    func load(_ id: String, kind: ClientPeopleKind, reset: Bool, api: any NativePeopleAPI, accepts: () -> Bool) async {
        if reset { clear() }
        guard !loading, accepts(), !Task.isCancelled else { return }
        let token = generation, previous = cursor
        loading = true; error = nil
        do {
            let page = try await api.people(id, kind: kind, until: previous)
            guard generation == token, accepts(), !Task.isCancelled else { return }
            guard page.allSatisfy({ $0.person(owner: id, kind: kind) != nil }) else { throw ClientAPIError.invalidResponse }
            var known = Set(entries.map(\.id)); entries += page.filter { known.insert($0.id).inserted }
            cursor = page.last?.id ?? previous; more = page.count == 30 && cursor != previous
        } catch {
            if generation == token, accepts(), !Task.isCancelled {
                // Do not leave a previously visible private list after denial.
                entries = []; cursor = nil; more = false
                if profileReadDenied(error) { self.error = "この一覧は閲覧できません。公開設定とログイン状態を確認してください。" }
                else { self.error = NativeClientSession.explain(error) }
            }
        }
        if generation == token { loading = false }
    }
}
