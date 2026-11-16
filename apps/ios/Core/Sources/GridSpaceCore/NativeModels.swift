// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public struct ClientUser: Decodable, Identifiable, Sendable {
    public struct Role: Decodable, Sendable { public let id: String }
    public let roles: [Role]?
    public struct Policies: Decodable, Sendable { public let maxFileSizeMb: Int? }
    public struct Field: Decodable, Sendable { public let name: String; public let value: String }
    public let id: String
    public let username: String
    public let name: String?
    public let host: String?
    public let avatarUrl: String?
    public let description: String?
    public let followersCount: Int?
    public let followingCount: Int?
    public let notesCount: Int?
    public let emojis: [String: String]?
    public let policies: Policies?
    public let bannerUrl: String?
    public let fields: [Field]?
    public let isLocked: Bool?
    public let isBot: Bool?
    public let movedTo: String?
    public let isFollowing: Bool?
    public let isFollowed: Bool?
    public let hasPendingFollowRequestFromYou: Bool?
    public let isBlocking: Bool?
    public let isBlocked: Bool?
    public let unreadNotificationsCount: Int?
    public let hasUnreadNotification: Bool?
    public var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? username }
    public var handle: String { "@" + username + (host.map { "@" + $0 } ?? "") }
    public func followAction(viewer: String) -> ClientFollowAction? {
        guard id != viewer, let following = isFollowing, let pending = hasPendingFollowRequestFromYou else { return nil }
        if following { return .unfollow }
        if pending { return .cancelRequest }
        guard movedTo == nil, isBlocking != true, isBlocked != true, let locked = isLocked else { return nil }
        return locked ? .request : .follow
    }
}

public enum ClientFollowAction: String, Sendable {
    case follow, request, unfollow, cancelRequest
    public var endpoint: String {
        switch self {
        case .follow, .request: return "following/create"
        case .unfollow: return "following/delete"
        case .cancelRequest: return "following/requests/cancel"
        }
    }
}

public enum ClientProfileFilter: String, CaseIterable, Identifiable, Sendable {
    case posts, replies, media
    public var id: String { rawValue }
}

public enum ClientPeopleKind: String, Hashable, Sendable {
    case following, followers
    public var endpoint: String { "users/" + rawValue }
}

public struct ClientFollowing: Decodable, Identifiable, Sendable {
    public let id: String
    public let followeeId: String
    public let followerId: String
    public let followee: ClientUser?
    public let follower: ClientUser?
    public func person(owner: String, kind: ClientPeopleKind) -> ClientUser? {
        switch kind {
        case .following: return followerId == owner && followee?.id == followeeId ? followee : nil
        case .followers: return followeeId == owner && follower?.id == followerId ? follower : nil
        }
    }
}

public struct ClientFile: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let url: String?
    public let thumbnailUrl: String?
    public let isSensitive: Bool
    public let comment: String?
    public let size: Int?
    public let userId: String?
}

public final class ClientNote: Decodable, Identifiable, Sendable {
    public let id: String
    public let createdAt: String
    public let text: String?
    public let cw: String?
    public let visibility: String
    public let user: ClientUser
    public let files: [ClientFile]?
    public let renote: ClientNote?
    public let repliesCount: Int?
    public let renoteCount: Int?
    public let reactions: [String: Int]?
    public let myReaction: String?
    public let myReactions: [String]?
    public let extendedReactions: Bool?
    public let reactionStateComplete: Bool?
    public let reactionAcceptance: String?
    public let reactionEmojis: [String: String]?
    public let reactionVersions: [String: String]?
    public let gridspaceReactions: Bool?
    public let gridspaceShared: Bool?
    public struct Channel: Decodable, Sendable { public let id: String }
    public let channel: Channel?
    public let replyId: String?
    public let renoteId: String?
    public let channelId: String?
    public let localOnly: Bool?
    public let poll: ClientPoll?
    public let emojis: [String: String]?

    public var supportsExtendedReactions: Bool {
        extendedReactions == true || user.host == nil || gridspaceReactions == true
            || (gridspaceShared == true && channelId == nil && channel == nil && ["public", "home"].contains(visibility))
    }
    /// Peer policy is evaluated as a remote reactor at the owning server.
    /// Peer-authored local channel posts use this server's local policy.
    public var acceptsOnlyLike: Bool {
        if reactionAcceptance == "likeOnly" { return true }
        let localChannelActor = gridspaceReactions == true && localOnly == true && (channelId != nil || channel != nil)
        return user.host != nil && !localChannelActor && ["likeOnlyForRemote", "nonSensitiveOnlyForLocalLikeOnlyForRemote"].contains(reactionAcceptance ?? "")
    }
    public var ownReactions: [String] {
        (myReactions ?? myReaction.map { [$0] } ?? []).reduce(into: []) { values, value in
            if !values.contains(where: { ClientEmojiSearch.equivalent($0, value) }) { values.append(value) }
        }
    }
    public func hasOwnReaction(_ value: String) -> Bool { ownReactions.contains { ClientEmojiSearch.equivalent($0, value) } }

    /// A new immutable note keeps reaction state scoped to this read/owner.
    public func applyingReactions(_ state: ClientReactionState?) -> ClientNote { ClientNote(copying: self, state: state) }
    public func applyingLiveReactions(_ state: ClientReactionState) -> ClientNote { ClientNote(copying: self, state: state, capability: supportsExtendedReactions) }
    public func hiding() -> ClientNote { ClientNote(copying: self, state: nil, projection: nil, hidden: true, capability: supportsExtendedReactions) }
    public func projectingReaction(_ value: String, adding: Bool, emojiURL: String? = nil) -> ClientNote {
        ClientNote(copying: self, state: nil, projection: (value, adding, emojiURL))
    }
    private init(copying note: ClientNote, state: ClientReactionState?, projection: (String, Bool, String?)? = nil, hidden: Bool? = nil, capability: Bool? = nil) {
        id = note.id
        createdAt = note.createdAt
        text = note.text
        cw = note.cw
        visibility = note.visibility
        user = note.user
        files = note.files
        renote = note.renote
        repliesCount = note.repliesCount
        renoteCount = note.renoteCount
        reactionAcceptance = note.reactionAcceptance
        gridspaceReactions = note.gridspaceReactions
        gridspaceShared = note.gridspaceShared
        channel = note.channel
        replyId = note.replyId
        renoteId = note.renoteId
        channelId = note.channelId
        localOnly = note.localOnly
        poll = note.poll
        emojis = note.emojis
        isHidden = hidden ?? note.isHidden
        reactionVersions = state?.reactionVersions ?? note.reactionVersions
        if let (value, adding, emojiURL) = projection {
            var counts = note.reactions ?? [:], own = note.ownReactions
            func remove(_ reaction: String) {
                if let key = counts.keys.first(where: { ClientEmojiSearch.equivalent($0, reaction) }) {
                    let count = max(0, (counts[key] ?? 0) - 1)
                    if count == 0 { counts.removeValue(forKey: key) } else { counts[key] = count }
                }
                own.removeAll { ClientEmojiSearch.equivalent($0, reaction) }
            }
            if adding && !note.hasOwnReaction(value) {
                if !note.supportsExtendedReactions { for old in own { remove(old) } }
                let key = counts.keys.first(where: { ClientEmojiSearch.equivalent($0, value) }) ?? value
                counts[key, default: 0] += 1; own.append(key)
            } else if !adding && note.hasOwnReaction(value) { remove(value) }
            reactions = counts; myReactions = own
            myReaction = note.supportsExtendedReactions ? note.myReaction.flatMap { old in own.contains(where: { ClientEmojiSearch.equivalent($0, old) }) ? old : nil } : own.first
            var urls = note.reactionEmojis ?? [:]
            if let name = ClientEmojiSearch.localName(value), let emojiURL { urls[name + "@."] = emojiURL; urls[name] = emojiURL }
            reactionEmojis = urls
            extendedReactions = note.extendedReactions; reactionStateComplete = note.reactionStateComplete
        } else {
            reactions = state?.reactions ?? note.reactions
            reactionEmojis = state?.reactionEmojis ?? note.reactionEmojis
            myReaction = state == nil ? note.myReaction : state!.myReaction
            myReactions = state?.myReactions
            extendedReactions = capability ?? true
            reactionStateComplete = state?.isComplete ?? false
        }
    }

    public var date: Date? { ISO8601DateFormatter().date(from: createdAt) ?? Self.fractionalDate(createdAt) }
    public let isHidden: Bool?
    public var isPureRenote: Bool {
        (renoteId != nil || renote != nil) && replyId == nil && text == nil && cw == nil && (files ?? []).isEmpty && poll == nil
    }
    public var reshareTarget: ClientNote? {
        guard isHidden != true else { return nil }
        guard isPureRenote else { return self }
        guard let renote, renote.isHidden != true, !renote.isPureRenote,
              renoteId == nil || renoteId == renote.id else { return nil }
        return renote
    }
    public func reshareVisibilities(viewer: String) -> [String] {
        guard isHidden != true, !isPureRenote, channelId == nil else { return [] }
        switch visibility {
        case "public": return ["public", "home", "followers"]
        case "home": return ["home", "followers"]
        case "followers": return user.id == viewer ? ["followers"] : []
        default: return []
        }
    }
    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

public struct ClientPoll: Decodable, Equatable, Sendable {
    public struct Choice: Decodable, Equatable, Sendable {
        public let text: String
        public let votes: Int
        public let isVoted: Bool?
    }
    public let choices: [Choice]
    public let multiple: Bool
    public let expiresAt: String?
    public var expiration: Date? {
        guard let expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
    }
    public func closed(at now: Date) -> Bool {
        guard expiresAt != nil else { return false }
        // Unknown date formats must not accidentally open an expired poll.
        return expiration.map { $0 <= now } ?? true
    }
    public func canVote(_ choice: Int, at now: Date) -> Bool {
        choices.indices.contains(choice) && !closed(at: now) && choices[choice].isVoted != true
            && (multiple || !choices.contains { $0.isVoted == true })
    }
    public var totalVotes: Int { choices.reduce(0) { total, choice in total.addingReportingOverflow(max(0, choice.votes)).overflow ? Int.max : total + max(0, choice.votes) } }
}

public struct ClientNotification: Decodable, Identifiable, Sendable {
    public struct Role: Decodable, Sendable { public let id: String; public let name: String }
    public struct Invitation: Decodable, Sendable {
        public struct Room: Decodable, Sendable { public let id: String; public let name: String }
        public let room: Room
    }
    public let id: String
    public let type: String
    public let user: ClientUser?
    public let note: ClientNote?
    public let reaction: String?
    public let createdAt: String
    public let header: String?
    public let body: String?
    public let message: String?
    public let role: Role?
    public let invitation: Invitation?
    public let achievement: String?
    public let exportedEntity: String?
    public let fileId: String?
    public func replacingNote(_ note: ClientNote) -> ClientNotification { ClientNotification(copying: self, note: note) }
    private init(copying item: ClientNotification, note: ClientNote) {
        self.note = note
        id = item.id
        type = item.type
        user = item.user
        reaction = item.reaction
        createdAt = item.createdAt
        header = item.header
        body = item.body
        message = item.message
        role = item.role
        invitation = item.invitation
        achievement = item.achievement
        exportedEntity = item.exportedEntity
        fileId = item.fileId
    }
    private enum CodingKeys: String, CodingKey { case id, type, user, note, reaction, createdAt, header, body, message, role, invitation, achievement, exportedEntity, fileId }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decode(String.self, forKey: .type)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        // A future notification may reuse payload names with different types.
        // Keep its envelope and Web route without interpreting that payload.
        if ClientNotificationKind(rawValue: type) == nil {
            user = nil; note = nil; reaction = nil; header = nil; body = nil; message = nil
            role = nil; invitation = nil; achievement = nil; exportedEntity = nil; fileId = nil
            return
        }
        user = try values.decodeIfPresent(ClientUser.self, forKey: .user)
        note = try values.decodeIfPresent(ClientNote.self, forKey: .note)
        reaction = try values.decodeIfPresent(String.self, forKey: .reaction)
        header = try values.decodeIfPresent(String.self, forKey: .header)
        body = try values.decodeIfPresent(String.self, forKey: .body)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        role = try values.decodeIfPresent(Role.self, forKey: .role)
        invitation = try values.decodeIfPresent(Invitation.self, forKey: .invitation)
        achievement = try values.decodeIfPresent(String.self, forKey: .achievement)
        exportedEntity = try values.decodeIfPresent(String.self, forKey: .exportedEntity)
        fileId = try values.decodeIfPresent(String.self, forKey: .fileId)
    }
    public var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }
    public var kind: ClientNotificationKind? { ClientNotificationKind(rawValue: type) }
    public var detailWebPath: String {
        switch kind {
        case .achievementEarned: return "/my/achievements"
        case .createToken: return "/settings/apps"
        case .chatRoomInvitationReceived: return "/chat"
        case .exportCompleted:
            if let fileId, !fileId.isEmpty, fileId.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) { return "/my/drive/file/" + fileId }
            return "/my/notifications"
        default: return "/my/notifications"
        }
    }
}

public enum ClientNotificationKind: String, CaseIterable, Hashable, Sendable {
    case note, follow, mention, reply, renote, quote, reaction, pollEnded
    case scheduledNotePosted, scheduledNotePostFailed, receiveFollowRequest, followRequestAccepted
    case roleAssigned, chatRoomInvitationReceived, achievementEarned, exportCompleted, login, createToken, app, test
    public var title: String {
        switch self {
        case .note: return "新しい投稿"
        case .follow: return "フォロー"
        case .mention: return "メンション"
        case .reply: return "返信"
        case .renote: return "リノート"
        case .quote: return "引用"
        case .reaction: return "リアクション"
        case .pollEnded: return "投票終了"
        case .scheduledNotePosted: return "予約投稿の完了"
        case .scheduledNotePostFailed: return "予約投稿の失敗"
        case .receiveFollowRequest: return "フォロー申請"
        case .followRequestAccepted: return "フォロー申請の承認"
        case .roleAssigned: return "ロールの付与"
        case .chatRoomInvitationReceived: return "チャットへの招待"
        case .achievementEarned: return "実績の獲得"
        case .exportCompleted: return "エクスポートの完了"
        case .login: return "ログイン"
        case .createToken: return "アクセストークンの作成"
        case .app: return "アプリ通知"
        case .test: return "テスト通知"
        }
    }
}

public enum ClientTimeline: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, local, global
    public var id: String { rawValue }
    public var endpoint: String {
        switch self {
        case .home: return "notes/timeline"
        case .local: return "notes/local-timeline"
        case .global: return "notes/global-timeline"
        }
    }
}

public enum ClientAPIError: Error, Equatable, Sendable {
    case rejected(status: Int, code: String)
    case invalidResponse
    case responseTooLarge
    case notAuthenticated
    case keychain(Int32)
}

/// Stable pagination: duplicate boundary notes keep their first position.
public func appendClientNotes(_ page: [ClientNote], to notes: [ClientNote]) -> [ClientNote] {
    var ids = Set(notes.map(\.id))
    return notes + page.filter { ids.insert($0.id).inserted }
}

public enum MiAuthConfiguration {
    public static let callbackScheme = "gridspace-auth"
    public static let permissions = ["read:account", "write:notes", "read:notifications", "write:reactions", "read:drive", "write:drive", "write:votes", "write:following", "write:notifications", "read:gridspace-private"]

    public static func authorizationURL(origin: ServerOrigin, session: UUID) -> URL {
        let identifier = session.uuidString.lowercased()
        var url = URLComponents(url: origin.url.appendingPathComponent("miauth/" + identifier), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "name", value: "ぐりすぺ iOS"),
                          URLQueryItem(name: "callback", value: callbackScheme + "://complete?state=" + identifier),
                          URLQueryItem(name: "permission", value: permissions.joined(separator: ","))]
        return url.url!
    }

    public static func acceptsCallback(_ url: URL, session: UUID) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == callbackScheme, components.host == "complete",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil else { return false }
        let states = components.queryItems?.filter { $0.name == "state" } ?? []
        return states.count == 1 && states[0].value.flatMap(UUID.init(uuidString:)) == session
    }
}

public enum ClientWebEditor {
    public static func url(origin: ServerOrigin, text: String, cw: String?, visibility: String, replyId: String?, renoteId: String? = nil, localOnly: Bool? = nil) -> URL {
        var components = URLComponents(url: origin.url.appendingPathComponent("share"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "visibility", value: visibility)]
        if let cw { query.append(URLQueryItem(name: "cw", value: cw)) }
        if let replyId { query.append(URLQueryItem(name: "replyId", value: replyId)) }
        if let renoteId { query.append(URLQueryItem(name: "renoteId", value: renoteId)) }
        if let localOnly { query.append(URLQueryItem(name: "localOnly", value: localOnly ? "1" : "0")) }
        components.queryItems = query
        return components.url!
    }
}
