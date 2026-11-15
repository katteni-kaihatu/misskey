# 画面・設定・管理機能の移行対応表

この付録はぐりすぺのWeb画面をiOSアプリへ移す際に、機能を欠落させないための確認対象を定める。対象は `f1bd2e3c4bebf931be8c49342691f03e3cdeb49b`、バージョン `2026.11.0-grid-space.31.33.1`。調査日は2026年11月15日。コードの読み取りによる調査であり、本番環境の設定値やiPhone実機での動作は確認していない。

## 対応方式と段階

初期の計画では全ルートを既存Web実装で処理する。下表の「初期」はこの計画を表し、iOSアプリで動作確認済みという意味ではない。「目標」は置き換え先の候補であり、実装済みではない。

| 記号 | 意味 |
|---|---|
| W | 既存Web実装をWKWebViewで維持する。後から必ずネイティブ化するという約束は含まない |
| N | 該当機能をネイティブで実装する候補。切り替えには機能ごとの同等性検証が必要 |
| H | ネイティブとWebを併用する候補。動的な表示や未対応の操作はWebで維持する |

| 段階 | 完了させる内容 |
|---|---|
| S0 | 機能一覧・対象コード・確認条件を確定する |
| S1 | 互換用WKWebView、認証、画面遷移、復帰処理を実装する |
| S2 | 写真・ファイル選択と既存アップロード処理の受け渡しを実装する |
| S3 | 共通の実行環境、状態管理、プラグイン連携を実装する |
| S4 | タイムライン・投稿・メディアをネイティブ化する |
| S5 | ソーシャル機能と標準ウィジェットのネイティブ対応を進める |
| S6 | 機能の同等性、実機動作、配布条件を検証する |

Wの画面にもS1とS6の検証が必要である。表にS1とある画面を、検証を省略してそのまま提供できるという意味にはしない。Hの画面も、S3でプラグインや状態管理を整えた後にS4またはS5で切り替える。

## 調査範囲と数え方

`packages/frontend/src/router.definition.ts` には162個の `path` 宣言がある。設定の子ルート32個、管理の子ルート33個のほか、親画面、空の子ルート、リダイレクト、該当なしの処理を含む。これは独立したユーザー機能の数ではない。子ルートは親の `/settings` または `/admin` と結合した。結合規則は `packages/frontend/src/lib/nirax.ts:115` にある。

ルートを網羅するだけでは、新規登録・初期設定・二要素認証などのダイアログ、ユーザーページ内のタブ、ファイル操作、メニュー、設定の各項目が漏れる。このため、後半にテンプレートごとの入力項目とクリック操作を併記する。`/settings/preferences` だけでも `v-model` または `:modelValue` が71か所ある。同じ設定が複数箇所に現れる場合を含むため、71個の独立した設定とは数えない。

権限の扱いも同等性の対象にする。`/settings` はログインを要し、管理の親画面と管理対象ユーザー・ファイル画面にはモデレーターの条件がある。`/admin/gridspace` はさらに管理者の条件がある。チャットは `policies.chatAvailability` で表示先を変える。画面が開けることと操作権限があることは別であり、API側の判定を維持する。

## URL・タブ・外部リンク

- `/about` と `/explore` はハッシュを `initialTab` として受け取る。`/play` は `tab`、`/play/doom` は `result` のクエリーを使う。通知からの起動、戻る操作、アプリの再起動でも対象タブを保つ。
- `/search` は `q,userId,username,host,channel,type,origin` を受け取る。`/gridspace/private` は `noteId,channelId`、`/miauth/:session` は `callback,name,icon,permission` を受け取る。
- `/share` は `title,text,url,visibility,localOnly,visibleUserIds,visibleAccts,replyId,replyUri,renoteId,renoteUri,fileIds` を個別に読む。公開範囲、宛先、返信・引用、添付、ActivityPub URIの解決、Unicode URLの正規化、親ウィンドウへの完了通知を残す。根拠は `packages/frontend/src/pages/share.vue:44` 以降。
- `/authorize-follow` と `/authorize_interaction` は `/lookup` へ、旧表記の `/install-extentions` は `/install-extensions` へ移る。`/redirect-test` はログインを要するテスト用ルートである。これらを重複機能として数えず、URL互換性の確認対象にする。
- `/neos/directupload` は通常メニューの一覧だけでは見落とすため、独立した確認対象にする。未分類の新ルートはアプリの空画面へ誘導せず、既存Web実装へ到達させる。

ユーザーページには `home,notes,files,activity,achievements,reactions,clips,lists,pages,flashs,gallery,raw` のタブがある。`packages/frontend/src/pages/user/index.vue:8`、`:38`、`:108` が根拠になる。実績はローカルユーザーかどうか、リアクションは本人・管理権限・`publicReactions` で条件が変わる。プロフィールと投稿一覧だけでユーザーページを移行済みにしない。

## 認証と初期設定

根拠は `packages/frontend/src/components/MkSignin*.vue`、`MkSignupDialog*.vue`、`MkUserSetupDialog*.vue`、`MkGridspaceSignupGuide.vue`、`packages/frontend/src/pages/welcome*.vue`、`packages/frontend/src/accounts.ts`、`i.ts`、`signout.ts`。

維持する機能はゲスト用の開始画面とタイムライン、サーバー初回設定、複数段階の `signin-flow`、ユーザー名・パスワード、hCaptcha・reCAPTCHA・Turnstile・mCaptcha、TOTP・バックアップコード、セキュリティキー・パスキー・パスワードレスログイン、新規登録と招待・サーバールールの確認、メール確認、パスワード再設定、トークン・MiAuth・OAuthの認可とコールバックである。

複数アカウント・複数ホスト、アカウント切り替えと保存解除、ログアウト時の消去、トークン失効時の復帰、破壊的な操作前の再認証も含む。ユーザー初期設定にはプロフィール、プライバシー、フォロー候補、GridSpace設定の再開がある。

WKWebViewでパスキーやCAPTCHAが使えるかは未検証である。必要に応じてシステムの認証用ブラウザへ渡すが、認証の結果を同じアカウントのアプリへ戻すところまで確認する。Safariに保存された認証状態が自動共有される前提にはしない。

## 設定の機能

各設定ページはS1でWeb版を維持する。使用頻度の高い項目をS5でネイティブ化する場合も、以下の操作・条件・保存範囲を対応表に残す。

- プロフィールには名前、自己紹介、場所、誕生日、言語、追加情報の編集と順序、フォロー時メッセージ、アバター・バナー、リアクション受付条件、猫・Bot表示がある。アバターデコレーションには選択、角度・位置・反転、個別解除、一括解除がある。
- プライバシーには手動フォロー承認、ローカル・リモート別のアカウント経過時間による承認条件、時間・日数の指定、フォロー済みユーザーの自動承認がある。リアクション、フォロー・フォロワー一覧、オンライン状態、検索エンジン、AI学習、探索、チャットの公開・受付条件、古い投稿の公開制限も維持する。
- セキュリティにはパスワード変更、TOTPの登録・更新・解除、バックアップコードの保存と残数警告、パスキーの登録・名前変更・解除、パスワードレスログインの前提条件、ログイン履歴のIP・時刻・成功状態、ログイントークンの再生成がある。
- ミュートにはソフト・ハードのワードミュート、一致した語の表示、絵文字、サーバー、ユーザーのリノートだけのミュート、期限付き・無期限ミュート、ブロック、設定日時の確認と解除がある。
- 通知には種類ごとの受付範囲、フォロー・フォロワー・相互・いずれか・リストの条件、特定ユーザーの通知、グループ表示、位置、音、既読化、テスト、削除、プッシュ登録、既読同期がある。APNsへ登録するだけで移行済みとはしない。
- メールにはアドレス変更・確認、サーバー告知、メンション・返信・引用・フォロー・フォロー申請の通知設定がある。
- データ移行には投稿・お気に入り・クリップ・フォロー・リスト・ミュート・ブロック・アンテナのエクスポートと、対応するインポートがある。ミュート済み・非アクティブユーザーの除外、返信を含める指定、非同期処理の完了・ダウンロード・失敗を確認する。
- ドライブには容量と統計、整理と削除、アップロード先フォルダー、ファイル名の維持、自動センシティブ判定・初期値、透かしとフレームのプリセット編集・削除・同期、画像と動画の圧縮レベルがある。
- クライアント設定には言語と絵文字索引の取得・削除、端末種別、リアルタイム受信・ポーリング間隔、アバターデコレーション、フォロー・リアクション確認、MFMとアニメーション、投稿操作、クリップ・リアクションの表示、メディア配置、原寸画像、NSFW・CW、投稿の初期公開範囲と連合、チャットのEnter操作、動きの抑制、スワイプ、引いて更新、画面維持、音声・動画再生、文字選択、メニュー、フォント、ぼかし、節約モード、URLプレビュー、固定リスト、切断時動作、ページキャッシュ、広告、季節演出、半球の指定がある。
- テーマ、任意CSS、Deck、ナビゲーション、ステータスバーはWeb表示に作用する。Webモードを意図的に維持し、ネイティブ画面に任意CSSを適用できるとは説明しない。テーマの導入・編集・削除、ナビゲーションの項目と順序、ステータスバーの種類・RSS・リスト・更新間隔、Deckの壁紙・列配置も残す。
- 設定プロファイル、クラウドへのバックアップと復元、インポート・エクスポート、キャッシュ削除、ヒントの再表示、ログアウトも操作として残す。サーバー・アカウント・端末の保存範囲と、未知の設定キーを失わない往復保存を確認する。
- GridSpace設定には連携状態、認可・再認可・解除・追加権限、相手サーバーの失敗、共有ドライブの進捗・制限、プロフィール・パレット・最近の絵文字・リスト・設定・配置・Playの移行と再試行、お気に入り・クリップ・ドライブの権限、フォロー複製の進捗と再試行、初期設定の再開がある。単一の連携スイッチとして置き換えない。

## 管理・モデレーション

管理機能はWを維持する対象とし、すべてをネイティブ化する義務を計画に追加しない。Web版で使えること、元の権限と再認証を維持することをS1・S6で確認する。入力欄にあるSMTP・S3・翻訳サービス等の秘密情報を、ネイティブ側のログや解析へ転送しない。

対象にはユーザー・アクティブユーザー・定着率・統計・ヒートマップ・連合・AP要求・サーバー・モデレーター・キューの概要、ID・アカウント・メール・ファイル検索、招待作成がある。ローカル・リモート絵文字の管理、旧版・新版の管理画面、検索・登録・ログ、アバターデコレーション、連合状態・配送キュー・再試行、ジョブ詳細、ファイル、告知、広告、通報の処理・転送・受信先、モデレーションログ、招待、データベース、システムWebhookも含む。

ロールには手動・条件付きの割り当て、条件式、権限種別、名前・説明・色・アイコン・表示順、アカウント移行時の維持、モデレーターによるメンバー編集、公開・バッジ・探索、期限付きのメンバー追加・解除、基本ポリシーとロール別ポリシーの有効・優先度・値・検索がある。

ポリシーの対象にはレート、GTL・LTL・VRTL、公開投稿、チャット、メンション数、招待数・周期・期限、絵文字・デコレーション管理、検索、翻訳、チャンネル、ドライブ容量・ファイルサイズ・種類、センシティブ指定、プロフィール画像、固定投稿、アンテナ、ワードミュート、Webhook、クリップ、リスト、広告、各種インポート、下書き、予約投稿、透かしがある。

サーバー設定には名称・連絡先・規約等、ブランド表示とゲスト表示、登録とルール・CAPTCHA、禁止語・ユーザー名・タグ、ブロック・サイレンス・メディアサイレンスのホスト、SMTP、S3、センシティブ画像判定、メール検証、IPログ、リレー、翻訳、連合モードと許可ホスト、リモートファイルの取得・保存、タイムライン配信、リアクションバッファー、リモート投稿整理、セットアップウィザードがある。

`packages/frontend/src/pages/admin-user.vue` にはモデレーションメモ、リモート情報の更新、凍結・解除、パスワード再設定、二要素認証の解除、アバター・バナー削除、全ファイル削除、アカウント削除、期限付きロール割り当て・解除、個別告知、グラフ、IP履歴、API上の情報表示がある。一部は管理者に限定される。URLが開くだけでは確認完了にしない。

## SPA以外の機能と端末連携

根拠は `packages/backend/src/server/web/ClientServerService.ts:147`、`:376`、`:424`、`:474`、`:565`、`:804` 以降、および `packages/frontend/src/_boot_.ts:19`。

- `/share,/auth,/miauth,/oauth,/signup-complete,/verify-email,/install-extensions` は最小構成の画面を独立して起動する。外部アプリからの認可・確認・共有も同様に成立させる。
- PWAのマニフェスト、ホーム画面のアイコン・名称・起動URL、`/?safemode=true`、共有ターゲット、Service Worker、更新・通知・クリック時の遷移は、WKWebViewへ入れるだけでは同等と扱わない。Web機能の維持または端末側の代替を項目ごとに検証する。
- 埋め込みは `/embed/user-timeline/:user`、`/embed/notes/:note`、`/embed/clips/:clip`、`/embed/*`、`/embed.js`、`/_info_card_`。フィードは `/@:user.atom`、`.rss`、`.json`、検索定義は `/opensearch.xml`。`/users/:user` 等の正規URLとHTMLプレビューを含め、アプリがリンクを受け取る場合も外部Webでの利用を壊さない。
- 埋め込みにはローカルユーザーや公開範囲の制約がある。フォロワー限定・宛先指定の投稿を公開埋め込みへ流用しない。
- `/bios,/cli,/flush`、サーバー側の `/streaming` の扱いは保守・復旧の確認対象とする。一律にネイティブ画面へ横取りしない。
- クリップボード、インポート・エクスポート・保存、別タブ・別ウィンドウ、画像編集、QR・カメラ、音声・動画・全画面表示、ゲームの描画、永続化、更新、セーフモード、異常終了からの復帰も確認する。

## 同等性の確認条件

1. 162宣言を基準にルートの追加・削除を検出し、各宣言に方式と確認担当を付ける。タブ・入力欄・メニュー・ダイアログも別項目として更新する。
2. ゲスト・一般ユーザー・モデレーター・管理者、本人・他人、ローカル・リモート、許可・拒否ポリシー、連携先の正常・解除・停止を組み合わせる。以前のアカウントのキャッシュやWeb保存領域から情報が混ざらないことを確認する。
3. パラメーター付きURL、クエリー、ハッシュ、Unicode、任意区間、旧URLを、終了中・ログイン中・認証途中・戻る操作で確認する。トークンを含むURLを記録しない。
4. 設定変更後にWeb・ネイティブ間を移動し、再起動、アカウント切り替え、バックアップ復元を行う。保存範囲を保ち、未知のキーを消さず、WebのCSS・テーマ・Deckが利用可能なことを確認する。
5. パスワード・TOTP・バックアップコード・パスキー・CAPTCHA・認可・復旧の各分岐を実機で確認する。組み込み表示で動かない処理には、実際に戻って来られるブラウザ連携を用意する。
6. ファイル選択の中止、不正な種類、クラウド未取得、通信切断、エクスポート失敗でもアカウントと編集中の内容を保つ。削除等の確認と認証を省かない。
7. コードの存在を確認した項目は「実装あり」と記録するが、「iOSで動作済み」「本番で有効」とは区別する。対象コードや設定が変わったらS0へ差分を反映し、S6の再検証範囲を決める。

## 全ルート宣言

根拠は `packages/frontend/src/router.definition.ts` の表中の行。コンポーネントは `packages/frontend/src/pages/` 配下である。初期Wと目標N・H・W、段階はいずれも計画であり、実機確認の結果ではない。

| ルート | ソース行 | コンポーネント | 初期 | 目標 | 段階 |
|---|---:|---|---|---|---|
| `/` | 26 | `welcome.vue (guest) / timeline.vue (signed in)` | W | H | S4 |
| `/timeline` | 29 | `timeline.vue` | W | H | S4 |
| `/gridspace/pages/:linkedId` | 32 | `page.vue` | W | W | S1・S6 |
| `/gridspace/gallery/:linkedId` | 35 | `gallery/post.vue` | W | W | S1・S6 |
| `/@:username/pages/:pageName(*)` | 38 | `page.vue` | W | W | S1・S6 |
| `/@:acct/following` | 41 | `user/following.vue` | W | H | S5 |
| `/@:acct/followers` | 44 | `user/followers.vue` | W | H | S5 |
| `/@:acct/:page?` | 48 | `user/index.vue` | W | H | S5 |
| `/notes/:noteId/:initialTab?` | 52 | `note.vue` | W | H | S4 |
| `/list/:listId` | 56 | `list.vue` | W | H | S5 |
| `/clips/:clipId/:peer?` | 59 | `clip.vue` | W | H | S5 |
| `/chat` | 62 | `chat/home.vue` | W | H | S5 |
| `/chat/user/:userId` | 66 | `chat/room.vue` | W | H | S5 |
| `/chat/room/:roomId` | 70 | `chat/room.vue` | W | H | S5 |
| `/chat/messages/:messageId` | 74 | `chat/message.vue` | W | H | S5 |
| `/instance-info/:host` | 78 | `instance-info.vue` | W | W | S1・S6 |
| `/settings` | 82 | `settings/index.vue` | W | H | S5 |
| `/settings/profile` | 86 | `settings/profile.vue` | W | H | S5 |
| `/settings/avatar-decoration` | 90 | `settings/avatar-decoration.vue` | W | H | S5 |
| `/settings/privacy` | 94 | `settings/privacy.vue` | W | H | S5 |
| `/settings/emoji-palette` | 98 | `settings/emoji-palette.vue` | W | H | S5 |
| `/settings/drive` | 102 | `settings/drive.vue` | W | H | S5 |
| `/settings/drive/cleaner` | 106 | `settings/drive-cleaner.vue` | W | H | S5 |
| `/settings/notifications` | 110 | `settings/notifications.vue` | W | H | S5 |
| `/settings/email` | 114 | `settings/email.vue` | W | H | S5 |
| `/settings/security` | 118 | `settings/security.vue` | W | W | S1・S6 |
| `/settings/preferences` | 122 | `settings/preferences.vue` | W | H | S5 |
| `/settings/auto-translation` | 126 | `settings/auto-translation.vue` | W | H | S5 |
| `/settings/theme/install` | 130 | `settings/theme.install.vue` | W | W | S1・S6 |
| `/settings/theme/manage` | 134 | `settings/theme.manage.vue` | W | W | S1・S6 |
| `/settings/theme` | 138 | `settings/theme.vue` | W | W | S1・S6 |
| `/settings/navbar` | 142 | `settings/navbar.vue` | W | W | S1・S6 |
| `/settings/statusbar` | 146 | `settings/statusbar.vue` | W | W | S1・S6 |
| `/settings/sounds` | 150 | `settings/sounds.vue` | W | H | S5 |
| `/settings/plugin/install` | 154 | `settings/plugin.install.vue` | W | W | S1・S6 |
| `/settings/plugin` | 158 | `settings/plugin.vue` | W | W | S1・S6 |
| `/settings/account-data` | 162 | `settings/account-data.vue` | W | W | S1・S6 |
| `/settings/mute-block` | 166 | `settings/mute-block.vue` | W | H | S5 |
| `/settings/connect` | 170 | `settings/connect.vue` | W | H | S5 |
| `/settings/apps` | 174 | `settings/apps.vue` | W | H | S5 |
| `/settings/webhook/edit/:webhookId` | 178 | `settings/webhook.edit.vue` | W | H | S5 |
| `/settings/webhook/new` | 182 | `settings/webhook.new.vue` | W | H | S5 |
| `/settings/deck` | 186 | `settings/deck.vue` | W | W | S1・S6 |
| `/settings/custom-css` | 190 | `settings/custom-css.vue` | W | W | S1・S6 |
| `/settings/profiles` | 194 | `settings/profiles.vue` | W | W | S1・S6 |
| `/settings/accounts` | 198 | `settings/accounts.vue` | W | H | S5 |
| `/settings/gridspace` | 202 | `settings/gridspace.vue` | W | W | S1・S6 |
| `/settings/other` | 206 | `settings/other.vue` | W | H | S5 |
| `/settings/` | 210 | `_empty_.vue` | W | H | S5 |
| `/reset-password/:token?` | 214 | `reset-password.vue` | W | H | S1 |
| `/signup-complete/:code` | 217 | `signup-complete.vue` | W | H | S1 |
| `/verify-email/:code` | 220 | `verify-email.vue` | W | H | S1 |
| `/announcements` | 223 | `announcements.vue` | W | H | S5 |
| `/announcements/:announcementId` | 226 | `announcement.vue` | W | H | S5 |
| `/about` | 229 | `about.vue` | W | W | S1・S6 |
| `/contact` | 233 | `contact.vue` | W | W | S1・S6 |
| `/about-misskey` | 236 | `about-misskey.vue` | W | W | S1・S6 |
| `/invite` | 239 | `invite.vue` | W | W | S1・S6 |
| `/ads` | 243 | `ads.vue` | W | W | S1・S6 |
| `/theme-editor` | 246 | `theme-editor.vue` | W | W | S1・S6 |
| `/roles/:roleId` | 250 | `role.vue` | W | H | S5 |
| `/user-tags/:tag` | 253 | `user-tag.vue` | W | H | S5 |
| `/explore` | 256 | `explore.vue` | W | H | S5 |
| `/search` | 260 | `search.vue` | W | H | S5 |
| `/gridspace/private` | 272 | `gridspace-private.vue` | W | H | S5 |
| `/gridspace/channels/:channelId?` | 276 | `gridspace-channels.vue` | W | H | S5 |
| `/authorize-follow` | 281 | `redirect` | W | H | S1 |
| `/authorize_interaction` | 286 | `redirect` | W | H | S1 |
| `/lookup` | 290 | `lookup.vue` | W | W | S1・S6 |
| `/share` | 294 | `share.vue` | W | H | S4 |
| `/api-console` | 298 | `api-console.vue` | W | W | S1・S6 |
| `/scratchpad` | 302 | `scratchpad.vue` | W | W | S1・S6 |
| `/preview` | 305 | `preview.vue` | W | W | S1・S6 |
| `/auth/:token` | 308 | `auth.vue` | W | H | S1 |
| `/miauth/:session` | 311 | `miauth.vue` | W | H | S1 |
| `/oauth/authorize` | 320 | `oauth.vue` | W | H | S1 |
| `/tags/:tag` | 323 | `tag.vue` | W | H | S5 |
| `/pages/new` | 326 | `page-editor/page-editor.vue` | W | W | S1・S6 |
| `/pages/edit/:initPageId` | 330 | `page-editor/page-editor.vue` | W | W | S1・S6 |
| `/pages` | 334 | `pages.vue` | W | W | S1・S6 |
| `/play/:id/edit` | 337 | `flash/flash-edit.vue` | W | W | S1・S6 |
| `/play/new` | 341 | `flash/flash-edit.vue` | W | W | S1・S6 |
| `/play/doom` | 345 | `flash/doom.vue` | W | W | S1・S6 |
| `/play/:id` | 349 | `flash/flash.vue` | W | W | S1・S6 |
| `/play` | 352 | `flash/flash-index.vue` | W | W | S1・S6 |
| `/gallery/:postId/edit` | 356 | `gallery/edit.vue` | W | H | S5 |
| `/gallery/new` | 360 | `gallery/edit.vue` | W | H | S5 |
| `/gallery/:postId` | 364 | `gallery/post.vue` | W | H | S5 |
| `/gallery` | 367 | `gallery/index.vue` | W | H | S5 |
| `/channels/:channelId/edit` | 370 | `channel-editor.vue` | W | H | S5 |
| `/channels/new` | 374 | `channel-editor.vue` | W | H | S5 |
| `/channels/:channelId` | 378 | `channel.vue` | W | H | S5 |
| `/channels` | 381 | `channels.vue` | W | H | S5 |
| `/custom-emojis-manager` | 384 | `custom-emojis-manager.vue` | W | W | S1・S6 |
| `/avatar-decorations` | 387 | `avatar-decorations.vue` | W | W | S1・S6 |
| `/registry/keys/:domain/:path(*)?` | 391 | `registry.keys.vue` | W | W | S1・S6 |
| `/registry/value/:domain/:path(*)?` | 394 | `registry.value.vue` | W | W | S1・S6 |
| `/registry` | 397 | `registry.vue` | W | W | S1・S6 |
| `/install-extentions` | 400 | `redirect` | W | W | S1・S6 |
| `/install-extensions` | 404 | `install-extensions.vue` | W | W | S1・S6 |
| `/admin/user/:userId` | 408 | `admin-user.vue` | W | W | S1・S6 |
| `/admin/file/:fileId` | 411 | `admin-file.vue` | W | W | S1・S6 |
| `/admin` | 414 | `admin/index.vue` | W | W | S1・S6 |
| `/admin/overview` | 417 | `admin/overview.vue` | W | W | S1・S6 |
| `/admin/users` | 421 | `admin/users.vue` | W | W | S1・S6 |
| `/admin/emojis` | 425 | `custom-emojis-manager.vue` | W | W | S1・S6 |
| `/admin/emojis2` | 429 | `admin/custom-emojis-manager2.vue` | W | W | S1・S6 |
| `/admin/avatar-decorations` | 433 | `avatar-decorations.vue` | W | W | S1・S6 |
| `/admin/gridspace` | 437 | `admin/gridspace.vue` | W | W | S1・S6 |
| `/admin/federation-job-queue` | 441 | `admin/federation-job-queue.vue` | W | W | S1・S6 |
| `/admin/job-queue` | 445 | `admin/job-queue.vue` | W | W | S1・S6 |
| `/admin/files` | 449 | `admin/files.vue` | W | W | S1・S6 |
| `/admin/federation` | 453 | `admin/federation.vue` | W | W | S1・S6 |
| `/admin/announcements` | 457 | `admin/announcements.vue` | W | W | S1・S6 |
| `/admin/ads` | 461 | `admin/ads.vue` | W | W | S1・S6 |
| `/admin/roles/:id/edit` | 465 | `admin/roles.edit.vue` | W | W | S1・S6 |
| `/admin/roles/new` | 469 | `admin/roles.edit.vue` | W | W | S1・S6 |
| `/admin/roles/:id` | 473 | `admin/roles.role.vue` | W | W | S1・S6 |
| `/admin/roles` | 477 | `admin/roles.vue` | W | W | S1・S6 |
| `/admin/database` | 481 | `admin/database.vue` | W | W | S1・S6 |
| `/admin/abuses` | 485 | `admin/abuses.vue` | W | W | S1・S6 |
| `/admin/modlog` | 489 | `admin/modlog.vue` | W | W | S1・S6 |
| `/admin/settings` | 493 | `admin/settings.vue` | W | W | S1・S6 |
| `/admin/branding` | 497 | `admin/branding.vue` | W | W | S1・S6 |
| `/admin/moderation` | 501 | `admin/moderation.vue` | W | W | S1・S6 |
| `/admin/email-settings` | 505 | `admin/email-settings.vue` | W | W | S1・S6 |
| `/admin/object-storage` | 509 | `admin/object-storage.vue` | W | W | S1・S6 |
| `/admin/security` | 513 | `admin/security.vue` | W | W | S1・S6 |
| `/admin/relays` | 517 | `admin/relays.vue` | W | W | S1・S6 |
| `/admin/external-services` | 521 | `admin/external-services.vue` | W | W | S1・S6 |
| `/admin/auto-translation` | 525 | `admin/auto-translation.vue` | W | W | S1・S6 |
| `/admin/performance` | 529 | `admin/performance.vue` | W | W | S1・S6 |
| `/admin/invites` | 533 | `admin/invites.vue` | W | W | S1・S6 |
| `/admin/abuse-report-notification-recipient` | 537 | `admin/abuse-report/notification-recipient.vue` | W | W | S1・S6 |
| `/admin/system-webhook` | 541 | `admin/system-webhook.vue` | W | W | S1・S6 |
| `/admin/` | 545 | `_empty_.vue` | W | W | S1・S6 |
| `/my/notifications` | 549 | `notifications.vue` | W | H | S4 |
| `/my/favorites` | 553 | `favorites.vue` | W | H | S5 |
| `/my/achievements` | 557 | `achievements.vue` | W | W | S1・S6 |
| `/my/drive/folder/:folder` | 561 | `drive.vue` | W | H | S4 |
| `/my/drive` | 565 | `drive.vue` | W | H | S4 |
| `/my/drive/file/:fileId` | 569 | `drive.file.vue` | W | H | S4 |
| `/my/follow-requests` | 573 | `follow-requests.vue` | W | H | S5 |
| `/my/lists/:listId` | 577 | `my-lists/list.vue` | W | H | S5 |
| `/my/lists` | 581 | `my-lists/index.vue` | W | H | S5 |
| `/my/clips` | 585 | `my-clips/index.vue` | W | H | S5 |
| `/my/antennas/create` | 589 | `my-antennas/create.vue` | W | H | S5 |
| `/my/antennas/:antennaId` | 593 | `my-antennas/edit.vue` | W | H | S5 |
| `/my/antennas` | 597 | `my-antennas/index.vue` | W | H | S5 |
| `/timeline/list/:listId` | 601 | `user-list-timeline.vue` | W | H | S4 |
| `/timeline/antenna/:antennaId` | 605 | `antenna-timeline.vue` | W | H | S4 |
| `/clicker` | 609 | `clicker.vue` | W | W | S1・S6 |
| `/games` | 613 | `games.vue` | W | W | S1・S6 |
| `/avatar-walk` | 617 | `avatar-walk.vue` | W | W | S1・S6 |
| `/bubble-game` | 621 | `drop-and-fusion.vue` | W | W | S1・S6 |
| `/reversi` | 625 | `reversi/index.vue` | W | W | S1・S6 |
| `/reversi/g/:gameId` | 629 | `reversi/game.vue` | W | W | S1・S6 |
| `/qr` | 633 | `qr.vue` | W | W | S1・S6 |
| `/debug` | 637 | `debug.vue` | W | W | S1・S6 |
| `/redirect-test` | 642 | `redirect` | W | H | S1 |
| `/neos/directupload` | 646 | `neos/direct-upload.vue` | W | W | S1・S6 |
| `/:(*)` | 649 | `not-found.vue` | W | W | S1・S6 |

## 設定テンプレートの入力項目と操作

以下は各テンプレートから `v-model`・`:modelValue` とクリックハンドラーを抽出した一覧である。識別子はコードと対応させるため原文のまま残す。入力項目名に秘密情報を示す識別子が含まれていても、実際の設定値は記載していない。

ハンドラーが一覧にない場合でも機能がないとは判定しない。子コンポーネントへの委譲、変更の監視、フォーム送信、動的に生成される項目、コンテキストメニューは別途確認する。表中の操作を画面で実行し、保存・中止・再表示・異常時・権限違いを確認する。

- `packages/frontend/src/pages/settings/2fa.qrdialog.vue`: 入力項目: `token`。クリック操作: `cancel`, `page++`, `page--`, `tokenDone`, `downloadBackupCodes`, `allDone`。
- `packages/frontend/src/pages/settings/2fa.vue`: 入力項目: `usePasswordLessLogin`, `v => updatePasswordLessLogin(v)`。クリック操作: `renewTOTP`, `unregisterTOTP`, `registerTOTP`, `addSecurityKey`, `renameKey(key)`, `unregisterKey(key)`。
- `packages/frontend/src/pages/settings/account-data.vue`: 入力項目: `excludeMutingUsers`, `excludeInactiveUsers`, `withReplies`。クリック操作: `exportNotes()`, `exportFavorites()`, `exportClips()`, `exportFollowing()`, `importFollowing($event)`, `exportUserLists()`, `importUserLists($event)`, `exportMuting()`, `importMuting($event)`, `exportBlocking()`, `importBlocking($event)`, `exportAntennas()`, `importAntennas($event)`。
- `packages/frontend/src/pages/settings/accounts.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `addAccount`, `refreshAllAccounts`, `showMenu(x.host, x.id, $event)`。
- `packages/frontend/src/pages/settings/apps.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `revoke(token)`。
- `packages/frontend/src/pages/settings/auto-translation.vue`: 入力項目: `enabled`, `targetLang`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/settings/avatar-decoration.decoration.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `emit('click')`。
- `packages/frontend/src/pages/settings/avatar-decoration.dialog.vue`: 入力項目: `angle`, `offsetX`, `offsetY`, `flipH`。クリック操作: `update`, `detach`, `attach`。
- `packages/frontend/src/pages/settings/avatar-decoration.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `openAttachedDecoration(i)`, `detachAllDecorations`, `openDecoration(avatarDecoration)`。
- `packages/frontend/src/pages/settings/connect.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `generateToken`。
- `packages/frontend/src/pages/settings/custom-css.vue`: 入力項目: `localCustomCss`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/settings/deck.vue`: 入力項目: `profilesSyncEnabled`, `changeProfilesSyncEnabled`, `useSimpleUiForNonRootPages`, `navWindow`, `alwaysShowMainColumn`, `columnAlign`, `menuPosition`, `navbarPosition`, `columnGap`。クリック操作: `setWallpaper`, `wallpaper = null`。
- `packages/frontend/src/pages/settings/drive-cleaner.vue`: 入力項目: `sortModeSelect`。クリック操作: `$event => onClick($event, file)`。
- `packages/frontend/src/pages/settings/drive.ImageFrameItem.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `edit`, `del`。
- `packages/frontend/src/pages/settings/drive.vue`: 入力項目: `keepOriginalFilename`, `alwaysMarkNsfw`, `saveProfile()`, `autoSensitive`, `watermarkPresetsSyncEnabled`, `changeWatermarkPresetsSyncEnabled`, `defaultWatermarkPresetId`, `imageFramePresetsSyncEnabled`, `changeImageFramePresetsSyncEnabled`, `defaultImageCompressionLevel`, `defaultVideoCompressionLevel`。クリック操作: `chooseUploadFolder()`, `addWatermarkPreset`, `addImageFramePreset`。
- `packages/frontend/src/pages/settings/drive.WatermarkItem.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `edit`, `del`。
- `packages/frontend/src/pages/settings/email.vue`: 入力項目: `emailAddress`, `$i.receiveAnnouncementEmail`, `onChangeReceiveAnnouncementEmail`, `emailNotification_mention`, `emailNotification_reply`, `emailNotification_quote`, `emailNotification_follow`, `emailNotification_receiveFollowRequest`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/settings/emoji-palette.palette.vue`: 入力項目: `emojis.map(emoji => ({ id: emoji, emoji }))`, `v => emojis = v.map(x => x.emoji)`。クリック操作: `rename`, `copy`, `paste`, `del`, `remove(item.emoji, $event)`, `pick`。
- `packages/frontend/src/pages/settings/emoji-palette.vue`: 入力項目: `palettesSyncEnabled`, `changePalettesSyncEnabled`, `emojiPaletteForMain`, `emojiPaletteForReaction`, `emojiPickerScale`, `emojiPickerWidth`, `emojiPickerHeight`, `emojiPickerStyle`。クリック操作: `addPalette`, `previewPicker`。
- `packages/frontend/src/pages/settings/gridspace.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `resumeSetup`, `refresh`, `start`, `revoke`, `startPrivate`, `retryProfile`, `retryPalette`, `startRecentEmojis`, `startSettings`, `retrySettings`, `runPlayImport(true, playImportError)`, `retry`。
- `packages/frontend/src/pages/settings/index.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `enableStoragePersistence`, `skipStoragePersistence`, `enableAutoBackup`, `skipAutoBackup`。
- `packages/frontend/src/pages/settings/migration.vue`: 入力項目: `accountAliases[i]`, `moveToAccount`。クリック操作: `add`, `save`, `move`。
- `packages/frontend/src/pages/settings/mute-block.emoji-mute.vue`: 入力項目: `syncEnabled`, `changeSyncEnabled`。クリック操作: `onEmojiClick($event, emoji)`, `add`。
- `packages/frontend/src/pages/settings/mute-block.instance-mute.vue`: 入力項目: `instanceMutes`。クリック操作: `save()`。
- `packages/frontend/src/pages/settings/mute-block.vue`: 入力項目: `showSoftWordMutedWord`。クリック操作: `toggleRenoteMuteItem(item)`, `unrenoteMute(item.mutee, $event)`, `toggleMuteItem(item)`, `unmute(item.mutee, $event)`, `toggleBlockItem(item)`, `unblock(item.blockee, $event)`。
- `packages/frontend/src/pages/settings/mute-block.word-mute.vue`: 入力項目: `mutedWords`。クリック操作: `save()`。
- `packages/frontend/src/pages/settings/navbar.vue`: 入力項目: `items`, `menuDisplay`, `showNavbarSubButtons`。クリック操作: `removeItem(item.id)`, `addItem`, `reset`, `save`。
- `packages/frontend/src/pages/settings/notifications.notification-config.vue`: 入力項目: `type`, `userListId`。クリック操作: `save`。
- `packages/frontend/src/pages/settings/notifications.vue`: 入力項目: `sendReadMessage`, `onChangeSendReadMessage`。クリック操作: `showNotifyMenu(item.followee!, $event)`, `readAllNotifications`, `testNotification`, `flushNotification`。
- `packages/frontend/src/pages/settings/other.vue`: 入力項目: `$i.injectFeaturedNote`, `reportError`, `skipNoteRender`, `stackingRouterView`, `enableFolderPageView`, `enableHapticFeedback`, `enableWebTranslatorApi`, `devMode`。クリック操作: `deleteAccount`, `resetAllTips`, `hideAllTips`, `readAllChatMessages`, `enableStoragePersistence`, `forceCloudBackup`。
- `packages/frontend/src/pages/settings/plugin.install.vue`: 入力項目: `code`。クリック操作: `install`。
- `packages/frontend/src/pages/settings/plugin.vue`: 入力項目: `plugin.active`, `changeActive(plugin, $event)`。クリック操作: `reload(plugin)`, `uninstall(plugin)`, `config(plugin)`。
- `packages/frontend/src/pages/settings/preferences.vue`: 入力項目: `lang`, `overridedDeviceKind`, `realtimeMode`, `pollingInterval`, `showTitlebar`, `showAvatarDecorations`, `alwaysConfirmFollow`, `highlightSensitiveMedia`, `confirmWhenRevealingSensitiveMedia`, `advancedMfm`, `enableInfiniteScroll`, `emojiStyle`, `showFixedPostForm`, `showFixedPostFormInChannel`, `collapseRenotes`, `showNoteActionsOnlyHover`, `showClipButtonInNoteFooter`, `showReactionsCount`, `confirmOnReact`, `loadRawImages`, `useReactionPickerForContextMenu`, `showAvailableReactionsFirstInNote`, `reactionsDisplaySize`, `limitWidthOfReaction`, `mediaListWithOneImageAppearance`, `showMediaListByGridInWideArea`, `instanceTicker`, `nsfw`, `keepCw`, `rememberNoteVisibility`, `enableQuickAddMfmFunction`, `defaultNoteVisibility`, `defaultNoteLocalOnly`, `useGroupedNotifications`, `notificationPosition`, `notificationStackAxis`, `chatShowSenderName`, `chatSendOnEnter`, `reduceAnimation`, `disableShowingAnimatedImages`, `animatedMfm`, `showPageTabBarBottom`, `enableHorizontalSwipe`, `enablePullToRefresh`, `keepScreenOn`, `useNativeUiForVideoAudioPlayer`, `makeEveryTextElementsSelectable`, `menuStyle`, `contextMenu`, `fontSize`, `useSystemFont`, `!reduceAnimation`, `v => reduceAnimation = !v`, `!disableShowingAnimatedImages`, `v => disableShowingAnimatedImages = !v`, `useBlurEffect`, `useBlurEffectForModal`, `enableHighQualityImagePlaceholders`, `useStickyIcons`, `dataSaver.media`, `dataSaver.avatar`, `dataSaver.disableUrlPreview`, `dataSaver.urlPreviewThumbnail`, `dataSaver.code`, `squareAvatars`, `autoplayEmbededPlayerOfUrlPreview`, `enableSeasonalScreenEffect`, `imageNewTab`, `defaultFollowWithReplies`, `serverDisconnectedBehavior`, `numberOfPageCache`, `forceShowAds`, `hemisphere`。クリック操作: `setPinnedList()`, `removePinnedList()`, `testNotification`, `enableAllDataSaver`, `disableAllDataSaver`, `removeEmojiIndex(lang)`, `downloadEmojiIndex(lang)`。
- `packages/frontend/src/pages/settings/privacy.vue`: 入力項目: `isLocked`, `save()`, `setting.mode`, `saveFollowApproval(setting)`, `setting.amount`, `scheduleFollowApprovalSave(setting)`, `setting.unit`, `autoAcceptFollowed`, `publicReactions`, `followingVisibility`, `followersVisibility`, `hideOnlineStatus`, `noCrawle`, `preventAiLearning`, `isExplorable`, `chatScope`, `requireSigninToViewContents`, `update_requireSigninToViewContents`, `makeNotesFollowersOnlyBefore_type`, `makeNotesFollowersOnlyBefore_selection`, `makeNotesFollowersOnlyBefore_customMonths`, `formatDateTimeString(new Date(makeNotesFollowersOnlyBefore * 1000), 'yyyy-MM-dd')`, `makeNotesFollowersOnlyBefore = Math.floor(new Date($event).getTime() / 1000)`, `makeNotesHiddenBefore_type`, `makeNotesHiddenBefore_selection`, `makeNotesHiddenBefore_customMonths`, `formatDateTimeString(new Date(makeNotesHiddenBefore * 1000), 'yyyy-MM-dd')`, `makeNotesHiddenBefore = Math.floor(new Date($event).getTime() / 1000)`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/settings/profile.vue`: 入力項目: `profile.name`, `profile.description`, `profile.location`, `profile.birthday`, `profile.lang`, `fields`, `item.name`, `item.value`, `profile.followedMessage`, `reactionAcceptance`, `profile.isCat`, `profile.isBot`。クリック操作: `changeBanner`, `changeAvatar`, `saveFields`, `addField`, `fieldEditMode = !fieldEditMode`, `deleteField(item.id)`。
- `packages/frontend/src/pages/settings/profiles.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `del(backup)`。
- `packages/frontend/src/pages/settings/security.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `change()`, `regenerateToken`。
- `packages/frontend/src/pages/settings/sounds.sound.vue`: 入力項目: `type`, `volume`。クリック操作: `selectSound`, `listen`, `save`。
- `packages/frontend/src/pages/settings/sounds.vue`: 入力項目: `notUseSound`, `useSoundOnlyWhenActive`, `masterVolume`。クリック操作: `reset()`。
- `packages/frontend/src/pages/settings/statusbar.statusbar.vue`: 入力項目: `statusbar.type`, `statusbar.name`, `statusbar.black`, `statusbar.size`, `statusbar.props.url`, `statusbar.props.shuffle`, `statusbar.props.refreshIntervalSec`, `statusbar.props.marqueeDuration`, `statusbar.props.marqueeReverse`, `statusbar.props.colored`, `statusbar.props.userListId`。クリック操作: `del`。
- `packages/frontend/src/pages/settings/statusbar.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `add`。
- `packages/frontend/src/pages/settings/theme.install.vue`: 入力項目: `installThemeCode`。クリック操作: `() => previewTheme(installThemeCode!)`, `() => install(installThemeCode!)`。
- `packages/frontend/src/pages/settings/theme.manage.vue`: 入力項目: `selectedThemeId`, `selectedTheme.author`, `selectedTheme.desc`, `selectedThemeCode`。クリック操作: `copyThemeCode()`, `uninstall()`。
- `packages/frontend/src/pages/settings/theme.vue`: 入力項目: `syncDeviceDarkMode`, `lightThemeId`, `darkThemeId`, `themesSyncEnabled`, `changeThemesSyncEnabled`。クリック操作: `toggleDarkMode()`。
- `packages/frontend/src/pages/settings/webhook.edit.vue`: 入力項目: `name`, `url`, `secret`, `event_follow`, `event_followed`, `event_note`, `event_reply`, `event_renote`, `event_reaction`, `event_mention`, `active`。クリック操作: `test('follow')`, `test('followed')`, `test('note')`, `test('reply')`, `test('renote')`, `test('reaction')`, `test('mention')`, `save`, `del`。
- `packages/frontend/src/pages/settings/webhook.new.vue`: 入力項目: `name`, `url`, `secret`, `event_follow`, `event_followed`, `event_note`, `event_reply`, `event_renote`, `event_reaction`, `event_mention`。クリック操作: `create`。

## 管理テンプレートの入力項目と操作

- `packages/frontend/src/pages/admin/abuses.vue`: 入力項目: `state`, `targetUserOrigin`, `reporterOrigin`, `searchUsername`, `searchHost`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/ads.vue`: 入力項目: `filterType`, `filterItems`, `ad.url`, `ad.imageUrl`, `ad.place`, `ad.ratio`, `ad.startsAt`, `ad.expiresAt`, `ad.isSensitive`, `ad.memo`。クリック操作: `save(ad)`, `remove(ad)`, `more()`。
- `packages/frontend/src/pages/admin/announcements.vue`: 入力項目: `announcementsStatus`, `announcement.title`, `announcement.text`, `announcement.imageUrl`, `announcement.autoArchiveAt`, `announcement.icon`, `announcement.display`, `announcement.forExistingUsers`, `announcement.silence`, `announcement.needConfirmationToRead`。クリック操作: `save(announcement)`, `archive(announcement)`, `unarchive(announcement)`, `del(announcement)`, `more()`。
- `packages/frontend/src/pages/admin/auto-translation.vue`: 入力項目: `config.enabled`, `config.baseUrl`, `config.model`, `apiKey`, `clearKey`, `config.allowPrivateNetwork`, `config.maxConcurrency`。クリック操作: `save`, `testConnection`。
- `packages/frontend/src/pages/admin/bot-protection.vue`: 入力項目: `botProtectionForm.state.provider`, `botProtectionForm.state.hcaptchaSiteKey`, `botProtectionForm.state.hcaptchaSecretKey`, `captchaResult`, `botProtectionForm.state.mcaptchaSiteKey`, `botProtectionForm.state.mcaptchaSecretKey`, `botProtectionForm.state.mcaptchaInstanceUrl`, `botProtectionForm.state.recaptchaSiteKey`, `botProtectionForm.state.recaptchaSecretKey`, `botProtectionForm.state.turnstileSiteKey`, `botProtectionForm.state.turnstileSecretKey`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/branding.vue`: 入力項目: `entrancePageStyle`, `showTimelineForVisitor`, `showActivitiesForVisitor`, `iconUrl`, `app192IconUrl`, `app512IconUrl`, `bannerUrl`, `backgroundImageUrl`, `notFoundImageUrl`, `infoImageUrl`, `serverErrorImageUrl`, `themeColor`, `defaultLightTheme`, `defaultDarkTheme`, `repositoryUrl`, `feedbackUrl`, `manifestJsonOverride`。クリック操作: `save`。
- `packages/frontend/src/pages/admin/custom-emojis-manager.local.list.search.vue`: 入力項目: `model.name`, `model.category`, `model.aliases`, `model.type`, `model.license`, `model.sensitive`, `model.localOnly`, `model.updatedAtFrom`, `model.updatedAtTo`, `queryRolesText`。クリック操作: `onQueryRolesEditClicked`, `onSearchRequest`, `onQueryResetButtonClicked`。
- `packages/frontend/src/pages/admin/custom-emojis-manager.local.list.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `onDeleteButtonClicked`, `onUpdateButtonClicked`, `onGridResetButtonClicked`。
- `packages/frontend/src/pages/admin/custom-emojis-manager.logs.vue`: 入力項目: `showingSuccessLogs`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/custom-emojis-manager.register.vue`: 入力項目: `selectedFolderId`, `directoryToCategory`。クリック操作: `onFileSelectClicked`, `onDriveSelectClicked`, `onRegistryClicked`, `onClearClicked`。
- `packages/frontend/src/pages/admin/custom-emojis-manager.remote.vue`: 入力項目: `queryName`, `queryHost`, `queryLicense`, `queryUri`, `queryPublicUrl`, `queryLimit`。クリック操作: `onSearchRequest`, `onQueryResetButtonClicked`, `onImportClicked`。
- `packages/frontend/src/pages/admin/custom-emojis-manager2.vue`: 入力項目: `headerTab`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/email-settings.vue`: 入力項目: `enableEmail`, `email`, `smtpHost`, `smtpPort`, `smtpUser`, `smtpPass`, `smtpSecure`。クリック操作: `save`, `testEmail`。
- `packages/frontend/src/pages/admin/external-services.vue`: 入力項目: `googleAnalyticsMeasurementId`, `deeplAuthKey`, `deeplIsPro`。クリック操作: `save_googleAnalytics`, `save_deepl`。
- `packages/frontend/src/pages/admin/federation-job-queue.vue`: 入力項目: `tab`。クリック操作: `promoteAllQueues`, `clear`。
- `packages/frontend/src/pages/admin/federation.vue`: 入力項目: `host`, `state`, `sort`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/files.vue`: 入力項目: `origin`, `searchHost`, `userId`, `type`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/gridspace.vue`: 入力項目: `userId`, `issuesOnly`, `kind`, `failedOnly`, `audience`, `title`, `message`, `display`。クリック操作: `refresh`, `retrySharedDrive`, `releaseSharedDrive`, `filterUser(link.localUserId)`, `contact(link)`, `loadLinks()`, `loadLinks(linksNext)`, `loadJobs()`, `retry(job)`, `loadJobs(jobsNext)`, `sendNotice`。
- `packages/frontend/src/pages/admin/invites.vue`: 入力項目: `noExpirationDate`, `expiresAt`, `createCount`, `type`, `sort`。クリック操作: `createWithOptions`。
- `packages/frontend/src/pages/admin/job-queue.job.vue`: 入力項目: `tab`, `editData`。クリック操作: `copyRaw()`, `refresh()`, `promoteJob()`, `moveJob`, `removeJob()`, `loadLogs()`。
- `packages/frontend/src/pages/admin/job-queue.vue`: 入力項目: `tab`, `jobState`, `searchQuery`。クリック操作: `tab = q.name`, `promoteAllJobs`, `createJob`, `resumeQueue`, `pauseQueue`, `clearQueue`, `fetchJobs()`, `removeJobs`。
- `packages/frontend/src/pages/admin/moderation.vue`: 入力項目: `enableRegistration`, `onChange_enableRegistration`, `emailRequiredForSignup`, `ugcVisibilityForVisitor`, `onChange_ugcVisibilityForVisitor`, `preservedUsernames`, `sensitiveWords`, `prohibitedWords`, `prohibitedWordsForNameOfUser`, `hiddenTags`, `silencedHosts`, `mediaSilencedHosts`, `blockedHosts`。クリック操作: `save_preservedUsernames`, `save_sensitiveWords`, `save_prohibitedWords`, `save_prohibitedWordsForNameOfUser`, `save_hiddenTags`, `save_silencedHosts`, `save_mediaSilencedHosts`, `save_blockedHosts`。
- `packages/frontend/src/pages/admin/modlog.vue`: 入力項目: `type`, `moderatorId`。クリック操作: `fetchMore`。
- `packages/frontend/src/pages/admin/object-storage.vue`: 入力項目: `useObjectStorage`, `objectStorageBaseUrl`, `objectStorageBucket`, `objectStoragePrefix`, `objectStorageEndpoint`, `objectStorageRegion`, `objectStorageAccessKey`, `objectStorageSecretKey`, `objectStorageUseSSL`, `objectStorageUseProxy`, `objectStorageSetPublicRead`, `objectStorageS3ForcePathStyle`。クリック操作: `save`。
- `packages/frontend/src/pages/admin/overview.heatmap.vue`: 入力項目: `src`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/performance.vue`: 入力項目: `enableServerMachineStats`, `enableIdenticonGeneration`, `enableChartsForRemoteUser`, `enableStatsForFederatedInstances`, `enableChartsForFederatedInstances`, `showRoleBadgesOfRemoteUsers`, `fttForm.state.enableFanoutTimeline`, `fttForm.state.enableFanoutTimelineDbFallback`, `fttForm.state.perLocalUserUserTimelineCacheMax`, `fttForm.state.perRemoteUserUserTimelineCacheMax`, `fttForm.state.perUserHomeTimelineCacheMax`, `fttForm.state.perUserListTimelineCacheMax`, `rbtForm.state.enableReactionsBuffering`, `remoteNotesCleaningForm.state.enableRemoteNotesCleaning`, `remoteNotesCleaningForm.state.remoteNotesCleaningExpiryDaysForEachNotes`, `remoteNotesCleaningForm.state.remoteNotesCleaningMaxProcessingDurationInMinutes`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/relays.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `remove(relay.inbox)`。
- `packages/frontend/src/pages/admin/roles.edit.vue`: 入力項目: `data`。クリック操作: `save`。
- `packages/frontend/src/pages/admin/roles.editor.vue`: 入力項目: `role.id`, `role.name`, `role.description`, `role.color`, `role.iconUrl`, `role.displayOrder`, `rolePermission`, `role.target`, `role.condFormula`, `role.preserveAssignmentOnMoveAccount`, `role.canEditMembersByModerator`, `role.isPublic`, `role.asBadge`, `role.isExplorable`, `q`, `rolePolicyValues`, `rolePolicyMeta`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/roles.policy-editor.folder.vue`: 入力項目: `useDefaultModel`, `priorityModel`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/roles.policy-editor.vue`: 入力項目: `policyMetaModel.rateLimitFactor`, `valuesModel.rateLimitFactor`, `policyMetaModel.gtlAvailable`, `valuesModel.gtlAvailable`, `policyMetaModel.ltlAvailable`, `valuesModel.ltlAvailable`, `policyMetaModel.vrtlAvailable`, `valuesModel.vrtlAvailable`, `policyMetaModel.canPublicNote`, `valuesModel.canPublicNote`, `policyMetaModel.chatAvailability`, `valuesModel.chatAvailability`, `policyMetaModel.mentionLimit`, `valuesModel.mentionLimit`, `policyMetaModel.canInvite`, `valuesModel.canInvite`, `policyMetaModel.inviteLimit`, `valuesModel.inviteLimit`, `policyMetaModel.inviteLimitCycle`, `valuesModel.inviteLimitCycle`, `policyMetaModel.inviteExpirationTime`, `valuesModel.inviteExpirationTime`, `policyMetaModel.canManageAvatarDecorations`, `valuesModel.canManageAvatarDecorations`, `policyMetaModel.canManageCustomEmojis`, `valuesModel.canManageCustomEmojis`, `policyMetaModel.canSearchNotes`, `valuesModel.canSearchNotes`, `policyMetaModel.canSearchUsers`, `valuesModel.canSearchUsers`, `policyMetaModel.canUseTranslator`, `valuesModel.canUseTranslator`, `policyMetaModel.canCreateChannel`, `valuesModel.canCreateChannel`, `policyMetaModel.driveCapacityMb`, `valuesModel.driveCapacityMb`, `policyMetaModel.maxFileSizeMb`, `valuesModel.maxFileSizeMb`, `policyMetaModel.uploadableFileTypes`, `valuesModel.uploadableFileTypes.join('\n')`, `v => valuesModel.uploadableFileTypes = v.split('\n')`, `policyMetaModel.alwaysMarkNsfw`, `valuesModel.alwaysMarkNsfw`, `policyMetaModel.canUpdateBioMedia`, `valuesModel.canUpdateBioMedia`, `policyMetaModel.pinLimit`, `valuesModel.pinLimit`, `policyMetaModel.antennaLimit`, `valuesModel.antennaLimit`, `policyMetaModel.wordMuteLimit`, `valuesModel.wordMuteLimit`, `policyMetaModel.webhookLimit`, `valuesModel.webhookLimit`, `policyMetaModel.clipLimit`, `valuesModel.clipLimit`, `policyMetaModel.noteEachClipsLimit`, `valuesModel.noteEachClipsLimit`, `policyMetaModel.userListLimit`, `valuesModel.userListLimit`, `policyMetaModel.userEachUserListsLimit`, `valuesModel.userEachUserListsLimit`, `policyMetaModel.canHideAds`, `valuesModel.canHideAds`, `policyMetaModel.avatarDecorationLimit`, `avatarDecorationLimit`, `updateAvatarDecorationLimit`, `policyMetaModel.canImportAntennas`, `valuesModel.canImportAntennas`, `policyMetaModel.canImportBlocking`, `valuesModel.canImportBlocking`, `policyMetaModel.canImportFollowing`, `valuesModel.canImportFollowing`, `policyMetaModel.canImportMuting`, `valuesModel.canImportMuting`, `policyMetaModel.canImportUserLists`, `valuesModel.canImportUserLists`, `policyMetaModel.noteDraftLimit`, `valuesModel.noteDraftLimit`, `policyMetaModel.scheduledNoteLimit`, `valuesModel.scheduledNoteLimit`, `policyMetaModel.watermarkAvailable`, `valuesModel.watermarkAvailable`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/roles.role.vue`: 入力項目: `role`。クリック操作: `edit`, `del`, `assign`, `toggleItem(item.id)`, `unassign(item.user.id, $event)`。
- `packages/frontend/src/pages/admin/roles.vue`: 入力項目: `baseRoleQ`, `policies`。クリック操作: `updateBaseRole`, `create`。
- `packages/frontend/src/pages/admin/RolesEditorFormula.vue`: 入力項目: `typeModelForMkSelect`, `v.values`, `item`, `updated => childValuesItemUpdated(updated)`, `v.value`, `v.sec`, `v.roleId`。クリック操作: `removeSelf`, `addChildValue`。
- `packages/frontend/src/pages/admin/security.vue`: 入力項目: `sensitiveMediaDetectionForm.state.sensitiveMediaDetection`, `sensitiveMediaDetectionForm.state.sensitiveMediaDetectionApiUrl`, `sensitiveMediaDetectionForm.state.sensitiveMediaDetectionApiKey`, `sensitiveMediaDetectionForm.state.sensitiveMediaDetectionTimeout`, `sensitiveMediaDetectionForm.state.sensitiveMediaDetectionMaxImagesPerRequest`, `sensitiveMediaDetectionForm.state.sensitiveMediaDetectionSensitivity`, `sensitiveMediaDetectionForm.state.enableSensitiveMediaDetectionForVideos`, `sensitiveMediaDetectionForm.state.setSensitiveFlagAutomatically`, `disallowUploadWhenPredictedAsPorn`, `emailValidationForm.state.enableActiveEmailValidation`, `emailValidationForm.state.enableVerifymailApi`, `emailValidationForm.state.verifymailAuthKey`, `emailValidationForm.state.enableTruemailApi`, `emailValidationForm.state.truemailInstance`, `emailValidationForm.state.truemailAuthKey`, `bannedEmailDomainsForm.state.bannedEmailDomains`, `ipLoggingForm.state.enableIpLogging`。クリック操作: 変更の監視・フォーム送信等を確認。
- `packages/frontend/src/pages/admin/server-rules.vue`: 入力項目: `serverRules`, `item.text`, `serverRules[index].text = $event`。クリック操作: `remove(item.id)`, `add`, `save`。
- `packages/frontend/src/pages/admin/settings.vue`: 入力項目: `infoForm.state.name`, `infoForm.state.shortName`, `infoForm.state.description`, `infoForm.state.maintainerName`, `infoForm.state.maintainerEmail`, `infoForm.state.tosUrl`, `infoForm.state.privacyPolicyUrl`, `infoForm.state.inquiryUrl`, `infoForm.state.repositoryUrl`, `infoForm.state.impressumUrl`, `pinnedUsersForm.state.pinnedUsers`, `serviceWorkerForm.state.enableServiceWorker`, `serviceWorkerForm.state.swPublicKey`, `serviceWorkerForm.state.swPrivateKey`, `adForm.state.notesPerOneAd`, `urlPreviewForm.state.urlPreviewEnabled`, `urlPreviewForm.state.urlPreviewAllowRedirect`, `urlPreviewForm.state.urlPreviewRequireContentLength`, `urlPreviewForm.state.urlPreviewMaximumContentLength`, `urlPreviewForm.state.urlPreviewTimeout`, `urlPreviewForm.state.urlPreviewUserAgent`, `urlPreviewForm.state.urlPreviewSummaryProxyUrl`, `urlPreviewForm.state.urlPreviewSensitiveList`, `federationForm.state.federation`, `federationForm.state.federationHosts`, `element.software`, `element.versionRange`, `federationForm.state.signToActivityPubGet`, `federationForm.state.proxyRemoteFiles`, `federationForm.state.allowExternalApRedirect`, `federationForm.state.cacheRemoteFiles`, `federationForm.state.cacheRemoteSensitiveFiles`, `proxyAccountForm.state.description`。クリック操作: `federationForm.state.deliverSuspendedSoftware.push({software: '', versionRange: ''})`, `federationForm.state.deliverSuspendedSoftware.splice(index, 1)`, `openSetupWizard`。
- `packages/frontend/src/pages/admin/system-webhook.item.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `onEditClick`, `onDeleteClick`。
- `packages/frontend/src/pages/admin/system-webhook.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `onCreateWebhookClicked`。
- `packages/frontend/src/pages/admin/users.vue`: 入力項目: `sort`, `state`, `origin`, `searchUsername`, `searchHost`。クリック操作: `resetQuery`。

## 管理の詳細画面と子テンプレート

- `packages/frontend/src/pages/admin-user.vue`: 入力項目: `tab`, `moderationNote`, `suspended`, `toggleSuspend`, `announcementsStatus`, `chartSrc`。クリック操作: `updateRemoteUser`, `resetPassword`, `unsetMfa`, `unsetUserAvatar`, `unsetUserBanner`, `deleteAccount`, `assignRole`, `toggleRoleItem(role)`, `unassignRole(role, $event)`, `createAnnouncement`, `editAnnouncement(announcement)`。API: `users/show`, `admin/show-user`, `admin/get-user-ips`, `admin/update-user-note`, `federation/update-remote-user`, `admin/reset-password`, `admin/unset-mfa`, `admin/unset-user-avatar`, `admin/unset-user-banner`, `admin/delete-all-files-of-a-user`, `admin/delete-account`, `admin/roles/list`, `admin/roles/assign`, `admin/roles/unassign`, `ap/get`。
- `packages/frontend/src/pages/admin-file.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: 子コンポーネント等を確認。API: `drive/files/show`, `admin/drive/show-file`。
- `packages/frontend/src/pages/admin/abuse-report/notification-recipient.editor.vue`: 入力項目: `title`, `method`, `userId`, `systemWebhookId`, `isActive`。クリック操作: `onEditSystemWebhookClicked`, `onSubmitClicked`, `onCancelClicked`。API: `admin/abuse-report/notification-recipient/create`, `admin/abuse-report/notification-recipient/update`, `admin/system-webhook/list`, `admin/show-users`, `admin/abuse-report/notification-recipient/show`。
- `packages/frontend/src/pages/admin/abuse-report/notification-recipient.item.vue`: 入力項目: 子コンポーネント等を確認。クリック操作: `onEditButtonClicked()`, `onDeleteButtonClicked()`。API: 子コンポーネント等を確認。
- `packages/frontend/src/pages/admin/abuse-report/notification-recipient.vue`: 入力項目: `filterMethod`, `filterText`。クリック操作: `onAddButtonClicked`。API: `admin/abuse-report/notification-recipient/delete`, `admin/abuse-report/notification-recipient/list`。

## 子画面と証拠の限界

`settings/migration.vue` と `settings/2fa.vue` は親の設定画面に含まれ、単独のルートを持たない。`admin/bot-protection.vue`、`admin/server-rules.vue`、`admin/roles.editor.vue`、`admin/roles.policy-editor.vue`、通報受信先の編集画面も同様に確認する。ルートがないことを理由に不要と判定しない。

一覧のコードパスと行番号は調査対象のコミットに対応する。今後の更新で行番号が変わるため、実装開始時にコミットとパスを照合する。ソース中に操作があることは確認できるが、本番で有効かどうか、既存の不具合、WKWebViewの対応状況、iOS側での表示・性能はこの調査では確定していない。目標方式と段階は実装案であり、対応できると実証した結果ではない。
