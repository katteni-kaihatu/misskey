// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import UniformTypeIdentifiers

/// Photos providers may invoke their callback again when NSProgress is cancelled.
/// Claim the continuation before copying, and cancel only a still-pending load.
final class PhotoSelectionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: Progress?

    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }

    func attach(_ progress: Progress) {
        lock.lock()
        if continuation != nil { self.progress = progress }
        lock.unlock()
    }

    private func take() -> (CheckedContinuation<URL, Error>, Progress?)? {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return nil }
        let progress = self.progress
        self.continuation = nil
        self.progress = nil
        return (continuation, progress)
    }

    func complete(source: URL?, error: Error?, area: UploadStagingArea, suggestedName: String?, maximumFileBytes: Int? = nil) {
        guard let (continuation, progress) = take() else { return }
        // Keep the progress alive until outside the lock and through the copy.
        defer { withExtendedLifetime(progress) { } }
        guard let source else {
            continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
            return
        }
        do { continuation.resume(returning: try area.copy(source, suggestedName: suggestedName, maximumFileBytes: maximumFileBytes)) }
        catch { continuation.resume(throwing: error) }
    }

    func cancel() {
        guard let (continuation, progress) = take() else { return }
        continuation.resume(throwing: CancellationError())
        progress?.cancel()
    }
}

@MainActor
enum PhotoSelectionLoader {
    /// Sequential loads preserve the picker's order and bound simultaneous iCloud
    /// retrievals. Copy within each provider callback, before its URL expires.
    static func load(_ providers: [NSItemProvider], into area: UploadStagingArea,
                     maximumFileBytes: Int? = nil,
                     shouldContinue: () -> Bool, onProgress: (PhotoSelectionOperation) -> Void) async throws -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            try Task.checkCancellation()
            guard shouldContinue() else { throw UploadStagingArea.StagingError.cancelled }
            guard let type = provider.registeredTypeIdentifiers.first(where: {
                guard let type = UTType($0) else { return false }
                return type.conforms(to: .image) || type.conforms(to: .movie)
            }) else { throw CocoaError(.fileReadUnknown) }
            let suggestedName = provider.suggestedName
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                let operation = PhotoSelectionOperation(continuation)
                let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    operation.complete(source: url, error: error, area: area, suggestedName: suggestedName, maximumFileBytes: maximumFileBytes)
                }
                operation.attach(progress)
                onProgress(operation)
            }
            urls.append(url)
        }
        guard shouldContinue() else { throw UploadStagingArea.StagingError.cancelled }
        return urls
    }
}
