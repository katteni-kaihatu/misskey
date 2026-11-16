// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import WebKit
import XCTest
@testable import GridSpace

@MainActor
final class WebRendererLifecycleTests: XCTestCase {
    @MainActor private final class Probe {
        let view = UIView()
        let web = WKWebView()
        var active = true
        var requests: [(hidden: Bool, finish: WebRendererLifecycle.Completion)] = []
        var lifecycle: WebRendererLifecycle!

        init() throws {
            view.addSubview(web)
            lifecycle = WebRendererLifecycle(webView: web, container: view, origin: try ServerOrigin("example.com"),
                key: String(repeating: "a", count: 64), evaluation: { [weak self] hidden, finish in
                    self?.requests.append((hidden, finish))
                }, isActive: { [weak self] in self?.active == true })
        }

        func waitForRequests(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            for _ in 0..<200 {
                if requests.count >= count { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Renderer request did not arrive", file: file, line: line)
        }

        func ready(supported: Bool = true) async {
            lifecycle.documentCommitted()
            await waitForRequests(1)
            requests[0].finish(.success(supported))
            await waitForRequests(2)
            requests[1].finish(.success(supported))
            for _ in 0..<10 { await Task.yield() }
            XCTAssertFalse(lifecycle.isConcealed)
        }
    }

    func testTransientSystemInterruptionOnlyConcealsAndPreservesRenderer() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        await p.ready()
        p.lifecycle.willResignActive()
        XCTAssertTrue(p.lifecycle.isConcealed)
        XCTAssertTrue(p.web.accessibilityElementsHidden)
        p.lifecycle.didBecomeActive()
        XCTAssertFalse(p.lifecycle.isConcealed)
        XCTAssertEqual(p.requests.count, 2, "A permission prompt must not discard a private draft")
    }

    func testBackgroundAndResumeWaitForDisposalAndIgnoreLateOldReplies() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        await p.ready()
        p.active = false
        p.lifecycle.willResignActive()
        p.lifecycle.didEnterBackground()
        XCTAssertTrue(p.lifecycle.isConcealed)
        await p.waitForRequests(3)
        XCTAssertTrue(p.requests[2].hidden)
        p.active = true
        p.lifecycle.didBecomeActive()
        await p.waitForRequests(4)
        p.requests[2].finish(.success(true)) // A reply from the suspended generation.
        XCTAssertTrue(p.lifecycle.isConcealed)
        XCTAssertTrue(p.requests[3].hidden)
        p.requests[3].finish(.success(true))
        await p.waitForRequests(5)
        XCTAssertFalse(p.requests[4].hidden)
        XCTAssertTrue(p.lifecycle.isConcealed)
        p.requests[4].finish(.success(true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(p.lifecycle.isConcealed)
        XCTAssertFalse(p.web.accessibilityElementsHidden)
    }

    func testAnotherBackgroundDuringResumeCannotRevealStaleContent() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        p.lifecycle.documentCommitted()
        await p.waitForRequests(1)
        p.requests[0].finish(.success(true))
        await p.waitForRequests(2)
        p.active = false
        p.lifecycle.willResignActive()
        p.lifecycle.didEnterBackground()
        await p.waitForRequests(3)
        p.requests[1].finish(.success(true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(p.lifecycle.isConcealed)
        XCTAssertFalse(p.lifecycle.isBlocked)
    }

    func testFailedDisposalStaysCoveredAndCanRetryWithoutNavigation() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        p.lifecycle.documentCommitted()
        await p.waitForRequests(1)
        p.requests[0].finish(.failure(URLError(.cannotParseResponse)))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(p.lifecycle.isBlocked)
        XCTAssertTrue(p.lifecycle.isConcealed)
        XCTAssertNil(p.web.url, "Failure must not reload or navigate an unsent form")
        p.lifecycle.check()
        await p.waitForRequests(2)
        p.requests[1].finish(.success(true))
        await p.waitForRequests(3)
        p.requests[2].finish(.success(true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(p.lifecycle.isConcealed)
    }

    func testKnownRendererCannotSilentlyDowngradeToLegacy() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        await p.ready()
        p.lifecycle.check()
        await p.waitForRequests(3)
        p.requests[2].finish(.success(false))
        await p.waitForRequests(4)
        p.requests[3].finish(.success(false))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(p.lifecycle.isBlocked)
        XCTAssertTrue(p.lifecycle.isConcealed)
    }

    func testUnresponsiveRendererTimesOutWithoutReloadAndIgnoresLateReply() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        p.lifecycle.documentCommitted()
        await p.waitForRequests(1)
        for _ in 0..<650 {
            if p.lifecycle.isBlocked { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(p.lifecycle.isBlocked)
        XCTAssertTrue(p.lifecycle.isConcealed)
        p.requests[0].finish(.success(true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(p.lifecycle.isBlocked)
        XCTAssertEqual(p.requests.count, 1, "Timeout must not automatically retry an unknown result")
        XCTAssertNil(p.web.url)
    }

    func testNavigationAndAccountChangesCannotAcceptAnOldResume() async throws {
        let p = try Probe()
        defer { p.lifecycle.shutdown() }
        p.lifecycle.documentCommitted()
        await p.waitForRequests(1)
        p.requests[0].finish(.success(true))
        await p.waitForRequests(2)
        p.lifecycle.navigationStarted()
        p.lifecycle.accountChanging()
        p.requests[1].finish(.success(true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(p.lifecycle.isConcealed)
        p.lifecycle.navigationFailed()
        await p.waitForRequests(3)
        XCTAssertTrue(p.requests[2].hidden, "A failed navigation must dispose the retained document before revealing it")
    }

    func testBootstrapWaitsForDisposalPreservesInputAndRefusesForgedResume() async throws {
        let key = String(repeating: "b", count: 64)
        let origin = try ServerOrigin("example.com")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WebSessionController(origin: origin, configuration: config, rendererLifecycleKey: key)
        defer { controller.shutdown() }
        let loaded = expectation(description: "Synthetic lifecycle document")
        let navigation = RendererNavigation { loaded.fulfill() }
        let web = controller.webView
        web.navigationDelegate = navigation
        web.loadHTMLString("<!doctype html><textarea id='draft'>Unsent ordinary input</textarea><div id='private'>Private body</div>", baseURL: origin.url)
        await fulfillment(of: [loaded], timeout: 10)
        let forged = try await web.callAsyncJavaScript("""
            const lifecycle = window.gridspaceNative.rendererLifecycle;
            let refused = false;
            try { await lifecycle.apply(false, 'x'.repeat(64)); } catch { refused = true; }
            window.privateActor = {name:'Private actor'};
            lifecycle.subscribe(async hidden => {
                if (!hidden) return;
                document.querySelector('#private').replaceChildren();
                window.privateActor = null;
                await new Promise(resolve => { window.releaseDisposal = resolve; });
            });
            return {refused, hidden:lifecycle.hidden, frozen:Object.isFrozen(lifecycle)};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(forged?["refused"] as? Bool, true)
        XCTAssertEqual(forged?["hidden"] as? Bool, true)
        XCTAssertEqual(forged?["frozen"] as? Bool, true)
        let container = UIView()
        container.addSubview(web)
        let lifecycle = WebRendererLifecycle(webView: web, container: container, origin: origin, key: key, isActive: { true })
        defer { lifecycle.shutdown() }
        lifecycle.documentCommitted()
        var waiting = false
        for _ in 0..<200 {
            waiting = (try await web.evaluateJavaScript("typeof window.releaseDisposal === 'function'")) as? Bool == true
            if waiting { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(waiting)
        XCTAssertTrue(lifecycle.isConcealed, "An unfinished disposal must not reveal the WebView")
        _ = try await web.evaluateJavaScript("window.releaseDisposal()")
        for _ in 0..<200 {
            if !lifecycle.isConcealed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(lifecycle.isConcealed)
        let state = try await web.evaluateJavaScript("({draft:document.querySelector('#draft').value, body:document.querySelector('#private').textContent, actor:window.privateActor})") as? [String: Any]
        XCTAssertEqual(state?["draft"] as? String, "Unsent ordinary input")
        XCTAssertEqual(state?["body"] as? String, "")
        XCTAssertTrue(state?["actor"] is NSNull)
        let failed = try await web.callAsyncJavaScript("""
            window.gridspaceNative.rendererLifecycle.subscribe(() => { throw new Error('synthetic failure'); });
            let disposed = false;
            window.gridspaceNative.rendererLifecycle.subscribe(() => { disposed = true; });
            // Release the earlier asynchronous listener as well.
            const pending = window.gridspaceNative.rendererLifecycle.apply(true, key);
            window.releaseDisposal();
            try { await pending; return false; } catch { return disposed; }
            """, arguments: ["key": key], in: nil, contentWorld: .page)
        XCTAssertEqual(failed as? Bool, true, "Other readers must still dispose when one listener throws")
        withExtendedLifetime(navigation) { }
    }

    func testOldWebCompatibilityAndShutdownCancelPendingReply() async throws {
        let p = try Probe()
        await p.ready(supported: false)
        p.lifecycle.check()
        await p.waitForRequests(3)
        p.lifecycle.shutdown()
        p.requests[2].finish(.success(true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(p.requests.count, 3)
    }
}

@MainActor
private final class RendererNavigation: NSObject, WKNavigationDelegate {
    let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
