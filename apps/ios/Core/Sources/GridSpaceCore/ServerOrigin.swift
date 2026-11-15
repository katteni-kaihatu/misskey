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

        components.scheme = "https"
        components.host = parsedHost.lowercased()
        components.port = effectivePort == 443 ? nil : effectivePort
        components.path = "/"
        guard let normalized = components.url else {
            throw ValidationError.invalidOrigin
        }
        self.url = normalized
        self.host = parsedHost.lowercased()
        self.port = effectivePort
    }

    /// Origin equality is exact; lookalike domains and other ports are separate.
    public func contains(_ url: URL) -> Bool {
        guard let components = Self.webComponents(for: url),
              components.scheme?.lowercased() == "https",
              url.host?.lowercased() == host else { return false }
        return (components.port ?? 443) == port
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
}
