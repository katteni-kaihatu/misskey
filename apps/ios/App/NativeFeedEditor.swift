// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativeChannelAPI: Sendable {
    func channels(query: String, until: String?) async throws -> [ClientChannel]
    func peerChannels(query: String, before: String?) async throws -> ClientPeerChannelPage
}
extension NativeChannelAPI {
    func peerChannels(query: String, before: String?) async throws -> ClientPeerChannelPage { throw ClientAPIError.notAuthenticated }
}

@MainActor
final class NativeChannelBrowserModel: ObservableObject {
    @Published private(set) var channels: [ClientChannel] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private var requestID = UUID()
    private var cursor: String?
    @Published private(set) var peerChannels: [ClientPeerChannelChoice] = []
    @Published private(set) var peerLoading = false
    @Published private(set) var peerError: String?
    @Published private(set) var peerNeedsLogin = false
    @Published private(set) var peerHasMore = false
    private var peerCursor: String?
    private var peerOrigin: String?
    private var peerRequestID = UUID()
    private var searchID = UUID()
    private func clearPeer() { peerRequestID = UUID(); peerChannels = []; peerCursor = nil; peerOrigin = nil; peerLoading = false; peerError = nil; peerHasMore = false; peerNeedsLogin = false }
    func clear() { searchID = UUID(); clearPeer(); requestID = UUID(); channels = []; cursor = nil; loading = false; error = nil; hasMore = false }
    func load(query: String, reset: Bool, includePeer: Bool = false, api: any NativeChannelAPI, accepts: () -> Bool) async {
        guard accepts(), !Task.isCancelled else { return }
        if reset { searchID = UUID(); clearPeer() }
        let search = searchID
        await loadLocal(query: query, reset: reset, api: api, accepts: accepts)
        guard search == searchID, accepts(), !Task.isCancelled else { return }
        if includePeer { await loadPeer(query: query, reset: reset, api: api, accepts: accepts) }
    }
    func loadPeer(query: String, reset: Bool, api: any NativeChannelAPI, accepts: () -> Bool) async {
        guard accepts(), !Task.isCancelled, !peerLoading, reset || (peerHasMore && peerError == nil) else { return }
        let request = UUID(); peerRequestID = request; peerLoading = true; peerError = nil
        defer { if request == peerRequestID { peerLoading = false } }
        do {
            let page = try await api.peerChannels(query: query, before: reset ? nil : peerCursor)
            guard request == peerRequestID, accepts(), !Task.isCancelled else { return }
            let origin = try ServerOrigin(page.origin).url.absoluteString
            guard reset || (origin == peerOrigin && (page.next == nil || page.next != peerCursor)) else { throw ClientAPIError.invalidResponse }
            let previous = reset ? [] : peerChannels
            var seen = Set(previous.map(\.id))
            peerChannels = previous + page.channels.map { ClientPeerChannelChoice(origin: origin, channel: $0) }.filter { seen.insert($0.id).inserted }
            peerCursor = page.next; peerHasMore = page.next != nil; peerOrigin = origin; peerNeedsLogin = false
        } catch {
            guard request == peerRequestID, accepts(), !Task.isCancelled else { return }
            peerChannels = []; peerCursor = nil; peerHasMore = false
            peerNeedsLogin = error as? ClientAPIError == .notAuthenticated
            if case ClientAPIError.rejected(let status, let code) = error { peerNeedsLogin = status == 401 || (status == 403 && code == "PERMISSION_DENIED") }
            peerError = peerNeedsLogin ? "れぞらぶのチャンネルを取得するには、連携先の読取権限でログインを更新してください。" : "連携先のチャンネルを取得できませんでした。"
        }
    }
    private func loadLocal(query: String, reset: Bool, api: any NativeChannelAPI, accepts: () -> Bool) async {
        guard accepts(), !Task.isCancelled, reset || (!loading && hasMore) else { return }
        let request = UUID(); requestID = request; loading = true; error = nil
        if reset { channels = []; cursor = nil; hasMore = false }
        defer { if requestID == request { loading = false } }
        do {
            let page = try await api.channels(query: query, until: cursor)
            guard requestID == request, accepts(), !Task.isCancelled else { return }
            let last = page.last?.id
            hasMore = page.count >= 30 && last != cursor
            cursor = last
            var seen = Set(channels.map(\.id))
            channels += page.filter { seen.insert($0.id).inserted }
        } catch {
            guard requestID == request, accepts(), !Task.isCancelled else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            self.error = NativeClientSession.explain(error)
        }
    }
}

struct NativeFeedEditor: View {
    @ObservedObject var preferences: NativeFeedPreferences
    @ObservedObject var session: NativeClientSession
    let added: (ClientFeedTab) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var addingChannel = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(preferences.tabs) { tab in
                        Label(tab.title, systemImage: tab.isChannel ? "number" : "house")
                            .accessibilityIdentifier("native-feed-editor:" + tab.id)
                    }
                    .onDelete { offsets in var values = preferences.tabs; values.remove(atOffsets: offsets); preferences.replace(values) }
                    .onMove { source, target in var values = preferences.tabs; values.move(fromOffsets: source, toOffset: target); preferences.replace(values) }
                } header: { Text("表示するタブ") } footer: { Text("右のハンドルで並べ替えられます。設定はこの端末のアカウントごとに保存します。最大20個まで追加できます。") }
                Section("追加") {
                    ForEach(ClientTimeline.allCases.filter { session.signedIn || $0 != .home }) { kind in
                        let tab = ClientFeedTab.timeline(kind)
                        Button { if preferences.add(tab) { added(tab) } } label: { Label(tab.title, systemImage: "plus.circle") }
                            .disabled(preferences.tabs.contains { $0.id == tab.id } || preferences.tabs.count >= 20)
                            .accessibilityIdentifier("native-feed-add:" + tab.id)
                    }
                    Button { addingChannel = true } label: { Label("チャンネルを追加", systemImage: "number") }
                        .disabled(preferences.tabs.count >= 20).accessibilityIdentifier("native-feed-add-channel")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("タブを編集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.accessibilityIdentifier("native-feed-editor-done") } }
        }
        .sheet(isPresented: $addingChannel) {
            NavigationStack { NativeChannelBrowser(session: session, preferences: preferences, added: added) }
        }
    }
}

private struct NativeChannelBrowser: View {
    @ObservedObject var session: NativeClientSession
    @ObservedObject var preferences: NativeFeedPreferences
    let added: (ClientFeedTab) -> Void
    @StateObject private var model = NativeChannelBrowserModel()
    @State private var query = ""
    @State private var source = "all"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("チャンネル名・説明で検索", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .accessibilityIdentifier("native-channel-search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("検索をクリア")
                }
            }.padding(11).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal).padding(.vertical, 8)
            Picker("表示元", selection: $source) {
                Text("すべて").tag("all"); Text("ぐりすぺ").tag("local"); Text("連携先").tag("peer")
            }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8).accessibilityIdentifier("native-channel-source")
            List {
                if source != "local", let error = model.peerError {
                    ClientErrorRow(message: error) { Task { let generation = session.revision; await model.loadPeer(query: query, reset: true, api: session.api, accepts: { session.accepts(generation) }) } }
                    if model.peerNeedsLogin { Button("ログインを更新") { Task { await session.signIn() } }.accessibilityIdentifier("native-peer-channel-login") }
                }
                if source == "peer" && !session.signedIn {
                    Text("連携先のチャンネルはログインすると表示できます。")
                    Button("ログイン") { Task { await session.signIn() } }
                }
                if source != "peer" {
                    ForEach(model.channels) { channel in
                        let exists = preferences.tabs.contains { $0.id == "channel:" + channel.id }
                        Button {
                            let tab = ClientFeedTab.channel(id: channel.id, name: channel.name)
                            if preferences.add(tab) { added(tab); dismiss() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(channel.name).font(.headline).foregroundStyle(.primary)
                                    if channel.isSensitive == true { Text("センシティブなチャンネル").font(.caption).foregroundStyle(.secondary) }
                                    else if let description = channel.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    if channel.isArchived == true { Text("アーカイブ済み").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(); Image(systemName: exists ? "checkmark.circle.fill" : "plus.circle")
                            }.contentShape(Rectangle())
                        }.disabled(exists || channel.isArchived == true || preferences.tabs.count >= 20)
                            .accessibilityIdentifier("native-channel-add:" + channel.id)
                    }
                }
                if source != "local" {
                    ForEach(model.peerChannels) { choice in
                        let exists = preferences.tabs.contains { $0.id == choice.id }
                        Button {
                            if preferences.add(choice.tab) { added(choice.tab); dismiss() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(choice.channel.name).font(.headline).foregroundStyle(.primary)
                                    Text((try? ServerOrigin(choice.origin).authority) ?? choice.origin).font(.caption).foregroundStyle(.secondary)
                                    if choice.channel.isSensitive == true { Text("センシティブなチャンネル").font(.caption).foregroundStyle(.secondary) }
                                    else if let text = choice.channel.description { Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                }
                                Spacer(); Image(systemName: exists ? "checkmark.circle.fill" : "plus.circle")
                            }
                        }.disabled(exists || choice.channel.isArchived == true || preferences.tabs.count >= 20)
                            .accessibilityIdentifier("native-peer-channel-add:" + choice.channel.id)
                    }
                }
                if model.peerLoading { ProgressView("連携先のチャンネルを検索中") }
                if let error = model.error { ClientErrorRow(message: error) { Task { await load(reset: true) } } }
                if model.loading { ProgressView("チャンネルを検索中") }
                if !model.loading && !model.peerLoading && model.error == nil && model.peerError == nil && (source == "peer" || model.channels.isEmpty) && (source == "local" || model.peerChannels.isEmpty) && (source != "peer" || session.signedIn) { Text("チャンネルが見つかりません").foregroundStyle(.secondary) }
                if model.hasMore || model.peerHasMore { Button("もっと見る") { Task { await load(reset: false) } }.disabled(model.loading || model.peerLoading).accessibilityIdentifier("native-channel-more") }
            }
        }
        .environment(\.editMode, .constant(.inactive))
        .navigationTitle("チャンネルを追加").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        .task(id: query + session.revision.uuidString) {
            model.clear()
            do { try await Task.sleep(nanoseconds: 300_000_000); try Task.checkCancellation(); await load(reset: true) } catch {}
        }
        .onDisappear { model.clear() }
    }
    private func load(reset: Bool) async {
        let generation = session.revision
        await model.load(query: query, reset: reset, includePeer: session.signedIn, api: session.api, accepts: { session.accepts(generation) })
    }
}

private extension ClientFeedTab {
    var isChannel: Bool { switch self { case .channel, .peerChannel: return true; case .timeline: return false } }
}
