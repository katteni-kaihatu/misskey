// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest

/// Changes only synthetic fixture state through its private native control channel.
/// Real OAuth consent and grant APIs run on the paired fixture's servers.
enum PairedParityControl {
    struct State: Decodable, Sendable {
        let granted: Bool?
        let canPostChannel: Bool?
        let name: String?
        let session: String?
        let emojiNoteID: String?
        let emojiTag: String?
        let emojiReaction: String?
        let emojiReactionCount: Int?
        let emojiWrites: Int?
        let emojiComposedTexts: [String]?
        let notificationTag: String?
        let notificationFirstFollowerID: String?
        let notificationUnreadCount: Int?
        let notificationReadAttempts: Int?
        let notificationReadWrites: Int?
        let actionTag: String?
        let actionTargetID: String?
        let actionReshareIDs: [String]?
        let actionQuoteIDs: [String]?
        let actionTexts: [String?]?
        let actionVisibilities: [String]?
        let actionLocalOnly: [Bool]?
        let actionTargetExists: Bool?
        let nativeNoteCount: Int?
        let nativeNoteVisibility: String?
        let nativeNoteCW: String?
        let attachmentNoteCount: Int?
        let attachmentNames: [String]?
        let attachmentSensitive: [Bool]?
        let attachmentComments: [String?]?
        let attachmentDriveCount: Int?
        let attachmentHashes: [String]?
        let socialTag: String?
        let socialTargetID: String?
        let singleVotes: [Int]?
        let multipleVotes: [Int]?
        let expiredVotes: [Int]?
        let deviceReplies: Int?
        let profilePublicID: String?
        let profileLockedID: String?
        let profilePrivateID: String?
        let profileFirstFanID: String?
        let profileTag: String?
        let profileFollowing: Bool?
        let profilePending: Bool?
        let lockedFollowing: Bool?
        let lockedPending: Bool?
    }

    static func perform(_ action: String, environment: [String: String]) async throws -> State {
        #if DEBUG
        let fixture = try XCTUnwrap(LocalParityServer(arguments: ["--ui-testing", "--local-parity-server"], environment: environment))
        let request = try XCTUnwrap(fixture.controlRequest(action))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        fixture.configureControlSession(configuration)
        let session = URLSession(configuration: configuration, delegate: PinDelegate(fixture), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "The private fixture control must succeed without redirects")
        return try JSONDecoder().decode(State.self, from: data)
        #else
        throw XCTSkip("Paired fixture controls require a Debug build")
        #endif
    }

    #if DEBUG
    private final class PinDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
        let fixture: LocalParityServer
        init(_ fixture: LocalParityServer) { self.fixture = fixture }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard let credential = await fixture.evaluatedCredential(for: challenge.protectionSpace) else {
                return (.cancelAuthenticationChallenge, nil)
            }
            return (.useCredential, credential)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
            nil // Never forward fixture-control headers to another URL.
        }
    }
    #endif
}
