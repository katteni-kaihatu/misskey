// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Negotiation and public session invalidation. There is no token, account-data
/// read, API relay, JavaScript execution or media-read command.
public enum BridgeHandshake {
    public static let version = 1
    public static let maximumMessageBytes = 4096

    public enum ValidationError: Error { case invalidMessage }
    public enum Status: String, Codable, Sendable {
        case success, cancelled, refused, expired, resultUnknown
    }

    public struct Request: Decodable, Sendable {
        public let protocolVersion: Int
        public let requestId: UUID
        public let accountEpoch: UUID?
        public let operation: String
        public let payload: Payload
    }

    public struct Payload: Decodable, Sendable {
        public let schemaVersion: Int?
        public let webVersion: String?
        public let host: String?
        public let userId: String?
        public let reason: SessionChangeReason?
    }

    public enum SessionChangeReason: String, Decodable, Sendable {
        case boot, logout, revoked, storage
        case switchAccount = "switch"
    }

    public struct Reply: Encodable, Sendable {
        public let protocolVersion = version
        public let requestId: UUID
        public let accountEpoch: UUID
        public let operation: String
        public let status: Status
        public let payload: Capabilities
    }

    public struct Capabilities: Encodable, Sendable {
        public let schemaVersion = version
        public let operations = ["capabilities", "ready", "session.changed"]
        public let nativeFileInput: Bool
        // Negotiation is not proof of authentication. Authenticated operations
        // remain unavailable until Web session invalidation is integrated.
        public let authenticatedOperations = false
    }

    public static func decode(_ data: Data) throws -> Request {
        guard data.count <= maximumMessageBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["protocolVersion", "requestId", "accountEpoch", "operation", "payload"]),
              let payload = object["payload"] as? [String: Any] else { throw ValidationError.invalidMessage }
        let request = try JSONDecoder().decode(Request.self, from: data)
        switch request.operation {
        case "capabilities":
            guard payload.isEmpty else { throw ValidationError.invalidMessage }
        case "ready":
            guard Set(payload.keys) == Set(["schemaVersion", "webVersion"]),
                  let webVersion = request.payload.webVersion, !webVersion.isEmpty,
                  webVersion.utf8.count <= 128 else { throw ValidationError.invalidMessage }
        case "session.changed":
            guard Set(payload.keys) == Set(["host", "userId", "reason"]),
                  let host = request.payload.host, !host.isEmpty, host.utf8.count <= 300,
                  request.payload.reason != nil else { throw ValidationError.invalidMessage }
            if let userId = request.payload.userId {
                guard !userId.isEmpty, userId.utf8.count <= 128,
                      userId.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
                    throw ValidationError.invalidMessage
                }
            }
        default:
            throw ValidationError.invalidMessage
        }
        return request
    }

    public static func reply(to request: Request, epoch: UUID, nativeFileInput: Bool,
                             expectedHost: String? = nil, replacementEpoch: UUID? = nil) -> Reply {
        let status: Status
        if request.protocolVersion != version || (request.operation == "ready" && request.payload.schemaVersion != version) {
            status = .refused
        } else if request.operation != "capabilities" && request.accountEpoch != epoch {
            status = .expired
        } else if request.operation == "session.changed" && (expectedHost == nil || request.payload.host != expectedHost) {
            status = .refused
        } else {
            status = .success
        }
        let responseEpoch = status == .success && request.operation == "session.changed" ? (replacementEpoch ?? UUID()) : epoch
        return Reply(requestId: request.requestId, accountEpoch: responseEpoch, operation: request.operation, status: status,
                     payload: Capabilities(nativeFileInput: nativeFileInput))
    }
}
