// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import WebKit

/// First compatibility slice: retain the real Web client and its authentication.
/// Exposes negotiation and public invalidation; authentication stays in the Web client.
@MainActor
final class WebSessionController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    enum ResponsePolicy: Equatable { case allow, download, cancel, confirmExternal }
    let origin: ServerOrigin
    let webView: WKWebView
    private let policy: NavigationPolicy
    private let bridge: WebBridge?
    private let isPopup: Bool
    private var childrenByID: [ObjectIdentifier: WebSessionController] = [:]
    private var onClose: (() -> Void)?
    private var pendingDialogs: [UUID: () -> Void] = [:]
    private var navigationObservations: [NSKeyValueObservation] = []
    private let downloads = WebDownloads()
    let uploads = WebUploads()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let recovery = UIStackView()
    private let recoveryText = UILabel()
    private var backButton: UIBarButtonItem!
    private var forwardButton: UIBarButtonItem!
    private var isShutDown = false
    private weak var accountOwner: WebSessionController?
    private let initialURL: URL?
    private var committedDocument = 0
    private var accountChangeDocument: Int?
    private var accountDocumentResetScheduled = false
    private var hasServerRedirect = false
    private var hasPendingMainFrameNavigation = false
    private let rendererLifecycleKey: String
    private var rendererLifecycle: WebRendererLifecycle?
    var onAccountDocumentChange: ((URL, WKWebsiteDataStore) -> Void)?

    init(origin: ServerOrigin, configuration: WKWebViewConfiguration? = nil, isPopup: Bool = false,
         accountOwner: WebSessionController? = nil, initialURL: URL? = nil,
         websiteDataStore: WKWebsiteDataStore? = nil, rendererLifecycleKey: String? = nil) {
        self.origin = origin
        let controlKey = rendererLifecycleKey ?? (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        self.rendererLifecycleKey = controlKey
        self.initialURL = initialURL.flatMap { origin.contains($0) ? $0 : nil }
        policy = NavigationPolicy(origin: origin)
        self.isPopup = isPopup
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.websiteDataStore = AppSession.isTesting ? .nonPersistent() : .default()
            #if DEBUG
            if let server = LocalParityServer.current {
                config.websiteDataStore = server.dataStore()
                // Deterministic language in the isolated synthetic store only.
                let expectedOrigin = server.origin.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let script = "if (location.origin === '\(expectedOrigin)') localStorage.setItem('lang', 'ja-JP');"
                config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            #endif
            if let websiteDataStore { config.websiteDataStore = websiteDataStore }
            config.allowsInlineMediaPlayback = true
            // Do not impersonate Safari or override the web client's user agent.
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        if isPopup {
            // Preserve WebKit's supplied configuration/store/process pool and
            // opener relationship, but give each window its own handler/epoch.
            let content = WKUserContentController()
            config.userContentController.userScripts.forEach { content.addUserScript($0) }
            config.userContentController = content
        }
        let bridge = WebBridge(origin: origin)
        self.bridge = bridge
        do {
            config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: WebBridge.name)
            if !isPopup, let scriptURL = Bundle.main.url(forResource: "BridgeBootstrap", withExtension: "js"),
               let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
                let configured = source.replacingOccurrences(of: "__GRIDSPACE_RENDERER_LIFECYCLE_KEY__", with: controlKey)
                config.userContentController.addUserScript(WKUserScript(source: configured, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
        // Child windows MUST use WebKit's supplied configuration, including its store.
        webView = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        if AppSession.isTesting { webView.accessibilityIdentifier = "web-session-\(UUID().uuidString)" }
        #endif
        super.init(nibName: nil, bundle: nil)
        self.accountOwner = accountOwner ?? self
        bridge.webView = webView
        bridge.onSessionChanged = { [weak self, weak bridge] reason in
            self?.accountOwner?.invalidateAccountContext(except: bridge, reason: reason)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        downloads.presenter = self
        uploads.presenter = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(origin:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = origin.host
        let toolbar = UIToolbar()
        backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(goBack))
        backButton.accessibilityLabel = "戻る"
        forwardButton = UIBarButtonItem(image: UIImage(systemName: "chevron.forward"), style: .plain, target: self, action: #selector(goForward))
        forwardButton.accessibilityLabel = "進む"
        let reload = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(confirmReload))
        reload.accessibilityLabel = "再読み込み"
        toolbar.items = [backButton, .flexibleSpace(), forwardButton, .flexibleSpace(), UIBarButtonItem(customView: spinner), .flexibleSpace(), reload]
        for subview in [webView, toolbar] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        rendererLifecycle = WebRendererLifecycle(webView: webView, container: view, origin: origin, key: rendererLifecycleKey)
        setupRecoveryView()
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateNavigation() }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateNavigation() }
            },
        ]
        if isPopup {
            isModalInPresentation = true
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(confirmClose))
        } else {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--compatibility-fixture") {
                webView.loadHTMLString(CompatibilityTestPage.html, baseURL: origin.url)
            } else {
                webView.load(URLRequest(url: initialURL ?? LocalParityServer.current?.initialURL ?? origin.url))
            }
            #else
            webView.load(URLRequest(url: initialURL ?? origin.url))
            #endif
        }
        updateNavigation()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        uploads.cancelPending()
    }

    private func setupRecoveryView() {
        recovery.axis = .vertical
        recovery.spacing = 16
        recovery.alignment = .center
        recovery.isLayoutMarginsRelativeArrangement = true
        recovery.directionalLayoutMargins = .init(top: 24, leading: 24, bottom: 24, trailing: 24)
        recovery.backgroundColor = .systemBackground
        recoveryText.numberOfLines = 0
        recoveryText.textAlignment = .center
        recoveryText.font = .preferredFont(forTextStyle: .body)
        recoveryText.adjustsFontForContentSizeCategory = true
        let retry = UIButton(type: .system)
        retry.setTitle("再読み込み", for: .normal)
        retry.addTarget(self, action: #selector(confirmReload), for: .touchUpInside)
        recovery.addArrangedSubview(recoveryText)
        recovery.addArrangedSubview(retry)
        recovery.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recovery)
        NSLayoutConstraint.activate([
            recovery.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            recovery.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recovery.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        recovery.isHidden = true
    }

    @objc private func goBack() {
        guard accountChangeDocument == nil else { return }
        webView.goBack()
    }
    @objc private func goForward() {
        guard accountChangeDocument == nil else { return }
        webView.goForward()
    }

    @objc private func confirmReload() {
        let alert = UIAlertController(title: "現在のページを再読み込みしますか？", message: "編集中の内容や未送信の添付は失われる場合があります。移動に失敗した場合は移動前のページを開きます。送信結果が不明な投稿は、再送する前に確認してください。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "再読み込み", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.recovery.isHidden = true
            if self.webView.url == nil { self.webView.load(URLRequest(url: self.origin.url)) }
            else { self.webView.reload() }
        })
        presentIfPossible(alert)
    }

    @objc private func confirmClose() {
        let alert = UIAlertController(title: "この画面を閉じますか？", message: "編集中の内容や未送信の添付は失われる場合があります。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "閉じる", style: .destructive) { [weak self] _ in self?.closePopup() })
        presentIfPossible(alert)
    }

    private func updateNavigation() {
        let permitsHistory = accountChangeDocument == nil && !isShutDown
        backButton?.isEnabled = permitsHistory && webView.canGoBack
        forwardButton?.isEnabled = permitsHistory && webView.canGoForward
    }

    private func presentIfPossible(_ controller: UIViewController) {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
        present(controller, animated: true)
    }

    private func openExternal(_ url: URL, confirm: Bool) {
        guard confirm else {
            UIApplication.shared.open(url)
            return
        }
        // Only show the origin; authorization queries can contain secrets.
        let destination = url.host ?? url.scheme ?? "外部アプリ"
        let alert = UIAlertController(title: "外部リンクを開きますか？", message: destination, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "開く", style: .default) { _ in UIApplication.shared.open(url) })
        presentIfPossible(alert)
    }

    private func isPermittedDownload(_ url: URL) -> Bool {
        origin.contains(url) || origin.containsBlob(url)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if DEBUG
        if let server = LocalParityServer.current, server.handles(challenge.protectionSpace) {
            guard challenge.previousFailureCount == 0 else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                showLoadFailure(URLError(.serverCertificateUntrusted))
                return
            }
            Task { [weak self] in
                let credential = await server.evaluatedCredential(for: challenge.protectionSpace)
                guard let self, !isShutDown else { completionHandler(.cancelAuthenticationChallenge, nil); return }
                guard let credential else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    // Auth cancellation can be -999, unlike ordinary trust
                    // failures; surface it instead of leaving a blank page.
                    showLoadFailure(URLError(.serverCertificateUntrusted))
                    return
                }
                completionHandler(.useCredential, credential)
            }
            return
        }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard !isShutDown, let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload, isPermittedDownload(url) {
            if navigationAction.targetFrame?.isMainFrame == true { hasPendingMainFrameNavigation = false }
            decisionHandler(.download)
            return
        }
        let decision = actionPolicy(url: url, isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                                    isUserActivated: navigationAction.navigationType == .linkActivated)
        if accountChangeDocument != nil, accountOwner?.onAccountDocumentChange != nil,
           decision == .allow, origin.contains(url),
           navigationAction.targetFrame?.isMainFrame ?? true,
           navigationAction.request.httpMethod == "GET" {
            // The Web client writes credentials before starting this request.
            // Move it to a fresh view before the new PWA/UGC can execute twice.
            decisionHandler(.cancel)
            accountOwner?.replaceAccountDocument(destination: isPopup ? nil : url)
            return
        }
        switch decision {
        case .allow:
            if navigationAction.targetFrame?.isMainFrame == true { hasPendingMainFrameNavigation = true }
            decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        case .openExternal, .confirmExternal:
            decisionHandler(.cancel)
            openExternal(url, confirm: decision == .confirmExternal)
        }
    }

    func actionPolicy(url: URL, isMainFrame: Bool, isUserActivated: Bool) -> NavigationDecision {
        policy.decision(for: url, isMainFrame: isMainFrame, isUserActivated: isUserActivated && !hasServerRedirect && !hasPendingMainFrameNavigation)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let policy = responsePolicy(url: navigationResponse.response.url,
            isMainFrame: navigationResponse.isForMainFrame, canShowMIMEType: navigationResponse.canShowMIMEType)
        switch policy {
        case .allow: decisionHandler(.allow)
        case .download:
            if navigationResponse.isForMainFrame { hasPendingMainFrameNavigation = false }
            decisionHandler(.download)
        case .cancel: decisionHandler(.cancel)
        case .confirmExternal:
            decisionHandler(.cancel)
            if let url = navigationResponse.response.url { openExternal(url, confirm: true) }
        }
    }

    // Evaluate public response values; WebKit owns WKNavigationResponse's
    // internal state, so tests must not construct instances of that class.
    func responsePolicy(url: URL?, isMainFrame: Bool, canShowMIMEType: Bool) -> ResponsePolicy {
        guard !isShutDown, let url else { return .cancel }
        if !canShowMIMEType {
            return isPermittedDownload(url) ? .download : .cancel
        } else {
            // The final response can follow a server redirect. Apply the same
            // origin boundary before rendering, retaining external UGC frames.
            let decision = policy.decision(for: url, isMainFrame: isMainFrame, isUserActivated: false)
            switch decision {
            case .allow: return .allow
            case .cancel: return .cancel
            case .openExternal, .confirmExternal:
                return .confirmExternal
            }
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { downloads.attach(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { downloads.attach(download) }

    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        // File input is an explicit user-consent flow, including inputs inside
        // existing UGC/embedded frames. It grants no bridge or parent credentials.
        guard !isShutDown, ["https", "http"].contains(frame.securityOrigin.protocol),
              !frame.securityOrigin.host.isEmpty else {
            completionHandler(nil)
            return
        }
        uploads.begin(allowsMultiple: parameters.allowsMultipleSelection, allowsDirectories: parameters.allowsDirectories, sourceHost: frame.securityOrigin.host, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        rendererLifecycle?.navigationStarted()
        hasServerRedirect = false
        hasPendingMainFrameNavigation = true
        bridge?.rotate()
        uploads.cancelPending()
        recovery.isHidden = true
        spinner.startAnimating()
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        hasServerRedirect = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        committedDocument += 1
        rendererLifecycle?.documentCommitted()
        uploads.invalidate()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasServerRedirect = false
        hasPendingMainFrameNavigation = false
        spinner.stopAnimating()
        updateNavigation()
        if let changed = accountChangeDocument, committedDocument > changed {
            accountOwner?.replaceAccountDocument()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        hasServerRedirect = false
        hasPendingMainFrameNavigation = false
        showLoadFailure(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hasServerRedirect = false
        hasPendingMainFrameNavigation = false
        showLoadFailure(error)
    }

    private func showLoadFailure(_ error: Error) {
        spinner.stopAnimating()
        rendererLifecycle?.navigationFailed()
        if (error as NSError).code == NSURLErrorCancelled { return }
        #if DEBUG
        if LocalParityServer.current != nil {
            // Codes only: never log a request, URL query, headers or Web data.
            let failure = error as NSError
            NSLog("Local parity navigation failure: %@ %ld", failure.domain, failure.code)
            if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError {
                NSLog("Local parity underlying failure: %@ %ld", underlying.domain, underlying.code)
                if let code = underlying.userInfo["_kCFStreamErrorCodeKey"] as? Int {
                    NSLog("Local parity stream failure: %ld", code)
                }
            }
        }
        #endif
        recoveryText.text = "ページを読み込めませんでした。通信状態を確認してください。下の操作は現在のページを再読み込みします。編集中の内容を残すため、自動では再読み込みしません。"
        recovery.isHidden = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        rendererLifecycle?.processTerminated()
        hasServerRedirect = false
        hasPendingMainFrameNavigation = false
        bridge?.rotate()
        cancelDialogs()
        downloads.cancelAll()
        uploads.invalidate()
        spinner.stopAnimating()
        recoveryText.text = "Web画面の処理が終了しました。保存されていない編集や添付は復元できない場合があります。送信済みか不明な投稿は再送前に確認してください。"
        recovery.isHidden = false
        // Never silently reload or replay a submission after process loss.
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !isShutDown, presentedViewController == nil,
              let url = navigationAction.request.url,
              policy.decision(for: url, isMainFrame: true, isUserActivated: navigationAction.navigationType == .linkActivated) == .allow else { return nil }
        let child = WebSessionController(origin: origin, configuration: configuration, isPopup: true,
                                         accountOwner: accountOwner, rendererLifecycleKey: rendererLifecycleKey)
        let key = ObjectIdentifier(child.webView)
        childrenByID[key] = child
        child.onClose = { [weak self] in self?.childrenByID.removeValue(forKey: key) }
        let container = UINavigationController(rootViewController: child)
        container.modalPresentationStyle = .fullScreen
        present(container, animated: true)
        child.loadViewIfNeeded()
        return child.webView
    }

    func webViewDidClose(_ webView: WKWebView) { closePopup() }

    private func closePopup() {
        guard isPopup else { return }
        shutdown()
        dismiss(animated: true)
        onClose?()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        let id = registerDialog { completionHandler() }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.finishDialog(id) })
        showDialog(alert, id: id)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        let id = registerDialog { completionHandler(false) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.finishDialog(id) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard self?.pendingDialogs.removeValue(forKey: id) != nil else { return }
            completionHandler(true)
        })
        showDialog(alert, id: id)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        let id = registerDialog { completionHandler(nil) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.finishDialog(id) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            guard self?.pendingDialogs.removeValue(forKey: id) != nil else { return }
            completionHandler(alert?.textFields?.first?.text)
        })
        showDialog(alert, id: id)
    }

    private func registerDialog(_ cancel: @escaping () -> Void) -> UUID {
        let id = UUID()
        pendingDialogs[id] = cancel
        return id
    }

    private func finishDialog(_ id: UUID) { pendingDialogs.removeValue(forKey: id)?() }

    private func showDialog(_ alert: UIAlertController, id: UUID) {
        guard !isShutDown, viewIfLoaded?.window != nil, presentedViewController == nil else {
            finishDialog(id)
            return
        }
        present(alert, animated: true)
    }

    private func cancelDialogs() {
        let cancellations = Array(pendingDialogs.values)
        pendingDialogs.removeAll()
        cancellations.forEach { $0() }
    }

    private func invalidateAccountContext(except source: WebBridge?, reason: BridgeHandshake.SessionChangeReason) {
        if bridge !== source { bridge?.rotate() }
        // Notification precedes the Web client's credential write. Do not tear
        // down its document until a subsequent document has committed/finished.
        // Boot is public invalidation, and must not cause a reload loop.
        if reason != .boot {
            rendererLifecycle?.accountChanging()
            accountChangeDocument = committedDocument
            webView.allowsBackForwardNavigationGestures = false
            updateNavigation()
        }
        cancelDialogs()
        uploads.invalidate()
        downloads.cancelAll()
        for child in childrenByID.values { child.invalidateAccountContext(except: source, reason: reason) }
        // Dismiss native prompts/exports, but leave Web authentication popups
        // alive until the Web client's existing account reload completes.
        if let presented = presentedViewController,
           !(presented is UINavigationController) {
            presented.dismiss(animated: false)
        }
    }

    private func replaceAccountDocument(destination requestedURL: URL? = nil) {
        guard !isShutDown, !accountDocumentResetScheduled, let onAccountDocumentChange else { return }
        accountDocumentResetScheduled = true
        let destination = (requestedURL ?? webView.url).flatMap { origin.contains($0) ? $0 : nil } ?? origin.url
        let store = webView.configuration.websiteDataStore
        // Let the WebKit delegate return before SwiftUI removes the controller.
        // Recreating the view drops page-cache/history and child windows while
        // the normal WebKit credential store remains owned by WebKit.
        Task { @MainActor [weak self] in
            guard let self, !self.isShutDown else { return }
            onAccountDocumentChange(destination, store)
        }
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        rendererLifecycle?.shutdown()
        bridge?.invalidate()
        if bridge != nil { webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridge.name, contentWorld: .page) }
        navigationObservations.removeAll()
        for child in childrenByID.values { child.shutdown() }
        childrenByID.removeAll()
        cancelDialogs()
        downloads.cancelAll()
        uploads.invalidate()
        presentedViewController?.dismiss(animated: false)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
