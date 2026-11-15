// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import GridSpaceCore

final class ServerOriginTests: XCTestCase {
    func testNormalizesSchemeHostDefaultPortAndWhitespace() throws {
        let origin = try ServerOrigin("  HTTPS://EXAMPLE.COM:443/\n")
        XCTAssertEqual(origin.url.absoluteString, "https://example.com/")
        XCTAssertEqual(origin.host, "example.com")
        XCTAssertEqual(origin.port, 443)
        XCTAssertEqual(origin, try ServerOrigin("example.com"))
    }

    func testPreservesNonDefaultPort() throws {
        let origin = try ServerOrigin("example.com:8443")
        XCTAssertEqual(origin.url.absoluteString, "https://example.com:8443/")
        XCTAssertTrue(origin.contains(URL(string: "https://EXAMPLE.com:8443/notes/1")!))
        XCTAssertFalse(origin.contains(URL(string: "https://example.com/")!))
    }

    func testRejectsNonOriginsAndAuthenticationMaterial() {
        for value in [
            "", " ", "http://example.com", "file:///tmp/test", "javascript:alert(1)",
            "https://user@example.com", "https://:password@example.com",
            "https://example.com/path", "https://example.com//",
            "https://example.com?", "https://example.com#", "https://example.com?q=x",
            "https://example.com/#x", "https://example.com:0", "https://example.com:65536",
            "https://exam ple.com", "https://example.com\\@evil.example",
            "https://%65xample.com", "https://example.com\n.evil.example",
        ] {
            XCTAssertThrowsError(try ServerOrigin(value), value)
        }
    }

    func testSameOriginIsNotPrefixOrSubstringMatching() throws {
        let origin = try ServerOrigin("https://example.com")
        for value in [
            "https://example.com.evil.test/path", "https://notexample.com",
            "https://child.example.com", "http://example.com", "https://example.com:444",
            "https://evil.test/example.com", "https://example.com@evil.test",
            "https://user@example.com", "https://example.com.",
        ] {
            XCTAssertFalse(origin.contains(URL(string: value)!), value)
        }
        XCTAssertTrue(origin.contains(URL(string: "https://EXAMPLE.COM:443/new/route?key=1#tab")!))
    }

    func testResolvePreservesEveryRouteComponent() throws {
        let origin = try ServerOrigin("https://example.com")
        let route = "/new/unrecognized%2Froute?tag=%E7%8C%AB&tag=x%2By#section%202"
        XCTAssertEqual(origin.resolve(route)?.absoluteString, "https://example.com" + route)
        XCTAssertNil(origin.resolve("//evil.test/a"))
        XCTAssertNil(origin.resolve("https://example.com:8443/"))
        XCTAssertNil(origin.resolve("javascript:alert(1)"))
    }
}
