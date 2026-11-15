# ぐりすぺ iOSアプリ

既存PWAをアプリ内で操作するための初期実装です。現在はサーバー指定、Web画面の表示、ログイン状態の保持、内部・外部リンクの振り分け、別窓、ファイル保存の処理を実装しています。全機能の互換性を確認した完成版ではありません。移行方針と機能一覧は[実装計画](../../plans/ios-native-parity/README.md)を参照してください。

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

このスクリプトは共通処理の単体テスト、Xcodeプロジェクトの生成、署名なしのシミュレーター用ビルドを行います。`.xcodeproj`は[XcodeGen](https://github.com/yonaskolb/XcodeGen)で`project.yml`から生成するため、Gitへ追加しません。

XcodeでGridSpaceスキームとiPhoneシミュレーターを選び、Runを実行します。実機ではSigning & Capabilitiesから自分のTeamを選び、必要に応じてBundle Identifierを変更します。署名用の資格情報はリポジトリへ保存しません。iOS 16.0は試作のビルド下限であり、製品の最低対応OSを決めたものではありません。

UIテストも実行する場合は、利用可能な端末のUDIDを指定します。テストは専用の設定領域を使い、実ユーザーのサーバー選択を引き継ぎません。

```sh
xcrun simctl list devices available
IOS_SIMULATOR='<表示されたUDID>' bash apps/ios/scripts/check-mac.sh --test
```

## 実装した動作

- サーバーはHTTPSのoriginとして検証します。ページのパス、認証情報、クエリーは指定できません。同じホストでもポートが異なれば別originとして扱います。
- Webのログインは永続`WKWebsiteDataStore`内に保持します。ネイティブ側はサーバーのoriginだけを保存し、Webトークンを読み出しません。アカウント切替は既存Web画面から行います。
- 同じoriginのルートは未知のルートも含めてWebへ渡し、queryとfragmentを保持します。外部ページは認証済みWebView内で開かず、外部ブラウザへ渡します。自動遷移には確認を表示します。UGCの外部iframeは別に扱います。
- WebKitが要求した別窓は、渡されたconfigurationで子WebViewを作成します。`window.close()`と、確認付きの閉じる操作に対応します。
- `WKDownload`の保存先を一時ディレクトリに限定し、設定のBlob書き出し等を共有シートへ渡します。ファイル名をパスとして解釈せず、保存完了・取消・失敗時に一時ファイルを削除します。
- JavaScriptのalert・confirm・promptに対応し、画面終了時も待機中のコールバックを完了させます。
- アプリ切替時はネイティブのカバーでWeb画面を隠します。Webプロセス終了時は自動再読み込みせず、復旧前に利用者の確認を求めます。

## この段階で未実装・未確認のもの

写真選択の独自PhotosUI、ネイティブのタイムライン・投稿画面、APNs、Share Extension、PWAからのローカルデータ移行、UGC共通実行環境、型付きブリッジは後続の作業です。現在はWebKit標準のファイル選択を利用します。iOS 18.4以降の独自open-panel実装はまだありません。

WindowsではiOS SDKによるコンパイル、端末へのインストール、Webログイン、パスキー、CAPTCHA、外部ウィジェットを確認できていません。シミュレーターと実機で次の操作を確認するまで、対応済みとは判定しません。

| 確認対象 | 確認する操作 |
|---|---|
| 認証 | 正規ログイン、再起動後の復元、アカウント切替、ログアウト、TOTP・パスキー・CAPTCHA |
| 遷移 | query・fragment付きの内部ルート、未知のルート、外部リンク、自動外部遷移、子窓の開閉 |
| ファイル | 設定のエクスポート、バックアップコードの保存、複数写真の選択、画像加工、保存取消、容量不足 |
| UGC | Play、AiScript、プラグイン、外部iframe、音声、3D、CSS、Deck |
| 復帰 | 私有ノート表示中のバックグラウンド移行、Web側の本文破棄と復帰時の再認可、プロセス終了時の表示 |

画面を隠すカバーだけではWeb側の私有本文破棄やキャッシュ制御の確認にはなりません。別窓では現行Webと同様にdocumentごとにプラグインが起動するため、共通実行環境を実装するまでは二重実行の検証が必要です。添付やPages・Playの編集中データがプロセス終了をまたいで復元されるとは保証しません。

## Windowsで共通処理を検査する

Dockerが動作する環境では、リポジトリルートから次を実行できます。これはLinux版Swiftによる検査であり、iOSビルドの代わりにはなりません。

```powershell
docker run --rm --mount "type=bind,source=$((Get-Location).Path)/apps/ios/Core,target=/work" --workdir /work swift:6.2 swift test
docker run --rm --mount "type=bind,source=$((Get-Location).Path)/apps/ios,target=/work,readonly" --workdir /work swift:6.2 sh -c 'swiftc -frontend -parse /work/App/*.swift /work/UITests/*.swift'
```

## Mac側のCodexへの引き継ぎ

上の手順で作業ブランチを取得し、Mac側のCodexでリポジトリを開けば、次の指示で続行できます。アプリ本体は`apps/ios/`、機能一覧と実装計画は`plans/ios-native-parity/`にあります。

> apps/ios/README.mdとplans/ios-native-parity/README.mdを読み、iOSクライアントの実装を続けてください。まずbash apps/ios/scripts/check-mac.shで実際のiOS SDKビルドを行い、失敗を修正してください。次に利用可能なシミュレーターでUIテストを実行し、上の確認表を基にWeb互換性を確認してください。未確認を対応済みにせず、既存PWAの機能を残したまま、写真選択と型付きブリッジの実装へ進めてください。認証情報をソースへ保存せず、ユーザーの依頼なしにpushやストア提出は行わないでください。
