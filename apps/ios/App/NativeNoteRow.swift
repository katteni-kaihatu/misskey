// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

struct NativeNoteRow: View {
    let note: ClientNote
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @StateObject private var reaction: NativeReactionModel
    @State private var emojiPicker = false
    @State private var emojiDetent: PresentationDetent = .medium
    @State private var reactionWatch: UUID?
    private var displayed: ClientNote { reaction.note ?? note }
    init(note: ClientNote, session: NativeClientSession, open: @escaping (ClientRoute) -> Void) {
        self.note = note; self.session = session; self.open = open
        _reaction = StateObject(wrappedValue: session.reactionModel(note.id))
    }
    var body: some View {
        content
            .onAppear { watchReactions() }
            .onDisappear { stopWatchingReactions() }
            .onChange(of: session.revision) { _ in stopWatchingReactions(); watchReactions() }
            .onChange(of: reaction.note?.isHidden) { hidden in if hidden == true { stopWatchingReactions() } }
            .task(id: session.revision.uuidString + String(describing: ObjectIdentifier(note))) {
                guard !Task.isCancelled, session.active else { return }
                reaction.receive(note)
                // Feeds are hydrated in batches; notification envelopes may
                // still contain raw notes. Resolve them once when visible.
                if displayed.isHidden != true, !displayed.isPureRenote,
                   displayed.supportsExtendedReactions, displayed.reactionStateComplete == nil {
                    let generation = session.revision
                    await reaction.refresh(id: displayed.id, api: session.api, accepts: { session.accepts(generation) })
                }
            }
    }
    private func watchReactions() {
        guard reactionWatch == nil, displayed.isHidden != true else { return }
        reactionWatch = session.observeReactions(note.id, model: reaction)
    }
    private func stopWatchingReactions() {
        if let reactionWatch { session.stopObservingReactions(note.id, token: reactionWatch) }
        reactionWatch = nil
    }
    @ViewBuilder private var content: some View {
        if displayed.isHidden == true {
            Label("このノートは表示できません", systemImage: "lock").foregroundStyle(.secondary)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Button { open(.profile(displayed.user.id)) } label: { ClientAvatar(url: displayed.user.avatarUrl) }
                    .buttonStyle(.plain).accessibilityLabel(displayed.user.displayName + "のプロフィール")
                VStack(alignment: .leading, spacing: 4) {
                    authorHeader
                    NativeNoteBody(note: displayed, session: session, open: open)
                    quote
                    reactionChips
                    actions
                    if !displayed.isPureRenote, displayed.supportsExtendedReactions, displayed.reactionStateComplete == false, !reaction.busy {
                        Button("リアクションを再取得") {
                            let generation = session.revision
                            Task { await reaction.refresh(id: note.id, api: session.api, accepts: { session.accepts(generation) }) }
                        }.font(.caption)
                    }
                    if let error = reaction.error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("状態を再取得") {
                            let generation = session.revision
                            Task { await reaction.refresh(id: note.id, api: session.api, accepts: { session.accepts(generation) }) }
                        }.font(.caption)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12))
            .sheet(isPresented: $emojiPicker) {
                NativeEmojiPicker(session: session, noteID: displayed.id, currents: displayed.ownReactions, initialNote: displayed,
                    choose: { choice in react(choice) }, remove: { value in react(NativeEmojiChoice(value: value, custom: nil, intent: .remove)) },
                    expandSearch: { withAnimation(.easeInOut(duration: 0.22)) { emojiDetent = .large } })
                    .presentationDetents([.medium, .large], selection: $emojiDetent)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: reaction.requiresSignIn) { needed in
                if needed {
                    let generation = session.revision
                    Task { _ = await session.invalidateIfUnauthorized(ClientAPIError.rejected(status: 401, code: "AUTHENTICATION_FAILED"), generation: generation) }
                }
            }
            .onChange(of: session.revision) { _ in emojiPicker = false }
            .onDisappear { emojiPicker = false }

        }
    }
    @ViewBuilder private var authorHeader: some View {
    Button { open(.profile(displayed.user.id)) } label: {
        HStack(spacing: 4) {
            NativeUserName(user: displayed.user, session: session).layoutPriority(1)
            Text(displayed.user.handle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            if let date = displayed.date { Text("·").foregroundStyle(.secondary); Text(date, style: .relative).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 0)
            if displayed.visibility != "public" { Image(systemName: visibilitySymbol(displayed.visibility)).font(.caption2).foregroundStyle(.secondary) }
        }.contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(displayed.user.displayName + " " + displayed.user.handle).accessibilityIdentifier("native-note-author:" + displayed.user.id)
    }
    @ViewBuilder private var quote: some View {
    if let renote = displayed.renote {
        VStack(alignment: .leading, spacing: 6) {
            if renote.isHidden == true { Label("この引用は表示できません", systemImage: "lock").foregroundStyle(.secondary) }
            else {
                HStack(spacing: 4) { Image(systemName: "arrow.2.squarepath"); NativeUserName(user: renote.user, session: session, style: .caption1, bold: false, secondary: true) }.font(.caption).foregroundStyle(.secondary)
                NativeNoteBody(note: renote, session: session, open: open)
            }
        }.padding(10).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
    }
    @ViewBuilder private var reactionChips: some View {
    if let reactions = displayed.reactions, !reactions.isEmpty {
        NativeReactionFlow {
            ForEach(reactions.keys.sorted(), id: \.self) { value in
                NativeReactionChip(note: displayed, value: value, count: reactions[value] ?? 0, version: reaction.version,
                    session: session, disabled: reaction.unknown, toggle: { reactToExisting(value) }) { reactionLabel(value) }
            }
        }
    }
    }
    @ViewBuilder private var actions: some View {
    HStack(spacing: 0) {
        Button { open(.reply(displayed.id)) } label: { Label("\(displayed.repliesCount ?? 0)", systemImage: "bubble").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityLabel("返信").accessibilityIdentifier("native-note-reply:" + displayed.id)
        Spacer(minLength: 2)
        Button {
            if let target = displayed.reshareTarget, !target.reshareVisibilities(viewer: session.accountID ?? "").isEmpty { open(.renote(target.id)) }
            else { session.message = "この公開範囲のリノートはまだ対応していません。" }
        } label: { Label("\(displayed.renoteCount ?? 0)", systemImage: "arrow.2.squarepath").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityLabel("リノート・引用").accessibilityIdentifier("native-note-renote:" + displayed.id)
        Spacer(minLength: 2)
        Button {
            if displayed.isPureRenote, let target = displayed.reshareTarget { open(.note(target.id)) }
            else if session.signedIn { showEmojiPicker() }
            else { Task { await session.signIn() } }
        } label: { Image(systemName: displayed.ownReactions.isEmpty ? "face.smiling" : "face.smiling.fill").foregroundStyle(displayed.ownReactions.isEmpty ? Color.secondary : ClientStyle.accent).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
            .disabled(reaction.unknown).accessibilityLabel("リアクション").accessibilityIdentifier("native-note-reaction:" + displayed.id)
        Spacer(minLength: 2)
        Button { open(.note(displayed.id)) } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityLabel("ノートの詳細").accessibilityIdentifier("native-note-detail:" + displayed.id)
    }.font(.subheadline).foregroundStyle(.secondary).buttonStyle(.borderless)
    }
    @ViewBuilder private func reactionLabel(_ value: String) -> some View {
        if value.hasPrefix(":"), value.hasSuffix(":"), value.count > 2 {
            let key = String(value.dropFirst().dropLast())
            NativeEmojiImage(url: MFMLinks.emoji(origin: session.origin, name: key.replacingOccurrences(of: "@.", with: ""), authorHost: nil, urls: displayed.reactionEmojis ?? [:]))
                .frame(width: 22, height: 22)
        } else { Text(value).font(.system(size: 18)) }
    }
    private func showEmojiPicker() {
        emojiDetent = .medium
        emojiPicker = true
    }
    private func reactToExisting(_ value: String) {
        if displayed.hasOwnReaction(value) { react(NativeEmojiChoice(value: value, custom: nil, intent: .remove)); return }
        // A remote custom emoji cannot be sent as an arbitrary local shortcode.
        if value.hasPrefix(":"), ClientEmojiSearch.localName(value) == nil { showEmojiPicker() }
        else { react(NativeEmojiChoice(value: value, custom: nil, intent: .add)) }
    }
    private func react(_ choice: NativeEmojiChoice?) {
        guard let owner = session.accountID, session.active, !session.authenticating else { return }
        let generation = session.revision, snapshot = displayed
        Task { await reaction.apply(choice, to: snapshot, owner: owner, api: session.api, accepts: { session.accepts(generation) }) }
    }

    private func visibilitySymbol(_ value: String) -> String {
        switch value { case "public": return "globe"; case "home": return "house"; case "followers": return "lock"; default: return "envelope" }
    }
}
