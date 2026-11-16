// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import UIKit

/// Observe the actual List scroll view, including its refresh inset and finger
/// tracking. A partially visible first row is not sufficient to mean 'at top'.
struct NativeTimelinePosition: UIViewRepresentable {
    var generation: UUID? = nil
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.changed = changed; return view }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.bind(generation); view.attach() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }
    final class Probe: UIView {
        var changed: ((Bool) -> Void)?
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var pending: DispatchWorkItem?
        private var last: Bool?
        private var generation: UUID?
        func bind(_ value: UUID?) { if generation != value { generation = value; last = nil } }
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { attach() } else { detach() } }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var parent = self.superview
                while let view = parent, !(view is UIScrollView) { parent = view.superview }
                guard let value = parent as? UIScrollView else { return }
                if self.scroll !== value {
                    self.detach(); self.scroll = value
                    value.panGestureRecognizer.addTarget(self, action: #selector(self.pan))
                    self.observation = value.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.schedule() }
                    }
                }
                self.schedule()
            }
        }
        @objc private func pan() { schedule() }
        private func schedule() {
            pending?.cancel()
            if let scroll, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 2 || scroll.isDragging || scroll.isDecelerating {
                emit(false)
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, let scroll = self.scroll else { return }
                self.emit(scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 2 && !scroll.isDragging && !scroll.isDecelerating && scroll.refreshControl?.isRefreshing != true)
            }
            pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
        private func emit(_ value: Bool) { if last != value { last = value; changed?(value) } }
        func detach() {
            pending?.cancel(); pending = nil; observation = nil
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(pan)); scroll = nil
            // Detaching a recycled row must stop automatic insertion.
            if last == true { DispatchQueue.main.async { [weak self] in self?.emit(false) } }
        }
    }
}
