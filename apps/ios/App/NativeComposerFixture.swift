// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
import Foundation
import GridSpaceCore

/// Offline compose QA. Neither synthetic authorization nor uploads leave this
/// explicitly selected session. This type is absent from Release builds.
final class NativeComposerFixture: URLProtocol, @unchecked Sendable {
    static let origin = try! ServerOrigin("https://composer.ios.test")
    // Owned two-color/two-frame image fixtures, generated with ImageIO/libvips.
    static let animatedGIF = Data(base64Encoded: "R0lGODdhEAAQAKIAAAAAAOYjLR5k6////wAAAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQFEAAEACwAAAAAEAAQAAADDxi63P4wykmrvTjrzbtfCQAh+QQFEAAEACwAAAAAEAAQAAADDyi63P4wykmrvTjrzbtfCQA7")!
    static let animatedWebP = Data(base64Encoded: "UklGRogAAABXRUJQVlA4WAoAAAACAAAADwAADwAAQU5JTQYAAAD/////AABBTk1GKgAAAAAAAAAAAA8AAA8AAKAAAAJWUDhMEQAAAC8PwAMAB9CRmrel/4GI6H8AAEFOTUYqAAAAAAAAAAAADwAADwAAoAAAAFZQOEwRAAAALw/AAwAHULJ6dL3/gYjofwAA")!
    static let session = "12345678-1234-4234-8234-123456789012"
    static var enabled: Bool { ["--ui-testing", "--native-client-fixture", "--native-composer-fixture"].allSatisfy(ProcessInfo.processInfo.arguments.contains) }
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: [String: Any]] = [:]
        var notes: [[String: Any]] = []
        var reactions: [String] = []
        var primaryReaction: String?
        var timelineReads: [String: Int] = [:]
        var notificationRead = false
        var livePhase = 0
        var liveOther: [String: Int] = [:]
    }
    private static let store = Store()
    static func noteEvents() -> NativeTimelineSubscription {
        guard ProcessInfo.processInfo.arguments.contains("--native-live-reactions-fixture") else { return NativeTimelineSubscription(events: AsyncThrowingStream { $0.finish() }, cancel: {}) }
        let events = AsyncThrowingStream<NativeTimelineEvent, Error> { continuation in
            let task = Task {
                do {
                    continuation.yield(.connected)
                    for phase in 1...4 {
                        try await Task.sleep(nanoseconds: 4_000_000_000)
                        setLivePhase(phase)
                        let packet: [String: Any] = ["type": "noteUpdated", "body": ["id": "synthetic-reaction-sheet", "type": "extendedReactionUpdated", "body": [:]]]
                        if let event = try NativeTimelineSocket.decode(JSONSerialization.data(withJSONObject: packet), id: "updates") { continuation.yield(event) }
                        if phase == 3 { continuation.yield(.emojiCatalogChanged) }
                    }
                    // Keep the fixture alive, like a quiet real connection.
                    try await Task.sleep(nanoseconds: 120_000_000_000)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return NativeTimelineSubscription(events: events, cancel: {})
    }
    private static func setLivePhase(_ phase: Int) {
        store.lock.lock(); defer { store.lock.unlock() }
        store.livePhase = phase
        store.liveOther = phase < 3 ? ["😂": 1] : phase == 3 ? ["😂": 1, "👍": 1] : ["👍": 1]
    }
    private let deliveryLock = NSRecursiveLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == origin.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var user: [String: Any] = ["id": "synthetic-composer", "username": "compose-fixture", "name": "Compose QA", "avatarUrl": originURL("synthetic-animated.gif"), "policies": ["maxFileSizeMb": 30]]
        if ProcessInfo.processInfo.arguments.contains("--native-name-emoji-fixture") {
            user["name"] = "Compose :synthetic_animation: QA"; user["emojis"] = ["synthetic_animation": originURL("synthetic-animated.gif")]
        }
        if request.url?.path == "/synthetic-animated.gif" || request.url?.path == "/synthetic-updated.webp" {
            let updated = request.url?.path == "/synthetic-updated.webp"
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": updated ? "image/webp" : "image/gif", "Cache-Control": "public, max-age=86400"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: updated ? Self.animatedWebP : Self.animatedGIF); client?.urlProtocolDidFinishLoading(self); return
        }
        let data = Self.requestData(request)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        Self.store.lock.lock(); defer { Self.store.lock.unlock() }
        var status = 200
        let result: Any
        let notificationFixture = ProcessInfo.processInfo.arguments.contains("--native-notifications-fixture")
        if notificationFixture { user["unreadNotificationsCount"] = Self.store.notificationRead ? 0 : 5 }
        let reactionFixture = ProcessInfo.processInfo.arguments.contains("--native-reaction-sheet-fixture")
        let avatarFixture = ProcessInfo.processInfo.arguments.contains("--native-reaction-avatars-fixture")
        func reactionCounts() -> [String: Int] {
            var counts = reactionFixture ? Dictionary(uniqueKeysWithValues: Self.store.reactions.map { ($0, 1) }) : [:]
            if avatarFixture { counts["👍", default: 0] += 2 }
            for (value, count) in Self.store.liveOther { counts[value, default: 0] += count }
            return counts
        }
        func reactionNote(_ id: String = "synthetic-reaction-sheet") -> [String: Any] {
            if ProcessInfo.processInfo.arguments.contains("--native-pure-renote-fixture"), id == "synthetic-pure-renote" {
                return ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "public", "user": user,
                        "renoteId": "synthetic-reaction-sheet", "renote": reactionNote(), "reactions": [String: Int]()]
            }
            var note: [String: Any] = ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "public", "gridspaceReactions": true,
                "text": id == "synthetic-reaction-sheet" ? "Short synthetic note" : "Second synthetic note :synthetic_animation:", "user": user,
                "emojis": ["synthetic_animation": originURL("synthetic-animated.gif")],
                "reactions": reactionCounts()]
            if let reaction = Self.store.primaryReaction { note["myReaction"] = reaction }
            return note
        }
        let path = request.url!.path
        let peerFixture = ProcessInfo.processInfo.arguments.contains("--native-peer-channels-fixture")
        if peerFixture && ["/api/channels/search", "/api/gridspace/channels", "/api/gridspace/private-notes", "/api/channels/timeline"].contains(path) {
            let channel: [String: Any] = ["id": "collision1", "name": path == "/api/channels/search" ? "Synthetic local music" : "Synthetic peer music", "isSensitive": false, "isArchived": false]
            if path == "/api/channels/search" { result = [channel] }
            else if path == "/api/gridspace/channels" {
                if ProcessInfo.processInfo.arguments.contains("--native-peer-permission-fixture") {
                    status = 403; result = ["error": ["code": "PERMISSION_DENIED"]]
                } else { result = ["origin": "https://peer.ios.test", "channels": [channel], "next": NSNull()] }
            } else if path == "/api/channels/timeline" {
                result = [["id": "localNote1", "createdAt": "2026-11-16T00:00:00Z", "visibility": "public", "channelId": "collision1", "text": "LOCAL CHANNEL NOTE", "user": user]]
            } else if body["mode"] as? String == "validate" && ProcessInfo.processInfo.arguments.contains("--native-peer-revocation-fixture") {
                status = 400; result = ["error": ["code": "GRIDSPACE_PRIVATE_UNAVAILABLE"]]
            } else {
                let validating = body["mode"] as? String == "validate"
                let ids = validating ? (body["ids"] as? [String] ?? []) : (body["cursor"] == nil ? (0..<10).map { "peerNote\($0)" } : ["peerNote10", "peerNote11"])
                let notes = ids.map { id -> [String: Any] in
                    ["id": id, "origin": "https://peer.ios.test", "createdAt": "2026-11-16T00:00:00Z", "text": "PEER CHANNEL NOTE " + id,
                     "channelId": "collision1", "files": [], "author": ["username": "peer-author", "host": "peer.ios.test", "name": "Synthetic peer author"]]
                }
                result = ["notes": notes, "cursor": !validating && body["cursor"] == nil ? "opaque+peer/cursor=" as Any : NSNull(), "observedAt": "2026-11-16T00:00:00.000Z"]
            }
        } else if path.hasPrefix("/api/miauth/") {
            result = ["ok": true, "token": "synthetic-offline-compose-token", "user": user]
        } else if path == "/api/i" { result = user }
        else if notificationFixture && path == "/api/i/notifications" {
            let samples: [(String, String, String)] = [
                ("reaction", "こはる :synthetic_animation:", "今日は少し遠回りして帰ろう。"),
                ("renote", "なつ", "週末の写真をまとめました。"),
                ("reply", "あおい", "そのお店、わたしも気になってました ☕️"),
                ("follow", "ましろ", ""),
                ("mention", "はる", "またみんなで集まりたいね。"),
                ("reaction", "そら", "おはようございます 🌿"),
                ("app", "ぐりすぺ", "新しいお知らせがあります。")
            ]
            let rows: [[String: Any]] = samples.enumerated().map { index, sample in
                var person = user
                person["id"] = "notification-person-\(index)"; person["name"] = sample.1
                person["emojis"] = ["synthetic_animation": originURL("synthetic-animated.gif")]
                var row: [String: Any] = ["id": "notification-\(index)", "type": sample.0, "user": person,
                    "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(-index * 180 - 60)))]
                if sample.0 == "app" { row["header"] = "ぐりすぺからのお知らせ"; row["body"] = sample.2 }
                else if sample.0 != "follow" {
                    var note = reactionNote("notification-note-\(index)")
                    note["text"] = sample.2
                    note["reactionEmojis"] = ["synthetic_animation@.": originURL("synthetic-animated.gif")]
                    if sample.0 == "mention" { note["cw"] = "映画の感想（ネタバレあり）"; note["text"] = "SYNTHETIC HIDDEN SPOILER" }
                    row["note"] = note
                    if sample.0 == "reaction" { row["reaction"] = index == 0 ? ":synthetic_animation@.:" : "💚" }
                }
                return row
            }
            let types = body["includeTypes"] as? [String]
            result = body["untilId"] == nil ? rows.filter { types == nil || types!.contains($0["type"] as! String) } : []
        }
        else if notificationFixture && path == "/api/notifications/mark-all-as-read" {
            Self.store.notificationRead = true; status = 204; result = [String: String]()
        }
        else if notificationFixture && path == "/api/notes/show" { result = reactionNote(body["noteId"] as? String ?? "notification-note-0") }
        else if notificationFixture && path == "/api/users/show" {
            var person = user; person["id"] = body["userId"] ?? "notification-person-3"; person["name"] = "ましろ"
            result = person
        }
        else if notificationFixture && path == "/api/users/notes" { result = [] as [[String: Any]] }
        else if path == "/api/users/show", ProcessInfo.processInfo.arguments.contains("--native-name-emoji-fixture") { result = user }
        else if path == "/api/users/notes", ProcessInfo.processInfo.arguments.contains("--native-name-emoji-fixture") { result = [reactionNote()] }
        else if path == "/api/drive/files/create" {
            let multipart = String(decoding: data, as: UTF8.self)
            func field(_ name: String) -> String {
                multipart.components(separatedBy: "name=\"\(name)\"\r\n\r\n").dropFirst().first?.components(separatedBy: "\r\n--").first ?? ""
            }
            let id = "synthetic-file-\(Self.store.files.count + 1)"
            let file: [String: Any] = ["id": id, "name": field("name"), "comment": field("comment"), "isSensitive": field("isSensitive") == "true",
                "type": "image/png", "userId": "synthetic-composer", "url": originURL("/synthetic.png"), "size": data.count]
            Self.store.files[id] = file; result = file
        } else if path == "/api/drive/files/show", let id = body["fileId"] as? String, let file = Self.store.files[id] { result = file }
        else if path == "/api/drive/stream" { result = Array(Self.store.files.values) }
        else if path == "/api/notes/extended-reactions/show" {
            result = (body["noteIds"] as? [String] ?? []).map { id -> [String: Any] in
                ["noteId": id, "reactions": reactionCounts(),
                 "reactionEmojis": ["synthetic_animation@.": originURL("synthetic-animated.gif")],
                 "myReaction": Self.store.primaryReaction as Any? ?? NSNull(), "myReactions": reactionFixture ? Self.store.reactions : [], "complete": true, "shared": false]
            }
        } else if reactionFixture && ["/api/notes/extended-reactions/list", "/api/notes/reactions"].contains(path) {
            let value = body["type"] as? String ?? ""
            var actors: [[String: Any]] = Self.store.reactions.contains(where: { ClientEmojiSearch.equivalent($0, value) }) ? [user] : []
            if avatarFixture && value == "👍" {
                actors += [["id": "synthetic-other", "username": "other", "avatarUrl": originURL("synthetic-animated.gif")],
                           ["id": "synthetic-peer", "username": "peer", "host": "peer.ios.test", "avatarUrl": originURL("synthetic-animated.gif")]]
            }
            if (Self.store.liveOther[value] ?? 0) > 0 {
                actors.append(["id": Self.store.livePhase == 1 ? "live-first" : "live-second", "username": Self.store.livePhase == 1 ? "live-first" : "live-second", "avatarUrl": originURL("synthetic-animated.gif")])
            }
            result = actors.enumerated().map { index, actor in ["id": "synthetic-row-\(index)", "type": value, "user": actor] as [String: Any] }
        } else if reactionFixture && path == "/api/notes/show" {
            let id = body["noteId"] as? String ?? "synthetic-reaction-sheet"
            result = Self.store.notes.first { $0["id"] as? String == id } ?? reactionNote(id)
        }
        else if reactionFixture && ["/api/notes/reactions/create", "/api/notes/extended-reactions/create"].contains(path) {
            let raw = body["reaction"] as? String ?? "❤"
            let value = ClientEmojiSearch.localName(raw).map { ":" + $0 + "@.:" } ?? raw
            if path == "/api/notes/reactions/create" { Self.store.reactions = [] }
            if Self.store.reactions.isEmpty { Self.store.primaryReaction = value }
            if !Self.store.reactions.contains(value) { Self.store.reactions.append(value) }
            status = 204; result = [String: String]()
        } else if reactionFixture && ["/api/notes/reactions/delete", "/api/notes/extended-reactions/delete"].contains(path) {
            let raw = body["reaction"] as? String ?? Self.store.primaryReaction ?? ""
            let value = ClientEmojiSearch.localName(raw).map { ":" + $0 + "@.:" } ?? raw
            Self.store.reactions.removeAll { $0 == value }
            if Self.store.primaryReaction == value { Self.store.primaryReaction = nil }
            status = 204; result = [String: String]()
        } else if path == "/api/notes/create" {
            var note: [String: Any] = ["id": "synthetic-post-\(Self.store.notes.count + 1)", "createdAt": "2026-11-16T00:00:00Z",
                "visibility": body["visibility"] ?? "public", "text": body["text"] ?? "", "user": user]
            note["files"] = (body["fileIds"] as? [String] ?? []).compactMap { Self.store.files[$0] }
            Self.store.notes.insert(note, at: 0); result = ["createdNote": note]
        } else if path.hasSuffix("timeline") {
            if ProcessInfo.processInfo.arguments.contains("--native-retained-timeline-fixture") {
                Self.store.timelineReads[path, default: 0] += 1
                let read = Self.store.timelineReads[path]!
                let start = (body["untilId"] as? String).flatMap { Int($0.split(separator: "-").last ?? "") }.map { $0 + 1 } ?? 0
                let rows: [[String: Any]] = (min(start, 60)..<min(start + 30, 60)).map { index in
                    let feed = path.split(separator: "/").last.map(String.init) ?? "timeline"
                    var note = reactionNote("retained-\(feed)-\(read)-\(index)")
                    note["text"] = "Synthetic retained \(feed) read \(read) row \(index)"
                    return note
                }
                result = body["untilId"] == nil ? Self.store.notes + rows : rows
            } else if ProcessInfo.processInfo.arguments.contains("--native-pure-renote-fixture") {
                result = [reactionNote("synthetic-pure-renote"), reactionNote()]
            } else { result = reactionFixture ? [reactionNote(), reactionNote("synthetic-reaction-sheet-second")] : Self.store.notes }
        }
        else if path == "/api/emojis" {
            if ProcessInfo.processInfo.arguments.contains("--native-emoji-catalog-offline-fixture") {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            result = ["emojis": reactionFixture || notificationFixture ? [animationEmoji()] : []]
        }
        else if path == "/api/emoji" { result = animationEmoji() }
        else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let responseData = status == 204 ? Data() : try! JSONSerialization.data(withJSONObject: result)
        let deliver: @Sendable () -> Void = { [self] in
            deliveryLock.lock(); defer { deliveryLock.unlock() }
            guard !stopped else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseData); client?.urlProtocolDidFinishLoading(self)
        }
        if reactionFixture && ProcessInfo.processInfo.arguments.contains("--native-reaction-delay-fixture") && (path.hasSuffix("reactions/create") || path.hasSuffix("reactions/delete")) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: deliver)
        } else { deliver() }
    }
    static func requestData(_ request: URLRequest) -> Data {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 16 * 1024)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(bytes, count: count) }
        }
        return data
    }
    private func animationEmoji() -> [String: Any] {
        ["name": "synthetic_animation", "aliases": ["animation"], "url": originURL(Self.store.livePhase >= 3 ? "synthetic-updated.webp" : "synthetic-animated.gif"), "roleIdsThatCanBeUsedThisEmojiAsReaction": []]
    }
    private func originURL(_ path: String) -> String { Self.origin.url.appendingPathComponent(path).absoluteString }
    override func stopLoading() { deliveryLock.lock(); stopped = true; deliveryLock.unlock() }
}
#endif
