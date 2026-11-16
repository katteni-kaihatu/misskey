// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativeEmojiTests: XCTestCase {
    private func emoji(_ extra: [String: Any] = [:]) throws -> ClientCustomEmoji {
        let body: [String: Any] = ["name": "synthetic", "aliases": ["拍手", "Synthetic Cheer"], "url": "https://synthetic.example/emoji.png"]
        return try JSONDecoder().decode(ClientCustomEmoji.self, from: JSONSerialization.data(withJSONObject: body.merging(extra, uniquingKeysWith: { _, b in b })))
    }
    private func note(_ extra: [String: Any] = [:]) throws -> ClientNote {
        let body: [String: Any] = ["id": "note", "createdAt": "2026-11-16T00:00:00Z", "visibility": "home", "user": ["id": "author", "username": "synthetic"]]
        return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: body.merging(extra, uniquingKeysWith: { _, b in b })))
    }
    func testCatalogContainsWebDefinitionsAndJapaneseSearchTermsAcrossCategories() {
        XCTAssertGreaterThan(ClientUnicodeEmoji.all.count, 1900)
        XCTAssertEqual(Set(ClientUnicodeEmoji.all.map(\.category)), Set(0..<9))
        XCTAssertTrue(ClientUnicodeEmoji.all.contains { $0.char == "😂" && $0.matches("嬉し泣き") })
        XCTAssertTrue(ClientUnicodeEmoji.all.contains { $0.char == "😂" && $0.matches("joy") })
        XCTAssertTrue(ClientUnicodeEmoji.all.contains { $0.char == "👨‍👨‍👧‍👧" })
        XCTAssertEqual(Set(ClientUnicodeEmoji.all.map(\.char)).count, ClientUnicodeEmoji.all.count)
    }
    func testAliasesShortcodesCaseAndWidthInsensitiveSearch() throws {
        let value = try emoji()
        XCTAssertTrue(value.matches(":ＳＹＮＴＨＥＴＩＣ:")); XCTAssertTrue(value.matches("拍手")); XCTAssertTrue(value.matches("synthetic cheer"))
        XCTAssertFalse(value.matches("missing")); XCTAssertTrue(value.matches(""))
        XCTAssertTrue(ClientEmojiSearch.equivalent(":synthetic@.:", ":synthetic:"))
        XCTAssertFalse(ClientEmojiSearch.equivalent(":synthetic@remote.example:", ":synthetic:"))
        XCTAssertTrue(ClientEmojiSearch.equivalent("❤", "❤️"))
        XCTAssertNil(ClientEmojiSearch.localName(":synthetic@remote.example:"))
    }
    func testLocalOnlySensitiveRolesAndAcceptanceApplyOnlyToReactions() throws {
        let value = try emoji(["localOnly": true, "isSensitive": true, "roleIdsThatCanBeUsedThisEmojiAsReaction": ["role"]])
        XCTAssertNil(value.restriction(note: try note(), roles: ["role"]))
        XCTAssertNotNil(value.restriction(note: try note(), roles: []))
        XCTAssertNotNil(value.restriction(note: try note(["reactionAcceptance": "likeOnly"]), roles: ["role"]))
        XCTAssertNotNil(value.restriction(note: try note(["reactionAcceptance": "nonSensitiveOnly"]), roles: ["role"]))
        XCTAssertNotNil(value.restriction(note: try note(["user": ["id": "remote", "username": "synthetic", "host": "remote.example"]]), roles: ["role"]))
        XCTAssertNotNil(value.restriction(note: try note(["isHidden": true]), roles: ["role"]))
        // This capability flag is also true on ordinary local notes; it is not
        // an authentication boundary or a reason to disable normal reactions.
        XCTAssertNil(value.restriction(note: try note(["gridspaceReactions": true]), roles: ["role"]))
        XCTAssertTrue(try emoji().validName)
        XCTAssertFalse(try emoji(["name": "bad@remote"]).validName)
    }
    func testRemoteLikePoliciesAndLocalChannelActorException() throws {
        let remote: [String: Any] = ["id": "peer", "username": "peer", "host": "peer.example"]
        for policy in ["likeOnlyForRemote", "nonSensitiveOnlyForLocalLikeOnlyForRemote"] {
            XCTAssertFalse(try note(["reactionAcceptance": policy]).acceptsOnlyLike)
            XCTAssertTrue(try note(["user": remote, "reactionAcceptance": policy, "gridspaceReactions": true]).acceptsOnlyLike)
            XCTAssertFalse(try note(["user": remote, "reactionAcceptance": policy, "gridspaceReactions": true, "channelId": "channel", "localOnly": true]).acceptsOnlyLike)
        }
    }
}

final class NativeMultipleReactionTests: XCTestCase {
    func testOptimisticProjectionKeepsEquivalentKeysCountsAndSingleRemoteSemantics() throws {
        let raw = #"{"id":"note","createdAt":"2026-11-16T00:00:00Z","visibility":"public","user":{"id":"remote","username":"test","host":"ordinary.example"},"myReaction":"👍","reactions":{"👍":2,":test@.:":3}}"#
        let note = try JSONDecoder().decode(ClientNote.self, from: Data(raw.utf8))
        let projected = note.projectingReaction(":test:", adding: true, emojiURL: "https://synthetic.example/emoji.png")
        XCTAssertFalse(projected.supportsExtendedReactions); XCTAssertEqual(projected.ownReactions, [":test@.:"])
        XCTAssertEqual(projected.reactions?["👍"], 1); XCTAssertEqual(projected.reactions?[":test@.:"], 4)
        XCTAssertEqual(projected.reactionEmojis?["test@."], "https://synthetic.example/emoji.png")
        XCTAssertEqual(projected.projectingReaction(":test@.:", adding: true).reactions?[":test@.:"], 4)
        let removed = projected.projectingReaction(":test:", adding: false)
        XCTAssertEqual(removed.reactions?[":test@.:"], 3); XCTAssertTrue(removed.ownReactions.isEmpty)
        XCTAssertEqual(note.myReaction, "👍")
    }
    func testStateCopyKeepsTheNoteAndAllOwnChoicesAfterPrimaryRemoval() throws {
        let note = try JSONDecoder().decode(ClientNote.self, from: Data(#"{"id":"note","createdAt":"2026-11-16T00:00:00Z","text":"original","cw":"warning","visibility":"home","localOnly":true,"user":{"id":"owner","username":"synthetic"},"myReaction":"👍"}"#.utf8))
        let state = try JSONDecoder().decode(ClientReactionState.self, from: Data(#"{"noteId":"note","reactions":{"😂":1,":synthetic@.:":2},"reactionEmojis":{},"myReaction":null,"myReactions":["😂",":synthetic@.:"],"complete":true,"shared":false}"#.utf8))
        let result = note.applyingReactions(state)
        XCTAssertTrue(state.valid); XCTAssertTrue(result.supportsExtendedReactions)
        XCTAssertEqual(result.ownReactions.count, 2); XCTAssertTrue(result.hasOwnReaction(":synthetic:"))
        XCTAssertNil(result.myReaction); XCTAssertEqual(result.text, "original"); XCTAssertEqual(result.cw, "warning")
        XCTAssertEqual(result.localOnly, true); XCTAssertEqual(note.myReaction, "👍")
        XCTAssertEqual(result.reactionStateComplete, true)
        XCTAssertEqual(note.applyingReactions(nil).reactionStateComplete, false)
    }
    func testOrdinaryRemoteUsesLegacyButLocalAndAdvertisedPeersUseExtended() throws {
        func note(_ extra: String) throws -> ClientNote {
            try JSONDecoder().decode(ClientNote.self, from: Data((#"{"id":"note","createdAt":"2026-11-16T00:00:00Z","visibility":"public","user":{"id":"author","username":"test","host":"remote.example"},"gridspaceReactions":false,"# + extra + "}").utf8))
        }
        XCTAssertFalse(try note(#""myReaction":"👍""#).supportsExtendedReactions)
        XCTAssertTrue(try note(#""gridspaceShared":true"#).supportsExtendedReactions)
        XCTAssertFalse(try note(#""gridspaceShared":true,"channel":{"id":"channel"}"#).supportsExtendedReactions)
    }
}
