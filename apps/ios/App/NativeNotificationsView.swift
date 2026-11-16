// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

struct NativeNotificationsView: View {
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @StateObject private var model = NativeNotificationsModel()
    @State private var kind: ClientNotificationKind?
    @State private var confirmation: UUID?
    var body: some View {
        VStack(spacing: 0) {
            if session.signedIn { controls }
            List {
                if !session.signedIn {
                    VStack(spacing: 16) {
                        Image(systemName: "bell").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("あなたへのお知らせをここに").font(.headline)
                        Button("ログインして通知を見る") { Task { await session.signIn() } }
                    }.frame(maxWidth: .infinity).padding(.vertical, 64).listRowSeparator(.hidden)
                } else {
                    if model.statusError != nil || model.operationError != nil || model.notice != nil { status }
                    ForEach(model.items) { item in
                        NativeNotificationRow(item: item, session: session, open: open)
                            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                            .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.35))
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 57 }
                            .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
                    }
                    if let error = model.error { ClientErrorRow(message: error) { Task { if model.items.isEmpty { await load() } else { await more() } } } }
                    if model.loading { ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden) }
                    if model.more {
                        Button("通知をもっと見る") { Task { await more() } }
                            .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .disabled(model.loading || model.marking).accessibilityIdentifier("native-notification-more")
                    }
                    if !model.loading, model.items.isEmpty, model.error == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "bell").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                            Text(kind == nil ? "通知はまだありません" : "この種類の通知はありません").font(.headline)
                            Text("新しいお知らせが届くと、ここに表示されます。")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 64).listRowSeparator(.hidden)
                    }
                }
            }.listStyle(.plain)
                .refreshable { if !model.marking { await load() } }
        }
            .task(id: session.revision.uuidString + (kind?.rawValue ?? "all")) { await load() }
            .onDisappear { confirmation = nil; model.clear() }
            .onChange(of: session.active) { active in if !active { confirmation = nil; model.clear() } }
            .onChange(of: model.requiresSignIn) { needed in
                if needed {
                    let generation = session.revision
                    Task { _ = await session.invalidateIfUnauthorized(ClientAPIError.rejected(status: 401, code: "AUTHENTICATION_FAILED"), generation: generation) }
                }
            }
            .confirmationDialog("通知をすべて既読にしますか？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                if let lease = confirmation {
                    Button("すべて既読にする") {
                        confirmation = nil
                        let generation = session.revision
                        Task { await model.markAll(expectedLease: lease, api: session.api, accepts: { session.accepts(generation) }) }
                    }
                }
                Button("キャンセル", role: .cancel) { confirmation = nil }
            } message: { Text("このサーバーで受け取った通知すべてが対象です。絞り込みや表示済みのページに限定しません。") }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("通知の種類", selection: $kind) {
                    Text("すべて").tag(ClientNotificationKind?.none)
                    ForEach(ClientNotificationKind.allCases, id: \.self) { kind in Text(kind.title).tag(Optional(kind)) }
                }.pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(kind?.title ?? "すべて").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.tint(.primary).disabled(model.marking).accessibilityLabel("通知の種類、" + (kind?.title ?? "すべて"))
                .accessibilityIdentifier("native-notification-filter")
            if let count = model.unreadCount {
                Text(count > 0 ? "未読 \(count)" : "未読なし").lineLimit(1).fixedSize()
                    .font(.caption.weight(.medium)).foregroundStyle(count > 0 ? ClientStyle.accent : .secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(count > 0 ? ClientStyle.accent.opacity(0.09) : Color(uiColor: .secondarySystemBackground), in: Capsule())
                    .accessibilityLabel("このサーバーの未読 \(count)件").accessibilityIdentifier("native-notification-unread")
            } else if model.hasUnread == true {
                Circle().fill(ClientStyle.accent).frame(width: 7, height: 7).accessibilityLabel("未読通知あり")
            }
            Spacer(minLength: 0)
            if model.marking || model.refreshingStatus { ProgressView().controlSize(.small).accessibilityLabel("通知を確認中") }
            Button { confirmation = model.lease } label: {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("通知をすべて既読にする").accessibilityHint("開くだけでは既読になりません")
                .disabled(model.marking || model.markUnknown || model.loading || model.refreshingStatus || model.hasUnread != true || !session.active)
                .accessibilityIdentifier("native-notification-read-all")
            Menu {
                Button("未読状態を再取得", systemImage: "arrow.clockwise", action: refreshStatus)
                    .disabled(model.marking || model.refreshingStatus)
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("通知のメニュー").accessibilityIdentifier("native-notification-menu")
        }.padding(.horizontal, 12).frame(minHeight: 52).background(.bar).overlay(alignment: .bottom) { Divider() }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.statusError { Text(error) }
            if let error = model.operationError { Text(error) }
            if model.notice != nil, model.statusError == nil, model.operationError == nil {
                Text(model.hasUnread == false ? "すべて既読になりました。" : "未読の通知があります。")
            }
            if model.statusError != nil || model.markUnknown {
                Button("未読状態を再取得", action: refreshStatus).disabled(model.marking || model.refreshingStatus)
            }
        }.font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6)
    }
    private func refreshStatus() {
        let generation = session.revision
        Task { await model.refreshStatus(api: session.api, accepts: { session.accepts(generation) }) }
    }

    private func load() async {
        confirmation = nil; model.clear()
        guard let owner = session.accountID, session.active else { return }
        let generation = session.revision
        await model.load(owner: owner, kind: kind, api: session.api, accepts: { session.accepts(generation) })
    }
    private func more() async {
        let generation = session.revision
        await model.loadMore(api: session.api, accepts: { session.accepts(generation) })
    }
}

private struct NativeNotificationRow: View {
    let item: ClientNotification
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @ScaledMetric(relativeTo: .body) private var avatarSize = 42.0
    private var appearance: NativeNotificationAppearance { NativeNotificationAppearance(kind: item.kind) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if item.note?.isHidden != true {
                if let user = item.user, item.kind != .app {
                    Button { open(.profile(user.id)) } label: { avatar(user) }
                        .buttonStyle(.plain).accessibilityLabel(user.displayName + "のプロフィール")
                        .accessibilityIdentifier("native-notification-person:" + user.id)
                } else {
                    Image(systemName: appearance.symbol).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(appearance.color).frame(width: avatarSize, height: avatarSize)
                        .background(appearance.color.opacity(0.1), in: Circle()).accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let user = item.user, item.kind != .app, item.note?.isHidden != true {
                        Button { open(.profile(user.id)) } label: { NativeUserName(user: user, session: session) }.buttonStyle(.plain)
                    } else { Text(item.header ?? item.kind?.title ?? "お知らせ").font(.subheadline.weight(.semibold)).lineLimit(1) }
                    Spacer(minLength: 0)
                    if let date = item.date { Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated)).environment(\.locale, Locale(identifier: "ja_JP")).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                }
                if item.note?.isHidden == true {
                    Label("この通知のノートは表示できません", systemImage: "lock").font(.subheadline).foregroundStyle(.secondary)
                } else if let note = item.note {
                    Button { open(.note(note.id)) } label: {
                        let source = note.isPureRenote ? note.renote ?? note : note
                        preview(NativeNotificationAppearance.summary(note), user: source.user, emojis: source.emojis ?? [:])
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(appearance.action + (item.reaction.map { " " + $0 } ?? "") + "、" + NativeNotificationAppearance.summary(note))
                        .accessibilityIdentifier("native-notification-note:" + item.id)
                } else {
                    NavigationLink { NativeNotificationDetail(item: item, session: session, open: open) } label: {
                        preview(item.message ?? item.body ?? item.role?.name ?? item.invitation?.room.name ?? appearance.action, user: item.user, emojis: item.user?.emojis ?? [:])
                    }.buttonStyle(.plain).accessibilityIdentifier("native-notification-detail:" + item.id)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("native-notification-row:" + item.id)
    }
    private func preview(_ text: String, user: ClientUser?, emojis: [String: String]) -> some View {
        NativeUserName(name: text, host: user?.host, emojis: emojis, session: session, style: .subheadline, bold: false, secondary: true)
    }
    private func avatar(_ user: ClientUser) -> some View {
        ClientAvatar(url: user.avatarUrl, size: avatarSize)
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if item.kind == .reaction, let reaction = item.reaction {
                        if reaction.hasPrefix(":"), reaction.hasSuffix(":"), reaction.count > 2 {
                            let key = String(reaction.dropFirst().dropLast()).replacingOccurrences(of: "@.", with: "")
                            NativeEmojiImage(url: MFMLinks.emoji(origin: session.origin, name: key, authorHost: nil, urls: item.note?.reactionEmojis ?? [:]))
                                .frame(width: 22, height: 22)
                        } else { Text(verbatim: reaction).font(.system(size: 18)).frame(width: 22, height: 22) }
                    } else {
                        Image(systemName: appearance.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(appearance.color, in: Circle())
                    }
                }.padding(2).background(Color(uiColor: .systemBackground), in: Circle()).offset(x: 4, y: 3).accessibilityHidden(true)
            }.padding(.trailing, 3).padding(.bottom, 3)
    }
}

/// The Web notification layout uses a 42 pt avatar, a small event badge and a
/// plain, bounded note summary. Never expand CW content or fetch note attachments.
struct NativeNotificationAppearance {
    let kind: ClientNotificationKind?
    var symbol: String {
        switch kind {
        case .follow: return "plus"
        case .receiveFollowRequest: return "clock"
        case .followRequestAccepted: return "checkmark"
        case .renote: return "repeat"
        case .quote: return "quote.bubble.fill"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .mention: return "at"
        case .reaction: return "face.smiling"
        case .pollEnded: return "chart.bar.fill"
        case .scheduledNotePosted: return "paperplane.fill"
        case .scheduledNotePostFailed: return "exclamationmark"
        case .achievementEarned: return "medal.fill"
        case .roleAssigned: return "rosette"
        case .exportCompleted: return "archivebox.fill"
        case .login: return "arrow.right.to.line"
        case .createToken: return "key.fill"
        case .chatRoomInvitationReceived: return "bubble.left.and.bubble.right.fill"
        default: return "bell.fill"
        }
    }
    var color: Color {
        switch kind {
        case .follow, .receiveFollowRequest, .followRequestAccepted: return Color(red: 0.21, green: 0.68, blue: 0.82)
        case .renote, .quote: return Color(red: 0.21, green: 0.72, blue: 0.52)
        case .reply, .login: return .blue
        case .reaction, .achievementEarned: return .orange
        default: return Color(red: 0.48, green: 0.59, blue: 0.66)
        }
    }
    var action: String {
        switch kind {
        case .follow: return "フォローされました"
        case .receiveFollowRequest: return "フォロー申請が届きました"
        case .followRequestAccepted: return "フォロー申請が承認されました"
        case .reaction: return "リアクションされました"
        case .renote: return "リノートされました"
        case .quote: return "引用されました"
        case .reply: return "返信が届きました"
        case .mention: return "メンションされました"
        case nil: return "新しいお知らせが届きました"
        default: return kind?.title ?? "お知らせ"
        }
    }
    static func summary(_ note: ClientNote) -> String {
        let displayed = note.isPureRenote ? note.renote ?? note : note
        guard displayed.isHidden != true else { return "このノートは表示できません" }
        var text = displayed.cw ?? displayed.text ?? ""
        if !(displayed.files ?? []).isEmpty { text += " （添付 \(displayed.files?.count ?? 0)件）" }
        if displayed.poll != nil { text += " （投票）" }
        return text.isEmpty ? "ノートを見る" : text
    }
}

private struct NativeNotificationDetail: View {
    let item: ClientNotification
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    var body: some View {
        List {
            Text(item.header ?? item.kind?.title ?? "通知").font(.title3.bold())
            if let date = item.date { Text(date.formatted()).font(.caption).foregroundStyle(.secondary) }
            if let user = item.user { Button { open(.profile(user.id)) } label: { NativeUserName(user: user, session: session, style: .body, bold: false) } }
            if let body = item.body ?? item.message { NativeMFMText(text: body, origin: session.origin, authorHost: item.user?.host, emojis: item.user?.emojis ?? [:], openLink: { open(.link($0)) }) }
            if let role = item.role { Text(role.name) }
            if let room = item.invitation?.room { Text(room.name) }
            if let achievement = item.achievement { Text(achievement) }
            if let entity = item.exportedEntity { Text(entity) }
            if let note = item.note { NativeNoteRow(note: note, session: session, open: open) }
            if item.kind == nil { Text("この種類の通知は詳細表示にまだ対応していません。受信した通知は保持されます。").foregroundStyle(.secondary) }
        }.listStyle(.plain).navigationTitle("通知の詳細").navigationBarTitleDisplayMode(.inline)
    }
}
