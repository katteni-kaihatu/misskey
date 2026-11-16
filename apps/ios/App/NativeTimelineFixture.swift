// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
import Foundation
import GridSpaceCore

/// Deterministic, offline gesture QA. Never registers with the shared session.
final class NativeTimelineFixture: URLProtocol, @unchecked Sendable {
    static let origin = try! ServerOrigin("https://refresh.ios.test")
    static var enabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--native-client-fixture") && arguments.contains("--native-refresh-fixture")
    }
    private final class Counter: @unchecked Sendable {
        let lock = NSLock(); var values: [String: Int] = [:]
        func next(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; values[path, default: 0] += 1; return values[path]! }
    }
    private static let counter = Counter()
    private var work: DispatchWorkItem?
    static func events(_ feed: ClientFeedTab) -> AsyncThrowingStream<NativeTimelineEvent, Error> {
        guard ProcessInfo.processInfo.arguments.contains("--native-live-fixture") else { return AsyncThrowingStream { $0.finish() } }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.connected)
                    for index in 1...120 {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        let user: [String: Any] = ["id": "synthetic-live-author", "username": "live-fixture", "host": index % 2 == 0 ? "peer.ios.test" as Any : NSNull()]
                        var note: [String: Any] = ["id": "synthetic-live-\(index)", "createdAt": ISO8601DateFormatter().string(from: Date()), "visibility": "public", "gridspaceShared": true, "text": "Synthetic live \(index)", "user": user]
                        if case .channel(let id, _) = feed { note["channelId"] = id }
                        let packet: [String: Any] = ["type": "channel", "body": ["id": "fixture", "type": "note", "body": note]]
                        if let event = try NativeTimelineSocket.decode(JSONSerialization.data(withJSONObject: packet), id: "fixture") { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == origin.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/owned-photo.gif" || request.url?.path == "/owned-emoji.gif" {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/gif", "Cache-Control": "public, max-age=86400"])!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: NativeComposerFixture.animatedGIF); self.client?.urlProtocolDidFinishLoading(self)
            }
            self.work = work; DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work); return
        }
        if request.url?.path == "/api/notes/extended-reactions/show" {
            let body = (try? JSONSerialization.jsonObject(with: NativeComposerFixture.requestData(request))) as? [String: Any]
            let states: [[String: Any]] = (body?["noteIds"] as? [String] ?? []).map { ["noteId": $0, "reactions": [String: Int](), "reactionEmojis": [String: String](), "myReaction": NSNull(), "myReactions": [String](), "complete": true, "shared": false] }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: states)); client?.urlProtocolDidFinishLoading(self); return
        }
        let path = request.url?.path ?? ""
        let body = (try? JSONSerialization.jsonObject(with: NativeComposerFixture.requestData(request))) as? [String: Any] ?? [:]
        if path == "/api/channels/search" {
            let query = body["query"] as? String ?? ""
            let rows: [[String: Any]]
            if !query.isEmpty { rows = query.lowercased().contains("music") ? [["id": "fixture-music", "name": "Synthetic music", "description": "Owned channel fixture", "isArchived": false]] : [] }
            else { rows = (body["untilId"] == nil ? Array(0..<30) : [30]).map { ["id": "fixture-channel-\($0)", "name": "Synthetic channel \($0)", "isArchived": false] } }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: rows)); client?.urlProtocolDidFinishLoading(self); return
        }
        guard ["/api/notes/local-timeline", "/api/notes/global-timeline", "/api/channels/timeline"].contains(path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        let channel = path == "/api/channels/timeline" ? body["channelId"] as? String : nil
        let batch = Self.counter.next(path + (channel ?? ""))
        let paging = ProcessInfo.processInfo.arguments.contains("--native-pagination-fixture")
        let until = body["untilId"] as? String
        let attempt = Self.counter.next(path + "/page/" + (until ?? "head"))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if paging && until == "auto-row-29" && attempt == 1 && ProcessInfo.processInfo.arguments.contains("--native-pagination-failure") {
                self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            if batch == 2 && ProcessInfo.processInfo.arguments.contains("--native-refresh-failure") {
                self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            let start = paging ? (until == "auto-row-29" ? 30 : until == "auto-row-59" ? 60 : until == nil ? 0 : 61) : 0
            let end = paging ? min(start + 30, 61) : 30
            let rows: [[String: Any]] = (start..<end).map { index in
                var note: [String: Any] = ["id": index == 0 ? "refresh-batch-\(batch)" : "refresh-row-\(index)",
                 "createdAt": "2026-11-16T00:00:00Z", "visibility": "public",
                 "text": index == 0 ? "Synthetic refresh batch \(batch)" : "Synthetic refresh row \(index)",
                 "user": ["id": "synthetic-refresh-author", "username": "refresh-fixture"]]
                if let channel {
                    note["channelId"] = channel
                    note["text"] = index == 0 ? "Synthetic channel timeline batch \(batch)" : "Synthetic channel row \(index)"
                    note["id"] = channel + "-\(batch)-\(index)"
                }
                if paging {
                    note["id"] = "auto-row-\(index)"; note["text"] = "Auto timeline row \(index)"
                    note["gridspaceShared"] = true
                    note["user"] = ["id": "synthetic-paging-author", "username": "paging-fixture", "host": index % 2 == 0 ? "peer.ios.test" as Any : NSNull()]
                }
                if ProcessInfo.processInfo.arguments.contains("--native-media-cache-fixture"), index == 0 {
                    note["files"] = [["id": "owned-photo", "name": "Owned synthetic photo", "type": "image/gif", "url": Self.origin.url.appendingPathComponent("owned-photo.gif").absoluteString, "isSensitive": false]]
                    note["emojis"] = ["fixture_wave": Self.origin.url.appendingPathComponent("owned-emoji.gif").absoluteString]
                    note["text"] = "Synthetic fixed media :fixture_wave:"
                }
                return note
            }
            let data = try! JSONSerialization.data(withJSONObject: rows)
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data); self.client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    override func stopLoading() { work?.cancel(); work = nil }
}
#endif
