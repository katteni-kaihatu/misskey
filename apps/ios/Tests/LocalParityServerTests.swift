// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
import GridSpaceCore
import Network
import CryptoKit
import Security
import WebKit
import XCTest
@testable import GridSpace

@MainActor
final class LocalParityServerTests: XCTestCase {
    private let arguments = ["--ui-testing", "--local-parity-server"]
    private var environment: [String: String] {
        ["GRIDSPACE_PARITY_ORIGIN": "https://192.168.2.3:61813",
         "GRIDSPACE_PARITY_STORE": "f1a1e7a1-8ab2-4052-85f0-c9c9985db55c",
         "GRIDSPACE_PARITY_CERT_SHA256": String(repeating: "ab", count: 32),
         "GRIDSPACE_PARITY_HTTP_USER": "synthetic-test",
         "GRIDSPACE_PARITY_HTTP_PASSWORD": String(repeating: "synthetic", count: 8)]
    }

    func testRequiresExplicitTestArgumentsAndCompleteConfiguration() {
        XCTAssertNotNil(LocalParityServer(arguments: arguments, environment: environment))
        for args in [[], ["--ui-testing"], ["--local-parity-server"], arguments + ["--compatibility-fixture"]] {
            XCTAssertNil(LocalParityServer(arguments: args, environment: environment))
        }
        for key in environment.keys {
            var missing = environment
            missing.removeValue(forKey: key)
            XCTAssertNil(LocalParityServer(arguments: arguments, environment: missing))
        }
    }

    func testRejectsPublicOrMalformedHostsAndIncompletePins() {
        for origin in ["http://192.168.2.3", "https://example.com", "https://192.168.2.3.example.com",
                       "https://192.168.2.300", "https://192.168..3", "https://192.168.2.3/path", "https://[2001:db8::1]", "https://g.ios-parity.test:61813"] {
            var changed = environment
            changed["GRIDSPACE_PARITY_ORIGIN"] = origin
            XCTAssertNil(LocalParityServer(arguments: arguments, environment: changed))
        }
        var wired = environment
        wired["GRIDSPACE_PARITY_ORIGIN"] = "https://[fd12:3456::2]:61813"
        XCTAssertNotNil(LocalParityServer(arguments: arguments, environment: wired))
        for hash in ["", "ab", String(repeating: "z", count: 64)] {
            var changed = environment
            changed["GRIDSPACE_PARITY_CERT_SHA256"] = hash
            XCTAssertNil(LocalParityServer(arguments: arguments, environment: changed))
        }
    }

    func testBasicCredentialIsConfinedToExactHTTPSOriginAndSession() throws {
        let config = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: environment))
        let space = URLProtectionSpace(host: "192.168.2.3", port: 61813, protocol: "https", realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let credential = try XCTUnwrap(config.credential(for: space))
        XCTAssertEqual(credential.persistence, .forSession)
        XCTAssertEqual(credential.user, "synthetic-test")
        for foreign in [
            URLProtectionSpace(host: "192.168.2.30", port: 61813, protocol: "https", realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "192.168.2.3", port: 61814, protocol: "https", realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "192.168.2.3", port: 61813, protocol: "http", realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
        ] { XCTAssertNil(config.credential(for: foreign)) }
        let missingTrust = URLProtectionSpace(host: "192.168.2.3", port: 61813, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        XCTAssertNil(config.credential(for: missingTrust))
    }

    func testNamedStoreIsIsolatedFromDefaultAndOrdinaryTests() throws {
        let config = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: environment))
        let store = config.dataStore()
        if #available(iOS 17.0, *) {
            XCTAssertEqual(store.identifier, config.storeID)
            XCTAssertNil(WKWebsiteDataStore.default().identifier)
        }
        XCTAssertNil(LocalParityServer.current)
    }

    func testDebugTLSExceptionsAreConfinedToTwoReservedFixtureNames() throws {
        let ats = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any])
        XCTAssertEqual(Set(ats.keys), ["NSExceptionDomains"])
        let domains = try XCTUnwrap(ats["NSExceptionDomains"] as? [String: [String: Any]])
        XCTAssertEqual(Set(domains.keys), ["g.ios-parity.test", "r.ios-parity.test"])
        for domain in domains.values {
            XCTAssertEqual(Set(domain.keys), ["NSExceptionAllowsInsecureHTTPLoads"])
            XCTAssertEqual(domain["NSExceptionAllowsInsecureHTTPLoads"] as? Bool, true)
        }
    }

    func testPeerPinsAreCompleteAndNeverReceivePrimaryBasicCredentials() throws {
        for peer in ["https://example.com", environment["GRIDSPACE_PARITY_ORIGIN"]!] {
            var invalid = environment
            invalid["GRIDSPACE_PARITY_PEER_ORIGIN"] = peer
            invalid["GRIDSPACE_PARITY_PEER_CERT_SHA256"] = String(repeating: "cd", count: 32)
            XCTAssertNil(LocalParityServer(arguments: arguments, environment: invalid))
        }
        var paired = environment
        paired["GRIDSPACE_PARITY_PEER_ORIGIN"] = "https://192.168.2.3:61815"
        XCTAssertNil(LocalParityServer(arguments: arguments, environment: paired))
        paired["GRIDSPACE_PARITY_PEER_CERT_SHA256"] = String(repeating: "cd", count: 32)
        let config = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: paired))
        let peerBasic = URLProtectionSpace(host: "192.168.2.3", port: 61815, protocol: "https", realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        XCTAssertNil(config.credential(for: peerBasic))
        XCTAssertNil(config.controlRequest("revoke"))
        paired["GRIDSPACE_PARITY_PAIR_CONTROL"] = "v1"
        let control = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: paired))
        let request = try XCTUnwrap(control.controlRequest("revoke"))
        XCTAssertEqual(request.url?.absoluteString, "https://192.168.2.3:61813/__ios-private-parity/control/revoke")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(control.controlRequest("native-emoji-prepare"))
        XCTAssertNotNil(control.controlRequest("native-emoji-status"))
        XCTAssertNil(control.controlRequest("https://example.com"))
        XCTAssertNil(control.controlRequest("../other"))
    }

    func testProxyRequiresExplicitPairAndNeverFallsBackToDirectNetworking() throws {
        var paired = environment
        paired["GRIDSPACE_PARITY_ORIGIN"] = "https://g.ios-parity.test:61813"
        paired["GRIDSPACE_PARITY_PEER_ORIGIN"] = "https://r.ios-parity.test:61815"
        paired["GRIDSPACE_PARITY_PEER_CERT_SHA256"] = String(repeating: "cd", count: 32)
        paired["GRIDSPACE_PARITY_PROXY_ADDRESS"] = "fd12:3456::2"
        paired["GRIDSPACE_PARITY_PROXY_PASSWORD"] = String(repeating: "a", count: 64)
        XCTAssertNil(LocalParityServer(arguments: arguments, environment: paired))
        paired["GRIDSPACE_PARITY_PAIR_CONTROL"] = "v1"
        if #available(iOS 17.0, *) {
            let config = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: paired))
            let proxies = config.dataStore().proxyConfigurations
            XCTAssertEqual(proxies.count, 1)
            XCTAssertEqual(proxies.first?.allowFailover, false)
            XCTAssertEqual(proxies.first?.matchDomains, ["ios-parity.test"])
            var excluded: [String] = []
            if let proxy = proxies.first { nw_proxy_config_enumerate_excluded_domains(proxy._nw) { excluded.append(String(cString: $0)) } }
            XCTAssertEqual(excluded, [])
            let space = URLProtectionSpace(proxyHost: "fd12:3456::2", port: 61816, type: NSURLProtectionSpaceHTTPProxy,
                                           realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            XCTAssertEqual(config.credential(for: space)?.user, "paired-parity")
            XCTAssertTrue(config.handles(space))
            let otherPort = URLProtectionSpace(proxyHost: "fd12:3456::2", port: 61817, type: NSURLProtectionSpaceHTTPProxy,
                                               realm: "test", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            XCTAssertNil(config.credential(for: otherPort))
        } else { XCTAssertNil(LocalParityServer(arguments: arguments, environment: paired)) }
        for address in ["example.com", "2001:db8::1", "192.168.1.2", "fd12::2%bad"] {
            paired["GRIDSPACE_PARITY_PROXY_ADDRESS"] = address
            XCTAssertNil(LocalParityServer(arguments: arguments, environment: paired))
        }
    }

    func testPinnedTrustStillVerifiesHostAndCertificateValidity() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LocalParityCertificate", withExtension: "cer"))
        let data = try Data(contentsOf: url)
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        func trust(at date: String) throws -> SecTrust {
            var result: SecTrust?
            XCTAssertEqual(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "192.168.2.3" as CFString), &result), errSecSuccess)
            let value = try XCTUnwrap(result)
            let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: date))
            XCTAssertEqual(SecTrustSetVerifyDate(value, instant as CFDate), errSecSuccess)
            return value
        }
        var pinned = environment
        pinned["GRIDSPACE_PARITY_CERT_SHA256"] = hash
        let config = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: pinned))
        XCTAssertTrue(config.accepts(try trust(at: "2026-11-17T00:00:00Z")))
        XCTAssertFalse(config.accepts(try trust(at: "2026-11-30T00:00:00Z")))
        pinned["GRIDSPACE_PARITY_ORIGIN"] = "https://192.168.2.4:61813"
        let wrongHost = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: pinned))
        XCTAssertFalse(wrongHost.accepts(try trust(at: "2026-11-17T00:00:00Z")))
        pinned["GRIDSPACE_PARITY_CERT_SHA256"] = String(repeating: "0", count: 64)
        let wrongPin = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: pinned))
        XCTAssertFalse(wrongPin.accepts(try trust(at: "2026-11-17T00:00:00Z")))
        pinned = environment
        pinned["GRIDSPACE_PARITY_CERT_SHA256"] = hash
        pinned["GRIDSPACE_PARITY_PEER_ORIGIN"] = "https://192.168.2.3:61815"
        pinned["GRIDSPACE_PARITY_PEER_CERT_SHA256"] = hash
        let peer = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: pinned))
        XCTAssertTrue(peer.accepts(try trust(at: "2026-11-17T00:00:00Z"), for: try ServerOrigin("https://192.168.2.3:61815")))
        XCTAssertFalse(peer.accepts(try trust(at: "2026-11-17T00:00:00Z"), for: try ServerOrigin("https://192.168.2.3:61816")))
        pinned["GRIDSPACE_PARITY_PEER_CERT_SHA256"] = String(repeating: "0", count: 64)
        let wrongPeerPin = try XCTUnwrap(LocalParityServer(arguments: arguments, environment: pinned))
        XCTAssertFalse(wrongPeerPin.accepts(try trust(at: "2026-11-17T00:00:00Z"), for: try ServerOrigin("https://192.168.2.3:61815")))
    }
}
#endif
