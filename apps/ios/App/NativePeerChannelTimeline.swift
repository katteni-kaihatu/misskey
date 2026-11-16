// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativePeerChannelAPI: Sendable {
    func peerChannelNotes(_ id: String, expectedOrigin: String, cursor: String?, validating: [String]?) async throws -> ClientPeerChannelNotePage
}

@MainActor
final class NativePeerChannelModel: ObservableObject {
    @Published private(set) var notes: [ClientPeerChannelNote] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var needsLogin = false
    @Published private(set) var hasMore = false
    @Published private(set) var headRevision = 0
    private(set) var generation: UUID?
    private(set) var cursor: String?
    private var requestID = UUID()
    func clear() { requestID = UUID(); notes = []; cursor = nil; loading = false; error = nil; hasMore = false; needsLogin = false; generation = nil }
    func activate(_ value: UUID) { guard generation != value else { return }; clear(); generation = value }
    func load(id: String, origin: String, reset: Bool, api: any NativePeerChannelAPI, accepts: () -> Bool) async {
        guard !loading, accepts(), !Task.isCancelled, reset || hasMore else { return }
        let request = UUID(); requestID = request; loading = true; error = nil
        if reset { notes = []; cursor = nil; hasMore = false }
        defer { if requestID == request { loading = false } }
        do {
            let previous = reset ? [] : try await validated(id: id, origin: origin, api: api)
            guard request == requestID, accepts(), !Task.isCancelled else { return }
            let page = try await api.peerChannelNotes(id, expectedOrigin: origin, cursor: cursor, validating: nil)
            guard request == requestID, accepts(), !Task.isCancelled else { return }
            guard page.cursor == nil || page.cursor != cursor else { throw ClientAPIError.invalidResponse }
            var seen = Set(previous.map(\.id))
            notes = previous + page.notes.filter { seen.insert($0.id).inserted }
            cursor = page.cursor; hasMore = cursor != nil; needsLogin = false
        } catch { if request == requestID, accepts(), !Task.isCancelled { fail(error) } }
    }
    func revalidate(id: String, origin: String, api: any NativePeerChannelAPI, accepts: () -> Bool) async {
        guard !loading, error == nil, accepts(), !Task.isCancelled else { return }
        if notes.isEmpty { await load(id: id, origin: origin, reset: true, api: api, accepts: accepts); return }
        let request = UUID(); requestID = request; loading = true
        defer { if requestID == request { loading = false } }
        do {
            let current = try await validated(id: id, origin: origin, api: api)
            guard request == requestID, accepts(), !Task.isCancelled else { return }
            notes = current
        } catch { if request == requestID, accepts(), !Task.isCancelled { fail(error) } }
    }
    func refreshHead(id: String, origin: String, api: any NativePeerChannelAPI, accepts: () -> Bool) async {
        guard !loading, error == nil, accepts(), !Task.isCancelled else { return }
        let request = UUID(); requestID = request; loading = true
        defer { if requestID == request { loading = false } }
        do {
            let page = try await api.peerChannelNotes(id, expectedOrigin: origin, cursor: nil, validating: nil)
            guard request == requestID, accepts(), !Task.isCancelled else { return }
            let old = Set(notes.map(\.id))
            if page.notes.isEmpty || !page.notes.contains(where: { old.contains($0.id) }) {
                notes = page.notes; cursor = page.cursor; hasMore = cursor != nil
                if !old.isEmpty || !notes.isEmpty { headRevision += 1 }
            } else {
                let fresh = page.notes.filter { !old.contains($0.id) }
                if !fresh.isEmpty { notes = fresh + notes; headRevision += 1 }
            }
        } catch { if request == requestID, accepts(), !Task.isCancelled { fail(error) } }
    }
    private func validated(id: String, origin: String, api: any NativePeerChannelAPI) async throws -> [ClientPeerChannelNote] {
        let snapshot = notes
        var allowed: [String: ClientPeerChannelNote] = [:]
        for offset in stride(from: 0, to: snapshot.count, by: 100) {
            try Task.checkCancellation()
            let ids = snapshot[offset..<min(snapshot.count, offset + 100)].map(\.id)
            let page = try await api.peerChannelNotes(id, expectedOrigin: origin, cursor: nil, validating: ids)
            guard page.notes.allSatisfy({ ids.contains($0.id) }) else { throw ClientAPIError.invalidResponse }
            for note in page.notes { allowed[note.id] = note }
        }
        return snapshot.compactMap { allowed[$0.id] }
    }
    private func fail(_ error: Error) {
        notes = []; cursor = nil; hasMore = false
        needsLogin = error as? ClientAPIError == .notAuthenticated
        if case ClientAPIError.rejected(let status, let code) = error { needsLogin = status == 401 || (status == 403 && code == "PERMISSION_DENIED") }
        self.error = needsLogin ? "連携先のチャンネルを読む権限でログインを更新してください。" : "連携先のチャンネルを読み込めませんでした。再試行してください。"
    }
}

struct NativePeerChannelTimeline: View {
    @ObservedObject var session: NativeClientSession
    let channelID: String
    let peerOrigin: String
    let isSelected: Bool
    let scrollRequest: NativeTimelineScrollRequest?
    @StateObject private var model = NativePeerChannelModel()
    @State private var atTop = true
    @State private var handledTopRequest: UUID?
    private var visible: Bool { isSelected && session.active && model.generation == session.revision }
    var body: some View {
        ScrollViewReader { proxy in
        List {
            if !session.signedIn {
                Button("ログインしてチャンネルを読む") { Task { await session.signIn() } }
            } else if visible {
                NativeTimelinePosition(generation: session.revision) { atTop = $0 }.frame(height: 1)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("native-peer-head").accessibilityHidden(true)
                ForEach(model.notes) { note in NativePeerChannelRow(note: note, session: session) }
                if let error = model.error {
                    ClientErrorRow(message: error) { Task { await load(reset: true) } }
                    if model.needsLogin { Button("ログインを更新") { Task { await session.signIn() } }.accessibilityIdentifier("native-peer-channel-login") }
                }
                if model.loading && model.notes.isEmpty { ProgressView("チャンネルを読み込み中") }
                if !model.loading && model.error == nil && model.notes.isEmpty { Text("ノートはありません").foregroundStyle(.secondary) }
                if model.hasMore {
                    NativeAutoLoadMore(cursor: session.revision.uuidString + (model.cursor ?? ""),
                                       active: visible, loading: model.loading, failed: model.error != nil) {
                        await load(reset: false)
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        // The horizontal pager extends below the custom navigation bar.
        // Keep the last row and pagination indicator above that overlay.
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 50) }
        .accessibilityIdentifier("native-peer-channel-timeline").accessibilityHidden(!isSelected)
        .refreshable { await load(reset: true) }
        .onChange(of: model.headRevision) { _ in if atTop { proxy.scrollTo("native-peer-head", anchor: .top) } }
        .task(id: (scrollRequest?.id.uuidString ?? "") + String(isSelected)) {
            let feed = ClientFeedTab.peerChannel(origin: peerOrigin, id: channelID, name: "")
            guard visible, let request = scrollRequest, request.feedID == feed.id,
                  handledTopRequest != request.id else { return }
            handledTopRequest = request.id; atTop = true
            proxy.scrollTo("native-peer-head", anchor: .top)
        }
        .task(id: session.revision.uuidString + String(isSelected)) {
            let generation = session.revision
            guard !Task.isCancelled, isSelected, session.accepts(generation), session.signedIn else { return }
            model.activate(generation)
            await load(reset: true)
            do {
                while !Task.isCancelled && session.accepts(generation) {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    try Task.checkCancellation()
                    await model.revalidate(id: channelID, origin: peerOrigin, api: session.api, accepts: { session.accepts(generation) })
                    if atTop {
                        await model.refreshHead(id: channelID, origin: peerOrigin, api: session.api, accepts: { session.accepts(generation) && isSelected && atTop })
                    }
                }
            } catch {}
        }
        .onChange(of: session.revision) { value in model.activate(value) }
        .onChange(of: session.active) { active in if !active { model.clear() } }
        .onChange(of: isSelected) { selected in if !selected { model.clear() } }
        .onDisappear { model.clear() }
        }
    }
    private func load(reset: Bool) async {
        let generation = session.revision
        guard isSelected, session.signedIn else { return }
        await model.load(id: channelID, origin: peerOrigin, reset: reset, api: session.api, accepts: { session.accepts(generation) })
    }
}

private struct NativePeerChannelRow: View {
    let note: ClientPeerChannelNote
    @ObservedObject var session: NativeClientSession
    @State private var expanded = false
    @State private var quoteExpanded = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ClientAvatar(url: note.author.avatarUrl)
            VStack(alignment: .leading, spacing: 6) {
                NativeUserName(name: note.author.name ?? note.author.username, host: note.author.host, emojis: note.author.emojis ?? [:], session: session)
                Text("@" + note.author.username + "@" + note.author.host).font(.caption).foregroundStyle(.secondary)
                if let cw = note.cw { Text(cw); Button(expanded ? "閉じる" : "内容を表示") { expanded.toggle() } }
                if note.cw == nil || expanded {
                    if let text = note.text { Text(verbatim: text).textSelection(.enabled) }
                    ForEach(note.files) { file in Label(file.name, systemImage: file.isSensitive ? "eye.slash" : "paperclip").font(.caption).foregroundStyle(.secondary) }
                    if let quote = note.renote {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) { Image(systemName: "arrow.2.squarepath"); NativeUserName(name: quote.author.name ?? quote.author.username, host: quote.author.host, emojis: quote.author.emojis ?? [:], session: session, style: .caption1, bold: false) }.font(.caption)
                            if let cw = quote.cw { Text(cw); Button(quoteExpanded ? "閉じる" : "引用を表示") { quoteExpanded.toggle() } }
                            if quote.cw == nil || quoteExpanded, let text = quote.text { Text(verbatim: text).textSelection(.enabled) }
                        }.padding(10).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .accessibilityIdentifier("native-peer-note:" + note.id)
        .onChange(of: note.cw) { _ in expanded = false }
        .onChange(of: note.renote?.cw) { _ in quoteExpanded = false }
    }
}
