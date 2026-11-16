// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

struct NativeProfileView: View {
    let userID: String
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @StateObject private var model = NativeProfileModel()
    @State private var filter: ClientProfileFilter = .posts
    @State private var action: ClientFollowAction?
    var body: some View {
        List {
            if let user = model.user {
                header(user)
                Section {
                    Picker("投稿の種類", selection: $filter) {
                        Text("投稿").tag(ClientProfileFilter.posts)
                        Text("返信を含む").tag(ClientProfileFilter.replies)
                        Text("メディア").tag(ClientProfileFilter.media)
                    }.pickerStyle(.segmented).disabled(model.mutating).accessibilityIdentifier("native-profile-filter")
                    ForEach(model.notes) { note in NativeNoteRow(note: note, session: session, open: open) }
                    if model.loadingNotes { ProgressView() }
                    if let error = model.notesError { ClientErrorRow(message: error) { Task { await more() } } }
                    if model.more { Button("投稿をもっと見る") { Task { await more() } }.disabled(model.loadingNotes).accessibilityIdentifier("native-profile-more") }
                    if model.notes.isEmpty, !model.loadingNotes, model.notesError == nil { Text("表示できる投稿はありません").foregroundStyle(.secondary) }
                }
            } else if let error = model.error { ClientErrorRow(message: error) { Task { await load() } } }
            else { ProgressView() }
        }.listStyle(.plain).navigationTitle("プロフィール").navigationBarTitleDisplayMode(.inline)
            .task(id: session.revision.uuidString + userID + filter.rawValue) { await load() }
            .refreshable { await load() }
            .onReceive(session.$postedNote) { note in if let note, session.active { model.receivePosted(note) } }
            .onDisappear { action = nil; model.clear() }
            .onChange(of: session.active) { active in if !active { action = nil; model.clear() } }
            .confirmationDialog(confirmTitle, isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                if let action, let viewer = session.accountID {
                    Button(actionTitle(action), role: action == .unfollow || action == .cancelRequest ? .destructive : nil) {
                        self.action = nil
                        let lease = model.lease, generation = session.revision
                        Task { await model.change(action, viewer: viewer, api: session.api, expectedLease: lease, accepts: { session.accepts(generation) }) }
                    }
                }
                Button("キャンセル", role: .cancel) { action = nil }
            } message: { Text(model.user?.handle ?? "") }
    }
    private var confirmTitle: String { action == .cancelRequest ? "申請を取り消しますか？" : action.map { actionTitle($0) + "しますか？" } ?? "確認" }
    private func actionTitle(_ action: ClientFollowAction) -> String {
        switch action { case .follow: return "フォロー"; case .request: return "フォロー申請"; case .unfollow: return "フォロー解除"; case .cancelRequest: return "申請を取り消す" }
    }
    @ViewBuilder private func header(_ user: ClientUser) -> some View {
        Section {
            if let url = clientImageURL(user.bannerUrl) { NativeRemoteImage(url: url, fill: true, cacheArtwork: true).frame(height: 140).clipped().accessibilityHidden(true) }
            HStack {
                ClientAvatar(url: user.avatarUrl)
                VStack(alignment: .leading) { NativeUserName(user: user, session: session, style: .title2); Text(user.handle).foregroundStyle(.secondary) }
            }
            if user.isLocked == true { Label("鍵アカウント", systemImage: "lock") }
            if user.isBot == true { Label("Bot", systemImage: "gearshape") }
            if user.movedTo != nil { Label("このアカウントは引っ越しています。", systemImage: "arrow.right") }
            if let description = user.description { mfm(description, user: user) }
            ForEach(Array((user.fields ?? []).enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 4) { Text(verbatim: field.name).font(.caption).foregroundStyle(.secondary); mfm(field.value, user: user) }
            }
            HStack {
                Button(user.followingCount.map { "\($0) フォロー中" } ?? "フォロー中") { open(.people(user.id, .following)) }
                    .accessibilityIdentifier("native-profile-following")
                Button(user.followersCount.map { "\($0) フォロワー" } ?? "フォロワー") { open(.people(user.id, .followers)) }
                    .accessibilityIdentifier("native-profile-followers")
            }.buttonStyle(.borderless)
            if user.isFollowed == true { Text("フォローされています").font(.caption).foregroundStyle(.secondary) }
            if let viewer = session.accountID, viewer != user.id {
                if let next = user.followAction(viewer: viewer) {
                    Button(user.isFollowing == true ? "フォロー中 · 解除" : user.hasPendingFollowRequestFromYou == true ? "申請中 · 取り消し" : actionTitle(next)) { action = next }
                        .disabled(model.mutating || model.uncertain || !session.active).accessibilityIdentifier("native-profile-follow-action")
                }
                Button("関係を再取得") {
                    let lease = model.lease, generation = session.revision
                    Task { await model.refreshRelationship(api: session.api, expectedLease: lease, accepts: { session.accepts(generation) }) }
                }.disabled(model.mutating).font(.caption)
            } else if !session.signedIn { Button("ログインしてフォロー") { Task { await session.signIn() } } }
            if model.mutating { ProgressView("関係を確認中") }
            if let error = model.relationshipError { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func mfm(_ text: String, user: ClientUser) -> some View {
        NativeMFMText(text: text, origin: session.origin, authorHost: user.host, emojis: user.emojis ?? [:], openLink: { open(.link($0)) })
    }
    private func load() async {
        action = nil
        let generation = session.revision
        await model.load(userID, filter: filter, api: session.api, accepts: { session.accepts(generation) })
    }
    private func more() async {
        let generation = session.revision
        await model.loadMore(api: session.api, accepts: { session.accepts(generation) })
    }
}

struct NativePeopleView: View {
    let userID: String
    let kind: ClientPeopleKind
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @StateObject private var model = NativePeopleModel()
    var body: some View {
        List {
            ForEach(model.entries) { entry in
                if let user = entry.person(owner: userID, kind: kind) {
                    Button { open(.profile(user.id)) } label: {
                        HStack { ClientAvatar(url: user.avatarUrl); VStack(alignment: .leading) { NativeUserName(user: user, session: session, style: .body, bold: false); Text(user.handle).font(.caption).foregroundStyle(.secondary) }; Spacer() }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("native-person:" + user.id)
                }
            }
            if model.loading { ProgressView() }
            if let error = model.error { ClientErrorRow(message: error) { Task { await load(reset: model.entries.isEmpty) } } }
            if model.more { Button("さらに読み込む") { Task { await load(reset: false) } }.disabled(model.loading).accessibilityIdentifier("native-people-more") }
            if !model.loading, model.entries.isEmpty, model.error == nil { Text("表示できるユーザーはいません").foregroundStyle(.secondary) }
        }.navigationTitle(kind == .following ? "フォロー中" : "フォロワー").navigationBarTitleDisplayMode(.inline)
            .task(id: session.revision) { await load(reset: true) }.refreshable { await load(reset: true) }
            .onDisappear { model.clear() }
            .onChange(of: session.active) { active in if !active { model.clear() } }
    }
    private func load(reset: Bool) async {
        let generation = session.revision
        await model.load(userID, kind: kind, reset: reset, api: session.api, accepts: { session.accepts(generation) })
    }
}
