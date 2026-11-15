// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import UIKit

/// Covers native and WebKit surfaces before UIKit captures the app switcher image.
/// Web-side authorization and private-note disposal remain separate requirements.
@MainActor
final class PrivacyShield {
    private var observers: [NSObjectProtocol] = []
    private var covers: [UIView] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.coverWindows() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.uncoverWindows() }
        })
    }

    private func coverWindows() {
        guard covers.isEmpty else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                let cover = UIView(frame: window.bounds)
                cover.backgroundColor = .systemBackground
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.isAccessibilityElement = true
                cover.accessibilityLabel = "ぐりすぺ"
                window.addSubview(cover)
                covers.append(cover)
            }
        }
    }

    private func uncoverWindows() {
        covers.forEach { $0.removeFromSuperview() }
        covers.removeAll()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
