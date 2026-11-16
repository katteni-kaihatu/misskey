// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GridSpaceCore

/// Per-selection ownership. Provider callbacks copy files before their temporary
/// URL expires. Copies and cleanup are serialized away from the main thread.
final class UploadStagingArea: @unchecked Sendable {
    enum StagingError: Error { case cancelled, tooLarge, unsupportedFile }
    private let queue = DispatchQueue(label: "dev.gridspace.upload-staging", qos: .userInitiated)
    private let directory: URL
    private var disposed = false

    private static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GridSpaceUploads", isDirectory: true)
    }

    static func removeOrphanedFiles() {
        try? FileManager.default.removeItem(at: root)
    }

    init() throws {
        directory = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
    }

    func copy(_ source: URL, suggestedName: String? = nil, maximumFileBytes: Int? = nil) throws -> URL {
        try queue.sync {
            guard !disposed else { throw StagingError.cancelled }
            guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
            let properties = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            guard properties.isSymbolicLink != true,
                  properties.isRegularFile == true || properties.isDirectory == true else { throw CocoaError(.fileReadNoPermission) }
            if let maximumFileBytes {
                guard properties.isRegularFile == true else { throw StagingError.unsupportedFile }
                guard let size = properties.fileSize, size > 0, size <= maximumFileBytes else { throw StagingError.tooLarge }
            }
            if properties.isDirectory == true {
                guard let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
                    throw CocoaError(.fileReadNoPermission)
                }
                for case let file as URL in files {
                    if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                        throw CocoaError(.fileReadNoPermission)
                    }
                }
            }
            // Never let WebKit follow a selected symlink into app-owned files.
            // A separate directory preserves repeated names and selection order.
            let item = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true,
                                                   attributes: [.protectionKey: FileProtectionType.complete])
            var name = suggestedName ?? source.lastPathComponent
            if (name as NSString).pathExtension.isEmpty, !source.pathExtension.isEmpty {
                name += "." + source.pathExtension
            }
            let destination = item.appendingPathComponent(UploadFilename.sanitized(name))
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
                return destination
            } catch {
                try? FileManager.default.removeItem(at: item)
                throw error
            }
        }
    }

    func writeCameraImage(_ data: Data) throws -> URL {
        try queue.sync {
            guard !disposed else { throw StagingError.cancelled }
            let destination = directory.appendingPathComponent("camera-\(UUID().uuidString).jpg")
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            return destination
        }
    }

    func dispose() {
        queue.async { [self] in
            disposed = true
            try? FileManager.default.removeItem(at: directory)
        }
    }

    deinit {
        // Usually already disposed by its document owner. No queued work holds
        // the last reference when this fallback runs.
        try? FileManager.default.removeItem(at: directory)
    }
}
