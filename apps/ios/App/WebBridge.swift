// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import WebKit

@MainActor
final class WebBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "gridspaceBridge"
    weak var webView: WKWebView?
    private let origin: ServerOrigin
    private var epoch = UUID()
    var onSessionChanged: ((BridgeHandshake.SessionChangeReason) -> Void)?
    private var active = true

    init(origin: ServerOrigin) { self.origin = origin }

    func rotate() { epoch = UUID() }
    func invalidate() { active = false; rotate() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        // A popup may inherit its opener's content controller, but never inherits
        // the opener's bridge session. Cross-origin and subframe calls fail shut.
        let frameHost = message.frameInfo.securityOrigin.host.lowercased()
        let sameHost = frameHost == origin.host || (origin.host.contains(":") && frameHost == "[\(origin.host)]")
        guard active, let webView, message.webView === webView, message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, origin.contains(url),
              message.frameInfo.securityOrigin.protocol == "https",
              sameHost,
              (message.frameInfo.securityOrigin.port == 0 ? 443 : message.frameInfo.securityOrigin.port) == origin.port,
              JSONSerialization.isValidJSONObject(message.body) else {
            replyHandler(nil, "Bridge request refused")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let request = try BridgeHandshake.decode(data)
            let nativeFileInput: Bool
            if #available(iOS 18.4, *) { nativeFileInput = true } else { nativeFileInput = false }
            let reply = BridgeHandshake.reply(to: request, epoch: epoch, nativeFileInput: nativeFileInput,
                                              expectedHost: origin.authority, replacementEpoch: UUID())
            if request.operation == "session.changed", reply.status == .success {
                // Public invalidation only. No account token or authentication
                // authority is derived from the page-supplied user ID.
                epoch = reply.accountEpoch
                if let reason = request.payload.reason { onSessionChanged?(reason) }
            }
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))
            replyHandler(object, nil)
        } catch {
            // Never reflect attacker-controlled payloads or authentication data.
            replyHandler(nil, "Invalid bridge message")
        }
    }
}
