# Even G2クライアント向けのMisskey側準備計画

作成日: 2026-11-27

状態: `2026.11.1-grid-space.3`として本番反映済み。初版はホームタイムラインと通知の閲覧を対象にする。[リリース記録](even-g2-client-release.md)を参照。

実装の起点は本番稼働中の`a964a69bc0aa6618674cafa0f79faeceabbd8565`（`2026.11.1-grid-space.2`）。計画作成時より新しい修正を含むため、元のチェックアウトからこのコミットへ作業の起点を移した。

実装したAPIの利用方法は[GridSpace external reader API](../docs/gridspace-client-api.md)に記載した。以下の計画との差異として、初版では`includePrivate: false`のとき連携先の追加取得を行わず、ローカルに存在する投稿を既存の可視性判定で返す。通常のActivityPub経由の限定投稿も含む。連携先の追加取得は、追加権限と`includePrivate: true`を要求する。

ローカル検証では関連4スイートの94件とHTTP経由の6件が通過した。SDK再生成、サーバー本体の型チェックも通過した。テスト用プロジェクトの型診断77件は起点コミットでも再現し、行番号を除いた診断の内容と件数が一致した。

## 目的

Even G2用アプリが権限を限定したアプリ用トークンで、このMisskeyのホームタイムラインと通知を取得できるようにする。ユーザー本人のログイントークンや、GridSpaceのサーバー間通信用トークンをアプリへ渡さない。

通常のMisskey APIとMiAuthは既存実装を使う。今回の追加対象はGridSpaceを含む閲覧機能を外部アプリから利用するためのAPIと権限判定である。API名と新しい権限名はこの計画での提案であり、既存仕様ではない。

## 現状と根拠

| 確認した実装 | 計画への影響 |
| --- | --- |
| [gridspace/timeline](../packages/backend/src/server/api/endpoints/gridspace/timeline.ts)、[gridspace/notifications](../packages/backend/src/server/api/endpoints/gridspace/notifications.ts)は`secure: true` | 既存の内部用APIをそのまま外部アプリから呼ぶことはできない |
| [ApiCallService](../packages/backend/src/server/api/ApiCallService.ts)は`secure`とアプリの権限を検証する | この共通判定を維持し、新しいAPIにも権限を設定する |
| [GridspaceTimelineService](../packages/backend/src/core/gridspace/timeline/GridspaceTimelineService.ts)と[GridspaceNotificationService](../packages/backend/src/core/gridspace/GridspaceNotificationService.ts)に統合処理がある | 投稿取得・統合・可視性判定を新しく複製しない |
| [GridspaceLinkService](../packages/backend/src/core/gridspace/GridspaceLinkService.ts)に閲覧許可、失効確認、サーバー間トークンの一般API利用を拒否する処理がある | アプリの許可と連携先の許可を別々に検証する |
| [timeline-protocol](../packages/backend/src/core/gridspace/timeline/timeline-protocol.ts)に期限・再検証間隔・取得元の状態がある | 外部アプリにも期限と部分的な取得失敗を伝える |
| [gridspaceTimeline](../packages/backend/src/server/api/stream/channels/gridspace-timeline.ts)はアプリ用トークンを拒否する | 初版はHTTPで取得し、WebSocket対応は後続の作業にする |
| [i/notifications](../packages/backend/src/server/api/endpoints/i/notifications.ts)は`markAsRead`の既定値が`true` | 読み取り用APIでは取得と既読化を分ける |
| [ApiServerService](../packages/backend/src/server/api/ApiServerService.ts)にはCORS設定がある | CORS変更を前提にせず、実際のHTTPS配信経路で確認する |

調査対象はこのチェックアウトであり、本番環境との一致は未確認。

## 初版の範囲

- MiAuthでアプリ用トークンを取得する。新しいログイン方式は作らない。
- 自分のホームタイムラインを取得し、ページ送りと再取得に対応する。
- ローカル、連携先、チャンネル由来の通知を、指定した取得元から読む。
- 連携先の限定投稿は、アプリへの明示的な許可と現在有効なGridSpaceの閲覧許可が両方ある場合だけ返す。
- ブロック、ミュート、公開範囲、アカウント停止、投稿削除などの既存判定を適用する。
- 通知の取得では既読状態を変更しない。
- スマホ側の停止後は再認証・再取得できる契約にする。サーバーがG2への常時通知を保証する仕様にはしない。

投稿・返信・リアクション・通知の既読化、検索、プロフィール、独立したチャンネル一覧、WebSocket配信、音声認識、G2の表示処理は後続の作業とする。ホームに含まれるチャンネル投稿の扱いは既存の統合ルールに従う。

## APIと権限の案

既存の内部用APIは変更せず、`/api/gridspace/client/`配下に読み取り用APIを追加する。G2固有の名前や画面寸法をAPIに含めず、用途と許可範囲を定義する。

| API案 | 基本権限案 | 役割 |
| --- | --- | --- |
| `gridspace/client/status` | `read:account` | APIのバージョン、アプリが利用できる閲覧機能、連携先の利用可否を返す |
| `gridspace/client/timeline` | 新設`read:gridspace-client-timeline` | 自分のホームタイムラインを返す |
| `gridspace/client/notifications` | 新設`read:gridspace-client-notifications` | ローカル・連携先・チャンネル由来の通知を読み、既読化しない |

連携先の限定投稿を読む場合は、新設`read:gridspace-client-private`も要求する。通知内の限定投稿、引用、リノート、添付情報にも適用する。既存のサーバー間連携用スコープと分け、同意画面でG2アプリに何を許可するかを説明する。

### 認可の条件

1. エンドポイントの基本権限を共通API処理で検証する。
2. リクエストの取得元と、必要な追加権限を検証する。
3. 連携先の閲覧許可、通知の許可、チャンネルの所属・代理アクセス資格を、取得対象に応じて検証する。
4. 既存サービスで対象データの可視性を確認する。本文を返す前にも失効を確認する。

ユーザーID、連携先URL、実効権限をリクエストから信用しない。ログインユーザーとサーバー設定から決める。サーバー間用トークンを、外部アプリ用APIから別の閲覧許可に乗り換えるために使わせない。

限定投稿を要求したのにアプリの追加権限がない場合は、権限不足として扱う。連携が未設定・失効している場合は取得元の状態で区別する。ローカルの結果を返せる場合も、連携先を取得できなかったことを明示する。権限のない投稿の本文、件数、識別子を返さない。

### リクエストとレスポンス

- タイムラインの種類は初版では`home`に固定する。プロフィール検索など、内部APIの全フィルターを開放しない。
- `limit`、ページ送り用カーソル、限定投稿を含めるかを受け付ける。件数の既定値・上限は既存実装と負荷計測を基に確定する。
- 通知の取得元は`local`、`peer`、`channel`で指定する。各取得元の権限と利用条件を別々に検証する。
- 投稿本文、CW、投稿者、投稿時刻、公開範囲、取得元、同一投稿を判別するキーを返す。表示用の切り詰めやMFMの簡略化はアプリ側で行う。
- ページ送り、取得元ごとの状態、再取得までの間隔、限定情報の表示期限を返す。既存の`validForMs`、`nextPolicyCheckAt`、`revalidateAfterMs`の意味を引き継ぐ。
- `status`は許可された機能だけを返す。トークン、連携許可の開始用URL、`clientKey`などの内部情報は含めない。
- 期限切れの限定情報は再検証に成功するまでアプリ側で非表示にする。この要件を利用手順にも記載する。
- HTTPエラーは既存の形式を使い、認証失効、権限不足、カーソル無効、連携先不通を区別する。

### カーソルとキャッシュ

現在のタイムラインセッションを外部アプリ向けに利用する前に、利用者だけでなくアプリの実効権限も識別できるようにする。同じユーザーが使う別トークンや、権限変更前のカーソルから、より広い範囲の結果を取得できないことを確認する。

実効権限はサーバーで構築し、投稿の取得と統合の段階から適用する。取得後に画面から隠すだけの実装にはしない。カーソル、キャッシュ、取得中の処理で権限が失効した場合は、失効前の本文を再利用しない。

認証付きレスポンスには`Cache-Control: private, no-store`を設定する。現在の専用ヘッダー設定はURLパターンを使うため、新しい`client/`経路にも適用されることを確認する。

アプリに取得済みの情報をサーバーから消すことはできないため、限定情報を永続保存しないこと、失効や再検証の失敗時に表示を消すこともアプリ側の要件にする。

## 実装順序

| 段階 | 作業 | 完了条件 |
| --- | --- | --- |
| 1. 認証と契約 | 新しい権限、同意画面の説明、APIスキーマ、状態・エラーの定義を追加 | 必要な権限を要求したMiAuthトークンを発行でき、権限不足を拒否できる |
| 2. ホーム閲覧 | 認可を行うサービスと`client/status`、`client/timeline`を追加 | 許可されたホーム投稿だけを取得・ページ送りできる |
| 3. 通知と限定投稿 | `client/notifications`、追加権限、連携先の失効確認を追加 | 各取得元を読み取れ、既読化せず、許可のない限定情報を返さない |
| 4. クライアントへの提供 | misskey-js再生成、HTTP経由の検証、利用手順と例を追加 | 実際のアプリ用トークンで取得でき、認証・失効・再取得の手順がそろう |

段階2では連携先の限定投稿を返さない。段階3の失効検証まで通してから、追加権限による閲覧を有効にする。新しい機能がない場合も既存Webクライアントの動作を維持する。

## 変更箇所の見込み

- `packages/backend/src/server/api/endpoints/gridspace/client/`: 上記の3エンドポイント。
- `packages/backend/src/core/gridspace/`: 外部アプリの認可を行うサービスとレスポンススキーマ。
- `packages/backend/src/core/CoreModule.ts`: 追加するサービスのDI登録。
- 既存のタイムライン・通知サービス: 信頼できる実効権限を受け取るための最小限の変更。内部クライアントの既定動作を維持する。
- `packages/backend/src/server/api/endpoint-list.ts`: エンドポイント登録。
- `packages/backend/src/server/api/ApiServerService.ts`: 新しい経路のキャッシュ抑止。
- `packages/misskey-js/src/consts.ts`: 権限名。`src/autogen/`は生成コマンドで更新する。
- `locales/ja-JP.yml`: 権限の説明。他言語のlocale YAMLは手動編集しない。
- backendのunit/e2eテスト、API利用手順。

新しいDBテーブルやカラムは現時点では不要と見込む。実装時に永続化が必要になった場合は、この計画を更新して新規migrationを追加する。

## 必須の検証

| ケース | 期待する結果 |
| --- | --- |
| 未認証、無効・失効済みトークン、基本権限なし | データを返さない |
| ホームだけの許可 | 通知APIと限定投稿の要求を拒否する |
| 限定投稿の許可なし | 本文だけでなく引用・添付・通知内の限定情報も返さない |
| アプリの追加許可あり、連携先の許可なし | 連携先の限定情報を返さない |
| 他ユーザー・別トークン・旧権限のカーソル | 権限を越えて再利用できない |
| 取得中にアプリ権限または連携許可が失効 | 応答前に確認し、失効した情報を返さない |
| ブロック・ミュート・削除・非公開化 | 既存の可視性判定が継続して働く |
| サーバー間用トークンで一般APIを呼ぶ | 既存の呼出元制限を維持する |
| 連携先不通、片側のみ成功、カーソル期限切れ | 状態を区別でき、再取得で復帰できる |
| 通知を取得する | 取得前後で既読状態が変わらない |
| 既存Webクライアント | 内部APIと既存のホーム・通知の動作が変わらない |
| 認証付きHTTP応答 | CORS・プリフライトが通り、共有キャッシュに保存されない |

認可を行うサービスのunitテストに加え、実際のHTTP認証処理を通すe2eテストを用意する。関連する既存テストは`GridspaceTimelineService.test.ts`、`notifications.test.ts`、`link-all.test.ts`などから選ぶ。

実装完了時に、少なくとも次を実行する。

1. `.config/test.yml`を用意し、変更に近いbackend unit/e2eテストを実行する。
2. `pnpm build-misskey-js-with-types`で生成物を更新する。
3. `pnpm --filter backend typecheck`を実行する。
4. `node scripts/check-shipping.mjs --base <実装開始時のコミット>`で変更ファイルのlint、SPDX、locale safetyを確認する。
5. DBスキーマを変更した場合だけ、migrationの`up`/`down`と`pnpm --filter backend check-migrations`を確認する。

API変更はリポジトリ指定のAPIレビューを受ける。実装時にはbackendスキル、権限説明を編集するときはfrontendスキル、完了時にはshippingスキルに従う。

## Misskey側の準備完了条件

- MiAuthで発行したアプリ用トークンにより、許可されたホーム・通知を取得できる。
- 限定投稿への許可とその失効をHTTP経由で検証できる。
- APIの型、エラー、カーソル、部分失敗、再取得、表示期限をクライアント開発者が確認できる。
- HTTPS接続先と必要な権限の一覧があり、G2アプリ側の接続先登録に使える。
- G2実機がなくてもMisskey側の検証を完了できる。実機での日本語表示・画面ロック中の動作確認はアプリ側の工程で行う。

本番反映、Even Hubへのアップロード、アプリの配布はこの計画作成には含めない。
