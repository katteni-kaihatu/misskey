// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import UIKit

/// A List can create its last cell well before it is visible. Measure the
/// footer against its actual scroll viewport instead of fetching onAppear.
struct NativeAutoLoadMore: View {
    let cursor: String
    let active: Bool
    let loading: Bool
    let failed: Bool
    var failure: String? = nil
    let load: () async -> Void
    @State private var nearBottom = false
    @State private var completion = 0
    private struct Trigger: Hashable {
        let cursor: String
        let active: Bool
        let near: Bool
        let failed: Bool
        let completion: Int
    }
    var body: some View {
        ZStack {
            if let failure {
                VStack(spacing: 6) {
                    Text(failure).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Button("再試行") { Task { await load() } }.disabled(loading)
                }
            } else if loading { ProgressView().accessibilityLabel("続きを読み込み中") }
            NativePaginationVisibility { nearBottom = $0 }.accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        // Keep the retry in the same fixed-size row. Removing a separate
        // error row makes List adjust its bottom anchor during an append.
        .frame(maxWidth: .infinity).frame(height: 88)
        .listRowSeparator(.hidden)
        .task(id: Trigger(cursor: cursor, active: active, near: nearBottom, failed: failed, completion: completion)) {
            // Allow the appended page to lay out before deciding whether the
            // footer is still near the screen. Loading is deliberately absent
            // from the task ID: starting a request must not cancel that request.
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard active, nearBottom, !loading, !failed, !Task.isCancelled else { return }
            await load()
        }
        .onChange(of: loading) { value in if !value { completion += 1 } }
    }
}

private struct NativePaginationVisibility: UIViewRepresentable {
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.changed = changed; return view }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.attach() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }
    final class Probe: UIView {
        var changed: ((Bool) -> Void)?
        private weak var scroll: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var last: Bool?
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { attach() } else { detach() } }
        override func layoutSubviews() { super.layoutSubviews(); schedule() }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var parent = self.superview
                while let view = parent, !(view is UIScrollView) { parent = view.superview }
                guard let value = parent as? UIScrollView else { return }
                if self.scroll !== value {
                    self.detach(); self.scroll = value
                    self.observations = [
                        value.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
                        value.observe(\.contentSize, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
                        value.observe(\.bounds, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
                    ]
                }
                self.measure()
            }
        }
        private func schedule() { DispatchQueue.main.async { [weak self] in self?.measure() } }
        private func measure() {
            guard window != nil, let scroll, bounds.height > 0 else { emit(false); return }
            let rect = convert(bounds, to: scroll)
            let viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
            emit(rect.maxY >= viewport.minY && rect.minY <= viewport.maxY + 250)
        }
        private func emit(_ value: Bool) { if last != value { last = value; changed?(value) } }
        func detach() {
            observations = []; scroll = nil
            if last == true { DispatchQueue.main.async { [weak self] in self?.measure() } }
        }
    }
}
