// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import AuthenticationServices
import GridSpaceCore
import Security
import SwiftUI
import UIKit

@MainActor
final class NativeClientSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    let origin: ServerOrigin
    let emojiCatalog = NativeEmojiCatalog()
    let visuals = NativeVisualMemory()
    private let emojiAPI: NativeAPI
    private(set) var api: NativeAPI
    @Published private(set) var postedNote: ClientNote?
    @Published private(set) var user: ClientUser?
    @Published private(set) var accountID: String?
    @Published private(set) var revision = UUID() { didSet { postedNote = nil; timelines.clear(); reactions.clear(); visuals.clear(); liveReactions.clear() } }
    private let timelines = NativeTimelineStore()
    private let reactions = NativeReactionStore()
    private let liveReactions = NativeLiveReactions()
    @Published private(set) var active = true
    @Published private(set) var authenticating = false
    @Published private(set) var signedIn = false
    @Published var message: String?
    private var authentication: ASWebAuthenticationSession?
    private weak var presentationWindow: UIWindow?
    private var desiredVisible = true

    init(origin: ServerOrigin) {
        self.origin = origin
        emojiAPI = NativeAPI(origin: origin)
        let token = AppSession.isTesting ? nil : try? NativeTokenStore.read(origin: origin)
        api = NativeAPI(origin: origin, token: token)
        signedIn = token != nil
        super.init()
    }

    func accepts(_ generation: UUID) -> Bool { active && generation == revision }
    func timelineModel(_ id: String) -> NativeTimelineModel { timelines.model(id) }
    func retainTimelines(_ ids: Set<String>) { timelines.retain(ids) }
    func reactionModel(_ id: String) -> NativeReactionModel { reactions.model(id) }
    func loadEmojiCatalog() async { await emojiCatalog.load(origin: origin, api: emojiAPI) }
    func refreshContent() { revision = UUID(); startLiveReactions() }
    /// A confirmed write is a local content change, not a new security/session
    /// generation. Keep timeline positions, media and pending reactions intact.
    func didPost(_ note: ClientNote, generation: UUID) {
        guard accepts(generation), signedIn, note.user.id == accountID, note.isHidden != true else { return }
        postedNote = note
        if let target = note.replyId ?? note.renoteId, let model = reactions.existing(target) {
            let api = api
            Task { await model.refreshAfterPost(id: target, api: api, accepts: { self.accepts(generation) }) }
        }
    }
    private func startLiveReactions() {
        guard active, !authenticating else { return }
        let generation = revision
        liveReactions.start(api: api, accepts: { [weak self] in self?.accepts(generation) == true },
            catalogChanged: { [weak self] in
                guard let self, self.accepts(generation) else { return }
                Task { await self.emojiCatalog.load(origin: self.origin, api: self.emojiAPI, force: true) }
            }, expired: { [weak self] in
                Task { [weak self] in
                    guard let self else { return }
                    _ = await self.invalidateIfUnauthorized(ClientAPIError.rejected(status: 401, code: "STREAM_AUTHENTICATION_FAILED"), generation: generation)
                }
            })
    }
    func observeReactions(_ id: String, model: NativeReactionModel) -> UUID? {
        guard active, !authenticating else { return nil }
        startLiveReactions(); return liveReactions.observe(id, model: model)
    }
    func stopObservingReactions(_ id: String, token: UUID) { liveReactions.remove(id, token: token) }
    deinit { let live = liveReactions; Task { @MainActor in live.clear() } }

    func restore() async {
        defer { startLiveReactions() }
        Task { await loadEmojiCatalog() }
        #if DEBUG
        if !signedIn, AppSession.isTesting, ProcessInfo.processInfo.arguments.contains("--native-client-fixture"),
           LocalParityServer.current?.origin == origin || (NativeComposerFixture.enabled && origin == NativeComposerFixture.origin),
           let raw = (NativeComposerFixture.enabled && origin == NativeComposerFixture.origin ? NativeComposerFixture.session : ProcessInfo.processInfo.environment["GRIDSPACE_PARITY_NATIVE_MIAUTH_SESSION"]), let id = UUID(uuidString: raw) {
            let generation = revision
            do {
                // The fixture supplies a one-time session ID, never a Web token.
                let (token, account) = try await api.checkMiAuth(id)
                guard accepts(generation) else { return }
                let previous = api
                api = NativeAPI(origin: origin, token: token)
                user = account; accountID = account.id; signedIn = true; revision = UUID()
                Task { await previous.cancelRequests() }
            } catch { if accepts(generation) { message = Self.explain(error) } }
            return
        }
        #endif
        guard active, signedIn else { return }
        let generation = revision
        do {
            let result = try await api.account()
            guard accepts(generation) else { return }
            user = result; accountID = result.id
        } catch {
            guard accepts(generation) else { return }
            if await invalidateIfUnauthorized(error, generation: generation) { return }
            message = Self.explain(error)
        }
    }

    func signIn() async {
        guard !authenticating, active else { return }
        authenticating = true
        defer { authenticating = false; authentication = nil; startLiveReactions() }
        let id = UUID(), generation = revision
        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                presentationWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first { $0.isKeyWindow }
                guard presentationWindow != nil else { continuation.resume(throwing: ClientAPIError.invalidResponse); return }
                let session = ASWebAuthenticationSession(url: MiAuthConfiguration.authorizationURL(origin: origin, session: id),
                                                         callbackURLScheme: MiAuthConfiguration.callbackScheme) { url, error in
                    if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: error ?? ClientAPIError.notAuthenticated) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                authentication = session
                if !session.start() { continuation.resume(throwing: ClientAPIError.invalidResponse) }
            }
            guard MiAuthConfiguration.acceptsCallback(callback, session: id), accepts(generation) else { return }
            let (token, account) = try await api.checkMiAuth(id)
            guard accepts(generation) else { return }
            if !AppSession.isTesting { try NativeTokenStore.write(token, origin: origin) }
            let previous = api
            api = NativeAPI(origin: origin, token: token)
            user = account; accountID = account.id; signedIn = true; revision = UUID(); message = nil
            Task { await previous.cancelRequests() }
        } catch {
            if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin { return }
            if accepts(generation) { message = Self.explain(error) }
        }
    }

    func signOut() async {
        authentication?.cancel()
        do { if !AppSession.isTesting { try NativeTokenStore.remove(origin: origin) } }
        catch { message = "保存したログイン情報を削除できませんでした。端末のロックを解除して再試行してください。" }
        let previous = api
        api = NativeAPI(origin: origin)
        active = false; revision = UUID(); user = nil; accountID = nil; signedIn = false
        let generation = revision
        await previous.cancelRequests()
        if revision == generation { active = desiredVisible; revision = UUID(); startLiveReactions() }
    }

    func invalidateIfUnauthorized(_ error: Error, generation: UUID) async -> Bool {
        guard accepts(generation), signedIn, case ClientAPIError.rejected(let status, _) = error, status == 401 else { return false }
        await signOut()
        message = "ログインの有効期限が切れました。もう一度ログインしてください。"
        return true
    }

    func visibility(_ visible: Bool, cancelAuthentication: Bool = false) async {
        guard desiredVisible != visible else { return }
        // The auth browser temporarily inactivates the app; its callback still
        // checks its own UUID and server-side one-time MiAuth session.
        if authenticating && !cancelAuthentication { return }
        if cancelAuthentication { authentication?.cancel() }
        desiredVisible = visible
        active = false; revision = UUID(); user = nil
        let generation = revision
        await api.cancelRequests()
        guard revision == generation, desiredVisible == visible else { return }
        if visible { active = true; revision = UUID(); await restore() }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationWindow ?? ASPresentationAnchor()
    }

    static func explain(_ error: Error) -> String {
        #if DEBUG
        if AppSession.isTesting, LocalParityServer.current != nil, error is URLError {
            return "通信エラー（隔離試験コード: \((error as NSError).code)）"
        }
        #endif
        if let error = error as? ClientAPIError {
            switch error {
            case .notAuthenticated: return "ログインしてください。"
            case .keychain: return "ログイン情報を安全に保存できませんでした。端末のロックを解除して再試行してください。"
            case .rejected(let status, let code):
                if status == 401 { return "ログインの有効期限が切れました。もう一度ログインしてください。" }
                if code == "LTL_DISABLED" || code == "GTL_DISABLED" { return "このタイムラインはサーバーで利用が制限されています。" }
                if code == "UNAVAILABLE" { return "この機能はサーバーで利用が制限されています。" }
                if status == 403 { return "この操作を行う権限がありません。" }
                if status == 429 { return "しばらく待ってから再試行してください。" }
                return "サーバーで処理できませんでした（HTTP \(status)）。"
            default: return "サーバーからの応答を確認できませんでした。"
            }
        }
        return "通信できませんでした。接続を確認して再試行してください。"
    }
}

enum NativeTokenStore {
    private static func query(_ origin: ServerOrigin) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.gridspace.ios.miauth.v1",
         kSecAttrAccount as String: origin.url.absoluteString,
         kSecAttrSynchronizable as String: false]
    }
    static func read(origin: ServerOrigin) throws -> String? {
        var attributes = query(origin)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ClientAPIError.keychain(status) }
        guard let data = value as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { throw ClientAPIError.keychain(errSecDecode) }
        return token
    }
    static func write(_ token: String, origin: ServerOrigin) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(origin) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query(origin).merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw ClientAPIError.keychain(added) }
        } else if status != errSecSuccess { throw ClientAPIError.keychain(status) }
    }
    static func remove(origin: ServerOrigin) throws {
        let status = SecItemDelete(query(origin) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientAPIError.keychain(status) }
    }
}
