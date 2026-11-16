// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Adapts WebKit's file input to native selection without uploading anything.
/// WebKit receives local URLs and the Web client's existing File[] pipeline
/// still performs editing, metadata handling and the authorized upload.
@MainActor
final class WebUploads: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate,
                        UIImagePickerControllerDelegate, UINavigationControllerDelegate,
                        UIPopoverPresentationControllerDelegate {
    weak var presenter: UIViewController?
    private var completion: (@MainActor @Sendable ([URL]?) -> Void)?
    private var requestID: UUID?
    private var area: UploadStagingArea?
    private var completedAreas: [UploadStagingArea] = []
    private var progress: [PhotoSelectionOperation] = []
    private weak var panel: UIViewController?
    private var multiple = false
    private enum Phase { case choosing, transitioning, loading }
    private var phase = Phase.choosing

    override init() {
        super.init()
        // Selector observers are weakly held by NotificationCenter. UIKit sends
        // this notification on the main thread, unlike permission-panel inactivity.
        NotificationCenter.default.addObserver(self, selector: #selector(cancelPending),
                                              name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func begin(allowsMultiple: Bool, allowsDirectories: Bool, sourceHost: String,
               completion: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        guard self.completion == nil, let presenter,
              presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else {
            completion(nil)
            return
        }
        do { area = try UploadStagingArea() } catch { completion(nil); showFailure(); return }
        self.completion = completion
        requestID = UUID()
        multiple = allowsMultiple
        phase = .choosing
        if allowsDirectories {
            showFiles(directories: true)
            return
        }
        let menu = UIAlertController(title: "添付を選ぶ", message: "添付先: " + sourceHost, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "写真・動画", style: .default) { [weak self, weak menu] _ in
            self?.transition(from: menu) { $0.showPhotos() }
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            menu.addAction(UIAlertAction(title: "撮影", style: .default) { [weak self, weak menu] _ in
                self?.transition(from: menu) { $0.showCamera() }
            })
        }
        menu.addAction(UIAlertAction(title: "ファイル", style: .default) { [weak self, weak menu] _ in
            self?.transition(from: menu) { $0.showFiles(directories: false) }
        })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.finish(nil) })
        menu.popoverPresentationController?.sourceView = presenter.view
        menu.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        present(menu)
    }

    private func transition(from controller: UIViewController?, next: @escaping (WebUploads) -> Void) {
        guard let id = requestID else { return }
        phase = .transitioning
        let show = { [weak self] in
            guard let self, self.requestID == id else { return }
            next(self)
        }
        if let controller { controller.dismiss(animated: true, completion: show) }
        else { show() }
    }

    private func present(_ controller: UIViewController, phase: Phase = .choosing, animated: Bool = true) {
        guard completion != nil, let presenter, presenter.viewIfLoaded?.window != nil else { finish(nil); return }
        self.phase = phase
        panel = controller
        presenter.present(controller, animated: animated)
        // UIKit owns an alert-style UIAlertController's presentation delegate.
        // Replacing it raises an exception on device. Alerts cancel explicitly.
        if let alert = controller as? UIAlertController, alert.preferredStyle == .alert { return }
        controller.presentationController?.delegate = self
        controller.popoverPresentationController?.delegate = self
    }

    private func showPhotos() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = multiple ? 0 : 1
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker)
    }

    private func showCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
        picker.delegate = self
        present(picker)
    }

    private func showFiles(directories: Bool) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: directories ? [.folder] : [.item], asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = self
        present(picker)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let id = requestID, let area else { picker.dismiss(animated: true); return }
        guard !results.isEmpty else { finish(nil); return }
        phase = .loading
        picker.dismiss(animated: true) { [weak self] in
            guard let self, self.requestID == id else { return }
            self.showLoading()
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let urls = try await PhotoSelectionLoader.load(results.map(\.itemProvider), into: area,
                        shouldContinue: { [weak self] in self?.requestID == id },
                        onProgress: { [weak self] in self?.progress.append($0) })
                    guard self.requestID == id else { return }
                    self.finish(urls)
                } catch {
                    guard self.requestID == id else { return }
                    self.finish(nil, failed: true)
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importFiles(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        cancelIfCurrentChooser(popoverPresentationController)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        cancelIfCurrentChooser(presentationController)
    }

    private func cancelIfCurrentChooser(_ controller: UIPresentationController) {
        // Dismissal notifications can arrive after an old menu has yielded to
        // Photos/Files or while its selected files are being imported.
        guard phase == .choosing, panel === controller.presentedViewController else { return }
        finish(nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let url = info[.mediaURL] as? URL ?? info[.imageURL] as? URL {
            importFiles([url])
        } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1),
                  let id = requestID, let area {
            phase = .loading
            picker.dismiss(animated: true) { [weak self] in
                guard let self, self.requestID == id else { return }
                self.showLoading()
                Task { @MainActor [weak self] in
                    do {
                        let url = try await Task.detached(priority: .userInitiated) { try area.writeCameraImage(data) }.value
                        guard self?.requestID == id else { return }
                        self?.finish([url])
                    } catch {
                        guard self?.requestID == id else { return }
                        self?.finish(nil, failed: true)
                    }
                }
            }
        } else {
            finish(nil, failed: true)
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard let id = requestID, let area else { return }
        phase = .loading
        // The document picker has already copied provider-owned files locally.
        let action = { [weak self] in
            guard let self, self.requestID == id else { return }
            self.showLoading()
            Task { @MainActor [weak self] in
                do {
                    let selected = try await Task.detached(priority: .userInitiated) {
                        try urls.map { url in
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            return try area.copy(url)
                        }
                    }.value
                    guard self?.requestID == id else { return }
                    self?.finish(selected)
                } catch {
                    guard self?.requestID == id else { return }
                    self?.finish(nil, failed: true)
                }
            }
        }
        if let panel { panel.dismiss(animated: true, completion: action) } else { action() }
    }

    private func showLoading() {
        let alert = UIAlertController(title: "添付を準備しています", message: "iCloudのファイルは取得に時間がかかる場合があります。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.finish(nil) })
        // Loading can finish before a presentation animation completes.
        present(alert, phase: .loading, animated: false)
    }

    private func finish(_ urls: [URL]?, failed: Bool = false) {
        guard let completion else { return }
        self.completion = nil
        requestID = nil
        if urls == nil { progress.forEach { $0.cancel() } }
        progress.removeAll()
        if let area {
            if urls != nil { completedAreas.append(area) } else { area.dispose() }
        }
        area = nil
        let panel = self.panel
        self.panel = nil
        // Resolve before any asynchronous dismissal; navigation/shutdown cannot
        // leave a callback queued with URLs from an obsolete document.
        completion(urls)
        let done = { [weak self] in if failed { self?.showFailure() } }
        if let panel, panel.presentingViewController != nil { panel.dismiss(animated: !(panel is UIAlertController), completion: done) }
        else { done() }
    }

    private func showFailure() {
        guard let presenter, presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(title: "添付を読み込めませんでした", message: "通信状態や空き容量を確認して、もう一度選択してください。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    @objc func cancelPending() { finish(nil) }

    /// A new document/server must never inherit a prior selection or callback.
    func invalidate() {
        finish(nil)
        completedAreas.forEach { $0.dispose() }
        completedAreas.removeAll()
    }
}
