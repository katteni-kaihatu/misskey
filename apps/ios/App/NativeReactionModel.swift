// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

@MainActor
final class NativeReactionModel: ObservableObject {
    @Published private(set) var note: ClientNote?
    @Published private(set) var busy = false
    @Published private(set) var unknown = false
    @Published private(set) var error: String?
    @Published private(set) var requiresSignIn = false
    @Published private(set) var version = 0
    private var confirmed: ClientNote?
    private weak var sourceNote: ClientNote?
    private var lease = UUID()
    private struct Intent {
        let original: ClientNote
        let choice: NativeEmojiChoice?
        let value: String
        let removing: Bool
        let owner: String
        let api: any NativeEmojiAPI
        let accepts: () -> Bool
        let completion: CheckedContinuation<Void, Never>
    }
    private var pending: [Intent] = []

    func clear() {
        version += 1
        lease = UUID(); confirmed = nil; sourceNote = nil; note = nil; busy = false; unknown = false; error = nil; requiresSignIn = false
        finishPending()
    }
    @discardableResult func receiveLive(_ state: ClientReactionState, expectedVersion: Int) -> Bool {
        guard version == expectedVersion, !busy, !unknown, let confirmed,
              !confirmed.isPureRenote, confirmed.id == state.noteId else { return false }
        guard state.valid, state.isComplete, confirmed.supportsExtendedReactions || state.myReactions.count <= 1 else { return false }
        self.confirmed = confirmed.applyingLiveReactions(state); project(); version += 1
        return true
    }
    func hideFromLive() {
        guard let hidden = confirmed?.hiding() else { return }
        let source = sourceNote; clear(); sourceNote = source; confirmed = hidden; note = hidden
    }
    func receive(_ source: ClientNote) {
        guard sourceNote !== source else { return }
        sourceNote = source
        if source.isHidden == true {
            clear(); sourceNote = source; confirmed = source; note = source; return
        }
        // A refreshed feed is authoritative once pending writes are settled.
        // Remounting the same cached feed row must not undo a completed write.
        guard !busy else { return }
        confirmed = source; note = source; unknown = false; error = nil; version += 1
    }
    private func finishPending() {
        let old = pending; pending = []
        for intent in old { intent.completion.resume() }
    }
    private func project() {
        note = pending.reduce(confirmed) { current, intent in
            let value = ClientEmojiSearch.localName(intent.value).map { ":" + $0 + "@.:" } ?? intent.value
            return current?.projectingReaction(value, adding: !intent.removing, emojiURL: intent.choice?.custom?.url)
        }
    }
    func refresh(id: String, api: any NativeEmojiAPI, accepts: () -> Bool) async {
        guard !busy, accepts() else { return }
        let token = lease; busy = true
        defer { if token == lease { busy = false } }
        do {
            let fresh = try await api.note(id)
            guard token == lease, accepts(), !Task.isCancelled else { return }
            guard fresh.id == id else { throw ClientAPIError.invalidResponse }
            confirmed = fresh; note = fresh; version += 1
            // A pure renote has no reactions of its own. The API deliberately
            // skips hydration for that wrapper; nil does not mean read failure.
            guard fresh.isHidden != true, fresh.isPureRenote || !fresh.supportsExtendedReactions || fresh.reactionStateComplete == true else { throw ClientAPIError.invalidResponse }
            unknown = false; error = nil
        } catch { if token == lease, accepts() { denied(error); self.error = NativeClientSession.explain(error) } }
    }
    /// Reconcile only the reply/renote target's counters. This read must not
    /// interrupt queued reactions, resolve uncertain writes or surface a new
    /// error after the post itself has already succeeded.
    func refreshAfterPost(id: String, api: any NativeEmojiAPI, accepts: () -> Bool) async {
        guard !busy, !unknown, accepts(), !Task.isCancelled else { return }
        let token = lease, previousVersion = version
        do {
            let fresh = try await api.note(id)
            guard lease == token, version == previousVersion, !busy, !unknown, accepts(), !Task.isCancelled,
                  fresh.id == id, fresh.isHidden == true || fresh.isPureRenote || !fresh.supportsExtendedReactions || fresh.reactionStateComplete == true else { return }
            // Keep the original feed object as the source token, so remounting
            // that cached row cannot undo the reconciled target snapshot.
            if fresh.isHidden == true {
                let source = sourceNote; clear(); sourceNote = source
            }
            confirmed = fresh; note = fresh; version += 1
        } catch { /* A cosmetic read failure must not turn a successful post into an error. */ }
    }
    func apply(_ choice: NativeEmojiChoice?, to original: ClientNote, owner: String, api: any NativeEmojiAPI, accepts: @escaping () -> Bool) async {
        guard !unknown, accepts(), !Task.isCancelled, !requiresSignIn else { return }
        guard !busy || !pending.isEmpty else { return } // An explicit recovery read owns the state.
        guard confirmed == nil || confirmed?.id == original.id else { return }
        let removing = choice?.intent == .remove || (choice?.intent == nil && (choice == nil || original.hasOwnReaction(choice!.value)))
        guard let wanted = choice?.value ?? (original.ownReactions.count == 1 ? original.ownReactions.first : nil) else {
            error = "解除するリアクションを選んでください。"; return
        }
        if confirmed == nil { confirmed = original }
        if sourceNote == nil { sourceNote = original }
        await withCheckedContinuation { completion in
            let start = pending.isEmpty
            pending.append(Intent(original: original, choice: choice, value: wanted, removing: removing, owner: owner, api: api, accepts: accepts, completion: completion))
            version += 1
            busy = true; error = nil; project() // Publish before the first network suspension.
            if start { let token = lease; Task { await drain(token) } }
        }
    }
    private func drain(_ token: UUID) async {
        while token == lease, let intent = pending.first {
            guard intent.accepts(), !Task.isCancelled else { clear(); return }
            let succeeded = await send(intent, token: token)
            guard token == lease else { return }
            pending.removeFirst().completion.resume()
            if !succeeded { finishPending() }
            project(); version += 1
        }
        if token == lease { busy = false }
    }
    private func send(_ intent: Intent, token: UUID) async -> Bool {
        let original = intent.original, wanted = intent.value, api = intent.api, removing = intent.removing
        var wrote = false, acknowledged = false
        func fail(_ message: String) -> Bool { error = message; return false }
        do {
            let fresh = try await api.note(original.id)
            guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
            guard fresh.id == original.id else { throw ClientAPIError.invalidResponse }
            confirmed = fresh; project()
            let account = try await api.account()
            guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
            guard fresh.isHidden != true, !fresh.isPureRenote, account.id == intent.owner else { throw ClientAPIError.invalidResponse }
            let extended = fresh.supportsExtendedReactions
            guard extended == original.supportsExtendedReactions else { return fail("リアクションの利用条件が変わりました。表示を再取得してください。") }
            guard !extended || fresh.reactionStateComplete == true else { return fail("リアクションの状態を取得できませんでした。再取得してから操作してください。") }
            if removing {
                if extended { guard fresh.hasOwnReaction(wanted) else { return true } }
                else {
                    let expected = intent.choice?.intent == .remove ? wanted : original.myReaction
                    guard ClientEmojiSearch.equivalent(expected, fresh.myReaction) else { return fail("リアクションが変わりました。現在の表示を確認してください。") }
                    guard fresh.myReaction != nil else { return true }
                }
            } else {
                if fresh.hasOwnReaction(wanted) { return true }
                if extended && fresh.ownReactions.count >= 16 { return fail("1つのノートに付けられるリアクションは16種類までです。") }
                if let name = intent.choice.flatMap({ $0.custom?.name ?? ClientEmojiSearch.localName($0.value) }) {
                    let checked = try await api.emoji(name)
                    guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
                    guard checked.name == name, checked.validName else { throw ClientAPIError.invalidResponse }
                    if let reason = checked.restriction(note: fresh, roles: Set((account.roles ?? []).map(\.id))) { return fail(reason) }
                } else {
                    guard !wanted.hasPrefix(":") else { return fail("ほかのサーバーの絵文字は選択できません。絵文字一覧から選んでください。") }
                    if fresh.acceptsOnlyLike, !ClientEmojiSearch.equivalent(wanted, "❤") { return fail("このノートはいいねのみ受け付けます。") }
                }
            }
            guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
            let value = ClientEmojiSearch.localName(wanted).map { ":" + $0 + ":" } ?? wanted
            wrote = true
            if removing { try await api.removeReaction(note: fresh.id, reaction: extended ? value : nil, extended: extended) }
            else {
                // Ordinary remote notes have one reaction. Changing it requires
                // deleting the old one before creating the new one.
                if !extended && fresh.myReaction != nil {
                    try await api.removeReaction(note: fresh.id, reaction: nil, extended: false)
                    acknowledged = true
                    guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
                }
                try await api.react(note: fresh.id, reaction: value, extended: extended)
            }
            acknowledged = true
            let result = try await api.note(fresh.id)
            guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
            guard result.id == fresh.id else { throw ClientAPIError.invalidResponse }
            confirmed = result
            guard result.isHidden != true, !extended || result.reactionStateComplete == true else { throw ClientAPIError.invalidResponse }
            if result.hasOwnReaction(wanted) == removing { return fail("サーバーの現在のリアクションが変わりました。表示を確認してください。") }
            return true
        } catch {
            guard token == lease, intent.accepts(), !Task.isCancelled else { return false }
            denied(error)
            if wrote {
                if !acknowledged, case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 {
                    self.error = NativeClientSession.explain(error)
                } else {
                    unknown = true; self.error = "結果を確認できませんでした。状態を再取得してから操作してください。"
                }
            } else { self.error = NativeClientSession.explain(error) }
            return false
        }
    }
    private func denied(_ error: Error) {
        if case ClientAPIError.rejected(let status, _) = error, status == 401 { confirmed = nil; note = nil; requiresSignIn = true }
    }
}

/// Ordinary note reactions live with the authenticated session, so List row
/// recycling does not discard a user's queued taps. No state goes to disk.
@MainActor
final class NativeReactionStore {
    private final class Reference {
        weak var model: NativeReactionModel?
        init(_ model: NativeReactionModel) { self.model = model }
    }
    private var models: [String: Reference] = [:]
    private var retained: [String: NativeReactionModel] = [:]
    private var order: [String] = []
    func model(_ id: String) -> NativeReactionModel {
        if let model = models[id]?.model { return model }
        models = models.filter { $0.value.model != nil }
        if retained.count >= 256, let oldest = order.first(where: { retained[$0]?.busy == false }) {
            retained.removeValue(forKey: oldest); order.removeAll { $0 == oldest }
        }
        let model = NativeReactionModel()
        models[id] = Reference(model)
        if retained.count < 256 { retained[id] = model; order.append(id) }
        return model
    }
    func existing(_ id: String) -> NativeReactionModel? { models[id]?.model }
    func clear() {
        // Mounted rows still own these objects. Clear their content in place
        // so every view continues sharing one queue after a revision change.
        for reference in models.values { reference.model?.clear() }
    }
}
