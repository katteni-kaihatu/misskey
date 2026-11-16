// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UIKit

/// Decoded display resources are bounded and memory-only. Note media and MFM
/// belong to one session generation; public artwork keeps its existing disk cache.
@MainActor
final class NativeVisualMemory {
    static let artwork = NativeVisualMemory()
    private let images = NSCache<NSString, UIImage>()
    private final class Nodes: NSObject { let value: [MFMNode]; init(_ value: [MFMNode]) { self.value = value } }
    private let parsed = NSCache<NSString, Nodes>()
    private struct Pending { let id = UUID(); let task: Task<UIImage?, Never> }
    private var pending: [String: Pending] = [:]
    private var prefetchQueue: [URL] = []
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]
    private var epoch = UUID()
    var generation: UUID { epoch }
    private let loader: (URL, Int, Bool) async -> UIImage?
    init(loader: @escaping (URL, Int, Bool) async -> UIImage? = { url, pixels, artwork in
        await NativeImageLoader.image(url, pixels: pixels, maximumBytes: 8 * 1024 * 1024, cached: artwork)
    }) {
        self.loader = loader
        images.totalCostLimit = 32 * 1024 * 1024; parsed.totalCostLimit = 4 * 1024 * 1024
    }
    static func key(_ url: URL, pixels: Int) -> String { url.absoluteString + "|" + String(pixels) }
    func cached(_ url: URL, pixels: Int) -> UIImage? { images.object(forKey: Self.key(url, pixels: pixels) as NSString) }
    func image(_ url: URL, pixels: Int, artwork: Bool) async -> UIImage? {
        let key = Self.key(url, pixels: pixels)
        if let image = cached(url, pixels: pixels) { return image }
        let token = epoch
        let request: Pending
        if let existing = pending[key] { request = existing }
        else { request = Pending(task: Task { await loader(url, pixels, artwork) }); pending[key] = request }
        let image = await request.task.value
        guard token == epoch else { return nil }
        // A visible waiter may resume before the prefetch owner. Every waiter
        // must publish the decoded image before returning it to the view.
        if pending[key]?.id == request.id { pending[key] = nil }
        if let image { images.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)) }
        return image
    }
    func nodes(_ text: String) -> [MFMNode]? { parsed.object(forKey: text as NSString)?.value }
    func store(_ nodes: [MFMNode], text: String) { parsed.setObject(Nodes(nodes), forKey: text as NSString, cost: text.utf8.count * 6 + 256) }
    static func upcomingPreviews(after id: String, in notes: [ClientNote]) -> [URL] {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return [] }
        var seen = Set<URL>()
        return notes.dropFirst(index + 1).prefix(3).flatMap { note -> [URL] in
            guard note.isHidden != true, note.cw == nil else { return [] }
            return Array((note.files ?? []).filter { !$0.isSensitive && $0.type.hasPrefix("image/") }.prefix(2)).compactMap {
                guard let url = clientImageURL($0.thumbnailUrl ?? $0.url), seen.insert(url).inserted else { return nil }
                return url
            }
        }
    }
    func prefetch(_ urls: [URL]) {
        var seen = Set<URL>()
        // Replace old queued work when the viewport moves. At most two small
        // look-ahead requests compete with images the reader can already see.
        prefetchQueue = Array(urls.filter { seen.insert($0).inserted && prefetchTasks[$0] == nil && cached($0, pixels: 1200) == nil }.prefix(6))
        startPrefetch()
    }
    private func startPrefetch() {
        while prefetchTasks.count < 2, !prefetchQueue.isEmpty {
            let url = prefetchQueue.removeFirst(), token = epoch
            if cached(url, pixels: 1200) != nil { continue }
            prefetchTasks[url] = Task(priority: .utility) { [weak self] in
                guard let self, !Task.isCancelled else { return }
                _ = await self.image(url, pixels: 1200, artwork: false)
                guard self.epoch == token else { return }
                self.prefetchTasks[url] = nil; self.startPrefetch()
            }
        }
    }
    func clear() {
        epoch = UUID(); images.removeAllObjects(); parsed.removeAllObjects()
        prefetchQueue = []; for task in prefetchTasks.values { task.cancel() }; prefetchTasks = [:]
        for request in pending.values { request.task.cancel() }; pending = [:]
    }
}

@MainActor
final class NativeEmojiMemory {
    static let shared = NativeEmojiMemory()
    private let bytes = NSCache<NSURL, NSData>()
    init() { bytes.totalCostLimit = 8 * 1024 * 1024 }
    func data(_ url: URL) -> Data? { bytes.object(forKey: url as NSURL).map { $0 as Data } }
    func store(_ data: Data, url: URL) { bytes.setObject(data as NSData, forKey: url as NSURL, cost: data.count) }
}

private struct NativeVisualMemoryKey: EnvironmentKey { static let defaultValue: NativeVisualMemory? = nil }
private struct NativeVisualGenerationKey: EnvironmentKey { static let defaultValue = UUID() }
extension EnvironmentValues {
    var nativeVisualMemory: NativeVisualMemory? {
        get { self[NativeVisualMemoryKey.self] }
        set { self[NativeVisualMemoryKey.self] = newValue }
    }
    var nativeVisualGeneration: UUID {
        get { self[NativeVisualGenerationKey.self] }
        set { self[NativeVisualGenerationKey.self] = newValue }
    }
}
