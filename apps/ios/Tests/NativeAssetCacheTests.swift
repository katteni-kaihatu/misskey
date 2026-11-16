// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import UIKit
import XCTest
@testable import GridSpace

@MainActor
final class NativeAssetCacheTests: XCTestCase {
    private var directory: URL!
    private let url = URL(string: "https://artwork.synthetic.example/emoji.png?revision=1")!
    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NativeArtwork-" + UUID().uuidString, isDirectory: true)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory); directory = nil
        try await super.tearDown()
    }
    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemYellow.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
    func testReusesArtworkInMemoryAndAfterRecreatingTheCacheWithoutSavingURLs() async throws {
        let bytes = png(), stub = ArtworkFetcher(data: png())
        let cache = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        let first = try await cache.data(for: url), second = try await cache.data(for: url)
        XCTAssertEqual(first, bytes); XCTAssertEqual(second, bytes)
        let restarted = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        let restored = try await restarted.data(for: url); XCTAssertEqual(restored, bytes)
        let requests = await stub.requests; XCTAssertEqual(requests.count, 1)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1); XCTAssertFalse(files[0].lastPathComponent.contains("emoji"))
        let record = try Data(contentsOf: files[0])
        XCTAssertNil(record.range(of: Data("artwork.synthetic.example".utf8)))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]); XCTAssertEqual(values.isExcludedFromBackup, true)
    }
    func testConcurrentRowsShareOneFetchAndCancelledWaiterDoesNotCancelOthers() async throws {
        let stub = ArtworkFetcher(data: png(), held: true)
        let cache = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        let first = Task { try await cache.data(for: url) }
        await stub.waitForRequest()
        let second = Task { try await cache.data(for: url) }
        first.cancel()
        await stub.release()
        let value = try await second.value; XCTAssertEqual(value, png())
        _ = try await first.value
        let requests = await stub.requests; XCTAssertEqual(requests.count, 1)
    }
    func testExpiresAndRevalidatesWithETagAndLastModifiedThenReuses304() async throws {
        let clock = ArtworkClock(), stub = ArtworkFetcher(data: png())
        await stub.setHeaders(["Cache-Control": "public, max-age=60", "ETag": "synthetic-v1", "Last-Modified": "Mon, 16 Nov 2026 00:00:00 GMT"])
        let cache = NativeAssetCache(directory: directory, now: { clock.now }, fetch: { try await stub.fetch($0, $1) })
        _ = try await cache.data(for: url); clock.advance(61)
        await stub.setStatus(304)
        let value = try await cache.data(for: url); XCTAssertEqual(value, png())
        _ = try await cache.data(for: url)
        let requests = await stub.requests; XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1]["If-None-Match"], "synthetic-v1")
        XCTAssertEqual(requests[1]["If-Modified-Since"], "Mon, 16 Nov 2026 00:00:00 GMT")
    }
    func testNoStoreDoesNotLeaveMemoryOrDiskEntries() async throws {
        let stub = ArtworkFetcher(data: png())
        await stub.setHeaders(["Cache-Control": "no-store"])
        let cache = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        _ = try await cache.data(for: url); _ = try await cache.data(for: url)
        let requests = await stub.requests; XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)
    }
    func testNoCacheRemainsRevalidationOnlyWhen304OmitsCacheControl() async throws {
        let stub = ArtworkFetcher(data: png())
        await stub.setHeaders(["Cache-Control": "no-cache", "ETag": "synthetic-v1"])
        let cache = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        _ = try await cache.data(for: url)
        await stub.setHeaders([:]); await stub.setStatus(304)
        _ = try await cache.data(for: url); _ = try await cache.data(for: url)
        let requests = await stub.requests; XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2]["If-None-Match"], "synthetic-v1")
    }
    func testOfflineFallbackIsBoundedAndHTTPRejectionRemovesOldArtwork() async throws {
        let clock = ArtworkClock(), stub = ArtworkFetcher(data: png())
        let cache = NativeAssetCache(directory: directory, now: { clock.now }, fetch: { try await stub.fetch($0, $1) })
        _ = try await cache.data(for: url); clock.advance(25 * 60 * 60)
        await stub.setOffline(true)
        let offline = try await cache.data(for: url); XCTAssertEqual(offline, png())
        await stub.setOffline(false); await stub.setStatus(404)
        do { _ = try await cache.data(for: url); XCTFail("Do not reuse artwork after rejection") } catch {}
        await stub.setOffline(true)
        do { _ = try await cache.data(for: url); XCTFail("Rejected entry must be removed") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)
    }
    func testSevenDayLimitAndMustRevalidateNeverServeExpiredOfflineArtwork() async throws {
        for control in ["public, max-age=60", "max-age=60, must-revalidate"] {
            let clock = ArtworkClock(), stub = ArtworkFetcher(data: png())
            await stub.setHeaders(["Cache-Control": control])
            let cache = NativeAssetCache(directory: directory.appendingPathComponent(UUID().uuidString), now: { clock.now }, fetch: { try await stub.fetch($0, $1) })
            _ = try await cache.data(for: url)
            clock.advance(control.contains("must-revalidate") ? 61 : 8 * 24 * 60 * 60)
            await stub.setOffline(true)
            do { _ = try await cache.data(for: url); XCTFail("Expired artwork cannot be served") } catch {}
        }
    }
    func testCorruptDiskEntryIsRefetchedAndInvalidResponsesAreNotCached() async throws {
        let stub = ArtworkFetcher(data: png())
        let cache = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        _ = try await cache.data(for: url)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("corrupt".utf8).write(to: file)
        let restarted = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        let value = try await restarted.data(for: url); XCTAssertEqual(value, png())
        let requests = await stub.requests; XCTAssertEqual(requests.count, 2)
        let invalid = NativeAssetCache(directory: directory.appendingPathComponent("invalid"), fetch: { _, _ in .init(status: 200, data: Data("<html>error</html>".utf8)) })
        do { _ = try await invalid.data(for: url); XCTFail("Only images may enter the artwork cache") } catch {}
    }
    func testDiskBudgetEvictsOldArtworkAndQueryRevisionUsesADifferentEntry() async throws {
        let clock = ArtworkClock(), stub = ArtworkFetcher(data: png())
        let cache = NativeAssetCache(directory: directory, diskLimit: 1024, memoryLimit: 0, now: { clock.now }, fetch: { try await stub.fetch($0, $1) })
        _ = try await cache.data(for: url)
        for index in 2...8 {
            clock.advance(1)
            _ = try await cache.data(for: URL(string: "https://artwork.synthetic.example/emoji.png?revision=\(index)")!)
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let size = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(size, 1024); XCTAssertLessThan(files.count, 8)
        _ = try await cache.data(for: url)
        let requests = await stub.requests; XCTAssertEqual(requests.count, 9)
    }
    func testRejectsHTTPAndCredentialBearingURLsBeforeFetching() async throws {
        let stub = ArtworkFetcher(data: png())
        let cache = NativeAssetCache(directory: directory, fetch: { try await stub.fetch($0, $1) })
        for value in ["http://artwork.synthetic.example/x.png", "https://user:password@artwork.synthetic.example/x.png"] {
            do { _ = try await cache.data(for: URL(string: value)!); XCTFail("Reject unsafe artwork URL") } catch {}
        }
        let requests = await stub.requests; XCTAssertTrue(requests.isEmpty)
    }
}

private final class ArtworkClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(interval) }
}
private actor ArtworkFetcher {
    let data: Data
    var held: Bool
    var headers: [String: String] = [:]
    var status = 200
    var offline = false
    var requests: [[String: String]] = []
    var waiter: CheckedContinuation<Void, Never>?
    var releaseWaiter: CheckedContinuation<Void, Never>?
    init(data: Data, held: Bool = false) { self.data = data; self.held = held }
    func fetch(_ url: URL, _ headers: [String: String]) async throws -> NativeAssetCache.Response {
        requests.append(headers); waiter?.resume(); waiter = nil
        if held { await withCheckedContinuation { releaseWaiter = $0 } }
        if offline { throw URLError(.notConnectedToInternet) }
        return .init(status: status, data: status == 304 ? Data() : data, headers: self.headers)
    }
    func waitForRequest() async { if requests.isEmpty { await withCheckedContinuation { waiter = $0 } } }
    func release() { held = false; releaseWaiter?.resume(); releaseWaiter = nil }
    func setHeaders(_ value: [String: String]) { headers = value }
    func setStatus(_ value: Int) { status = value }
    func setOffline(_ value: Bool) { offline = value }
}
