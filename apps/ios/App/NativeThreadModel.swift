// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativeThreadAPI: Sendable {
    func note(_ id: String) async throws -> ClientNote
    func conversation(_ id: String, offset: Int) async throws -> [ClientNote]
    func replies(_ id: String, until: String?) async throws -> [ClientNote]
}

@MainActor
final class NativeThreadModel: ObservableObject {
    @Published private(set) var note: ClientNote?
    @Published private(set) var parents: [ClientNote] = []
    @Published private(set) var replies: [ClientNote] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingParents = false
    @Published private(set) var loadingReplies = false
    @Published private(set) var moreParents = false
    @Published private(set) var moreReplies = false
    @Published private(set) var error: String?
    @Published private(set) var parentsError: String?
    @Published private(set) var repliesError: String?
    private var request = UUID()
    private var parentOffset = 0
    private var replyCursor: String?

    func clear() {
        request = UUID(); note = nil; parents = []; replies = []
        loading = false; loadingParents = false; loadingReplies = false
        moreParents = false; moreReplies = false; parentOffset = 0; replyCursor = nil
        error = nil; parentsError = nil; repliesError = nil
    }
    func unavailable() { clear(); error = "このノートは削除済み、または表示できません。" }
    func load(_ id: String, api: any NativeThreadAPI, accepts: @escaping @MainActor @Sendable () -> Bool) async {
        clear()
        guard accepts(), !Task.isCancelled else { return }
        let token = request; loading = true
        do {
            let result = try await api.note(id)
            guard request == token, accepts(), !Task.isCancelled else { return }
            guard result.id == id else { throw ClientAPIError.invalidResponse }
            note = result; loading = false
            guard result.isHidden != true else { return }
            async let previous: Void = loadParents(api: api, accepts: accepts)
            async let following: Void = loadReplies(api: api, accepts: accepts)
            _ = await (previous, following)
        } catch { if request == token, accepts(), !Task.isCancelled { self.error = NativeClientSession.explain(error); loading = false } }
    }
    func receivePosted(_ created: ClientNote) {
        guard let note, note.isHidden != true, created.isHidden != true, created.replyId == note.id else { return }
        replies = appendClientNotes(replies, to: [created])
    }
    func loadParents(api: any NativeThreadAPI, accepts: @escaping @MainActor @Sendable () -> Bool) async {
        guard let note, note.isHidden != true, note.replyId != nil, !loadingParents, accepts() else { return }
        let token = request, offset = parentOffset
        loadingParents = true; parentsError = nil
        do {
            let page = try await api.conversation(note.id, offset: offset)
            guard request == token, accepts(), !Task.isCancelled else { return }
            parents = appendClientNotes(page.filter { $0.id != note.id }, to: parents)
            parentOffset += page.count; moreParents = page.count == 20
        } catch { if request == token, accepts(), !Task.isCancelled { parentsError = NativeClientSession.explain(error) } }
        if request == token { loadingParents = false }
    }
    func loadReplies(api: any NativeThreadAPI, accepts: @escaping @MainActor @Sendable () -> Bool) async {
        guard let note, note.isHidden != true, !loadingReplies, accepts() else { return }
        let token = request, cursor = replyCursor
        loadingReplies = true; repliesError = nil
        do {
            let page = try await api.replies(note.id, until: cursor)
            guard request == token, accepts(), !Task.isCancelled else { return }
            replies = appendClientNotes(page.filter { $0.id != note.id }, to: replies)
            replyCursor = page.last?.id ?? cursor
            moreReplies = page.count == 30 && replyCursor != cursor
        } catch { if request == token, accepts(), !Task.isCancelled { repliesError = NativeClientSession.explain(error) } }
        if request == token { loadingReplies = false }
    }
}

struct NativeThreadDetail: View {
    let id: String
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @StateObject private var model = NativeThreadModel()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let note = model.note {
                if note.isHidden != true {
                    if note.replyId != nil { Section("これまでの会話") {
                        if model.moreParents { Button("さらに前の会話") { Task { await previous() } }.disabled(model.loadingParents) }
                        ForEach(model.parents.reversed()) { parent in NativeNoteRow(note: parent, session: session, open: open) }
                        if model.loadingParents { ProgressView() }
                        if let error = model.parentsError { ClientErrorRow(message: error) { Task { await previous() } } }
                    } }
                }
                Section { NativeNoteRow(note: note, session: session, open: open) }
                if note.isHidden != true {
                    Section("返信") {
                        ForEach(model.replies) { reply in NativeNoteRow(note: reply, session: session, open: open) }
                        if model.loadingReplies { ProgressView() }
                        if let error = model.repliesError { ClientErrorRow(message: error) { Task { await following() } } }
                        if model.moreReplies { Button("返信をもっと見る") { Task { await following() } }.disabled(model.loadingReplies).accessibilityIdentifier("native-more-replies") }
                        if !model.loadingReplies, model.replies.isEmpty, model.repliesError == nil { Text("返信はありません").foregroundStyle(.secondary) }
                    }
                    if let owner = session.accountID, owner == note.user.id {
                        Section { NativeNoteDeleteControl(noteID: note.id, owner: owner, session: session, deleted: {
                            model.clear(); session.refreshContent(); dismiss()
                        }, unavailable: { model.unavailable() }) }
                    }
                }
            } else if let error = model.error { ClientErrorRow(message: error) { Task { await load() } } }
            else { ProgressView() }
        }.listStyle(.plain).navigationTitle("ノート").navigationBarTitleDisplayMode(.inline)
            .task(id: session.revision) { await load() }.refreshable { await load() }
            .onReceive(session.$postedNote) { note in if let note, session.active { model.receivePosted(note) } }
            .onDisappear { model.clear() }
    }
    private func load() async {
        let generation = session.revision
        await model.load(id, api: session.api, accepts: { session.accepts(generation) })
    }
    private func previous() async {
        let generation = session.revision
        await model.loadParents(api: session.api, accepts: { session.accepts(generation) })
    }
    private func following() async {
        let generation = session.revision
        await model.loadReplies(api: session.api, accepts: { session.accepts(generation) })
    }
}
