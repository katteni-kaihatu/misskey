// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UIKit

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var origin: ServerOrigin?
    @Published var address = ""
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let privacyShield = PrivacyShield()
    private static let originKey = "gridspace.serverOrigin"

    static let productionOrigin = try! ServerOrigin("https://misskey.grid-space.io")

    static var isTesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    init() {
        WebDownloads.removeOrphanedExports()
        UploadStagingArea.removeOrphanedFiles()
        // UI tests must not inherit a real account's persistent server selection.
        let isTesting = Self.isTesting
        NativeMultipart.removeOrphanedFiles()
        let attachmentIDs = NativeDraftStore.current().attachmentIDs()
        if let attachmentIDs { Task { await NativeAttachmentFiles(testing: isTesting).removeOrphans(keeping: attachmentIDs) } }
        // Gesture QA must exercise real sheet and refresh-control settling.
        let gestureQA = ProcessInfo.processInfo.arguments.contains("--native-peer-channels-fixture")
            || ProcessInfo.processInfo.arguments.contains("--native-refresh-fixture")
            || ProcessInfo.processInfo.arguments.contains("--native-reaction-sheet-fixture")
        if isTesting && !gestureQA { UIView.setAnimationsEnabled(false) }
        defaults = isTesting ? UserDefaults(suiteName: "GridSpaceUITests")! : .standard
        if isTesting {
            defaults.removeObject(forKey: Self.originKey)
            #if DEBUG
            if NativeComposerFixture.enabled {
                origin = NativeComposerFixture.origin
                address = NativeComposerFixture.origin.url.absoluteString
            } else if NativeTimelineFixture.enabled {
                origin = NativeTimelineFixture.origin
                address = NativeTimelineFixture.origin.url.absoluteString
            } else if let server = LocalParityServer.current {
                NSLog("Local parity Wi-Fi address: %@", server.wifiAddress() ?? "unavailable")
                origin = server.origin
                address = server.origin.url.absoluteString
            } else if ProcessInfo.processInfo.arguments.contains("--compatibility-fixture"),
               ProcessInfo.processInfo.arguments.contains("--fixture-direct") {
                origin = try? ServerOrigin("https://example.com")
                address = "https://example.com"
            }
            #endif
        } else {
            origin = Self.productionOrigin
            address = Self.productionOrigin.url.absoluteString
        }
    }

    func connect() {
        guard Self.isTesting else { origin = Self.productionOrigin; address = Self.productionOrigin.url.absoluteString; return }
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
        guard Self.isTesting else { return }
        origin = nil
        errorMessage = nil
        defaults.removeObject(forKey: Self.originKey)
    }
}
