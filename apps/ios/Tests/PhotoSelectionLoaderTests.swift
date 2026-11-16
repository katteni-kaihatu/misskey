// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import UniformTypeIdentifiers
import XCTest
@testable import GridSpace

@MainActor
final class PhotoSelectionLoaderTests: XCTestCase {
    func testOrderedSelectionPreservesOriginalBytesAndExtensions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let area = try UploadStagingArea()
        defer { area.dispose() }
        let providers = try ["first", "second"].map { name -> NSItemProvider in
            let url = directory.appendingPathComponent(name + ".heic")
            try Data(name.utf8).write(to: url)
            let provider = NSItemProvider()
            provider.suggestedName = name
            provider.registerFileRepresentation(forTypeIdentifier: UTType.heic.identifier, fileOptions: [], visibility: .all) { completion in
                completion(url, false, nil)
                return nil
            }
            return provider
        }
        let files = try await PhotoSelectionLoader.load(providers, into: area, shouldContinue: { true }, onProgress: { _ in })
        XCTAssertEqual(files.map(\.lastPathComponent), ["first.heic", "second.heic"])
        XCTAssertEqual(try files.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }, ["first", "second"])
    }

    func testDuplicateCompletionAfterSuccessCannotResumeTwice() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("synthetic image".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let area = try UploadStagingArea()
        defer { area.dispose() }
        let copied: URL = try await withCheckedThrowingContinuation { continuation in
            let operation = PhotoSelectionOperation(continuation)
            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = { XCTFail("Completed provider was cancelled") }
            operation.attach(progress)
            operation.complete(source: source, error: nil, area: area, suggestedName: nil)
            operation.complete(source: nil, error: CancellationError(), area: area, suggestedName: nil)
            operation.cancel()
        }
        XCTAssertEqual(try Data(contentsOf: copied), Data("synthetic image".utf8))
    }

    func testNativeSizeLimitRejectsProviderFileBeforeStagingACopy() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data(repeating: 17, count: 1024).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let area = try UploadStagingArea()
        defer { area.dispose() }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(source, false, nil); return nil
        }
        do {
            _ = try await PhotoSelectionLoader.load([provider], into: area, maximumFileBytes: 100, shouldContinue: { true }, onProgress: { _ in })
            XCTFail("Do not copy the oversized original")
        } catch UploadStagingArea.StagingError.tooLarge { }
    }

    func testCancellationCompletesEvenWhenProviderNeverRepliesAndIgnoresLateReply() async throws {
        let area = try UploadStagingArea()
        defer { area.dispose() }
        do {
            let _: URL = try await withCheckedThrowingContinuation { continuation in
                let operation = PhotoSelectionOperation(continuation)
                operation.attach(Progress(totalUnitCount: 1))
                operation.cancel()
                operation.complete(source: nil, error: CocoaError(.fileReadUnknown), area: area, suggestedName: nil)
            }
            XCTFail("Cancelled load succeeded")
        } catch is CancellationError { }
    }

    func testCancelledRequestNeverStartsAnotherProvider() async throws {
        let area = try UploadStagingArea()
        defer { area.dispose() }
        do {
            _ = try await PhotoSelectionLoader.load([NSItemProvider()], into: area, shouldContinue: { false }, onProgress: { _ in XCTFail("Cancelled selection started loading") })
            XCTFail("Cancelled selection succeeded")
        } catch UploadStagingArea.StagingError.cancelled { }
    }
}
