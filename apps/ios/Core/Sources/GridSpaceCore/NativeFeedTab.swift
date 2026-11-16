// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public struct ClientChannel: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let isArchived: Bool?
    public let isSensitive: Bool?
}

public enum ClientFeedTab: Codable, Hashable, Identifiable, Sendable {
    case timeline(ClientTimeline)
    case channel(id: String, name: String)
    case peerChannel(origin: String, id: String, name: String)
    public var id: String {
        switch self {
        case .timeline(let kind): return kind.rawValue
        case .channel(let id, _): return "channel:" + id
        case .peerChannel(let origin, let id, _): return "peer-channel:" + ((try? ServerOrigin(origin).url.absoluteString) ?? origin) + ":" + id
        }
    }
    public var title: String {
        switch self {
        case .timeline(.home): return "ホーム"
        case .timeline(.local): return "ローカル"
        case .timeline(.global): return "グローバル"
        case .channel(_, let name): return name
        case .peerChannel(let origin, _, let name): return name + "（" + ((try? ServerOrigin(origin).authority) ?? origin) + "）"
        }
    }
    public static func defaults(signedIn: Bool) -> [Self] {
        (signedIn ? ClientTimeline.allCases : [.local, .global]).map(Self.timeline)
    }
    public static func normalized(_ tabs: [Self]) -> [Self] {
        var ids = Set<String>()
        let result = tabs.compactMap { tab -> Self? in
            guard ids.count < 20 else { return nil }
            let value: Self
            switch tab {
            case .timeline: value = tab
            case .channel(let id, let name):
                guard validChannelID(id) else { return nil }
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                value = .channel(id: id, name: title.isEmpty ? "チャンネル" : String(title.prefix(100)))
            case .peerChannel(let rawOrigin, let id, let name):
                guard validPeerID(id), let origin = try? ServerOrigin(rawOrigin) else { return nil }
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                value = .peerChannel(origin: origin.url.absoluteString, id: id, name: title.isEmpty ? "チャンネル" : String(title.prefix(100)))
            }
            return ids.insert(value.id).inserted ? value : nil
        }
        return result.isEmpty ? [.timeline(.local)] : result
    }
    public static func validPeerID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 32 && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }
    public static func validChannelID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}
