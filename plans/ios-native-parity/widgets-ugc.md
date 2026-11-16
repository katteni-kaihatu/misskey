# ウィジェット・UGC・拡張機能の全件一覧

基準コミット: `f1bd2e3c4bebf931be8c49342691f03e3cdeb49b`。調査日: 2026-11-15。対象: `C:/Users/neo/GitHub/grid-space-misskey`。ソース調査のみで、実機動作・外部サービスの稼働は未検証。ここにあるネイティブ対応はすべて未実装の計画案。

## 読み方

初期実装はS0–S1で既存Web画面を残す。写真選択などのOS連携はS2、スクリプト共通実行環境はS3、日常画面はS4、標準ウィジェットとソーシャル機能はS5、配布判定はS6で扱う。

- N: 互換性の確認後にネイティブへ置き換える。確認前はWebを使う。
- H: ネイティブの外枠と既存Web/スクリプト/外部コンテンツを併用する。
- W: Web表示を維持する。後日のネイティブ化を前提条件にしない。

`widgets/index.ts`の登録は**37件**。`button`は標準ウィジェットだがユーザーのAiScriptを実行する。`aichan`・`kokolive`は標準ウィジェットでも外部iframeを含む。「標準ならすべて純ネイティブ」という分け方では機能が欠ける。

## 37件のウィジェット

根拠として示すパスは`packages/frontend/src/`からの相対パスである。プロパティは各`widgetPropsDef`を参照する。hidden値・未認識の値も保存・復元の対象とする。

| ID | 現在の機能と設定 | 初期 | 目標・段階 | 主な証拠 |
|---|---|---|---|---|
| `usefulLinks` | Resonite公式・コミュニティのリンク、説明、外部ページ表示。設定なし | W | N・S5 | `widgets/WidgetUsefulLinks.vue` |
| `profile` | 自分のバナー・アバター・名前・アカウント・プロフィールへの移動。設定なし | W | N・S5 | `widgets/WidgetProfile.vue` |
| `neosUserCount` | Resonite利用者数・履歴、外部統計API。`showHeader` | W | N・S5 | `widgets/WidgetNeosUserCount.vue` |
| `neosEvent` | 外部イベント情報の日付別表示・時刻・曜日色・詳細/場所。`showHeader` | W | N・S5 | `widgets/WidgetNeosEvent.vue` |
| `instanceInfo` | サーバーバナー・アイコン・名前・ホスト・概要画面。設定なし | W | N・S5 | `widgets/WidgetInstanceInfo.vue` |
| `memo` | メモ編集・手動保存・1秒後自動保存。`showHeader`,`height`。本文は`store.s.memo` | W | N・S5 | `widgets/WidgetMemo.vue` |
| `memo2` | 別メモの編集・手動/自動保存。`showHeader`。本文は`store.s.memo2` | W | N・S5 | `widgets/WidgetMemo2.vue` |
| `morse` | 共有ビープ、音の有効/無効・周波数・音量・押下/解放・接続状態。外部WebSocket/WebAudio。`sound`、storeに`toggle/freq/volume` | W | HまたはN・S5 | `widgets/WidgetMorse.vue` |
| `notifications` | 通知一覧。`showHeader`,`height`,hiddenの`excludeTypes` | W | N・S4/S5、通知と共通 | `widgets/WidgetNotifications.vue` |
| `timeline` | 利用可能な基本TL・リスト・アンテナ・共有アンテナ。`showHeader`,`height`,hiddenの`src/antenna/list`。サーバーポリシーで表示制限 | W | N・S4/S5、TLと共通 | `widgets/WidgetTimeline.vue`,`timelines.ts` |
| `calendar` | 日付・曜日・日/月/年の経過率・日付更新。`transparent` | W | N・S5 | `widgets/WidgetCalendar.vue` |
| `rss` | RSS一覧・更新。`url`,`refreshIntervalSec`,`maxEntries`,`showHeader`。サーバーRSSプロキシ利用 | W | N・S5 | `widgets/WidgetRss.vue` |
| `rssTicker` | RSSの横流し・シャッフル・方向。`url`,`shuffle`,`refreshIntervalSec`,`maxEntries`,`duration`,`reverse`,`showHeader`,`transparent` | W | N・S5 | `widgets/WidgetRssTicker.vue` |
| `trends` | トレンドハッシュタグと移動。`showHeader`。`hashtags/trend` | W | N・S5 | `widgets/WidgetTrends.vue` |
| `clock` | アナログ時計。`transparent`,`size`,`thickness`,`graduations`,`fadeGraduations`,`sAnimation`,`twentyFour`,`label`,`timezone` | W | N・S5 | `widgets/WidgetClock.vue` |
| `activity` | 自分の投稿アクティビティをカレンダー/グラフ表示。`showHeader`,`transparent`,hiddenの`view`。`charts/user/notes` | W | N・S5 | `widgets/WidgetActivity.vue`と子コンポーネント |
| `photos` | ドライブ写真、アップロード時の更新。`showHeader`,`transparent`。`drive/stream`とmainストリーム | W | N・S4/S5 | `widgets/WidgetPhotos.vue` |
| `digitalClock` | デジタル時計。`transparent`,`fontSize`,`showMs`,`showLabel`,`timezone` | W | N・S5 | `widgets/WidgetDigitalClock.vue` |
| `unixClock` | Unix時刻。`transparent`,`fontSize`,`showMs`,`showLabel` | W | N・S5 | `widgets/WidgetUnixClock.vue` |
| `postForm` | 固定表示の投稿フォーム全機能、autofocusなし。設定なし | W | H/N・S4/S5、投稿フォーム互換性が前提 | `widgets/WidgetPostForm.vue` |
| `slideshow` | ドライブフォルダー選択・ランダム画像・10秒周期・遷移。`height`,hiddenの`folderId` | W | N・S5 | `widgets/WidgetSlideshow.vue` |
| `serverMetric` | CPU+メモリ/ネットワーク/CPU/メモリ/ディスクの5表示。`showHeader`,`transparent`,hiddenの`view`。`server-info`,`serverStats` | W | N・S5 | `widgets/server-metric/index.vue`と子コンポーネント |
| `onlineUsers` | オンライン人数、15秒更新。`transparent`。`get-online-users-count` | W | N・S5 | `widgets/WidgetOnlineUsers.vue` |
| `jobQueue` | 配信/受信ジョブ状態・グラフ・音。`transparent`,`sound`。`queueStats`、認証/権限確認が必要 | W | N・S5 | `widgets/WidgetJobQueue.vue` |
| `button` | ユーザーのAiScriptを押下時に実行。`label`,`colored`,`script`。共通Mk API・widgetストレージ | W | H・S3/S5。スクリプトを捨てない | `widgets/WidgetButton.vue` |
| `aiscript` | コード編集・RUN・入力ダイアログ・print/end/errorログ。`showHeader`,hiddenの`script` | W | W/H・S3。ネイティブ描画は任意 | `widgets/WidgetAiscript.vue` |
| `aiscriptApp` | スクリプトのAsUi描画・操作・エラー・取込後の明示起動。`script`は手動保存、hiddenの`runAutomatically`,`showHeader` | W | W/H・S3。未対応なら画面全体Web | `widgets/WidgetAiscriptApp.vue` |
| `aichan` | 外部Live2D iframe、カーソル位置メッセージ。`transparent` | W | H/W・S5 | `widgets/WidgetAichan.vue` |
| `userList` | リスト選択・メンバーアバター・プロフィール移動。`showHeader`,hiddenの`listId`。`users/lists/show`,`users/show` | W | N・S5 | `widgets/WidgetUserList.vue` |
| `clicker` | クリッカーゲーム、registryの進捗保存。`showHeader` | W | W/HまたはN・S5 | `widgets/WidgetClicker.vue`,`components/MkClickerGame.vue`,`utility/clicker-game.ts` |
| `birthdayFollowings` | フォロー中の誕生日一覧、today/3day/week/month・日付更新。`showHeader`,`height`,`period` | W | N・S5 | `widgets/WidgetBirthdayFollowings.vue`と子コンポーネント |
| `chat` | チャット履歴・ルームへの移動。`showHeader` | W | N・S4/S5 | `widgets/WidgetChat.vue`,`components/MkChatHistories.vue` |
| `avatarWalk` | コンパクト/全画面のアバター散歩、VRM選択・アトラス生成/保存・共有・マルチプレイヤー・ズーム/アクション | W | H/W・S5。純ネイティブは別工数 | `widgets/WidgetAvatarWalk.vue`,`components/MkAvatarWalkGame.vue`,`utility/avatar-walk-*.ts` |
| `federation` | 連合サーバーとグラフ。`showHeader`。`federation/instances`,`charts/instance`。連合無効時は非表示 | W | N・S5 | `widgets/WidgetFederation.vue` |
| `instanceCloud` | 連合サーバークラウド表示。`transparent`。連合無効時は非表示 | W | N・S5 | `widgets/WidgetInstanceCloud.vue` |
| `kokolive` | 明示操作で外部配信iframeを表示、現行のPCでは別ウィンドウ操作。`showHeader` | W | H/W・S5 | `widgets/WidgetKokolive.vue` |
| `zou` | Resonite認証連携、銀行残高、入浴報酬/クールダウン/統計、入浴投稿の抑制、統計投稿。`sound`。外部auth/bank/QOLサービス | W | HまたはN・S5、外部APIの確認後 | `widgets/WidgetZou.vue` |

### 全ウィジェット共通の互換条件

- 追加・削除・設定・並び替え・ヘッダー・透明度・高さ・リンク・コンテキスト操作を保持する。
- 通常UIの左右配置`place`と、Deck各列の`widgets`配列を別々に保持する。`name/id/data`をそのまま復元できること。
- 未認識のIDやプロパティを保存時に消さない。新しい種類はWeb互換表示に回す。
- `gridspaceImportError`の通知/修復と、取込スクリプトの`runAutomatically=false`を保持する。
- 一般設定の保存には3秒のスロットルを使い、メモは独自の保存処理を持つ。バックグラウンドへの移行・Webプロセス終了の前後でも、未保存の編集を失わない設計が必要である。
- アプリ内ウィジェットをiOSのWidgetKitと混同しない。ホーム/ロック画面ウィジェットは追加機能で、37種類の置換にならない。
- 証拠: `components/MkWidgets.vue`, `widgets/widget.ts`, `ui/_common_/widgets.vue`, `ui/deck/widgets-column.vue`, `preferences/def.ts`。

## UGC・拡張機能

| 機能 | 落とせない内容 | 初期→目標 | 証拠 |
|---|---|---|---|
| 共通AiScript API | `USER_ID/USER_NAME/USER_USERNAME`,`CUSTOM_EMOJIS`,`LOCALE`,`SERVER_URL`; `Mk:dialog/confirm/toast/api/save/load/remove/url/nyaize`; 入力readline; NULL/エラー値の意味 | W→H・S3 | `aiscript/api.ts:35` |
| API権限 | 明示トークン指定/実行環境トークンの使い分け、プラグイン個別トークン、エンドポイント検証、`request_failed`。`Mk:apiExternal`は現行で無効 | W→H・S3、権限を広げない | `aiscript/api.ts`,`plugin.ts:376` |
| AsUi 14種類 | `root/container/text/mfm/button/buttons/switch/textarea/textInput/numberInput/select/folder/postFormButton/postForm`。ID・hidden・入れ子・スタイル・イベント・update/get/render | W→W/H・S3。純ネイティブ描画は任意 | `aiscript/ui.ts:149`,`:531`,`components/MkAsUi.vue` |
| 現行の未実装API | `Ui:patch`は現在TODO/no-op。完全対応していると誤記しない。node.updateやUi:renderと区別 | 現行挙動を維持 | `aiscript/ui.ts:155`,`:573` |
| Play実行 | 現行AiScript、版指定なし/1.0未満の旧0.19実行環境、入力/エラー、リセット・破棄 | W維持・S3 | `pages/flash/flash.vue:199` |
| Play利用操作 | 発見/検索/自作/いいね一覧、開始、ソース、いいね解除、共有/投稿共有/リンクコピー、作者/日時、通報、管理操作 | W維持。外枠Nは任意 | `pages/flash/flash-index.vue`,`pages/flash/flash.vue` |
| Play作成 | title/summary/MFM補完/プレビュー、コードエディター、プリセット、visibility、作成/更新/削除/確認 | W維持 | `pages/flash/flash-edit.vue` |
| Scratchpad | コード保存・実行・入出力・ログ/エラー・共通Mk API | W維持 | `pages/scratchpad.vue` |
| プラグイン管理 | コード導入、metadata/version、権限承認、設定、active、reload、uninstall、ログ/ソース、safe mode | W→H・S3 | `plugin.ts`,`pages/settings/plugin*.vue` |
| 外部拡張導入 | URL+hash取得・照合、plugin/theme判定、metadata/権限表示、導入/取消、取得/parse/hashエラー | W維持、deep link接続 | `pages/install-extensions.vue`,`components/MkExtensionInstaller.vue` |
| プラグインの6フック | 投稿フォーム追加操作、ユーザー操作、ノート操作、ノート表示加工/非表示、投稿前加工、ページ表示加工。旧名aliasも維持 | W→H・S3、N画面からも呼ぶ | `plugin.ts:197`,`:378` |
| Pages閲覧 | section/text/image/noteの4ブロック、入れ子/MFM、中央/フォント、表紙、いいね/リンク/共有/通報/編集、GridSpaceのorigin/managed対応 | W維持、限定Nは任意 | `pages/page.vue`,`components/page/page.block.vue` |
| Pages編集 | 作成/更新/削除/複製、名前/title/summary、表紙、整列/フォント/pin title、4種ブロック、プレビュー、保存検証 | W維持 | `pages/page-editor/common.ts`,`pages/page-editor/page-editor.vue` |
| 旧動的Pages | 現行PWAは未対応通知とPlayへの案内。旧動的コード実行まで現行機能とみなさない | Wの現行挙動 | `components/page/page.dynamic.vue` |
| テーマ | 組込/JSON5導入、light/dark/OS連動、派生色式、GUI/コード編集、管理/削除/コピー | H・S5。Nは色トークン対応、Wは完全維持 | `theme.ts`,`../frontend-shared/js/theme.ts`,`pages/theme-editor.vue`,`pages/settings/theme*.vue` |
| 任意Custom CSS | DOM/CSSセレクターと配置変更、local保存、safe mode無効化、適用時reload | Wを維持。Nに同等適用は保証しない | `pages/settings/custom-css.vue:29` |
| 設定profile | 名前・server/account/device scope・各値のsyncフラグ、cloud sync、自動backup、cloud一覧/復元/削除、`.misskeypreferences`入出力、開発用raw copy | H・S1/S3、形式を保持 | `preferences/manager.ts:73`,`preferences.ts`,`preferences/utility.ts:113` |
| Deck | 列/順序/スタック/幅と各列widgets、プロファイル同期、wallpaper/non-root UI/ナビゲーション設定 | W完全モード維持 | `deck.ts`,`ui/deck`,`pages/settings/deck.vue` |
| 保存ゲーム | Clicker registry進捗、AvatarWalk VRMアトラスBlob/共有/マルチプレイヤー | W維持・S1/S5でデータ移行 | `utility/clicker-game.ts`,`utility/avatar-walk-atlas.ts`ほか |

## 共通実行環境で維持する動作

フック名は`post_form_action`,`user_action`,`note_action`,`note_view_interruptor`,`note_post_interruptor`,`page_view_interruptor`。`Plugin:register:<name>`と旧`Plugin:register_<name>`の両方がある。

- `note_view_interruptor`: 同期的にNoteまたはnullを返す。順に加工し、nullなら後続を止めて表示しない。現行では例外をログに出力して続行する。未加工の本文を先に描画して見せず、表示用の変換をサーバーから取得したキャッシュそのものに反映しない。
- `note_post_interruptor`: 実行環境内は`execFnSync`を使い、フォーム側は各ハンドラーをawaitする。複製したペイロードを順に渡し、その返却値を次へ渡す。現行では例外をcatchしてログに出力し、続行する。本文だけでなくCW/公開範囲などの変更と、二重実行の有無を比較する。
- `page_view_interruptor`: 順にawaitして加工する。画面ロード全体のcatchでエラーを表示する。ノートと同じ例外処理だと決めつけない。
- `post_form_action`: フォームと`update(key,value)`コールバックを渡す。後からコールバックで状態が変わる可能性も扱う。一往復だけのRPCにして機能を削らない。
- user/note action: 選択対象と登録されたメニュー、UIダイアログ、API呼び出し、URLを開く動作を保持する。
- JavaScript関数はJSONとして渡せない。クロージャーは実行環境に残し、セッション内だけで有効なコールバックIDと値をやり取りする。再読み込み・ログアウトで古いIDを失効させる。
- WKWebViewのブリッジは非同期である。メインスレッドを同期待ちで止めず、フック処理は描画前/送信前の非同期工程として構成する。現行スクリプトの例外と、新たに生じるブリッジ障害/タイムアウトを区別する。ブリッジの応答なしに未加工の投稿を勝手に送らず、下書きの保持・再試行・Webフォームへの引き継ぎを設計する。
- JavaScriptCoreへの移動は、DOM依存やhost APIを切り出せるかを確認してから別途判断する。既存のインタープリターパッケージがそのまま動くとは断定しない。
- ブリッジは自社originからの定義済み操作に限定する。外部iframeとUGCへ任意のネイティブAPIやユーザーの全権トークンを与えない。Apple規定への適合は別途確認する。

## S0-3: 配布条件と実装境界の照合

2026-11-16に[AppleのApp Review Guidelines 4.7](https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators)を再確認した。次は原文の条件と、現在の実装を分けた記録であり、審査承認ではない。AiScript/Play/プラグインを対象ソフトウェアとして評価するのは設計上の仮定で、機能ごとの適用判断は未確認。

| 条項 | 原文で確認した条件 | 現在の実装と残件 |
|---|---|---|
| 4.7.1 | プライバシー、フィルタ、通報・ブロック、課金条件 | 既存Webの操作を保持する。各UGC画面での実操作・対応範囲の照合は未完了 |
| 4.7.2 | native API・技術の拡張/公開にはAppleの事前許可 | 公開bridgeは交渉・失効通知のみで、authenticatedOperationsはfalse。UGCへ任意API・主トークンを渡さない。OS標準file inputのアダプターを独自のUGC APIと同一視せず、免除とも断定しない |
| 4.7.3 | 個々のソフトウェアへのデータ・権限共有には都度明示同意 | ファイル選択自体は利用者が操作する。S3で実行所有者・操作・データを結び付ける同意が必要で、同一originや公開userIdだけを権限にしない |
| 4.7.4 | ソフトウェアの索引・metadataと、全ソフトウェアへのUniversal Links | ソース調査用の一覧は利用者向け索引ではない。現行entitlementは任意のwebcredentialsのみで、applinksや受信ルーターは未実装。私有コードを公開しない索引・遷移先・認可の実装と比較が残る |
| 4.7.5 | 対象年齢を超えるソフトウェアの識別と年齢制限 | アプリ側の年齢情報・UGCごとの判定・制限をまだ実装/比較していない。既存のセンシティブ表示だけで達成とみなさない |

S3の操作レジストリでは、第一者の画面操作とUGCの能力を分け、所有者・同意・認証文脈が未確認なら権限を発行しない。これは実装方針であり、Appleの許可を得たという意味ではない。UGC機能を取り除いてS5完了に置き換えず、配布判断・必要な許可と機能比較を別々に追跡する。

## ストレージ互換性

- `Mk:save/load/remove`のキー: widget/button/scratchpad=`aiscript:widget:*`、Play=`aiscript:flash:<id>:*`、plugin=`aiscript:plugins:<installId>:*`。現行の共有範囲を調べずに、アプリで別の名前空間へ変えたり全件を統合したりしない。
- `PreferencesProfile`はid/version/type/modifiedAt/name/preferencesを持ち、各値はscope/value/metaである。未知のフィールドを残し、ネイティブとWebの同時書き込み・アカウント切替・クラウドからの復元をテストする。
- `.misskeypreferences`に含まれるのはプロファイルのJSONだけである。memo/memo2/morseのstore値、プラグイントークン、AiScriptのlocalStorage、VRMのIndexedDB blob等が全て含まれると誤解しない。
- Clickerは`i/registry/get,set`の保存。AvatarWalkは`MisskeyAvatarWalk` IndexedDB、`avatarWalkGame::atlas`等とBlobを保存する。PWA→アプリへの移行手段を別に設計する。
- Web互換画面を開けてもSafariのlocalStorage/IndexedDBは自動で移らない。設定とローカルUGCデータの移行を別機能として扱う。

## 互換性の受入試験

1. ウィジェット登録37件・各プロパティ・AsUi 14種・プラグイン6種と旧名のエイリアスをスナップショット化し、上流更新の差分に合わせて一覧を更新する。
2. ネイティブ/Web混在ボードの追加/配置/並び替え/削除/設定、左右/Deck、未知のキー、再起動/ファイル入出力/クラウドからの復元を比較する。
3. button/AiScriptの入力/ログ/エラー/API成功・失敗/保存/削除/破棄と、取込時の手動起動を確認する。
4. Playの旧バージョン/現行バージョン、14ノード、更新・コールバック・MFMイベント・投稿フォームの初期値・再開/中断を確認する。
5. 全プラグインフックを2つ以上組み合わせ、順序/null/例外/非同期のフォーム更新/設定変更/再読み込み/削除/権限拒否をネイティブ/Webで比較する。
6. 任意CSSでレイアウト/セレクターを変更したテストデータは、完全Webモードで保持する。ネイティブ表示と同等とは表記しない。
7. 外部ウィジェットはネットワーク障害/未ログイン/音声を有効にする操作/復帰/外部リンクの動作を確認する。外部APIの仕様と稼働はソースから推定しない。
8. 個人データや認証情報をログやテストデータへ複写せず、合成データで試験する。
9. ゲームの保存/復元、VRMファイルの選択・ローカルアトラスの復元・共有、Webプロセスの終了とメモリ警告を含める。

## 確認上の注意

`WidgetNeosEvent.vue`には、既存のタイマーのコールバックが`getNeosEvent`を返すだけで呼び出さない箇所がある。現行のバグを自動的に「新アプリの欠落」とも「対応済み動作」とも扱わず、基準となる実際の動作を別途記録する。

本付録は機能調査の記録であり、記載したネイティブUIやWeb連携はまだ実装していない。
