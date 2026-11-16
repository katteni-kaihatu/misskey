// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativeNoteDeleteAPI: Sendable {
    func note(_ id: String) async throws -> ClientNote
    func deleteNote(_ id: String) async throws
}

@MainActor
final class NativeNoteDeleteModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var unknown = false
    @Published private(set) var deleted = false
    @Published private(set) var unavailable = false
    @Published private(set) var error: String?
    private(set) var lease = UUID()
    func clear() { lease = UUID(); busy = false; unknown = false; deleted = false; unavailable = false; error = nil }
    func delete(_ id: String, owner: String, expectedLease: UUID, api: any NativeNoteDeleteAPI, accepts: () -> Bool) async {
        guard lease == expectedLease, !busy, !unknown, !deleted, !unavailable, accepts(), !Task.isCancelled else { return }
        busy = true; error = nil
        defer { if lease == expectedLease { busy = false } }
        do {
            let fresh = try await api.note(id)
            guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
            guard fresh.id == id, fresh.user.id == owner, fresh.isHidden != true else { throw ClientAPIError.invalidResponse }
            do { try await api.deleteNote(id) }
            catch {
                guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
                if case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 {
                    self.error = NativeClientSession.explain(error)
                } else {
                    unknown = true; self.error = "削除結果が不明です。状態を再取得してください。自動では再送しません。"
                }
                return
            }
            guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
            deleted = true
        } catch {
            guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
            handleReadError(error)
        }
    }
    func refresh(_ id: String, owner: String, expectedLease: UUID, api: any NativeNoteDeleteAPI, accepts: () -> Bool) async {
        guard lease == expectedLease, !busy, !deleted, !unavailable, accepts(), !Task.isCancelled else { return }
        busy = true
        defer { if lease == expectedLease { busy = false } }
        do {
            let fresh = try await api.note(id)
            guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
            guard fresh.id == id, fresh.user.id == owner, fresh.isHidden != true else { throw ClientAPIError.invalidResponse }
            unknown = false; error = "ノートはまだ表示できます。削除する場合はもう一度確認してください。"
        } catch {
            guard lease == expectedLease, accepts(), !Task.isCancelled else { return }
            handleReadError(error)
        }
    }
    private func handleReadError(_ error: Error) {
        if case ClientAPIError.rejected(let status, let code) = error,
           [401, 403, 404].contains(status) || ["NO_SUCH_NOTE", "FORBIDDEN"].contains(code) {
            unavailable = true; unknown = false
            self.error = "このノートは削除済み、または表示できません。"
        } else { self.error = NativeClientSession.explain(error) }
    }
}

struct NativeNoteDeleteControl: View {
    let noteID: String
    let owner: String
    @ObservedObject var session: NativeClientSession
    let deleted: () -> Void
    let unavailable: () -> Void
    @StateObject private var model = NativeNoteDeleteModel()
    @State private var confirmation: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("このノートを削除", role: .destructive) { confirmation = model.lease }
                .disabled(model.busy || model.unknown || !session.active).accessibilityIdentifier("native-note-delete")
            if model.busy { ProgressView("ノートを確認中") }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if model.unknown {
                Button("削除後の状態を再取得") {
                    let lease = model.lease, generation = session.revision
                    Task { await model.refresh(noteID, owner: owner, expectedLease: lease, api: session.api, accepts: { session.accepts(generation) }) }
                }.disabled(model.busy)
            }
        }
        .confirmationDialog("このノートを削除しますか？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let lease = confirmation {
                Button("削除する", role: .destructive) {
                    confirmation = nil
                    let generation = session.revision
                    Task { await model.delete(noteID, owner: owner, expectedLease: lease, api: session.api, accepts: { session.accepts(generation) && session.accountID == owner }) }
                }
            }
            Button("キャンセル", role: .cancel) { confirmation = nil }
        } message: { Text("元に戻せません。リノートを削除する場合、元のノートは削除しません。") }
        .onChange(of: model.deleted) { value in if value { deleted() } }
        .onChange(of: model.unavailable) { value in if value { unavailable() } }
        .onChange(of: session.active) { active in if !active { confirmation = nil; model.clear() } }
        .onDisappear { confirmation = nil; model.clear() }
    }
}
