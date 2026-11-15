// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import GridSpaceCore

final class NavigationPolicyTests: XCTestCase {
    private let policy = NavigationPolicy(origin: try! ServerOrigin("https://example.com"))

    private func decision(_ value: String, main: Bool = true, user: Bool = false) -> NavigationDecision {
        policy.decision(for: URL(string: value)!, isMainFrame: main, isUserActivated: user)
    }

    func testUnknownSameOriginRouteRemainsAvailable() {
        XCTAssertEqual(decision("https://example.com/new-feature?q=a#b"), .allow)
        XCTAssertEqual(decision("https://example.com:443/settings", main: false), .allow)
    }

    func testExternalLinksUseSeparateBrowserAndRedirectsNeedConfirmation() {
        XCTAssertEqual(decision("https://example.com.evil.test", user: true), .openExternal)
        XCTAssertEqual(decision("https://example.com.evil.test"), .confirmExternal)
        XCTAssertEqual(decision("http://example.com", user: true), .openExternal)
        XCTAssertEqual(decision("https://example.com:8443"), .confirmExternal)
    }

    func testExternalWidgetsKeepTheirEmbeds() {
        for value in [
            "https://widget.example/frame", "http://widget.example/frame",
            "about:blank", "about:srcdoc", "blob:https://widget.example/1234",
            "blob:https://example.com/1234",
        ] {
            XCTAssertEqual(decision(value, main: false), .allow, value)
        }
        XCTAssertEqual(decision("about:blank"), .allow)
    }

    func testPrivilegedAndOpaqueSchemesCannotNavigate() {
        for value in [
            "javascript:alert(1)", "data:text/html,hello", "file:///tmp/private",
            "custom-app://operation", "blob:null/1234", "about:config",
            "https://user:password@example.com/", "https://user@external.example/",
        ] {
            XCTAssertEqual(decision(value, user: true), .cancel, value)
            XCTAssertEqual(decision(value, main: false, user: true), .cancel, value)
        }
        XCTAssertEqual(decision("blob:https://example.com/1234", user: true), .cancel)
        XCTAssertEqual(decision("about:srcdoc"), .cancel)
    }

    func testMailAndPhoneRequireExplicitMainFrameAction() {
        for value in ["mailto:hello@example.com", "tel:+123456789"] {
            XCTAssertEqual(decision(value, user: true), .openExternal)
            XCTAssertEqual(decision(value), .cancel)
            XCTAssertEqual(decision(value, main: false, user: true), .cancel)
        }
    }
}
