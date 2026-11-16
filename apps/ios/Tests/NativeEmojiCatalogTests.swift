// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

@MainActor
final class NativeEmojiCatalogTests: XCTestCase {
    func testEmojiBroadcastCanRefreshAFreshCachedCatalogWithoutWaitingForItsTTL() async throws {
        let cache = NativeEmojiCatalogCache(directory: directory), initial = CatalogAPI()
        _ = try await cache.catalog(origin: origin, api: initial)
        let updated = CatalogAPI(name: "updated"), model = NativeEmojiCatalog()
        await model.load(origin: origin, api: updated, cache: cache, force: true)
        XCTAssertEqual(model.items.first?.name, "updated")
        let calls = await updated.calls; XCTAssertEqual(calls, 1)
    }
    private var directory: URL!
    private let origin = try! ServerOrigin("https://catalog.ios.test")
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EmojiCatalog-" + UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    func testPublicCatalogIsReusedFromMemoryAndAfterRestartWithoutAnotherFetch() async throws {
        let api = CatalogAPI(), cache = NativeEmojiCatalogCache(directory: directory)
        let first = try await cache.catalog(origin: origin, api: api)
        let second = try await cache.catalog(origin: origin, api: api)
        XCTAssertEqual(first.map(\.name), ["synthetic"]); XCTAssertEqual(first, second)
        let restarted = NativeEmojiCatalogCache(directory: directory)
        let restored = await restarted.snapshot(origin: origin)
        XCTAssertEqual(restored, first)
        let offline = CatalogAPI(offline: true)
        let fromDisk = try await restarted.catalog(origin: origin, api: offline)
        XCTAssertEqual(fromDisk, first)
        let calls = await api.calls, offlineCalls = await offline.calls
        XCTAssertEqual(calls, 1); XCTAssertEqual(offlineCalls, 0)
        let backup = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(backup.isExcludedFromBackup, true)
        let other = await restarted.snapshot(origin: try ServerOrigin("https://other.ios.test"))
        XCTAssertNil(other)
    }
    func testExpiredCatalogAppearsBeforeDelayedRefreshAndIsReplacedAfterward() async throws {
        let clock = CatalogClock(), api = CatalogAPI(), cache = NativeEmojiCatalogCache(directory: directory, now: { clock.now })
        _ = try await cache.catalog(origin: origin, api: api); clock.advance(3601)
        let refreshing = CatalogAPI(name: "updated", hold: true), model = NativeEmojiCatalog()
        let task = Task { await model.load(origin: origin, api: refreshing, cache: cache) }
        for _ in 0..<200 { if await refreshing.waiting { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        let waiting = await refreshing.waiting; XCTAssertTrue(waiting)
        XCTAssertTrue(model.ready); XCTAssertEqual(model.items.first?.name, "synthetic"); XCTAssertNil(model.error)
        await refreshing.release(); await task.value
        XCTAssertEqual(model.items.first?.name, "updated")
    }
    func testOfflineRefreshKeepsUsableCatalogButDoesNotKeepEntriesBeyondSevenDays() async throws {
        let clock = CatalogClock(), api = CatalogAPI(), cache = NativeEmojiCatalogCache(directory: directory, now: { clock.now })
        _ = try await cache.catalog(origin: origin, api: api); clock.advance(3601)
        let offline = CatalogAPI(offline: true), model = NativeEmojiCatalog()
        await model.load(origin: origin, api: offline, cache: cache)
        XCTAssertEqual(model.items.first?.name, "synthetic"); XCTAssertNil(model.error)
        clock.advance(8 * 24 * 60 * 60)
        let expired = NativeEmojiCatalog()
        await expired.load(origin: origin, api: offline, cache: cache)
        XCTAssertFalse(expired.ready); XCTAssertTrue(expired.items.isEmpty); XCTAssertNotNil(expired.error)
    }
    func testConcurrentPickersShareTheCatalogRequestAndDropInvalidOrDuplicateNames() async throws {
        let cache = NativeEmojiCatalogCache(directory: directory), api = CatalogAPI(hold: true)
        let first = Task { try await cache.catalog(origin: origin, api: api) }
        for _ in 0..<200 { if await api.waiting { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        let second = Task { try await cache.catalog(origin: origin, api: api) }
        await api.release()
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a.map(\.name), ["synthetic"]); XCTAssertEqual(a, b)
        let calls = await api.calls; XCTAssertEqual(calls, 1)
    }
    func testRecentsMixCustomAndUnicodeInUseOrderAndSearchesTheWholeCatalog() throws {
        let ordinary = try catalogEmoji("synthetic"), sensitive = try catalogEmoji("sensitive", sensitive: true)
        let values = ["😂", ":synthetic@.:", "👍", ":synthetic:", ":deleted:", ":sensitive:"]
        let choices = NativeEmojiRecents.choices(values, custom: [ordinary, sensitive], query: "", showSensitive: false)
        XCTAssertEqual(choices.map(\.value), ["😂", ":synthetic:", "👍"])
        let custom = NativeEmojiRecents.choices([], custom: [ordinary], query: "synthetic", showSensitive: false)
        XCTAssertEqual(custom.map(\.value), [":synthetic:"])
        let unicode = NativeEmojiRecents.choices([], custom: [ordinary], query: "嬉し泣き", showSensitive: false)
        XCTAssertTrue(unicode.contains { $0.value == "😂" })
        let revealed = NativeEmojiRecents.choices(values, custom: [ordinary, sensitive], query: "", showSensitive: true)
        XCTAssertEqual(revealed.last?.value, ":sensitive:")
    }
}
private func catalogEmoji(_ name: String, sensitive: Bool = false) throws -> ClientCustomEmoji {
    try JSONDecoder().decode(ClientCustomEmoji.self, from: JSONSerialization.data(withJSONObject: ["name": name, "aliases": [], "url": "https://catalog.ios.test/emoji.png", "isSensitive": sensitive]))
}
private actor CatalogAPI: NativeEmojiAPI {
    var calls = 0
    let name: String, offline: Bool, hold: Bool
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    init(name: String = "synthetic", offline: Bool = false, hold: Bool = false) { self.name = name; self.offline = offline; self.hold = hold }
    func release() { continuation?.resume(); continuation = nil }
    func emojis() async throws -> [ClientCustomEmoji] {
        calls += 1
        if hold { await withCheckedContinuation { continuation = $0 } }
        if offline { throw URLError(.notConnectedToInternet) }
        return [try catalogEmoji(name), try catalogEmoji(name), try catalogEmoji("invalid@host")]
    }
    func emoji(_ name: String) throws -> ClientCustomEmoji { throw ClientAPIError.invalidResponse }
    func note(_ id: String) throws -> ClientNote { throw ClientAPIError.invalidResponse }
    func account() throws -> ClientUser { throw ClientAPIError.invalidResponse }
    func react(note: String, reaction: String, extended: Bool) {}
    func removeReaction(note: String, reaction: String?, extended: Bool) {}
}
private final class CatalogClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date.addTimeInterval(seconds); lock.unlock() }
}
