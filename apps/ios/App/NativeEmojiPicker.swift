// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import ImageIO

protocol NativeEmojiAPI: Sendable {
    func emojis() async throws -> [ClientCustomEmoji]
    func emoji(_ name: String) async throws -> ClientCustomEmoji
    func note(_ id: String) async throws -> ClientNote
    func account() async throws -> ClientUser
    func react(note: String, reaction: String, extended: Bool) async throws
    func removeReaction(note: String, reaction: String?, extended: Bool) async throws
    func reactionUsers(note: String, reaction: String, extended: Bool) async throws -> [ClientUser]
}

extension NativeEmojiAPI {
    func reactionUsers(note: String, reaction: String, extended: Bool) async throws -> [ClientUser] { [] }
}

struct NativeEmojiChoice: Identifiable {
    let value: String
    let custom: ClientCustomEmoji?
    enum Intent { case add, remove }
    var intent: Intent? = nil
    var id: String { value }
}

/// Public catalogs are shared; note/role previews remain sheet-local.
struct NativeEmojiPicker: View {
    @ObservedObject var session: NativeClientSession
    var noteID: String? = nil
    var currents: [String] = []
    let choose: (NativeEmojiChoice) -> Void
    var remove: ((String) -> Void)? = nil
    var expandSearch: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog: NativeEmojiCatalog
    private var custom: [ClientCustomEmoji] { catalog.items }
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var source = "recent"
    @State private var category = ""
    @State private var recent: [String] = []
    @State private var target: ClientNote?
    @State private var roles = Set<String>()
    @State private var error: String?
    @State private var showSensitive = false
    @State private var revision: UUID?
    init(session: NativeClientSession, noteID: String? = nil, currents: [String] = [], initialNote: ClientNote? = nil, choose: @escaping (NativeEmojiChoice) -> Void,
         remove: ((String) -> Void)? = nil, expandSearch: (() -> Void)? = nil) {
        self.session = session; self.noteID = noteID; self.currents = currents; self.choose = choose
        self.remove = remove; self.expandSearch = expandSearch; catalog = session.emojiCatalog
        _target = State(initialValue: initialNote?.id == noteID && initialNote?.isHidden != true ? initialNote : nil)
        _roles = State(initialValue: Set((session.user?.roles ?? []).map(\.id)))
        _revision = State(initialValue: session.revision)
    }
    private var preferences: UserDefaults {
        let scope = ProcessInfo.processInfo.environment["GRIDSPACE_COMPOSER_TEST_STORE"] ?? "unit"
        return AppSession.isTesting ? UserDefaults(suiteName: "gridspace-emoji-tests." + scope)! : .standard
    }
    private var recentKey: String {
        let scope = (try? JSONEncoder().encode([session.origin.url.absoluteString, session.accountID ?? "anonymous"])) ?? Data()
        return "native-emoji-recent:" + scope.base64EncodedString()
    }
    private var customResults: [ClientCustomEmoji] {
        let items = custom.filter { $0.matches(query) && (category.isEmpty || $0.category == category) && (showSensitive || $0.isSensitive != true) }
        return items
    }
    private var unicodeResults: [ClientUnicodeEmoji] {
        let items = ClientUnicodeEmoji.all.filter { $0.matches(query) && (category.isEmpty || String($0.category) == category) }
        return items
    }
    private var recentResults: [NativeEmojiChoice] { NativeEmojiRecents.choices(recent, custom: custom, query: query, showSensitive: showSensitive) }
    private var showEmpty: Bool {
        if source == "custom" { return catalog.ready && customResults.isEmpty }
        if source == "unicode" { return unicodeResults.isEmpty }
        return recentResults.isEmpty && (catalog.ready || (recent.isEmpty && query.isEmpty))
    }
    private func selected(_ value: String) -> Bool { currents.contains { ClientEmojiSearch.equivalent($0, value) } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Picker("絵文字の種類", selection: $source) {
                    Text("カスタム").tag("custom"); Text("標準").tag("unicode"); Text("最近").tag("recent")
                }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                if source != "recent" {
                    HStack {
                        Picker("カテゴリ", selection: $category) {
                            Text("すべてのカテゴリ").tag("")
                            if source == "custom" {
                                ForEach(Array(Set(custom.compactMap(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                            } else {
                                ForEach(ClientUnicodeEmoji.categories.indices, id: \.self) { index in Text(ClientUnicodeEmoji.categories[index]).tag(String(index)) }
                            }
                        }.accessibilityIdentifier("native-emoji-category")
                        Spacer()
                        if source == "custom" {
                            Toggle(isOn: $showSensitive) { Image(systemName: "eye.slash").accessibilityLabel("センシティブな絵文字を表示") }
                                .toggleStyle(.button).accessibilityIdentifier("native-emoji-sensitive")
                        }
                    }.font(.subheadline).padding(.horizontal).padding(.bottom, 8)
                }
                ScrollView {
                    if let error = error ?? (custom.isEmpty ? catalog.error : nil) {
                        ClientErrorRow(message: error) { Task { await load() } }.padding()
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 72), spacing: 8)], spacing: 10) {
                        if source == "recent" {
                            ForEach(recentResults) { choice in
                                if let emoji = choice.custom { customButton(emoji) }
                                else if let emoji = ClientUnicodeEmoji.all.first(where: { $0.char == choice.value }) { unicodeButton(emoji) }
                            }
                        }
                        if source == "custom" {
                            ForEach(customResults) { emoji in
                                customButton(emoji)
                            }
                        }
                        if source == "unicode" {
                            ForEach(unicodeResults) { emoji in
                                unicodeButton(emoji)
                            }
                        }
                    }.buttonStyle(.plain).padding(.horizontal)
                    if showEmpty {
                        Text(source == "recent" && query.isEmpty ? "選んだ絵文字がここに表示されます" : "該当する絵文字はありません").foregroundStyle(.secondary).padding()
                    }
                    if target?.acceptsOnlyLike == true {
                        Button("❤ いいね") { select(NativeEmojiChoice(value: "❤", custom: nil)) }.buttonStyle(.bordered).padding()
                    }
                    if source == "custom" { Text("センシティブな絵文字は表示を切り替えられます。鍵付きはこのノートへの利用を確認できない絵文字です。アニメーションは「視差効果を減らす」設定に従います。").font(.caption).foregroundStyle(.secondary).padding() }
                }.scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("絵文字").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                if !currents.isEmpty, let remove {
                    ToolbarItem(placement: .confirmationAction) {
                        if currents.count == 1 {
                            Button("解除") { guard valid else { return }; dismiss(); remove(currents[0]) }.accessibilityIdentifier("native-emoji-remove")
                        } else {
                            Menu("解除") {
                                ForEach(currents, id: \.self) { value in Button(value) { guard valid else { return }; dismiss(); remove(value) }.accessibilityIdentifier("native-emoji-remove:" + value) }
                            }.accessibilityIdentifier("native-emoji-remove")
                        }
                    }
                }
            }
        }.tint(ClientStyle.accent)
        .task { await load() }
        .onChange(of: source) { _ in category = "" }
        .onChange(of: searchFocused) { focused in if focused { expandSearch?() } }
        .onChange(of: session.revision) { _ in dismiss() }
        .onChange(of: session.active) { active in if !active { dismiss() } }
        .onDisappear { target = nil; roles = []; revision = nil }
    }
    private func customButton(_ emoji: ClientCustomEmoji) -> some View {
        let reason = target.flatMap { emoji.restriction(note: $0, roles: roles) }
        return Button { select(NativeEmojiChoice(value: emoji.shortcode, custom: emoji)) } label: {
            VStack(spacing: 3) {
                NativeEmojiImage(url: clientImageURL(emoji.url)).frame(width: 32, height: 32)
                Text(emoji.name).font(.system(size: 9)).lineLimit(1)
                if reason != nil { Image(systemName: "lock.fill").font(.system(size: 9)) }
            }.frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
        }.overlay(alignment: .topTrailing) { if selected(emoji.shortcode) { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(ClientStyle.accent).accessibilityHidden(true) } }
            .disabled((reason != nil && !selected(emoji.shortcode)) || (noteID != nil && target == nil))
            .accessibilityLabel(emoji.shortcode + (reason.map { "、" + $0 } ?? ""))
            .accessibilityIdentifier("native-emoji:" + emoji.name)
    }
    private func unicodeButton(_ emoji: ClientUnicodeEmoji) -> some View {
        Button { select(NativeEmojiChoice(value: emoji.char, custom: nil)) } label: {
            Text(emoji.char).font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
        }.overlay(alignment: .topTrailing) { if selected(emoji.char) { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(ClientStyle.accent).accessibilityHidden(true) } }
            .disabled(noteID != nil && (target == nil || (target?.acceptsOnlyLike == true && !ClientEmojiSearch.equivalent(emoji.char, "❤") && !selected(emoji.char))))
            .accessibilityLabel(emoji.char + "、" + (emoji.keywords.first ?? emoji.name)).accessibilityIdentifier("native-emoji:" + emoji.char)
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("絵文字名・別名で検索", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("絵文字名・別名で検索").accessibilityIdentifier("native-emoji-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .accessibilityLabel("検索をクリア")
            }
        }.padding(.leading, 12).padding(.trailing, query.isEmpty ? 12 : 0).frame(height: 44)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }
    private var valid: Bool { revision.map { session.accepts($0) } == true && !session.authenticating }
    private func select(_ choice: NativeEmojiChoice) {
        guard valid else { return }
        var choice = choice
        if let target {
            choice.intent = selected(choice.value) ? .remove : .add
            if choice.intent != .remove, let custom = choice.custom, custom.restriction(note: target, roles: roles) != nil { return }
        }
        recent.removeAll { ClientEmojiSearch.equivalent($0, choice.value) }; recent.insert(choice.value, at: 0)
        recent = Array(recent.prefix(32)); preferences.set(recent, forKey: recentKey)
        dismiss(); choose(choice)
    }
    private func load() async {
        let generation = session.revision
        revision = generation; error = nil
        recent = Array((preferences.stringArray(forKey: recentKey) ?? []).prefix(32))
        do {
            async let catalog: Void = session.loadEmojiCatalog()
            if let noteID {
                let note = try await session.api.note(noteID)
                let account = try await session.api.account()
                guard session.accepts(generation), !Task.isCancelled else { return }
                guard note.id == noteID, note.isHidden != true, !note.isPureRenote, account.id == session.accountID,
                      !note.supportsExtendedReactions || note.reactionStateComplete == true else { throw ClientAPIError.invalidResponse }
                target = note; roles = Set((account.roles ?? []).map(\.id))
            }
            await catalog
            guard session.accepts(generation), !Task.isCancelled else { return }
        } catch {
            guard session.accepts(generation), !Task.isCancelled else { return }
            if noteID != nil { target = nil; roles = [] }
            self.error = NativeClientSession.explain(error)
        }
    }
}

struct NativeEmojiImage: View {
    let url: URL?
    @State private var data: Data?
    @State private var loadedURL: URL?
    private var displayed: Data? { (loadedURL == url ? data : nil) ?? url.flatMap { NativeEmojiMemory.shared.data($0) } }
    var body: some View {
        ZStack {
            if let data = displayed { NativeAnimatedEmoji(data: data) }
            else { Image(systemName: "face.smiling").foregroundStyle(.secondary) }
        }.accessibilityHidden(true).task(id: url) {
            guard let url else { return }
            if let result = try? await NativeAssetCache.shared.data(for: url), !Task.isCancelled, NativeEmojiFrames(result) != nil {
                NativeEmojiMemory.shared.store(result, url: url); data = result; loadedURL = url
            }
        }
        .onDisappear { data = nil; loadedURL = nil }
    }
}

final class NativeEmojiTransport: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await evaluate(challenge)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await evaluate(challenge)
    }
    private func evaluate(_ challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        #if DEBUG
        if let fixture = LocalParityServer.current, fixture.handles(challenge.protectionSpace) {
            if let credential = await fixture.evaluatedCredential(for: challenge.protectionSpace) { return (.useCredential, credential) }
            return (.cancelAuthenticationChallenge, nil)
        }
        #endif
        return (.performDefaultHandling, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard clientImageURL(request.url?.absoluteString) != nil else { return nil }; return request
    }
}
