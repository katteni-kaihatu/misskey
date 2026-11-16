// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Only explicitly public artwork (avatars, logos and emoji) enters this cache.
/// Note attachments keep their existing transient, unauthenticated transport.
actor NativeAssetCache {
    struct Response: Sendable {
        let status: Int
        let data: Data
        var headers: [String: String] = [:]
    }
    typealias Fetch = @Sendable (URL, [String: String]) async throws -> Response
    private struct Entry: Codable {
        let data: Data
        let validated: Date
        let freshUntil: Date
        let freshnessLifetime: TimeInterval
        let etag: String?
        let modified: String?
        let mustRevalidate: Bool
    }
    private struct DiskItem { let size: Int; var accessed: Date }
    private struct Pending { let id: UUID; let task: Task<Data, Error> }
    static let maximumDownload = 8 * 1024 * 1024
    static let shared: NativeAssetCache = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        // XCTest must neither read nor populate the normal app's cache.
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        let testing = false
        #endif
        let name = testing ? "NativeArtwork-tests-" + UUID().uuidString : "NativeArtwork-v1"
        return NativeAssetCache(directory: base.appendingPathComponent(name, isDirectory: true))
    }()

    private let directory: URL
    private let diskLimit: Int
    private let memoryLimit: Int
    private let now: @Sendable () -> Date
    private let fetch: Fetch
    private var memory: [String: Entry] = [:]
    private var memoryOrder: [String] = []
    private var disk: [String: DiskItem] = [:]
    private var indexed = false
    private var pending: [String: Pending] = [:]
    private static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    init(directory: URL, diskLimit: Int = 64 * 1024 * 1024, memoryLimit: Int = 8 * 1024 * 1024,
         now: @escaping @Sendable () -> Date = { Date() }, fetch: @escaping Fetch = { try await NativeAssetCache.download($0, headers: $1) }) {
        self.directory = directory; self.diskLimit = diskLimit; self.memoryLimit = memoryLimit
        self.now = now; self.fetch = fetch
    }

    func data(for url: URL) async throws -> Data {
        guard clientImageURL(url.absoluteString) != nil else { throw URLError(.badURL) }
        let key = Self.key(url.absoluteString)
        if let entry = read(key), entry.freshUntil > now() { return entry.data }
        if let existing = pending[key] { return try await existing.task.value }
        let id = UUID()
        let task = Task { try await self.refresh(url, key: key) }
        pending[key] = Pending(id: id, task: task)
        // A disappearing row cancels its waiter, not downloads other rows share.
        defer { if pending[key]?.id == id { pending[key] = nil } }
        return try await task.value
    }

    private func refresh(_ url: URL, key: String) async throws -> Data {
        let previous = read(key)
        var headers: [String: String] = [:]
        if let etag = previous?.etag { headers["If-None-Match"] = etag }
        if let modified = previous?.modified { headers["If-Modified-Since"] = modified }
        let result: Response
        do { result = try await fetch(url, headers) }
        catch {
            // Offline fallback is bounded, and never used after an HTTP rejection.
            if let previous, !previous.mustRevalidate, now().timeIntervalSince(previous.validated) < Self.maximumAge { return previous.data }
            throw error
        }
        guard result.status == 200 || (result.status == 304 && previous != nil) else {
            remove(key); throw URLError(.badServerResponse)
        }
        let data = result.status == 304 ? previous!.data : result.data
        guard !data.isEmpty, data.count <= Self.maximumDownload,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            remove(key); throw URLError(.cannotDecodeContentData)
        }
        let fields = Dictionary(result.headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        let controls = (fields["cache-control"] ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let noStore = controls.contains("no-store") || controls.contains("private") || fields["vary"]?.trimmingCharacters(in: .whitespaces) == "*"
        if noStore { remove(key); return data }
        let specifiedAge = controls.first(where: { $0.hasPrefix("max-age=") }).flatMap { TimeInterval($0.dropFirst(8).replacingOccurrences(of: "\"", with: "")) }
        let age = max(0, TimeInterval(fields["age"] ?? "0") ?? 0)
        let inherited = result.status == 304 && fields["cache-control"] == nil
        let lifetime = inherited ? previous!.freshnessLifetime : (controls.contains("no-cache") ? 0 : min(specifiedAge ?? 24 * 60 * 60, Self.maximumAge))
        let ttl = max(0, lifetime - age)
        let entry = Entry(data: data, validated: now(), freshUntil: now().addingTimeInterval(ttl), freshnessLifetime: lifetime,
                          etag: fields["etag"] ?? (result.status == 304 ? previous?.etag : nil),
                          modified: fields["last-modified"] ?? (result.status == 304 ? previous?.modified : nil),
                          mustRevalidate: inherited ? previous!.mustRevalidate : (controls.contains("must-revalidate") || controls.contains("no-cache")))
        store(entry, key: key)
        return data
    }

    private func prepare() {
        guard !indexed else { return }; indexed = true
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
                guard file.pathExtension == "plist", let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
                disk[file.deletingPathExtension().lastPathComponent] = DiskItem(size: values.fileSize ?? 0, accessed: values.contentModificationDate ?? .distantPast)
            }
            trimDisk()
        } catch { /* A non-writable/OS-purged cache must not prevent loading. */ }
    }
    private func read(_ key: String) -> Entry? {
        prepare()
        if let entry = memory[key] {
            if now().timeIntervalSince(entry.validated) >= Self.maximumAge { remove(key); return nil }
            disk[key]?.accessed = now(); remember(entry, key: key); return entry
        }
        guard disk[key] != nil else { return nil }
        let path = file(key)
        guard let bytes = try? Data(contentsOf: path), bytes.count <= Self.maximumDownload + 8192,
              let entry = try? PropertyListDecoder().decode(Entry.self, from: bytes),
              now().timeIntervalSince(entry.validated) < Self.maximumAge else { remove(key); return nil }
        disk[key]?.accessed = now()
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: path.path)
        remember(entry, key: key); return entry
    }
    private func remember(_ entry: Entry, key: String) {
        memory[key] = entry; memoryOrder.removeAll { $0 == key }; memoryOrder.append(key)
        var bytes = memory.values.reduce(0) { $0 + $1.data.count }
        while bytes > memoryLimit, let oldest = memoryOrder.first {
            memoryOrder.removeFirst(); bytes -= memory.removeValue(forKey: oldest)?.data.count ?? 0
        }
    }
    private func store(_ entry: Entry, key: String) {
        prepare(); remember(entry, key: key)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        guard let bytes = try? encoder.encode(entry), bytes.count <= diskLimit else { return }
        do {
            try bytes.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            disk[key] = DiskItem(size: bytes.count, accessed: now()); trimDisk()
        } catch { /* Memory caching still works when disk storage is unavailable. */ }
    }
    private func trimDisk() {
        var bytes = disk.values.reduce(0) { $0 + $1.size }
        guard bytes > diskLimit else { return }
        for (key, item) in disk.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            guard bytes > diskLimit else { break }
            bytes -= item.size; disk[key] = nil; try? FileManager.default.removeItem(at: file(key))
        }
    }
    private func remove(_ key: String) {
        memory[key] = nil; memoryOrder.removeAll { $0 == key }; disk[key] = nil
        try? FileManager.default.removeItem(at: file(key))
    }
    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".plist") }
    static func key(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func download(_ url: URL, headers: [String: String]) async throws -> Response {
        try await NativeImageTransport.shared.data(url, headers: headers)
    }
}

private final class NativeDecodedImage: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

@MainActor
enum NativeImageLoader {
    static func image(_ url: URL, pixels: Int, maximumBytes: Int, cached: Bool) async -> UIImage? {
        do {
            let data: Data
            if cached { data = try await NativeAssetCache.shared.data(for: url) }
            else {
                let response = try await NativeAssetCache.download(url, headers: [:])
                guard (200..<300).contains(response.status) else { return nil }
                data = response.data
            }
            try Task.checkCancellation()
            guard data.count <= maximumBytes else { return nil }
            let result = await Task.detached(priority: .utility) { decode(data, pixels: pixels) }.value
            try Task.checkCancellation()
            return result?.image
        } catch { return nil }
    }
    private nonisolated static func decode(_ data: Data, pixels: Int) -> NativeDecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return nil }
        return NativeDecodedImage(UIImage(cgImage: thumbnail))
    }
}
