// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Darwin
import Foundation
import GridSpaceCore
import ImageIO
import UniformTypeIdentifiers

/// Own user-selected bytes and input metadata only. A Drive ID is scoped by the
/// surrounding draft's origin/account/reply key, never a URL or fetched body.
struct NativeAttachmentDraft: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var comment = ""
    var sensitive = false
    var byteCount: Int
    var mimeType: String
    var driveID: String?
    var outcomeUnknown = false
}

enum NativeAttachmentError: Error, Equatable {
    case tooLarge, unavailable, invalidFile, tooMany, metadataTooLong
    var message: String {
        switch self {
        case .tooLarge: return "ファイルがアップロード上限を超えています。"
        case .unavailable: return "選んだファイルを読み込めませんでした。もう一度選択してください。"
        case .invalidFile: return "通常のファイルを選択してください。フォルダやリンクは添付できません。"
        case .tooMany: return "添付は16件までです。"
        case .metadataTooLong: return "ファイル名または説明が長すぎます。"
        }
    }
}

actor NativeAttachmentFiles {
    let root: URL
    init(testing: Bool, directory: URL? = nil) {
        root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GridSpaceNativeAttachments", isDirectory: true)
            .appendingPathComponent(testing ? "Testing" : "Drafts", isDirectory: true)
    }
    private func prepareRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var directory = root
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
    }
    func importFile(_ source: URL, maximum: Int) throws -> NativeAttachmentDraft {
        try Task.checkCancellation()
        guard source.isFileURL else { throw NativeAttachmentError.invalidFile }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw NativeAttachmentError.invalidFile }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw NativeAttachmentError.invalidFile }
        guard maximum > 0, info.st_size > 0, info.st_size <= maximum else { throw NativeAttachmentError.tooLarge }
        var entry = NativeAttachmentDraft(name: UploadFilename.sanitized(source.lastPathComponent), byteCount: Int(info.st_size),
                                          mimeType: UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
        try prepareRoot()
        let destination = url(entry.id)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw NativeAttachmentError.unavailable }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var count = 0
            while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                guard data.count <= maximum - count else { throw NativeAttachmentError.tooLarge }
                try output.write(contentsOf: data); count += data.count
            }
            guard count > 0 else { throw NativeAttachmentError.unavailable }
            entry.byteCount = count
            return entry
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func thumbnail(_ id: UUID) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(id) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 480] as CFDictionary)
    }
    func url(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }
    func remove(_ ids: [UUID]) { for id in ids { try? FileManager.default.removeItem(at: url(id)) } }
    func removeOrphans(keeping ids: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where !ids.contains(UUID(uuidString: file.lastPathComponent) ?? UUID()) { try? FileManager.default.removeItem(at: file) }
    }
}

/// Multipart is streamed from a protected temporary file. The authorization
/// token is sent only in a header and never written into that file.
enum NativeMultipart {
    static func removeOrphanedFiles() {
        let root = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("native-upload-") { try? FileManager.default.removeItem(at: file) }
    }
    static func write(source: URL, entry: NativeAttachmentDraft, directory: URL = FileManager.default.temporaryDirectory) throws -> (URL, String, Int) {
        guard entry.name.count <= 200, entry.comment.count <= 512 else { throw NativeAttachmentError.metadataTooLong }
        let boundary = "GridSpace-" + UUID().uuidString
        let url = directory.appendingPathComponent("native-upload-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw NativeAttachmentError.unavailable }
        do {
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }
            func write(_ value: String) throws { try output.write(contentsOf: Data(value.utf8)) }
            for (name, value) in [("name", UploadFilename.sanitized(entry.name)), ("comment", entry.comment), ("isSensitive", entry.sensitive ? "true" : "false"), ("force", "true")] {
                try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
            }
            // A constant wire filename avoids quoting/header injection. The
            // separately encoded name field preserves the user's display name.
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"attachment\"\r\nContent-Type: application/octet-stream\r\n\r\n")
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            var count = 0
            while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                guard data.count <= entry.byteCount - count else { throw NativeAttachmentError.invalidFile }
                try output.write(contentsOf: data); count += data.count
            }
            guard count == entry.byteCount else { throw NativeAttachmentError.invalidFile }
            try write("\r\n--\(boundary)--\r\n")
            return (url, boundary, Int(try output.offset()))
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
}
