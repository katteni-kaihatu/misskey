// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import XCTest
@testable import GridSpace

final class NativeAttachmentFileTests: XCTestCase {
    func testDurableCopiesRejectSymlinksAndSizeLimitsAndCollectOnlyOrphans() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic.txt")
        let bytes = Data("synthetic own bytes".utf8)
        try bytes.write(to: source)
        let files = NativeAttachmentFiles(testing: true, directory: directory.appendingPathComponent("owned"))
        let entry = try await files.importFile(source, maximum: bytes.count)
        let copy = await files.url(entry.id)
        XCTAssertEqual(try Data(contentsOf: copy), bytes)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: copy), bytes, "The provider URL may disappear after selection")
        let link = directory.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: copy)
        do { _ = try await files.importFile(link, maximum: 1000); XCTFail("No symlink imports") }
        catch { XCTAssertEqual(error as? NativeAttachmentError, .invalidFile) }
        do { _ = try await files.importFile(copy, maximum: 1); XCTFail("No partial oversize imports") }
        catch { XCTAssertEqual(error as? NativeAttachmentError, .tooLarge) }
        await files.removeOrphans(keeping: [entry.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        await files.removeOrphans(keeping: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    func testMultipartPreservesBytesAndFieldsWithoutHeaderInjection() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data([0, 255, 13, 10, 45, 97, 98])
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let entry = NativeAttachmentDraft(name: "../日本語\"\r\nX-Injection: yes.png", comment: "説明\nline", sensitive: true, byteCount: data.count, mimeType: "image/png")
        let (body, boundary, count) = try NativeMultipart.write(source: source, entry: entry)
        defer { try? FileManager.default.removeItem(at: body) }
        let result = try Data(contentsOf: body)
        XCTAssertEqual(result.count, count)
        XCTAssertNotNil(result.range(of: data))
        XCTAssertNotNil(result.range(of: Data("name=\"isSensitive\"\r\n\r\ntrue\r\n".utf8)))
        XCTAssertNotNil(result.range(of: Data("説明\nline".utf8)))
        XCTAssertNotNil(result.range(of: Data("filename=\"attachment\"\r\nContent-Type: application/octet-stream\r\n".utf8)))
        XCTAssertTrue(result.suffix(Data("--\(boundary)--\r\n".utf8).count).elementsEqual(Data("--\(boundary)--\r\n".utf8)))
        XCTAssertNil(result.range(of: Data("\r\nX-Injection:".utf8)))
    }

    func testOldDraftsStillDecodeAndNewDraftsRetainAttachmentOrderAndScope() throws {
        let data = Data(#"{"text":"old","cw":"","useCW":false,"visibility":"followers","outcomeUnknown":false}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(NativeDraft.self, from: data).attachments.isEmpty)
        let suite = "NativeAttachmentDraftTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NativeDraftStore(defaults: defaults), origin = try ServerOrigin("https://synthetic.example")
        let first = NativeAttachmentDraft(name: "one", byteCount: 3, mimeType: "text/plain", driveID: "own-file")
        let second = NativeAttachmentDraft(name: "two", byteCount: 4, mimeType: "text/plain", outcomeUnknown: true)
        store.write(NativeDraft(attachments: [second, first]), origin: origin, account: "owner", reply: "reply")
        XCTAssertEqual(store.read(origin: origin, account: "owner", reply: "reply")?.attachments, [second, first])
        XCTAssertNil(store.read(origin: origin, account: "other", reply: "reply"))
        XCTAssertNil(store.read(origin: origin, account: "owner", reply: nil))
        XCTAssertEqual(store.attachmentIDs(), Set([first.id, second.id]))
    }

    func testUnreadableDraftIsKeptAndPreventsAutomaticFileCollectionOrOverwrite() throws {
        let suite = "NativeUnreadableDraftTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NativeDraftStore(defaults: defaults), origin = try ServerOrigin("https://synthetic.example")
        store.write(NativeDraft(text: "before"), origin: origin, account: "owner", reply: nil)
        let key = try XCTUnwrap(defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("gridspace.nativeDraft.v1.") })
        let damaged = Data("unreadable synthetic draft".utf8)
        defaults.set(damaged, forKey: key)
        XCTAssertNil(store.attachmentIDs())
        XCTAssertFalse(store.write(NativeDraft(text: "after"), origin: origin, account: "owner", reply: nil))
        XCTAssertEqual(defaults.data(forKey: key), damaged)
        store.remove(origin: origin, account: "owner", reply: nil)
        XCTAssertTrue(store.write(NativeDraft(text: "new"), origin: origin, account: "owner", reply: nil))
    }
}

@MainActor
final class NativeAttachmentStateTests: XCTestCase {
    func testPartialUploadRetainsCompletedIDsAndAnAmbiguousItemIsNeverAutomaticallyRetried() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = NativeAttachmentFiles(testing: true, directory: directory.appendingPathComponent("owned"))
        let source = directory.appendingPathComponent("input.txt"); try Data("synthetic".utf8).write(to: source)
        let first = try await files.importFile(source, maximum: 100), second = try await files.importFile(source, maximum: 100)
        let model = NativeAttachments(files: files); model.entries = [first, second]
        let api = AttachmentAPIStub(modes: [.success, .network])
        var persisted: [[NativeAttachmentDraft]] = []
        model.upload(using: api, accepts: { true }, persist: { persisted.append(model.entries) })
        try await wait { !model.busy }
        XCTAssertEqual(model.entries.first?.driveID, "file-1")
        XCTAssertTrue(model.entries[1].outcomeUnknown)
        XCTAssertEqual(persisted.first?.first?.outcomeUnknown, true, "Ambiguity is durable before calling the API")
        XCTAssertFalse(model.ready)
        model.upload(using: api, accepts: { true }, persist: {})
        let calls = await api.count
        XCTAssertEqual(calls, 2)
        model.entries[1].outcomeUnknown = false // explicit user confirmation
        model.upload(using: api, accepts: { true }, persist: {})
        try await wait { !model.busy }
        let finalCalls = await api.count
        XCTAssertEqual(finalCalls, 3, "The completed first file must not upload again")
        XCTAssertTrue(model.ready)
        let firstURL = await files.url(first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
    }

    func testComposeCanAwaitUploadsAndAnAlreadyUploadedSelectionDoesNotUploadAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = NativeAttachmentFiles(testing: true, directory: directory.appendingPathComponent("owned"))
        let source = directory.appendingPathComponent("input.txt"); try Data("synthetic".utf8).write(to: source)
        let model = NativeAttachments(files: files)
        model.entries = [try await files.importFile(source, maximum: 100), try await files.importFile(source, maximum: 100)]
        let api = AttachmentAPIStub(modes: [.success, .success])
        let ready = await model.uploadAndWait(using: api, accepts: { true }, persist: {})
        XCTAssertTrue(ready); XCTAssertEqual(model.entries.compactMap(\.driveID), ["file-1", "file-2"])
        let again = await model.uploadAndWait(using: api, accepts: { true }, persist: {})
        XCTAssertTrue(again)
        let calls = await api.count; XCTAssertEqual(calls, 2)
    }

    func testAwaitingAnAmbiguousUploadCannotPermitPostingOrRepeatTheUpload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = NativeAttachmentFiles(testing: true, directory: directory.appendingPathComponent("owned"))
        let source = directory.appendingPathComponent("input.txt"); try Data("synthetic".utf8).write(to: source)
        let model = NativeAttachments(files: files); model.entries = [try await files.importFile(source, maximum: 100)]
        let api = AttachmentAPIStub(modes: [.network])
        let ready = await model.uploadAndWait(using: api, accepts: { true }, persist: {})
        XCTAssertFalse(ready); XCTAssertTrue(model.entries[0].outcomeUnknown)
        let again = await model.uploadAndWait(using: api, accepts: { true }, persist: {})
        XCTAssertFalse(again)
        let calls = await api.count; XCTAssertEqual(calls, 1)
    }

    func testDefiniteRejectionCanRetryAndCancellationKeepsAnUnknownResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = NativeAttachmentFiles(testing: true, directory: directory.appendingPathComponent("owned"))
        let source = directory.appendingPathComponent("input.txt"); try Data("synthetic".utf8).write(to: source)
        let entry = try await files.importFile(source, maximum: 100)
        let model = NativeAttachments(files: files); model.entries = [entry]
        let api = AttachmentAPIStub(modes: [.rejected, .waiting])
        model.upload(using: api, accepts: { true }, persist: {})
        try await wait { !model.busy }
        XCTAssertFalse(model.entries[0].outcomeUnknown)
        model.upload(using: api, accepts: { true }, persist: {})
        try await wait { model.entries[0].outcomeUnknown }
        model.cancel()
        XCTAssertTrue(model.entries[0].outcomeUnknown)
        XCTAssertFalse(model.ready)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Attachment operation did not settle")
    }

    func testRowBindingsKeepIdentityAfterReorderAndRemainSafeAfterRemoval() {
        let model = NativeAttachments(files: NativeAttachmentFiles(testing: true))
        let first = NativeAttachmentDraft(name: "first", byteCount: 1, mimeType: "text/plain")
        let second = NativeAttachmentDraft(name: "second", byteCount: 1, mimeType: "text/plain")
        model.entries = [first, second]
        let binding = model.binding(for: first)
        model.entries.swapAt(0, 1)
        binding.wrappedValue.sensitive = true
        XCTAssertFalse(model.entries[0].sensitive)
        XCTAssertTrue(model.entries[1].sensitive)
        model.entries = []
        XCTAssertEqual(binding.wrappedValue.name, "first", "A disappearing Switch can still read its old value")
        binding.wrappedValue.sensitive = false
        XCTAssertTrue(model.entries.isEmpty, "A stale editor must not resurrect a removed file")
    }

    func testCancelledSelectionCannotAppendToOrClearANewerSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = directory.appendingPathComponent("old.txt"), b = directory.appendingPathComponent("new.txt")
        try Data("old selection".utf8).write(to: a); try Data("new selection".utf8).write(to: b)
        let files = NativeAttachmentFiles(testing: true, directory: directory.appendingPathComponent("owned"))
        let model = NativeAttachments(files: files)
        model.importURLs([a], maximum: 100, persist: {})
        model.cancel()
        model.importURLs([b], maximum: 100, persist: {})
        try await wait { !model.busy }
        XCTAssertEqual(model.entries.map(\.name), ["new.txt"])
        let url = await files.url(try XCTUnwrap(model.entries.first?.id))
        XCTAssertEqual(try Data(contentsOf: url), Data("new selection".utf8))
    }
}

private actor AttachmentAPIStub: NativeAttachmentAPI {
    enum Mode { case success, network, rejected, waiting }
    var modes: [Mode]
    private(set) var count = 0
    init(modes: [Mode]) { self.modes = modes }
    func upload(source: URL, entry: NativeAttachmentDraft) async throws -> ClientFile {
        count += 1
        let mode = modes.isEmpty ? .success : modes.removeFirst()
        switch mode {
        case .network: throw URLError(.networkConnectionLost)
        case .rejected: throw ClientAPIError.rejected(status: 413, code: "MAX_FILE_SIZE_EXCEEDED")
        case .waiting: try await Task.sleep(nanoseconds: 30_000_000_000)
        case .success: break
        }
        return try JSONDecoder().decode(ClientFile.self, from: Data("{\"id\":\"file-\(count)\",\"name\":\"synthetic\",\"type\":\"text/plain\",\"isSensitive\":false}".utf8))
    }
    func verifyOwnFile(_ id: String, owner: String) async throws {}
}
