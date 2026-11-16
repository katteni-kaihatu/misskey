// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GridSpaceCore

enum NativeTimelineEvent: Sendable { case connected; case note(ClientNote); case noteChanged(id: String, deleted: Bool); case emojiCatalogChanged }
struct NativeTimelineSubscription: Sendable {
    let events: AsyncThrowingStream<NativeTimelineEvent, Error>
    let cancel: @Sendable () -> Void
    var watch: @Sendable ([String]) async throws -> Void = { _ in }
}
protocol NativeTimelineLiveAPI: NativeTimelineAPI {
    func timelineEvents(_ feed: ClientFeedTab) async throws -> NativeTimelineSubscription
    func prepareLiveNotes(_ notes: [ClientNote]) async throws -> [ClientNote]
}

enum NativeTimelineSocket {
    static func subscription(_ feed: ClientFeedTab, id: String) throws -> String {
        let channel: String, params: [String: Any]
        switch feed {
        case .timeline(.home): channel = "homeTimeline"; params = [:]
        case .timeline(.local): channel = "localTimeline"; params = ["withReplies": false]
        case .timeline(.global): channel = "globalTimeline"; params = [:]
        case .channel(let value, _): channel = "channel"; params = ["channelId": value]
        case .peerChannel: throw ClientAPIError.invalidResponse // Private proxy snapshots use their own cursor and validation.
        }
        let data = try JSONSerialization.data(withJSONObject: ["type": "connect", "body": ["id": id, "channel": channel, "params": params, "pong": true]])
        return String(decoding: data, as: UTF8.self)
    }
    static func decode(_ data: Data, id: String) throws -> NativeTimelineEvent? {
        guard data.count <= 2 * 1024 * 1024 else { throw ClientAPIError.responseTooLarge }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if ["emojiAdded", "emojiUpdated", "emojiDeleted"].contains(value["type"] as? String ?? "") { return .emojiCatalogChanged }
        guard let body = value["body"] as? [String: Any] else { return nil }
        if value["type"] as? String == "noteUpdated", let noteID = body["id"] as? String,
           ClientFeedTab.validChannelID(noteID), ["reacted", "unreacted", "extendedReactionUpdated", "deleted"].contains(body["type"] as? String ?? "") {
            return .noteChanged(id: noteID, deleted: body["type"] as? String == "deleted")
        }
        guard body["id"] as? String == id else { return nil }
        if value["type"] as? String == "connected" { return .connected }
        guard value["type"] as? String == "channel", body["type"] as? String == "note", let raw = body["body"] as? [String: Any] else { return nil }
        return .note(try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: raw)))
    }
    static func ping(_ task: URLSessionWebSocketTask) async throws {
        let watchdog = Task { try await Task.sleep(nanoseconds: 10_000_000_000); task.cancel(with: .goingAway, reason: nil) }
        defer { watchdog.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
    }
    static func open(_ task: URLSessionWebSocketTask, feed: ClientFeedTab?) throws -> NativeTimelineSubscription {
        let id = UUID().uuidString, subscription = try feed.map { try subscription($0, id: id) }
        let writer = NativeNoteSocketWriter(task: task)
        task.maximumMessageSize = 2 * 1024 * 1024
        let events = AsyncThrowingStream<NativeTimelineEvent, Error>(bufferingPolicy: .bufferingOldest(256)) { continuation in
            task.resume()
            let reader = Task {
                do {
                    if let subscription { try await task.send(.string(subscription)) }
                    else { try await ping(task); continuation.yield(.connected) }
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let data: Data
                        switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: continue }
                        if let event = try decode(data, id: id) {
                            if case .dropped = continuation.yield(event) { throw ClientAPIError.responseTooLarge }
                        }
                    }
                    continuation.finish()
                } catch {
                    if let response = task.response as? HTTPURLResponse, [401, 403].contains(response.statusCode) {
                        continuation.finish(throwing: ClientAPIError.rejected(status: response.statusCode, code: "STREAM_AUTHENTICATION_FAILED"))
                    } else { continuation.finish(throwing: error) }
                }
            }
            let heartbeat = Task {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 20_000_000_000)
                        try await ping(task)
                    }
                } catch { task.cancel(with: .goingAway, reason: nil) }
            }
            continuation.onTermination = { _ in reader.cancel(); heartbeat.cancel(); task.cancel(with: .goingAway, reason: nil) }
        }
        return NativeTimelineSubscription(events: events, cancel: { task.cancel(with: .goingAway, reason: nil) }, watch: { try await writer.set($0) })
    }
}

private actor NativeNoteSocketWriter {
    let task: URLSessionWebSocketTask
    private var current = Set<String>(), desired = Set<String>(), sending = false
    init(task: URLSessionWebSocketTask) { self.task = task }
    func set(_ ids: [String]) async throws {
        guard ids.count <= 128, ids.allSatisfy(ClientFeedTab.validChannelID) else { throw ClientAPIError.invalidResponse }
        desired = Set(ids)
        guard !sending else { return }
        sending = true; defer { sending = false }
        while current != desired {
            let removing = current.subtracting(desired).sorted().first
            guard let id = removing ?? desired.subtracting(current).sorted().first else { break }
            let data = try JSONSerialization.data(withJSONObject: ["type": removing == nil ? "subNote" : "unsubNote", "body": ["id": id]])
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
            if removing == nil { current.insert(id) } else { current.remove(id) }
        }
    }
}
