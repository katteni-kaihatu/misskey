// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UIKit

/// The Web's plain user-name mode: literal text and emoji, without links,
/// MFM formatting or a separate gesture that could intercept the profile tap.
struct NativeUserName: View {
    let name: String
    let host: String?
    let emojis: [String: String]
    let origin: ServerOrigin
    var style: UIFont.TextStyle = .subheadline
    var bold = true
    var secondary = false
    @ObservedObject private var catalog: NativeEmojiCatalog
    init(user: ClientUser, session: NativeClientSession, style: UIFont.TextStyle = .subheadline, bold: Bool = true, secondary: Bool = false) {
        self.init(name: user.displayName, host: user.host, emojis: user.emojis ?? [:], session: session, style: style, bold: bold, secondary: secondary)
    }
    init(name: String, host: String?, emojis: [String: String], session: NativeClientSession, style: UIFont.TextStyle = .subheadline, bold: Bool = true, secondary: Bool = false) {
        self.name = name; self.host = host; self.emojis = emojis; origin = session.origin
        self.style = style; self.bold = bold; self.secondary = secondary; catalog = session.emojiCatalog
    }
    var body: some View {
        NativeUserNameLabel(name: name, origin: origin, host: host, emojis: emojis,
            local: host == nil ? catalog.items : [], style: style, bold: bold, secondary: secondary)
            .accessibilityLabel(name).accessibilityIdentifier("native-user-name")
    }
}

@MainActor
enum NativeUserNameRenderer {
    static func render(_ name: String, origin: ServerOrigin, host: String?, emojis: [String: String], local: [ClientCustomEmoji], font: UIFont, color: UIColor,
                       loaded: [URL: Data] = [:]) -> (text: NSAttributedString, urls: [URL]) {
        let plain = name.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        let output = NSMutableAttributedString(string: plain, attributes: [.font: font, .foregroundColor: color])
        let regex = try! NSRegularExpression(pattern: ":[A-Za-z0-9_+\\-]+:")
        let matches = Array(regex.matches(in: plain, range: NSRange(location: 0, length: (plain as NSString).length)).prefix(32))
        var urls: [URL] = []
        for match in matches.reversed() {
            let code = (plain as NSString).substring(with: match.range), key = String(code.dropFirst().dropLast())
            let url = host == nil ? local.first(where: { $0.name == key }).flatMap { clientImageURL($0.url) }
                ?? MFMLinks.emoji(origin: origin, name: key, authorHost: host, urls: emojis)
                : MFMLinks.emoji(origin: origin, name: key, authorHost: host, urls: emojis)
            guard let url else { continue }
            if !urls.contains(url) { urls.append(url) }
            let attachment: NSTextAttachment
            if let data = loaded[url] ?? NativeEmojiMemory.shared.data(url), let poster = NativeEmojiFrames(data)?.image(at: 0) {
                attachment = NativeEmojiAttachment(data: data, poster: poster)
            } else { attachment = NSTextAttachment(); attachment.image = UIImage(systemName: "face.smiling") }
            attachment.bounds = CGRect(x: 0, y: font.descender, width: font.lineHeight, height: font.lineHeight)
            let replacement = NSMutableAttributedString(attachment: attachment)
            replacement.addAttributes([.font: font, .foregroundColor: color, NativeMFMRenderer.emojiAltKey: code], range: NSRange(location: 0, length: replacement.length))
            output.replaceCharacters(in: match.range, with: replacement)
        }
        return (output, urls)
    }
}

private struct NativeUserNameLabel: UIViewRepresentable {
    let name: String
    let origin: ServerOrigin
    let host: String?
    let emojis: [String: String]
    let local: [ClientCustomEmoji]
    let style: UIFont.TextStyle
    let bold: Bool
    let secondary: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    private var font: UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        return bold ? UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: base.pointSize) : base
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> NativeMFMTextView {
        let view = NativeMFMTextView()
        view.isEditable = false; view.isSelectable = false; view.isScrollEnabled = false; view.isUserInteractionEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.textContainer.maximumNumberOfLines = 1; view.textContainer.lineBreakMode = .byTruncatingTail
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "native-user-name"
        return view
    }
    func updateUIView(_ view: NativeMFMTextView, context: Context) {
        view.accessibilityLabel = name
        let input = Coordinator.Input(name: name, host: host, emojis: emojis, local: local.filter { name.contains($0.shortcode) }, size: font.pointSize, style: style.rawValue, bold: bold, secondary: secondary, dark: colorScheme == .dark)
        guard context.coordinator.input != input else { return }
        context.coordinator.task?.cancel(); context.coordinator.input = input
        let rendered = NativeUserNameRenderer.render(name, origin: origin, host: host, emojis: emojis, local: local, font: font, color: secondary ? .secondaryLabel : .label)
        let generation = UUID(); context.coordinator.generation = generation
        view.attributedText = rendered.text
        guard !rendered.urls.isEmpty else { return }
        let coordinator = context.coordinator
        coordinator.task = Task { @MainActor [weak view, weak coordinator] in
            var loaded: [URL: Data] = [:]
            for url in rendered.urls {
                guard !Task.isCancelled else { return }
                if let data = try? await NativeAssetCache.shared.data(for: url), NativeEmojiFrames(data) != nil {
                    NativeEmojiMemory.shared.store(data, url: url); loaded[url] = data
                }
            }
            guard !Task.isCancelled, let view, coordinator?.generation == generation else { return }
            view.attributedText = NativeUserNameRenderer.render(name, origin: origin, host: host, emojis: emojis, local: local, font: font, color: secondary ? .secondaryLabel : .label, loaded: loaded).text
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeMFMTextView, context: Context) -> CGSize? {
        let ideal = (uiView.attributedText ?? NSAttributedString()).boundingRect(with: CGSize(width: 100_000, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return CGSize(width: min(proposal.width ?? ceil(ideal.width), ceil(ideal.width)), height: ceil(font.lineHeight * 1.15))
    }
    static func dismantleUIView(_ view: NativeMFMTextView, coordinator: Coordinator) { coordinator.task?.cancel(); coordinator.generation = UUID(); view.attributedText = nil }
    @MainActor final class Coordinator {
        struct Input: Equatable {
            let name: String; let host: String?; let emojis: [String: String]; let local: [ClientCustomEmoji]
            let size: CGFloat; let style: String; let bold: Bool; let secondary: Bool; let dark: Bool
        }
        var input: Input?
        var task: Task<Void, Never>?
        var generation = UUID()
        deinit { task?.cancel() }
    }
}
