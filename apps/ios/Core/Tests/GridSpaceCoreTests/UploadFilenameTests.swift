// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class UploadFilenameTests: XCTestCase {
    func testNamesCannotEscapeTheStagingDirectory() {
        XCTAssertEqual(UploadFilename.sanitized("../../photo.jpg"), "photo.jpg")
        XCTAssertEqual(UploadFilename.sanitized("C:\\Users\\test\\photo.jpg"), "photo.jpg")
        XCTAssertEqual(UploadFilename.sanitized("a\u{0000}\n.jpg"), "a.jpg")
        for name in ["", ".", "..", "/", "\\"] {
            XCTAssertEqual(UploadFilename.sanitized(name), "attachment")
        }
    }

    func testUnicodeNamesAreBoundedInBytesAndRemainValid() {
        let result = UploadFilename.sanitized(String(repeating: "📸", count: 100) + ".jpg")
        XCTAssertLessThanOrEqual(result.utf8.count, 180)
        XCTAssertFalse(result.contains("�"))
        XCTAssertTrue(result.hasSuffix(".jpg"))
        XCTAssertEqual(UploadFilename.sanitized("猫の写真.heic"), "猫の写真.heic")
    }
}
