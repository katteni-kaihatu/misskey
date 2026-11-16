// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GridSpaceCore
import SwiftUI

/// Only the unauthenticated, public emoji catalog. Account/role membership,
/// note state, recent choices and credentials never enter these files.
actor NativeEmojiCatalogCache {
    private struct Entry: Codable { let updated: Date; let emojis: [ClientCustomEmoji] }
    private struct Pending { let id: UUID; let task: Task<[ClientCustomEmoji], Error> }
    static let shared: NativeEmojiCatalogCache = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let suffix = ProcessInfo.processInfo.environment["GRIDSPACE_COMPOSER_TEST_STORE"] ?? UUID().uuidString
        let name = testing ? "NativeEmojiCatalog-tests-" + suffix : "NativeEmojiCatalog-v1"
        return NativeEmojiCatalogCache(directory: base.appendingPathComponent(name, isDirectory: true))
    }()
    private let directory: URL
    private let now: @Sendable () -> Date
    private var memory: [String: Entry] = [:]
    private var pending: [String: Pending] = [:]
    private let maximumBytes = 8 * 1024 * 1024
    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) { self.directory = directory; self.now = now }
    private func key(_ origin: ServerOrigin) -> String { NativeAssetCache.key(origin.url.absoluteString) }
    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".json") }
    private func read(_ key: String) -> Entry? {
        if let entry = memory[key] { return valid(entry) ? entry : nil }
        let url = file(key)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumBytes,
              let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: data), valid(entry) else { return nil }
        remember(entry, key: key); return entry
    }
    private func valid(_ entry: Entry) -> Bool {
        let age = now().timeIntervalSince(entry.updated)
        return age >= -300 && age < 7 * 24 * 60 * 60 && entry.emojis.allSatisfy(\.validName)
    }
    private func remember(_ entry: Entry, key: String) {
        if memory[key] == nil && memory.count >= 4 { memory.removeValue(forKey: memory.keys.sorted().first!) }
        memory[key] = entry
    }
    func snapshot(origin: ServerOrigin) -> [ClientCustomEmoji]? { read(key(origin))?.emojis }
    func catalog(origin: ServerOrigin, api: any NativeEmojiAPI, force: Bool = false) async throws -> [ClientCustomEmoji] {
        let key = key(origin)
        // The public API declares cacheSec: 3600. The UI may show its previous
        // catalog while an expired entry is refreshed; writes still preflight.
        if !force, let entry = read(key), now().timeIntervalSince(entry.updated) < 3600 { return entry.emojis }
        if let task = pending[key]?.task { return try await task.value }
        let id = UUID()
        let task = Task {
            do {
                let items = try await api.emojis()
                var names = Set<String>()
                let emojis = items.filter { $0.validName && names.insert($0.name).inserted }
                let entry = Entry(updated: self.now(), emojis: emojis)
                let data = try JSONEncoder().encode(entry)
                guard data.count <= self.maximumBytes else { throw ClientAPIError.responseTooLarge }
                self.remember(entry, key: key); self.write(data, key: key)
                return emojis
            } catch {
                if let cached = self.read(key) { return cached.emojis }
                throw error
            }
        }
        pending[key] = Pending(id: id, task: task)
        defer { if pending[key]?.id == id { pending[key] = nil } }
        return try await task.value
    }
    private func write(_ data: Data, key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var directory = directory; try directory.setResourceValues(values)
            try data.write(to: file(key), options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" }.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
            for file in files.prefix(max(0, files.count - 8)) { try? FileManager.default.removeItem(at: file) }
        } catch { /* Cache eviction or a full disk must not block the picker. */ }
    }
}

@MainActor
final class NativeEmojiCatalog: ObservableObject {
    @Published private(set) var items: [ClientCustomEmoji] = []
    @Published private(set) var ready = false
    @Published private(set) var error: String?
    private var request: Task<Void, Never>?
    private var pendingForce = false
    func load(origin: ServerOrigin, api: any NativeEmojiAPI, cache: NativeEmojiCatalogCache = .shared, force: Bool = false) async {
        if let request { pendingForce = pendingForce || force; await request.value; return }
        let task = Task {
            if let cached = await cache.snapshot(origin: origin) { items = cached; ready = true }
            do { items = try await cache.catalog(origin: origin, api: api, force: force); ready = true; error = nil }
            catch { if items.isEmpty { self.error = NativeClientSession.explain(error) } }
        }
        request = task; await task.value; request = nil
        if pendingForce { pendingForce = false; await load(origin: origin, api: api, cache: cache, force: true) }
    }
}

/// Recents keep one interleaved order for custom and standard emoji. Searching
/// from the default Recent tab searches the complete catalog.
enum NativeEmojiRecents {
    static func choices(_ values: [String], custom: [ClientCustomEmoji], query: String, showSensitive: Bool) -> [NativeEmojiChoice] {
        let custom = custom.filter { showSensitive || $0.isSensitive != true }
        if !ClientEmojiSearch.normalize(query).isEmpty {
            return custom.filter { $0.matches(query) }.map { .init(value: $0.shortcode, custom: $0) }
                + ClientUnicodeEmoji.all.filter { $0.matches(query) }.map { .init(value: $0.char, custom: nil) }
        }
        var result: [NativeEmojiChoice] = []
        for value in values.prefix(32) {
            let choice: NativeEmojiChoice?
            if let emoji = custom.first(where: { ClientEmojiSearch.equivalent($0.shortcode, value) }) { choice = .init(value: emoji.shortcode, custom: emoji) }
            else if let emoji = ClientUnicodeEmoji.all.first(where: { ClientEmojiSearch.equivalent($0.char, value) }) { choice = .init(value: emoji.char, custom: nil) }
            else { choice = nil }
            if let choice, !result.contains(where: { ClientEmojiSearch.equivalent($0.value, choice.value) }) { result.append(choice) }
        }
        return result
    }
}
