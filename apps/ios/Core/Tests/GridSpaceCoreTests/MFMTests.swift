// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import GridSpaceCore

final class MFMTests: XCTestCase {
    func testBundledJavaScriptCoreParserMatchesActualWebParserFixtures() async throws {
        #if !canImport(JavaScriptCore)
        throw XCTSkip("MFM rendering requires Apple's JavaScriptCore; URL and size checks remain portable")
        #endif
        struct Fixtures: Decodable {
            struct Example: Decodable { let text: String; let nodes: [MFMNode] }
            let mfmVersion: String
            let fixtures: [Example]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "MFMFixtures", withExtension: "json"))
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.mfmVersion, "0.28.0")
        for fixture in fixtures.fixtures {
            let nodes = try await MFMParser.shared.parse(fixture.text)
            XCTAssertEqual(nodes, fixture.nodes)
        }
    }

    func testInputIsDataAndContextsDoNotRetainAnEarlierNote() async throws {
        #if !canImport(JavaScriptCore)
        throw XCTSkip("MFM rendering requires Apple's JavaScriptCore")
        #endif
        let injection = "\"; throw new Error('executed'); // **synthetic**"
        let first = try await MFMParser.shared.parse(injection)
        XCTAssertEqual(first.last?.type, "bold")
        let second = try await MFMParser.shared.parse("next")
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.props?.text, "next")
    }

    func testOversizeFailsExplicitlyRatherThanTruncatingOrDisplayingHiddenSource() async throws {
        do { _ = try await MFMParser.shared.parse(String(repeating: "a", count: MFMParser.maximumUTF8Bytes + 1)); XCTFail("Expected a size limit") }
        catch { XCTAssertEqual(error as? MFMError, .tooLarge) }
    }

    func testMentionsInRemoteNotesUseTheAuthorsHostAndEncodePathData() throws {
        let origin = try ServerOrigin("https://synthetic.example:8443")
        let mention = MFMLinks.mention(origin: origin, username: "alice", host: nil, authorHost: "remote.example")
        XCTAssertEqual(mention.absoluteString, "https://synthetic.example:8443/@alice@remote.example")
        XCTAssertEqual(MFMLinks.mention(origin: origin, username: "bob", host: "explicit.example", authorHost: "remote.example").path, "/@bob@explicit.example")
        let tag = MFMLinks.hashtag(origin: origin, tag: "tag?#fragment")
        XCTAssertEqual(tag.path, "/tags/tag?#fragment")
        XCTAssertNil(tag.query); XCTAssertNil(tag.fragment)
        XCTAssertTrue(MFMLinks.hashtag(origin: origin, tag: "a/b").absoluteString.hasSuffix("/tags/a%2Fb"))
        let query = "a&visibility=public#x"
        XCTAssertEqual(URLComponents(url: MFMLinks.search(origin: origin, query: query), resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "q", value: query)])
    }

    func testLinksDenyExecutableSchemesCredentialsAndUnknownRemoteEmoji() throws {
        for url in ["javascript:alert(1)", "data:text/html,test", "file:///tmp/test", "https://user:secret@example.test", "gridspace-auth://complete"] {
            XCTAssertNil(MFMLinks.external(url))
        }
        XCTAssertEqual(MFMLinks.external("https://example.test/a?x=1#fragment")?.fragment, "fragment")
        let origin = try ServerOrigin("https://synthetic.example")
        XCTAssertNil(MFMLinks.emoji(origin: origin, name: "test", authorHost: "remote.example", urls: [:]))
        XCTAssertNil(MFMLinks.emoji(origin: origin, name: "../path", authorHost: nil, urls: [:]))
        XCTAssertEqual(MFMLinks.emoji(origin: origin, name: "test", authorHost: nil, urls: [:])?.path, "/emoji/test.webp")
        XCTAssertEqual(MFMLinks.emoji(origin: origin, name: "test", authorHost: nil, urls: ["test@.": "https://cdn.example/animated.gif"])?.path, "/animated.gif")
        XCTAssertNil(MFMLinks.emoji(origin: origin, name: "test", authorHost: "remote.example", urls: ["test@.": "https://cdn.example/animated.gif"]))
        XCTAssertEqual(MFMLinks.emoji(origin: origin, name: "test", authorHost: "remote.example", urls: ["test": "https://cdn.example/emoji.webp"])?.host, "cdn.example")
    }
}
