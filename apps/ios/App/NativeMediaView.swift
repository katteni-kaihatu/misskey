// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import AVKit
import GridSpaceCore
import SwiftUI

/// Media stays in the native hierarchy; opening an attachment never starts a
/// second Web login or sends the app token to the media host.
struct NativeMediaView: View {
    let file: ClientFile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var revealed = false
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var player: AVPlayer?
    var body: some View {
        VStack(spacing: 16) {
            if file.isSensitive && !revealed {
                Spacer()
                Button { revealed = true } label: { Label("センシティブな添付を表示", systemImage: "eye.slash") }.buttonStyle(.bordered)
                Spacer()
            } else if file.type.hasPrefix("image/") {
                GeometryReader { bounds in
                    NativeRemoteImage(url: clientImageURL(file.url), fill: false)
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .scaleEffect(min(5, max(1, scale * magnification)))
                        .gesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }.onEnded { scale = min(5, max(1, scale * $0)) })
                        .onTapGesture(count: 2) { scale = scale == 1 ? 2 : 1 }
                        .clipped()
                }
            } else if file.type.hasPrefix("video/") || file.type.hasPrefix("audio/") {
                VideoPlayer(player: player).task(id: revealed) {
                    guard (!file.isSensitive || revealed), let url = clientImageURL(file.url) else { return }
                    let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: [HTTPCookie](), AVURLAssetHTTPUserAgentKey: NativeHTTP.userAgent])
                    player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                }
            } else {
                Spacer(); Image(systemName: "doc").font(.system(size: 56)).foregroundStyle(.secondary)
                Text(file.name).font(.headline)
                Text(file.type).font(.caption).foregroundStyle(.secondary)
                if let url = clientImageURL(file.url) { ShareLink(item: url) { Label("ファイルのリンクを共有", systemImage: "square.and.arrow.up") } }
                Spacer()
            }
            if !file.isSensitive || revealed {
                if let comment = file.comment, !comment.isEmpty { Text(verbatim: comment).textSelection(.enabled).padding(.horizontal) }
                if let size = file.size { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.bottom).navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .onChange(of: scenePhase) { phase in if phase != .active { player?.pause(); dismiss() } }
            .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
    }
}
