// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import WebKit
import XCTest
@testable import GridSpace

@MainActor
final class WebUploadIntegrationTests: XCTestCase {
    func testSelectedFileReachesTheExistingWebFileInputWithoutChangingBytes() async throws {
        guard #available(iOS 18.4, *) else { throw XCTSkip("Native open panel requires iOS 18.4") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first { $0.isKeyWindow }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Popup mode skips an automatic network request. This fixture is local.
        let controller = WebSessionController(origin: try ServerOrigin("example.com"), configuration: configuration, isPopup: true)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            controller.shutdown()
            window.isHidden = true
            prior?.makeKeyAndVisible()
        }
        let loaded = expectation(description: "Synthetic upload document loaded")
        let navigation = UploadNavigation { loaded.fulfill() }
        controller.webView.navigationDelegate = navigation
        controller.webView.loadHTMLString("<!doctype html><input id='file' type='file' multiple>", baseURL: URL(string: "https://example.com"))
        await fulfillment(of: [loaded], timeout: 10)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("synthetic upload bytes".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let selection = Task { @MainActor in
            let value = try await controller.webView.callAsyncJavaScript("""
                return await new Promise(resolve => {
                    const input = document.getElementById('file');
                    input.onchange = async () => resolve(await input.files[0].text());
                    input.click();
                });
                """, arguments: [:], in: nil, contentWorld: .page)
            return value as? String
        }
        let presented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.presentedViewController != nil }
        }, object: nil)
        await fulfillment(of: [presented], timeout: 5)
        // Supply the same delegate result as Files, using synthetic bytes only.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        controller.uploads.documentPicker(picker, didPickDocumentsAt: [source])
        let content = try await selection.value
        XCTAssertEqual(content, "synthetic upload bytes")
        let count = try await controller.webView.evaluateJavaScript("document.getElementById('file').files.length")
        XCTAssertEqual(count as? Int, 1)
        withExtendedLifetime(navigation) { }
    }
}

@MainActor
private final class UploadNavigation: NSObject, WKNavigationDelegate {
    let onLoad: () -> Void
    init(onLoad: @escaping () -> Void) { self.onLoad = onLoad }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoad() }
}
