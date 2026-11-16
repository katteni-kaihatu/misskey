// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public struct MFMNode: Decodable, Equatable, Sendable {
    public struct Properties: Decodable, Equatable, Sendable {
        public let text: String?
        public let code: String?
        public let lang: String?
        public let formula: String?
        public let name: String?
        public let emoji: String?
        public let url: String?
        public let username: String?
        public let host: String?
        public let acct: String?
        public let hashtag: String?
        public let query: String?
        public let content: String?
        public let args: [String: Argument]?
    }
    public enum Argument: Decodable, Equatable, Sendable {
        case text(String), flag(Bool)
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) { self = .text(text) }
            else { self = .flag(try value.decode(Bool.self)) }
        }
        public var text: String? { if case .text(let value) = self { return value }; return nil }
    }
    public let type: String
    public let props: Properties?
    public let children: [MFMNode]?
}

public enum MFMError: Error, Equatable, Sendable { case tooLarge, unavailable, invalidResult }

/// The same trusted parser as the Web client, without a WebView, native bindings,
/// module loader, network, timers, or a persistent cache of parsed note contents.
/// Each operation owns and releases its JS context; UGC is passed only as data.
public actor MFMParser {
    public static let shared = MFMParser()
    public static let maximumUTF8Bytes = 16 * 1024
    private let source: String?

    public init() {
        source = Bundle.module.url(forResource: "Parser", withExtension: "js", subdirectory: "MFM")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    public func parse(_ text: String) throws -> [MFMNode] {
        try Task.checkCancellation()
        guard text.utf8.count <= Self.maximumUTF8Bytes else { throw MFMError.tooLarge }
        #if canImport(JavaScriptCore)
        guard let source, let context = JSContext() else { throw MFMError.unavailable }
        context.evaluateScript(source)
        guard context.exception == nil, let function = context.objectForKeyedSubscript("gridspaceParseMFM"),
              !function.isUndefined else { throw MFMError.unavailable }
        let result = function.call(withArguments: [text])
        try Task.checkCancellation()
        guard context.exception == nil, let json = result?.toString(), let data = json.data(using: .utf8),
              data.count <= 4 * 1024 * 1024 else { throw MFMError.invalidResult }
        let nodes = try JSONDecoder().decode([MFMNode].self, from: data)
        var count = 0
        func validate(_ children: [MFMNode], depth: Int) throws {
            guard depth <= 40 else { throw MFMError.invalidResult }
            count += children.count
            guard count <= 8192 else { throw MFMError.invalidResult }
            for node in children { if let nested = node.children { try validate(nested, depth: depth + 1) } }
        }
        try validate(nodes, depth: 0)
        return nodes
        #else
        throw MFMError.unavailable
        #endif
    }
}

/// Links are built from parsed data with component encoding, never by treating
/// a mention, hashtag or emoji name as a path or executable URL.
public enum MFMLinks {
    public static func external(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private static func route(origin: ServerOrigin, segments: [String]) -> URL {
        var components = URLComponents(url: origin.url, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~@"))
        components.percentEncodedPath = "/" + segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        return components.url!
    }
    public static func mention(origin: ServerOrigin, username: String, host: String?, authorHost: String?) -> URL {
        route(origin: origin, segments: ["@" + username + ((host ?? authorHost).map { "@" + $0 } ?? "")])
    }
    public static func hashtag(origin: ServerOrigin, tag: String) -> URL { route(origin: origin, segments: ["tags", tag]) }
    public static func search(origin: ServerOrigin, query: String) -> URL {
        var components = URLComponents(url: origin.url, resolvingAgainstBaseURL: false)!
        components.path = "/search"; components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
    public static func emoji(origin: ServerOrigin, name: String, authorHost: String?, urls: [String: String]) -> URL? {
        // Extended reaction maps retain the local @. qualifier. Prefer the
        // supplied animation URL to requesting another proxy representation.
        if let value = urls[name] ?? (authorHost == nil ? urls[name + "@."] : nil) {
            return external(value).flatMap { $0.scheme == "https" ? $0 : nil }
        }
        guard authorHost == nil, !name.isEmpty,
              name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-").contains($0) }) else { return nil }
        return route(origin: origin, segments: ["emoji", name + ".webp"])
    }
}
