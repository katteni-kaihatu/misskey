// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public enum NavigationDecision: Equatable, Sendable {
    case allow
    /// Open a deliberate link outside the authenticated WebView.
    case openExternal
    /// An automatic redirect must not launch another application without confirmation.
    case confirmExternal
    case cancel
}

/// Keeps the authenticated main frame on its selected origin while allowing
/// existing widgets and other UGC to embed external web content.
public struct NavigationPolicy: Sendable {
    public let origin: ServerOrigin

    public init(origin: ServerOrigin) {
        self.origin = origin
    }

    public func decision(
        for url: URL,
        isMainFrame: Bool,
        isUserActivated: Bool
    ) -> NavigationDecision {
        if origin.contains(url) { return .allow }

        if ServerOrigin.webComponents(for: url) != nil {
            if !isMainFrame { return .allow }
            return isUserActivated ? .openExternal : .confirmExternal
        }

        let scheme = url.scheme?.lowercased()
        // A blank window is also used by window.open() before it receives a URL.
        if url.absoluteString == "about:blank" { return .allow }
        if !isMainFrame && url.absoluteString == "about:srcdoc" { return .allow }

        if !isMainFrame && scheme == "blob" {
            if ServerOrigin.blobSourceURL(url) != nil { return .allow }
        }

        if isMainFrame && isUserActivated && ["mailto", "tel"].contains(scheme ?? "") {
            return .openExternal
        }
        // In particular: javascript:, data:, file:, custom application schemes,
        // blob:null, and automatic attempts to open mail or dial a number.
        return .cancel
    }
}
