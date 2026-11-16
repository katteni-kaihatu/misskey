// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import ImageIO

struct NativeClientView: View {
    @StateObject private var session: NativeClientSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var externalLink: URL?
    @State private var sheet: ClientSheet?
    @State private var selectedTab: ClientTab = .timeline
    @State private var timelineFeed = "local"
    @State private var timelineTopRequest: NativeTimelineScrollRequest?
    @State private var timelinePath: [ClientDestination] = []
    @State private var searchPath: [ClientDestination] = []
    @State private var notificationPath: [ClientDestination] = []
    @State private var profilePath: [ClientDestination] = []
    @State private var observedAccountID: String?
    init(origin: ServerOrigin) {
        _session = StateObject(wrappedValue: NativeClientSession(origin: origin))
    }

    var body: some View {
        lifecycleClient
            .environment(\.nativeVisualMemory, session.visuals)
            .environment(\.nativeVisualGeneration, session.revision)
            .confirmationDialog("外部リンクをブラウザで開きますか？", isPresented: Binding(get: { externalLink != nil }, set: { if !$0 { externalLink = nil } }), titleVisibility: .visible) {
                if let url = externalLink { Button("ブラウザで開く") { externalLink = nil; openURL(url) } }
                Button("キャンセル", role: .cancel) { externalLink = nil }
            } message: { Text(externalLink?.host ?? "") }
    }

    private var lifecycleClient: some View {
        clientTabs
            .disabled(session.authenticating)
            .overlay { authenticationCover }
            .sheet(item: $sheet, content: sheetContent)
            .task { await session.restore() }
            .onChange(of: session.accountID) { id in
                // Initial restoration identifies the current session. Treating
                // it as an account switch can close the first composer just
                // after the user opens it on a cold launch.
                let changedKnownAccount = observedAccountID != nil || id == nil
                observedAccountID = id
                if changedKnownAccount {
                    timelinePath = []; searchPath = []; notificationPath = []; profilePath = []; externalLink = nil; sheet = nil
                    timelineFeed = "local"; timelineTopRequest = nil
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active { externalLink = nil }
                Task { await session.visibility(phase == .active, cancelAuthentication: phase == .background) }
            }
            .alert("確認", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) {
                Button("閉じる", role: .cancel) { session.message = nil }
            } message: { Text(session.message ?? "") }
    }

    private var clientTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $timelinePath) {
                NativeTimelineView(session: session, kind: $timelineFeed, scrollRequest: timelineTopRequest,
                                   isActive: selectedTab == .timeline, open: open)
                    .navigationDestination(for: ClientDestination.self, destination: destination)
                    .navigationTitle("ぐりすぺ")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { commonToolbar }
                    .toolbar(.hidden, for: .tabBar)
            }.id("timeline:" + (session.accountID ?? "anonymous")).tabItem { Label("タイムライン", systemImage: "house") }.tag(ClientTab.timeline)
            NavigationStack(path: $searchPath) {
                NativeSearchView(session: session, open: open)
                    .navigationDestination(for: ClientDestination.self, destination: destination)
                    .navigationTitle("検索")
                    .toolbar { commonToolbar }
                    .toolbar(.hidden, for: .tabBar)
            }.id("search:" + (session.accountID ?? "anonymous")).tabItem { Label("検索", systemImage: "magnifyingglass") }.tag(ClientTab.search)
            NavigationStack(path: $notificationPath) {
                NativeNotificationsView(session: session, open: open)
                    .navigationDestination(for: ClientDestination.self, destination: destination)
                    .navigationTitle("通知")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { commonToolbar }
                    .toolbar(.hidden, for: .tabBar)
            }.id("notifications:" + (session.accountID ?? "anonymous")).tabItem { Label("通知", systemImage: "bell") }.tag(ClientTab.notifications)
            NavigationStack(path: $profilePath) {
                Group {
                    if let id = session.accountID { NativeProfileView(userID: id, session: session, open: open) }
                    else { VStack(spacing: 18) {
                        Image(systemName: "person.crop.circle").font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("ぐりすぺへようこそ").font(.title2.bold())
                        Button("ログイン") { Task { await session.signIn() } }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .navigationDestination(for: ClientDestination.self, destination: destination)
                .toolbar { commonToolbar }
                    .toolbar(.hidden, for: .tabBar)
            }.id("profile:" + (session.accountID ?? "anonymous")).tabItem { Label("プロフィール", systemImage: "person") }.tag(ClientTab.profile)
        }
        .tint(ClientStyle.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                clientTab(.timeline, title: "タイムライン", icon: "house", selectedIcon: "house.fill")
                clientTab(.search, title: "検索", icon: "magnifyingglass", selectedIcon: "magnifyingglass")
                clientTab(.notifications, title: "通知", icon: "bell", selectedIcon: "bell.fill")
                clientTab(.profile, title: "プロフィール", icon: "person.crop.circle", selectedIcon: "person.crop.circle.fill")
            }.padding(.top, 4).background(.bar).overlay(alignment: .top) { Divider() }
        }
        .overlay(alignment: .bottomTrailing) {
            if selectedTab == .timeline {
                Button {
                    if session.signedIn { sheet = .compose(nil, nil) } else { Task { await session.signIn() } }
                } label: {
                    Image(systemName: "plus").font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white).frame(width: 58, height: 58).background(ClientStyle.accent, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
                }.buttonStyle(.plain).padding(.trailing, 20).padding(.bottom, 76)
                    .accessibilityLabel("投稿を書く").accessibilityIdentifier("native-floating-compose")
                    .disabled(session.authenticating || (session.signedIn && session.user == nil))
            }
        }
    }

    private func clientTab(_ tab: ClientTab, title: String, icon: String, selectedIcon: String) -> some View {
        Button {
            if tab == .timeline {
                timelinePath = []
                timelineTopRequest = NativeTimelineScrollRequest(feedID: timelineFeed)
            }
            selectedTab = tab
        } label: {
            Image(systemName: selectedTab == tab ? selectedIcon : icon)
                .font(.system(size: 23, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            .accessibilityIdentifier("native-tab:" + title)
    }

    @ViewBuilder private var authenticationCover: some View {
        if session.authenticating {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                ProgressView("ログインを確認中")
            }
        }
    }

    @ViewBuilder private func sheetContent(_ destination: ClientSheet) -> some View {
            NavigationStack {
                switch destination {
                case .compose(let reply, let renote): NativeComposerView(session: session, replyId: reply, renoteId: renote, openHistory: {
                    if let id = session.accountID { sheet = .history(id) }
                })
                case .history(let id):
                    NativeProfileView(userID: id, session: session, open: { route in sheet = nil; open(route) })
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { sheet = nil } } }
                case .drive:
                    NativeDrivePicker(session: session, browsing: true, selected: { _ in })
                case .media(let file): NativeMediaView(file: file)
                }
            }
    }

    @ViewBuilder private func destination(_ target: ClientDestination) -> some View {
        switch target {
        case .profile(let id): NativeProfileView(userID: id, session: session, open: open)
        case .account(let username, let host): NativeAccountLookup(username: username, host: host, session: session, open: open)
        case .search(let query): NativeSearchView(session: session, initialQuery: query, open: open).navigationTitle("検索")
        case .note(let id): NativeNoteDetail(id: id, session: session, open: open)
        case .people(let id, let kind): NativePeopleView(userID: id, kind: kind, session: session, open: open)
        }
    }

    @ToolbarContentBuilder private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                if let user = session.user {
                    Text(user.handle)
                    Button("自分のプロフィール") { open(.profile(user.id)) }
                }
                if session.signedIn {
                    Button("別アカウントでログイン") { Task { await session.signIn() } }.disabled(session.authenticating)
                    Button("アプリからログアウト", role: .destructive) { Task { await session.signOut() } }
                } else {
                    Button("ログイン") { Task { await session.signIn() } }
                        .disabled(session.authenticating)
                }
                Divider()
                if session.signedIn { Button("ドライブ") { sheet = .drive } }
                Text(session.origin.authority)
            } label: {
                if let user = session.user { ClientAvatar(url: user.avatarUrl, size: 30) }
                else { Image(systemName: "person.crop.circle").foregroundStyle(.primary) }
            }
            .accessibilityLabel("アカウント")
        }
    }

    private func open(_ route: ClientRoute) {
        switch route {
        case .profile(let id): push(.profile(id))
        case .people(let id, let kind): push(.people(id, kind))
        case .note(let id): push(.note(id))
        case .media(let file): sheet = .media(file)
        case .drive: sheet = .drive
        case .link(let url):
            guard MFMLinks.external(url.absoluteString) != nil else { return }
            if session.origin.contains(url) {
                let parts = url.path.split(separator: "/").map(String.init)
                if parts.count == 2, parts[0] == "notes" { push(.note(parts[1])) }
                else if parts.count == 2, parts[0] == "users" { push(.profile(parts[1])) }
                else if parts.count == 1, parts[0].hasPrefix("@") {
                    let account = parts[0].dropFirst().split(separator: "@", omittingEmptySubsequences: false)
                    if account.count == 1, !account[0].isEmpty { push(.account(String(account[0]), nil)) }
                    else if account.count == 2, !account[0].isEmpty, !account[1].isEmpty { push(.account(String(account[0]), String(account[1]))) }
                }
                else if parts.count == 2, parts[0] == "tags" { push(.search("#" + parts[1])) }
                else if parts == ["my", "drive"] { sheet = .drive }
                else { session.message = "この画面はネイティブ版へ実装中です。" }
            } else { externalLink = url }
        case .reply(let id): if session.signedIn { sheet = .compose(id, nil) } else { Task { await session.signIn() } }
        case .renote(let id): if session.signedIn { sheet = .compose(nil, id) } else { Task { await session.signIn() } }
        }
    }

    private func push(_ target: ClientDestination) {
        switch selectedTab {
        case .timeline: timelinePath.append(target)
        case .search: searchPath.append(target)
        case .notifications: notificationPath.append(target)
        case .profile: profilePath.append(target)
        }
    }
}

private enum ClientSheet: Identifiable {
    case compose(String?, String?), history(String), drive, media(ClientFile)
    var id: String {
        switch self {
        case .compose(let reply, let renote): return "compose:" + (reply ?? "new") + ":" + (renote ?? "")
        case .history(let id): return "history:" + id
        case .drive: return "drive"
        case .media(let file): return "media:" + file.id
        }
    }
}
enum ClientRoute { case link(URL), reply(String), renote(String), profile(String), note(String), people(String, ClientPeopleKind), media(ClientFile), drive }
struct NativeTimelineScrollRequest: Equatable {
    let id = UUID()
    let feedID: String
}
private enum ClientDestination: Hashable { case profile(String), note(String), people(String, ClientPeopleKind), account(String, String?), search(String) }
private enum ClientTab: Hashable { case timeline, search, notifications, profile }

private struct NativeTimelineView: View {
    @ObservedObject var session: NativeClientSession
    @Binding var kind: String
    let scrollRequest: NativeTimelineScrollRequest?
    let isActive: Bool
    let open: (ClientRoute) -> Void
    @State private var editing = false
    @StateObject private var preferences = NativeFeedPreferences(store: .current())
    private var tabs: [ClientFeedTab] { preferences.visible(signedIn: session.signedIn) }
    private var selection: Binding<String> {
        Binding(get: { tabs.contains { $0.id == kind } ? kind : tabs[0].id }, set: { kind = $0 })
    }
    var body: some View {
        VStack(spacing: 0) {
            ClientFeedTabs(selection: selection, tabs: tabs) { editing = true }
            TabView(selection: selection) {
                ForEach(tabs) { feed in
                    Group {
                        if case .peerChannel(let origin, let id, _) = feed {
                            NativePeerChannelTimeline(session: session, channelID: id, peerOrigin: origin,
                                                      isSelected: isActive && selection.wrappedValue == feed.id, scrollRequest: scrollRequest)
                        } else {
                            NativeTimelinePage(session: session, model: session.timelineModel(feed.id), feed: feed, isSelected: isActive && selection.wrappedValue == feed.id,
                                               scrollRequest: scrollRequest, open: open)
                        }
                    }.tag(feed.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
        .task(id: session.accountID) { preferences.activate(origin: session.origin, account: session.accountID) }
        .task(id: tabs.map(\.id)) { session.retainTimelines(Set(tabs.map(\.id))) }
        .sheet(isPresented: $editing) {
            NativeFeedEditor(preferences: preferences, session: session) { feed in kind = feed.id }
        }
        .onChange(of: session.accountID) { _ in editing = false }
        .onChange(of: session.active) { active in if !active { editing = false } }
        .onChange(of: tabs.map(\.id)) { _ in
            if !tabs.contains(where: { $0.id == kind }) { kind = tabs[0].id }
        }
    }
}

private struct NativeTimelinePage: View {
    @ObservedObject var session: NativeClientSession
    @ObservedObject var model: NativeTimelineModel
    let feed: ClientFeedTab
    let isSelected: Bool
    let scrollRequest: NativeTimelineScrollRequest?
    let open: (ClientRoute) -> Void
    @State private var handledTopRequest: UUID?

    var body: some View {
        ScrollViewReader { proxy in
        List {
            NativeTimelinePosition(generation: session.revision) { model.setAtTop($0) }
                .frame(height: 1).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                .id("native-timeline-head").accessibilityHidden(true)
            if !session.signedIn {
                Button("ログインしてホームを読む") { Task { await session.signIn() } }
            }
            ForEach(model.notes) { note in
                NativeNoteRow(note: note, session: session, open: open)
                    .onAppear {
                        if isSelected && session.active {
                            session.visuals.prefetch(NativeVisualMemory.upcomingPreviews(after: note.id, in: model.notes))
                        }
                    }
            }
            if let error = model.error, model.retryResets || model.notes.isEmpty {
                ClientErrorRow(message: error) { Task { await load(reset: model.retryResets) } }
            }
            // Pull-to-refresh owns its spinner. Do not swap the pagination
            // footer for another spinner and change row height mid-gesture.
            if model.loading && model.notes.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            if !model.loading && model.error == nil && model.notes.isEmpty { Text("ノートはありません").foregroundStyle(.secondary) }
            if model.hasMore && !model.notes.isEmpty {
                NativeAutoLoadMore(cursor: session.revision.uuidString + feed.id + (model.notes.last?.id ?? ""),
                                   active: isSelected && session.active, loading: model.loading, failed: model.error != nil,
                                   failure: model.retryResets ? nil : model.error) {
                    await load(reset: false)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .accessibilityIdentifier("native-timeline")
        .overlay(alignment: .top) {
            if model.pendingCount > 0 {
                Button("\(model.pendingCount)件の新着") {
                    model.setAtTop(true); proxy.scrollTo("native-timeline-head", anchor: .top)
                }.buttonStyle(.borderedProminent).clipShape(Capsule()).padding(.top, 8)
                    .accessibilityIdentifier("native-timeline-new-notes")
            }
        }
        .onChange(of: model.topRevision) { _ in
            if isSelected && model.atTop { proxy.scrollTo("native-timeline-head", anchor: .top) }
        }
        .task(id: (scrollRequest?.id.uuidString ?? "") + String(isSelected)) {
            guard isSelected, session.active, let request = scrollRequest,
                  request.feedID == feed.id, handledTopRequest != request.id else { return }
            handledTopRequest = request.id
            model.setAtTop(true)
            proxy.scrollTo("native-timeline-head", anchor: .top)
        }
        .refreshable { await load(reset: true) }
        // UIKit can keep the adjacent page alive during a swipe. Hide its
        // accessibility tree until selected, including from VoiceOver.
        .accessibilityHidden(!isSelected)
        .task(id: session.revision.uuidString + feed.id + String(isSelected)) {
            guard isSelected, session.active, !Task.isCancelled else { return }
            let generation = session.revision
            model.activate(generation.uuidString + feed.id)
            if !model.initialized { await load(reset: true) }
            guard !Task.isCancelled, isSelected, session.accepts(generation) else { return }
            await model.listen(feed: feed, api: session.api, accepts: { session.accepts(generation) && isSelected })
            if model.requiresSignIn && session.accepts(generation) { await session.signOut() }
        }
        .onReceive(session.$postedNote) { note in
            if let note, let owner = session.accountID, session.active {
                model.receivePosted(note, feed: feed, owner: owner)
            }
        }
        .onDisappear { model.stopLive() }
        .onChange(of: isSelected) { selected in if !selected { model.stopLive() } }
        }
    }

    private func load(reset: Bool) async {
        let generation = session.revision
        // refreshable can retain the action created while this pager's
        // adjacent tab was inactive. Gate automatic pagination in its footer,
        // not with a captured selection value in this shared refresh action.
        await model.load(feed: feed, reset: reset, api: session.api, accepts: { session.accepts(generation) })
        if model.requiresSignIn, session.accepts(generation) {
            await session.signOut()
            session.message = "ログインの有効期限が切れました。もう一度ログインしてください。"
        }
    }
}


struct NativeNoteBody: View {
    let note: ClientNote
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cw = note.cw {
                Text(cw).font(.subheadline)
                Button(expanded ? "閉じる" : "内容を表示") { expanded.toggle() }.font(.caption)
            }
            if note.cw == nil || expanded {
                if let text = note.text, !text.isEmpty {
                    NativeMFMText(text: text, origin: session.origin, authorHost: note.user.host, emojis: note.emojis ?? [:],
                                  openLink: { open(.link($0)) })
                }
                ForEach(note.files ?? []) { file in NativeFilePreview(file: file, open: { open(.media(file)) }) }
                if let poll = note.poll {
                    NativePollView(noteID: note.id, poll: poll, session: session)
                }
            }
        }
    }
}

struct NativeFilePreview: View {
    let file: ClientFile
    let open: () -> Void
    @State private var revealed = false
    var body: some View {
        if file.isSensitive && !revealed {
            Button { revealed = true } label: { Label("センシティブな添付を表示", systemImage: "eye.slash") }
                .frame(maxWidth: .infinity).frame(height: file.type.hasPrefix("image/") ? 240 : 60)
        } else if file.type.hasPrefix("image/"), let url = clientImageURL(file.thumbnailUrl ?? file.url) {
            Button(action: open) {
                NativeRemoteImage(url: url, fill: false)
                    .frame(maxWidth: .infinity).frame(height: 240)
                    .background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel(file.name)
                .accessibilityIdentifier("native-file-preview:" + file.id)
        } else {
            Button(action: open) { Label(file.name, systemImage: file.type.hasPrefix("video/") ? "play.rectangle" : "doc") }
        }
    }
}

func clientImageURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil else { return nil }
    return url
}

struct ClientAvatar: View {
    let url: String?
    var size: CGFloat = 40
    var body: some View {
        NativeRemoteImage(url: clientImageURL(url), fill: true, placeholder: "person.fill", cacheArtwork: true)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

/// Public artwork opts into the bounded cache; note media stays transient.
struct NativeRemoteImage: View {
    let url: URL?
    let fill: Bool
    var placeholder: String = "photo"
    var cacheArtwork = false
    @Environment(\.nativeVisualMemory) private var visuals
    @Environment(\.nativeVisualGeneration) private var generation
    @State private var image: UIImage?
    @State private var loadedKey: String?
    private var pixels: Int { fill ? 160 : 1200 }
    private var memory: NativeVisualMemory? { cacheArtwork ? .artwork : visuals }
    private var key: String { (cacheArtwork ? "public" : generation.uuidString) + (url?.absoluteString ?? "") }
    private var displayed: UIImage? { (loadedKey == key ? image : nil) ?? url.flatMap { memory?.cached($0, pixels: pixels) } }
    var body: some View {
        ZStack {
            if let image = displayed {
                if fill { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(uiImage: image).resizable().scaledToFit() }
            } else {
                Image(systemName: placeholder).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: fill ? nil : 100, maxHeight: .infinity).background(.quaternary)
            }
        }.task(id: key) {
            let activeKey = key
            guard let url else { return }
            let value: UIImage?
            if let memory { value = await memory.image(url, pixels: pixels, artwork: cacheArtwork) }
            else { value = await NativeImageLoader.image(url, pixels: pixels, maximumBytes: 8 * 1024 * 1024, cached: cacheArtwork) }
            guard !Task.isCancelled else { return }
            image = value; loadedKey = activeKey
        }
        .onDisappear { image = nil; loadedKey = nil } // The bounded cache supplies the first returning frame.
    }
}

private typealias NativeNoteDetail = NativeThreadDetail

private struct NativeSearchView: View {
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @State private var query = ""
    @State private var results: [ClientNote] = []
    @State private var error: String?
    @State private var searching = false
    @State private var requestID = UUID()
    init(session: NativeClientSession, initialQuery: String = "", open: @escaping (ClientRoute) -> Void) {
        self.session = session; self.open = open; _query = State(initialValue: initialQuery)
    }
    var body: some View {
        List {
            if searching { ProgressView() }
            if let error { ClientErrorRow(message: error) { Task { await search() } } }
            ForEach(results) { note in NativeNoteRow(note: note, session: session, open: open) }
            if !query.isEmpty && !searching && results.isEmpty && error == nil { Text("検索語を入力して検索してください").foregroundStyle(.secondary) }
        }.listStyle(.plain).searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "ノートを検索")
            .onSubmit(of: .search) { Task { await search() } }
            .task { if !query.isEmpty { await search() } }
            .onChange(of: session.revision) { _ in requestID = UUID(); results = []; error = nil; searching = false }
            .onDisappear { requestID = UUID(); results = []; error = nil; searching = false }
    }
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, session.active else { return }
        let generation = session.revision, request = UUID()
        requestID = request; searching = true; error = nil
        do { let notes = try await session.api.search(text); if session.accepts(generation) && requestID == request { results = appendClientNotes(notes, to: []) } }
        catch { if session.accepts(generation) && requestID == request, !(await session.invalidateIfUnauthorized(error, generation: generation)) { self.error = NativeClientSession.explain(error) } }
        if requestID == request { searching = false }
    }
}

struct ClientErrorRow: View {
    let message: String
    let retry: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(message).foregroundStyle(.secondary); Button("再試行", action: retry) }.padding(.vertical, 8) }
}
