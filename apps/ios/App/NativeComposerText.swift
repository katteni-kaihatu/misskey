// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import UIKit

/// UITextView keeps UTF-16 selection, marked text and native undo intact when
/// the emoji sheet replaces the keyboard. No app-wide first-responder lookup.
@MainActor
final class NativeComposerTextState: ObservableObject {
    weak var view: UITextView?
    private var selected = NSRange(location: 0, length: 0)
    private var lastText: String?
    private var presentedText: String?
    func remember(_ view: UITextView) {
        guard view.markedTextRange == nil else { return }
        selected = view.selectedRange; lastText = view.text
    }
    @discardableResult func prepareEmoji(expectedText: String? = nil) -> Bool {
        if let view {
            guard view.markedTextRange == nil else { return false }
            remember(view); view.resignFirstResponder()
        }
        guard let text = expectedText ?? lastText, text == lastText else { return false }
        presentedText = text
        return true
    }
    func selection(for text: String) -> NSRange? { lastText == text ? selected : nil }
    func insert(_ emoji: String, expectedText: String) -> String? {
        guard presentedText == expectedText,
              selected.location <= (expectedText as NSString).length,
              selected.length <= (expectedText as NSString).length - selected.location else { return nil }
        let cursor = selected.location + (emoji as NSString).length
        let replacement = (expectedText as NSString).replacingCharacters(in: selected, with: emoji)
        if let view {
            guard view.markedTextRange == nil, view.text == expectedText,
                  let start = view.position(from: view.beginningOfDocument, offset: selected.location),
                  let end = view.position(from: start, offset: selected.length), let range = view.textRange(from: start, to: end) else { return nil }
            view.selectedTextRange = range; view.replace(range, withText: emoji)
            view.delegate?.textViewDidChange?(view)
        }
        selected = NSRange(location: cursor, length: 0)
        lastText = replacement; presentedText = nil
        return replacement
    }
    func clear() { presentedText = nil; lastText = nil; selected = NSRange(location: 0, length: 0) }

}

struct NativeComposerText: UIViewRepresentable {
    @Binding var text: String
    let state: NativeComposerTextState
    var minimumHeight: CGFloat = 150
    func makeUIView(context: Context) -> UITextView {
        let view = ComposerInputView()
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 20)); view.adjustsFontForContentSizeCategory = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear; view.delegate = context.coordinator
        view.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.accessibilityIdentifier = "native-compose-text"; view.accessibilityLabel = "投稿本文"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        state.view = view
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self; state.view = view
        if view.text != text, view.markedTextRange == nil {
            let old = state.selection(for: text) ?? view.selectedRange
            view.text = text
            let location = min(old.location, (text as NSString).length)
            view.selectedRange = NSRange(location: location, length: min(old.length, (text as NSString).length - location))
        }
        state.remember(view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minimumHeight, size.height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) { view.resignFirstResponder(); view.delegate = nil; view.text = nil; if coordinator.parent.state.view === view { coordinator.parent.state.view = nil } }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeComposerText
        init(_ parent: NativeComposerText) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) { parent.state.remember(view); parent.text = view.text }
        func textViewDidChangeSelection(_ view: UITextView) { parent.state.remember(view) }
    }
}

private final class ComposerInputView: UITextView {
    private var requestedFocus = false
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !requestedFocus else { return }
        requestedFocus = true
        becomeFirstResponder()
    }
}
