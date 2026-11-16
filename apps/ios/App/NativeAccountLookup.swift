// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI

struct NativeAccountLookup: View {
    let username: String
    let host: String?
    @ObservedObject var session: NativeClientSession
    let open: (ClientRoute) -> Void
    @State private var id: String?
    @State private var error: String?
    var body: some View {
        Group {
            if let id { NativeProfileView(userID: id, session: session, open: open) }
            else if let error { ClientErrorRow(message: error) { Task { await load() } }.padding() }
            else { ProgressView("プロフィールを取得中") }
        }.task(id: session.revision) { await load() }.onDisappear { id = nil; error = nil }
    }
    private func load() async {
        let generation = session.revision
        id = nil; error = nil
        do {
            let result = try await session.api.user(username: username, host: host)
            guard session.accepts(generation), !Task.isCancelled else { return }
            guard result.username.caseInsensitiveCompare(username) == .orderedSame,
                  (result.host ?? "").caseInsensitiveCompare(host ?? "") == .orderedSame else { throw ClientAPIError.invalidResponse }
            id = result.id
        } catch { if session.accepts(generation), !Task.isCancelled { self.error = NativeClientSession.explain(error) } }
    }
}
