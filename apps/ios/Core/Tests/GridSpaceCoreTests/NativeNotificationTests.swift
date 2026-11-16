// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativeNotificationTests: XCTestCase {
    func testKnownNotificationKindsKeepTheirAPIValuesAndAnUnknownKindStillDecodes() throws {
        XCTAssertEqual(ClientNotificationKind.allCases.count, 20)
        XCTAssertEqual(Set(ClientNotificationKind.allCases.map(\.rawValue)).count, 20)
        let data = Data("{\"id\":\"future\",\"type\":\"future-event\",\"createdAt\":\"2026-11-16T00:00:00.123Z\",\"body\":{\"newPayload\":true},\"user\":\"new-user-format\"}".utf8)
        let item = try JSONDecoder().decode(ClientNotification.self, from: data)
        XCTAssertNil(item.kind); XCTAssertNotNil(item.date); XCTAssertEqual(item.detailWebPath, "/my/notifications")
        XCTAssertNil(item.user); XCTAssertNil(item.body)
    }
    func testAppAndInvitationPayloadsRemainDataAndFileRoutesRejectPathInjection() throws {
        let base: [String: Any] = ["id": "notification", "type": "app", "createdAt": "2026-11-16T00:00:00Z", "header": "Synthetic header", "body": "**Synthetic body**", "invitation": ["room": ["id": "room", "name": "Synthetic room"]]]
        let app = try JSONDecoder().decode(ClientNotification.self, from: JSONSerialization.data(withJSONObject: base))
        XCTAssertEqual(app.body, "**Synthetic body**"); XCTAssertEqual(app.invitation?.room.name, "Synthetic room")
        for (id, expected) in [("safeID123", "/my/drive/file/safeID123"), ("../settings", "/my/notifications"), ("x?i=secret", "/my/notifications")] {
            var record = base; record["type"] = "exportCompleted"; record["fileId"] = id
            XCTAssertEqual(try JSONDecoder().decode(ClientNotification.self, from: JSONSerialization.data(withJSONObject: record)).detailWebPath, expected)
        }
    }
}
