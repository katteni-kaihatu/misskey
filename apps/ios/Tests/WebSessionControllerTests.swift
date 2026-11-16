// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import WebKit
import XCTest
@testable import GridSpace

@MainActor
final class WebSessionControllerTests: XCTestCase {
    func testAccountChangeWaitsForNextNavigationAndPreservesWebOwnedStorage() async throws {
        let origin = try ServerOrigin("https://example.com")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = WebSessionController(origin: origin, configuration: configuration)
        defer { controller.shutdown() }
        let loaded = expectation(description: "Initial synthetic account document")
        let navigation = LocalNavigation { loaded.fulfill() }
        controller.webView.navigationDelegate = navigation
        controller.webView.loadHTMLString("<!doctype html><title>Before account change</title>", baseURL: origin.url)
        await fulfillment(of: [loaded], timeout: 10)

        let replaced = expectation(description: "Account document replacement")
        let destination = try XCTUnwrap(origin.resolve("/after-change?keep=one%2Btwo#section"))
        var replacements = 0
        var retainedStore: WKWebsiteDataStore?
        controller.onAccountDocumentChange = { requestedURL, store in
            XCTAssertEqual(requestedURL, destination)
            XCTAssertTrue(store === configuration.websiteDataStore)
            retainedStore = store
            replacements += 1
            replaced.fulfill()
        }
        let status = try await controller.webView.callAsyncJavaScript("""
            await window.gridspaceNative.handshake('synthetic-account-document');
            const result = await window.gridspaceNative.sessionChanged({host:'example.com',userId:'synthetic-next',reason:'switch'});
            localStorage.setItem('synthetic-committed-account', 'next');
            return result.status;
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(status as? String, "success")
        XCTAssertEqual(replacements, 0, "The notification reply must not destroy the document before its Web storage write")
        XCTAssertFalse(controller.webView.allowsBackForwardNavigationGestures)
        controller.webView.navigationDelegate = controller
        // This HTTPS action must be cancelled before a network request or a
        // second execution of the PWA. The host receives its exact destination.
        controller.webView.load(URLRequest(url: destination))
        await fulfillment(of: [replaced], timeout: 10)
        XCTAssertEqual(replacements, 1)
        let fresh = WebSessionController(origin: origin, websiteDataStore: try XCTUnwrap(retainedStore))
        defer { fresh.shutdown() }
        XCTAssertTrue(fresh.webView.configuration.websiteDataStore === configuration.websiteDataStore)
        XCTAssertTrue(fresh.webView.allowsBackForwardNavigationGestures)
        let freshLoaded = expectation(description: "Fresh WebView with the original Web-owned store")
        let freshNavigation = LocalNavigation { freshLoaded.fulfill() }
        fresh.webView.navigationDelegate = freshNavigation
        fresh.webView.loadHTMLString("<!doctype html><title>Fresh account view</title>", baseURL: origin.url)
        await fulfillment(of: [freshLoaded], timeout: 10)
        XCTAssertFalse(fresh.webView.canGoBack)
        let value = try await fresh.webView.evaluateJavaScript("localStorage.getItem('synthetic-committed-account')")
        XCTAssertEqual(value as? String, "next")
        withExtendedLifetime((navigation, freshNavigation)) { }
    }

    func testBridgeUsesBrowserIPv6AuthorityForSessionChanges() async throws {
        let origin = try ServerOrigin("https://[fd12:3456::2]:61813")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = WebSessionController(origin: origin, configuration: configuration)
        defer { controller.shutdown() }
        let loaded = expectation(description: "Synthetic IPv6 document")
        let navigation = LocalNavigation { loaded.fulfill() }
        controller.webView.navigationDelegate = navigation
        controller.webView.loadHTMLString("<!doctype html><title>IPv6 session</title>", baseURL: origin.url)
        await fulfillment(of: [loaded], timeout: 10)
        let status = try await controller.webView.callAsyncJavaScript("""
            await window.gridspaceNative.handshake('ipv6-fixture');
            return (await window.gridspaceNative.sessionChanged({host:'[fd12:3456::2]:61813',userId:null,reason:'logout'})).status;
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(status as? String, "success")
        withExtendedLifetime(navigation) { }
    }

    func testWebKitRecognizesPolicyAndDialogDelegates() throws {
        let controller = WebSessionController(origin: try ServerOrigin("example.com"))
        defer { controller.shutdown() }
        // Optional Objective-C delegates can silently stop being called when their
        // Swift callback isolation no longer matches the SDK's declaration.
        for selector in [
            "webView:decidePolicyForNavigationAction:decisionHandler:",
            "webView:decidePolicyForNavigationResponse:decisionHandler:",
            "webView:didReceiveServerRedirectForProvisionalNavigation:",
            "webView:didReceiveAuthenticationChallenge:completionHandler:",
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
        ] {
            XCTAssertTrue(controller.responds(to: NSSelectorFromString(selector)), selector)
        }
    }

    func testBridgeRejectsForeignOriginsAndSubframes() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WebSessionController(origin: try ServerOrigin("example.com"), configuration: config)
        defer { controller.shutdown() }
        let web = controller.webView
        let body: [String: Any] = ["protocolVersion": 1, "requestId": UUID().uuidString,
                                   "accountEpoch": NSNull(), "operation": "capabilities", "payload": [:]]
        for host in ["example.com", "other.example"] {
            let loaded = expectation(description: host)
            let navigation = LocalNavigation { loaded.fulfill() }
            web.navigationDelegate = navigation
            web.loadHTMLString("<!doctype html><body>Bridge test</body>", baseURL: URL(string: "https://" + host))
            await fulfillment(of: [loaded], timeout: 10)
            let status = try await web.callAsyncJavaScript("""
                try { const r = await window.webkit.messageHandlers.gridspaceBridge.postMessage(body); return r.status; }
                catch { return 'refused'; }
                """, arguments: ["body": body], in: nil, contentWorld: .page)
            XCTAssertEqual(status as? String, host == "example.com" ? "success" : "refused")
            if host == "example.com" {
                let childStatus = try await web.callAsyncJavaScript("""
                    return await new Promise(resolve => {
                        window.addEventListener('message', e => resolve(e.data), {once:true});
                        const child = document.createElement('iframe');
                        child.srcdoc = '<script>window.webkit.messageHandlers.gridspaceBridge.postMessage(' + JSON.stringify(body) +
                            ').then(() => parent.postMessage("success", "*"), () => parent.postMessage("refused", "*"));<' + '/script>';
                        document.body.append(child);
                    });
                    """, arguments: ["body": body], in: nil, contentWorld: .page)
                XCTAssertEqual(childStatus as? String, "refused")
            }
            withExtendedLifetime(navigation) { }
        }
    }

    func testDialogsWithoutPresenterCompleteWithSafeDefaults() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = WebSessionController(origin: try ServerOrigin("example.com"), configuration: configuration)
        defer { controller.shutdown() }
        let loaded = expectation(description: "Local HTML loaded")
        let navigation = LocalNavigation { loaded.fulfill() }
        controller.webView.navigationDelegate = navigation
        controller.webView.loadHTMLString("<!doctype html><title>Dialogs</title>", baseURL: nil)
        await fulfillment(of: [loaded], timeout: 10)

        let alert = try await controller.webView.evaluateJavaScript("alert('test'); 'completed'")
        XCTAssertEqual(alert as? String, "completed")
        let confirm = try await controller.webView.evaluateJavaScript("confirm('test')")
        XCTAssertEqual(confirm as? Bool, false)
        let prompt = try await controller.webView.evaluateJavaScript("prompt('test', 'default')")
        XCTAssertTrue(prompt is NSNull)
    }

    func testSessionChangeCancelsPendingSelectionBeforeReplyAndExpiresOldEpoch() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = WebSessionController(origin: try ServerOrigin("example.com"), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            controller.shutdown()
            window.isHidden = true
            prior?.makeKeyAndVisible()
        }
        let loaded = expectation(description: "Synthetic session document")
        let navigation = LocalNavigation { loaded.fulfill() }
        controller.webView.navigationDelegate = navigation
        controller.webView.loadHTMLString("<!doctype html><title>Session test</title>", baseURL: URL(string: "https://example.com"))
        await fulfillment(of: [loaded], timeout: 10)
        var cancellations = 0
        controller.uploads.begin(allowsMultiple: true, allowsDirectories: false, sourceHost: "example.com") { urls in
            XCTAssertNil(urls)
            cancellations += 1
        }
        let result = try await controller.webView.callAsyncJavaScript("""
            const native = window.gridspaceNative;
            const before = await native.handshake('synthetic-session');
            const changed = await native.sessionChanged({host:'example.com', userId:null, reason:'logout'});
            const stale = await window.webkit.messageHandlers.gridspaceBridge.postMessage({
                protocolVersion:1, requestId:crypto.randomUUID(), accountEpoch:before.accountEpoch,
                operation:'ready', payload:{schemaVersion:1, webVersion:'synthetic-session'}
            });
            return {changed:changed.status, rotated:before.accountEpoch !== changed.accountEpoch,
                    stale:stale.status, authenticated:changed.payload.authenticatedOperations};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(result?["changed"] as? String, "success")
        XCTAssertEqual(result?["rotated"] as? Bool, true)
        XCTAssertEqual(result?["stale"] as? String, "expired")
        XCTAssertEqual(result?["authenticated"] as? Bool, false)
        withExtendedLifetime(navigation) { }
    }

    func testPopupKeepsWebStoreButOwnsItsHandlerAndInvalidatesParentEpoch() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let parent = WebSessionController(origin: try ServerOrigin("example.com"), configuration: configuration)
        let child = WebSessionController(origin: parent.origin, configuration: parent.webView.configuration,
                                         isPopup: true, accountOwner: parent)
        defer { child.shutdown(); parent.shutdown() }
        XCTAssertTrue(parent.webView.configuration.websiteDataStore === child.webView.configuration.websiteDataStore)
        XCTAssertFalse(parent.webView.configuration.userContentController === child.webView.configuration.userContentController)
        for controller in [parent, child] {
            let loaded = expectation(description: "Synthetic window")
            let navigation = LocalNavigation { loaded.fulfill() }
            controller.webView.navigationDelegate = navigation
            controller.webView.loadHTMLString("<!doctype html><title>Window session</title>", baseURL: URL(string: "https://example.com"))
            await fulfillment(of: [loaded], timeout: 10)
            withExtendedLifetime(navigation) { }
        }
        let capabilities = """
            return await window.webkit.messageHandlers.gridspaceBridge.postMessage({protocolVersion:1,
                requestId:crypto.randomUUID(), accountEpoch:null, operation:'capabilities', payload:{}});
            """
        let before = try await parent.webView.callAsyncJavaScript(capabilities, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        let changed = try await child.webView.callAsyncJavaScript("""
            const caps = await window.webkit.messageHandlers.gridspaceBridge.postMessage({protocolVersion:1,
                requestId:crypto.randomUUID(), accountEpoch:null, operation:'capabilities', payload:{}});
            const changed = await window.webkit.messageHandlers.gridspaceBridge.postMessage({protocolVersion:1,
                requestId:crypto.randomUUID(), accountEpoch:caps.accountEpoch, operation:'session.changed',
                payload:{host:'example.com', userId:'synthetic-user', reason:'switch'}});
            const ready = await window.webkit.messageHandlers.gridspaceBridge.postMessage({protocolVersion:1,
                requestId:crypto.randomUUID(), accountEpoch:changed.accountEpoch, operation:'ready',
                payload:{schemaVersion:1, webVersion:'synthetic-popup'}});
            return ready.status;
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(changed as? String, "success")
        let after = try await parent.webView.callAsyncJavaScript(capabilities, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertNotEqual(try XCTUnwrap(before?["accountEpoch"] as? String), try XCTUnwrap(after?["accountEpoch"] as? String))
    }
}

@MainActor
private final class LocalNavigation: NSObject, WKNavigationDelegate {
    let onLoad: () -> Void

    init(onLoad: @escaping () -> Void) { self.onLoad = onLoad }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoad() }
}
