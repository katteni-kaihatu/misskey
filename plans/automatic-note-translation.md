# 常時翻訳の実装と運用

更新日: 2026-11-07 JST。対象: `resonite-master` の `f683929d70` から作成した `codex/always-translation`。リリース対象は `2026.10.0-resonite-love.1`。

## 使い方

1. 通常のMisskey更新手順で、この変更をビルド・配置して新規migrationを適用する。
2. 管理画面の「常時翻訳」(`/admin/auto-translation`) を開く。
3. APIの接続先を `http://192.168.10.86:8766/v1`、モデルIDを `plamo-translate-0.8b-q2` に設定する。
4. PLaMo側のBearer APIキーを入力し、「LAN・VPN内の接続先とHTTP接続を許可する」をオンにする。同時翻訳数の初期値は16。
5. 「保存して接続を確認」で、認証とモデル一覧を確認する。常時翻訳を有効にして保存する。
6. 各ユーザーが設定の「常時翻訳」(`/settings/auto-translation`) で機能をオンにし、翻訳先を選ぶ。初期状態はオフ、翻訳先は日本語。

APIキーはこの文書へ記載しない。PLaMoの既存Webパネルや公開範囲、本番Misskeyの設定は今回変更していない。現在のMisskeyホストからはLAN経由で到達できるため、Cloudflare Tunnelは必須ではない。

## 構成

```text
表示中の投稿 → MkAutoTranslatedNote → Misskey専用API
                                      → 閲覧権限・利用ポリシー確認
                                      → 言語判定・Redisキャッシュ・同時実行制限
                                      → PLaMo API
```

既存DeepLのAPI (`notes/translate`)、設定画面、`translatorAvailable`、手動翻訳メニューは変更していない。既存ファイルの変更は、専用機能の登録、メニュー、投稿表示への接続が中心。

| 用途 | 実装 |
| --- | --- |
| 利用可否・対応言語 | `auto-translation/capabilities` |
| 投稿の翻訳 | `auto-translation/translate-note` (`noteId`, `targetLang`) |
| 管理者設定 | `admin/auto-translation/get-config`, `update-config`, `test-connection` |
| 設定の保存 | `auto_translation_config` テーブル。新規migrationあり |
| ユーザー設定 | `autoTranslation.enabled`, `autoTranslation.targetLang`。アカウント別preferences |
| 専用表示 | `MkAutoTranslatedNote.vue`。タイムライン、詳細、引用、返信へ接続 |

バックエンドの処理は `packages/backend/src/core/auto-translation/`、フロントエンドの通信処理は `packages/frontend/src/utility/auto-translation.ts` にまとめた。接続先はPLaMo Translate向けで、OpenAI互換のchat completionsに `chat_template_kwargs.target_lang` などを渡す。他のOpenAI互換サービスすべてに対応する汎用翻訳アダプターではない。

## 動作と制限

- ログインと既存の `canUseTranslator` ポリシーが必要。キャッシュを返す前にも投稿の閲覧権限と非表示状態を確認する。
- 言語判定はバックエンドで行う。同じ言語と判定できた場合はモデルを呼ばない。短文や混在文など判定が不確かな場合は翻訳を試す。言語判定は推定であり、完全ではない。
- ブラウザでは表示領域内の投稿を対象とし、閉じたCWの本文は開くまで要求しない。ブラウザ内の同時要求は2、サーバー全体の同時処理は1〜16に制限する。
- 同じ投稿への要求はまとめる。Redisキャッシュのキーには投稿ID、本文、CW、翻訳先、接続設定のリビジョンを含め、有効期間は1時間。
- サーバーの待ち時間は最大30秒。待機する別ジョブは最大64件。翻訳APIはユーザーごとに毎分120回まで。
- 原文は書き換えない。翻訳済み表示では原文へ切り替えられる。失敗時や途中で切れた訳文は採用せず、原文を表示する。
- URL、メンション、カスタム絵文字、コード、MFMの記号などを保護する。モデルが保護記号を消したり並べ替えたりした場合も原文を表示する。
- 実機のPLaMo 0.8B Q2では通常文の翻訳を確認した。複雑な入れ子のMFMでは保護記号を維持できない例があり、その投稿の自動翻訳は失敗扱いになる。翻訳品質はモデルに依存する。
- 既存の本文表示への接続に限定し、投票の選択肢や画像内の文字、UI全体は翻訳しない。

## 認証と接続

管理者用APIは管理者権限が必要。保存したAPIキーの値は管理者向け取得APIにも返さず、設定済みかどうかだけを返す。空欄での保存は既存キーを維持し、明示的な削除スイッチで削除できる。更新時の例外にもキーやSQLのパラメーターを含めない。

ブラウザはPLaMoへ直接接続しない。接続先は管理者設定に固定し、HTTP/HTTPS以外、URL内の認証情報・クエリー・フラグメントを拒否する。リダイレクトは禁止。応答は最大1 MiB、タイムアウトあり。LAN接続の許可はこの機能だけに適用し、Misskey全体のSSRF対策は変更しない。

将来Tunnelを使う場合も、PLaMo側の `/v1/*` だけを中継し、同じホストにある認証なしWebパネルや `/api/translate` を公開しない。今回の設定で扱う認証はBearerキー。Cloudflare Accessのサービス資格情報は未対応。

## 検証

- PASS: バックエンドunit 14件、API e2e 5件、フロントエンドunit/component 7件。
- PASS: 全体ビルド (`pnpm build`)、backend型チェック、API型の再生成、新規migrationのdown/up、migrationのスキーマ整合性。
- PASS: 変更ファイルのESLint、locale安全検査。API・Vue専用レビューで見つかった修正を反映。
- PASS: PLaMo実APIへの合成テキストによる疎通・翻訳。複雑なMFMでの失敗も確認し、原文へ戻す設計で扱う。
- BASELINE: リポジトリ全体のfrontend型チェックには既存のカスタムウィジェットなどのエラーがある。SPDX検査には既存12ファイルのヘッダー欠落がある。今回の変更とは別であり、これらは修正していない。

CHANGELOG候補: 「PLaMo対応の常時翻訳を追加。管理者が接続先を設定し、ユーザーが翻訳先と自動翻訳の有効・無効を選べるようにしました。」
