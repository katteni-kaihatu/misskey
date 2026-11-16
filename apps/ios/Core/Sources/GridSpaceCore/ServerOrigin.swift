// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// The HTTPS origin selected by the user, without any authentication material.
public struct ServerOrigin: Hashable, Sendable {
    public enum ValidationError: Error, Equatable {
        case invalidOrigin
    }

    public let url: URL
    public let host: String
    public let port: Int

    /// Browser location.host syntax, including brackets around IPv6 literals.
    public var authority: String {
        let name = host.contains(":") ? "[\(host)]" : host
        return port == 443 ? name : "\(name):\(port)"
    }

    /// Accepts an HTTPS origin or a bare host, optionally followed by a port.
    public init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\\"),
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ValidationError.invalidOrigin
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let parsedURL = components.url,
              let parsedHost = parsedURL.host, !parsedHost.isEmpty,
              components.percentEncodedHost?.contains("%") != true else {
            throw ValidationError.invalidOrigin
        }
        let effectivePort = components.port ?? 443
        guard (1...65535).contains(effectivePort) else {
            throw ValidationError.invalidOrigin
        }

        let normalizedHost = Self.unbracket(parsedHost.lowercased())
        components.scheme = "https"
        components.host = normalizedHost.contains(":") ? "[\(normalizedHost)]" : normalizedHost
        components.port = effectivePort == 443 ? nil : effectivePort
        components.path = "/"
        guard let normalized = components.url else {
            throw ValidationError.invalidOrigin
        }
        self.url = normalized
        self.host = normalizedHost
        self.port = effectivePort
    }

    /// Origin equality is exact; lookalike domains and other ports are separate.
    public func contains(_ url: URL) -> Bool {
        guard let components = Self.webComponents(for: url),
              components.scheme?.lowercased() == "https",
              url.host.map({ Self.unbracket($0.lowercased()) }) == host else { return false }
        return (components.port ?? 443) == port
    }

    public func containsBlob(_ url: URL) -> Bool {
        guard let source = Self.blobSourceURL(url) else { return false }
        return contains(source)
    }

    static func blobSourceURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "blob" else { return nil }
        // Foundation's Swift and CFURL parsers escape IPv6 Blob URLs
        // differently. Repair only the scheme colon and IPv6 brackets;
        // never decode arbitrary host delimiters, credentials or Blob IDs.
        var embedded = String(url.absoluteString.dropFirst(5))
        for scheme in ["https", "http"] {
            let escapedScheme = scheme + "%3a//"
            if embedded.lowercased().hasPrefix(escapedScheme) {
                embedded = scheme + "://" + embedded.dropFirst(escapedScheme.count)
            }
            let escapedHost = scheme + "://%5b"
            if embedded.lowercased().hasPrefix(escapedHost) {
                let hostStart = embedded.index(embedded.startIndex, offsetBy: escapedHost.count)
                guard let end = embedded.range(of: "%5d", options: .caseInsensitive, range: hostStart..<embedded.endIndex) else { return nil }
                let literal = embedded[hostStart..<end.lowerBound]
                guard !literal.isEmpty, literal.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == ":" || $0 == ".") }) else { return nil }
                embedded = scheme + "://[" + literal + "]" + embedded[end.upperBound...]
            }
        }
        guard let source = URL(string: embedded),
              webComponents(for: source) != nil else { return nil }
        return source
    }

    /// Keeps encoded paths, queries and fragments intact for known and unknown routes.
    public func resolve(_ reference: String) -> URL? {
        guard let resolved = URL(string: reference, relativeTo: url)?.absoluteURL,
              contains(resolved) else { return nil }
        return resolved
    }

    static func webComponents(for url: URL) -> URLComponents? {
        guard !url.absoluteString.contains("\\"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.percentEncodedHost?.contains("%") != true,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        return components
    }

    private static func unbracket(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
}
