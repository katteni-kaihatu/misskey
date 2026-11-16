// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UniformTypeIdentifiers

struct NativeComposerView: View {
    @ObservedObject var session: NativeClientSession
    let replyId: String?
    let renoteId: String?
    let openHistory: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var attachments = NativeAttachments(files: NativeAttachmentFiles(testing: AppSession.isTesting))
    @State private var picker: NativeAttachmentPickerKind?
    @State private var editingAttachment: NativeAttachmentDraft?
    @State private var draggedAttachment: UUID?
    @State private var emojiPicker = false
    @State private var emojiLease: UUID?
    @StateObject private var textState = NativeComposerTextState()
    @State private var retryAttachment: UUID?
    @State private var checkingFiles = false
    @State private var sendRequest: UUID?
    @State private var unreadableDraft = false
    @State private var text = ""
    @State private var cw = ""
    @State private var useCW = false
    @State private var visibility = "public"
    @State private var sending = false
    @State private var uncertain = false
    @State private var error: String?
    @State private var confirmsClose = false
    @State private var replyTarget: ClientNote?
    @State private var preparingReply = false
    @State private var draftOwner: String?
    @State private var confirmsRetry = false
    @State private var reshareApproval: UUID?
    @State private var editLease = UUID()
    private var drafts: NativeDraftStore { NativeDraftStore.current() }
    private var busy: Bool { sending || checkingFiles || attachments.busy }
    private var targetID: String? { replyId ?? renoteId }
    private var allowedVisibilities: [String] {
        if renoteId != nil { return replyTarget?.reshareVisibilities(viewer: session.accountID ?? "") ?? [] }
        if replyTarget?.visibility == "followers" { return ["followers"] }
        if replyTarget?.visibility == "home" { return ["home", "followers"] }
        return ["public", "home", "followers"]
    }
    private var maximumFileBytes: Int {
        let megabytes = session.user?.policies?.maxFileSizeMb ?? 30
        return megabytes > 0 && megabytes <= Int.max / (1024 * 1024) ? megabytes * 1024 * 1024 : 0
    }
    var body: some View {
        composerForm
            .safeAreaInset(edge: .top) {
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.bar)
                        .accessibilityIdentifier("native-compose-error")
                }
            }
            .sheet(isPresented: $emojiPicker) {
                NativeEmojiPicker(session: session) { choice in
                    guard emojiLease == editLease, session.active, session.user?.id == draftOwner, !busy, !uncertain else { return }
                    if let updated = textState.insert(choice.value, expectedText: text) { text = updated; saveDraft() }
                }
            }
            .sheet(item: $picker, onDismiss: { Task { await prepareReply() } }, content: pickerContent)
            .sheet(item: $editingAttachment) { entry in
                NativeAttachmentEditor(entry: attachments.binding(for: entry), editable: !busy && !uncertain && entry.driveID == nil && !entry.outcomeUnknown)
            }
            .alert("保存した下書きを読み込めません", isPresented: $unreadableDraft) {
                Button("閉じる", role: .cancel) { dismiss() }
                Button("記録を削除して新規作成", role: .destructive) {
                    if let id = draftOwner { drafts.remove(origin: session.origin, account: id, reply: replyId, renote: renoteId) }
                    error = nil
                }
            } message: { Text("記録は上書きせず保持しています。削除すると、この下書きと未送信の原本を復元できなくなります。") }
            .onChange(of: attachments.entries) { _ in saveDraft() }
            .onChange(of: session.active) { active in if !active {
                editLease = UUID(); emojiLease = nil; emojiPicker = false; textState.clear(); reshareApproval = nil; picker = nil; editingAttachment = nil; draggedAttachment = nil; attachments.cancel(); checkingFiles = false; sendRequest = nil; replyTarget = nil
                if sending { sending = false; uncertain = true; saveDraft() }
            } }
            .confirmationDialog("ドライブで未送信を確認しましたか？", isPresented: Binding(get: { retryAttachment != nil }, set: { if !$0 { retryAttachment = nil } }), titleVisibility: .visible) {
                Button("未送信を確認して再試行を許可") {
                    if let id = retryAttachment, let index = attachments.entries.firstIndex(where: { $0.id == id }) { attachments.entries[index].outcomeUnknown = false; saveDraft() }
                    retryAttachment = nil
                }
                Button("戻る", role: .cancel) { retryAttachment = nil }
            }
    }
    private var composerForm: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                ClientAvatar(url: session.user?.avatarUrl, size: 40)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        if let user = session.user { NativeUserName(user: user, session: session) }
                        Spacer(minLength: 8)
                        visibilityMenu.disabled(busy || uncertain)
                    }
                    if let target = replyTarget {
                        Text(target.user.handle + (renoteId == nil ? " への返信" : " を引用"))
                            .font(.subheadline).foregroundStyle(ClientStyle.accent)
                        if renoteId != nil {
                            Text(verbatim: target.cw ?? target.text ?? "添付・投票のあるノート")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            if target.localOnly == true { Label("連合なし", systemImage: "house").font(.caption) }
                        }
                    }
                    if preparingReply { ProgressView("対象のノートを確認中") }
                    if useCW {
                        HStack(alignment: .top) {
                            Image(systemName: "eye.slash").foregroundStyle(ClientStyle.accent).padding(.top, 12)
                            TextField("内容の警告", text: $cw, axis: .vertical)
                                .padding(.vertical, 10).accessibilityIdentifier("native-compose-cw").disabled(busy || uncertain)
                            Button { useCW = false } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("内容の警告を外す").padding(.top, 12).disabled(busy || uncertain)
                        }.font(.subheadline)
                        Divider()
                    }
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty { Text(replyId != nil ? "返信を書く" : "本文を入力")
                            .font(.system(size: 20)).foregroundStyle(.tertiary).padding(.top, 10).allowsHitTesting(false) }
                        NativeComposerText(text: $text, state: textState, minimumHeight: attachments.entries.isEmpty ? 150 : 44)
                            .frame(minHeight: attachments.entries.isEmpty ? 150 : 44).disabled(busy || uncertain)
                    }
                    if !attachments.entries.isEmpty { attachmentGallery }
                    attachmentStatus
                    if uncertain {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("投稿履歴を確認する", action: openHistory)
                            Button("未投稿であることを確認して編集を再開") { confirmsRetry = true }
                        }.font(.subheadline)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { composerTools }
        .background(Color(uiColor: .systemBackground))
        .disabled(sending || !session.active || unreadableDraft)
        .navigationTitle(renoteId != nil ? "リノート・引用" : replyId == nil ? "投稿" : "返信")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(busy || !text.isEmpty || !attachments.entries.isEmpty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("閉じる") { if text.isEmpty && attachments.entries.isEmpty { dismiss() } else { confirmsClose = true } }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button(sending || checkingFiles ? "送信中…" : "投稿") {
                textState.view?.resignFirstResponder()
                if renoteId != nil { reshareApproval = editLease }
                else { let lease = editLease; Task { await send(expectedLease: lease) } }
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(ClientStyle.accent)
                .disabled(busy || attachments.entries.contains(where: \.outcomeUnknown) || uncertain || preparingReply || (targetID != nil && replyTarget == nil) || (renoteId == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.entries.isEmpty) || !allowedVisibilities.contains(visibility) || !session.signedIn || session.user?.id == nil || session.user?.id != draftOwner).accessibilityIdentifier("native-compose-send") }
        }
        .task(id: session.revision) { await prepareReply() }
        .task(id: session.user?.id) { restoreDraft() }
        .onDisappear { editLease = UUID(); reshareApproval = nil; sendRequest = nil; replyTarget = nil; if picker == nil { attachments.cancel() } }
        .onChange(of: text) { _ in saveDraft() }
        .onChange(of: cw) { _ in saveDraft() }
        .onChange(of: useCW) { _ in saveDraft() }
        .onChange(of: visibility) { _ in saveDraft() }
        .onChange(of: uncertain) { _ in saveDraft() }
        .confirmationDialog("下書きの保存", isPresented: $confirmsClose, titleVisibility: .visible) {
            Button("保存して閉じる") { saveDraft(); dismiss() }
            Button("破棄して閉じる", role: .destructive) { removeDraft(); dismiss() }
            Button("編集を続ける", role: .cancel) {}
        }
        .confirmationDialog("同じ投稿が送信済みでないことを確認しましたか？", isPresented: $confirmsRetry, titleVisibility: .visible) {
            Button("未投稿を確認した") { uncertain = false; error = nil }
            Button("戻る", role: .cancel) {}
        }
        .confirmationDialog("この公開範囲でリノート・引用しますか？", isPresented: Binding(get: { reshareApproval != nil }, set: { if !$0 { reshareApproval = nil } }), titleVisibility: .visible) {
            if let lease = reshareApproval { Button("送信する") { reshareApproval = nil; Task { await send(expectedLease: lease) } } }
            Button("キャンセル", role: .cancel) {}
        }
    }
    private var visibilityMenu: some View {
        Menu {
            Picker("公開範囲", selection: $visibility) {
                if allowedVisibilities.contains("public") { Text("パブリック").tag("public") }
                if allowedVisibilities.contains("home") { Text("ホーム").tag("home") }
                if allowedVisibilities.contains("followers") { Text("フォロワー").tag("followers") }
            }
        } label: {
            Label(visibility == "public" ? "パブリック" : visibility == "home" ? "ホーム" : "フォロワー",
                  systemImage: visibility == "followers" ? "person.2" : visibility == "home" ? "house" : "globe.asia.australia")
                .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Capsule().stroke(ClientStyle.accent.opacity(0.4)))
        }.foregroundStyle(ClientStyle.accent).accessibilityIdentifier("native-compose-visibility")
    }

    private var composerTools: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Button { textState.view?.resignFirstResponder(); picker = .photos } label: { Image(systemName: "photo") }
                    .accessibilityLabel("写真・動画を選ぶ").accessibilityIdentifier("native-compose-photos")
                    .disabled(busy || uncertain || attachments.entries.count >= 16)
                Button {
                    if textState.prepareEmoji(expectedText: text) { emojiLease = editLease; emojiPicker = true }
                } label: { Image(systemName: "face.smiling") }
                    .accessibilityLabel("絵文字").accessibilityIdentifier("native-compose-emoji").disabled(busy || uncertain)
                Menu {
                    Button("ファイルを選ぶ", systemImage: "doc") { textState.view?.resignFirstResponder(); picker = .files }
                        .disabled(attachments.entries.count >= 16)
                    Button("ドライブから選ぶ", systemImage: "externaldrive") { textState.view?.resignFirstResponder(); picker = .drive }
                        .disabled(attachments.entries.count >= 16)
                    Toggle("内容の警告（CW）", isOn: $useCW).accessibilityIdentifier("native-compose-cw-enabled")
                    #if DEBUG
                    if AppSession.isTesting, LocalParityServer.current != nil {
                        Button("合成添付を選ぶ") { syntheticAttachment() }.accessibilityIdentifier("native-synthetic-attachment")
                    }
                    #endif
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("投稿のオプション").accessibilityIdentifier("native-add-attachment")
                    .disabled(busy || uncertain)
                Spacer()
                if !attachments.entries.isEmpty { Text("\(attachments.entries.count)/16").font(.caption).foregroundStyle(.secondary) }
                Text("\(text.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("本文\(text.count)文字").padding(.leading, 8)
            }.font(.system(size: 22)).buttonStyle(ComposerToolButtonStyle())
                .foregroundStyle(ClientStyle.accent).padding(.horizontal, 12).padding(.vertical, 6)
        }.background(.bar)
    }

    private var attachmentGallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments.entries) { entry in
                    NativeAttachmentCard(entry: entry, index: (attachments.entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1,
                        files: attachments.files, session: session, editable: !busy && !uncertain,
                        edit: { editingAttachment = entry }, remove: { attachments.remove(entry.id, persist: saveDraft) },
                        earlier: { moveAttachment(entry.id, by: -1) }, later: { moveAttachment(entry.id, by: 1) })
                        .onDrag {
                            guard !busy, !uncertain else { return NSItemProvider() }
                            draggedAttachment = entry.id
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: UTType.text.identifier, visibility: .ownProcess) { completion in
                                completion(Data(entry.id.uuidString.utf8), nil); return nil
                            }
                            return provider
                        }
                        .onDrop(of: [UTType.text], delegate: ComposerAttachmentDrop(target: entry.id, dragged: $draggedAttachment, move: reorderAttachment))
                }
            }.padding(.vertical, 2)
        }
    }
    @ViewBuilder private var attachmentStatus: some View {
        if let status = attachments.status {
            HStack(spacing: 8) { ProgressView(); Text(status).font(.caption); Spacer()
                Button("中止") { attachments.cancel(); saveDraft() }.font(.caption)
            }
        }
        if let error = attachments.error { Text(error).font(.caption).foregroundStyle(.red) }
        ForEach(attachments.entries.filter(\.outcomeUnknown)) { entry in
            Button("「\(entry.name)」のアップロード結果を確認した") { retryAttachment = entry.id }.font(.caption)
        }
    }
    private func reorderAttachment(_ source: UUID, _ target: UUID) {
        guard !busy, !uncertain, session.active, session.user?.id == draftOwner,
              let from = attachments.entries.firstIndex(where: { $0.id == source }),
              let to = attachments.entries.firstIndex(where: { $0.id == target }), from != to else { return }
        let moved = attachments.entries.remove(at: from); attachments.entries.insert(moved, at: to); saveDraft()
    }
    @ViewBuilder private func pickerContent(_ kind: NativeAttachmentPickerKind) -> some View {
        switch kind {
        case .photos:
            NativePhotoPicker(limit: 16 - attachments.entries.count) { providers in
                picker = nil
                guard session.active, session.user?.id == draftOwner else { return }
                if !providers.isEmpty { attachments.importPhotos(providers, maximum: maximumFileBytes, persist: saveDraft) }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        case .files:
            NativeFilePicker { urls in
                picker = nil
                guard session.active, session.user?.id == draftOwner else { return }
                if !urls.isEmpty { attachments.importURLs(urls, maximum: maximumFileBytes, persist: saveDraft) }
            }
        case .drive:
            NativeDrivePicker(session: session) { file in attachments.addDriveFile(file, persist: saveDraft) }
        }
    }
    private func moveAttachment(_ id: UUID, by offset: Int) {
        guard !busy, let index = attachments.entries.firstIndex(where: { $0.id == id }), attachments.entries.indices.contains(index + offset) else { return }
        attachments.entries.swapAt(index, index + offset); saveDraft()
    }
    #if DEBUG
    private func syntheticAttachment() {
        guard AppSession.isTesting, LocalParityServer.current != nil else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-native-attachment.txt")
        do {
            try Data("Synthetic native attachment bytes\n".utf8).write(to: url, options: [.atomic, .completeFileProtection])
            attachments.importURLs([url], maximum: maximumFileBytes, persist: saveDraft)
        } catch { attachments.error = NativeAttachments.explain(error) }
    }
    #endif
    private func restoreDraft() {
        guard draftOwner == nil, let id = session.user?.id else { return }
        draftOwner = id
        guard let draft = drafts.read(origin: session.origin, account: id, reply: replyId, renote: renoteId) else {
            if drafts.contains(origin: session.origin, account: id, reply: replyId, renote: renoteId) { unreadableDraft = true }
            return
        }
        text = draft.text; cw = draft.cw; useCW = draft.useCW; visibility = draft.visibility; uncertain = draft.outcomeUnknown
        if replyTarget != nil, !allowedVisibilities.contains(visibility) { visibility = allowedVisibilities.first ?? "followers" }
        attachments.entries = draft.attachments
        if uncertain { error = "前回の送信結果を確認してください。自動では再送しません。" }
    }
    private func saveDraft() {
        guard let id = draftOwner, !unreadableDraft else { return }
        if !drafts.write(NativeDraft(text: text, cw: cw, useCW: useCW, visibility: visibility, outcomeUnknown: uncertain || sending, attachments: attachments.entries), origin: session.origin, account: id, reply: replyId, renote: renoteId) { unreadableDraft = true }
    }
    private func removeDraft() {
        let ids = attachments.entries.map(\.id)
        attachments.cancel(); attachments.entries = []
        Task { await attachments.files.remove(ids) }
        if let id = draftOwner { drafts.remove(origin: session.origin, account: id, reply: replyId, renote: renoteId) }
        draftOwner = nil
    }
    private func prepareReply() async {
        replyTarget = nil
        guard let targetID, session.active else { return }
        let generation = session.revision
        let lease = editLease
        preparingReply = true
        do {
            let target = try await session.api.note(targetID)
            guard lease == editLease, session.accepts(generation), !Task.isCancelled else { return }
            guard target.id == targetID, target.isHidden != true,
                  renoteId != nil ? !target.reshareVisibilities(viewer: session.accountID ?? "").isEmpty : ["public", "home", "followers"].contains(target.visibility) else {
                error = "このノートへの操作はまだ対応していません。"; preparingReply = false; return
            }
            replyTarget = target
            if !allowedVisibilities.contains(visibility) { visibility = allowedVisibilities.first ?? "followers" }
        } catch { if lease == editLease, session.accepts(generation), !Task.isCancelled { self.error = NativeClientSession.explain(error) } }
        if lease == editLease, session.accepts(generation) { preparingReply = false }
    }
    private func send(expectedLease: UUID) async {
        guard expectedLease == editLease, !busy, !attachments.entries.contains(where: \.outcomeUnknown), !uncertain, !session.authenticating, session.signedIn, session.active,
              let owner = draftOwner, session.user?.id == owner, targetID == nil || replyTarget != nil else { return }
        error = nil
        let generation = session.revision
        let api = session.api
        let request = UUID(); sendRequest = request
        checkingFiles = true
        do {
            if let targetID {
                let fresh = try await api.note(targetID)
                guard sendRequest == request, session.accepts(generation) else { return }
                guard fresh.id == targetID, fresh.isHidden != true,
                      renoteId != nil ? fresh.reshareVisibilities(viewer: owner).contains(visibility) : ["public", "home", "followers"].contains(fresh.visibility),
                      fresh.visibility == replyTarget?.visibility, fresh.localOnly == replyTarget?.localOnly,
                      fresh.user.id == replyTarget?.user.id else {
                    replyTarget = nil; checkingFiles = false
                    error = "対象の公開範囲や状態が変わったため、送信を止めました。画面を開き直して確認してください。"; return
                }
                replyTarget = fresh
            }
            let uploaded = await attachments.uploadAndWait(using: api,
                accepts: { session.accepts(generation) && editLease == expectedLease && sendRequest == request && !unreadableDraft }, persist: saveDraft)
            guard sendRequest == request, expectedLease == editLease, session.accepts(generation) else { return }
            guard uploaded else { checkingFiles = false; return }
            for (index, entry) in attachments.entries.enumerated() {
                guard let id = entry.driveID else { checkingFiles = false; return }
                let file = try await api.ownFile(id, owner: owner)
                guard sendRequest == request, session.accepts(generation) else { return }
                if file.name != entry.name || (file.comment ?? "") != entry.comment || file.isSensitive != entry.sensitive {
                    attachments.entries[index].name = file.name; attachments.entries[index].comment = file.comment ?? ""
                    attachments.entries[index].sensitive = file.isSensitive
                    saveDraft(); checkingFiles = false
                    error = "ドライブ上の添付情報が変わったため、投稿を止めました。名前・説明・センシティブ指定を確認してください。"
                    return
                }
            }
            guard sendRequest == request else { return }
            guard session.accepts(generation), session.user?.id == owner else { checkingFiles = false; return }
        } catch {
            guard sendRequest == request else { return }
            checkingFiles = false; self.error = "対象のノートや添付の利用可否を確認できませんでした。公開範囲とログイン権限を確認してください。"; return
        }
        let ids = attachments.entries.compactMap(\.driveID)
        checkingFiles = false; sending = true; saveDraft()
        guard !unreadableDraft else { sending = false; return }
        do {
            let created = try await api.create(text: text, cw: useCW ? cw : nil, visibility: visibility, replyId: replyId, fileIDs: ids, renoteId: renoteId, localOnly: replyTarget?.localOnly == true)
            guard created.user.id == owner else { throw ClientAPIError.invalidResponse }
            guard sendRequest == request, expectedLease == editLease, session.accepts(generation) else { return }
            sending = false; removeDraft(); session.didPost(created, generation: generation); dismiss()
        } catch {
            guard sendRequest == request, expectedLease == editLease, session.accepts(generation) else { return }
            sending = false
            _ = await session.invalidateIfUnauthorized(error, generation: generation)
            if case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 { self.error = NativeClientSession.explain(error) }
            else {
                uncertain = true
                self.error = "送信結果を確認できませんでした。自動では再送しません。投稿履歴を確認してください。"
            }
            saveDraft()
        }
    }
}
