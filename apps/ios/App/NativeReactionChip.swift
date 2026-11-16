// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

@MainActor
final class NativeReactionUsersModel: ObservableObject {
    @Published private(set) var users: [ClientUser] = []
    private(set) var context: String?
    private var lease = UUID()
    func clear() { lease = UUID(); users = []; context = nil }
    func load(note: String, reaction: String, extended: Bool, api: any NativeEmojiAPI, context: String = "", accepts: () -> Bool) async {
        if self.context != context { clear(); self.context = context }
        let token = UUID(); lease = token
        guard accepts(), !Task.isCancelled else { clear(); return }
        do {
            let result = try await api.reactionUsers(note: note, reaction: reaction, extended: extended)
            guard token == lease, accepts(), !Task.isCancelled else { return }
            var ids = Set<String>()
            users = Array(result.filter { ids.insert($0.id).inserted }.prefix(10))
        } catch { if token == lease { users = [] } }
    }
    /// Reflect the optimistic owner immediately, even while the actor page is
    /// still the old server state. Never duplicate the same account's avatar.
    func previews(owner: ClientUser?, selected: Bool) -> [ClientUser] {
        guard let owner else { return users }
        var result = users.filter { $0.id != owner.id }
        if selected { result.insert(owner, at: 0) }
        return Array(result.prefix(10))
    }
}

struct NativeReactionChip<Icon: View>: View {
    let note: ClientNote
    let value: String
    let count: Int
    let version: Int
    @ObservedObject var session: NativeClientSession
    let disabled: Bool
    let toggle: () -> Void
    @ViewBuilder let icon: () -> Icon
    @StateObject private var reactors = NativeReactionUsersModel()
    private var selected: Bool { note.hasOwnReaction(value) }
    private var context: String { session.revision.uuidString + ":" + note.id }
    private var users: [ClientUser] {
        guard session.active else { return [] }
        if reactors.context != context { return selected ? session.user.map { [$0] } ?? [] : [] }
        return reactors.previews(owner: session.user, selected: selected)
    }
    private var requestKey: String { [session.revision.uuidString, note.id, value, String(count), note.reactionVersions?[value] ?? "", String(version)].joined(separator: "|") }
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                icon()
                HStack(spacing: 2) {
                    ForEach(users) { user in ClientAvatar(url: user.avatarUrl, size: 14) }
                }
            }.padding(.horizontal, 6).frame(height: 42)
                .background(selected ? ClientStyle.accent.opacity(0.13) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? ClientStyle.accent : .clear))
        }.buttonStyle(.borderless).disabled(disabled)
            .accessibilityLabel(value + "、" + String(count) + "件")
            .accessibilityValue(users.map(\.handle).joined(separator: "、"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("native-reaction:" + note.id + ":" + value)
            .task(id: requestKey) {
                let generation = session.revision
                await reactors.load(note: note.id, reaction: value, extended: note.supportsExtendedReactions,
                    api: session.api, context: context, accepts: { session.accepts(generation) })
            }
            .onChange(of: session.active) { active in if !active { reactors.clear() } }
            .onDisappear { reactors.clear() }
    }
}

/// Keep each emoji and its (up to ten) 14 pt avatars together, as on the Web.
/// Fixed-width grid cells would clip actor previews or leave large empty gaps.
struct NativeReactionFlow: Layout {
    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        var frames: [CGRect] = []
        for view in subviews {
            var size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            size.width = min(width, size.width)
            if x > 0 && x + size.width > width { x = 0; y += height + 5; height = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + 5; height = max(height, size.height)
        }
        return (CGSize(width: width, height: y + height), frames)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: max(1, proposal.width ?? 300)).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(subviews, width: max(1, bounds.width)).1
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
}
