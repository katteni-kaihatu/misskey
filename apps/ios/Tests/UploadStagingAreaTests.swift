// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpace

final class UploadStagingAreaTests: XCTestCase {
    func testRepeatedNamesRemainDistinctAndCopiesSurviveProviderRemoval() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let bytes = Data("synthetic attachment".utf8)
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let area = try UploadStagingArea()
        defer { area.dispose() }
        let first = try area.copy(source, suggestedName: "../same.txt")
        let second = try area.copy(source, suggestedName: "../same.txt")
        try FileManager.default.removeItem(at: source)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "same.txt")
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(try Data(contentsOf: second), bytes)
    }

    func testSelectedSymlinksCannotExposeUnselectedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("unselected.txt")
        try Data("synthetic secret".utf8).write(to: target)
        let directory = root.appendingPathComponent("selected-folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let area = try UploadStagingArea()
        defer { area.dispose() }
        XCTAssertThrowsError(try area.copy(link))
        XCTAssertThrowsError(try area.copy(directory))
    }

    func testCancellationRemovesFilesAndRejectsLateProviderCompletion() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("synthetic".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let area = try UploadStagingArea()
        let copy = try area.copy(source)
        area.dispose()
        // copy synchronizes with queued cleanup, making this assertion deterministic.
        XCTAssertThrowsError(try area.copy(source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }
}
