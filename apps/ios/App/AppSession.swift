// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var origin: ServerOrigin?
    @Published var address = ""
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let privacyShield = PrivacyShield()
    private static let originKey = "gridspace.serverOrigin"

    init() {
        WebDownloads.removeOrphanedExports()
        // UI tests must not inherit a real account's persistent server selection.
        let isTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        defaults = isTesting ? UserDefaults(suiteName: "GridSpaceUITests")! : .standard
        if isTesting {
            defaults.removeObject(forKey: Self.originKey)
        } else if let saved = defaults.string(forKey: Self.originKey) {
            origin = try? ServerOrigin(saved)
            address = saved
        }
    }

    func connect() {
        do {
            let validated = try ServerOrigin(address)
            // Only the server origin is persisted. Authentication belongs to WebKit.
            defaults.set(validated.url.absoluteString, forKey: Self.originKey)
            errorMessage = nil
            origin = validated
        } catch {
            errorMessage = "HTTPSのサーバーアドレスを入力してください。ユーザー情報、ページのパス、クエリーは指定できません。"
        }
    }

    func chooseAnotherServer() {
        origin = nil
        errorMessage = nil
        defaults.removeObject(forKey: Self.originKey)
    }
}
