// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativeLiveReactionAPI: NativeEmojiAPI {
    func noteEvents() async throws -> NativeTimelineSubscription
    func reactionStates(_ ids: [String]) async throws -> [ClientReactionState]
}

/// One note-update connection for the session, shared by visible timeline,
/// profile, thread and notification rows. Peer proxy IDs never enter this map.
@MainActor
final class NativeLiveReactions {
    private struct Source { let model: NativeReactionModel; var watchers: Set<UUID> }
    private var sources: [String: Source] = [:]
    private var dirty = Set<String>()
    private var epoch = UUID()
    private var connection: Task<Void, Never>?
    private var reads: Task<Void, Never>?
    private var watching: Task<Void, Never>?
    private var subscription: NativeTimelineSubscription?
    private var api: (any NativeLiveReactionAPI)?
    private var accepts: (() -> Bool)?
    private var catalogChanged: (() -> Void)?
    private var expired: (() -> Void)?

    func start(api: any NativeLiveReactionAPI, accepts: @escaping () -> Bool, catalogChanged: @escaping () -> Void, expired: @escaping () -> Void = {}) {
        guard connection == nil, accepts() else { return }
        self.api = api; self.accepts = accepts; self.catalogChanged = catalogChanged; self.expired = expired
        let lease = epoch
        connection = Task { await run(api: api, lease: lease, accepts: accepts) }
    }
    func observe(_ id: String, model: NativeReactionModel) -> UUID {
        let token = UUID()
        if var source = sources[id] { source.watchers.insert(token); sources[id] = source }
        else { sources[id] = Source(model: model, watchers: [token]); dirty.insert(id) }
        updateWatch(); scheduleReads()
        return token
    }
    func remove(_ id: String, token: UUID) {
        guard var source = sources[id] else { return }
        source.watchers.remove(token)
        if source.watchers.isEmpty { sources[id] = nil; dirty.remove(id) } else { sources[id] = source }
        updateWatch()
    }
    func clear() {
        epoch = UUID(); subscription?.cancel(); subscription = nil
        connection?.cancel(); connection = nil; reads?.cancel(); reads = nil; watching?.cancel(); watching = nil
        sources = [:]; dirty = []; api = nil; accepts = nil; catalogChanged = nil; expired = nil
    }
    private func updateWatch() {
        watching?.cancel()
        guard let subscription else { return }
        let lease = epoch
        watching = Task {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
                guard epoch == lease, accepts?() == true else { return }
                try await subscription.watch(Array(sources.keys.sorted().prefix(128)))
            } catch {}
        }
    }
    private func run(api: any NativeLiveReactionAPI, lease: UUID, accepts: @escaping () -> Bool) async {
        var retry: UInt64 = 1
        while epoch == lease && accepts() && !Task.isCancelled {
            do {
                let stream = try await api.noteEvents()
                guard epoch == lease, accepts(), !Task.isCancelled else { stream.cancel(); return }
                subscription = stream
                defer { stream.cancel(); if epoch == lease { subscription = nil } }
                for try await event in stream.events {
                    guard epoch == lease, accepts(), !Task.isCancelled else { return }
                    switch event {
                    case .connected:
                        retry = 1; updateWatch(); dirty.formUnion(sources.keys); scheduleReads()
                    case .noteChanged(let id, let deleted):
                        guard let source = sources[id] else { continue }
                        if deleted { source.model.hideFromLive(); dirty.remove(id) }
                        else { dirty.insert(id); scheduleReads() }
                    case .emojiCatalogChanged:
                        catalogChanged?(); dirty.formUnion(sources.keys); scheduleReads()
                    case .note: break
                    }
                }
            } catch {
                guard epoch == lease, accepts(), !Task.isCancelled else { return }
                if case ClientAPIError.rejected(let status, _) = error, [401, 403].contains(status) {
                    // Normal account restoration owns sign-out. Never keep old
                    // reaction bodies while the stream's identity is rejected.
                    for source in sources.values { source.model.hideFromLive() }
                    if status == 401 { expired?() }
                    return
                }
            }
            do { try await Task.sleep(nanoseconds: retry * 1_000_000_000) } catch { return }
            retry = min(30, retry * 2)
        }
    }
    private func scheduleReads() {
        guard reads == nil, let api, accepts?() == true, !dirty.isEmpty else { return }
        let lease = epoch
        reads = Task {
            defer { if epoch == lease { reads = nil } }
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                while epoch == lease && accepts?() == true && !dirty.isEmpty && !Task.isCancelled {
                    // Keep the wrapper subscribed for deletion events, but
                    // never ask for reaction state belonging to a pure renote.
                    // onAppear can register before the row receives its note.
                    dirty = dirty.filter { sources[$0]?.model.note?.isPureRenote != true }
                    guard !dirty.isEmpty else { break }
                    let ids = Array(dirty.sorted().filter { id in
                        guard let model = sources[id]?.model else { return false }
                        return !model.busy && !model.unknown && model.note?.isHidden != true && model.note != nil
                    }.prefix(100))
                    if ids.isEmpty { try await Task.sleep(nanoseconds: 300_000_000); continue }
                    let expected = Dictionary(uniqueKeysWithValues: ids.compactMap { id in sources[id].map { (id, ($0.model, $0.model.version)) } })
                    dirty.subtract(ids)
                    do {
                        let states = try await api.reactionStates(ids)
                        guard epoch == lease, accepts?() == true, !Task.isCancelled else { return }
                        var retryPartial = false
                        for id in ids {
                            guard let source = sources[id], let (model, version) = expected[id], source.model === model else { continue }
                            if let state = states.first(where: { $0.noteId == id }) {
                                if !model.receiveLive(state, expectedVersion: version) { dirty.insert(id); retryPartial = true }
                            } else if !model.busy && model.version == version { model.hideFromLive() }
                        }
                        if retryPartial { try await Task.sleep(nanoseconds: 500_000_000) }
                    } catch {
                        guard epoch == lease, accepts?() == true, !Task.isCancelled else { return }
                        if case ClientAPIError.rejected(let status, _) = error, status == 401 {
                            for source in sources.values { source.model.hideFromLive() }; expired?(); return
                        }
                        dirty.formUnion(ids.filter { sources[$0] != nil })
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            } catch {}
        }
    }
}
