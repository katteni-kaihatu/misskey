// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import ImageIO
import UIKit

final class NativeEmojiDecodedFrame: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

/// ImageIO state is serialized even when an old resize and a new animation
/// frame overlap. Animated frames are decoded on a worker, never by the tick.
final class NativeEmojiFrameDecoder: @unchecked Sendable {
    private let source: CGImageSource
    private let lock = NSLock()
    init(_ source: CGImageSource) { self.source = source }
    func decode(index: Int, pixels: Int) -> NativeEmojiDecodedFrame? {
        lock.lock(); defer { lock.unlock() }
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index,
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
             kCGImageSourceThumbnailMaxPixelSize: min(192, max(1, pixels)), kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return NativeEmojiDecodedFrame(UIImage(cgImage: frame))
    }
}

/// Public emoji frames share a bounded, memory-only cache across players and
/// loops. Raw image data, target size and frame index all participate in the key.
@MainActor
final class NativeEmojiFrameCache {
    static let shared = NativeEmojiFrameCache()
    private let images = NSCache<NSString, UIImage>()
    private struct Pending { let id = UUID(); let task: Task<NativeEmojiDecodedFrame?, Never> }
    private var pending: [String: Pending] = [:]
    private var epoch = UUID()
    init() { images.totalCostLimit = 16 * 1024 * 1024; images.countLimit = 512 }
    func image(_ key: String) -> UIImage? { images.object(forKey: key as NSString) }
    func store(_ image: UIImage, key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(image.size.width * image.size.height * 4)
        images.setObject(image, forKey: key as NSString, cost: cost)
    }
    func prepare(_ key: String, decode: @escaping @Sendable () -> NativeEmojiDecodedFrame?) async -> UIImage? {
        if let image = image(key) { return image }
        let token = epoch
        let request: Pending
        if let existing = pending[key] { request = existing }
        else { request = Pending(task: Task.detached(priority: .userInitiated, operation: decode)); pending[key] = request }
        let value = await request.task.value
        guard token == epoch else { return nil }
        if pending[key]?.id == request.id { pending[key] = nil }
        if let image = value?.image { store(image, key: key) }
        return value?.image
    }
    func clear() {
        epoch = UUID(); images.removeAllObjects()
        for request in pending.values { request.task.cancel() }; pending = [:]
    }
}
