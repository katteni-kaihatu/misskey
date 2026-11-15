// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import WebKit

/// First compatibility slice: retain the real Web client and its authentication.
/// Deliberately installs no script handler or token-extraction JavaScript.
@MainActor
final class WebSessionController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let origin: ServerOrigin
    let webView: WKWebView
    private let policy: NavigationPolicy
    private let isPopup: Bool
    private var childrenByID: [ObjectIdentifier: WebSessionController] = [:]
    private var onClose: (() -> Void)?
    private var pendingDialogs: [UUID: () -> Void] = [:]
    private var navigationObservations: [NSKeyValueObservation] = []
    private let downloads = WebDownloads()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let recovery = UIStackView()
    private let recoveryText = UILabel()
    private var backButton: UIBarButtonItem!
    private var forwardButton: UIBarButtonItem!
    private var isShutDown = false

    init(origin: ServerOrigin, configuration: WKWebViewConfiguration? = nil, isPopup: Bool = false) {
        self.origin = origin
        policy = NavigationPolicy(origin: origin)
        self.isPopup = isPopup
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.websiteDataStore = .default()
            config.allowsInlineMediaPlayback = true
            // Do not impersonate Safari or override the web client's user agent.
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        // Child windows MUST use WebKit's supplied configuration, including its store.
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        downloads.presenter = self
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
            webView.load(URLRequest(url: origin.url))
        }
        updateNavigation()
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

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }

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
        backButton?.isEnabled = webView.canGoBack
        forwardButton?.isEnabled = webView.canGoForward
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
        if origin.contains(url) { return true }
        if url.scheme?.lowercased() == "blob",
           let nested = URL(string: String(url.absoluteString.dropFirst(5))) {
            return origin.contains(nested)
        }
        return false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !isShutDown, let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload, isPermittedDownload(url) {
            decisionHandler(.download)
            return
        }
        let decision = policy.decision(for: url, isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true, isUserActivated: navigationAction.navigationType == .linkActivated)
        switch decision {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        case .openExternal, .confirmExternal:
            decisionHandler(.cancel)
            openExternal(url, confirm: decision == .confirmExternal)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            guard let url = navigationResponse.response.url, isPermittedDownload(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { downloads.attach(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { downloads.attach(download) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        recovery.isHidden = true
        spinner.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showLoadFailure(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadFailure(error) }

    private func showLoadFailure(_ error: Error) {
        spinner.stopAnimating()
        if (error as NSError).code == NSURLErrorCancelled { return }
        recoveryText.text = "ページを読み込めませんでした。通信状態を確認してください。下の操作は現在のページを再読み込みします。編集中の内容を残すため、自動では再読み込みしません。"
        recovery.isHidden = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        cancelDialogs()
        downloads.cancelAll()
        spinner.stopAnimating()
        recoveryText.text = "Web画面の処理が終了しました。保存されていない編集や添付は復元できない場合があります。送信済みか不明な投稿は再送前に確認してください。"
        recovery.isHidden = false
        // Never silently reload or replay a submission after process loss.
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !isShutDown, presentedViewController == nil,
              let url = navigationAction.request.url,
              policy.decision(for: url, isMainFrame: true, isUserActivated: navigationAction.navigationType == .linkActivated) == .allow else { return nil }
        let child = WebSessionController(origin: origin, configuration: configuration, isPopup: true)
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

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        let id = registerDialog { completionHandler() }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.finishDialog(id) })
        showDialog(alert, id: id)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        let id = registerDialog { completionHandler(false) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.finishDialog(id) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard self?.pendingDialogs.removeValue(forKey: id) != nil else { return }
            completionHandler(true)
        })
        showDialog(alert, id: id)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
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

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        navigationObservations.removeAll()
        for child in childrenByID.values { child.shutdown() }
        childrenByID.removeAll()
        cancelDialogs()
        downloads.cancelAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
