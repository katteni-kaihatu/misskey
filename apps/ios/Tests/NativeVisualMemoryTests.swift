// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import XCTest
@testable import GridSpace

@MainActor
final class NativeVisualMemoryTests: XCTestCase {
    func testRecycledRowsReuseDecodedMediaWithoutAnotherDownloadAndClearInvalidatesIt() async throws {
        var downloads = 0
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in UIColor.systemPurple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10)) }
        let memory = NativeVisualMemory { _, _, _ in downloads += 1; return image }
        let url = URL(string: "https://media.ios.test/owned.png")!
        let first = await memory.image(url, pixels: 1200, artwork: false)
        let second = await memory.image(url, pixels: 1200, artwork: false)
        XCTAssertTrue(first === second); XCTAssertEqual(downloads, 1); XCTAssertNotNil(memory.cached(url, pixels: 1200))
        memory.clear(); XCTAssertNil(memory.cached(url, pixels: 1200))
        _ = await memory.image(url, pixels: 1200, artwork: false); XCTAssertEqual(downloads, 2)
    }
    func testClearingPrivateMediaRejectsAllWaitersAndParsedBodies() async throws {
        var gate: CheckedContinuation<Void, Never>?
        let image = UIImage(systemName: "photo")!
        let memory = NativeVisualMemory { _, _, _ in await withCheckedContinuation { gate = $0 }; return image }
        let url = URL(string: "https://media.ios.test/private.png")!
        let first = Task { await memory.image(url, pixels: 1200, artwork: false) }
        for _ in 0..<200 { if gate != nil { break }; await Task.yield() }
        let second = Task { await memory.image(url, pixels: 1200, artwork: false) }
        await Task.yield()
        memory.store(try await MFMParser.shared.parse("Synthetic private body"), text: "Synthetic private body")
        XCTAssertNotNil(memory.nodes("Synthetic private body"))
        memory.clear(); gate?.resume()
        let a = await first.value, b = await second.value
        XCTAssertNil(a); XCTAssertNil(b); XCTAssertNil(memory.nodes("Synthetic private body"))
    }
    func testInlineEmojiHasItsFinalBoundsBeforeTheImageArrivesAndCopyKeepsTheName() async throws {
        let nodes = try await MFMParser.shared.parse("before :synthetic: after")
        let result = NativeMFMRenderer(origin: try ServerOrigin("https://media.ios.test"), authorHost: nil, emojis: [:], fontSize: 17, revealed: []).render(nodes)
        var bounds: CGRect?
        result.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { bounds = attachment.bounds }
        }
        XCTAssertGreaterThan(try XCTUnwrap(bounds).height, 0)
        XCTAssertEqual(bounds?.width, bounds?.height)
        XCTAssertEqual(NativeMFMCopy.text(result.text), "before :synthetic: after")
    }
    func testUpcomingPreviewWindowUsesThumbnailsAndSkipsCWAndSensitiveFiles() throws {
        func note(_ id: String, cw: Bool = false, hidden: Bool = false, sensitive: Bool = false) throws -> ClientNote {
            var value: [String: Any] = ["id": id, "createdAt": "2026-11-16T00:00:00Z", "visibility": "public", "isHidden": hidden,
                "user": ["id": "synthetic", "username": "synthetic"],
                "files": [["id": id, "name": "Owned image", "type": "image/png", "isSensitive": sensitive,
                           "url": "https://media.ios.test/\(id)-original.png", "thumbnailUrl": "https://media.ios.test/\(id)-thumb.png"]]]
            if cw { value["cw"] = "Synthetic CW" }
            return try JSONDecoder().decode(ClientNote.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let notes = try [note("head"), note("visible"), note("cw", cw: true), note("sensitive", sensitive: true), note("outside")]
        XCTAssertEqual(NativeVisualMemory.upcomingPreviews(after: "head", in: notes).map(\.lastPathComponent), ["visible-thumb.png"])
        XCTAssertTrue(NativeVisualMemory.upcomingPreviews(after: "missing", in: notes).isEmpty)
        XCTAssertTrue(NativeVisualMemory.upcomingPreviews(after: "head", in: try [note("head"), note("hidden", hidden: true)]).isEmpty)
    }
    func testVisibleRequestSharesPrefetchAndReusesItsDecodedImage() async throws {
        var downloads = 0
        var gate: CheckedContinuation<UIImage?, Never>?
        let memory = NativeVisualMemory { _, _, _ in downloads += 1; return await withCheckedContinuation { gate = $0 } }
        let url = URL(string: "https://media.ios.test/owned-preview.png")!, image = UIImage(systemName: "photo")!
        memory.prefetch([url, url])
        for _ in 0..<200 { if gate != nil { break }; await Task.yield() }
        XCTAssertNotNil(gate)
        let visible = Task { await memory.image(url, pixels: 1200, artwork: false) }
        await Task.yield(); gate?.resume(returning: image)
        let result = await visible.value
        XCTAssertTrue(result === image); XCTAssertEqual(downloads, 1)
        XCTAssertTrue(memory.cached(url, pixels: 1200) === image)
        memory.clear()
    }
    func testPrefetchIsBoundedReplacesQueuedWorkAndCannotRefillAfterClear() async {
        var started: [URL] = [], gates: [URL: CheckedContinuation<UIImage?, Never>] = [:]
        let memory = NativeVisualMemory { url, _, _ in
            started.append(url); return await withCheckedContinuation { gates[url] = $0 }
        }
        let urls = (0..<6).map { URL(string: "https://media.ios.test/owned-\($0).png")! }
        memory.prefetch(Array(urls.prefix(4)))
        for _ in 0..<200 { if started.count == 2 { break }; await Task.yield() }
        XCTAssertEqual(started, Array(urls.prefix(2)))
        memory.prefetch(Array(urls.suffix(2)))
        gates.removeValue(forKey: urls[0])?.resume(returning: UIImage(systemName: "photo"))
        for _ in 0..<200 { if started.count == 3 { break }; await Task.yield() }
        XCTAssertEqual(started.last, urls[4]); XCTAssertEqual(started.count, 3)
        memory.clear()
        let remaining = Array(gates.values); gates = [:]
        for gate in remaining { gate.resume(returning: nil) }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(started.count, 3); XCTAssertNil(memory.cached(urls[0], pixels: 1200))
    }
}
