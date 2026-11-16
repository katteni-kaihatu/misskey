// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import WebKit

/// Coordinates renderer disposal, not authentication. Private Web readers must
/// fetch authorization again before replacing their suspended references.
@MainActor
final class WebRendererLifecycle {
    typealias Completion = @MainActor @Sendable (Result<Bool, Error>) -> Void
    typealias Evaluation = @MainActor (Bool, @escaping Completion) -> Void

    private weak var webView: WKWebView?
    private let evaluate: Evaluation
    private let active: () -> Bool
    private let mask = UIView()
    private let status = UILabel()
    private let retry = UIButton(type: .system)
    private var observers: [NSObjectProtocol] = []
    private var pending: [UUID: CheckedContinuation<Bool, Error>] = [:]
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var ticket = 0
    private var hasDocument = false
    private var knownRenderer = false
    private var needsCheck = true
    private var backgrounded = false
    private var stopped = false
    private(set) var isConcealed = true
    private(set) var isBlocked = false

    init(webView: WKWebView, container: UIView, origin: ServerOrigin, key: String,
         evaluation: Evaluation? = nil, isActive: (() -> Bool)? = nil) {
        self.webView = webView
        active = isActive ?? { [weak webView] in
            guard UIApplication.shared.applicationState == .active else { return false }
            if let scene = webView?.window?.windowScene { return scene.activationState == .foregroundActive }
            return true
        }
        evaluate = evaluation ?? { [weak webView] hidden, completion in
            guard let webView, let url = webView.url, origin.contains(url) else {
                completion(.failure(URLError(.badURL))); return
            }
            webView.callAsyncJavaScript("""
                const lifecycle = window.gridspaceNative?.rendererLifecycle;
                if (!lifecycle) return {version: 1, supported: false, hidden};
                return await lifecycle.apply(hidden, key);
                """, arguments: ["hidden": hidden, "key": key], in: nil, in: .page) { result in
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let value):
                    guard let reply = value as? [String: Any], reply["version"] as? Int == 1,
                          reply["hidden"] as? Bool == hidden, let supported = reply["supported"] as? Bool else {
                        completion(.failure(URLError(.cannotParseResponse))); return
                    }
                    completion(.success(supported))
                }
            }
        }
        mask.backgroundColor = .systemBackground
        mask.translatesAutoresizingMaskIntoConstraints = false
        status.numberOfLines = 0
        status.textAlignment = .center
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.accessibilityIdentifier = "renderer-resume-status"
        retry.setTitle("再確認", for: .normal)
        retry.accessibilityIdentifier = "renderer-resume-retry"
        retry.addAction(UIAction { [weak self] _ in self?.check() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [status, retry])
        stack.axis = .vertical; stack.spacing = 16; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        mask.addSubview(stack)
        container.addSubview(mask)
        NSLayoutConstraint.activate([
            mask.leadingAnchor.constraint(equalTo: webView.leadingAnchor), mask.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            mask.topAnchor.constraint(equalTo: webView.topAnchor), mask.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            stack.centerYAnchor.constraint(equalTo: mask.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: mask.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: mask.trailingAnchor, constant: -24),
        ])
        conceal()
        observe(UIApplication.willResignActiveNotification) { $0.willResignActive() }
        observe(UIApplication.didEnterBackgroundNotification) { $0.didEnterBackground() }
        observe(UIApplication.didBecomeActiveNotification) { $0.didBecomeActive() }
        observe(UIScene.willDeactivateNotification, sceneOnly: true) { $0.willResignActive() }
        observe(UIScene.didEnterBackgroundNotification, sceneOnly: true) { $0.didEnterBackground() }
        observe(UIScene.didActivateNotification, sceneOnly: true) { $0.didBecomeActive() }
    }

    private func observe(_ name: Notification.Name, sceneOnly: Bool = false, action: @escaping @MainActor @Sendable (WebRendererLifecycle) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let scene = note.object as? UIWindowScene
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                if sceneOnly {
                    guard let scene, scene === self.webView?.window?.windowScene else { return }
                }
                action(self)
            }
        })
    }

    func navigationStarted() {
        invalidate(); needsCheck = true
        conceal()
    }

    func documentCommitted() {
        invalidate(); hasDocument = true; knownRenderer = false; needsCheck = true
        if active() { check() } else { didEnterBackground() }
    }

    func navigationFailed() {
        if !hasDocument { reveal(); return } // Only the native load-error UI is present.
        if active() { check() }
    }

    func processTerminated() {
        invalidate(); hasDocument = false; needsCheck = true
        reveal() // The existing native process-loss UI covers an empty renderer.
    }

    func accountChanging() { invalidate(); needsCheck = true; conceal() }

    func willResignActive() {
        invalidate(); conceal()
        // An interruption (for example a system permission prompt) is not yet
        // backgrounding. Do not discard a private form just for that prompt.
    }

    func didEnterBackground() {
        guard !stopped else { return }
        invalidate(); backgrounded = true; needsCheck = true; conceal()
        guard hasDocument else { return }
        let current = ticket
        task = Task { [weak self] in
            guard let self else { return }
            if let supported = try? await send(hidden: true), current == ticket {
                knownRenderer = knownRenderer || supported
            }
        }
    }

    func didBecomeActive() {
        guard !stopped, active() else { return }
        if !hasDocument { return }
        if backgrounded || needsCheck { check() } else { reveal() }
    }

    func check() {
        guard !stopped, hasDocument, active() else { return }
        invalidate(); needsCheck = true; conceal(checking: true)
        let current = ticket
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, current == ticket else { return }
            invalidate(); block()
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Repeating suspension also handles JS frozen before the
                // background callback ran, and cached history documents.
                let suspended = try await send(hidden: true)
                guard current == ticket, active() else { return }
                knownRenderer = knownRenderer || suspended
                let resumed = try await send(hidden: false)
                guard current == ticket, active() else { return }
                guard !knownRenderer || (suspended && resumed) else { throw URLError(.cannotParseResponse) }
                knownRenderer = knownRenderer || resumed
                deadline?.cancel(); deadline = nil
                needsCheck = false; backgrounded = false
                reveal()
            } catch {
                guard current == ticket, active() else { return }
                deadline?.cancel(); deadline = nil
                block()
            }
        }
    }

    private func send(hidden: Bool) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            pending[id] = continuation
            evaluate(hidden) { [weak self] result in self?.pending.removeValue(forKey: id)?.resume(with: result) }
        }
    }

    private func invalidate() {
        ticket += 1
        deadline?.cancel(); deadline = nil
        task?.cancel(); task = nil
        let continuations = Array(pending.values); pending.removeAll()
        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    private func conceal(checking: Bool = false) {
        isConcealed = true; isBlocked = false
        mask.isHidden = false; webView?.accessibilityElementsHidden = true
        status.text = checking ? "画面を再開しています…" : "ぐりすぺ"
        retry.isHidden = true
    }

    private func block() {
        conceal(); isBlocked = true
        status.text = "画面の再開を確認できませんでした。再確認するか、ツールバーから再読み込みしてください。未送信の内容は自動では破棄しません。"
        retry.isHidden = false
    }

    private func reveal() {
        isConcealed = false; isBlocked = false
        mask.isHidden = true; webView?.accessibilityElementsHidden = false
    }

    func shutdown() {
        guard !stopped else { return }
        stopped = true; invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        mask.removeFromSuperview()
    }
}
