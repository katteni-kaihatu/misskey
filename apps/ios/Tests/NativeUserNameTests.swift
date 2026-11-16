// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import XCTest
@testable import GridSpace

@MainActor
final class NativeUserNameTests: XCTestCase {
    private let origin = try! ServerOrigin("https://name.ios.test")
    func testNameRendersAnimatedCustomAndStandardEmojiWhileLeavingMarkupLiteral() throws {
        let url = URL(string: "https://name.ios.test/owned.gif")!, name = "**Alice** :wave: 🌸"
        let result = NativeUserNameRenderer.render(name, origin: origin, host: nil, emojis: ["wave": url.absoluteString], local: [], font: .boldSystemFont(ofSize: 17), color: .label, loaded: [url: NativeComposerFixture.animatedGIF])
        XCTAssertEqual(NativeMFMCopy.text(result.text), name)
        XCTAssertEqual(result.urls, [url]); XCTAssertTrue(result.text.string.contains("**Alice**")); XCTAssertTrue(result.text.string.contains("🌸"))
        var attachment: NativeEmojiAttachment?
        result.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in if let value = value as? NativeEmojiAttachment { attachment = value } }
        XCTAssertEqual(attachment?.emojiData, NativeComposerFixture.animatedGIF)
        let view = NativeMFMTextView(); view.frame = CGRect(x: 0, y: 0, width: 300, height: 30)
        view.attributedText = result.text; view.layoutSubviews()
        XCTAssertTrue(view.subviews.compactMap { $0 as? NativeEmojiImageView }.contains { ($0.frames?.frameCount ?? 0) == 2 })
    }
    func testRemoteNameUsesItsOwnEmojiMapAndNeverSubstitutesALocalEmojiOfTheSameName() throws {
        let remote = "https://peer.ios.test/wave.gif"
        let local = try emoji("https://name.ios.test/local.gif")
        let result = NativeUserNameRenderer.render("Remote :wave:", origin: origin, host: "peer.ios.test", emojis: ["wave": remote], local: [local], font: .systemFont(ofSize: 17), color: .label)
        XCTAssertEqual(result.urls.map(\.absoluteString), [remote])
        let unknown = NativeUserNameRenderer.render("Remote :wave:", origin: origin, host: "peer.ios.test", emojis: [:], local: [local], font: .systemFont(ofSize: 17), color: .label)
        XCTAssertEqual(unknown.text.string, "Remote :wave:"); XCTAssertTrue(unknown.urls.isEmpty)
    }
    func testUpdatedLocalCatalogOverridesStaleUserMetadataWithoutChangingAttachmentBounds() throws {
        let url = URL(string: "https://name.ios.test/updated.gif")!, font = UIFont.systemFont(ofSize: 23)
        let plain = NativeUserNameRenderer.render("Alice :wave:", origin: origin, host: nil, emojis: ["wave": "https://name.ios.test/old.gif"], local: [try emoji(url.absoluteString)], font: font, color: .label)
        let loaded = NativeUserNameRenderer.render("Alice :wave:", origin: origin, host: nil, emojis: [:], local: [try emoji(url.absoluteString)], font: font, color: .label, loaded: [url: NativeComposerFixture.animatedWebP])
        XCTAssertEqual(plain.urls, [url]); XCTAssertEqual(loaded.urls, [url])
        func bounds(_ value: NSAttributedString) -> CGRect? {
            var result: CGRect?
            value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { value, _, _ in if let attachment = value as? NSTextAttachment { result = attachment.bounds } }
            return result
        }
        XCTAssertEqual(bounds(plain.text), bounds(loaded.text)); XCTAssertEqual(bounds(plain.text)?.height, font.lineHeight)
    }
    func testPeerAuthorEmojiMetadataDecodesAndIsUsableWithoutALocalUserID() throws {
        let author = try JSONDecoder().decode(ClientPeerChannelNote.Author.self, from: Data(#"{"name":"Peer :wave:","username":"peer","host":"peer.ios.test","emojis":{"wave":"https://peer.ios.test/wave.gif"}}"#.utf8))
        let result = NativeUserNameRenderer.render(try XCTUnwrap(author.name), origin: origin, host: author.host, emojis: author.emojis ?? [:], local: [], font: .systemFont(ofSize: 17), color: .label)
        XCTAssertEqual(result.urls.first?.host, "peer.ios.test")
    }
    private func emoji(_ url: String) throws -> ClientCustomEmoji {
        try JSONDecoder().decode(ClientCustomEmoji.self, from: JSONSerialization.data(withJSONObject: ["name": "wave", "aliases": [], "url": url]))
    }
}
