// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class NativeModelsTests: XCTestCase {
    private func note(_ id: String) throws -> ClientNote {
        try JSONDecoder().decode(ClientNote.self, from: Data("""
        {"id":"\(id)","createdAt":"2026-11-16T00:00:00.000Z","text":"synthetic","visibility":"followers",
         "user":{"id":"u","username":"synthetic","name":null,"host":null},
         "cw":"Synthetic CW","files":[],"renote":{"id":"original","createdAt":"2026-11-16T00:00:00Z","visibility":"public","user":{"id":"a","username":"author"},"text":"original"}}
        """.utf8))
    }

    func testDecodesPrivateVisibilityCWAndNestedRenoteWithoutDiscardingThem() throws {
        let result = try note("first")
        XCTAssertEqual(result.visibility, "followers")
        XCTAssertEqual(result.cw, "Synthetic CW")
        XCTAssertEqual(result.renote?.text, "original")
        XCTAssertEqual(result.user.displayName, "synthetic")
        XCTAssertEqual(result.user.handle, "@synthetic")
        XCTAssertNotNil(result.date)
        XCTAssertNotNil(result.renote?.date)
    }

    func testPaginationPreservesOrderAndDeduplicatesOverlappingPageBoundaries() throws {
        let first = try note("first"), second = try note("second"), third = try note("third")
        XCTAssertEqual(appendClientNotes([second, third, third], to: [first, second]).map(\.id), ["first", "second", "third"])
    }

    func testMiAuthUsesExactOriginAndOnlyOrdinaryPermissions() throws {
        let origin = try ServerOrigin("https://example.test:8443")
        let id = UUID()
        let url = MiAuthConfiguration.authorizationURL(origin: origin, session: id)
        XCTAssertTrue(origin.contains(url))
        XCTAssertEqual(url.path, "/miauth/" + id.uuidString.lowercased())
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(parameters.first { $0.name == "permission" }?.value, "read:account,write:notes,read:notifications,write:reactions,read:drive,write:drive,write:votes,write:following,write:notifications,read:gridspace-private")
        let callback = URL(string: parameters.first { $0.name == "callback" }!.value!)!
        XCTAssertTrue(MiAuthConfiguration.acceptsCallback(callback, session: id))
        for invalid in ["https://complete?state=\(id)", "gridspace-auth://elsewhere?state=\(id)",
                        "gridspace-auth://complete?state=\(UUID())", "gridspace-auth://complete?state=\(id)&state=\(id)",
                        "gridspace-auth://complete/path?state=\(id)", "gridspace-auth://complete?state=\(id)#fragment"] {
            XCTAssertFalse(MiAuthConfiguration.acceptsCallback(URL(string: invalid)!, session: id))
        }
    }

    func testWebEditingKeepsOriginEscapesTextAndDistinguishesMissingFromEmptyCW() throws {
        let origin = try ServerOrigin("https://synthetic.example:8443")
        let text = "synthetic own text &visibility=public#fragment"
        let plain = ClientWebEditor.url(origin: origin, text: text, cw: nil, visibility: "followers", replyId: "target")
        XCTAssertTrue(origin.contains(plain))
        let query = try XCTUnwrap(URLComponents(url: plain, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "text" }?.value, text)
        XCTAssertEqual(query.filter { $0.name == "visibility" }.map(\.value), ["followers"])
        XCTAssertEqual(query.first { $0.name == "replyId" }?.value, "target")
        XCTAssertFalse(query.contains { $0.name == "cw" })
        let emptyCW = ClientWebEditor.url(origin: origin, text: text, cw: "", visibility: "followers", replyId: nil)
        XCTAssertEqual(URLComponents(url: emptyCW, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cw" }?.value, "")
    }
}
