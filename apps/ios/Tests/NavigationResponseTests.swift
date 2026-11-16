// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import WebKit
import XCTest
@testable import GridSpace

@MainActor
final class NavigationResponseTests: XCTestCase {
    func testServerRedirectCannotReuseOriginalLinkActivationAndStateExpires() throws {
        let controller = WebSessionController(origin: try ServerOrigin("https://example.com"))
        defer { controller.shutdown() }
        let outside = try XCTUnwrap(URL(string: "https://outside.example/"))
        XCTAssertEqual(controller.actionPolicy(url: outside, isMainFrame: true, isUserActivated: true), .openExternal)
        controller.webView(controller.webView, didStartProvisionalNavigation: nil)
        XCTAssertEqual(controller.actionPolicy(url: outside, isMainFrame: true, isUserActivated: true), .confirmExternal)
        controller.webView(controller.webView, didReceiveServerRedirectForProvisionalNavigation: nil)
        XCTAssertEqual(controller.actionPolicy(url: outside, isMainFrame: true, isUserActivated: true), .confirmExternal)
        XCTAssertEqual(controller.actionPolicy(url: outside, isMainFrame: false, isUserActivated: true), .allow)
        controller.webView(controller.webView, didFinish: nil)
        XCTAssertEqual(controller.actionPolicy(url: outside, isMainFrame: true, isUserActivated: true), .openExternal)
        controller.webView(controller.webView, didReceiveServerRedirectForProvisionalNavigation: nil)
        controller.webView(controller.webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        XCTAssertEqual(controller.actionPolicy(url: outside, isMainFrame: true, isUserActivated: true), .openExternal)
    }

    func testFinalResponseEnforcesOriginWithoutBlockingWidgetFrames() throws {
        let controller = WebSessionController(origin: try ServerOrigin("https://example.com"))
        defer { controller.shutdown() }
        let cases: [(String, Bool, Bool, WebSessionController.ResponsePolicy)] = [
            ("https://EXAMPLE.com:443/new?q=x#tab", true, true, .allow),
            ("https://example.com.evil.test/page", true, true, .confirmExternal),
            ("https://example.com:8443/page", true, true, .confirmExternal),
            ("http://example.com/page", true, true, .confirmExternal),
            ("https://widget.example/frame", false, true, .allow),
            ("about:blank", true, true, .allow),
            ("about:srcdoc", false, true, .allow),
            ("data:text/html,untrusted", true, true, .cancel),
            ("file:///tmp/private", false, true, .cancel),
            ("https://user:password@example.com/page", true, true, .cancel),
            ("https://example.com/archive", true, false, .download),
            ("blob:https://example.com/archive", true, false, .download),
            ("https://outside.example/archive", true, false, .cancel),
            ("blob:https://outside.example/archive", false, false, .cancel),
        ]
        for (url, main, displayable, expected) in cases {
            let result = controller.responsePolicy(url: try XCTUnwrap(URL(string: url)), isMainFrame: main, canShowMIMEType: displayable)
            XCTAssertEqual(result, expected, url)
        }
        XCTAssertEqual(controller.responsePolicy(url: nil, isMainFrame: true, canShowMIMEType: true), .cancel)
    }

    func testShutdownRejectsDisplayAndDownloadResponses() throws {
        let controller = WebSessionController(origin: try ServerOrigin("https://example.com"))
        controller.shutdown()
        for displayable in [false, true] {
            let result = controller.responsePolicy(url: try XCTUnwrap(URL(string: "https://example.com/file")), isMainFrame: true, canShowMIMEType: displayable)
            XCTAssertEqual(result, .cancel)
        }
    }

    func testIPv6BlobDownloadUsesItsExactEmbeddedOrigin() throws {
        let controller = WebSessionController(origin: try ServerOrigin("https://[fd12:3456::2]:61813"))
        defer { controller.shutdown() }
        let local = try XCTUnwrap(URL(string: "blob:https://[fd12:3456::2]:61813/archive"))
        XCTAssertEqual(controller.responsePolicy(url: local, isMainFrame: true, canShowMIMEType: false), .download)
        let webKitLocal = try XCTUnwrap(URL(string: "blob:https://%5Bfd12:3456::2%5D:61813/archive"))
        XCTAssertEqual(controller.responsePolicy(url: webKitLocal, isMainFrame: true, canShowMIMEType: false), .download)
        let outside = try XCTUnwrap(URL(string: "blob:https://[fd12:3456::3]:61813/archive"))
        XCTAssertEqual(controller.responsePolicy(url: outside, isMainFrame: true, canShowMIMEType: false), .cancel)
    }
}
