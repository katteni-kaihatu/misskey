// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Reuse media connections and append URLSession's data chunks, rather than
/// creating a session and awaiting every individual byte for every image.
/// The response remains bounded in memory; note media is never written to disk.
final class NativeImageTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = NativeImageTransport()
    private final class Pending {
        let continuation: CheckedContinuation<NativeAssetCache.Response, Error>
        var response: HTTPURLResponse?
        var data = Data()
        init(_ continuation: CheckedContinuation<NativeAssetCache.Response, Error>) { self.continuation = continuation }
    }
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false
        func attach(_ task: URLSessionDataTask) {
            lock.lock(); self.task = task; let cancelled = cancelled; lock.unlock()
            if cancelled { task.cancel() }
        }
        func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
    }
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private let trust = NativeEmojiTransport()
    private var session: URLSession!
    private let maximumBytes: Int

    init(configuration: URLSessionConfiguration? = nil, maximumBytes: Int = NativeAssetCache.maximumDownload) {
        self.maximumBytes = maximumBytes
        super.init()
        let config = configuration ?? .ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": NativeHTTP.userAgent]
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 6
        #if DEBUG
        if configuration == nil {
            var protocols: [AnyClass] = []
            if NativeComposerFixture.enabled { protocols.append(NativeComposerFixture.self) }
            if NativeTimelineFixture.enabled { protocols.append(NativeTimelineFixture.self) }
            if !protocols.isEmpty { config.protocolClasses = protocols }
            LocalParityServer.current?.configureControlSession(config)
        }
        #endif
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }
    func invalidate() { session.invalidateAndCancel() }
    func data(_ url: URL, headers: [String: String] = [:]) async throws -> NativeAssetCache.Response {
        guard clientImageURL(url.absoluteString) != nil else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        // Media never receives the app's token, ambient cookies or credentials.
        for (key, value) in headers where ["if-none-match", "if-modified-since"].contains(key.lowercased()) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                lock.lock(); pending[task.taskIdentifier] = Pending(continuation); lock.unlock()
                cancellation.attach(task); task.resume()
            }
        } onCancel: { cancellation.cancel() }
    }
    private func finish(_ task: URLSessionTask, _ result: Result<NativeAssetCache.Response, Error>) {
        lock.lock(); let item = pending.removeValue(forKey: task.taskIdentifier); lock.unlock()
        item?.continuation.resume(with: result)
    }
    private func response(_ http: HTTPURLResponse, data: Data) -> NativeAssetCache.Response {
        var fields: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        return .init(status: http.statusCode, data: data, headers: fields)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, clientImageURL(http.url?.absoluteString) != nil else {
            finish(dataTask, .failure(URLError(.badServerResponse))); completionHandler(.cancel); return
        }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
            finish(dataTask, .success(self.response(http, data: Data()))); completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= maximumBytes else {
            finish(dataTask, .failure(URLError(.dataLengthExceedsMaximum))); completionHandler(.cancel); return
        }
        lock.lock()
        pending[dataTask.taskIdentifier]?.response = http
        pending[dataTask.taskIdentifier]?.data.reserveCapacity(min(maximumBytes, max(0, min(64 * 1024, Int(response.expectedContentLength)))))
        lock.unlock()
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let item = pending[dataTask.taskIdentifier] else { lock.unlock(); return }
        guard data.count <= maximumBytes - item.data.count else {
            lock.unlock(); finish(dataTask, .failure(URLError(.dataLengthExceedsMaximum))); dataTask.cancel(); return
        }
        item.data.append(data)
        lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let item = pending.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let item else { return }
        if let error { item.continuation.resume(throwing: error) }
        else if let http = item.response { item.continuation.resume(returning: response(http, data: item.data)) }
        else { item.continuation.resume(throwing: URLError(.badServerResponse)) }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trust.urlSession(session, didReceive: challenge)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trust.urlSession(session, task: task, didReceive: challenge)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, clientImageURL(url.absoluteString) != nil else { return nil }
        var clean = URLRequest(url: url); clean.httpShouldHandleCookies = false
        if url.host == response.url?.host && url.port == response.url?.port {
            for name in ["If-None-Match", "If-Modified-Since"] { clean.setValue(request.value(forHTTPHeaderField: name), forHTTPHeaderField: name) }
        }
        return clean
    }
}
