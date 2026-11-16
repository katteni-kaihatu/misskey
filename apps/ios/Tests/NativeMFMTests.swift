// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import UIKit
import XCTest
@testable import GridSpace

@MainActor
final class NativeMFMTests: XCTestCase {
    private func render(_ text: String, host: String? = nil, revealed: Set<String> = []) async throws -> NativeMFMRenderResult {
        let nodes = try await MFMParser.shared.parse(text)
        return NativeMFMRenderer(origin: try ServerOrigin("https://synthetic.example"), authorHost: host,
                                 emojis: [:], fontSize: 17, revealed: revealed).render(nodes)
    }

    func testBlurNeverExposesItsTextOrEmojiURLBeforeExplicitReveal() async throws {
        let hidden = try await render("visible $[blur synthetic secret :emoji:]")
        XCTAssertEqual(hidden.text.string, "visible ［ぼかした内容を表示］")
        XCTAssertFalse(hidden.hasEmoji)
        let range = (hidden.text.string as NSString).range(of: "［ぼかした内容を表示］")
        let url = try XCTUnwrap(hidden.text.attribute(.link, at: range.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(url.scheme, "gridspace-mfm"); XCTAssertEqual(url.host, "reveal")
        let revealed = try await render("visible $[blur synthetic secret :emoji:]", revealed: [url.path])
        XCTAssertEqual(NativeMFMCopy.text(revealed.text), "visible synthetic secret :emoji:")
        XCTAssertTrue(revealed.hasEmoji)
    }

    func testFormattingCombinesNestedTraitsAndPreservesCodeWhitespace() async throws {
        let result = try await render("**bold <i>both</i>** ~~gone~~\n```swift\nlet x = 1  \n\nprint(x)\n```")
        XCTAssertFalse(result.text.string.contains("**"))
        let range = (result.text.string as NSString).range(of: "both")
        let font = try XCTUnwrap(result.text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains([.traitBold, .traitItalic]))
        XCTAssertTrue(result.text.string.contains("let x = 1  \n\nprint(x)"))
        let strike = (result.text.string as NSString).range(of: "gone")
        XCTAssertEqual(result.text.attribute(.strikethroughStyle, at: strike.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
    }

    func testMathKeepsLiteralFormulaAndAnimationsKeepTheirTextWithoutWebRouting() async throws {
        let result = try await render("\\(x^2\\) $[spin.left,speed=2s moving]")
        XCTAssertTrue(result.needsWeb)
        XCTAssertTrue(result.text.string.contains("x^2"))
        XCTAssertTrue(result.text.string.contains("moving"))
    }

    func testLinkRoutingUsesRemoteAuthorAndNeverInstallsAnExecutableURL() async throws {
        let result = try await render("@alice #タグ [site](https://example.test) [bad](javascript:alert(1))", host: "remote.example")
        var links: [URL] = []
        result.text.enumerateAttribute(.link, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in if let url = value as? URL { links.append(url) } }
        XCTAssertTrue(links.contains { $0.absoluteString == "https://synthetic.example/@alice@remote.example" })
        XCTAssertTrue(links.contains { $0.path == "/tags/タグ" })
        XCTAssertTrue(links.contains { $0.host == "example.test" })
        XCTAssertTrue(links.allSatisfy { $0.scheme == "https" })
    }

    func testUnknownRemoteEmojiRemainsItsNameAndPlainMarkupIsNotInterpreted() async throws {
        let result = try await render(":missing: <plain>**literal** :literal:</plain>", host: "remote.example")
        XCTAssertEqual(result.text.string, ":missing: **literal** :literal:")
        XCTAssertFalse(result.hasEmoji)
    }

    func testCopyOfAnImageAttachmentKeepsItsEmojiName() {
        let text = NSMutableAttributedString(string: "before ")
        let emoji = NSMutableAttributedString(attachment: NSTextAttachment())
        emoji.addAttribute(NativeMFMRenderer.emojiAltKey, value: ":synthetic:", range: NSRange(location: 0, length: emoji.length))
        text.append(emoji); text.append(NSAttributedString(string: " after"))
        XCTAssertEqual(NativeMFMCopy.text(text), "before :synthetic: after")
    }
    func testImageCompletionResizeReusesTheSameAttachmentsInsteadOfStartingAnotherLoad() async throws {
        let origin = try ServerOrigin("https://synthetic.example")
        let nodes = try await MFMParser.shared.parse("before :synthetic: after")
        let url = try XCTUnwrap(MFMLinks.emoji(origin: origin, name: "synthetic", authorHost: nil, urls: [:]))
        NativeEmojiMemory.shared.store(NativeComposerFixture.animatedGIF, url: url)
        let renderer = NativeMFMRenderer(origin: origin, authorHost: nil, emojis: [:], fontSize: 17, revealed: [])
        // This is the original feedback trigger: identical loaded emoji text
        // renders unequal because each render constructs a new attachment.
        XCTAssertFalse(renderer.render(nodes).text.isEqual(to: renderer.render(nodes).text))
        let cache = NativeMFMRenderCache(), generation = UUID()
        let initial = cache.value(nodes, renderer: renderer, generation: generation)
        let emojiRange = (NativeMFMCopy.text(initial.text) as NSString).range(of: ":synthetic:")
        XCTAssertTrue(initial.text.attribute(.attachment, at: emojiRange.location, effectiveRange: nil) is NativeEmojiAttachment)
        for _ in 0..<20 {
            let resized = cache.value(nodes, renderer: renderer, generation: generation)
            XCTAssertTrue(initial.text === resized.text)
            XCTAssertTrue(initial.text.isEqual(to: resized.text), "updateUIView must not start image loading again after resized()")
        }
        let differentGeneration = cache.value(nodes, renderer: renderer, generation: UUID())
        XCTAssertFalse(initial.text === differentGeneration.text)
        cache.clear()
        XCTAssertFalse(differentGeneration.text === cache.value(nodes, renderer: renderer, generation: generation).text)
    }
    func testRenderCacheInvalidatesWhenEmojiURLFontOrBlurDisclosureChanges() async throws {
        let origin = try ServerOrigin("https://synthetic.example"), cache = NativeMFMRenderCache(), generation = UUID()
        let nodes = try await MFMParser.shared.parse(":synthetic: $[blur hidden]")
        func renderer(_ url: String, size: CGFloat = 17, revealed: Set<String> = []) -> NativeMFMRenderer {
            NativeMFMRenderer(origin: origin, authorHost: nil, emojis: ["synthetic": url], fontSize: size, revealed: revealed)
        }
        let first = cache.value(nodes, renderer: renderer("https://synthetic.example/a.gif"), generation: generation)
        let changedURL = cache.value(nodes, renderer: renderer("https://synthetic.example/b.gif"), generation: generation)
        XCTAssertFalse(first.text === changedURL.text)
        let larger = cache.value(nodes, renderer: renderer("https://synthetic.example/b.gif", size: 24), generation: generation)
        XCTAssertFalse(changedURL.text === larger.text)
        var path: String?
        larger.text.enumerateAttribute(.link, in: NSRange(location: 0, length: larger.text.length)) { value, _, _ in
            if let url = value as? URL, url.host == "reveal" { path = url.path }
        }
        let revealed = cache.value(nodes, renderer: renderer("https://synthetic.example/b.gif", size: 24, revealed: [try XCTUnwrap(path)]), generation: generation)
        XCTAssertTrue(NativeMFMCopy.text(revealed.text).contains("hidden"))
        XCTAssertFalse(NativeMFMCopy.text(larger.text).contains("hidden"))
    }
}
