// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GridSpaceCore
import PhotosUI
import SwiftUI

protocol NativeAttachmentAPI: Sendable {
    func upload(source: URL, entry: NativeAttachmentDraft) async throws -> ClientFile
    func verifyOwnFile(_ id: String, owner: String) async throws
}

@MainActor
final class NativeAttachments: ObservableObject {
    @Published var entries: [NativeAttachmentDraft] = []
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published var error: String?
    let files: NativeAttachmentFiles
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var progress: PhotoSelectionOperation?
    init(files: NativeAttachmentFiles) { self.files = files }
    var ready: Bool { !busy && entries.allSatisfy { $0.driveID != nil && !$0.outcomeUnknown } }
    // SwiftUI may read a disappearing Toggle after a collection mutation.
    // Bind by stable ID; a removed row cannot index or edit another attachment.
    func binding(for entry: NativeAttachmentDraft) -> Binding<NativeAttachmentDraft> {
        Binding(get: { self.entries.first { $0.id == entry.id } ?? entry }, set: { value in
            if let index = self.entries.firstIndex(where: { $0.id == entry.id }) { self.entries[index] = value }
        })
    }

    func importURLs(_ urls: [URL], maximum: Int, persist: @escaping () -> Void) {
        runImport(maximum: maximum, persist: persist) { _ in urls }
    }
    func importPhotos(_ providers: [NSItemProvider], maximum: Int, persist: @escaping () -> Void) {
        runImport(maximum: maximum, persist: persist) { [weak self] valid in
            let area = try UploadStagingArea()
            do {
                let urls = try await PhotoSelectionLoader.load(providers, into: area, maximumFileBytes: maximum, shouldContinue: valid, onProgress: { self?.progress = $0 })
                // Keep the staging area through the subsequent durable copies.
                self?.photoArea = area
                return urls
            } catch { area.dispose(); throw error }
        }
    }
    private var photoArea: UploadStagingArea?
    private func runImport(maximum: Int, persist: @escaping () -> Void,
                           sources: @escaping @MainActor (@escaping @MainActor () -> Bool) async throws -> [URL]) {
        guard !busy else { return }
        busy = true; error = nil; status = "ファイルを読み込み中"
        let request = UUID(); generation = request
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == request { photoArea?.dispose(); photoArea = nil; progress = nil; busy = false; status = nil; task = nil } }
            do {
                let urls = try await sources { [weak self] in self?.generation == request && !Task.isCancelled }
                for source in urls {
                    guard generation == request, !Task.isCancelled else { return }
                    guard entries.count < 16 else { throw NativeAttachmentError.tooMany }
                    let entry = try await files.importFile(source, maximum: maximum)
                    guard generation == request, !Task.isCancelled else { await files.remove([entry.id]); return }
                    entries.append(entry); persist()
                }
            } catch { if generation == request, !Task.isCancelled { self.error = Self.explain(error) } }
        }
    }
    func upload(using api: any NativeAttachmentAPI, accepts: @escaping () -> Bool, persist: @escaping () -> Void) {
        guard !busy, !entries.contains(where: \.outcomeUnknown) else { return }
        busy = true; error = nil
        let request = UUID(); generation = request
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == request { busy = false; status = nil; task = nil } }
            for id in entries.map(\.id) {
                guard generation == request, accepts(), !Task.isCancelled else { return }
                guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].driveID == nil else { continue }
                // Persist ambiguity before the first outbound byte. A cancelled
                // task, background transition or crash cannot silently retry it.
                entries[index].outcomeUnknown = true; persist()
                guard accepts() else { return }
                let entry = entries[index]
                status = "\(index + 1)/\(entries.count) をアップロード中"
                do {
                    let url = await files.url(id)
                    let uploaded = try await api.upload(source: url, entry: entry)
                    guard generation == request, accepts(), !Task.isCancelled else { return }
                    entries[index].driveID = uploaded.id; entries[index].outcomeUnknown = false
                    persist(); await files.remove([id])
                } catch {
                    guard generation == request, !Task.isCancelled else { return }
                    if let local = error as? NativeAttachmentError {
                        entries[index].outcomeUnknown = false; self.error = local.message
                    } else if case ClientAPIError.rejected(let status, _) = error, (400..<500).contains(status), status != 408 {
                        entries[index].outcomeUnknown = false
                        self.error = status == 403 ? "添付の権限がありません。アカウントメニューからログインし直し、ドライブの権限を確認してください。" : Self.explain(error)
                    } else { self.error = "アップロード結果が不明です。ドライブを確認してください。自動では再送しません。" }
                    persist(); return
                }
            }
        }
    }
    /// The compose action awaits this operation; a lost upload response stays
    /// ambiguous and prevents the subsequent note write or an automatic retry.
    func uploadAndWait(using api: any NativeAttachmentAPI, accepts: @escaping () -> Bool, persist: @escaping () -> Void) async -> Bool {
        guard !busy, accepts(), !Task.isCancelled else { return false }
        if ready { return true }
        upload(using: api, accepts: accepts, persist: persist)
        await task?.value
        return ready && accepts() && !Task.isCancelled
    }

    func addDriveFile(_ file: ClientFile, persist: () -> Void) {
        guard !busy, entries.count < 16, !entries.contains(where: { $0.driveID == file.id }) else { return }
        entries.append(NativeAttachmentDraft(name: file.name, comment: file.comment ?? "", sensitive: file.isSensitive,
                                              byteCount: file.size ?? 0, mimeType: file.type, driveID: file.id))
        persist()
    }
    func remove(_ id: UUID, persist: () -> Void) {
        guard !busy else { return }
        entries.removeAll { $0.id == id }; persist()
        Task { await files.remove([id]) }
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; progress?.cancel(); progress = nil
        photoArea?.dispose(); photoArea = nil; busy = false; status = nil
    }
    static func explain(_ error: Error) -> String {
        if let error = error as? NativeAttachmentError { return error.message }
        if let error = error as? UploadStagingArea.StagingError {
            switch error {
            case .tooLarge: return NativeAttachmentError.tooLarge.message
            case .unsupportedFile: return NativeAttachmentError.invalidFile.message
            case .cancelled: return "ファイルの選択を中止しました。"
            }
        }
        if error is CocoaError { return "ファイルを保存できませんでした。端末の空き容量とファイルの読み取り権限を確認してください。" }
        return NativeClientSession.explain(error)
    }
}

enum NativeAttachmentPickerKind: String, Identifiable { case photos, files, drive; var id: String { rawValue } }

struct NativePhotoPicker: UIViewControllerRepresentable {
    let limit: Int
    let picked: ([NSItemProvider]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(picked) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos]); config.selectionLimit = max(1, limit)
        config.selection = .ordered; config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let picked: ([NSItemProvider]) -> Void
        init(_ picked: @escaping ([NSItemProvider]) -> Void) { self.picked = picked }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { picked(results.map(\.itemProvider)) }
    }
}

struct NativeFilePicker: UIViewControllerRepresentable {
    let picked: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(picked) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: ([URL]) -> Void
        init(_ picked: @escaping ([URL]) -> Void) { self.picked = picked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { picked(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { picked([]) }
    }
}

struct NativeDrivePicker: View {
    @ObservedObject var session: NativeClientSession
    var browsing = false
    @State private var preview: ClientFile?
    let selected: (ClientFile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var files: [ClientFile] = []
    @State private var loading = false
    @State private var more = true
    @State private var error: String?
    @State private var request = UUID()
    var body: some View {
        NavigationStack {
            List {
                ForEach(files) { file in
                    Button { Task { await choose(file) } } label: {
                        VStack(alignment: .leading) { Label(file.name, systemImage: file.isSensitive ? "eye.slash" : "doc"); Text(file.type).font(.caption).foregroundStyle(.secondary) }
                    }.disabled(loading)
                }
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary); Button("再試行") { Task { await load(reset: files.isEmpty) } } }
                if !loading, more { Button("もっと見る") { Task { await load(reset: false) } } }
                if files.isEmpty, !loading, error == nil { Text(browsing ? "ファイルはありません" : "添付できるファイルはありません") }
            }.navigationTitle(browsing ? "ドライブ" : "ドライブから添付")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }.task(id: session.revision) { await load(reset: true) }
            .sheet(item: $preview) { file in NavigationStack { NativeMediaView(file: file) } }
            .onChange(of: session.revision) { _ in preview = nil }
            .onDisappear { request = UUID(); files = []; error = nil; preview = nil }
    }
    private func load(reset: Bool) async {
        let revision = session.revision, id = UUID(); request = id
        if reset { files = [] }
        guard session.active else { return }
        loading = true; error = nil
        do {
            let result = try await session.api.driveFiles(until: reset ? nil : files.last?.id)
            guard session.accepts(revision), request == id else { return }
            let known = Set(files.map(\.id)); files += result.filter { !known.contains($0.id) }; more = result.count == 30
        } catch { if session.accepts(revision), request == id { self.error = NativeAttachments.explain(error) } }
        if request == id { loading = false }
    }
    private func choose(_ file: ClientFile) async {
        guard !loading, let owner = session.user?.id else { return }
        let revision = session.revision, selection = UUID(); request = selection; loading = true
        do {
            let fresh = try await session.api.ownFile(file.id, owner: owner)
            if session.accepts(revision), request == selection { if browsing { preview = fresh } else { selected(fresh); dismiss() } }
        } catch { if session.accepts(revision), request == selection { self.error = NativeAttachments.explain(error) } }
        if request == selection { loading = false }
    }
}
