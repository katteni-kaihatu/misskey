// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

protocol NativeTimelineAPI: Sendable {
    func timeline(_ kind: ClientTimeline, until: String?) async throws -> [ClientNote]
    func channelTimeline(_ id: String, until: String?) async throws -> [ClientNote]
}
extension NativeTimelineAPI {
    func channelTimeline(_ id: String, until: String?) async throws -> [ClientNote] { throw ClientAPIError.invalidResponse }
}

@MainActor
final class NativeTimelineModel: ObservableObject {
    private(set) var initialized = false
    @Published private(set) var notes: [ClientNote] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    private(set) var retryResets = true
    @Published private(set) var hasMore = true
    @Published private(set) var requiresSignIn = false
    @Published private(set) var atTop = true
    @Published private(set) var pendingCount = 0
    @Published private(set) var topRevision = 0
    private var queued: [ClientNote] = []
    private var replacement: [ClientNote]?
    private var liveID = UUID()
    private var raw: [ClientNote] = []
    private var hydration: Task<Void, Never>?
    private var cancelLive: (@Sendable () -> Void)?
    private var requestID = UUID()
    private var context: String?

    func activate(_ context: String) {
        guard self.context != context else { return }
        clear(); self.context = context
    }

    func clear() {
        stopLive(); queued = []; replacement = nil; pendingCount = 0; atTop = true
        requestID = UUID(); context = nil; notes = []; error = nil
        loading = false; loadingMore = false; hasMore = true; requiresSignIn = false; initialized = false
    }

    func load(_ kind: ClientTimeline, reset: Bool, api: any NativeTimelineAPI, accepts: () -> Bool) async {
        await load(feed: .timeline(kind), reset: reset, api: api, accepts: accepts)
    }
    func load(feed: ClientFeedTab, reset: Bool, api: any NativeTimelineAPI, accepts: () -> Bool) async {
        guard accepts(), !Task.isCancelled else { return }
        // A second pull must not replace a refresh already in progress. A pull
        // can supersede pagination; its late response must not append old rows.
        guard !loading || (reset && loadingMore) else { return }
        guard reset || (hasMore && !notes.isEmpty) else { return }
        let request = UUID(), cursor = reset ? nil : notes.last?.id
        retryResets = reset
        requestID = request; loading = true; loadingMore = !reset; error = nil; requiresSignIn = false
        defer { if requestID == request { loading = false; loadingMore = false; if atTop { releasePending() } } }
        do {
            let page: [ClientNote]
            switch feed {
            case .timeline(let kind): page = try await api.timeline(kind, until: cursor)
            case .channel(let id, _): page = try await api.channelTimeline(id, until: cursor)
            case .peerChannel: throw ClientAPIError.invalidResponse // Separate authorized snapshot reader.
            }
            guard requestID == request, accepts(), !Task.isCancelled else { return }
            notes = appendClientNotes(page, to: reset ? [] : notes)
            initialized = true
            // A full page containing only retained IDs cannot advance the
            // cursor. Stop rather than repeatedly downloading the same page.
            hasMore = page.count >= 30 && (reset || notes.last?.id != cursor)
        } catch {
            guard requestID == request, accepts(), !Task.isCancelled else { return }
            // Cancellation is a lifecycle event, not a failed refresh. In both
            // cases the defer releases loading, including the spinner footer.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if case ClientAPIError.rejected(let status, _) = error, status == 401 || status == 403 {
                clear(); requiresSignIn = status == 401
            }
            // Keep visible rows/height on a network failure while pulling.
            self.error = NativeClientSession.explain(error)
        }
    }
    func setAtTop(_ value: Bool) { if atTop != value { atTop = value }; if value && !loading { releasePending() } }
    func releasePending() {
        guard !queued.isEmpty || replacement != nil else { return }
        if let replacement { hasMore = replacement.count >= 30 }
        let combined = appendClientNotes(replacement ?? notes, to: queued)
        if combined.count > 500 { hasMore = true }
        notes = Array(combined.prefix(500))
        queued = []; replacement = nil; pendingCount = 0; topRevision += 1
    }
    func receiveLive(_ incoming: [ClientNote], replacingHead: Bool = false) {
        if replacingHead && !notes.isEmpty && incoming.count >= 30 && !incoming.contains(where: { fresh in notes.contains { $0.id == fresh.id } }) {
            replacement = incoming; queued = []
        }
        let retained = Set(notes.map(\.id))
        let fresh = incoming.filter { !retained.contains($0.id) && $0.isHidden != true }
        queued = appendClientNotes(queued, to: fresh)
        if queued.count > 100 { replacement = Array(queued.prefix(30)); queued = [] }
        pendingCount = max(queued.count, replacement?.count ?? 0)
        if atTop && !loading { releasePending() }
    }
    func receivePosted(_ note: ClientNote, feed: ClientFeedTab, owner: String) {
        guard context != nil, note.user.id == owner, Self.matches(note, feed: feed) else { return }
        // Locally acknowledged posts have not passed the stream's server-side
        // feed filters. Be conservative about channel/direct/reply delivery.
        if case .timeline = feed {
            guard note.channelId == nil, note.channel == nil, note.visibility != "specified", note.replyId == nil else { return }
        }
        receiveLive([note])
    }
    func stopLive() { liveID = UUID(); cancelLive?(); cancelLive = nil; hydration?.cancel(); hydration = nil; raw = [] }
    func listen(feed: ClientFeedTab, api: any NativeTimelineLiveAPI, accepts: @escaping () -> Bool) async {
        // A retired page must not cancel its successor's live subscription.
        guard accepts(), !Task.isCancelled else { return }
        stopLive(); let lease = liveID
        var retry: UInt64 = 1
        var reconcile = !initialized
        while liveID == lease && accepts() && !Task.isCancelled {
            do {
                let subscription = try await api.timelineEvents(feed)
                guard liveID == lease, accepts(), !Task.isCancelled else { subscription.cancel(); return }
                cancelLive = subscription.cancel
                defer { subscription.cancel(); if liveID == lease { cancelLive = nil } }
                for try await event in subscription.events {
                    guard liveID == lease, accepts(), !Task.isCancelled else { return }
                    switch event {
                    case .noteChanged, .emojiCatalogChanged: break // The session's visible-note subscription owns these updates.
                    case .connected:
                        retry = 1
                        // The initial head was already loaded. Returning to a
                        // retained tab resumes future events without another
                        // REST read; a real connection interruption still heals
                        // the missed interval on the next connection.
                        guard reconcile else { continue }
                        let head: [ClientNote]
                        switch feed {
                        case .timeline(let kind): head = try await api.timeline(kind, until: nil)
                        case .channel(let id, _): head = try await api.channelTimeline(id, until: nil)
                        case .peerChannel: return
                        }
                        guard liveID == lease, accepts(), !Task.isCancelled else { return }
                        retry = 1
                        initialized = true
                        receiveLive(head, replacingHead: true)
                    case .note(let note):
                        // The server's LTL includes gridspaceShared peer posts.
                        // Never replace its paired-server filter with host == nil.
                        guard Self.matches(note, feed: feed) else { continue }
                        raw = Array(appendClientNotes([note], to: raw).suffix(100))
                        if hydration == nil {
                            hydration = Task {
                                do {
                                    try await Task.sleep(nanoseconds: 100_000_000)
                                    while !raw.isEmpty && liveID == lease && accepts() && !Task.isCancelled {
                                        let batch = raw; raw = []
                                        let ready = try await api.prepareLiveNotes(batch)
                                        guard liveID == lease, accepts(), !Task.isCancelled else { return }
                                        receiveLive(ready.reversed())
                                    }
                                } catch { /* Reconnection/next head read reconciles an incomplete batch. */ }
                                if liveID == lease { hydration = nil }
                            }
                        }
                    }
                }
            } catch {
                guard liveID == lease, accepts(), !Task.isCancelled else { return }
                if error as? ClientAPIError == .notAuthenticated { clear(); requiresSignIn = true; return }
                if case ClientAPIError.rejected(let status, _) = error, status == 401 || status == 403 {
                    clear(); requiresSignIn = status == 401; self.error = NativeClientSession.explain(error); return
                }
            }
            reconcile = true
            do { try await Task.sleep(nanoseconds: retry * 1_000_000_000) } catch { return }
            retry = min(30, retry * 2)
        }
    }
    static func matches(_ note: ClientNote, feed: ClientFeedTab) -> Bool {
        guard note.isHidden != true else { return false }
        switch feed {
        case .timeline(.home): return true // Follow, linked identity and visibility are server-filtered.
        case .timeline(.local): return note.visibility == "public" && note.channelId == nil && note.channel == nil && (note.user.host == nil || note.gridspaceShared == true)
        case .timeline(.global): return note.visibility == "public" && note.channelId == nil && note.channel == nil
        case .channel(let id, _): return note.channelId == id || note.channel?.id == id
        case .peerChannel: return false
        }
    }
}


/// Page containers may discard distant tabs. Keep each feed's model with the
/// session, bounded by the configured tab set, and clear it on session changes.
@MainActor
final class NativeTimelineStore {
    private var models: [String: NativeTimelineModel] = [:]
    func model(_ id: String) -> NativeTimelineModel {
        if let model = models[id] { return model }
        let model = NativeTimelineModel(); models[id] = model; return model
    }
    func retain(_ ids: Set<String>) {
        for id in Array(models.keys) where !ids.contains(id) { models.removeValue(forKey: id)?.clear() }
    }
    func clear() { for model in models.values { model.clear() } }
}
