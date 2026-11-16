// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import UIKit
import WebKit

/// Retains downloads until completion, then lets the user save/share the file.
/// Files live only in a per-download temporary directory, including secret exports.
@MainActor
final class WebDownloads: NSObject, WKDownloadDelegate {
    weak var presenter: UIViewController?
    private struct Transfer {
        let download: WKDownload
        var directory: URL?
        var destination: URL?
    }
    private var transfers: [ObjectIdentifier: Transfer] = [:]
    private struct Export {
        let directory: URL
        let file: URL
    }
    private var exports: [UUID: Export] = [:]
    private var pendingExports: [UUID] = []
    private var activeExport: UUID?
    private var presentationTimer: Timer?
    private let fileManager = FileManager.default

    private static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GridSpaceExports", isDirectory: true)
    }

    /// Called once at app launch, before any WebViews or transfers are created.
    static func removeOrphanedExports() {
        try? FileManager.default.removeItem(at: exportRoot)
    }

    func attach(_ download: WKDownload) {
        transfers[ObjectIdentifier(download)] = Transfer(download: download)
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let key = ObjectIdentifier(download)
        guard var transfer = transfers[key] else { completionHandler(nil); return }
        let directory = Self.exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // The site-supplied filename must never be interpreted as a path.
        let leaf = (suggestedFilename.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let cleaned = leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let filename = String(String.UnicodeScalarView(cleaned)).prefix(180)
        let safeName = filename.isEmpty || filename == "." || filename == ".." ? "download" : String(filename)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let destination = directory.appendingPathComponent(safeName)
            transfer.directory = directory
            transfer.destination = destination
            transfers[key] = transfer
            completionHandler(destination)
        } catch {
            completionHandler(nil)
            transfers.removeValue(forKey: key)
            showFailure()
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)),
              let directory = transfer.directory, let destination = transfer.destination else { return }
        let id = UUID()
        exports[id] = Export(directory: directory, file: destination)
        pendingExports.append(id)
        if presentationTimer == nil {
            presentationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.presentNextExport() }
            }
        }
        presentNextExport()
    }

    private func presentNextExport() {
        guard activeExport == nil, let id = pendingExports.first, let export = exports[id],
              let presenter, presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil,
              UIApplication.shared.applicationState == .active else { return }
        pendingExports.removeFirst()
        activeExport = id
        let activity = UIActivityViewController(activityItems: [export.file], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            // UIKit invokes this on the main thread for its presentation lifecycle.
            Task { @MainActor in self?.removeExport(id) }
        }
        activity.popoverPresentationController?.sourceView = presenter.view
        activity.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        presenter.present(activity, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)), let directory = transfer.directory {
            try? fileManager.removeItem(at: directory)
        }
        // Do not persist or automatically resume potentially account-scoped transfers.
        showFailure()
    }

    private func removeExport(_ id: UUID) {
        if let export = exports.removeValue(forKey: id) { try? fileManager.removeItem(at: export.directory) }
        if activeExport == id { activeExport = nil }
        pendingExports.removeAll { $0 == id }
        if pendingExports.isEmpty {
            presentationTimer?.invalidate()
            presentationTimer = nil
        }
    }

    private func showFailure() {
        guard let presenter, presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(title: "保存できませんでした", message: "通信状態や空き容量を確認してから、もう一度操作してください。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    func cancelAll() {
        presentationTimer?.invalidate()
        presentationTimer = nil
        let active = Array(transfers.values)
        transfers.removeAll()
        for transfer in active {
            transfer.download.delegate = nil
            transfer.download.cancel { _ in }
            if let directory = transfer.directory { try? fileManager.removeItem(at: directory) }
        }
        for id in Array(exports.keys) { removeExport(id) }
    }
}
