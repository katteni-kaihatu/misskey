// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

final class NativeAPITests: XCTestCase {
    private func api(token: String = "synthetic-native-token") throws -> NativeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NativeAPIStub.self]
        return NativeAPI(origin: try ServerOrigin("https://synthetic.example"), token: token, configuration: config)
    }

    override func tearDown() { NativeAPIStub.reset(); super.tearDown() }
    func testReactionAvatarPagesUseTheMatchingEndpointTypeAndTenActorLimit() async throws {
        NativeAPIStub.respond(status: 200, body: #"[{"id":"row1","type":"😂","user":{"id":"one","username":"first"}},{"id":"row2","type":"😂","user":{"id":"one","username":"first"}},{"id":"row3","type":"😂","user":{"id":"two","username":"second","host":"peer.example"}}]"#)
        let client = try api()
        let users = try await client.reactionUsers(note: "note", reaction: "😂", extended: true)
        XCTAssertEqual(users.map(\.id), ["one", "two"])
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notes/extended-reactions/list")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["noteId"] as? String, "note"); XCTAssertEqual(body["type"] as? String, "😂"); XCTAssertEqual(body["limit"] as? Int, 10)
        _ = try await client.reactionUsers(note: "note", reaction: "😂", extended: false)
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notes/reactions")
        do { _ = try await client.reactionUsers(note: "note", reaction: "👍", extended: true); XCTFail("Reject unrelated reaction actors") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
    }
    func testReshareAndQuotePayloadsKeepTheTargetAndLocalOnlyWithoutAnEmptyBody() async throws {
        NativeAPIStub.respond(status: 200, body: "{\"createdNote\":{\"id\":\"created\",\"renoteId\":\"original\",\"createdAt\":\"2026-11-16T00:00:00Z\",\"visibility\":\"home\",\"user\":{\"id\":\"owner\",\"username\":\"synthetic\"}}}")
        let client = try api()
        _ = try await client.create(text: "", cw: nil, visibility: "home", renoteId: "original", localOnly: true)
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["renoteId"] as? String, "original"); XCTAssertEqual(body["localOnly"] as? Bool, true)
        XCTAssertNil(body["text"]); XCTAssertNil(body["replyId"])
        _ = try await client.create(text: "Own synthetic quote", cw: "Synthetic CW", visibility: "home", fileIDs: ["attachment"], renoteId: "original")
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["text"] as? String, "Own synthetic quote"); XCTAssertEqual(body["fileIds"] as? [String], ["attachment"])
        XCTAssertEqual(body["cw"] as? String, "Synthetic CW"); XCTAssertNil(body["replyId"])
        do { _ = try await client.create(text: "", cw: nil, visibility: "home", replyId: "reply", renoteId: "quote"); XCTFail("Do not mix native target modes") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
        do { _ = try await client.create(text: "", cw: nil, visibility: "home", renoteId: "different"); XCTFail("Reject an unrelated created target") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
    }
    func testPeerCatalogUsesTheLocalAuthenticatedProxyAndItsOwnPaginationContract() async throws {
        NativeAPIStub.respond(status: 200, body: #"{"origin":"https://peer.example","channels":[{"id":"channel1","name":"Peer"}],"next":"next1"}"#)
        let client = try api(); let page = try await client.peerChannels(query: "Music", before: "boundary1")
        XCTAssertEqual(page.channels.first?.name, "Peer"); XCTAssertEqual(page.next, "next1")
        let request = try XCTUnwrap(NativeAPIStub.lastRequest())
        XCTAssertEqual(request.url?.host, "synthetic.example"); XCTAssertEqual(request.url?.path, "/api/gridspace/channels")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["i"] as? String, "synthetic-native-token"); XCTAssertEqual(body["list"] as? String, "search")
        XCTAssertEqual(body["queryType"] as? String, "nameAndDescription"); XCTAssertEqual(body["before"] as? String, "boundary1")
        XCTAssertNil(body["untilId"]); XCTAssertEqual(body["limit"] as? Int, 20)
        let anonymous = NativeAPI(origin: try ServerOrigin("https://synthetic.example"))
        do { _ = try await anonymous.peerChannels(query: ""); XCTFail("Require app authentication") }
        catch { XCTAssertEqual(error as? ClientAPIError, .notAuthenticated) }
    }
    func testPeerNotesKeepOpaqueCursorsValidationContextAndRejectWrongSource() async throws {
        let snapshot = #"{"notes":[{"id":"peer1","origin":"https://peer.example","createdAt":"2026-11-16T00:00:00Z","text":"Synthetic peer note","channelId":"channel1","author":{"username":"author","host":"peer.example"},"files":[]}],"cursor":null,"observedAt":"2026-11-16T00:00:00.000Z"}"#
        NativeAPIStub.respond(status: 200, body: snapshot)
        let client = try api()
        let page = try await client.peerChannelNotes("channel1", expectedOrigin: "https://peer.example", cursor: "opaque+/cursor=")
        XCTAssertEqual(page.notes.first?.author.username, "author")
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/gridspace/private-notes")
        XCTAssertEqual(body["cursor"] as? String, "opaque+/cursor="); XCTAssertEqual(body["mode"] as? String, "channel"); XCTAssertNil(body["untilId"])
        _ = try await client.peerChannelNotes("channel1", expectedOrigin: "https://peer.example", validating: ["peer1"])
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["mode"] as? String, "validate"); XCTAssertEqual(body["contextMode"] as? String, "channel"); XCTAssertEqual(body["ids"] as? [String], ["peer1"]); XCTAssertNil(body["cursor"])
        do { _ = try await client.peerChannelNotes("channel1", expectedOrigin: "https://different.example"); XCTFail("Do not reuse IDs on another peer") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
        do { _ = try await client.peerChannelNotes("channel1", expectedOrigin: "https://peer.example", validating: ["other"]); XCTFail("Reject extra validation IDs") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
    }

    func testChannelSearchAndTimelineKeepDistinctCursorsAndChannelIdentity() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        _ = try await client.channels(query: "Synthetic music", until: "channel-cursor")
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/channels/search")
        XCTAssertEqual(body["query"] as? String, "Synthetic music"); XCTAssertEqual(body["untilId"] as? String, "channel-cursor")
        _ = try await client.channelTimeline("channel-a", until: "note-cursor")
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/channels/timeline")
        XCTAssertEqual(body["channelId"] as? String, "channel-a"); XCTAssertEqual(body["untilId"] as? String, "note-cursor")
        XCTAssertNil(body["query"]); XCTAssertEqual(body["limit"] as? Int, 30)
        NativeAPIStub.respond(status: 200, body: #"[{"id":"note","createdAt":"2026-11-16T00:00:00Z","visibility":"public","channelId":"other","user":{"id":"user","username":"synthetic"}}]"#)
        do { _ = try await client.channelTimeline("channel-a"); XCTFail("Reject a different channel's notes") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
        do { _ = try await client.channelTimeline("../wrong"); XCTFail("Reject invalid IDs before sending") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
    }

    func testExtendedReactionWritesKeepTheExactEmojiAndNeverUseLegacyDeletion() async throws {
        NativeAPIStub.respond(status: 204, body: "")
        let client = try api()
        try await client.react(note: "note", reaction: ":synthetic@.:", extended: true)
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notes/extended-reactions/create")
        try await client.removeReaction(note: "note", reaction: ":synthetic@.:", extended: true)
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notes/extended-reactions/delete")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["noteId"] as? String, "note"); XCTAssertEqual(body["reaction"] as? String, ":synthetic@.:")
        let sent = NativeAPIStub.lastBody()
        do { try await client.removeReaction(note: "note", extended: true); XCTFail("Extended removal needs one exact emoji") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
        XCTAssertEqual(NativeAPIStub.lastBody(), sent)
    }
    func testTimelineBatchesFullOwnReactionSetsAndMarksFailedOrMissingStatesIncomplete() async throws {
        let notes = (0..<105).map { ["id": "note-\($0)", "createdAt": "2026-11-16T00:00:00Z", "visibility": "home", "user": ["id": "author", "username": "synthetic"]] as [String: Any] }
        NativeAPIStub.respond(status: 200, body: String(decoding: try JSONSerialization.data(withJSONObject: notes), as: UTF8.self))
        let state = #"[{"noteId":"note-0","reactions":{"😂":1,"👍":1},"reactionEmojis":{},"myReaction":null,"myReactions":["😂","👍"],"complete":true}]"#
        NativeAPIStub.respond(path: "/api/notes/extended-reactions/show", status: 200, body: state)
        let result = try await api().timeline(.home)
        XCTAssertEqual(result.first?.ownReactions, ["😂", "👍"]); XCTAssertNil(result.first?.myReaction)
        XCTAssertEqual(result.first?.reactionStateComplete, true)
        XCTAssertEqual(result[1].reactionStateComplete, false)
        let batches = try NativeAPIStub.bodies(path: "/api/notes/extended-reactions/show").map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any])["noteIds"] as? [String] }
        XCTAssertEqual(batches.compactMap { $0?.count }, [100, 5])
        NativeAPIStub.respond(path: "/api/notes/extended-reactions/show", status: 503, body: "{}")
        let failed = try await api().timeline(.home)
        XCTAssertEqual(failed.first?.reactionStateComplete, false)
        XCTAssertTrue(failed.first?.supportsExtendedReactions == true)
    }

    func testDeletionUsesTheExactOuterNoteAndAccepts204() async throws {
        NativeAPIStub.respond(status: 204, body: "")
        let client = try api(); try await client.deleteNote("outer-renote")
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notes/delete")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["noteId"] as? String, "outer-renote"); XCTAssertNil(body["renoteId"])
    }

    func testOrdinaryHomeUsesJSONTokenAndCursorWithoutCookiesOrURLCredentials() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        _ = try await client.timeline(.home, until: "boundary")
        let request = try XCTUnwrap(NativeAPIStub.lastRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://synthetic.example/api/notes/timeline")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "GridSpace-iOS/0.1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.url?.user)
        let body = try XCTUnwrap(NativeAPIStub.lastBody())
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(value["i"] as? String, "synthetic-native-token")
        XCTAssertEqual(value["untilId"] as? String, "boundary")
        await client.cancelRequests()
    }

    func testNotificationsDoNotMarkItemsReadAsASideEffect() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        _ = try await client.notifications()
        let body = try XCTUnwrap(NativeAPIStub.lastBody())
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(value["markAsRead"] as? Bool, false)
        await client.cancelRequests()
    }
    func testNotificationTypeAndCursorDoNotChangeTheExplicitReadOnlyFlag() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        _ = try await client.notifications(until: "notification-cursor", kind: .follow)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["untilId"] as? String, "notification-cursor")
        XCTAssertEqual(body["includeTypes"] as? [String], ["follow"])
        XCTAssertEqual(body["markAsRead"] as? Bool, false)
        XCTAssertEqual(body["limit"] as? Int, 30)
        _ = try await client.notifications()
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertNil(all["includeTypes"]); XCTAssertNil(all["untilId"])
    }
    func testReadAllNotificationsUsesTheDedicatedWriteEndpointAnd204Response() async throws {
        NativeAPIStub.respond(status: 204, body: "")
        let client = try api(); try await client.markAllNotificationsRead()
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notifications/mark-all-as-read")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["i"] as? String, "synthetic-native-token"); XCTAssertEqual(body.count, 1)
    }

    func testMiAuthCheckNeverAttachesAnExistingAccountsToken() async throws {
        NativeAPIStub.respond(status: 200, body: "{\"ok\":true,\"token\":\"synthetic-new-token\",\"user\":{\"id\":\"new\",\"username\":\"new\"}}")
        let client = try api()
        let result = try await client.checkMiAuth(UUID())
        XCTAssertEqual(result.0, "synthetic-new-token")
        let value = try JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any]
        XCTAssertNil(value?["i"])
        await client.cancelRequests()
    }

    func testServerFailureRetainsItsStatusAndDoesNotBecomeAnEmptyTimeline() async throws {
        NativeAPIStub.respond(status: 403, body: "{\"error\":{\"code\":\"LTL_DISABLED\"}}")
        let client = try api()
        do { _ = try await client.timeline(.local); XCTFail("Expected the actual server error") }
        catch { XCTAssertEqual(error as? ClientAPIError, .rejected(status: 403, code: "LTL_DISABLED")) }
        await client.cancelRequests()
    }

    func testSearchRestrictionIsRetainedAsAServerError() async throws {
        NativeAPIStub.respond(status: 400, body: "{\"error\":{\"code\":\"UNAVAILABLE\"}}")
        let client = try api()
        do { _ = try await client.search("synthetic"); XCTFail("A restricted search is not an empty result") }
        catch { XCTAssertEqual(error as? ClientAPIError, .rejected(status: 400, code: "UNAVAILABLE")) }
        await client.cancelRequests()
    }

    func testFileOnlyPostSendsOrderedIDsWithoutAnEmptyTextField() async throws {
        NativeAPIStub.respond(status: 200, body: "{\"createdNote\":{\"id\":\"n\",\"createdAt\":\"2026-11-16T00:00:00Z\",\"visibility\":\"followers\",\"user\":{\"id\":\"u\",\"username\":\"synthetic\"}}}")
        let client = try api()
        _ = try await client.create(text: " \n", cw: nil, visibility: "followers", fileIDs: ["second", "first"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertNil(body["text"])
        XCTAssertEqual(body["fileIds"] as? [String], ["second", "first"])
        XCTAssertEqual(body["visibility"] as? String, "followers")
    }

    func testMultipartUploadUsesBearerHeaderAndNeverWritesTheTokenIntoItsBody() async throws {
        NativeAPIStub.respond(status: 200, body: "{\"id\":\"file\",\"name\":\"synthetic\",\"type\":\"text/plain\",\"isSensitive\":false}")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data("synthetic upload bytes".utf8)
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let client = try api()
        _ = try await client.upload(source: source, entry: NativeAttachmentDraft(name: "synthetic.txt", byteCount: bytes.count, mimeType: "text/plain"))
        let request = try XCTUnwrap(NativeAPIStub.lastRequest()), body = try XCTUnwrap(NativeAPIStub.lastBody())
        XCTAssertEqual(request.url?.absoluteString, "https://synthetic.example/api/drive/files/create")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-native-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "GridSpace-iOS/0.1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(body.range(of: bytes))
        XCTAssertNil(body.range(of: Data("synthetic-native-token".utf8)))
    }

    func testRestoredAttachmentMustStillBelongToThePostingAccount() async throws {
        NativeAPIStub.respond(status: 200, body: "{\"id\":\"file\",\"userId\":\"other\",\"name\":\"synthetic\",\"type\":\"text/plain\",\"isSensitive\":false}")
        let client = try api()
        do { try await client.verifyOwnFile("file", owner: "owner"); XCTFail("Reject a different owner") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
    }

    func testConversationOffsetAndReplyCursorUseTheirDistinctPaginationContracts() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        _ = try await client.conversation("target", offset: 40)
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["offset"] as? Int, 40); XCTAssertEqual(body["limit"] as? Int, 20)
        XCTAssertEqual(body["noteId"] as? String, "target"); XCTAssertNil(body["untilId"])
        _ = try await client.replies("target", until: "cursor")
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["untilId"] as? String, "cursor"); XCTAssertEqual(body["limit"] as? Int, 30); XCTAssertNil(body["offset"])
    }
    func testPollVoteSendsAnIntegerChoiceAndAcceptsAnEmptySuccessResponse() async throws {
        NativeAPIStub.respond(status: 204, body: "")
        let client = try api()
        try await client.vote("target", choice: 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
        XCTAssertEqual(body["choice"] as? Int, 1); XCTAssertEqual(body["noteId"] as? String, "target")
        XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/notes/polls/vote")
    }
    func testProfileFiltersNeverCombineRepliesWithFilesAndKeepTheNoteCursor() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        for filter in ClientProfileFilter.allCases {
            _ = try await client.userNotes("target", filter: filter, until: "note-cursor")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
            XCTAssertEqual(body["userId"] as? String, "target"); XCTAssertEqual(body["untilId"] as? String, "note-cursor")
            XCTAssertEqual(body["withReplies"] as? Bool, filter == .replies); XCTAssertEqual(body["withFiles"] as? Bool, filter == .media)
            XCTAssertEqual(body["limit"] as? Int, 30); XCTAssertNil(body["allowPartial"])
        }
    }
    func testFollowingAndFollowersKeepTheRelationshipCursorAndDistinctRoutes() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let client = try api()
        for kind: ClientPeopleKind in [.following, .followers] {
            _ = try await client.people("owner", kind: kind, until: "edge-cursor")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any])
            XCTAssertEqual(body["untilId"] as? String, "edge-cursor"); XCTAssertEqual(body["userId"] as? String, "owner")
            XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/" + kind.endpoint)
        }
    }
    func testExplicitRelationshipActionsUseTheirOwnEndpointsAndVerifyTheReturnedTarget() async throws {
        NativeAPIStub.respond(status: 200, body: "{\"id\":\"target\"}")
        let client = try api()
        for action: ClientFollowAction in [.follow, .request, .unfollow, .cancelRequest] {
            try await client.changeFollowing("target", action: action)
            XCTAssertEqual(NativeAPIStub.lastRequest()?.url?.path, "/api/" + action.endpoint)
        }
        NativeAPIStub.respond(status: 200, body: "{\"id\":\"other\"}")
        do { try await client.changeFollowing("target", action: .follow); XCTFail("Reject a mismatched response") }
        catch { XCTAssertEqual(error as? ClientAPIError, .invalidResponse) }
    }
    func testReplacingAClientCannotRetargetAnOlderAccountsRequests() async throws {
        NativeAPIStub.respond(status: 200, body: "[]")
        let old = try api(token: "synthetic-old-account"), new = try api(token: "synthetic-new-account")
        for (client, expected) in [(old, "synthetic-old-account"), (new, "synthetic-new-account"), (old, "synthetic-old-account")] {
            _ = try await client.timeline(.home)
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(NativeAPIStub.lastBody())) as? [String: Any]
            XCTAssertEqual(body?["i"] as? String, expected)
        }
        await old.cancelRequests(); await new.cancelRequests()
    }
}

private final class NativeAPIStub: URLProtocol, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var response = (200, "[]")
        var captured: (URLRequest, Data)?
        var history: [(URLRequest, Data)] = []
        var routes: [String: (Int, String)] = [:]
    }
    private static let storage = Storage()
    static func respond(status: Int, body: String) { storage.lock.lock(); defer { storage.lock.unlock() }; storage.response = (status, body) }
    static func respond(path: String, status: Int, body: String) { storage.lock.lock(); defer { storage.lock.unlock() }; storage.routes[path] = (status, body) }
    static func bodies(path: String) -> [Data] { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.history.filter { $0.0.url?.path == path }.map { $0.1 } }
    static func reset() { storage.lock.lock(); defer { storage.lock.unlock() }; storage.captured = nil; storage.history = []; storage.routes = [:]; storage.response = (200, "[]") }
    static func lastRequest() -> URLRequest? { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.captured?.0 }
    static func lastBody() -> Data? { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.captured?.1 }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "synthetic.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
        }
        Self.storage.lock.lock(); Self.storage.captured = (request, body); Self.storage.history.append((request, body)); let response = Self.storage.routes[request.url?.path ?? ""] ?? Self.storage.response; Self.storage.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
