// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import SwiftUI
import UIKit
import WebKit

struct RootView: View {
    @ObservedObject var session: AppSession
    @State private var showsServerConfirmation = false
    @State private var nativeSessionToStop: NativeClientSession?

    var body: some View {
        Group {
            if AppSession.isTesting && !ProcessInfo.processInfo.arguments.contains("--native-client-fixture") {
                compatibilityFlow
            } else {
                // Fixture origins exist only in explicitly isolated Debug tests.
                NativeClientView(origin: AppSession.isTesting ? (session.origin ?? AppSession.productionOrigin) : AppSession.productionOrigin)
            }
        }
        .confirmationDialog("サーバーを変更しますか？", isPresented: $showsServerConfirmation, titleVisibility: .visible) {
            Button("サーバーを変更", role: .destructive) {
                if let native = nativeSessionToStop { Task { await native.visibility(false, cancelAuthentication: true) } }
                nativeSessionToStop = nil
                session.chooseAnotherServer()
            }
        } message: {
            Text("編集中の内容や未送信の添付は失われる場合があります。ログイン情報はアプリ内に残ります。")
        }
        .onChange(of: showsServerConfirmation) { if !$0 { nativeSessionToStop = nil } }
    }

    private var compatibilityFlow: some View {
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
                Text("利用するぐりすぺのアドレスを入力してください。接続後にアカウントメニューからログインできます。Web版はWebタブから利用できます。")
            }
        }
    }
}

struct CompatibilityHost: View {
    let origin: GridSpaceCore.ServerOrigin
    var initialDestination: URL? = nil
    @State private var documentID = UUID()
    @State private var initialURL: URL?
    @State private var websiteDataStore: WKWebsiteDataStore?

    var body: some View {
        WebDocumentHost(origin: origin, initialURL: initialURL ?? initialDestination, websiteDataStore: websiteDataStore) { destination, store in
            initialURL = destination
            websiteDataStore = store
            documentID = UUID()
        }
        .id(documentID)
    }
}

private struct WebDocumentHost: UIViewControllerRepresentable {
    let origin: GridSpaceCore.ServerOrigin
    let initialURL: URL?
    let websiteDataStore: WKWebsiteDataStore?
    let onAccountDocumentChange: (URL, WKWebsiteDataStore) -> Void

    func makeUIViewController(context: Context) -> WebSessionController {
        let controller = WebSessionController(origin: origin, initialURL: initialURL, websiteDataStore: websiteDataStore)
        controller.onAccountDocumentChange = onAccountDocumentChange
        return controller
    }

    func updateUIViewController(_ uiViewController: WebSessionController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: WebSessionController, coordinator: ()) {
        uiViewController.shutdown()
    }
}
