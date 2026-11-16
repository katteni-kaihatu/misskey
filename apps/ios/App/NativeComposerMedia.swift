// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UniformTypeIdentifiers

struct ComposerToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44)
            .background(configuration.isPressed ? ClientStyle.accent.opacity(0.1) : .clear, in: Circle())
    }
}

struct NativeAttachmentCard: View {
    let entry: NativeAttachmentDraft
    let index: Int
    let files: NativeAttachmentFiles
    @ObservedObject var session: NativeClientSession
    let editable: Bool
    let edit: () -> Void
    let remove: () -> Void
    let earlier: () -> Void
    let later: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                NativeAttachmentThumbnail(entry: entry, files: files, session: session)
                    .frame(width: 190, height: 190).clipped()
                    .blur(radius: entry.sensitive ? 16 : 0)
                    .overlay {
                        if entry.sensitive { Label("センシティブ", systemImage: "eye.slash").font(.caption.bold()).padding(8).background(.regularMaterial, in: Capsule()) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Button(action: remove) {
                    Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(.black.opacity(0.65), in: Circle())
                }.buttonStyle(.plain).padding(8).disabled(!editable)
                    .accessibilityLabel("添付\(index)を外す").accessibilityIdentifier("native-attachment-remove:" + entry.id.uuidString)
                VStack { Spacer(); HStack {
                    Text(String(index)).font(.caption.bold()).frame(width: 24, height: 24)
                        .foregroundStyle(.white).background(.black.opacity(0.65), in: Circle())
                    Spacer()
                    Button(action: edit) {
                        Text(entry.comment.isEmpty ? "ALT・編集" : "ALT ✓").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(.white).background(.black.opacity(0.65), in: Capsule())
                    }.buttonStyle(.plain).disabled(!editable).accessibilityLabel("添付\(index)の説明と設定")
                        .accessibilityIdentifier("native-attachment-edit:" + entry.id.uuidString)
                }.padding(8) }
            }.frame(width: 190, height: 190)
            HStack(spacing: 4) {
                Text(entry.name).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Menu {
                    Button("説明と設定", action: edit)
                    Button("前へ", systemImage: "arrow.left", action: earlier).disabled(!editable || index == 1)
                    Button("後へ", systemImage: "arrow.right", action: later).disabled(!editable)
                    Button("外す", role: .destructive, action: remove).disabled(!editable)
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 28) }
                    .accessibilityLabel("添付\(index)の操作").accessibilityIdentifier("native-attachment-actions:" + entry.id.uuidString)
            }.frame(width: 190)
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("native-attachment-card:" + entry.id.uuidString)
    }
}

private struct NativeAttachmentThumbnail: View {
    let entry: NativeAttachmentDraft
    let files: NativeAttachmentFiles
    @ObservedObject var session: NativeClientSession
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: entry.mimeType.hasPrefix("video/") ? "video" : entry.mimeType.hasPrefix("image/") ? "photo" : "doc")
                .font(.system(size: 32)).foregroundStyle(.secondary) }
            if entry.mimeType.hasPrefix("video/") { Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white) }
        }.accessibilityHidden(true)
        .task(id: session.revision.uuidString + entry.id.uuidString) {
            let generation = session.revision
            if let thumbnail = await files.thumbnail(entry.id), !Task.isCancelled, session.accepts(generation) { image = UIImage(cgImage: thumbnail); return }
            guard let id = entry.driveID, let owner = session.accountID, entry.mimeType.hasPrefix("image/") || entry.mimeType.hasPrefix("video/") else { return }
            do {
                let fresh = try await session.api.ownFile(id, owner: owner)
                guard session.accepts(generation), !Task.isCancelled, let url = clientImageURL(fresh.thumbnailUrl ?? fresh.url) else { return }
                let thumbnail = await NativeImageLoader.image(url, pixels: 480, maximumBytes: 8 * 1024 * 1024, cached: false)
                if session.accepts(generation), !Task.isCancelled { image = thumbnail }
            } catch { /* The attachment stays usable as a file card. */ }
        }
        .onDisappear { image = nil }
        .onChange(of: session.revision) { _ in image = nil }
    }
}

struct NativeAttachmentEditor: View {
    @Binding var entry: NativeAttachmentDraft
    let editable: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("画像の内容を説明", text: $entry.comment, axis: .vertical)
                        .lineLimit(4...10).accessibilityIdentifier("native-attachment-comment")
                        .disabled(!editable)
                } header: { Text("画像の説明（ALT）") } footer: { Text("画像を見られない人にも内容が伝わるように説明できます。") }
                Section {
                    Toggle("センシティブな内容", isOn: $entry.sensitive).accessibilityIdentifier("native-attachment-sensitive").disabled(!editable)
                }
                Section("ファイル名") {
                    TextField("ファイル名", text: $entry.name).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("native-attachment-name").disabled(!editable)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                }
                if !editable { Text("アップロード済みのファイルの設定はこの画面では変更できません。").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("添付を編集").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.bold() } }
        }
    }
}

struct ComposerAttachmentDrop: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let move: (UUID, UUID) -> Void
    func dropEntered(info: DropInfo) { if let dragged, dragged != target { move(dragged, target) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { guard dragged != nil else { return false }; dragged = nil; return true }
}
