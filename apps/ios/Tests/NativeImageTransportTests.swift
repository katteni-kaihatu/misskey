// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import GridSpace

@MainActor
final class NativeImageTransportTests: XCTestCase {
    private func transport(maximumBytes: Int = 2 * 1024 * 1024) -> NativeImageTransport {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImageSpeedProtocol.self]
        return NativeImageTransport(configuration: config, maximumBytes: maximumBytes)
    }
    private func url(_ path: String) -> URL { URL(string: "https://images.ios.test/" + path)! }
    func testChunkedDownloadPreservesBytesAndOnlySendsMediaHeaders() async throws {
        let transport = transport(); defer { transport.invalidate() }
        let response = try await transport.data(url("chunked"), headers: ["If-None-Match": "owned-v1", "Authorization": "synthetic-do-not-forward", "Cookie": "synthetic=ignore"])
        XCTAssertEqual(response.status, 200); XCTAssertEqual(response.data, ImageSpeedProtocol.payload)
        let request = try XCTUnwrap(ImageSpeedProtocol.capture.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "owned-v1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }
    func testDeclaredAndChunkedOverflowAreRejectedAndSessionStillWorks() async throws {
        let transport = transport(maximumBytes: 128 * 1024); defer { transport.invalidate() }
        for path in ["known-overflow", "unknown-overflow"] {
            do { _ = try await transport.data(url(path)); XCTFail("Bound the response before accumulating oversized media") }
            catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
        }
        let response = try await transport.data(url("small")); XCTAssertEqual(response.data.count, 1024)
    }
    func testCancellationCompletesAndDoesNotPreventAnotherImageLoading() async throws {
        let transport = transport(); defer { transport.invalidate() }
        let task = Task { try await transport.data(url("held")) }
        try await Task.sleep(nanoseconds: 30_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must release its waiter") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        let response = try await transport.data(url("small")); XCTAssertEqual(response.status, 200)
        let cancelled = Task { try await transport.data(url("held")) }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancellation before task registration must finish") } catch {}
    }
    func testRejectionsAnd304ReachTheCacheWithoutBeingMistakenForImages() async throws {
        let transport = transport(); defer { transport.invalidate() }
        let rejected = try await transport.data(url("not-found"))
        XCTAssertEqual(rejected.status, 404); XCTAssertTrue(rejected.data.isEmpty)
        let unchanged = try await transport.data(url("not-modified"))
        XCTAssertEqual(unchanged.status, 304); XCTAssertTrue(unchanged.data.isEmpty)
        let created = try await transport.data(url("created"))
        XCTAssertEqual(created.status, 201); XCTAssertEqual(created.data, ImageSpeedProtocol.payload)
        for value in ["http://images.ios.test/small", "https://user:synthetic@images.ios.test/small"] {
            do { _ = try await transport.data(URL(string: value)!); XCTFail("Reject unsafe URLs") }
            catch { XCTAssertEqual((error as? URLError)?.code, .badURL) }
        }
    }
    func testRedirectKeepsHTTPSAndDropsCredentialsAndCrossHostValidators() async throws {
        let transport = transport(); defer { transport.invalidate() }
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url("small"))
        let response = HTTPURLResponse(url: url("small"), statusCode: 302, httpVersion: nil, headerFields: [:])!
        var request = URLRequest(url: URL(string: "https://other.ios.test/image")!)
        request.setValue("synthetic", forHTTPHeaderField: "Authorization"); request.setValue("synthetic", forHTTPHeaderField: "Cookie")
        request.setValue("owned-v1", forHTTPHeaderField: "If-None-Match")
        let result = await transport.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request)
        XCTAssertNotNil(result); XCTAssertNil(result?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(result?.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(result?.value(forHTTPHeaderField: "If-None-Match"))
        let insecure = await transport.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "http://other.ios.test/image")!))
        XCTAssertNil(insecure)
    }
    func testSyntheticOneMiBTransferBenchmark() async throws {
        let transport = transport(); defer { transport.invalidate() }
        var old: [Double] = [], chunks: [Double] = []
        for _ in 0..<3 {
            var start = ProcessInfo.processInfo.systemUptime
            let original = try await Self.bytewiseBaseline(url("chunked")); old.append(ProcessInfo.processInfo.systemUptime - start)
            start = ProcessInfo.processInfo.systemUptime
            let improved = try await transport.data(url("chunked")); chunks.append(ProcessInfo.processInfo.systemUptime - start)
            XCTAssertEqual(original, improved.data)
        }
        print(String(format: "GRIDSPACE_IMAGE_TRANSPORT_BENCHMARK bytes=%d bytewise_median_ms=%.3f chunks_median_ms=%.3f", ImageSpeedProtocol.payload.count, old.sorted()[1] * 1000, chunks.sorted()[1] * 1000))
    }
    private nonisolated static func bytewiseBaseline(_ url: URL) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.protocolClasses = [ImageSpeedProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let (bytes, _) = try await session.bytes(for: URLRequest(url: url))
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }
}

private final class ImageSpeedProtocol: URLProtocol, @unchecked Sendable {
    static let payload = Data(repeating: 0x5A, count: 1024 * 1024)
    final class Capture: @unchecked Sendable {
        private let lock = NSLock(); private var value: URLRequest?
        var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return value }
        func store(_ request: URLRequest) { lock.lock(); value = request; lock.unlock() }
    }
    static let capture = Capture()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "images.ios.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capture.store(request)
        let path = request.url!.lastPathComponent
        let count = path == "small" ? 1024 : Self.payload.count
        var headers = ["Content-Type": "image/png"]
        if path != "unknown-overflow" { headers["Content-Length"] = String(count) }
        let status = path == "not-found" ? 404 : path == "not-modified" ? 304 : path == "created" ? 201 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        if path == "held" { return }
        if (200..<300).contains(status) {
            for start in stride(from: 0, to: count, by: 32 * 1024) {
                client?.urlProtocol(self, didLoad: Self.payload.subdata(in: start..<min(count, start + 32 * 1024)))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
