// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GridSpaceCore

enum NativeHTTP {
    // Identify this client consistently, without impersonating a browser.
    static let userAgent = "GridSpace-iOS/0.1"
}

/// Ordinary MiAuth APIs only. GridSpace's secure APIs continue in the Web client.
actor NativeAPI: NativeTimelineLiveAPI, NativeAttachmentAPI, NativeThreadAPI, NativePollAPI, NativeProfileAPI, NativePeopleAPI, NativeNoteDeleteAPI, NativeNotificationsAPI, NativeLiveReactionAPI, NativeChannelAPI, NativePeerChannelAPI {
    let origin: ServerOrigin
    private let token: String?
    private var session: URLSession
    private let redirect = NoAPIRedirects()

    init(origin: ServerOrigin, token: String? = nil, configuration: URLSessionConfiguration? = nil) {
        self.origin = origin
        self.token = token
        let config = configuration ?? .ephemeral
        #if DEBUG
        if NativeComposerFixture.enabled, origin == NativeComposerFixture.origin { config.protocolClasses = [NativeComposerFixture.self] }
        if NativeTimelineFixture.enabled, origin == NativeTimelineFixture.origin { config.protocolClasses = [NativeTimelineFixture.self] }
        if let fixture = LocalParityServer.current, fixture.origin == origin { fixture.configureControlSession(config) }
        #endif
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config, delegate: redirect, delegateQueue: nil)
    }

    func cancelRequests() {
        let config = session.configuration
        session.invalidateAndCancel()
        session = URLSession(configuration: config, delegate: redirect, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func account() async throws -> ClientUser { try await request("i", [:], requiresAccount: true) }
    func emojis() async throws -> [ClientCustomEmoji] {
        struct Catalog: Decodable { let emojis: [ClientCustomEmoji] }
        let catalog: Catalog = try await request("emojis", [:], useToken: false)
        var names = Set<String>()
        return catalog.emojis.filter { $0.validName && names.insert($0.name).inserted }
    }
    func emoji(_ name: String) async throws -> ClientCustomEmoji { try await request("emoji", ["name": name], useToken: false) }
    func reactionUsers(note: String, reaction: String, extended: Bool) async throws -> [ClientUser] {
        let rows: [ClientNoteReaction] = try await request(extended ? "notes/extended-reactions/list" : "notes/reactions", ["noteId": note, "type": reaction, "limit": 10])
        guard rows.count <= 10, rows.allSatisfy({ ClientEmojiSearch.equivalent($0.type, reaction) }) else { throw ClientAPIError.invalidResponse }
        var ids = Set<String>()
        return rows.map(\.user).filter { ids.insert($0.id).inserted }
    }
    func timeline(_ kind: ClientTimeline, until: String? = nil) async throws -> [ClientNote] {
        var body: [String: Any] = ["limit": 30]
        if let until { body["untilId"] = until }
        let notes: [ClientNote] = try await request(kind.endpoint, body, requiresAccount: kind == .home)
        return try await hydrateReactions(notes)
    }
    func timelineEvents(_ feed: ClientFeedTab) throws -> NativeTimelineSubscription {
        if case .timeline(.home) = feed, token == nil { throw ClientAPIError.notAuthenticated }
        _ = try NativeTimelineSocket.subscription(feed, id: "validate")
        #if DEBUG
        if NativeTimelineFixture.enabled { return NativeTimelineSubscription(events: NativeTimelineFixture.events(feed), cancel: {}) }
        if NativeComposerFixture.enabled {
            if ProcessInfo.processInfo.arguments.contains("--native-retained-timeline-fixture") {
                let (events, continuation) = AsyncThrowingStream<NativeTimelineEvent, Error>.makeStream()
                continuation.yield(.connected)
                return NativeTimelineSubscription(events: events, cancel: { continuation.finish() })
            }
            return NativeTimelineSubscription(events: AsyncThrowingStream { $0.finish() }, cancel: {})
        }
        #endif
        var components = URLComponents(url: origin.url, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"; components.path = "/streaming"
        var request = URLRequest(url: components.url!)
        request.setValue(NativeHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return try NativeTimelineSocket.open(session.webSocketTask(with: request), feed: feed)
    }
    func prepareLiveNotes(_ notes: [ClientNote]) async throws -> [ClientNote] { try await hydrateReactions(notes) }
    func noteEvents() throws -> NativeTimelineSubscription {
        #if DEBUG
        if NativeComposerFixture.enabled { return NativeComposerFixture.noteEvents() }
        if NativeTimelineFixture.enabled { return NativeTimelineSubscription(events: AsyncThrowingStream { $0.finish() }, cancel: {}) }
        #endif
        var components = URLComponents(url: origin.url, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"; components.path = "/streaming"
        var request = URLRequest(url: components.url!)
        request.setValue(NativeHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return try NativeTimelineSocket.open(session.webSocketTask(with: request), feed: nil)
    }
    func reactionStates(_ ids: [String]) async throws -> [ClientReactionState] {
        guard !ids.isEmpty, ids.count <= 100, Set(ids).count == ids.count else { throw ClientAPIError.invalidResponse }
        let states: [ClientReactionState] = try await request("notes/extended-reactions/show", ["noteIds": ids])
        guard Set(states.map(\.noteId)).count == states.count, states.allSatisfy({ ids.contains($0.noteId) && $0.valid }) else { throw ClientAPIError.invalidResponse }
        return states
    }
    func channels(query: String, until: String? = nil) async throws -> [ClientChannel] {
        var body: [String: Any] = ["query": query, "limit": 30, "type": "nameAndDescription"]
        if let until { body["untilId"] = until }
        let items: [ClientChannel] = try await request("channels/search", body)
        var ids = Set<String>()
        return items.filter { ClientFeedTab.validChannelID($0.id) && ids.insert($0.id).inserted }
    }
    func peerChannels(query: String, before: String? = nil) async throws -> ClientPeerChannelPage {
        var body: [String: Any] = ["list": "search", "query": String(query.prefix(100)), "queryType": "nameAndDescription", "limit": 20]
        if let before { guard ClientFeedTab.validPeerID(before) else { throw ClientAPIError.invalidResponse }; body["before"] = before }
        let page: ClientPeerChannelPage = try await request("gridspace/channels", body, requiresAccount: true)
        guard let peer = try? ServerOrigin(page.origin), peer != origin, page.channels.count <= 20,
              Set(page.channels.map(\.id)).count == page.channels.count,
              page.channels.allSatisfy({ ClientFeedTab.validPeerID($0.id) }), page.next.map(ClientFeedTab.validPeerID) ?? true else { throw ClientAPIError.invalidResponse }
        return page
    }
    func peerChannelNotes(_ id: String, expectedOrigin: String, cursor: String? = nil, validating: [String]? = nil) async throws -> ClientPeerChannelNotePage {
        guard ClientFeedTab.validPeerID(id), let expected = try? ServerOrigin(expectedOrigin), expected != origin,
              cursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true else { throw ClientAPIError.invalidResponse }
        var body: [String: Any] = ["mode": "channel", "channelId": id, "limit": 10]
        if let validating {
            guard !validating.isEmpty, validating.count <= 100, validating.allSatisfy(ClientFeedTab.validPeerID), Set(validating).count == validating.count else { throw ClientAPIError.invalidResponse }
            body["mode"] = "validate"; body["contextMode"] = "channel"; body["ids"] = validating
        } else if let cursor { body["cursor"] = cursor }
        let page: ClientPeerChannelNotePage = try await request("gridspace/private-notes", body, requiresAccount: true)
        guard page.notes.count <= (validating == nil ? 10 : 100), Set(page.notes.map(\.id)).count == page.notes.count,
              page.cursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true,
              ISO8601DateFormatter().date(from: page.observedAt) != nil || Self.peerDate(page.observedAt) != nil,
              page.notes.allSatisfy({ note in
                  ClientFeedTab.validPeerID(note.id) && (try? ServerOrigin(note.origin)) == expected
                      && (note.channelId == id || note.channel?.id == id) && (validating?.contains(note.id) ?? true)
              }) else { throw ClientAPIError.invalidResponse }
        return page
    }
    private static func peerDate(_ value: String) -> Date? {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return format.date(from: value)
    }
    func channelTimeline(_ id: String, until: String? = nil) async throws -> [ClientNote] {
        guard ClientFeedTab.validChannelID(id) else { throw ClientAPIError.invalidResponse }
        var body: [String: Any] = ["channelId": id, "limit": 30]
        if let until { body["untilId"] = until }
        let notes: [ClientNote] = try await request("channels/timeline", body)
        guard notes.allSatisfy({ $0.isHidden == true || $0.channelId == id || $0.channel?.id == id }) else { throw ClientAPIError.invalidResponse }
        return try await hydrateReactions(notes)
    }
    func note(_ id: String) async throws -> ClientNote {
        let note: ClientNote = try await request("notes/show", ["noteId": id])
        return try await hydrateReactions([note])[0]
    }

    private func hydrateReactions(_ notes: [ClientNote]) async throws -> [ClientNote] {
        let eligible = notes.filter { $0.supportsExtendedReactions && $0.isHidden != true && !$0.isPureRenote }
        let ids = Array(Set(eligible.map(\.id))).sorted()
        guard !ids.isEmpty else { return notes }
        var states: [String: ClientReactionState] = [:]
        for offset in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[offset..<min(ids.count, offset + 100)])
            do {
                let result: [ClientReactionState] = try await request("notes/extended-reactions/show", ["noteIds": batch])
                guard Set(result.map(\.noteId)).count == result.count, result.allSatisfy({ batch.contains($0.noteId) && $0.valid }) else { throw ClientAPIError.invalidResponse }
                for state in result { states[state.noteId] = state }
            } catch { try Task.checkCancellation() /* Partial display must never downgrade to a single-reaction write. */ }
        }
        try Task.checkCancellation()
        return notes.map { note in eligible.contains(where: { $0.id == note.id }) ? note.applyingReactions(states[note.id]) : note }
    }
    func conversation(_ id: String, offset: Int = 0) async throws -> [ClientNote] {
        let notes: [ClientNote] = try await request("notes/conversation", ["noteId": id, "limit": 20, "offset": offset])
        return try await hydrateReactions(notes)
    }
    func replies(_ id: String, until: String? = nil) async throws -> [ClientNote] {
        var body: [String: Any] = ["noteId": id, "limit": 30]
        if let until { body["untilId"] = until }
        let notes: [ClientNote] = try await request("notes/replies", body)
        return try await hydrateReactions(notes)
    }
    func vote(_ id: String, choice: Int) async throws {
        let _: EmptyResponse = try await request("notes/polls/vote", ["noteId": id, "choice": choice], requiresAccount: true)
    }
    func user(_ id: String) async throws -> ClientUser { try await request("users/show", ["userId": id]) }
    func user(username: String, host: String?) async throws -> ClientUser {
        var body: [String: Any] = ["username": username]
        if let host { body["host"] = host }
        return try await request("users/show", body)
    }
    func userNotes(_ id: String, filter: ClientProfileFilter, until: String? = nil) async throws -> [ClientNote] {
        var body: [String: Any] = ["userId": id, "limit": 30, "withReplies": filter == .replies, "withFiles": filter == .media,
                                  "withRenotes": true, "withChannelNotes": false]
        if let until { body["untilId"] = until }
        let notes: [ClientNote] = try await request("users/notes", body)
        return try await hydrateReactions(notes)
    }
    func people(_ id: String, kind: ClientPeopleKind, until: String? = nil) async throws -> [ClientFollowing] {
        var body: [String: Any] = ["userId": id, "limit": 30]
        if let until { body["untilId"] = until }
        return try await request(kind.endpoint, body)
    }
    func changeFollowing(_ id: String, action: ClientFollowAction) async throws {
        struct Result: Decodable { let id: String }
        let result: Result = try await request(action.endpoint, ["userId": id], requiresAccount: true)
        guard result.id == id else { throw ClientAPIError.invalidResponse }
    }
    func search(_ query: String, until: String? = nil) async throws -> [ClientNote] {
        var body: [String: Any] = ["query": query, "limit": 30]
        if let until { body["untilId"] = until }
        let notes: [ClientNote] = try await request("notes/search", body)
        return try await hydrateReactions(notes)
    }
    func notifications(until: String? = nil, kind: ClientNotificationKind? = nil) async throws -> [ClientNotification] {
        var body: [String: Any] = ["limit": 30, "markAsRead": false]
        if let until { body["untilId"] = until }
        if let kind { body["includeTypes"] = [kind.rawValue] }
        let items: [ClientNotification] = try await request("i/notifications", body, requiresAccount: true)
        let notes = try await hydrateReactions(items.compactMap(\.note))
        var index = 0
        return items.map { item in
            guard item.note != nil else { return item }
            defer { index += 1 }
            return item.replacingNote(notes[index])
        }
    }
    func markAllNotificationsRead() async throws {
        let _: EmptyResponse = try await request("notifications/mark-all-as-read", [:], requiresAccount: true)
    }
    func create(text: String, cw: String?, visibility: String, replyId: String? = nil, fileIDs: [String] = [], renoteId: String? = nil, localOnly: Bool = false) async throws -> ClientNote {
        guard replyId == nil || renoteId == nil else { throw ClientAPIError.invalidResponse }
        var body: [String: Any] = ["visibility": visibility]
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["text"] = text }
        if !fileIDs.isEmpty { body["fileIds"] = fileIDs }
        if let cw { body["cw"] = cw }
        if let replyId { body["replyId"] = replyId }
        if let renoteId { body["renoteId"] = renoteId }
        if localOnly { body["localOnly"] = true }
        struct Created: Decodable { let createdNote: ClientNote }
        let result: Created = try await request("notes/create", body, requiresAccount: true)
        guard result.createdNote.replyId == replyId, result.createdNote.renoteId == renoteId else { throw ClientAPIError.invalidResponse }
        return result.createdNote
    }
    func deleteNote(_ id: String) async throws {
        let _: EmptyResponse = try await request("notes/delete", ["noteId": id], requiresAccount: true)
    }
    func react(note: String, reaction: String, extended: Bool = false) async throws {
        let _: EmptyResponse = try await request(extended ? "notes/extended-reactions/create" : "notes/reactions/create", ["noteId": note, "reaction": reaction], requiresAccount: true)
    }
    func removeReaction(note: String, reaction: String? = nil, extended: Bool = false) async throws {
        var body: [String: Any] = ["noteId": note]
        if extended {
            guard let reaction, !reaction.isEmpty else { throw ClientAPIError.invalidResponse }
            body["reaction"] = reaction
        }
        let _: EmptyResponse = try await request(extended ? "notes/extended-reactions/delete" : "notes/reactions/delete", body, requiresAccount: true)
    }
    func checkMiAuth(_ id: UUID) async throws -> (String, ClientUser) {
        struct Result: Decodable { let ok: Bool; let token: String?; let user: ClientUser? }
        let result: Result = try await request("miauth/" + id.uuidString.lowercased() + "/check", [:], useToken: false)
        guard result.ok, let token = result.token, !token.isEmpty, let user = result.user else { throw ClientAPIError.notAuthenticated }
        return (token, user)
    }

    private struct EmptyResponse: Decodable {}
    private struct ErrorBody: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }

    private func request<T: Decodable>(_ endpoint: String, _ body: [String: Any], requiresAccount: Bool = false, useToken: Bool = true) async throws -> T {
        if requiresAccount && token == nil { throw ClientAPIError.notAuthenticated }
        var payload = body
        if useToken, let token { payload["i"] = token }
        var request = URLRequest(url: origin.url.appendingPathComponent("api/" + endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(NativeHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (bytes, response) = try await session.bytes(for: request, delegate: redirect)
        return try await decode(bytes, response)
    }

    func upload(source: URL, entry: NativeAttachmentDraft) async throws -> ClientFile {
        guard let token else { throw ClientAPIError.notAuthenticated }
        try Task.checkCancellation()
        let prepared: (URL, String, Int)
        do { prepared = try NativeMultipart.write(source: source, entry: entry) }
        catch let error as NativeAttachmentError { throw error }
        catch { throw NativeAttachmentError.unavailable }
        let (file, boundary, length) = prepared
        defer { try? FileManager.default.removeItem(at: file) }
        var request = URLRequest(url: origin.url.appendingPathComponent("api/drive/files/create"))
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(NativeHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        request.setValue(String(length), forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 120
        request.httpBodyStream = InputStream(url: file)
        let (bytes, response) = try await session.bytes(for: request, delegate: redirect)
        return try await decode(bytes, response)
    }

    func verifyOwnFile(_ id: String, owner: String) async throws {
        _ = try await ownFile(id, owner: owner)
    }
    func ownFile(_ id: String, owner: String) async throws -> ClientFile {
        let file: ClientFile = try await request("drive/files/show", ["fileId": id], requiresAccount: true)
        guard file.id == id, file.userId == owner else { throw ClientAPIError.invalidResponse }
        return file
    }
    func driveFiles(until: String? = nil) async throws -> [ClientFile] {
        var body: [String: Any] = ["limit": 30]
        if let until { body["untilId"] = until }
        return try await request("drive/stream", body, requiresAccount: true)
    }

    private func decode<T: Decodable>(_ bytes: URLSession.AsyncBytes, _ response: URLResponse) async throws -> T {
        guard let response = response as? HTTPURLResponse, let url = response.url, origin.contains(url) else { throw ClientAPIError.invalidResponse }
        let maximum = 8 * 1024 * 1024
        guard response.expectedContentLength <= maximum else { throw ClientAPIError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else { throw ClientAPIError.responseTooLarge }
            data.append(byte)
        }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data).error.code) ?? "HTTP_ERROR"
            // A server's raw body, URL or token never becomes an error message.
            throw ClientAPIError.rejected(status: response.statusCode, code: code)
        }
        if response.statusCode == 204 { return try JSONDecoder().decode(T.self, from: Data("{}".utf8)) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private final class NoAPIRedirects: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await evaluate(challenge)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await evaluate(challenge)
    }
    private func evaluate(_ challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        #if DEBUG
        if let fixture = LocalParityServer.current, fixture.handles(challenge.protectionSpace) {
            if let credential = await fixture.evaluatedCredential(for: challenge.protectionSpace) { return (.useCredential, credential) }
            return (.cancelAuthenticationChallenge, nil)
        }
        #endif
        return (.performDefaultHandling, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
