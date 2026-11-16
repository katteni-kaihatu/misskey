// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import ImageIO
import CryptoKit
import SwiftUI
import UIKit

/// Keep compressed frames and decode only the current, downsampled frame.
/// A large animation falls back to its first frame instead of allocating an
/// unbounded UIImage.animatedImage array for every visible emoji.
@MainActor
final class NativeEmojiFrames {
    private let decoder: NativeEmojiFrameDecoder
    private let fingerprint: String
    let frameCount: Int
    let delays: [TimeInterval]
    let duration: TimeInterval
    let loops: Int
    var pixels = 96
    init?(_ data: Data) {
        guard data.count <= 4 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        decoder = NativeEmojiFrameDecoder(source)
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let count = CGImageSourceGetCount(source)
        frameCount = count <= 300 && width <= 2048 && height <= 2048 ? count : 1
        var times: [TimeInterval] = []
        for index in 0..<frameCount {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] ?? [:]
            var delay: Double?
            for (dictionary, unclamped, clamped) in Self.timingKeys {
                let values = props[dictionary as String] as? [String: Any] ?? [:]
                if let value = (values[unclamped as String] ?? values[clamped as String]) as? NSNumber { delay = value.doubleValue; break }
            }
            let value = delay.flatMap { $0.isFinite && $0 >= 0.02 ? $0 : nil } ?? 0.1
            times.append(min(10, value))
        }
        delays = times; duration = times.reduce(0, +)
        let overall = CGImageSourceCopyProperties(source, nil) as? [String: Any] ?? [:]
        var loopCount = 0
        for (dictionary, key) in [(kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
                                  (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
                                  (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount)] {
            if let values = overall[dictionary as String] as? [String: Any], let count = values[key as String] as? Int { loopCount = max(0, count); break }
        }
        loops = loopCount
    }
    private static let timingKeys = [
        (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
        (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
    ]
    func index(at time: TimeInterval) -> Int {
        guard frameCount > 1 else { return 0 }
        if loops > 0 && time >= duration * Double(loops) { return frameCount - 1 }
        var position = max(0, time).truncatingRemainder(dividingBy: duration)
        for (index, delay) in delays.enumerated() { if position < delay { return index }; position -= delay }
        return frameCount - 1
    }
    func image(at index: Int) -> UIImage? {
        let key = key(index)
        if let image = NativeEmojiFrameCache.shared.image(key) { return image }
        guard let image = decoder.decode(index: index, pixels: pixels)?.image else { return nil }
        NativeEmojiFrameCache.shared.store(image, key: key); return image
    }
    private func key(_ index: Int) -> String { fingerprint + ":" + String(pixels) + ":" + String(index) }
    func cachedImage(at index: Int) -> UIImage? { NativeEmojiFrameCache.shared.image(key(index)) }
    func preparedImage(at index: Int) async -> UIImage? {
        let decoder = decoder, pixels = pixels
        return await NativeEmojiFrameCache.shared.prepare(key(index)) { decoder.decode(index: index, pixels: pixels) }
    }
}

private final class NativeEmojiClock: @unchecked Sendable {
    private var link: CADisplayLink?
    @MainActor var running: Bool { link != nil }
    @MainActor func start(_ view: NativeEmojiImageView) {
        guard link == nil else { return }
        let link = CADisplayLink(target: NativeEmojiTick(view), selector: #selector(NativeEmojiTick.tick(_:)))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common); self.link = link
    }
    @MainActor func stop() { link?.invalidate(); link = nil }
    deinit { link?.invalidate() }
}
@MainActor
private final class NativeEmojiTick: NSObject {
    weak var view: NativeEmojiImageView?
    init(_ view: NativeEmojiImageView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { if let view { view.tick(link.timestamp) } else { link.invalidate() } }
}

final class NativeEmojiImageView: UIImageView {
    private var data: Data?
    private(set) var frames: NativeEmojiFrames?
    private let clock = NativeEmojiClock()
    private var origin: TimeInterval?
    private var current = -1
    private var playbackAllowed = true
    private var suspended = false
    private var frameTask: Task<Void, Never>?
    private var frameRevision = UUID()
    private var desired = -1
    var animationRunning: Bool { clock.running }
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit; clipsToBounds = true; isUserInteractionEnabled = false
        isAccessibilityElement = false; accessibilityElementsHidden = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(motionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    deinit { frameTask?.cancel(); NotificationCenter.default.removeObserver(self) }
    func load(_ value: Data?) {
        guard value != data else { return }
        clock.stop(); cancelFrame(); origin = nil; current = -1; data = value
        frames = value.flatMap { NativeEmojiFrames($0) }; image = nil
        render(at: 0); refreshPlayback()
    }
    func allowPlayback(_ value: Bool) { playbackAllowed = value; refreshPlayback() }
    override func didMoveToWindow() { super.didMoveToWindow(); refreshPlayback() }
    override func layoutSubviews() {
        super.layoutSubviews()
        let pixels = min(192, max(32, Int(ceil(max(bounds.width, bounds.height) * (window?.screen.scale ?? 3)))))
        if frames?.pixels != pixels { cancelFrame(); frames?.pixels = pixels; current = -1; render(at: 0) }
    }
    @objc private func pause() { suspended = true; refreshPlayback() }
    @objc private func resume() { suspended = false; refreshPlayback() }
    @objc private func motionChanged() { refreshPlayback() }
    private func refreshPlayback() {
        if playbackAllowed, !suspended, !UIAccessibility.isReduceMotionEnabled, window != nil,
           UIApplication.shared.applicationState == .active, (frames?.frameCount ?? 0) > 1 {
            if !clock.running { origin = nil; clock.start(self) }
        } else { clock.stop(); cancelFrame(); origin = nil; render(at: 0) }
    }
    func tick(_ timestamp: TimeInterval) {
        guard let window, !isHidden, alpha > 0, convert(bounds, to: window).intersects(window.bounds) else { return }
        if origin == nil { origin = timestamp }
        if let frames { advance(to: frames.index(at: timestamp - (origin ?? timestamp))) }
    }
    private func cancelFrame() { frameRevision = UUID(); frameTask?.cancel(); frameTask = nil; desired = -1 }
    func advance(to index: Int) {
        desired = index
        guard let frames, index != current else { return }
        if let image = frames.cachedImage(at: index) { self.image = image; current = index; return }
        guard frameTask == nil else { return }
        let revision = frameRevision, pixels = frames.pixels
        frameTask = Task { @MainActor [weak self] in
            let image = await frames.preparedImage(at: index)
            guard let self, !Task.isCancelled, self.frameRevision == revision, self.frames === frames, frames.pixels == pixels else { return }
            self.frameTask = nil
            // Slow decoding skips obsolete frames instead of queueing them or
            // showing an old frame over a newer cached one.
            if self.desired == index, let image { self.image = image; self.current = index }
        }
    }
    func render(at elapsed: TimeInterval) {
        guard let frames else { return }
        let index = frames.index(at: elapsed)
        guard index != current else { return }
        if let image = frames.image(at: index) { self.image = image; current = index }
    }
}

struct NativeAnimatedEmoji: UIViewRepresentable {
    let data: Data
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeUIView(context: Context) -> NativeEmojiImageView { NativeEmojiImageView(frame: .zero) }
    func updateUIView(_ view: NativeEmojiImageView, context: Context) { view.load(data); view.allowPlayback(phase == .active && !reduceMotion) }
    static func dismantleUIView(_ view: NativeEmojiImageView, coordinator: ()) { view.load(nil) }
}

/// The poster participates in text layout and selection. NativeMFMTextView
/// places the shared animated player at the laid-out attachment baseline.
final class NativeEmojiAttachment: NSTextAttachment {
    let emojiData: Data
    init(data: Data, poster: UIImage) {
        emojiData = data; super.init(data: nil, ofType: nil)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { _ in
            let factor = 96 / max(1, max(poster.size.width, poster.size.height))
            let size = CGSize(width: poster.size.width * factor, height: poster.size.height * factor)
            poster.draw(in: CGRect(x: (96 - size.width) / 2, y: (96 - size.height) / 2, width: size.width, height: size.height))
        }
    }
    required init?(coder: NSCoder) {
        guard let data = coder.decodeObject(of: NSData.self, forKey: "emojiData") as Data? else { return nil }
        emojiData = data; super.init(coder: coder)
    }
    override func encode(with coder: NSCoder) { super.encode(with: coder); coder.encode(emojiData as NSData, forKey: "emojiData") }
}
