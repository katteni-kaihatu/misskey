// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class BridgeHandshakeTests: XCTestCase {
    private func message(operation: String = "capabilities", epoch: UUID? = nil,
                         version: Int = 1, payload: [String: Any] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": version, "requestId": UUID().uuidString,
            "accountEpoch": epoch.map { $0.uuidString as Any } ?? NSNull(),
            "operation": operation, "payload": payload,
        ])
    }

    func testNegotiationExposesNoAuthenticatedOperations() throws {
        let epoch = UUID()
        let request = try BridgeHandshake.decode(message())
        let reply = BridgeHandshake.reply(to: request, epoch: epoch, nativeFileInput: true)
        XCTAssertEqual(reply.status, .success)
        XCTAssertEqual(reply.requestId, request.requestId)
        XCTAssertEqual(reply.operation, "capabilities")
        XCTAssertEqual(reply.accountEpoch, epoch)
        XCTAssertFalse(reply.payload.authenticatedOperations)
        XCTAssertEqual(reply.payload.operations, ["capabilities", "ready", "session.changed"])
    }

    func testReadyRequiresCurrentEpochAndSupportedSchema() throws {
        let epoch = UUID()
        let payload: [String: Any] = ["schemaVersion": 1, "webVersion": "test"]
        let ready = try BridgeHandshake.decode(message(operation: "ready", epoch: epoch, payload: payload))
        XCTAssertEqual(BridgeHandshake.reply(to: ready, epoch: epoch, nativeFileInput: true).status, .success)
        XCTAssertEqual(BridgeHandshake.reply(to: ready, epoch: UUID(), nativeFileInput: true).status, .expired)
        let unsupported = try BridgeHandshake.decode(message(version: 2))
        XCTAssertEqual(BridgeHandshake.reply(to: unsupported, epoch: epoch, nativeFileInput: true).status, .refused)
        let schema = try BridgeHandshake.decode(message(operation: "ready", epoch: epoch, payload: ["schemaVersion": 2, "webVersion": "test"]))
        XCTAssertEqual(BridgeHandshake.reply(to: schema, epoch: epoch, nativeFileInput: true).status, .refused)
    }

    func testRejectsPrivilegedOperationsMalformedOrOversizedPayloads() throws {
        XCTAssertThrowsError(try BridgeHandshake.decode(message(operation: "api")))
        XCTAssertThrowsError(try BridgeHandshake.decode(message(operation: "media.read")))
        XCTAssertThrowsError(try BridgeHandshake.decode(message(payload: ["token": "synthetic"])))
        XCTAssertThrowsError(try BridgeHandshake.decode(message(operation: "ready", payload: ["webVersion": "test"])))
        XCTAssertThrowsError(try BridgeHandshake.decode(Data(repeating: 32, count: 4097)))
        XCTAssertThrowsError(try BridgeHandshake.decode(Data("{}".utf8)))
    }

    func testSessionChangeRotatesOnlyForCurrentEpochAndExactHost() throws {
        let epoch = UUID()
        let next = UUID()
        let request = try BridgeHandshake.decode(message(operation: "session.changed", epoch: epoch,
            payload: ["host": "example.com:8443", "userId": "synthetic-user_1", "reason": "switch"]))
        let reply = BridgeHandshake.reply(to: request, epoch: epoch, nativeFileInput: true,
            expectedHost: "example.com:8443", replacementEpoch: next)
        XCTAssertEqual(reply.status, .success)
        XCTAssertEqual(reply.accountEpoch, next)
        XCTAssertFalse(reply.payload.authenticatedOperations)
        XCTAssertEqual(BridgeHandshake.reply(to: request, epoch: epoch, nativeFileInput: true,
            expectedHost: "example.com", replacementEpoch: next).status, .refused)
        let expired = BridgeHandshake.reply(to: request, epoch: next, nativeFileInput: true,
            expectedHost: "example.com:8443", replacementEpoch: UUID())
        XCTAssertEqual(expired.status, .expired)
        XCTAssertEqual(expired.accountEpoch, next)
    }

    func testSessionChangeAllowsLogoutButRejectsCredentialsAndMalformedIdentity() throws {
        let epoch = UUID()
        let payload: [String: Any] = ["host": "example.com", "userId": NSNull(), "reason": "logout"]
        let request = try BridgeHandshake.decode(message(operation: "session.changed", epoch: epoch, payload: payload))
        XCTAssertNil(request.payload.userId)
        XCTAssertEqual(BridgeHandshake.reply(to: request, epoch: epoch, nativeFileInput: true).status, .refused)
        for invalid in [
            payload.merging(["token": "synthetic-secret"]) { _, value in value },
            payload.merging(["userId": "../other"]) { _, value in value },
            payload.merging(["userId": ""]) { _, value in value },
            payload.merging(["reason": "arbitrary"]) { _, value in value },
            payload.merging(["host": ""]) { _, value in value },
        ] {
            XCTAssertThrowsError(try BridgeHandshake.decode(message(operation: "session.changed", epoch: epoch, payload: invalid)))
        }
    }
}
