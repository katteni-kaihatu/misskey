// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import UIKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GridSpace

@MainActor
final class NativeEmojiAnimationTests: XCTestCase {
    func testGIFAndWebPKeepFrameDelaysAndRenderDifferentFrames() throws {
        for bytes in [NativeComposerFixture.animatedGIF, NativeComposerFixture.animatedWebP] {
            let frames = try XCTUnwrap(NativeEmojiFrames(bytes))
            XCTAssertEqual(frames.frameCount, 2); XCTAssertEqual(frames.duration, 0.32, accuracy: 0.03)
            XCTAssertEqual(frames.index(at: 0), 0); XCTAssertEqual(frames.index(at: 0.18), 1)
            XCTAssertEqual(frames.index(at: 0.34), 0)
            let first = try XCTUnwrap(frames.image(at: 0)?.pngData()), second = try XCTUnwrap(frames.image(at: 1)?.pngData())
            XCTAssertNotEqual(first, second)
            let view = NativeEmojiImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
            view.load(bytes); view.render(at: 0.18)
            XCTAssertEqual(view.image?.pngData(), second)
            view.allowPlayback(false)
            XCTAssertEqual(view.image?.pngData(), first); XCTAssertFalse(view.animationRunning)
            view.load(nil); XCTAssertNil(view.image); XCTAssertNil(view.frames)
        }
    }
    func testAPNGAndInlineAttachmentKeepTheAnimatedBytes() throws {
        let gif = try XCTUnwrap(NativeEmojiFrames(NativeComposerFixture.animatedGIF))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
        for index in 0..<2 {
            CGImageDestinationAddImage(destination, try XCTUnwrap(gif.image(at: index)?.cgImage), [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.16]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let frames = try XCTUnwrap(NativeEmojiFrames(bytes as Data)); XCTAssertEqual(frames.frameCount, 2)
        XCTAssertEqual(frames.index(at: 0.18), 1)
        let attachment = NativeEmojiAttachment(data: bytes as Data, poster: try XCTUnwrap(frames.image(at: 0)))
        attachment.bounds = CGRect(x: 0, y: -3, width: 24, height: 24)
        XCTAssertEqual(attachment.emojiData, bytes as Data)
        XCTAssertNotNil(attachment.image)
    }
    func testNativeTextInstallsAnimatedInlineViewAndDetachingStopsItsClock() async throws {
        let frames = try XCTUnwrap(NativeEmojiFrames(NativeComposerFixture.animatedGIF))
        let attachment = NativeEmojiAttachment(data: NativeComposerFixture.animatedGIF, poster: try XCTUnwrap(frames.image(at: 0)))
        attachment.bounds = CGRect(x: 0, y: -3, width: 24, height: 24)
        let text = NativeMFMTextView()
        text.frame = CGRect(x: 0, y: 0, width: 250, height: 80)
        text.isEditable = false; text.isScrollEnabled = false; text.font = .systemFont(ofSize: 17)
        text.attributedText = NSAttributedString(attachment: attachment)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let controller = UIViewController(); window.rootViewController = controller
        let previous = scene.windows.first { $0.isKeyWindow }
        controller.view.addSubview(text); window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        window.layoutIfNeeded(); text.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        func find(_ view: UIView) -> NativeEmojiImageView? {
            if let player = view as? NativeEmojiImageView { return player }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let player = try XCTUnwrap(find(text), "The text view must install its inline animated player")
        XCTAssertEqual(player.frames?.frameCount, 2)
        XCTAssertTrue(player.frame.minY >= 0); XCTAssertEqual(player.frame.width, 24)
        if !UIAccessibility.isReduceMotionEnabled && UIApplication.shared.applicationState == .active {
            XCTAssertTrue(player.animationRunning)
            player.render(at: 0)
            let poster = player.image?.pngData()
            let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in player.image?.pngData() != poster }, object: nil)
            await fulfillment(of: [advancing], timeout: 2)
        }
        player.render(at: 0)
        let first = player.image?.pngData()
        player.render(at: 0.18)
        XCTAssertNotNil(player.image); XCTAssertNotEqual(first, player.image?.pngData())
        text.removeFromSuperview()
        XCTAssertFalse(player.animationRunning)
    }
    func testInlineFramesFollowWrappedTextAfterCompositeUnicodeAndAreRemovedWithTheText() throws {
        let bytes = NativeComposerFixture.animatedGIF
        let poster = try XCTUnwrap(NativeEmojiFrames(bytes)?.image(at: 0))
        func emoji() -> NSAttributedString {
            let attachment = NativeEmojiAttachment(data: bytes, poster: poster)
            attachment.bounds = CGRect(x: 0, y: -3, width: 24, height: 24)
            return NSAttributedString(attachment: attachment)
        }
        let body = NSMutableAttributedString(string: "👨‍👩‍👧‍👦 👨‍👩‍👧‍👦 ")
        body.append(emoji()); body.append(NSAttributedString(string: "\nSome synthetic wrapped text ")); body.append(emoji())
        body.addAttribute(.font, value: UIFont.systemFont(ofSize: 17), range: NSRange(location: 0, length: body.length))
        let text = NativeMFMTextView(); text.isScrollEnabled = false
        text.frame = CGRect(x: 0, y: 0, width: 240, height: 300); text.attributedText = body; text.layoutIfNeeded()
        let players = text.subviews.compactMap { $0 as? NativeEmojiImageView }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(players.count, 2)
        let before = try XCTUnwrap(players.last?.frame.minY)
        let firstY = try XCTUnwrap(players.first?.frame.minY)
        XCTAssertTrue(before > firstY)
        text.frame.size.width = 100; text.setNeedsLayout(); text.layoutIfNeeded()
        XCTAssertTrue(try XCTUnwrap(players.last?.frame.minY) > before)
        text.attributedText = nil
        XCTAssertTrue(players.allSatisfy { $0.superview == nil && $0.frames == nil && !$0.animationRunning })
    }
    func testInvalidAndOversizedCompressedDataIsRejected() {
        XCTAssertNil(NativeEmojiFrames(Data("not an image".utf8)))
        XCTAssertNil(NativeEmojiFrames(Data(repeating: 0, count: 4 * 1024 * 1024 + 1)))
    }
    func testFramesAreReusedAcrossPlayersAndLoopsButSeparateSizesAndData() throws {
        NativeEmojiFrameCache.shared.clear()
        let first = try XCTUnwrap(NativeEmojiFrames(NativeComposerFixture.animatedGIF))
        let second = try XCTUnwrap(NativeEmojiFrames(NativeComposerFixture.animatedGIF))
        let poster = try XCTUnwrap(first.image(at: 0)), next = try XCTUnwrap(first.image(at: 1))
        for _ in 0..<10 {
            XCTAssertTrue(second.image(at: 0) === poster); XCTAssertTrue(second.image(at: 1) === next)
        }
        XCTAssertNotEqual(poster.pngData(), next.pngData())
        second.pixels = 32
        let smaller = try XCTUnwrap(second.image(at: 0))
        XCTAssertFalse(smaller === poster); XCTAssertLessThanOrEqual(try XCTUnwrap(smaller.cgImage?.width), 32)
        let other = try XCTUnwrap(NativeEmojiFrames(NativeComposerFixture.animatedWebP))
        XCTAssertFalse(other.image(at: 0) === poster)
    }
    func testConcurrentFrameRequestsDecodeOnceOffTheMainThreadAndClearRejectsLateFrames() async throws {
        let cache = NativeEmojiFrameCache(), image = NativeEmojiDecodedFrame(UIImage(systemName: "face.smiling")!)
        let gate = EmojiDecodeGate(image)
        defer { gate.release() }
        let first = Task { await cache.prepare("owned-frame") { gate.decode() } }
        try await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await cache.prepare("owned-frame") { gate.decode() } }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(gate.count, 1); XCTAssertFalse(gate.ranOnMain)
        gate.release()
        let a = await first.value, b = await second.value
        XCTAssertTrue(a === image.image); XCTAssertTrue(a === b)
        let cached = await cache.prepare("owned-frame") { gate.decode() }
        XCTAssertTrue(cached === a); XCTAssertEqual(gate.count, 1)
        let late = EmojiDecodeGate(image)
        defer { late.release() }
        let pending = Task { await cache.prepare("late-frame") { late.decode() } }
        try await Task.sleep(nanoseconds: 20_000_000)
        cache.clear(); late.release()
        let rejected = await pending.value
        XCTAssertNil(rejected); XCTAssertNil(cache.image("owned-frame")); XCTAssertNil(cache.image("late-frame"))
    }
    func testAsyncAnimationFrameCannotOverwriteAPausedOrReusedPlayer() async throws {
        NativeEmojiFrameCache.shared.clear()
        let player = NativeEmojiImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        player.load(NativeComposerFixture.animatedGIF)
        let frames = try XCTUnwrap(player.frames), poster = player.image
        player.advance(to: 1); player.allowPlayback(false)
        _ = await frames.preparedImage(at: 1)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(player.image === poster); XCTAssertFalse(player.animationRunning)
        NativeEmojiFrameCache.shared.clear()
        player.advance(to: 1); player.load(nil)
        _ = await frames.preparedImage(at: 1)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(player.image); XCTAssertNil(player.frames)
    }
}

private final class EmojiDecodeGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var calls = 0
    private var main = false
    private let result: NativeEmojiDecodedFrame
    init(_ result: NativeEmojiDecodedFrame) { self.result = result }
    var count: Int { condition.lock(); defer { condition.unlock() }; return calls }
    var ranOnMain: Bool { condition.lock(); defer { condition.unlock() }; return main }
    func decode() -> NativeEmojiDecodedFrame {
        condition.lock(); calls += 1; main = Thread.isMainThread
        while !released { condition.wait() }
        condition.unlock(); return result
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
