// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public struct ClientCustomEmoji: Codable, Identifiable, Equatable, Sendable {
    public let name: String
    public let aliases: [String]
    public let category: String?
    public let url: String
    public let localOnly: Bool?
    public let isSensitive: Bool?
    public let roleIdsThatCanBeUsedThisEmojiAsReaction: [String]?
    public var id: String { name }
    public var shortcode: String { ":" + name + ":" }
    public var validName: Bool { !name.isEmpty && name.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 43 || $0 == 45 } }
    public func matches(_ query: String) -> Bool {
        ClientEmojiSearch.matches(query, in: [name] + aliases)
    }
    public func restriction(note: ClientNote, roles: Set<String>) -> String? {
        if note.isHidden == true || note.isPureRenote { return "このノートへのリアクションは実装中です" }
        if note.acceptsOnlyLike { return "このノートはいいねのみ受け付けます" }
        if localOnly == true && (note.user.host != nil || note.renote?.user.host != nil || (note.renoteId != nil && note.renote == nil)) { return "ローカルのノート専用です" }
        if isSensitive == true && ["nonSensitiveOnly", "nonSensitiveOnlyForLocalLikeOnlyForRemote"].contains(note.reactionAcceptance ?? "") { return "このノートはセンシティブな絵文字を受け付けません" }
        let required = Set(roleIdsThatCanBeUsedThisEmojiAsReaction ?? [])
        if !required.isEmpty && required.isDisjoint(with: roles) { return "利用ロールを確認できません" }
        return nil
    }
}

public struct ClientUnicodeEmoji: Decodable, Identifiable, Sendable {
    public let char: String
    public let name: String
    public let category: Int
    public let keywords: [String]
    public var id: String { char }
    public func matches(_ query: String) -> Bool { ClientEmojiSearch.matches(query, in: [char, name] + keywords) }
    public static let categories = ["顔・感情", "人・体", "動物・自然", "食べ物・飲み物", "活動", "旅行・場所", "もの", "記号", "旗"]
    public static let all: [ClientUnicodeEmoji] = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Emoji"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([ClientUnicodeEmoji].self, from: data) else { return [] }
        return items
    }()
}

public enum ClientEmojiSearch {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }
    public static func matches(_ query: String, in values: [String]) -> Bool {
        let terms = normalize(query).split(whereSeparator: { $0.isWhitespace })
        let text = values.map(normalize).joined(separator: " ")
        return terms.allSatisfy { text.contains($0) }
    }
    public static func localName(_ reaction: String) -> String? {
        guard reaction.hasPrefix(":"), reaction.hasSuffix(":"), reaction.count > 2 else { return nil }
        let name = String(reaction.dropFirst().dropLast())
        if name.hasSuffix("@.") { return String(name.dropLast(2)) }
        return name.contains("@") ? nil : name
    }
    public static func equivalent(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == b }
        return a == b || (localName(a) != nil && localName(a) == localName(b)) || a.replacingOccurrences(of: "\u{FE0F}", with: "") == b.replacingOccurrences(of: "\u{FE0F}", with: "")
    }
}

public struct ClientReactionState: Decodable, Sendable {
    public let noteId: String
    public let reactions: [String: Int]
    public let reactionEmojis: [String: String]
    public let myReaction: String?
    public let myReactions: [String]
    public let shared: Bool?
    public let complete: Bool?
    public let reactionVersions: [String: String]?
    public var isComplete: Bool { complete ?? (shared != true) }
    public var valid: Bool {
        myReactions.count <= 128 && reactions.count <= 4096 && reactions.values.allSatisfy { $0 >= 0 }
            && (myReaction == nil || myReactions.contains { ClientEmojiSearch.equivalent($0, myReaction) })
    }
}

public struct ClientNoteReaction: Decodable, Sendable {
    public let id: String
    public let type: String
    public let user: ClientUser
}
