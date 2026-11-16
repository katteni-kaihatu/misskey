# iOSブリッジ v1（交渉・公開の失効通知）

`protocol.schema.json`がリクエストの契約、`GridSpaceCore.BridgeHandshake`がSwift側の型と入力検証を定義します。アプリがメインフレームへ注入する`BridgeBootstrap.js`は、`window.gridspaceNative.capabilities()`、`handshake(webVersion)`、`sessionChanged(change)`を提供します。Web版がこのオブジェクトを使わなくても既存画面を利用できます。

- 共通フィールドは`protocolVersion/requestId/accountEpoch/operation/payload`。requestIdはUUID、メッセージは最大4096 UTF-8 bytesです。
- `capabilities`は空のpayloadと`accountEpoch: null`で開始します。応答でバージョン、操作一覧、ネイティブのファイル入力対応、epochを返します。
- `ready`は返されたepochと`{ schemaVersion: 1, webVersion: "..." }`を送ります。Webバージョンは128 UTF-8 bytes以内です。
- `session.changed`は現在のepochと`{ host, userId, reason }`を送り、新しいepochを返します。hostは選択したサーバーと完全一致するauthority、userIdは128文字以内の英数字・`_`・`-`またはnull、reasonは`boot/switch/logout/revoked/storage`です。余分なキーは拒否します。受理時に添付選択・取得・一時ファイル・保存・ダイアログを失効させ、他の窓のepochも更新します。boot以外の変更では戻る・進むを止め、次の同一originのGET遷移を新しいWebViewへ渡して古い画面履歴と子窓を破棄します。Webが保存を終える前にはdocumentを破棄しません。通知元の新epochはその応答に含めます。
- 応答は`protocolVersion/requestId/accountEpoch/operation/status/payload`です。状態の型は`success/cancelled/refused/expired/resultUnknown`を区別します。交渉ではsuccess/refused/expiredを使用し、壊れたメッセージはPromiseをrejectします。未対応バージョンはrefusedとなり、Web互換表示を継続します。
- 選択中のHTTPS origin、メインフレーム、所有するWebViewを検証します。iframe、別origin、他のWebViewのハンドラーへの要求を拒否します。子窓はWebKit指定のconfigurationとデータストアを保ち、独立したhandler/epochを持ちます。公開の失効通知は同じアカウント文脈の親・子窓へ伝播します。

現在のepochはネイティブのdocument/session nonceで、認証アカウントを証明するものではありません。遷移開始・プロセス終了・画面終了・受理した失効通知で更新・失効します。`authenticatedOperations`は常にfalseです。ページが名乗るuserIdから権限を作りません。S1-3の認証比較とS3の認証・操作権限設計が済むまで、トークン取得、認証API中継、下書き、プラグイン、メディア読出しを追加しません。

Webアダプターは起動時に交渉し、対応する場合だけboot通知を送ります。ログイン・切替はアカウント保存の前に通知を待ち、接続後の失敗・期限切れでは保存を止めます。ログアウト・認証失効では通知に失敗してもWeb資格情報の削除・再読込を続けます。通常PWA・旧アプリは従来のWeb動作を保ちます。保留処理の失効通知だけで、Web内の私有本文の破棄や認証済みの操作ブリッジが完成したとは扱いません。サーバーへ未配布のWebアダプターは、実サーバーで動作済みとはみなしません。

`rendererLifecycle`は、この認証・操作メッセージとは別の表示制御です。対応Webは`version: 1`、現在の`hidden`、`subscribe(listener)`を使い、通常のdocument visibilityとネイティブの非表示状態を合わせます。通知で私有本文を参照へ戻し、Vueの反映後に応答します。表示へ戻る通知は既存のWeb認可処理を起動するだけで、古い本文を復元する許可ではありません。起動直後は非表示から始め、非表示中にマウントした読取り画面も取得を延期します。

ネイティブの`WebRendererLifecycle`だけが、注入時の制御用nonceを付けて`apply(hidden, key)`を呼びます。このnonceはアカウント資格情報ではなく、subscriberにも渡しません。応答の`{ version: 1, supported, hidden }`は表示処理の完了通知で、認証の証明には使いません。バックグラウンドへの移行時に破棄を通知し、復帰時にも破棄を繰り返してから表示を再開します。待機中はWebViewとそのアクセシビリティ要素を覆い、5秒で応答しなければ確認画面を保ちます。再確認は利用者の操作で行い、自動再読み込み・投稿再送はしません。遷移・アカウント変更・再度のバックグラウンド移行で、以前の応答は無効になります。

一時的なシステムUIによる非アクティブ化では画面だけを覆い、バックグラウンド移行前にはフォームを破棄しません。購読を持たない旧Webは従来の互換表示へ戻します。この場合に、新しい本文破棄の保証があるとは扱いません。協調するWebでも全私有リソース・複数窓・実連携先の失効・全キャッシュの比較は引き続き必要です。

写真選択はこの交渉用メッセージでデータを送らず、iOS 18.4以降のWebKit open-panel契約からネイティブUIへ接続します。選択順を保ってURLをWebKitへ返し、Web側の`File[]`、既存加工・アップローダーを使用します。UGC/外部iframeのファイル入力も、添付先ホストを表示して利用者が選択できますが、ブリッジは継承しません。iOS 16–18.3はWebKit標準の選択UIを維持します。

一時ファイルは選択単位の保護付きディレクトリへコピーし、取消・失敗時、documentの置換、Webプロセス終了、画面終了、次回起動時に削除します。SPA内の画面移動では同じdocumentのFile参照を保持します。選択中の要求は遷移開始時にも取り消し、遅れて届いた取得結果を渡しません。選択UIの終了通知は現在の画面と段階を照合し、写真プロバイダーの応答はスレッド間でも一度だけ受理します。取消は未完了の取得だけを対象とし、プロバイダーから返答がなくても待機中の処理を終了させます。画像本体をbase64に変換せず、PHPickerの原本表現とファイル名・拡張子を保持します。カメラで撮影した静止画はJPEGとして渡します。

アカウント変更後の新しいWebViewは、元の`WKWebsiteDataStore`オブジェクトを引き継ぎます。認証情報をSwiftへ取り出さず、認証後のGETが始まる直前に元の遷移を取消して移します。同じPWAを余分に二度起動する処理にはしません。GETとして移せないdocument置換では完了後の交換へ戻し、POSTを自動再送しません。この経路の全比較と、対応アダプターを持たない旧Web版・GridSpace私有本文の全キャッシュ破棄は別途未完了です。
