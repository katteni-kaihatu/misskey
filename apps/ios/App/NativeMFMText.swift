// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UIKit
import ImageIO

/// No WebView per note. Only the trusted MFM parser runs JavaScript; all visible
/// text, selection, links and animated emoji are native UIKit content.
struct NativeMFMText: View {
    let text: String
    let origin: ServerOrigin
    let authorHost: String?
    let emojis: [String: String]
    let openLink: (URL) -> Void
    @State private var nodes: [MFMNode]?
    @State private var nodeKey: String?
    @Environment(\.nativeVisualMemory) private var visuals
    @Environment(\.nativeVisualGeneration) private var generation
    @State private var failed = false
    @State private var revealed = Set<String>()
    @State private var layoutRevision = 0
    @StateObject private var rendering = NativeMFMRenderCache()
    @ScaledMetric(relativeTo: .body) private var fontSize = 17
    private var key: String { generation.uuidString + text }
    private var parsed: [MFMNode]? { (nodeKey == key ? nodes : nil) ?? visuals?.nodes(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nodes = parsed {
                if nodes.allSatisfy({ ["text", "unicodeEmoji"].contains($0.type) }) {
                    Text(verbatim: text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let renderer = NativeMFMRenderer(origin: origin, authorHost: authorHost, emojis: emojis,
                                                     fontSize: fontSize, revealed: nodeKey == key ? revealed : [])
                    let rendered = rendering.value(nodes, renderer: renderer, generation: generation)
                    NativeMFMLabel(rendered: rendered, layoutRevision: layoutRevision, open: follow,
                                   resized: { layoutRevision &+= 1 })
                    if rendered.needsWeb {
                        Text("一部の装飾は静止した文字として表示しています").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else if failed {
                if text.contains("$[blur") { Text("本文を表示できません").foregroundStyle(.secondary) }
                else { Text(verbatim: text).textSelection(.enabled) }
            } else {
                if text.contains("$[blur") { Text(" ").frame(maxWidth: .infinity, alignment: .leading) }
                else { Text(verbatim: text).textSelection(.enabled) }
            }
        }
        .contextMenu { Button("本文の原文をコピー") { UIPasteboard.general.string = text } }
        .task(id: key) {
            let token = visuals?.generation, activeKey = key
            if nodeKey != activeKey { revealed = [] }
            if let cached = visuals?.nodes(text) { nodes = cached; nodeKey = key; return }
            failed = false
            do {
                let parsed = try await MFMParser.shared.parse(text)
                guard !Task.isCancelled, visuals?.generation == token else { return }
                nodes = parsed
                nodeKey = activeKey; visuals?.store(parsed, text: text)
            } catch { if !Task.isCancelled { failed = true } }
        }
        .onDisappear { nodes = nil; rendering.clear() } // Parsed nodes return synchronously from the session cache.
    }

    private func follow(_ url: URL) {
        if url.scheme == "gridspace-mfm" {
            if url.host == "reveal" { revealed.insert(url.path) }
        } else if MFMLinks.external(url.absoluteString) != nil { openLink(url) }
    }
}

struct NativeMFMRenderResult {
    let text: NSAttributedString
    let needsWeb: Bool
    let hasEmoji: Bool
}

/// Retain one immutable rendering for this mounted text body. Image completion
/// requests another size pass, but must not create fresh attachment identities:
/// that makes updateUIView reload images and request yet another size pass.
@MainActor
final class NativeMFMRenderCache: ObservableObject {
    private struct Input: Equatable {
        let nodes: [MFMNode]
        let origin: ServerOrigin
        let authorHost: String?
        let emojis: [String: String]
        let fontSize: CGFloat
        let revealed: Set<String>
        let generation: UUID
    }
    private var input: Input?
    private var rendered: NativeMFMRenderResult?
    func value(_ nodes: [MFMNode], renderer: NativeMFMRenderer, generation: UUID) -> NativeMFMRenderResult {
        let next = Input(nodes: nodes, origin: renderer.origin, authorHost: renderer.authorHost, emojis: renderer.emojis,
                         fontSize: renderer.fontSize, revealed: renderer.revealed, generation: generation)
        if input == next, let rendered { return rendered }
        let result = renderer.render(nodes)
        input = next; rendered = result
        return result
    }
    func clear() { input = nil; rendered = nil }
}

@MainActor
struct NativeMFMRenderer {
    static let emojiKey = NSAttributedString.Key("GridSpaceMFMEmoji")
    static let emojiAltKey = NSAttributedString.Key("GridSpaceMFMEmojiAlt")
    let origin: ServerOrigin
    let authorHost: String?
    let emojis: [String: String]
    let fontSize: CGFloat
    let revealed: Set<String>

    func render(_ nodes: [MFMNode]) -> NativeMFMRenderResult {
        let output = NSMutableAttributedString(string: "")
        var needsWeb = false
        var hasEmoji = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        let base: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.label, .paragraphStyle: paragraph]

        func append(_ value: String, _ attributes: [NSAttributedString.Key: Any]) { output.append(NSAttributedString(string: value, attributes: attributes)) }
        func font(_ attributes: [NSAttributedString.Key: Any]) -> UIFont { attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: fontSize) }
        func linked(_ attributes: [NSAttributedString.Key: Any], _ url: URL?) -> [NSAttributedString.Key: Any] {
            var result = attributes
            if let url { result[.link] = url; result[.foregroundColor] = UIColor.link }
            return result
        }
        func color(_ input: String?) -> UIColor? {
            let candidate = input ?? "f00"
            let value = (3...6).contains(candidate.count) && candidate.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) ? candidate : "f00"
            // The Web renderer admits 3–6 hex digits; CSS ignores five digits.
            guard value.count != 5 else { return nil }
            let expanded = value.count <= 4 ? value.map { "\($0)\($0)" }.joined() : value
            guard let number = UInt64(expanded, radix: 16) else { return .red }
            let alpha = expanded.count == 8 ? CGFloat(number & 255) / 255 : 1
            let rgb = expanded.count == 8 ? number >> 8 : number
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
        }
        func walk(_ children: [MFMNode], _ attributes: [NSAttributedString.Key: Any], _ parent: String) {
            for (index, node) in children.enumerated() {
                let path = parent + "/" + String(index)
                let props = node.props
                var style = attributes
                var descend = true
                switch node.type {
                case "text": append((props?.text ?? "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"), style); descend = false
                case "unicodeEmoji": append(props?.emoji ?? "", style); descend = false
                case "bold", "italic":
                    let current = font(style)
                    let traits: UIFontDescriptor.SymbolicTraits = node.type == "bold" ? .traitBold : .traitItalic
                    if let descriptor = current.fontDescriptor.withSymbolicTraits(current.fontDescriptor.symbolicTraits.union(traits)) {
                        style[.font] = UIFont(descriptor: descriptor, size: current.pointSize)
                    }
                case "strike": style[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case "small": style[.font] = font(style).withSize(font(style).pointSize * 0.8); style[.foregroundColor] = UIColor.secondaryLabel
                case "plain": break
                case "inlineCode", "blockCode":
                    style[.font] = UIFont.monospacedSystemFont(ofSize: font(style).pointSize * 0.9, weight: .regular)
                    style[.backgroundColor] = UIColor.secondarySystemBackground
                    if node.type == "blockCode", output.length > 0, !output.string.hasSuffix("\n") { append("\n", attributes) }
                    append(props?.code ?? "", style)
                    if node.type == "blockCode" { append("\n", attributes) }
                    descend = false
                case "quote", "center":
                    if output.length > 0, !output.string.hasSuffix("\n") { append("\n", attributes) }
                    let paragraph = (style[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    if node.type == "center" { paragraph.alignment = .center }
                    else { paragraph.headIndent += 14; paragraph.firstLineHeadIndent = paragraph.headIndent; style[.foregroundColor] = UIColor.secondaryLabel }
                    style[.paragraphStyle] = paragraph
                    walk(node.children ?? [], style, path)
                    append("\n", style); descend = false
                case "url", "link":
                    style = linked(style, props?.url.flatMap(MFMLinks.external))
                    if node.type == "url" { append(props?.url ?? "", style); descend = false }
                case "mention":
                    let name = props?.username ?? ""
                    append("@" + name + ((props?.host ?? authorHost).map { "@" + $0 } ?? ""), linked(style, MFMLinks.mention(origin: origin, username: name, host: props?.host, authorHost: authorHost)))
                    descend = false
                case "hashtag":
                    let tag = props?.hashtag ?? ""
                    append("#" + tag, linked(style, MFMLinks.hashtag(origin: origin, tag: tag))); descend = false
                case "search":
                    append(props?.content ?? props?.query ?? "", linked(style, MFMLinks.search(origin: origin, query: props?.query ?? ""))); descend = false
                case "emojiCode":
                    let name = props?.name ?? ""
                    if let url = MFMLinks.emoji(origin: origin, name: name, authorHost: authorHost, urls: emojis) {
                        style[Self.emojiKey] = url; style[Self.emojiAltKey] = ":" + name + ":"; hasEmoji = true
                        let attachment: NSTextAttachment
                        if let data = NativeEmojiMemory.shared.data(url), let poster = NativeEmojiFrames(data)?.image(at: 0) {
                            attachment = NativeEmojiAttachment(data: data, poster: poster)
                        } else { attachment = NSTextAttachment(); attachment.image = UIImage(systemName: "face.smiling") }
                        let font = font(style), height = font.lineHeight * 1.2
                        attachment.bounds = CGRect(x: 0, y: font.descender, width: height, height: height)
                        let replacement = NSMutableAttributedString(attachment: attachment)
                        replacement.addAttributes(style, range: NSRange(location: 0, length: replacement.length))
                        output.append(replacement); descend = false; continue
                    }
                    append(":" + name + ":", style); descend = false
                case "mathInline", "mathBlock":
                    needsWeb = true
                    append(props?.formula ?? props?.code ?? "［数式］", style)
                    descend = false
                case "fn":
                    switch props?.name {
                    case "blur":
                        if !revealed.contains(path) {
                            append("［ぼかした内容を表示］", linked(style, URL(string: "gridspace-mfm://reveal" + path)))
                            descend = false
                        }
                    case "fg": if let color = color(props?.args?["color"]?.text) { style[.foregroundColor] = color }
                    case "bg": if let color = color(props?.args?["color"]?.text) { style[.backgroundColor] = color }
                    case "font":
                        let args = props?.args ?? [:]
                        if args["monospace"] != nil { style[.font] = UIFont.monospacedSystemFont(ofSize: font(style).pointSize, weight: .regular) }
                        else if args["serif"] != nil, let descriptor = font(style).fontDescriptor.withDesign(.serif) { style[.font] = UIFont(descriptor: descriptor, size: font(style).pointSize) }
                        else { needsWeb = true }
                    case "x2", "x3", "x4":
                        // Preserve layout bounds; the original Web transform remains available.
                        needsWeb = true
                        let factor: CGFloat = props?.name == "x2" ? 1.5 : props?.name == "x3" ? 1.8 : 2
                        style[.font] = font(style).withSize(min(font(style).pointSize * factor, fontSize * 3))
                    default: needsWeb = true
                    }
                default: needsWeb = true; append("［未対応の装飾］", style); descend = false
                }
                if descend { walk(node.children ?? [], style, path) }
            }
        }
        walk(nodes, base, "")
        return NativeMFMRenderResult(text: output, needsWeb: needsWeb, hasEmoji: hasEmoji)
    }
}

private struct NativeMFMLabel: UIViewRepresentable {
    let rendered: NativeMFMRenderResult
    let layoutRevision: Int
    let open: (URL) -> Void
    let resized: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UITextView {
        let view = NativeMFMTextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []; view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.open = open
        guard context.coordinator.original?.isEqual(to: rendered.text) != true else { return }
        context.coordinator.task?.cancel()
        context.coordinator.original = rendered.text
        let generation = UUID(); context.coordinator.generation = generation
        view.attributedText = rendered.text
        // Keep a text alternative even after replacing emoji names with images.
        view.accessibilityLabel = NativeMFMCopy.text(rendered.text)
        let coordinator = context.coordinator
        coordinator.task = Task { @MainActor [weak view, weak coordinator] in
            var urls: [URL] = []
            rendered.text.enumerateAttribute(NativeMFMRenderer.emojiKey, in: NSRange(location: 0, length: rendered.text.length)) { value, _, _ in
                if let url = value as? URL, !urls.contains(url), urls.count < 16 { urls.append(url) }
            }
            for url in urls {
                guard !Task.isCancelled, let view, let coordinator, coordinator.generation == generation else { return }
                guard let data = try? await NativeAssetCache.shared.data(for: url), !Task.isCancelled,
                      let frames = NativeEmojiFrames(data), let image = frames.image(at: 0), coordinator.generation == generation else { continue }
                NativeEmojiMemory.shared.store(data, url: url)
                let updated = NSMutableAttributedString(attributedString: view.attributedText)
                var ranges: [NSRange] = []
                updated.enumerateAttribute(NativeMFMRenderer.emojiKey, in: NSRange(location: 0, length: updated.length)) { value, range, _ in
                    if (value as? URL) == url { ranges.append(range) }
                }
                for range in ranges.reversed() {
                    let attributes = updated.attributes(at: range.location, effectiveRange: nil)
                    let font = attributes[.font] as? UIFont ?? .preferredFont(forTextStyle: .body)
                    let height = font.lineHeight * 1.2
                    let attachment = NativeEmojiAttachment(data: data, poster: image)
                    attachment.bounds = CGRect(x: 0, y: font.descender, width: height, height: height)
                    let replacement = NSMutableAttributedString(attachment: attachment)
                    replacement.addAttributes(attributes.filter { $0.key != NativeMFMRenderer.emojiKey }, range: NSRange(location: 0, length: replacement.length))
                    updated.replaceCharacters(in: range, with: replacement)
                }
                view.attributedText = updated; view.invalidateIntrinsicContentSize(); resized()
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.task?.cancel(); coordinator.task = nil; coordinator.original = nil; coordinator.open = nil
        coordinator.generation = UUID(); view.attributedText = nil; view.accessibilityLabel = nil; view.delegate = nil
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var original: NSAttributedString?
        var task: Task<Void, Never>?
        var generation = UUID()
        var open: ((URL) -> Void)?
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            // Long-press previews must not make an automatic external request.
            if interaction == .invokeDefaultAction { open?(URL) }
            return false
        }
        deinit { task?.cancel() }
    }
}

enum NativeMFMCopy {
    static func text(_ value: NSAttributedString) -> String {
        let copy = NSMutableAttributedString(attributedString: value)
        var replacements: [(NSRange, String)] = []
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attachment, range, _ in
            if attachment != nil, let name = value.attribute(NativeMFMRenderer.emojiAltKey, at: range.location, effectiveRange: nil) as? String { replacements.append((range, name)) }
        }
        for (range, name) in replacements.reversed() { copy.replaceCharacters(in: range, with: name) }
        return copy.string
    }
}

final class NativeMFMTextView: UITextView {
    private var emojiViews: [Int: NativeEmojiImageView] = [:]
    init() {
        // Use a single layout engine for glyph positions, selection and copy.
        let storage = NSTextStorage(), manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var attributedText: NSAttributedString! {
        didSet {
            if attributedText == nil || attributedText.length == 0 {
                for view in emojiViews.values { view.load(nil); view.removeFromSuperview() }
                emojiViews = [:]
            }
            setNeedsLayout()
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        var active = Set<Int>()
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard active.count < 64, let attachment = value as? NativeEmojiAttachment else { return }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyph < layoutManager.numberOfGlyphs else { return }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = layoutManager.location(forGlyphAt: glyph)
            let box = attachment.bounds
            let frame = CGRect(x: textContainerInset.left + line.minX + baseline.x + box.minX,
                               y: textContainerInset.top + line.minY + baseline.y - box.maxY,
                               width: box.width, height: box.height)
            guard frame.width > 0, frame.height > 0 else { return }
            active.insert(range.location)
            let player = emojiViews[range.location] ?? NativeEmojiImageView(frame: frame)
            player.frame = frame; player.load(attachment.emojiData)
            if player.superview == nil { addSubview(player) }
            emojiViews[range.location] = player
        }
        for key in Array(emojiViews.keys) where !active.contains(key) {
            emojiViews[key]?.load(nil); emojiViews[key]?.removeFromSuperview(); emojiViews[key] = nil
        }
    }

    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0, NSMaxRange(selectedRange) <= textStorage.length else { return }
        UIPasteboard.general.string = NativeMFMCopy.text(textStorage.attributedSubstring(from: selectedRange))
    }
}
