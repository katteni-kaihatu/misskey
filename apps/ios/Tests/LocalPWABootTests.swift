// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
import GridSpaceCore
import UIKit
import WebKit
import XCTest
@testable import GridSpace

@MainActor
final class LocalPWABootTests: XCTestCase {
    func testAnonymousPWAReachesSigninBeforeAnyAccountIsCreatedInWebStorage() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let server = LocalParityServer(arguments: ["--ui-testing", "--local-parity-server"], environment: environment) else {
            throw XCTSkip("Local PWA fixture environment is not configured")
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = server.configureDataStore(.nonPersistent())
        configuration.userContentController.addUserScript(WKUserScript(source: """
            localStorage.setItem('lang', 'ja-JP');
            window.__parityBootErrors = [];
            addEventListener('error', e => window.__parityBootErrors.push(
                e.error ? String(e.error.stack || e.error).slice(0, 3000) : 'resource: ' + String(e.target?.src || e.target?.href || '').split('?')[0]), true);
            addEventListener('unhandledrejection', e => window.__parityBootErrors.push(String(e.reason?.stack || e.reason).slice(0, 3000)));
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let controller = WebSessionController(origin: server.origin, configuration: configuration)
        let delegate = ParityBootNavigation(server: server)
        controller.webView.navigationDelegate = delegate
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { controller.shutdown(); window.isHidden = true; prior?.makeKeyAndVisible() }
        var ready = false
        for _ in 0..<120 {
            if (try? await controller.webView.evaluateJavaScript("Boolean(document.querySelector('[data-testid=signin]'))")) as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(250))
        }
        // This fresh anonymous, nonpersistent view has no account or user
        // content. Diagnostics cannot include a logged-in user's data.
        let errors = try? await controller.webView.evaluateJavaScript("JSON.stringify(window.__parityBootErrors ?? [])")
        var page: Any?
        if !ready {
            page = try? await controller.webView.evaluateJavaScript("JSON.stringify({url:location.href,state:document.readyState,text:document.body?.innerText?.slice(0,2000),resources:performance.getEntriesByType('resource').map(x=>new URL(x.name).pathname)})")
        }
        XCTAssertTrue(ready, "Anonymous PWA boot errors: \(errors as? String ?? "none"); navigation: \(delegate.failure ?? "none"); page: \(page as? String ?? "none")")
        withExtendedLifetime(delegate) { }
    }
}

@MainActor
private final class ParityBootNavigation: NSObject, WKNavigationDelegate {
    let server: LocalParityServer
    var failure: String?
    init(server: LocalParityServer) { self.server = server }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if failure == nil {
            let value = error as NSError
            let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError
            failure = "\(value.domain):\(value.code), underlying=\(underlying?.domain ?? "none"):\(underlying?.code ?? 0), stream=\(underlying?.userInfo["_kCFStreamErrorCodeKey"] as? Int ?? 0)"
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if failure == nil { failure = "\((error as NSError).domain):\((error as NSError).code)" }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard server.handles(challenge.protectionSpace), challenge.previousFailureCount == 0 else {
            failure = "challenge rejected: \(challenge.protectionSpace.authenticationMethod), port=\(challenge.protectionSpace.port), proxy=\(challenge.protectionSpace.isProxy()), failures=\(challenge.previousFailureCount)"
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        Task {
            if let credential = await server.evaluatedCredential(for: challenge.protectionSpace) { completionHandler(.useCredential, credential) }
            else { failure = "fixture credential refused: \(challenge.protectionSpace.authenticationMethod), port=\(challenge.protectionSpace.port)"; completionHandler(.cancelAuthenticationChallenge, nil) }
        }
    }
}
#endif
