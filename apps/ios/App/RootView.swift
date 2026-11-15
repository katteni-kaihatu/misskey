// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UIKit

struct RootView: View {
    @ObservedObject var session: AppSession
    @State private var showsServerConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let origin = session.origin {
                    CompatibilityHost(origin: origin)
                        .id(origin.url.absoluteString)
                        .navigationTitle(origin.host)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button {
                                    showsServerConfirmation = true
                                } label: {
                                    Image(systemName: "server.rack")
                                }
                                .accessibilityLabel("サーバーを変更")
                            }
                        }
                } else {
                    setupForm
                        .navigationTitle("ぐりすぺ")
                }
            }
            .confirmationDialog("サーバーを変更しますか？", isPresented: $showsServerConfirmation, titleVisibility: .visible) {
                Button("サーバーを変更", role: .destructive) {
                    session.chooseAnotherServer()
                }
            } message: {
                Text("編集中の内容や未送信の添付は失われる場合があります。ログイン情報はアプリ内に残ります。")
            }
        }
    }

    private var setupForm: some View {
        Form {
            Section {
                TextField("https://サーバーのドメイン", text: $session.address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("server-address")
                    .onSubmit(session.connect)
                Button("接続", action: session.connect)
                    .accessibilityIdentifier("connect-server")
                if let message = session.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("server-error")
                }
            } header: {
                Text("サーバー")
            } footer: {
                Text("利用するぐりすぺのアドレスを入力してください。次の画面でWeb版と同じログインを行います。")
            }
        }
    }
}

private struct CompatibilityHost: UIViewControllerRepresentable {
    let origin: GridSpaceCore.ServerOrigin

    func makeUIViewController(context: Context) -> WebSessionController {
        WebSessionController(origin: origin)
    }

    func updateUIViewController(_ uiViewController: WebSessionController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: WebSessionController, coordinator: ()) {
        uiViewController.shutdown()
    }
}
