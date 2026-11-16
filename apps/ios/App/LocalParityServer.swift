// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
import CryptoKit
import Darwin
import GridSpaceCore
import Network
import Security
import WebKit

/// Opt-in physical-device tests against a private, synthetic PWA server.
/// No trust roots, real credentials, or default WebKit stores are changed.
struct LocalParityServer: Sendable {
    static let current = LocalParityServer(arguments: ProcessInfo.processInfo.arguments,
                                            environment: ProcessInfo.processInfo.environment)
    let origin: ServerOrigin
    let storeID: UUID
    let certificateHash: String
    let initialURL: URL
    private let username: String
    private let password: String
    private let peer: (origin: ServerOrigin, certificateHash: String)?
    private let pairControlEnabled: Bool
    private let proxy: (address: String, password: String)?

    init?(arguments: [String], environment: [String: String]) {
        guard arguments.contains("--ui-testing"), arguments.contains("--local-parity-server"),
              !arguments.contains("--compatibility-fixture"),
              let address = environment["GRIDSPACE_PARITY_ORIGIN"],
              let origin = try? ServerOrigin(address), Self.isFixtureHost(origin.host, environment: environment),
              let rawID = environment["GRIDSPACE_PARITY_STORE"], let storeID = UUID(uuidString: rawID),
              storeID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              let hash = environment["GRIDSPACE_PARITY_CERT_SHA256"], hash.count == 64,
              hash.allSatisfy({ $0.isASCII && ($0.isHexDigit) }),
              let username = environment["GRIDSPACE_PARITY_HTTP_USER"], !username.isEmpty, !username.contains(":"),
              let password = environment["GRIDSPACE_PARITY_HTTP_PASSWORD"], password.count >= 32 else { return nil }
        self.origin = origin
        self.storeID = storeID
        certificateHash = hash.lowercased()
        self.username = username
        self.password = password
        let peerAddress = environment["GRIDSPACE_PARITY_PEER_ORIGIN"]
        let peerHash = environment["GRIDSPACE_PARITY_PEER_CERT_SHA256"]
        if peerAddress != nil || peerHash != nil {
            guard let peerAddress, let peerOrigin = try? ServerOrigin(peerAddress), peerOrigin != origin,
                  Self.isFixtureHost(peerOrigin.host, environment: environment), let peerHash, peerHash.count == 64,
                  peerHash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            peer = (peerOrigin, peerHash.lowercased())
        } else { peer = nil }
        pairControlEnabled = environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1"
        let proxyAddress = environment["GRIDSPACE_PARITY_PROXY_ADDRESS"]
        let proxyPassword = environment["GRIDSPACE_PARITY_PROXY_PASSWORD"]
        if proxyAddress != nil || proxyPassword != nil {
            guard #available(iOS 17.0, *), pairControlEnabled, peer != nil,
                  let proxyAddress, !proxyAddress.contains("%"), (proxyAddress == "127.0.0.1" || proxyAddress.contains(":")), Self.isPrivateHost(proxyAddress),
                  let proxyPassword, proxyPassword.count == 64, proxyPassword.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  origin.host == "g.ios-parity.test", peer?.origin.host == "r.ios-parity.test",
                  origin.port == 61813, peer?.origin.port == 61815 else { return nil }
            proxy = (proxyAddress, proxyPassword)
        } else { proxy = nil }
        let path = environment["GRIDSPACE_PARITY_PATH"] ?? "/"
        guard path.hasPrefix("/"), !path.hasPrefix("//"), let initialURL = origin.resolve(path) else { return nil }
        self.initialURL = initialURL
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        // Explicit addresses avoid DNS redirection. ULA IPv6 also permits the
        // paired device's USB tunnel. A matching certificate remains mandatory.
        if host.contains(":") {
            var address = in6_addr()
            guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return false }
            return withUnsafeBytes(of: address) { $0[0] & 0xfe == 0xfc }
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ UInt8($0) != nil }) else { return false }
        let bytes = parts.compactMap { UInt8($0) }
        return bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168) || host == "127.0.0.1"
    }

    private static func isFixtureHost(_ host: String, environment: [String: String]) -> Bool {
        isPrivateHost(host) || (environment["GRIDSPACE_PARITY_PAIR_CONTROL"] == "v1"
            && environment["GRIDSPACE_PARITY_PROXY_ADDRESS"] != nil
            && ["g.ios-parity.test", "r.ios-parity.test"].contains(host))
    }

    func matches(_ space: URLProtectionSpace) -> Bool {
        matches(space, origin: origin)
    }

    private func matches(_ space: URLProtectionSpace, origin: ServerOrigin) -> Bool {
        space.host.lowercased() == origin.host && space.port == origin.port && space.protocol == "https"
    }

    func handles(_ space: URLProtectionSpace) -> Bool {
        if matches(space) { return true }
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let peer, matches(space, origin: peer.origin) { return true }
        return space.authenticationMethod == NSURLAuthenticationMethodHTTPBasic && space.isProxy()
            && proxy.map { space.host.lowercased() == $0.address && space.port == 61816 } == true
    }

    /// Only the synthetic paired fixture understands these fixed operations.
    /// The secret stays in the test runner's native URLSession, outside WebKit.
    func controlRequest(_ action: String) -> URLRequest? {
        guard pairControlEnabled, peer != nil, ["status", "rename", "revoke", "authorize", "native-auth", "native-status", "native-attachment-status", "native-social-prepare", "native-social-status", "native-profile-prepare", "native-profile-status", "native-actions-prepare", "native-actions-restrict", "native-actions-status", "native-notifications-prepare", "native-notifications-status", "native-auth-notifications-read-only", "native-emoji-prepare", "native-emoji-status"].contains(action),
              let url = origin.resolve("/__ios-private-parity/control/" + action) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(password, forHTTPHeaderField: "X-Gridspace-Parity-Control")
        return request
    }

    func wifiAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }
        var next = interfaces
        while let current = next {
            defer { next = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == "en0", let address = current.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    func credential(for space: URLProtectionSpace) -> URLCredential? {
        if space.authenticationMethod == NSURLAuthenticationMethodHTTPBasic {
            if let proxy, space.isProxy(), space.host.lowercased() == proxy.address,
               space.port == 61816 {
                return URLCredential(user: "paired-parity", password: proxy.password, persistence: .forSession)
            }
            guard matches(space) else { return nil }
            return URLCredential(user: username, password: password, persistence: .forSession)
        }
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust else { return nil }
        let candidate = matches(space) ? origin : peer.flatMap { matches(space, origin: $0.origin) ? $0.origin : nil }
        guard let candidate, accepts(trust, for: candidate) else { return nil }
        return URLCredential(trust: trust)
    }

    func evaluatedCredential(for space: URLProtectionSpace) async -> URLCredential? {
        // Security.framework trust evaluation can block on trustd. WebKit's
        // delegate is on the main actor; keep the UI responsive during loading.
        await Task.detached(priority: .userInitiated) { credential(for: space) }.value
    }

    func accepts(_ trust: SecTrust) -> Bool {
        accepts(trust, for: origin)
    }

    func accepts(_ trust: SecTrust, for candidate: ServerOrigin) -> Bool {
        let hash: String
        if candidate == origin { hash = certificateHash }
        else if let peer, candidate == peer.origin { hash = peer.certificateHash }
        else { return false }
        return Self.accepts(trust, origin: candidate, certificateHash: hash)
    }

    private static func accepts(_ trust: SecTrust, origin: ServerOrigin, certificateHash: String) -> Bool {
        // Copy the evaluated chain, including a self-signed leaf. Initial
        // system trust may fail; no credential is returned until the pin AND
        // the subsequent scoped evaluation succeed. Do not fetch network data.
        guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        var chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        if chain?.isEmpty != false {
            _ = SecTrustEvaluateWithError(trust, nil)
            chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        }
        guard let certificate = chain?.first else {
            NSLog("Local parity trust: certificate unavailable")
            return false
        }
        let bytes = SecCertificateCopyData(certificate) as Data
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard hash == certificateHash else {
            NSLog("Local parity trust: pin mismatch")
            return false
        }
        // Pin the exact temporary leaf, and still verify its validity, signature
        // and host. This anchor is scoped to this challenge, never the keychain.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, origin.host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else { return false }
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            if let error { NSLog("Local parity trust failure: %@ %ld", CFErrorGetDomain(error) as String, CFErrorGetCode(error)) }
            return false
        }
        return true
    }

    @MainActor func dataStore() -> WKWebsiteDataStore {
        if #available(iOS 17.0, *) {
            return configureDataStore(WKWebsiteDataStore(forIdentifier: storeID))
        }
        return .nonPersistent() // Restart persistence is not claimed on older OSes.
    }

    @MainActor func configureDataStore(_ store: WKWebsiteDataStore) -> WKWebsiteDataStore {
        if #available(iOS 17.0, *), let configuration = proxyConfiguration() { store.proxyConfigurations = [configuration] }
        return store
    }

    @available(iOS 17.0, *)
    private func proxyConfiguration() -> ProxyConfiguration? {
        guard let proxy else { return nil }
        var configuration = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .init(proxy.address), port: 61816))
        configuration.allowFailover = false
        configuration.matchDomains = ["ios-parity.test"]
        nw_proxy_config_clear_excluded_domains(configuration._nw)
        configuration.applyCredential(username: "paired-parity", password: proxy.password)
        return configuration
    }

    func configureControlSession(_ configuration: URLSessionConfiguration) {
        if #available(iOS 17.0, *), let proxy = proxyConfiguration() { configuration.proxyConfigurations = [proxy] }
    }
}
#endif
