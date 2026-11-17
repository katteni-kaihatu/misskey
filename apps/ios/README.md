# ぐりすぺ iOSアプリ

`https://misskey.grid-space.io` に接続するSwiftUI/UIKitのネイティブクライアントです。通常起動ではサーバー入力やWebタブを表示しません。Webへのフォールバックを完成条件に含めない方針へ変更しました。現行の実装順序・残件は[ネイティブ開発計画](../../plans/ios-native-client.md)を参照してください。旧S1–S5のWeb互換性計画と検証記録は履歴として残します。

2026-11-17に開発方針を更新しました。写真・カメラからの投稿体験、MFM・Playのネイティブ対応、リアルタイム通信の効率を、必要なサーバーAPI拡張と合わせて改善します。技術の比較候補、未決定事項、受入条件は上記の計画にまとめています。この方針更新でカメラやPlayの実装が完了したわけではありません。以下は現在の実装と実行方法です。

ホーム/ローカル/グローバルと追加したチャンネルのタイムライン、検索、通知、自分のプロフィールをネイティブ画面で操作します。下線付きのフィードタブ、丸いアバター、本文と操作アイコン、固定の下部ナビゲーション、右下の青い投稿ボタンを使います。右上の投稿ボタンとタイムライン先頭の投稿誘導欄は表示しません。下部のホームアイコンをタップすると、選択中のTL/チャンネルの先頭へ戻り、保留中の新着も反映します。別の画面やノート詳細から押してもTLへ戻り、他のフィードの読書位置は動かしません。外部サイトへの通常のリンクは確認してブラウザで開きます。タイムラインのホーム・ローカル・グローバルは、上のタブのタップと左右スワイプで切り替えます。未ログイン時はローカル・グローバルを表示します。同じサーバーのノート・ユーザー・メンション・タグはネイティブへ遷移します。未実装の内部画面をWebViewで開きません。

上部タブ右端の編集ボタンから、タブの追加・削除・ドラッグでの並べ替えができます。「チャンネルを追加」で名前・説明を検索し、選んだチャンネルをタブへ追加します。チャンネルも左右スワイプ、引っ張って更新、末尾での自動読み込みで読めます。最大20個まで保存し、同じチャンネルの重複は防ぎます。設定はこの端末のアカウントごとに保存され、再起動後も順序を復元します。最後のタブを削除するとローカルを残します。

チャンネル追加画面は「すべて／ぐりすぺ／連携先」で表示元を切り替えられます。れぞらぶ側は専用APIとorigin付きのIDで取得・保存し、同じIDのローカルチャンネルと区別します。旧ログインには「ログインを更新」を表示して連携先の読取権限を追加します。連携先は本文・CW・引用と添付名の読み取りまで対応し、添付そのものの取得、投稿・リアクション等は継続実装です。本文は一時メモリだけで扱い、非表示時、失効/通信失敗時に破棄します。

アカウントメニューからMiAuthのシステム認可画面でログインし、アプリ用のトークンをKeychainへ保存します。通常の画面操作にWeb版のログインを使いません。既に保存された同じoriginのMiAuth認証は引き継ぎます。認証・通知/ドライブ/フォロー等の権限が不足する場合はログインし直してください。

投稿・返信・リノート/引用、CW、公開範囲、自分の下書き、写真/ファイル/ドライブ添付、アップロード、自分のノートの確認付き削除に対応します。投稿成功でTL全体や画像・リアクションの状態を作り直しません。表示対象の新しい投稿だけを、先頭にいる時は差し込み、途中を読んでいる時は「新着」へ保留します。自分のプロフィールと返信一覧にも差分を反映し、返信・リノート元の件数はそのノートだけを裏で確認します。応答喪失時は自動で書込を再送せず、ネイティブの履歴やドライブで状態を確認できます。画像の拡大と動画・音声再生もアプリ内のビューを使います。一般ファイルのダウンロード/管理・画像加工・投票作成等は継続実装です。

投稿画面は本文を中心にした白い画面と、キーボードの上に固定する画像・絵文字・オプションのツールバーを使います。画像ボタンから写真/動画を直接選択し、選択順にプレビューカードを表示します。カードから削除・ALT/センシティブ設定・ドラッグまたはメニューでの並べ替えができ、公開範囲は小さなメニュー、CWはオプションへまとめています。「投稿」で未アップロードの添付を順に送信してからノートを作成するため、手動アップロードの操作は不要です。送信結果が不明な添付は自動で再送せず、下書きに状態を残します。

絵文字は投稿とリアクションに共通のネイティブピッカーを使います。サーバーのカスタム絵文字、名前/別名検索、カテゴリ、センシティブ表示切替、標準絵文字1,915件の日本語/英語検索、origin/アカウント別の最近の選択に対応します。ピッカーは毎回「最近」から開き、標準とカスタムを混ぜて使った順に表示します。「最近」で検索すると全絵文字から探せます。画像とは別に公開の絵文字一覧も保存し、起動時に準備して、保存済みの一覧を先に表示します。「絵文字を取得中」のインジケーターは出しません。一覧は1時間再利用し、期限後は裏で更新します。更新できない場合は最大7日まで保存済みの一覧を使います。投稿本文ではカーソル/選択範囲へ挿入します。ぐりすぺのノートと、サーバーが連携対象と判定したれぞらぶのノートでは、専用APIで最大16種類を追加でき、自分の選択をすべて表示して1種類ずつ解除します。通常のリモートノートは1種類とし、変更時は古い絵文字を解除してから付け直します。選択直後に絵文字・件数・自分のアイコンを仮反映し、読取と権限確認・送信・結果の照合は裏で行います。連続操作は順番に送り、スクロールやタブ移動でも送信を継続し、拒否時は戻します。応答喪失時は未確定と表示し、再取得前に自動再送しません。リアクションボタンはWeb版と同じく絵文字の横に最大10人の14pxアバターを並べ、アバターは共通画像キャッシュを使います。人物一覧そのものはセッション内の一時メモリだけで扱います。いいねのみ（連携先のリモート向け制限を含む）/ローカル専用/センシティブ/確認できるロール制限を考慮し、サーバーで公開されないロールの利用可否は未確認として選択を止めます。本文・リアクション・ピッカーではGIF/APNG/WebPのアニメーションを再生します。画像データは共通キャッシュを使い、現在のフレームだけ最大192pxへ縮小して描画します。4 MiBを超えるデータは表示せず、300フレーム/2048pxを超える画像は先頭フレームで表示します。生成済みの絵文字フレームは16 MiB・512枚を上限にメモリだけで共有し、同じフレームを周回や別の表示で使い回します。再生中の未生成フレームはバックグラウンドで縮小・展開し、古いフレームの処理が遅れても新しい表示や静止画を上書きしません。本文1つで再生する絵文字は最大64個です。バックグラウンドや画面外では再生を止め、「視差効果を減らす」設定では静止画にします。 リアクションの選択は最初に画面の半分ほどで開き、上へのドラッグか検索欄のタップで大きく広がります。選択後は閉じ、次に開くと半分の高さへ戻ります。ノートは上下・左右の余白を整理し、操作ボタンのタッチ領域を保ったまま表示を詰めています。

ユーザーの表示名も、標準絵文字とアニメーション付きカスタム絵文字を描画します。タイムライン、引用、プロフィール、人物一覧、通知、投稿画面、連携先チャンネルで共通の1行表示を使います。リモートの表示名はそのユーザーの絵文字URLを使い、同名のローカル絵文字へ置き換えません。名前ではMFMの文章装飾やリンクを解釈しません。

アバター・プロフィールのバナー・カスタム絵文字（本文/リアクション/ピッカー）は、共通の画像キャッシュを使います。メモリ8 MiB・ディスク64 MiBを上限とし、アプリの再起動後も再利用します。通常の有効期間は24時間で、サーバーのmax-ageを尊重して最大7日に制限し、期限後はETag/Last-Modifiedで更新を確認します。通信失敗時のみ最大7日まで再利用し、no-store/private/no-cache/must-revalidateとHTTP拒否を考慮します。同じURLの同時通信は1回にまとめ、URLのqueryが変われば別画像として扱います。画像の通信セッションを共有して接続を再利用し、受信データはチャンク単位で処理します。宣言サイズと実際の受信量を最大8 MiBに制限し、Cookieやアプリのトークンは画像ホストへ送りません。保存名はハッシュとし、バックアップへ含めません。通常の投稿添付は永続キャッシュへ入れず、認証済みAPIの本文やトークンも保存しません。

添付画像の枠は読み込み前・読み込み後・センシティブ表示前を240ptで揃えます。表示用の縮小画像をメモリに保持し、スクロールで戻った最初のフレームから再利用します。画像の縮小は表示処理と別のタスクで行い、本文のMFM解析結果とインライン絵文字の表示データも再利用します。インライン絵文字は画像の取得前から同じ文字枠を確保します。本文の整形済みテキストと絵文字の埋め込みオブジェクトも表示中の本文ごとに再利用し、画像の読込後のサイズ調整で同じ画像を再取得・再生成する循環を防ぎます。本文・著者・絵文字URL・文字サイズ・ぼかしの開閉・セッション世代が変われば作り直し、非表示時に破棄します。通常TL・ローカルチャンネルは次の3投稿の非センシティブ画像（1投稿につき最大2枚）を同時2枚まで先読みします。CW・非表示投稿・センシティブ添付・連携先の私有チャンネルは先読みせず、スクロールで古くなった待機分は入れ替えます。先読みと画面表示は同じ通信・縮小済み画像を共有します。通常の投稿添付と本文の解析結果はセッション内の上限付きメモリだけに保持し、アカウント変更・背景移行で破棄します。

ホーム/ローカル/グローバルと通常チャンネルは、ぐりすぺのWebSocketを購読して新着を受け取ります。先頭で指を離している時だけ自動挿入し、過去を読んでいる間は表示位置を動かさず「新着」へ保留します。先頭へ戻るか新着ボタンで反映します。れぞらぶの共有投稿もサーバーのLTL配信条件を使い、ローカル投稿だけに絞り直しません。ホーム・ローカル・グローバルと通常チャンネルは、タブをスワイプしても読み込み済みのノート・続きのページ・表示位置を保ち、切り替え時に先頭を取り直しません。実際の接続断は再接続し、先頭を読み直して重複を除きます。れぞらぶの専用チャンネルは通常WSへ混ぜず、既存の認可付きAPIで15秒ごとに再確認し、先頭にいる時だけ新着を取得します。本文なしのリノート行にはリアクション状態の取得を要求せず、リノート自身の削除通知は受け取ります。引用投稿と通常ノートのリアクション更新は維持します。表示中のノートは共通のWebSocketでリアクションの追加/解除と拡張更新を購読し、100件ずつ最新状態を取り直します。自分の送信中の仮表示を上書きせず、件数が同じでも付けた人が変わればアイコンを更新します。サーバーの絵文字追加/変更/削除通知では保存済みカタログを先に表示したまま更新します。通常TL・ローカル/連携先チャンネルは末尾の250pt手前から続きを自動取得します。Listの先読みだけでは取得せず、表示中のタブで1回ずつ読み込み、末尾や進まないカーソルで停止します。通常TLの通信失敗では表示済みの投稿を残し、「再試行」で同じ続きから再開します。連携先の私有チャンネルはページごとの閲覧権限の再確認と失敗時の破棄を維持します。タイムラインのフィードタブはスクロール領域の外に固定し、引っ張って更新中も表示済みの一覧を保持します。更新中にページ送りの表示を入れ替えず、通信の失敗・キャンセル後も更新状態を解放します。

会話/返信と通常投票、プロフィールの紹介文・項目・投稿フィルター/ページ送り、フォロー/解除・申請/取消・フォロー中/フォロワー一覧、通知のページ送り・種類の絞り込み・未読数・確認付き一括既読を実装しています。通知一覧はWeb版と同じく、42ptのアバターにリアクション絵文字や種類別の小さなアイコンを重ね、名前・時刻・短い本文を並べます。投稿全体や添付画像は一覧内に展開せず、本文をタップしてノートを開きます。CWは注意書きだけを表示します。絞り込み・未読数・一括既読を上部へまとめ、状態の説明は必要な時だけ表示します。通知を閲覧しただけでは既読にしません。全機能が完成したクライアントではなく、プロフィール編集・検索拡張・投稿本文の編集配信・プッシュ・連携先の操作などは現行計画で追跡します。

ビルド、実機のアプリ内試験、合成データによる主要UIの確認結果は[検証記録](../../plans/ios-native-parity/validation.md)へ記録しています。新しい機能ごとの対象、途中の失敗、再試験、未実行の範囲を分けて追跡します。

写真UIの自動試験は、`GridSpace Composer QA`という名前の専用Simulatorに、固定色の合成PNG（RGB `140,103,226`と`44,169,175`）を2枚追加した環境だけで実行します。それ以外のSimulatorと実機ではスキップし、利用者の写真ライブラリを試験で開きません。通常の添付状態・原本取り込み・送信の単体試験はこの写真ライブラリを必要としません。

## WindowsとMacでできること

Windowsではコードの編集、URL判定などの単体テスト、Swiftの構文検査を進められます。SwiftUI・UIKit・WebKitを使うアプリ全体のビルド、シミュレーター、iPhoneへのインストールには、Macとフル版のXcodeが必要です。

MacのCodexにログインしていても、Windowsで実行中のチャットのコマンド実行先が自動的にMacへ変わるわけではありません。Mac側でこのリポジトリを開き、以下の手順で確認してください。Appleの対応環境は[Xcodeのシステム要件](https://developer.apple.com/xcode/system-requirements)を参照してください。

## Macでビルドする

MacのぐりすぺMisskeyリポジトリで、作業ブランチを取得します。`origin`は`https://github.com/katteni-kaihatu/misskey`を指すものとします。

```sh
git fetch origin
git switch codex/ios-native-parity-plan
git pull --ff-only origin codex/ios-native-parity-plan
```

フル版のXcodeを起動して初回設定と必要なiOSシミュレーターのインストールを済ませます。`xcode-select -p`がCommandLineToolsを指す場合は、XcodeのSettings > LocationsでCommand Line Toolsにフル版のXcodeを選びます。

リポジトリルートから次を実行します。Homebrewを利用する場合のXcodeGen導入コマンドも含みます。

```sh
brew install xcodegen
bash apps/ios/scripts/check-mac.sh
open apps/ios/GridSpace.xcodeproj
```

このスクリプトは共通処理の単体テスト、Xcodeプロジェクトの生成、署名なしのシミュレーター用ビルドを行います。`--test`ではWebKitのdelegate・ダイアログのアプリ内テストと、サーバー設定のUIテストも実行します。`.xcodeproj`は[XcodeGen](https://github.com/yonaskolb/XcodeGen)で`project.yml`から生成するため、Gitへ追加しません。

XcodeでGridSpaceスキームとiPhoneシミュレーターを選び、Runを実行します。実機ではSigning & Capabilitiesから自分のTeamを選び、必要に応じてBundle Identifierを変更します。署名用の資格情報はリポジトリへ保存しません。iOS 16.0は試作のビルド下限であり、製品の最低対応OSを決めたものではありません。

UIテストも実行する場合は、利用可能な端末のUDIDを指定します。テストは専用の設定領域を使い、実ユーザーのサーバー選択を引き継ぎません。

```sh
xcrun simctl list devices available
IOS_SIMULATOR='<表示されたUDID>' bash apps/ios/scripts/check-mac.sh --test
```

[iOS CI](../../.github/workflows/ios.yml)も追加しています。`apps/ios/`変更時のMacジョブで共通処理のテストと署名なしSDKビルドを実行します。GitHub上のジョブ自体はまだ未実行です。

## 接続したiPhoneでビルド・テストする

MacのXcodeへ開発用Apple Accountを登録し、iPhoneをペアリングしてデベロッパモードを有効にします。初回はiPhoneの「設定 → 一般 → VPNとデバイス管理」で開発元の信頼も必要です。

```sh
xcrun devicectl list devices
export IOS_DEVICE='<接続端末のidentifier>'
export IOS_DEVELOPMENT_TEAM='<自分のDevelopment Team ID>'
bash apps/ios/scripts/check-device.sh --test
bash apps/ios/scripts/check-device.sh --install
```

`--test`はDebugで共通処理・アプリ内テスト・UIテストを実行し、`--install`はSwiftの最適化を有効にした署名付きReleaseビルドを端末へ入れて通常起動します。引数なしなら実機向けビルドだけを行います。署名設定はコマンド引数で渡し、プロジェクトやGitへ個人のTeam・証明書・認証情報を保存しません。開発用プロファイルが期限切れになったら再ビルド・再インストールします。

UIテストは専用のUserDefaultsと非永続Webデータストアを使用します。DEBUGビルドの`--ui-testing --compatibility-fixture`で合成HTMLを開き、実サーバーへ投稿せずにファイル入力・ダイアログ・ブリッジを検証します。通常起動時のログイン情報をテストへ引き継ぎません。合成画像の保存・共有を手動確認するときは、DEBUG起動引数へ`--fixture-direct`も追加するとサーバー入力を省略できます。自動テスト起動時は原則としてUIKitの画面アニメーションを無効にし、XCTestの終了通知待ちを避けています。更新ジェスチャーとリアクションシートの試験では通常のアニメーションを有効にします。通常起動時のアニメーションには適用しません。実機のXCTest文字入力とiPhoneミラーリングは競合するため、UI自動テスト中はミラーリングを終了し、Xcodeが要求したときだけ端末をロック解除します。

## 旧Web互換ホストで実装した動作（履歴）

- サーバーはHTTPSのoriginとして検証します。ページのパス、認証情報、クエリーは指定できません。同じホストでもポートが異なれば別originとして扱います。
- Webのログインは永続`WKWebsiteDataStore`内に保持し、そのアカウント切替はWeb画面から行います。Webトークンは読み出しません。ネイティブ画面は別のMiAuthトークンをKeychainへ保存し、アプリのアカウントメニューから切り替えます。
- 同じoriginのルートは未知のルートも含めてWebへ渡し、queryとfragmentを保持します。外部ページは認証済みWebView内で開かず、外部ブラウザへ渡します。自動遷移には確認を表示します。UGCの外部iframeは別に扱います。
- WebKitが要求した別窓は、渡されたconfigurationで子WebViewを作成します。`window.close()`と、確認付きの閉じる操作に対応します。
- `WKDownload`の保存先を一時ディレクトリに限定し、設定のBlob書き出し等を共有シートへ渡します。ファイル名をパスとして解釈せず、保存完了・取消・失敗時に一時ファイルを削除します。
- iOS 18.4以降のファイル入力はPhotosUI・カメラ・Filesから選択できます。PhotosUIは順序付きの原本表現を使い、保護付き一時ファイルをWebKitへ返します。画像本体のbase64転送やネイティブからの先行アップロードは行わず、Webの加工・アップロード処理へ引き継ぎます。iOS 16–18.3ではWebKit標準UIを使います。
- 添付選択の取消・失敗・バックグラウンド移行・メモリ警告・遷移開始で待機中の要求を取り消します。一時ファイルはdocument置換、画面・Webプロセス終了、次回起動で片付けます。同じdocument内のSPA遷移では選択済みFile参照を保持します。
- [ブリッジv1](Bridge/README.md)は型付きのcapabilities/ready交渉と公開の`session.changed`失効通知を提供し、origin・frame・WebView・バージョン・epoch・サイズ・入力構造を検証します。対応Web版はアカウント保存の前に通知を待ち、ネイティブの添付選択・一時ファイル・保存・ダイアログを失効させます。子窓は独立したhandler/epochを持ち、親子の失効を連動させます。認証された操作はまだ公開しません。
- 対応Web版でアカウントを変更したら、保存後の同一originのGET遷移を新しいWebViewへ渡します。元のWebKit保存領域を引き継ぎ、古い画面履歴・子窓・保留処理を破棄します。通知直後にWebの保存を中断したり、POSTを自動再送したりしません。通常のSPA内の移動は履歴を保持します。
- JavaScriptのalert・confirm・promptに対応し、画面終了時も待機中のコールバックを完了させます。
- アプリ切替時はネイティブのカバーでWeb画面を隠します。Webプロセス終了時は自動再読み込みせず、復旧前に利用者の確認を求めます。
- 対応Web版にはバックグラウンド移行を通知し、復帰時は本文破棄とVue反映の応答を待って画面を戻します。非公開データの再認可は既存WebのAPIで行い、通常の入力は全体再読み込みで失わないようにします。応答失敗・5秒の待機超過では画面を覆ったまま再確認できます。旧Webは従来の互換表示を保ちます。全私有リソースの破棄確認が完了した意味ではありません。

## Macでの検証記録

2026-11-15、Xcode 27.2（27B52）で署名なしのiOS Simulator向けビルド、署名付きの実機ビルドとiPhone 16へのインストール・通常起動を確認しました。実機はiOS 27.2.1（24B156）です。共通処理の単体テスト15件、実機上でのアプリ内・UIテスト16件が成功しています。

実機では合成ファイルのバイト列をWebのFile入力へ渡す統合試験、順序付きプロバイダー読出し、後片付けと遅延応答・シンボリックリンクの拒否、外部origin/iframeからのブリッジ拒否、バージョン交渉、メニュー取消後の再選択、バックグラウンド移行後の再選択、JavaScriptダイアログを確認しています。追加の手動試験では、アプリのBlob書き出し→共有シートから合成PNG（128×128、359 bytes）を写真へ保存し、PhotosUI→既存Webの添付欄→既存アップローダー→ドライブ一覧への到達を確認しました。画像は未アップロードのFileとして先に渡り、PNG/MIME/サイズと加工メニューを保持しています。実ライブラリのiCloud遅延やカメラによる撮影、各画像加工の出力比較・公開投稿までの全経路は別途検証します。

シミュレーターは11月16日の再確認で起動し、iPhone 17 Pro / iOS 26.5でアプリ内25件・UI19件のケースが、全体実行と対象の修正後再試験で成功しました。合成PWAの認証・切替・退出・再認証・失効、実HTTPリダイレクト、Filesの移行・保存・再選択、起動前の移行復旧を含みます。以前の起動停滞とは区別して[検証記録](../../plans/ios-native-parity/validation.md)へ残しています。

実機でもUSBの開発用IPv6トンネルで認証・切替とFiles移行を確認し、回収した保存コピーの合成4レコード・未知フィールド・2 MiB Blob全バイトが元と一致しました。Swift/CFURLで表現が異なるIPv6 Blob URLを補正し、Core 19件と実機の応答判定4件も成功しています。さらにScratchpadを使う自動復旧・競合の保持/復元・別アカウントの内容非表示の4ケースが実機で成功し、再起動後の値とidentity、退避した記録の表示・削除取消・削除を確認しました。

画像などのBlobを含む競合復旧もSimulatorと実機で確認しました。復旧後の再起動、退避記録のFiles保存・再選択、通常移行としての拒否、通常snapshotの書出しと回収が成功し、移行前・取込み値・競合値の3種類の2 MiB全バイト・未知metadata・identity・hashが一致しました。

壊れた復旧記録の保持・再試行と、同じTOTP欄での訂正も実機で成功しました。通常移行を含む3件の通し実行と回収バイト比較が成功しています。同期的な保存拒否で全体の起動失敗へ例外が漏れる問題を修正し、保存拒否の分岐はChromium/WebKitのPWAで例外注入により確認しました。

ネイティブの非表示通知とWebの本文破棄処理も接続しました。新しい制御の9ケースがSimulatorと実機で成功し、実機ではアプリ内35件とUI3件が同じ通し実行で成功しています。PWAのScratchpad入力を保つ2回の復帰、アカウントの往復切替、退出後の本人限定ノートの非表示を確認しました。実連携のGridSpace私有APIによる全保持箇所の破棄・再認可を確認した意味ではありません。

GridSpaceの返信・引用ダイアログには対象IDだけを渡し、取得済みの本文・人物をpropsに残さないようにしました。復帰時は対象を実APIで再取得し、対象由来のCWも更新します。利用者が編集した本文・CW・添付候補は保持します。隔離した2サーバーのOAuth連携を使い、Chromium/WebKitで再取得待機中の非表示、人物情報の更新、許可撤回時の非表示と再認可後の下書き保持を確認しました。ブラウザ試験では実際のbootstrapを注入しますが、WebKitメッセージの提供部分は合成で、ServiceWorkerは無効です。実機・キャッシュ全体の比較を代替しません。

同じ2サーバーfixtureを使うSimulatorのアプリ内でも、通常ログイン・再起動後にチャンネル内引用を開き、下書きを入力して2回バックグラウンドから復帰するUI試験が成功しました。さらにUSB経由の実機で、復帰時の作者更新、許可撤回後の本文・人物の非表示と送信不可、実OAuth再認可後の下書き復元を確認しました。アプリ内38件とこのUI1件が同じ実行で成功しています。媒体・キャッシュ・複数窓を含む全私有データの比較は残っています。

これらは別の実行・対象再試験を含む限定した結果です。全保存状態、Web機能全体やほかのOSの互換性確認とは扱いません。

## 旧Web互換計画の未確認項目（履歴）

APNs、Share Extension、UGC共通実行環境、認証済みの操作ブリッジは後続の作業です。公開の失効通知と、設定「プロファイル管理」の確認付きローカルデータ移行をWeb側へ実装しましたが、実サーバーへは未配布です。[移行の契約と残件](../../plans/ios-native-parity/local-data-transfer.md)に記載したWebの比較試験は成功しています。通常の移行とScratchpadの起動前復旧は実機でも比較しましたが、全保存状態・障害・複数窓の比較は未完了です。現在のブリッジepochはdocument/sessionの識別子であり、ページが名乗るuserIdから認証権限を作りません。認証比較と権限設計の完了前に認証APIやプラグイン処理をネイティブへ移しません。

通常起動では指定された実サーバーのログイン状態保持、タイムラインと投稿フォーム、PhotosUIの取消、合成画像のドライブアップロードを手動確認しました。追加の合成PWA比較では、実機のTOTP・バックアップコード・連携解除・退出・再認証・再読込後の失効・2アカウントの往復切替も成功しています。認証8ケースは7件成功と、モバイル用メニューの操作要素を修正した切替1件の再試験を合わせた結果です。実機のパスキー・CAPTCHA・外部ウィジェットの互換性は未確認です。次の未確認の操作まで比較し、段階全体を対応済みとは判定しません。

| 確認対象 | 確認する操作 |
|---|---|
| 認証 | 正規ログイン、再起動後の復元、アカウント切替、ログアウト、TOTP・パスキー・CAPTCHA |
| 遷移 | query・fragment付きの内部ルート、未知のルート、外部リンク、自動外部遷移、子窓の開閉 |
| ファイル | 設定のエクスポート、バックアップコードの保存、複数写真の選択、画像加工、保存取消、容量不足 |
| UGC | Play、AiScript、プラグイン、外部iframe、音声、3D、CSS、Deck |
| 復帰 | 私有ノート表示中のバックグラウンド移行、Web側の本文破棄と復帰時の再認可、プロセス終了時の表示 |

画面を隠すカバーだけではWeb側の私有本文破棄やキャッシュ制御の確認にはなりません。別窓では現行Webと同様にdocumentごとにプラグインが起動するため、共通実行環境を実装するまでは二重実行の検証が必要です。添付やPages・Playの編集中データがプロセス終了をまたいで復元されるとは保証しません。

## 合成PWAとの通し試験

`local-parity-server.mjs`は、ビルド済みのe2eサーバーと専用のテスト用PostgreSQL/Redisを使います。既存の`test-misskey` DBを初期化するため、共有のテスト実行中は起動しません。通常の開発DBや本番へ接続する設定は受け付けません。リポジトリ指定のNode/pnpmと、次のビルドが必要です。

```sh
pnpm --filter i18n build
pnpm --filter frontend build
pnpm --filter frontend-embed build
pnpm --filter sw build
pnpm --filter backend build:e2e
```

フロントエンドを再ビルドしたら、試験サーバーも終了して起動し直します。起動時に読み込んだentry名と新しい静的ファイルが一致しないままでは、起動用JavaScriptが404になります。再起動では専用DBとfixtureも再生成されるため、実行中の試験が終わってから行います。

テスト用DB/Redisは既存e2e構成のlocalhost:54312/56312です。別の開発サーバーがlocalhost:61812を使っている場合は起動を拒否します。シミュレーター用のサーバーを1つのターミナルで起動します。

```sh
export GRIDSPACE_PARITY_DIRECTORY="$(mktemp -d /tmp/gridspace-ios-parity-XXXXXX)"
export GRIDSPACE_PARITY_ADDRESS=127.0.0.1
export GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET=1
pnpm --filter frontend exec tsx ../../apps/ios/scripts/local-parity-server.mjs
```

`LOCAL_PARITY_READY`が出てから、別ターミナルで同じ一時ディレクトリと起動したシミュレーターを指定します。

```sh
export IOS_SIMULATOR='<シミュレーターのUDID>'
python3 apps/ios/scripts/check-parity.py --run-dir '<上で作成した一時ディレクトリ>' --verify-export --verify-recovery
```

このrunnerはビルド、インストール、合成の移行ファイルを専用Documentsフォルダへコピー、非公開のxctestrun生成、XCTest実行を行います。個別の試験には`--only-test GridSpaceUITests/LocalPWAParityTests`などを指定できます。`run.json`には生成したテスト用資格情報があるため、内容をログへ出したりGitへ追加したりしません。結果のxcresultにも端末診断が含まれる場合があります。すべて一時ディレクトリに保存します。

`--verify-export`はFilesへの保存完了、プロセス再起動後の再選択、保存ファイルの回収・内容比較までを必須にします。フォルダは実行ごとに短い固有名で新しく作成し、Xcodeのインストール後に保存領域の場所が変わっても現在の場所から回収します。iOS 18.4未満でこの試験がskipされた場合も、検証指定時は合格にしません。実行環境にはリポジトリ指定のNode/pnpmが必要です。

`--verify-recovery`はBlobを含む競合の復旧後に、退避記録と通常の移行ファイルを別の専用フォルダへ保存し、回収した両ファイルを比較します。退避記録を通常の移行として取り込めないことも、再起動後のFiles選択で検査します。移行前・取込み値・競合した現在値のそれぞれの2 MiB Blob、未知フィールド、identityとhashを比較し、ファイル不在やskipを合格にしません。対象を絞る場合は`--only-test GridSpaceUITests/LocalPWAParityTests/testBlobRecoveryRestoresValuesAndExportsRecord --verify-recovery`を使います。

比較環境には一般利用者2人、TOTP利用者、トークン再生成専用の利用者を用意します。バックエンドのテスト用TOTP省略を無効にし、不正・使用済みコードの拒否を起動時に検査します。限定した連携アプリ用トークンが`secure: true`の`i/apps`へアクセスできないことと、第一者トークンで取得できることも検査します。本人限定・ローカルのみの合成ノートも作成し、未ログインと別アカウントで本文・添付が取得できないことを先に検査します。資格情報は合成データだけです。バックアップコードの使用と連携解除を含む試験の再実行には、サーバーを終了して新しいfixtureを作成してください。

実機では`GRIDSPACE_PARITY_ADDRESS`にMacのプライベートIP、`GRIDSPACE_PARITY_PEER`に対象iPhoneのプライベートIPを指定してサーバーを起動し、runner側では`IOS_SIMULATOR`の代わりに`IOS_DEVICE`と`IOS_DEVELOPMENT_TEAM`を指定します。Mac自身と指定した1端末からの通信だけを直接許可し、他の接続には一時的なHTTP認証を要します。これは試験サーバーの通信制限であり、Misskeyのユーザー認証や権限は変更しません。既存WebのAPI通信は`credentials: 'omit'`のため、HTTP認証だけに依存しません。

Wi-Fi経由で届かない場合は、ペアリング済み実機のCoreDevice wired IPv6 ULAトンネルでも試験できます。`devicectl device info details`の`connectionProperties.tunnelIPAddress`が端末側で、Mac側の現在のIPv6アドレスは`ifconfig`と照合します。Mac側を`GRIDSPACE_PARITY_ADDRESS`、端末側を`GRIDSPACE_PARITY_PEER`へ指定します。開発接続が閉じるとトンネルとアドレスが変わるため、読取り接続を維持してからサーバーを起動し、変わった場合は試験を止めてfixtureも作り直します。Mac自身からこのアドレスへ接続できるとは限らず、端末からの試験結果を確認します。端末・チーム・IPをソースへ固定しません。

USB経路には接続維持用スクリプトもあります。シミュレーターの試験・サーバーを終えてから、実機用の新しいディレクトリで起動します。

```sh
export GRIDSPACE_PARITY_DIRECTORY="$(mktemp -d /tmp/gridspace-ios-parity-usb-XXXXXX)"
export IOS_DEVICE='<対象のペアリング済み端末のidentifier>'
python3 apps/ios/scripts/hold-usb-parity.py --run-dir "$GRIDSPACE_PARITY_DIRECTORY"
```

`USB_PARITY_TRANSPORT_READY`が出たら、別ターミナルで同じ一時ディレクトリを指定します。

```sh
export GRIDSPACE_PARITY_DIRECTORY='<上で作成した一時ディレクトリ>'
export GRIDSPACE_PARITY_TRANSPORT_FILE="$GRIDSPACE_PARITY_DIRECTORY/usb-transport.json"
export GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET=1
unset GRIDSPACE_PARITY_ADDRESS GRIDSPACE_PARITY_PEER
pnpm --filter frontend exec tsx ../../apps/ios/scripts/local-parity-server.mjs
```

スクリプトはwiredのULAと、同じネットワークにある一意のMacアドレスだけを選びます。端末の全情報はprivateな一時領域で読み、接続情報を5秒ごとに更新します。サーバーは所有プロセスの生存と20秒以内の情報を要求し、明示アドレスとの混在を拒否します。維持は既定15分（`--seconds`で最大1時間）で、終了時は接続情報ファイルも削除します。アドレス変更は停止として扱い、実行中のDBを自動再初期化しません。通常の実機runnerは同じ`--run-dir`と前述の`IOS_DEVICE`・`IOS_DEVELOPMENT_TEAM`で実行し、終了後はサーバーと維持スクリプトを止めます。

試験接続はDEBUGビルドの`--ui-testing --local-parity-server`と、全パラメーターが揃った場合だけ有効です。7日間のサーバー証明書をSHA-256で固定し、ホスト名と有効期限も検証します。信頼ルートを端末やMacへインストールしません。HTTPSの検査はバックグラウンドで行い、APIや画像の読み込み中にメインスレッドを止めません。通常起動とReleaseでは既定のシステムの認証・証明書検証を使います。

試験のWeb保存領域はiOS 17以降の専用UUIDのデータストアを使い、通常のログイン情報と分離します。個々のUI試験ごとに新しい領域を作り、その試験内のプロセス再起動では同じ領域を使います。iOS 16では非永続ストアへ戻るため、その経路で再起動後の保持を確認したとは扱いません。Filesで使う合成ファイルのフォルダ公開もDEBUGだけです。

試験用のInfoキーは`Configuration/Debug-Info.plist`に明示し、runnerがビルド済みの値も検査します。`INFOPLIST_KEY_UIFileSharingEnabled`だけでは実際のplistへ出力されず、Files一覧が空になったためです。シミュレーターのUIテストrunnerは再インストールしますが、通常のアプリや保存データは削除しません。

合成ファイルを取り込み、再起動後に改めて書き出したファイルは、次で元の4レコードとバイト列を比較できます。元の取り込みファイルをそのまま渡すと拒否します。

```sh
pnpm --filter frontend exec tsx ../../apps/ios/scripts/verify-parity-export.mjs '<一時ディレクトリ>' '<新しく書き出したファイル>'
```

復旧エラーのPWA比較は、既存のe2e用DB/Redisとテストサーバーを起動し、`pnpm --filter frontend test:e2e local-data-recovery-errors.spec.ts`で実行します。`GRIDSPACE_PARITY_BROWSER=webkit`でWebKitを選べます。壊れた記録、IndexedDBアクセス拒否、退避作成途中の保存拒否を対象にし、最後の2つはブラウザAPIへの例外注入です。実機で実際に容量を使い切る試験とは区別します。

保存処理だけのブラウザ比較は、`pnpm --filter frontend test:browser`（Chromium）と`GRIDSPACE_PARITY_BROWSER=webkit pnpm --filter frontend test:browser`で実行できます。Playwrightの対応エンジンを事前にインストールしてください。WebKitでは実際のIndexedDB Blob保存に合わせ、試験専用の新しい永続profileを一時ディレクトリに作り、終了時に削除します。iOSの実機試験とは別の結果です。

実機のUI Automationでパスコード認証が求められたら、利用者が端末上で操作します。同じWi-Fiでも実機とMacが到達できない場合は通信エラーを記録し、シミュレーターの成功で実機の結果を置き換えません。試験サーバーは終了時に停止し、正常終了した実機のrunnerは通常のアプリ起動へ戻します。

## GridSpace連携先を含む隔離比較

上の静的ファイルとbackendのビルド、専用DB/Redisが必要です。単一サーバーのfixtureを終了してから起動します。既定はloopbackで、実機には下のUSB用手順を使います。

```sh
export GRIDSPACE_PARITY_DIRECTORY="$(mktemp -d /tmp/gridspace-ios-parity-pair-XXXXXX)"
export GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET=1
pnpm --filter frontend exec tsx ../../apps/ios/scripts/private-parity-server.mjs
```

`PRIVATE_PARITY_READY`の後、別ターミナルから同じディレクトリを指定します。両ブラウザとネイティブ試験は同じ合成アカウントの権限を使うため、順に実行します。

```sh
pnpm --filter frontend exec tsx ../../apps/ios/scripts/check-private-parity.mjs '<一時ディレクトリ>'
GRIDSPACE_PARITY_BROWSER=webkit pnpm --filter frontend exec tsx ../../apps/ios/scripts/check-private-parity.mjs '<一時ディレクトリ>'
# IOS_SIMULATORを指定してから実行
python3 apps/ios/scripts/check-parity.py --run-dir '<一時ディレクトリ>' --only-test GridSpaceUITests/LocalPWAParityTests/testPairedChannelQuoteReauthorizesAfterBackgroundWithoutLosingDraft
```

HTTPSの61813/61815と起動・終了時の検査用61812/61814を占有します。既存の待受けは停止せず起動を拒否し、起動ごとの新しいDBとRedis名前空間を作成して終了時に片付けます。既存の`test-misskey`は変更しません。暗号署名は通常の起動と同じslaccで行い、連合は他方のfixtureだけに限定します。OAuthの同意と許可の取得は実APIを通し、DBへ認可情報を直接挿入しません。試験用CAは子プロセス内に限り、システムの信頼設定へ追加しません。

`run.json`・鍵・trace・画面・XCTestログは合成の資格情報を含み得るため、すべてcheckout外の非公開ディレクトリに保存します。ブラウザ試験は投稿を送信せず、実際の許可撤回と再認可を行います。ServiceWorker・オフライン・ネイティブの認証APIや実機の許可撤回比較は、このブラウザ試験の対象外です。終了時は起動したサーバーへ通常の終了シグナルを送り、後片付けを待ちます。

実機用には、先の`hold-usb-parity.py`を別の非公開ディレクトリで起動し、その`usb-transport.json`を指定します。アドレスや端末IDは固定しません。

```sh
export GRIDSPACE_PARITY_DIRECTORY="$(mktemp -d /tmp/gridspace-ios-parity-pair-usb-XXXXXX)"
export GRIDSPACE_PARITY_TRANSPORT_FILE='<接続維持用ディレクトリ>/usb-transport.json'
export GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET=1
unset GRIDSPACE_PARITY_ADDRESS GRIDSPACE_PARITY_PEER
pnpm --filter frontend exec tsx ../../apps/ios/scripts/private-parity-server.mjs
```

USB用は予約済みの`g.ios-parity.test:61813`と`r.ios-parity.test:61815`を使い、61816のCONNECTプロキシで対応するloopbackポートだけへ転送します。プロキシには別の合成資格情報を要求し、実機側の接続元は指定した1端末に限定します。Mac上のブラウザ・Simulator用には同じプロキシをloopbackにも用意します。URL・Host・TLS・署名は各テストoriginのままです。TLSはプロキシで終端せず、Node worker内でこの2名のDNSだけを解決します。システムのDNS・ネットワーク経路・プロキシ・証明書の信頼設定は変更しません。接続維持の停止・アドレス変更・情報の期限切れではfixtureを終了します。

```sh
node apps/ios/scripts/check-parity-transport.mjs '<USB用fixtureディレクトリ>'
# IOS_DEVICE / IOS_DEVELOPMENT_TEAMを指定し、IOS_SIMULATORは未設定にする
python3 apps/ios/scripts/check-parity.py --run-dir '<USB用fixtureディレクトリ>' --only-test GridSpaceTests --only-test GridSpaceUITests/LocalPWAParityTests/testPairedChannelQuoteReauthorizesAfterBackgroundWithoutLosingDraft
```

試験用のWebデータストアと制御用URLSessionにだけ、iOS 17以降の[ProxyConfiguration](https://developer.apple.com/documentation/network/proxyconfiguration)を適用します。直接通信へのfailoverは許可しません。新しい実機試験は、Webへ秘密を渡さない閉じた制御経路で合成作者の更新・private grantの撤回と実OAuth再認可を行います。HTTPSの証明書はclientとpeerそれぞれの指定origin・指紋・有効期限を検証し、clientのHTTP認証情報をpeerへ渡しません。

自己署名の試験証明書をWebViewで手動検証するため、Debugのplistにだけ、この2つの予約名のATS例外を用意します。[Appleの当該キーの説明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionallowsinsecurehttploads)に従い、TLSバージョン・forward secrecyや証明書の指紋検査は緩めません。一般originへの例外やシステムへの信頼追加はありません。Releaseの生成plistにはこれらの例外・Files共有設定がないことをビルド後に検査しています。通常アプリの最低対応OSは変更していません。

## パスキー用のドメイン関連付け

WKWebViewでのパスキーには、RP IDのドメインとアプリの関連付けが必要です。[Appleの説明](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)と[関連付けファイルの仕様](https://developer.apple.com/documentation/xcode/supporting-associated-domains)に従い、次の2つを揃えます。

サーバーの設定に、運用者が管理するアプリのApplication Identifierを指定します。プレースホルダーは実際の署名済みアプリの値へ置き換えてください。

```yaml
iosAppIdentifiers:
  - '<Application Identifier Prefix>.<Bundle Identifier>'
```

`/.well-known/apple-app-site-association`が`webcredentials.apps`だけをJSONで返します。設定がなければ404です。IDのワイルドカード・不正な形式は起動時に拒否し、リクエストのHostからIDを作りません。アプリIDは最大32件です。関連付け先のHTTPSから、リダイレクトせず有効な証明書で配信する必要があります。Apple CDNの反映と端末上の関連付け確認も必要です。

アプリでは、Associated Domainsを含む署名プロファイルを用意してから明示的に有効化します。

```sh
export IOS_AUTH_DOMAIN='misskey.grid-space.io'
# IOS_DEVICE / IOS_DEVELOPMENT_TEAMも指定
bash apps/ios/scripts/check-device.sh --install
```

`Configuration/AssociatedDomains.entitlements`をアプリtargetにだけ適用します。ドメインはスキーム・パス・ポート・ワイルドカードを含まないDNS名に限ります。通常のビルドはこの設定を有効にしません。任意のサーバーのパスキーを使うブラウザ用権限や、Universal Linksは追加しません。

この関連付けはサーバーへ未配布で、有効な署名での実機のパスキー登録・認証・取消・復帰も未確認です。パスワード・TOTP・バックアップコードの試験成功で代替しません。

## Windowsで共通処理を検査する

Dockerが動作する環境では、リポジトリルートから次を実行できます。これはLinux版Swiftによる検査であり、iOSビルドの代わりにはなりません。JavaScriptCoreを使うMFMの2試験はApple以外では明示的にskipし、Mac/iOSで検証します。

```powershell
docker run --rm --mount "type=bind,source=$((Get-Location).Path)/apps/ios/Core,target=/work" --workdir /work swift:6.2 swift test
docker run --rm --mount "type=bind,source=$((Get-Location).Path)/apps/ios,target=/work,readonly" --workdir /work swift:6.2 sh -c 'swiftc -frontend -parse /work/App/*.swift /work/UITests/*.swift'
```

## Mac側のCodexへの引き継ぎ

2026-11-17の引き継ぎです。対象は`katteni-kaihatu/misskey`の`codex/ios-native-parity-plan`ブランチです。アプリ本体は`apps/ios/`、現行方針と優先順位は[ネイティブ開発計画](../../plans/ios-native-client.md)、過去の実行結果は[検証記録](../../plans/ios-native-parity/validation.md)にあります。`plans/ios-native-parity/`の旧Web併用案を現行方針として採用しないでください。

### ブランチを取得する

Macにこのリポジトリがない場合は、ターミナルで作業先へ移動して取得します。

```sh
git clone --branch codex/ios-native-parity-plan --single-branch https://github.com/katteni-kaihatu/misskey.git grid-space-misskey
cd grid-space-misskey
```

既にある場合は、そのリポジトリで次を実行します。作業中の変更があれば先に確認し、上書きせずに保存してください。`origin`が上記のリポジトリを指していることも確認します。

```sh
git status --short --branch
git remote get-url origin
git fetch origin
git switch codex/ios-native-parity-plan
git pull --ff-only origin codex/ios-native-parity-plan
```

### Xcodeと実行環境を確認する

フル版のXcodeを起動し、初回設定と必要なiOS Simulatorのインストールを済ませます。`xcode-select -p`がCommandLineToolsを指す場合は、XcodeのSettings > LocationsでCommand Line Toolsにフル版のXcodeを選びます。

```sh
xcode-select -p
xcodebuild -version
```

XcodeGenが未導入なら、Homebrewを使う環境では`brew install xcodegen`で導入できます。初回のネイティブSDKビルドは次のコマンドで行います。

```sh
bash apps/ios/scripts/check-mac.sh
open apps/ios/GridSpace.xcodeproj
```

この手順は同梱済みのMFM・絵文字データを使います。サーバーの起動やデータの再生成を行う段階では、`.node-version`と`package.json`の`packageManager`に合うNode/pnpmと依存関係も準備してください。

### Simulatorと実機で確認する

SDKビルドが通ったら利用可能なSimulatorを選び、テストを実行します。

```sh
xcrun simctl list devices available
IOS_SIMULATOR='<表示されたSimulatorのUDID>' bash apps/ios/scripts/check-mac.sh --test
```

隔離バックエンドや専用写真ライブラリが必要な試験は、その環境がないとスキップされます。スキップを機能の確認済みとして数えず、必要な環境は上の「合成PWAとの通し試験」「GridSpace連携先を含む隔離比較」を参照してください。写真UIの自動試験に個人の写真ライブラリを使わないでください。

カメラ・日本語入力・スクロール・発熱は手元のiPhoneで確認します。XcodeでApple Accountと署名用Teamを設定し、iPhoneをペアリングしてデベロッパモードを有効にしたうえで実行します。

```sh
xcrun devicectl list devices
export IOS_DEVICE='<接続端末のidentifier>'
export IOS_DEVELOPMENT_TEAM='<自分のDevelopment Team ID>'
bash apps/ios/scripts/check-device.sh --test
bash apps/ios/scripts/check-device.sh --install
```

`--test`はDebugの試験、`--install`は通常利用と性能確認用のReleaseビルドです。Simulatorの性能をiPhoneの性能として扱わないでください。署名・認証情報はリポジトリへ保存しません。

### Mac側のCodexへ渡す指示

取得した`grid-space-misskey`をMac側のCodexで開き、次の指示を渡します。

```text
このブランチのネイティブiOSクライアント開発を続けてください。
AGENTS.md、apps/ios/README.md、plans/ios-native-client.mdを読み、
plans/ios-native-parity/validation.mdで既存の検証結果と未確認範囲を確認してください。

まず作業ツリーとブランチを確認し、bash apps/ios/scripts/check-mac.shでSDKビルドを行ってください。
利用可能なSimulatorでテストし、環境不足によるスキップと成功を分けて記録してください。
次に写真・カメラ・添付編集・下書き復旧を一連のネイティブ投稿体験として改善してください。
MFM・Playの小規模な試作と、リアルタイム通信・描画の性能検証も現行計画に沿って進めてください。

必要なサーバーAPI拡張は許容されています。実装前に該当するbackend/frontendのスキルを参照し、
既存PWAとの互換性を保ってください。通常画面のWebフォールバックは採用しないでください。
PlayのJavaScriptCore対応やPWAへの性能優位を未検証のまま達成済みにしないでください。
実機のReleaseビルドで確認し、結果と未確認事項を検証記録へ残してください。
認証情報をソースやログへ保存せず、別途の指示なしにpushやストア提出は行わないでください。
```
