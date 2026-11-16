// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativePollAPI: Sendable {
    func note(_ id: String) async throws -> ClientNote
    func vote(_ id: String, choice: Int) async throws
}

@MainActor
final class NativePollModel: ObservableObject {
    @Published private(set) var poll: ClientPoll?
    @Published private(set) var busy = false
    @Published private(set) var unknown = false
    @Published private(set) var error: String?
    private var generation = UUID()
    var lease: UUID { generation }
    init(poll: ClientPoll) { self.poll = poll }
    func replace(_ value: ClientPoll) { if !busy { poll = value } }
    func clear() { generation = UUID(); poll = nil; busy = false; unknown = false; error = nil }
    func refresh(_ id: String, api: any NativePollAPI, lease: UUID? = nil, accepts: () -> Bool) async {
        guard !busy, poll != nil, lease == nil || lease == generation, accepts(), !Task.isCancelled else { return }
        let token = generation; busy = true
        do {
            let note = try await api.note(id)
            guard token == generation, accepts(), !Task.isCancelled else { return }
            guard note.id == id else { throw ClientAPIError.invalidResponse }
            poll = note.isHidden == true ? nil : note.poll
            unknown = false; error = poll == nil ? "この投票は表示できません。" : nil
        } catch { if token == generation, accepts(), !Task.isCancelled { self.error = NativeClientSession.explain(error) } }
        if token == generation { busy = false }
    }
    func vote(_ id: String, choice: Int, expectedText: String, api: any NativePollAPI, lease: UUID? = nil, accepts: () -> Bool) async {
        guard !busy, !unknown, poll != nil, lease == nil || lease == generation, accepts(), !Task.isCancelled else { return }
        let token = generation; busy = true; error = nil
        defer { if token == generation { busy = false } }
        do {
            let note = try await api.note(id)
            guard token == generation, accepts(), !Task.isCancelled else { return }
            guard note.id == id else { throw ClientAPIError.invalidResponse }
            guard note.isHidden != true, let current = note.poll else { poll = nil; error = "この投票は表示できません。"; return }
            poll = current
            guard current.canVote(choice, at: Date()), current.choices[choice].text == expectedText else { error = "投票の状態が変わりました。最新の状態を確認してください。"; return }
            do { try await api.vote(id, choice: choice) }
            catch {
                guard token == generation, accepts(), !Task.isCancelled else { return }
                unknown = true
                if case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 {
                    unknown = false
                    self.error = status == 403 ? "投票の権限を確認してください。アカウントメニューからログインし直すと投票権限を追加できます。" : NativeClientSession.explain(error)
                } else { self.error = "投票結果が不明です。再取得して確認してください。自動では再送しません。" }
            }
            guard token == generation, accepts(), !Task.isCancelled else { return }
            // Read the committed state; never increment a count optimistically
            // or POST again to resolve a lost response.
            let wasUnknown = unknown
            do {
                let updated = try await api.note(id)
                guard token == generation, accepts(), !Task.isCancelled else { return }
                guard updated.id == id else { throw ClientAPIError.invalidResponse }
                poll = updated.isHidden == true ? nil : updated.poll; unknown = false
                if poll == nil { error = "この投票は表示できません。" }
                else if wasUnknown { error = "最新の投票状態を再取得しました。表示を確認してください。" }
            } catch { if token == generation, accepts(), !Task.isCancelled { unknown = true; self.error = "投票の最新状態を確認できませんでした。再取得してください。" } }
        } catch { if token == generation, accepts(), !Task.isCancelled { self.error = NativeClientSession.explain(error) } }
    }
}

struct NativePollView: View {
    let noteID: String
    let initialPoll: ClientPoll
    @ObservedObject var session: NativeClientSession
    @StateObject private var model: NativePollModel
    @State private var selected: Int?
    @State private var showResults = false
    init(noteID: String, poll: ClientPoll, session: NativeClientSession) {
        self.noteID = noteID; initialPoll = poll; self.session = session
        _model = StateObject(wrappedValue: NativePollModel(poll: poll))
    }
    var body: some View {
        TimelineView(.periodic(from: Date(), by: initialPoll.expiresAt == nil ? 60 : 1)) { context in
            if let poll = model.poll { contents(poll, now: context.date) }
            else { Text(model.error ?? "この投票は表示できません。").font(.caption).foregroundStyle(.secondary) }
        }
        .onChange(of: initialPoll) { poll in model.replace(poll) }
        .onChange(of: session.active) { active in if !active { selected = nil; model.clear() } }
        .onDisappear { selected = nil; model.clear() }
        .onAppear { model.replace(initialPoll) }
        .confirmationDialog("この選択肢に投票しますか？", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
            if let choice = selected, let poll = model.poll, poll.choices.indices.contains(choice) {
                let name = poll.choices[choice].text
                Button("投票する") {
                    selected = nil
                    let generation = session.revision, lease = model.lease
                    Task { await model.vote(noteID, choice: choice, expectedText: name, api: session.api, lease: lease, accepts: { session.accepts(generation) }) }
                }
            }
            Button("キャンセル", role: .cancel) { selected = nil }
        } message: { Text(selected.flatMap { model.poll?.choices.indices.contains($0) == true ? model.poll?.choices[$0].text : nil } ?? "") }
    }
    private func contents(_ poll: ClientPoll, now: Date) -> some View {
        let results = showResults || poll.closed(at: now) || (!poll.multiple && poll.choices.contains { $0.isVoted == true })
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(poll.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    if session.signedIn { selected = index } else { Task { await session.signIn() } }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(verbatim: choice.text); Spacer(); if choice.isVoted == true { Image(systemName: "checkmark.circle.fill") }; if results { Text("\(choice.votes)票").font(.caption) } }
                        if results { ProgressView(value: min(1, Double(max(0, choice.votes)) / Double(max(1, poll.totalVotes)))).accessibilityHidden(true) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.borderless).disabled(model.busy || model.unknown || !session.active || !poll.canVote(index, at: now))
                    .accessibilityIdentifier("native-poll-choice-\(index)")
                    .accessibilityLabel(choice.text + (choice.isVoted == true ? "・投票済み" : "") + (results ? "・\(choice.votes)票" : ""))
            }
            Text("合計 \(poll.totalVotes)票" + (poll.multiple ? " · 複数回答可" : "")).font(.caption).foregroundStyle(.secondary)
            if poll.closed(at: now) { Text("投票終了").font(.caption) }
            else if let expiration = poll.expiration { Text("期限 \(expiration.formatted())").font(.caption).foregroundStyle(.secondary) }
            if !results { Button("結果を見る") { showResults = true }.font(.caption) }
            if model.busy { ProgressView("投票の状態を確認中") }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            Button("投票結果を更新") {
                let generation = session.revision, lease = model.lease
                Task { await model.refresh(noteID, api: session.api, lease: lease, accepts: { session.accepts(generation) }) }
            }.font(.caption).disabled(model.busy)
        }
    }
}
