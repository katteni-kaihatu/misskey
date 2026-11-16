// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public struct ClientPeerChannelPage: Decodable, Sendable {
    public let origin: String
    public let channels: [ClientChannel]
    public let next: String?
}
public struct ClientPeerChannelChoice: Identifiable, Sendable {
    public let origin: String
    public let channel: ClientChannel
    public init(origin: String, channel: ClientChannel) { self.origin = origin; self.channel = channel }
    public var tab: ClientFeedTab { .peerChannel(origin: origin, id: channel.id, name: channel.name) }
    public var id: String { tab.id }
}

/// Peer IDs and author identities never become local ClientNote/User IDs.
/// Deliberately Decodable only: authorized snapshots are held in memory.
public struct ClientPeerChannelNote: Decodable, Identifiable, Sendable {
    public struct Author: Decodable, Sendable {
        public let name: String?
        public let username: String
        public let host: String
        public let avatarUrl: String?
        public let emojis: [String: String]?
    }
    public struct File: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let isSensitive: Bool
    }
    public struct Quote: Decodable, Sendable {
        public let author: Author
        public let text: String?
        public let cw: String?
    }
    public let id: String
    public let origin: String
    public let createdAt: String
    public let text: String?
    public let cw: String?
    public let author: Author
    public let channelId: String?
    public let channel: ClientNote.Channel?
    public let files: [File]
    public let renote: Quote?
}
public struct ClientPeerChannelNotePage: Decodable, Sendable {
    public let notes: [ClientPeerChannelNote]
    public let cursor: String?
    public let observedAt: String
}
