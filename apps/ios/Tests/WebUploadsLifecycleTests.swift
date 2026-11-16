// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import GridSpace

@MainActor
final class WebUploadsLifecycleTests: XCTestCase {
    func testLatePopoverDismissalDoesNotDiscardSelectedFiles() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first { $0.isKeyWindow }
        let presenter = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        let uploads = WebUploads()
        uploads.presenter = presenter
        defer {
            uploads.invalidate()
            window.isHidden = true
            prior?.makeKeyAndVisible()
        }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("synthetic selection".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let completed = expectation(description: "Selected files delivered")
        var selection: [URL]?
        uploads.begin(allowsMultiple: true, allowsDirectories: false, sourceHost: "example.com") { urls in
            selection = urls
            completed.fulfill()
        }
        let menu = try XCTUnwrap(presenter.presentedViewController)
        let oldPopover = try XCTUnwrap(menu.popoverPresentationController)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        uploads.documentPicker(picker, didPickDocumentsAt: [source])
        // iOS can report the old chooser's dismissal after selection has begun.
        uploads.popoverPresentationControllerDidDismissPopover(oldPopover)
        await fulfillment(of: [completed], timeout: 5)
        let selected = try XCTUnwrap(selection?.first)
        XCTAssertEqual(try Data(contentsOf: selected), Data("synthetic selection".utf8))
    }
}
