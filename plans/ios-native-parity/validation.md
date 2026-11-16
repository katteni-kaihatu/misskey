# 調査資料の検証と実装時の受入条件

対象: `f1bd2e3c4bebf931be8c49342691f03e3cdeb49b`、2026-11-15。ここでのPASSは調査資料の整合性を確認したことを表し、iOSでの互換性が確認できたという意味ではない。

## 今回確認する項目

| 検査 | 状態・内容 |
|---|---|
| 静的索引の再生成 | PASS。TypeScript ASTで再抽出し、同一コミットのJSONと全体一致 |
| 抽出数 | PASS。ルート162、設定122、状態26、ウィジェット37、ナビゲーション25、ページ259、個別起動7 |
| 詳細表 | PASS。日常176行、PWA基盤35行、GridSpace31行。各IDの一意性と欠落を検査 |
| 参照整合 | PASS。265ソースハッシュ、200コンポーネント参照、618ローカルリンク。Markdown表の列数不整合0件 |
| 意味のレビュー | PASS。認証・UGC・通知・ファイル・共有状態の計画を別担当がレビューし、実装順や二重実行の問題を修正 |
| 日本語 | PASS。yomiyasuの資料照合・lint、natural-japaneseの技術文書lintを実行。専門語の反復と比較表は意味保持のため残した。これは内容の正しさを自動保証しない |
| リポジトリ安全性 | PASS。基準コミットを指定した`check-shipping.mjs`と`check-spdx.mjs`が成功。SPDX 2933ファイル、ロケールの安全検査に合格。対象コードのlintはSKIPPED |
| アプリの動作試験 | SKIPPED。実装を変更しておらず、iOSプロジェクトもまだ作成していない |
| 本番/外部サービス | SKIPPED。個人アカウント、稼働設定、機能フラグ、外部ウィジェットのサービスには接続していない |

## 再調査コマンド

リポジトリの依存関係を導入した環境で実行する。抽出ツールはアプリのコードを実行しない。出力先は一時ファイルを推奨する。

```powershell
node plans/ios-native-parity/collect-source-inventory.mjs --root . --output "$env:TEMP/gridspace-ios-current-inventory.json"
node --check plans/ios-native-parity/collect-source-inventory.mjs
node scripts/check-shipping.mjs --base f1bd2e3c4bebf931be8c49342691f03e3cdeb49b
node scripts/check-spdx.mjs
```

JSONのソースハッシュ・ルートの条件式・ウィジェット登録・設定キーを比較し、増減や既存の挙動の変更を詳細表に反映する。新しいルートがWで開けることと、既存のN画面が新しい仕様に追従していることは別々に確認する。

## 実装時に作る比較環境

[README](README.md)のS0-2で、合成データを持つ同一サーバーをPWA/Web互換モード/ネイティブの3方式から操作する。実ユーザーの投稿や秘密情報はテストデータへコピーしない。一般利用者・管理者・モデレーター・未ログイン・移行済み・連携済み/撤回済みの状態を用意する。

各機能行に次を記録する。

| 項目 | 記録する値 |
|---|---|
| ID | 日常D-*、基盤P*、GridSpace G*、widget ID、route ID、設定キー |
| 方式 | N/H/W、表示を切り替える条件 |
| ケース | 成功、取消、権限拒否、連携先の停止、ネットワーク障害、復帰 |
| 出力 | UI、投稿ペイロード、加工済み画像、保存データ、イベント、対象アカウント |
| 実行環境 | アプリ/Web/サーバーのバージョン、iOSバージョン、端末、言語、ロール |
| 結果 | PASS/FAIL/未実行、証拠、未解決事項、担当、実装PR |

全件を同じ大きさのテストにしない。独立した長い操作は統合試験とし、設定データの往復やソース一覧の差分はデータ駆動で検査する。Webの既存の単体/e2eテストは、既存機能を壊していないことの確認に用いる。iOSの試験の代わりにはしない。

## 比較試験セット

- **AUTH**: Webの正規ログイン、MiAuthの範囲、secure API、CAPTCHA、TOTP/バックアップコード、パスキー、再認証、別ホスト/別アカウント、ログアウト、トークン失効。
- **NAV**: 162ルートの実体URL、query/fragment/redirect、未知のルート、共有、通知からの起動、外部URL、戻る、画面窓、完全Webモード、セーフモード。
- **STATE**: 設定122と状態26の全キー、未認識のキー、クラウドでの同時変更、localStorage/IndexedDBの移行、Script/Playの保存、VRM blob、下書き、プロセス終了。
- **NOTE**: 全TL種別/フィルター、複合ページング、順序/重複、MFMの全分岐、投票、CW、NSFW、絵文字、拡張リアクション、翻訳、メニュー。
- **POST**: 新規/返信/引用/宛先/チャンネル/ペア、添付16枚までの現行条件、投票、公開範囲、位置付きの下書き、加工、圧縮、トークン切替、結果不明。
- **UPLOAD**: Photos/Files/カメラ、複数ファイルの順序、iCloudの遅延、取消、メモリ、透かし、フレーム、EXIF/回転、動画変換、音声/3D、私有アップロード、共有Drive。
- **UGC**: ウィジェット37種、AsUi14種、プラグイン6種と旧名のエイリアス、新旧AiScript、null/例外/後続のコールバック、二重起動、副作用の結果不明、Web表示への退避。
- **SOCIAL**: プロフィール内の子タブ、フォロー/承認、ミュート/ブロック、リスト/アンテナ/クリップ、チャンネル、チャット/ルーム/招待、ギャラリー、ゲーム/レジストリ。
- **PUSH**: 通知20種、アンテナ/チャット/既読、複数アカウント、イベントの重複、別PWAの購読維持、無効な端末、権限がない場合、タップ後の正しい参照先。
- **PRIVATE**: 全私有モード、アクセス許可の不足/撤回、可視性変更、バックグラウンドでの本文/画像の破棄、復帰時の再認可、キャッシュ/スナップショットから流出しないこと、古い応答の破棄。
- **ADMIN**: 全管理画面の閲覧・入力・保存・取消・権限、破壊的な操作の確認、秘密値を復元やログに出さないこと、連携先の管理。
- **UX**: 60Hz/120Hz、スクロール、画像の先読み、キーボード/IME、VoiceOver、Dynamic Type、Reduce Motion、ダークモード、縦横/iPad、操作待ち。

PWAで現在未実装の`Ui:patch`、旧動的Pages、未保証の完全オフライン閲覧を、既存の機能として数えない。現行のバグは基準動作と意図を分けて記録し、自動的に機能削除の理由にはしない。

## iOS実装の検証記録

2026-11-15。Xcode 27.2（27B52）、iPhone 16 / iOS 27.2.1（24B156）で実施。実機の名前・UDID・開発チーム・認証情報は記録しない。以下のPASSは記載した合成データのケースに限定し、段階全体やWeb機能全体の互換性完了とは扱わない。

この節は実施時点ごとの履歴であり、冒頭の表は初回の結果。追加の修正・再試験は下へ追記する。現在の段階と残件は[実装・受入状況](implementation-status.md)を参照する。

| 対象 | 結果・範囲 |
|---|---|
| S1-1 SDK/実機 | PASS。署名付きビルド、インストール、通常起動。シミュレーター向けSDKビルドも成功。シミュレーターのUIテストは起動停滞のため未確認 |
| iOS CI | 追加。変更パスを限定したMacジョブで同じ`check-mac.sh`を実行。GitHub上のジョブは未実行 |
| Core単体テスト | PASS、15件。origin/ルート、外部遷移方針、ファイル名のパス・UTF-8制約、交渉スキーマ、不明な操作、バージョン/epoch不一致 |
| 実機アプリ内テスト | PASS、12件。WebKit delegate、ダイアログの安全な既定応答、外部origin/iframeのブリッジ拒否、順序付きプロバイダー読出し、コピー・取消後の削除、選択ファイル/ディレクトリ内のsymlink拒否、合成ファイルのFile入力への受渡しとバイト列一致、古いpopover終了通知の拒否、写真プロバイダーの二重完了と取消時の応答保証 |
| 実機UIテスト | PASS、4件。HTTPサーバー指定拒否、capabilities/ready交渉とJSダイアログ、添付メニュー取消後の再選択、バックグラウンド移行後の取消・再選択 |
| S1-3 認証 | 部分確認。通常起動・再インストール後も既存Webのログインを保持し、指定アカウントの画面を表示。新規ログイン、アカウント切替、TOTP/パスキー/CAPTCHA/再認証は未確認 |
| S1-4 交渉 | 部分実装。Swift Codable、JSON Schema、メインフレーム用JS bootstrap、入力制限。認証epoch/session.changed、データ移行、認証・下書き・プラグイン操作は未実装 |
| S2-1 添付 | 部分実装。iOS 18.4以降のPhotosUI/カメラ/Filesのopen-panelアダプター。一時ファイル経由で既存WebのFile入力へ接続。iOS 16–18.3は標準UIを維持。承認された合成PNGの写真→Web添付→既存アップローダー→ドライブ一覧到達を手動確認。iCloud遅延、大容量、撮影、加工・投稿、UGC内入力の全比較は未完了 |
| S2-2 書き出し | 部分確認。ローカル合成PNGのBlobダウンロード→ネイティブ共有シート→写真追加を実機で確認。Share Extension、設定/バックアップコード全形式の比較は未完了 |
| テストの隔離 | 専用UserDefaultsと非永続Webデータストア、DEBUG限定合成HTMLを使用。自動テストだけUIKitアニメーションを無効化。実アカウントのデータを複製せず、外部へ投稿しない |
| 修正した不具合 | SDKのdelegateコールバック型、テストターゲットのInfo.plist生成不足、popover取消時の要求解放、読み込み用UIAlertControllerのpresentation delegate変更による実機クラッシュと表示/終了の競合、古い選択画面の終了通知による取消、完了済みPhotos取得の取消によるcontinuation二重完了クラッシュ |
| 出荷検査 | PASS（今回の未commit差分、`--base HEAD`）。SPDX/locale safety、lint対象なし。既存ブランチ全体の多言語locale差分は今回の変更に含めない |

実機UIテストはミラーリングを終了して実行する。接続中はXCTestのキー入力が空になったため、各URL入力直後の値もassertする。Xcodeがロック解除を求めた場合は利用者に操作してもらい、ロック解除を迂回しない。

実機テスト結果はローカルの`apps/ios/DerivedData/Logs/Test/*.xcresult`へ保存する。個人の開発プロファイルや端末診断をGitへ追加しない。実サーバーでは既存ログインの再起動後の保持、タイムラインと投稿フォーム、PhotosUIの取消、許可された合成PNGのドライブ到達を手動確認した。新規ログイン全経路・全ルート・UGC・私有データ破棄・写真形式全般の結果は、上の限定したPASSから推定しない。ノート投稿は行わず、試験画像1枚は写真とドライブへ残した。

### S1の公開失効通知を追加した検証

同日、同じ実機で追加確認。Webアダプターはリポジトリ内の実装であり、実サーバーには未配布。以下は認証操作の全互換性やS1完了を示さない。

| 対象 | 結果・範囲 |
|---|---|
| Core | PASS、17件。従来15件に加え、失効通知のhost/epoch照合・新nonce・不正ID/余分な資格情報フィールドの拒否 |
| SDKビルド | PASS。`check-mac.sh`でSimulator向けビルド |
| 実機のセッション統合 | PASS、`WebSessionControllerTests`の5件。通知の応答前に添付選択を取消、旧epoch拒否、子窓のデータストア保持・handler分離・親epoch失効を含む。結果: `Test-GridSpace-2026.11.15_22-48-00-+0900.xcresult` |
| 実機UI | PASS、`CompatibilityTests`の3件。交渉・ダイアログ、添付取消、バックグラウンド取消。結果: `Test-GridSpace-2026.11.15_22-46-41-+0900.xcresult` |
| Web単体・認証保存の境界 | PASS、3ファイル12件。通常Web/旧アプリ、通知の順序と入力制限、切替前待機、失敗時の保存停止、期限切れ・遅延応答、ログアウト・認証失効での資格情報削除継続。`pnpm --filter frontend test test/unit/ios-native-session.test.ts test/unit/ios-native-account-switch.test.ts test/unit/ios-native-signout.test.ts` |
| Webの型検査 | 新しい通知処理とその単体テストの`tsc --strict --noEmit`はPASS。全体`vue-tsc --noEmit`はBASELINE: 既定ヒープではメモリ不足、8 GiB設定では既存の80診断で失敗。隔離したHEADではsrc配下81診断を再現し、今回のsrc配下80診断はすべてその集合に含まれる。変更したファイルの診断なし |
| Webテスト環境の警告 | 共有setupからlocalhost:3000への接続拒否ログとVite設定の警告あり。無変更の`is-birthday.test.ts`でも再現し5件PASS。今回の12件は成功したが、これを実サーバー比較の成功とは扱わない |
| lint・出荷検査 | PASS（未commit差分、`--base HEAD`）。変更したWeb実装4ファイル、明示した単体テスト3ファイルの`eslint --quiet`、SPDX、locale safety。ブランチ全体の以前からあるlocale差分は別範囲 |
| 修正した不具合 | 応答requestIdの照合で、Swiftが返す大文字UUIDとJSの小文字UUIDを同じIDとして扱う。最初の実機試験で検出し、修正後に該当する統合・UI試験を再実行 |
| 静的索引 | 件数は162/122/26/37/25/259/7のまま。現在HEADと原本のcommit metadata、改行を含むソースハッシュに差がある。差のある12ページは基準コミットとのLF正規化後の内容が一致し、ナビのaction式も改行正規化後に一致 |
| 比較環境の準備 | 専用Colima profile `gridspace-ios-parity`。既存Docker contextは切り替えず、PostgreSQL 18/Redis 7を既存テスト構成と同じlocalhostポート54312/56312で起動し、`pg_isready`/`PING`に成功。テストユーザーとPWA/iOS比較結果はまだ作成していない |

Webの失効通知にはhost/userId/reasonだけを送り、tokenやユーザーオブジェクトを渡さない。ネイティブはそのIDを認証証明として扱わない。通知はnative UIと一時処理の失効に限定し、Webに残る本文・IndexedDB・プラグインの安全な破棄、データ移行、認証済み操作の許可は別途検証する。

### S1のローカルデータ移行を追加した検証

同日、[ローカルデータ移行](local-data-transfer.md)のWeb実装を追加。実サーバーへは未配布。iPhoneから新しいWeb画面を使う試験は未実施で、以前のFiles/ダウンロード試験から今回の全経路の合格を推定しない。

| 対象 | 結果・範囲 |
|---|---|
| Web単体 | PASS、6ファイル26件。移行codec/方針/復旧13件と、通知・認証保存境界13件。構造化値・未知フィールド・循環/共有参照・MIME/バイト列、改変/重複/不正ID・認証情報の拒否、確認後の変更検出、quota相当の失敗・再起動からの復元、設定の未知キーの後続commit、ネイティブ失敗・自動バックアップ失敗時のログアウト継続 |
| 実ブラウザの保存試験 | PASS、Chromium 6件。実際のIndexedDBとBlobを使う2 MiB画像の往復、移行先の認証情報の保持、journalからの復元、失敗時のrollback、通常起動時にIndexedDBを開かないこと、64 MiB画像と4 MiB以下のfingerprint読出し、アカウント変更の前に中断・復元が完了する順序 |
| PWAの通し試験 | PASS、`test/e2e/local-data-transfer.spec.ts`の2件。一般利用者のパスワード新規ログイン→書出し→件数/内容確認→信頼の明示→取込→再読込、下書き・Scratchpad・AiScript・未知設定・画像の復元、ログイン保持、再適用拒否。もう1件はjournalを残したdocumentの起動前復旧。管理者も合成アカウントとして用意するが管理画面の全操作は未確認 |
| 実行環境 | Node 26.13.1、pnpm 12.17.0。専用ColimaのPostgreSQL 18/Redis 7、test-misskey DBとテスト用ポートを使用。アプリはUnix socket、比較用HTTPプロキシはlocalhost:61812に限定。プロキシの接続元IP転送を正し、通常の認証・IP処理を通す。実アカウントや本番DBへテストデータを送らない |
| ビルド | PASS。i18n、frontend、frontend-embed、Service Worker、backend e2e bundle。依存導入時に省略したre2/sharp/v-code-diffの必要なbuild処理を実行。最初のWebビルドはv-code-diffのpostinstall未実行で失敗し、実行後に成功 |
| Web型検査 | 移行処理3ファイルとcodec/方針/browser testの対象型検査はPASS。大容量試験のTypedArray型の拡張による1件を修正。全体の最終検査はBASELINE、既存80診断で失敗。診断のファイル/行/列/codeはすべて以前の隔離HEADの84診断（src配下81件を含む）の集合に含まれ、新規の診断位置なし |
| Vueレビュー | スキル指定のreviewerが対象2つのVueとja-JPの新セクションを確認し、指摘なし。グループ別件数、任意の識別子一覧とページング、i18n、確認・取消・再読込を含む |
| lint・安全検査 | PASS。変更したWeb実装11ファイルと生成locale型の`eslint --quiet`、変更したテスト・設定ファイルの明示lint、SPDX 2946ファイル、locale safety（未commit差分、`--base HEAD`）。i18nのtypecheck/lintも成功し、未変更ファイルに警告2件あり |
| 静的索引 | ルート162、設定122、状態26、ウィジェット37、ナビ25、個別起動7は維持。ページは移行用子UIを追加して260件。原本JSONの259件は調査時の基準値として残す |

通常のPWAテストコマンドは次のとおり。e2eは隔離したテストサーバーが起動し、必要なビルドが完了した状態で実行する。

```sh
pnpm --filter frontend test test/unit/local-data-archive.test.ts test/unit/local-data-transfer.test.ts test/unit/preferences-unknown-records.test.ts test/unit/ios-native-session.test.ts test/unit/ios-native-account-switch.test.ts test/unit/ios-native-signout.test.ts
pnpm --filter frontend test:browser
pnpm --filter frontend test:e2e local-data-transfer.spec.ts
```

証拠はローカルの`/tmp/gridspace-ios-combined-web-tests-final.log`、`/tmp/gridspace-local-data-browser-complete.log`、`/tmp/gridspace-local-data-e2e-complete.log`。確認画面の合成データの画像は`packages/frontend/test/e2e/artifacts/local-data-transfer-local--abb3d-etention-and-replay-refusal-chromium/local-data-review.png`。これらのartifactsや個人の端末情報をGitへ追加しない。一般の設定/Pizzax書込みとクラウド同期の全競合制御、全認証方式、実機・旧OSの比較は引き続き未完了。復旧競合UIは次の追加検証を参照する。

### S1の復旧競合画面と退避記録の追加検証

2026-11-16。アプリの通常起動前に競合値を確認するWeb画面と、元のjournalを失わない復旧を追加した。実サーバーへは未配布で、今回の変更にはSwiftの編集を含まない。以下をiPhoneのFiles・WKDownload経路やS1全体の合格と扱わない。

| 対象 | 結果・範囲 |
|---|---|
| Web単体 | PASS、6ファイル32件。以前の26件に、keep/restore、確認後の変更、別アカウントの復元拒否、選択後の再中断、credential-bearing journalの拒否、元から壊れたraw値の保持と通常snapshotの検証維持を追加 |
| 実ブラウザ | PASS、Chromium 10件。以前の6件に、実IndexedDB transactionでの元のjournal・現在値・Blob退避、認証フィールドの除外と維持、別アカウントへの現在値の複製防止と記録の閲覧・削除拒否、古いversionと確認後の壊れたjournalでの原子的な中止を追加 |
| PWAの通し試験 | PASS、5件。以前の2件に、390×844の画面で21件の競合一覧→下部の確認→keep/restore→通常起動→退避archiveの保存→削除の取消・確定を追加。もう1件は移行時と異なるアカウントで、以前の本文・復元選択肢を出さず現在値を保持して起動し、そのアカウントへ元の退避記録を表示しないことを確認 |
| 画面・Vueレビュー | PASS。reviewerが長い一覧をスクロールできない問題を検出し、専用スクロール領域へ修正。再レビューで指摘なし。最終の合成データの画面も目視確認。通常のMk*/osはアプリストアを初期化するため、起動前画面だけは独立したVueと標準フォーム・画面内確認を使用 |
| 初回の通し試験失敗 | 既存のソースコード案内を閉じる手順がなく、通常起動後の操作を遮った。案内を閉じる手順と、削除取消ダイアログの終了を待つ手順を追加。追加した別アカウント試験の期待値も「現在値を残す」へ修正し、最終の5件が成功。実装の失敗を試験の成功として置換していない |
| ビルド・型検査 | frontend buildとi18n build/typecheck/lintはPASS。i18nは未変更ファイルに既存警告2件。全体のvue-tscはBASELINE、80診断で失敗。ファイル/行/列/codeはすべて以前の隔離HEADの84診断の集合に含まれ、今回の新しい診断位置なし |
| lint・安全検査 | PASS。`check-shipping.mjs --base HEAD`によるWeb実装14ファイルと生成locale型、テスト3ファイルの明示eslint、SPDX 2949ファイル、locale safety。以前からあるブランチ全体のlocale変更は今回の範囲と区別 |
| 静的索引 | 162ルート、122設定、26状態、37ウィジェット、25ナビ、7個別起動を維持し警告0。起動前の復旧Vueを追加し現在261ページ。原本JSONは調査時の259ページを保持 |

最終の証拠: `/tmp/gridspace-recovery-units-final.log`、`/tmp/gridspace-recovery-browser-complete.log`、`/tmp/gridspace-recovery-e2e-verified.log`、`/tmp/gridspace-recovery-build-complete.log`、`/tmp/gridspace-recovery-types-complete.log`、`/tmp/gridspace-recovery-shipping-complete.log`。画面は`packages/frontend/test/e2e/artifacts/local-data-transfer-confli-84517-preserves-both-values-keep--chromium/local-data-recovery.png`ほか各ケースのartifactsへ保存する。ローカルサーバーとDBには合成アカウント・合成保存値だけを使用した。

残件は新しいWeb版とiPhoneの選択・保存・復旧・再起動の比較、保存禁止や容量不足・旧OSでの動作、全保存状態、認証方式と権限別の比較。通常の設定/Pizzaxの全writerや外部PWAとの競合を原子的に防ぐ仕組みはS3の未完了項目であり、移行時にほかの窓を閉じる条件を残す。

### 隔離した合成PWAとネイティブの通し試験

2026-11-16。`apps/ios/scripts/local-parity-server.mjs`と`check-parity.py`を追加し、専用のテストDB・合成アカウント・外部の一時ディレクトリを使うDebug専用の比較環境を作成した。実サーバーへは未配布。通常のWebKit保存領域と既存ログインは使わず、試験ごとのnamed storeをプロセス再起動時だけ引き継ぐ。

| 対象 | 結果・範囲 |
|---|---|
| Simulatorの全アプリ内・UI試験 | PASS。iPhone 17 Pro / iOS 26.5、アプリ内21件・UI6件。匿名PWAの起動、実キーボードによるパスワードログイン、初期設定の終了、プロセス再起動後のログイン保持、移行の書き出し確認画面、誤った証明書pinでの読込み拒否、既存のダイアログ・添付取消・背景移行・HTTPS入力検証を含む |
| 実機の限定試験 | PASS。証明書と隔離設定5件・WebSessionController 6件、別実行の交渉とJavaScriptダイアログ1件。利用者へのUI Automation操作の再依頼後に実行できた。これを実機の新規PWAログイン成功とは扱わない |
| 実機から合成PWAへの通信 | 未解決。同じWi-Fiであることを利用者が確認。実機ではNSURLErrorDomain -1004 / NSPOSIXErrorDomain 64（ホストダウン）、Mac側も端末のARP未解決。試験サーバーへ接続が届かず、実機のPWAログインは失敗。Macのファイアウォールは読み取りで無効を確認し、設定変更は行わなかった。APの制限など原因は未確定 |
| IPv6 | PASS。URLComponentsへIPv6を設定する際の括弧欠落によるURL生成失敗を修正。Core 18件にIPv6 authority・port・拒否条件を追加。実際のWebKit securityOriginが返す括弧付きhostとFoundationのhostの差をbridgeで正しく照合し、Simulator・実機で失効通知を確認 |
| TLSと試験の境界 | PASS。Debugかつ2つの明示フラグ、private origin、証明書SHA-256 pin、hostname、有効期間を検証。実Security.frameworkで正しい証明書・誤pin・別host・期限切れを試験。trust評価はメインスレッド外で実行し、信頼ルートやATSを緩めない。通常起動の認証challengeは既定処理 |
| SDK・Release・安全検査 | PASS。最終の`check-mac.sh`（Core 18件・SDKビルド）と別DerivedDataのReleaseビルド。Releaseの実行ファイルに試験の環境変数名・起動フラグがなく、試験証明書・Local Network/Files公開のDebug用Infoキーも含まれないことを確認。`check-shipping.mjs --base HEAD`の変更Web 15ファイル・生成locale 1ファイルのlint、SPDX 2949ファイル、locale safetyも成功 |
| Webのアクセシビリティ | 初期設定を閉じるアイコンボタンへ既存翻訳のaria-labelを追加。frontend buildと指定Vue reviewerはPASS。ネイティブUI試験で実際に「閉じる」を操作 |
| 初回失敗と修正 | 自己署名証明書のserverAuth用途不足、credentials:omitのAPIに試験プロキシがBasic認証を要求した問題、キーボードの値確定前にassertする問題を検出して修正。TLS検証や製品の認証を回避せず、専用接続元制限と入力確定待機で修正後の全27件を実行 |

証拠: `/tmp/gridspace-parity-runner-full.log`と`/tmp/gridspace-ios-parity-phone-ih78nrdu/result-4f1601cb242d4f22a2a420efc203dff4.xcresult`。実機の限定試験は`/tmp/gridspace-parity-phone-current-tests.log`、`/tmp/gridspace-parity-device-ui-retry.log`。一時ファイルには合成アカウントの認証情報が含まれるため、Git・共有資料へ追加しない。実機は試験後に通常起動へ戻した。Filesからの移行取込み・書出しの保存・復旧のネイティブ通し試験と、全認証方式の比較は引き続き未完了。

### SimulatorのFiles移行とBlob書出しの修正

同日、前節のUI試験をFilesの実操作まで拡充し、次を確認した。実機のLAN接続問題は未解決で、実サーバーへWebコードを配布した結果ではない。

| 対象 | 結果・範囲 |
|---|---|
| Nativeの全試験 | PASS、アプリ内21件・UI6件。新規ログイン→再起動→Filesで合成archiveを選択→信頼確認と適用→実際の再読込完了→プロセス再起動→書出し→ネイティブ共有シートの保存選択肢を確認 |
| 書出しの内容比較 | PASS。WKDownloadが書いた完全な一時ファイルをSimulatorから回収し、`verify-parity-export.mjs`で新しいarchive ID、同じorigin/ユーザー、下書き・Scratchpad・AiScript・未知のmetadataと2 MiB Blob全バイトを確認。元の取込みファイル自身を渡すと拒否する |
| 発見した破損 | 修正前のネイティブ書出しでは、2 MiBと宣言したBlob partに元のarchive全体が入り、宣言より1233 bytes多くなって再取込み不能だった。UIだけの合格とせず、回収ファイルで再現。decode時に元ファイルのBlob範囲を4 MiB以下ずつ独立したBlobへコピーする修正後、宣言長・内容が一致し共有シートまで成功 |
| Webの検証 | PASS。単体6ファイル33件、実ブラウザ10件（64 MiB画像を含む）、変更codecとその単体試験のstrict型検査、frontend build。新しい10 MiBのファイル由来Blob試験で読出し上限・先頭末尾を含む全バイト・再書出しを確認。全体vue-tscの以前のBASELINE 80診断を今回改めて実行したものではない |
| 試験手順の修正 | DebugのFiles公開キーをXcodeが出力していなかったため、専用plistとビルド後検査へ修正。長いフォルダ名のcaptionをtapしても中へ入らないため、Filesの観測したcell内のiconをtap。再実行時の既設定アカウントと古いunsigned UI runnerも考慮し、実アプリのデータは削除しない |
| 共有シートの再検証 | PASS。最初の「ファイル」「保存」を含むlabel判定がWebの注意書きにも一致したため、その共有UIの合格を撤回し、システムの保存アクションとの完全一致へ変更。該当の通し試験を単独で再実行し成功。取得を待った後のスクリーンショットで、2.1 MBのファイルとネイティブの「“ファイル”に保存」アクションを目視確認。証拠は`/tmp/gridspace-parity-blob-native-share.log`と`result-0a475c20dfca43508d16744ebadb1c71.xcresult` |
| 初回の追加検証失敗 | 大きいTypedArrayをVitestのdeep比較へ渡した試験がメモリ不足になり、全バイトをbooleanで比較するよう修正。ブラウザの旧「12 bytes以下」期待は新たなBlobコピーに合わないため、4 MiB以下の要件へ変更。修正後の33件・10件を実行し直した |
| 安全検査・実機への反映 | PASS。変更ファイルlint、明示したテスト2ファイルのeslint、SPDX・locale safety、diff検査。最終の実機Debug/Simulator Releaseビルド成功、Debugの3キーとReleaseでの試験キー・証明書・フラグの不在を確認。実機へアプリを更新し通常起動した。実機のWebは配布済みの版を引き続き使う |

証拠: `/tmp/gridspace-parity-blob-native-full.log`、`/tmp/gridspace-ios-parity-phone-ih78nrdu/result-65511cd1a49249d188b47fa5ad44e3d4.xcresult`、`/tmp/gridspace-parity-blob-verified.log`、`/tmp/gridspace-parity-blob-units-final.log`、`/tmp/gridspace-parity-blob-browser-final.log`、`/tmp/gridspace-parity-blob-types.log`、`/tmp/gridspace-parity-blob-build.log`、`/tmp/gridspace-parity-blob-shipping.log`。Filesへ書出しを保存し終える操作・共有取消・復旧画面のネイティブ比較、実機での新しい移行経路、512 MiB付近のメモリ余裕は未確認。S1全体やS2の完了とはしない。


### Filesへの保存完了、2FAと第一者API、関連付け設定

2026-11-16、前節と同じ隔離環境。実サーバーへの配布や実アカウントの設定変更は行っていない。

| 対象 | 結果・範囲 |
|---|---|
| Simulatorの全Native試験 | PASS、アプリ内21件・UI10件の計31件。以前の試験に、TOTPの不正コード拒否→正しいコードでログイン→再起動、バックアップコードの成功→別storeで再使用拒否、連携一覧の取得・解除・再起動後の消失、RFCのTOTPベクトル検査を追加 |
| Filesの保存と再選択 | PASS。共有シートのシステムアクションを完全一致で選び、専用Documentsフォルダへ保存完了→プロセス再起動で一時WKDownloadを破棄→Filesから保存済みコピーを再選択→再度信頼確認が必要であることを確認。保存コピーを回収し、元と異なるarchive ID、同じ合成identity、4レコード・未知フィールド・2 MiB Blob全バイトを検査 |
| 再現用runner | 実行ごとに固有のfixtureフォルダを使い、アプリ本体の保存領域は削除しない。Xcodeがインストール時にdata containerを移動する場合にも現在の場所から回収。原本と書出しを同じartifactsへ保存し、サーバーのfixture再生成後もその組合せだけで比較可能。`--verify-export`は保存未完了や対象OSのskipを成功にしない |
| 認証の比較条件 | バックエンドのテストモードにあるTOTP省略を明示的に無効化。起動時にも不正・使用済みTOTPの拒否を検査し、実際の再使用保護を保つ。限定MiAuthトークンの`secure: true`な`i/apps`拒否と第一者の成功も検査。ネイティブUIで一覧・解除を操作した。`i/revoke-token`自体はsecure指定ではなく、既存の所有者確認を使う |
| 入力とアクセシビリティ | TOTP入力へ既存翻訳のaria-labelを追加し、frontend buildとVue reviewerがPASS。最初のUI試験でキーボードに隠れた操作、古いコード前へのcaret挿入を検出。標準のキーボード完了と編集メニューの全選択、確定値のassertで修正し、認証の省略や直接DOM入力を使わず再実行 |
| TOTPの計算 | PASS。CryptoKitのテスト用SHA-1 HMAC計算を[RFC 6238 Appendix B](https://www.rfc-editor.org/rfc/rfc6238#appendix-B)の6ベクトルで検査し、合成secretを既存OTPAuthとも比較。テスト実装はDEBUGだけで、元アカウントのsecretを使わない |
| Associated Domainsの準備 | PASS、backend単体13件とビルド済みサーバーのHTTPS GET/HEAD。設定なしは404/no-store、設定時は明示したApplication Identifierだけをwebcredentials JSONで返し、Host由来の生成・リダイレクト・cookieはない。不正設定は起動前に拒否。API reviewerも指摘なし。REST APIのmeta/paramDef/res・entityは未変更で、misskey-js再生成・migrationは対象外 |
| 署名設定 | PASS。任意のIOS_AUTH_DOMAINを指定した場合だけアプリtargetへ関連付けentitlementを適用。通常の実機Debugビルド成功と、その署名にassociated-domainsがないことを検査。showBuildSettingsで任意設定の展開・別targetへの非適用を確認。DNS入力の有効3件・拒否9件、plist/bash/Python/JS構文も検査。Associated Domains付きprofileでの実機ビルドは未実行 |
| Mac・出荷検査 | PASS。Core 18件とSDKビルド、backend build:e2e、変更backend 3・frontend 16・生成locale型1ファイルと追加backend試験のeslint、SPDX 2951ファイル、locale safety、diff検査。全体vue-tscの既存BASELINEは再検査していない |

証拠: `/tmp/gridspace-parity-auth-all.log`、`/tmp/gridspace-ios-parity-phone-ih78nrdu/result-1a9e261b1b164b44a9c5de45e70d0cd7.xcresult`、`/tmp/gridspace-parity-durable-verified.log`、`/tmp/gridspace-parity-association-unit-final.log`、`/tmp/gridspace-parity-association-http.log`、`/tmp/gridspace-parity-association-mac.log`、`/tmp/gridspace-parity-association-device.log`、`/tmp/gridspace-parity-association-shipping-final.log`。xcresult・artifactsは合成資格情報や端末診断を含み得るためGitへ追加しない。

パスキーの条件は[AppleのWKWebView向け説明](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)と[Associated Domainsの仕様](https://developer.apple.com/documentation/xcode/supporting-associated-domains)を参照した。公開HTTPSでのAASA配布、Apple CDN・署名profileとの関連付け、実機での登録・認証・取消・復帰は未確認。Simulatorの2FA成功で代替しない。実機の新しいPWA経路はLAN接続問題が残り、ログアウト・切替・失効後の本文と履歴の破棄、再認証・CAPTCHA、全保存状態と復旧画面もS1の残件。


### アカウント変更後の履歴破棄と最終の対象再試験

同日、Simulatorの通し試験を切替・退出・本人限定ノートまで拡充し、アカウント変更後に古いWeb画面が履歴から戻る問題を修正した。通常の実機用アプリも更新・起動したが、新しいWebアダプターとAASAの実サーバー配布は行っていない。

| 対象 | 結果・範囲 |
|---|---|
| 履歴の不具合 | 修正前は、ログアウト後の戻る操作で以前の「ログアウト処理中」のdocumentが復元されて停止した。録画で確認。これを私有本文漏えいの実証とは扱わない。変更通知の応答前にdocumentを壊さず、Webの保存後に始まる同一originのGETを新しいWebViewへ渡すよう修正。古い履歴・子窓・保留処理を破棄する。通常のSPA履歴は保持 |
| WebViewの保存領域 | PASS。元のWKWebsiteDataStoreオブジェクトをそのまま渡す。新しい統合試験で通知後のWebの保存、応答前に交換しないこと、GETを元のWebViewで実行しないこと、遷移先のquery/fragment、新しいWebViewでの保存値の保持と空の履歴を検査。WebのトークンをSwiftへ抽出しない。bootは交換を起こさず、authenticatedOperationsはfalseのまま |
| 最終Nativeの検証 | PASS、アプリ内22件・UI13件の計35ケースを検証。全体実行は33件成功・2件失敗。その後、試験手順を修正したFilesとTOTPの2件を単独の対象実行で成功させた。1つの全体実行が35件すべて成功したという意味ではない |
| 切替・退出 | PASS。一般アカウント2人を通常UIから追加し、両方向に切替、プロセス再起動後の選択identityをWebの移行確認画面で検査。退出後は再起動して保護されたURLで再ログインが必要。本人限定・localOnlyの合成ノートは、本人の表示を先に確認し、退出時に実際のWebView IDが変わること・戻る履歴の消失・再起動後の非公開表示を検査。未ログインと別アカウントのAPI取得でも本文・添付がないことをfixture生成時に確認 |
| Filesの最終再試験 | PASS。取込み・信頼確認・適用・再読込・再起動・書出し・共有シート・Files保存・再起動後の再選択まで成功。保存コピーと原本を同じartifactsへ回収し、新しいarchive ID、同じidentity、下書き・Scratchpad・AiScript・未知フィールド・2 MiB Blobの全バイトを自動比較。`--verify-export`もexit 0 |
| Files試験の停止原因 | 原本は現在のアプリDocumentsに存在した。長いフォルダ名と画面外cellへの座標tapでBrowse側へ戻り、全画面への下スワイプではpickerも閉じた。短い固有フォルダ名と、観測したcell内のImage要素へのtapへ変更し再検証。共有シート前の別の失敗ではソース提供の案内が書出しボタンに重なっていたため、既存の「わかった」をUIで操作する手順を追加。保存flagを直接書き換えない |
| TOTPの最終再試験 | PASS。不正コードの拒否後、同じnamed storeをデータ削除なしで再起動し、未ログイン状態から再び通常のユーザー名・パスワード・TOTP入力を通す。次の時間区間の正しいコードを入力し、確定値・キーボード完了・ログイン・再起動後のidentityを検査。テストモードの検証省略は無効のまま |
| TOTP入力編集の残件 | 同じ欄を長押しした選択メニューが出ず、全選択キーでも期待値にならない試験失敗を記録した。この自動編集操作の成功は未確認。最終の再試験は、同じ保存領域で新しい通常ログインを行う範囲であり、同じ欄の修正が解決したとはしない |
| SDK・実機・Release | PASS。最終のCore 18件とSimulator SDK、署名付き実機Debug、Simulator Releaseをビルド。最新アプリのiPhoneへのインストール・通常起動コマンド成功。通常署名はAssociated Domainsを増やしていない。Releaseには比較試験フラグ・WebView試験ID・Files公開キー・試験証明書がないことを検査。ミラーリングは端末のロック待ちだったため、追加の利用者操作を求めず終了。通常画面の再目視は保留 |
| 型・lint・安全検査 | PASS。AASA実装・単体試験のstrict型検査、変更ファイルのeslint・SPDX 2951ファイル・locale safety、Python/JS/bash構文、diff検査。backend単体13件と実HTTPSのAASA検査は前節の証拠を使用し、変更のない広域試験を繰り返していない |

全体結果: `/tmp/gridspace-parity-auth-complete-final.log`、`/tmp/gridspace-ios-parity-phone-ih78nrdu/result-8fe48799d26c4b4f855393b93e905a29.xcresult`。対象2件の成功と書出し内容の比較: `/tmp/gridspace-parity-files-totp-retry-final.log`、`/tmp/gridspace-ios-parity-phone-ih78nrdu/result-49b57aa5bc9f46878571c00c6e9bcd72.xcresult`。保存した組は同じ一時ディレクトリの`artifacts/Parity-742d25abd034/`にある。ほかの証拠: `/tmp/gridspace-parity-account-reset-mac.log`、`/tmp/gridspace-parity-account-reset-device.log`、`/tmp/gridspace-parity-account-reset-release.log`、`/tmp/gridspace-parity-context-release-inspection.log`、`/tmp/gridspace-parity-context-device-install-final.log`、`/tmp/gridspace-parity-context-shipping-final.log`、`/tmp/gridspace-parity-association-types.log`。

S1は引き続き未完了。実機の合成PWAへの通信、新規認証・失効・再認証・CAPTCHA・パスキー、複数窓と通知後にGETへ進まない場合、POST後のdocument交換の比較、GridSpace私有データ全体の本文・画像・キャッシュ破棄と保存状態の全比較は残る。今回の通常GET経路では、新しいPWAを読み込んでからもう一度実行する方式を避けた。GETとして移せない場合の交換は限定したfallbackで、POSTを自動再送しない。S2以降やS5の完了には置き換えない。


### HTTPリダイレクトの確認とクラウド設定取得の失敗処理

2026-11-16、同じ隔離Simulator環境。WebKitが302先のactionへ元のlinkActivatedを引き継ぎ、外部ブラウザを確認なしで起動する問題を実HTTP fixtureで再現した。redirect通知だけでは間に合わなかったため、許可したmain-frame遷移の開始から完了・失敗までを追跡し、その間の外部遷移には確認を要求する。表示可能な最終応答にもorigin方針を適用し、外部UGC iframeは従来どおり許可する。同一originのdownload・Blobは保持する。

| 対象 | 結果・範囲 |
|---|---|
| Simulatorの対象再試験 | PASS。アプリ内25件とHTTP遷移UI 1件。実302で反復query・percent encoding・fragmentを保持し、外部302ではhostだけの確認を表示、取消で元画面へ戻る。認証queryの合成markerを確認文へ出さない |
| 応答の単体試験 | PASS。正規化origin、別port、HTTP降格、外部iframe、about、data/file/userinfo、同一origin download/Blob、拒否URL、shutdown後の拒否と遷移状態の終了を検査。初回のWKNavigationResponse派生テストダブルは内部状態不足でhostがcrashしたため不採用。公開の値を使う判定へ切り出した。初回実行を成功件数に含めない |
| Webのクラウド設定 | PizzaxのAPI・IDB失敗をloadedへ伝え、利用側で未処理のrejectionにならないよう修正。readyで復元したcacheをAPI失敗で初期化せず、cloudが未確認なら初期設定wizardを開かない。認証失効の案内は既存のアカウント更新処理に任せる |
| Webの関連単体試験 | PASS。新規5件は認証・通信エラー時のcache保持、loadedの拒否、未処理rejectionの不在、保存完了待機、IDB失敗を検査。切替・退出・公開bridgeと合わせ4ファイル18件成功 |
| テスト配信の中断 | Web再ビルド後に起動中backendが旧entry名を参照し、起動JSが404となった再認証試験を中断。試験サーバーを終了・再起動してfixtureを再生成し、匿名PWAのログインボタン表示を実ブラウザで先に確認。製品の認証失敗とは区別する |

HTTP再試験: `/tmp/gridspace-parity-navigation-pending.log`、`result-65c90b138fad445e9d3fc1ef34b914a6.xcresult`。最初の失敗・crashは`/tmp/gridspace-parity-navigation-auth.log`、redirect通知だけの失敗は`/tmp/gridspace-parity-navigation-retry.log`。Web単体は`/tmp/gridspace-parity-pizzax-unit.log`、`/tmp/gridspace-parity-revocation-regression.log`。これまでのUI13件と今回の1件は別の実行であり、一度の全件実行ではない。

追加の型検査: 全体`vue-tsc`はNode既定heapでメモリ不足となり診断完了前に失敗。heap拡大で再試行したが、8 GiBのMacでの実機・Simulator試験への影響を避けるため、この所有プロセスを中断した。今回の全体型検査をPASSや既存BASELINE件数の再現とは扱わない。frontend buildと上記18件の単体試験は成功している。

再認証・失効の対象UI試験は修正版Webと再起動したサーバーでPASS。合成専用ユーザーが本人限定ノートからセキュリティ設定へ移動し、再認証を取消しても再起動後のidentityを保持すること、正しいパスワードでトークン再生成ができることを確認した。利用者がNative再読込を確認した後、通常の「トークンが無効です」を表示し、退出後の戻る履歴がなく、再起動した私有ノートは非公開となり、通常のパスワードログインで同じidentityへ復帰することまで成功。再読込前・バックグラウンド中・複数窓の即時失効を証明したものではない。証拠は`/tmp/gridspace-parity-revocation-restarted.log`、`result-65c915128dd041a8a6bb18fa356e92d8.xcresult`。Nativeの成功件数は複数回の実行を合わせアプリ内25件・UI15件であり、一度の全40件成功ではない。

追加検査: `check-mac.sh`のCore 18件・SDK build、frontend build、変更ファイルlint（backend 3・frontend 18・i18n 1）、新規単体ファイルの明示eslint、SPDX 2952・locale safety・diff/構文検査はPASS。最終DebugをiPhoneへ更新・通常起動し、Release buildと試験flag・証明書・Files/Local Networkキー・WebView試験IDの不在もPASS。証拠は`/tmp/gridspace-parity-navigation-final-mac.log`、`/tmp/gridspace-parity-revocation-webbuild.log`、`/tmp/gridspace-parity-navigation-shipping-final.log`、`/tmp/gridspace-parity-navigation-device-installed.log`、`/tmp/gridspace-parity-navigation-release.log`、`/tmp/gridspace-parity-navigation-release-inspection.log`。


### USB開発トンネルを使う実機比較の再開

同日、Wi-Fiの同一接続は維持したまま、CoreDeviceのwired IPv6 ULAトンネルを読み取りで確認し、Macと端末の応答を確認した。トンネルは開発接続を閉じると消えるため、最初のlistenはEADDRNOTAVAILで停止。所有する短時間のdevicectl読取りを保ってアドレスを取り直し、専用の試験サーバーをそのMac側アドレスへbindした。許可する接続元も端末側1アドレスだけに指定。ATSや信頼ルート、ファイアウォール、Wi-Fi設定は変更していない。

実機のHTTPリダイレクトUI試験はPASS。起動からHTTPSのpin/hostname/期限検証、実302の内部query/fragment保持、外部遷移の確認・取消と元画面の保持まで成功した。証拠は`/tmp/gridspace-parity-usb-device-http.log`。これはWi-Fi経由の失敗原因を特定・解消したという意味ではない。Mac自身から同じUSBのローカルアドレスへ開くChromiumの補助検査は接続timeoutとなり、端末側の成功と区別する。


### 実機のIPv6 Blob書出し修正とFiles移行の通し検証

実機の新規ログイン・再起動・Files取込み・適用・再起動までは動いたが、最初の2回の通し試験は書出しの共有シートが出ずFAIL。FoundationのSwift URL生成とCFURL/WebKitで、IPv6を含むBlob URLのscheme colon・角括弧のエスケープが異なり、埋め込みoriginの照合に失敗していた。全体のpercent decodeを許可せず、scheme colonとIPv6 literalの角括弧だけを補正する共通処理へ変更した。hostのエスケープ、userinfo、別host/port、HTTP降格、opaqueなBlobは同じ認証originのdownloadとして許可しない。Blob ID・pathは解釈し直さない。外部のWeb Blob iframeは既存方針を維持する。

| 対象 | 結果・範囲 |
|---|---|
| 実機Files通し試験 | PASS。iPhone 16 / iOS 27.2.1。新規パスワードログイン→初期設定→再起動後のidentity保持→実Filesで合成archive選択→信頼確認・適用・再読込→再起動→書出し→共有シート→専用Documentsへ保存→再起動で一時downloadを破棄→Filesで保存コピーを再選択→改めて信頼確認が必要であることを確認 |
| 回収ファイルの比較 | PASS。実機から原本と保存コピーを回収し、異なるarchive ID、同じ合成origin/identity、下書き・Scratchpad・AiScript・未知フィールド・2 MiB Blob全バイトを検査。`--verify-export`はexit 0、通常アプリの起動も成功。合成の保存フォルダだけを使用 |
| Coreとアプリ内試験 | PASS。Core 19件。実機アプリ内26件の後、最終の両表現を含む応答判定4件を再実行して成功。Swift/CFURL両形式、外部origin、偽装されたencoded host/delimiter、IPv6 Blob iframeを含む。26件全件を最終修正後に1度で再実行したという意味ではない |
| ビルドと検査 | PASS。最終の`check-mac.sh`（Core 19件・Simulator SDK build）、実機Debug、Simulator Release。変更ファイルlint、SPDX 2952、locale safety、diff検査。全体vue-tscは前述のメモリ不足・中断を引き続き区別する |

成功は`/tmp/gridspace-parity-usb-device-files-final.log`、`/tmp/gridspace-ios-parity-usb-xo127k/result-b4e66ea69fed450bb3b9bd75d52fbed4.xcresult`、保存した組は同じ一時ディレクトリの`artifacts/Parity-a06d075d2010/`。最初の失敗は`/tmp/gridspace-parity-usb-device-files.log`、Swift側の形式だけを扱った中間修正の失敗とアプリ内26件は`/tmp/gridspace-parity-usb-device-files-blob-fixed.log`。最終Coreは`/tmp/gridspace-parity-blob-ipv6-core-final.log`、ビルドは`/tmp/gridspace-parity-blob-ipv6-final-mac.log`、`/tmp/gridspace-parity-blob-ipv6-final-release.log`、安全検査は`/tmp/gridspace-parity-navigation-and-blob-shipping.log`。試験の資格情報・証明書・端末情報・XCTest入力ログは共有しない。

### 実機の認証・切替・退出・失効の対象検証

同日、同じUSBの隔離環境で認証の8ケースを実行した。最初の実行は7件PASS・1件FAIL。失敗した切替のテスト操作を修正し、1件だけの再実行でPASS。1つの実行が8件すべて成功したという意味ではない。通常のWebKit保存領域や実アカウントの認証設定を変更していない。

| 対象 | 結果・範囲 |
|---|---|
| TOTP・バックアップコード | PASS。不正TOTPを拒否し、同じnamed storeを再起動して通常のパスワード・新しい有効TOTPで認証、再起動後のidentityを確認。バックアップコードは初回成功・別storeで同じコードの再使用を拒否。テスト用TOTP省略は無効。同じ欄を編集して修正する操作の未確認は引き続き残す |
| 第一者の連携一覧・解除 | PASS。実機の通常UIで一覧・解除を操作し、再起動後も消失。限定MiAuthのsecure API拒否と第一者の成功はfixture起動時に検査 |
| 退出・本人限定ノート | PASS。本人の表示を先に確認し、退出後にWebView IDが変わり、古い戻る履歴が消えること、再起動後に私有ノートが非公開となることを検査。全私有データ・画像・キャッシュの破棄や復帰時の再認可を証明したものではない |
| 再認証・トークン失効 | PASS。再認証の取消でログインを保持し、正しいパスワードでトークンを再生成。確認付きNative再読込後に失効案内・退出・履歴破棄・私有ノートの非表示となり、通常の新規パスワード認証で同じidentityへ復帰。再読込前の即時失効は未確認 |
| 2アカウントの往復切替 | 修正後PASS。通常UIから2人目を追加、選択は自動で変わらないこと、2人目へ切替・再起動後のID確認、元の利用者へ切替・再起動後のID確認まで成功 |
| 切替テストの初回失敗 | 実機のモバイル用メニューはButtonとして「既存のアカウント」を表示していたが、テストがMenuItemだけを検索していた。記録したUI階層で確認し、正確なlabelを持つButton/MenuItemの操作要素に対応。StaticTextや座標だけで合格にしない。製品のメニューや認証処理は変更していない |
| 証明書の拒否 | PASS。誤ったpinでPWAを開かず、復旧案内を表示。正しいpinでの実機アクセスは上記認証・Filesの成功と区別して確認 |

7件成功・1件失敗は`/tmp/gridspace-parity-usb-device-auth.log`、`/tmp/gridspace-ios-parity-usb-xo127k/result-e0694197ca424528934ab8727de7feb4.xcresult`。切替1件の再試験は`/tmp/gridspace-parity-usb-device-account-retry.log`、`result-b48bb86198154efca6ea0748a7f6f792.xcresult`でexit 0、通常アプリの起動も成功。最後の`check-mac.sh`は`/tmp/gridspace-parity-native-final-mac.log`、変更ファイルlint・SPDX 2952・locale safetyは`/tmp/gridspace-parity-physical-auth-shipping.log`でPASS。最終Releaseの試験キー・証明書・WebView試験ID不在も確認。所有する試験サーバーと接続維持用の読取りプロセスを終了した。

CAPTCHAは未確認。SigninApiServiceのテストモードではCAPTCHA検証が省略されるため、画面だけの合格で代替しない。パスキーの関連付け配布・署名・本人確認、復帰時の私有本文の再認可、複数窓・復旧・権限別fixture・保存状態全体がS1の残件。新しいWebコードは実サーバーへ未配布であり、通常の実アカウントでの結果とは区別する。S2以降やS5の完了とはしない。

### 起動前復旧のSimulator・実機比較とUSB接続の再現手順

2026-11-16。隔離サーバーに専用の合成復旧ページを追加した。実機を実際の書込み途中で強制終了する代わりに、中断後のjournal・現在値・pending markerを同じnamed storeへ保存し、通常のScratchpadルートへ移動する。journalのhashは製品のcodec/fingerprint関数から作り、Webでログインした合成利用者のIDが一致する場合だけfixtureを作成する。製品の起動コードへ試験用の復旧省略や条件分岐は追加していない。

| 対象 | 結果・範囲 |
|---|---|
| 中断の自動復旧 | PASS。Scratchpadの部分適用値を起動前に移行前の値へ戻す。実際のeditorのvalue、プロセス再起動後の同じ値、通常の移行確認画面でログインidentityの保持を検査 |
| 競合の現在値保持 | PASS。editorを起動する前の復旧画面、既定の保持、未確認時の適用不可、タグを含む値の文字列表示、利用者の確認・適用、editorと再起動後の値を検査。自分の退避記録を表示し、削除を取消した後も残り、再度確認して削除できる |
| 競合の移行前への復元 | PASS。iOSの選択UIを実際に操作し、選択値と適用後・再起動後のeditor、ログインidentityを検査。JavaScriptで選択値を直接書き換えない |
| 異なるアカウント | PASS。journalの所有者と現在の利用者が異なる状態で、移行前の値・プレビュー操作を出さず、現在の値を保って起動できる。同じ通常画面の状態で、自分の退避記録は表示され、他アカウントの記録は表示されないことを別々に検査 |
| Simulator | PASS。最初の3件は自動復旧と異なるアカウントの2件成功・保持の履歴検索1件失敗。その後、保持・復元・異なるアカウントの3件が1実行で成功。4ケースすべてが一度の実行で成功したという意味ではない |
| 実機 | PASS。iPhone 16 / iOS 27.2.1、上記4ケースが1実行ですべて成功。通常アプリの起動コマンドも成功 |
| 履歴検索の初回失敗 | 退避履歴は末尾にアイコンを含むButtonとして公開されていたが、テストが完全一致のStaticTextを検索していた。UI階層で確認し、書出しレビューを閉じた同じ状態で実際の履歴ボタンを検査するよう修正。異なるアカウントの負の検査も同じ操作要素へ変更し、正のケースとともに再試験。製品の履歴処理は変更していない |
| USB接続の補助 | `hold-usb-parity.py`を追加。wiredのULA、同じ/64にある一意のMacアドレスだけを選び、privateな接続情報を定期更新する。サーバーは混在設定・古い情報・停止したPIDを拒否し、接続変更による自動再起動・DB再生成はしない。wired/private/一意性の選択と4つの拒否条件、古い情報・停止した所有者・混在設定がDB setup前に拒否されることを実行確認。実機4ケースでこの接続手順を使用した。拒否検査は`/tmp/gridspace-parity-usb-transport-refusals.log` |
| 終了と安全検査 | PASS。所有するサーバーと接続維持プロセスを終了し、接続情報ファイルが削除されることを確認。MacのCore 19件・SDK build、Python/JS構文、変更ファイルlint・SPDX 2952・locale safety（`--base HEAD`）、diff検査も成功 |

Simulator初回は`/tmp/gridspace-parity-recovery-native-initial.log`、`/tmp/gridspace-ios-parity-recovery-r03SAL/result-02d998a2b691450894ce343e23ada306.xcresult`。修正後3件は`/tmp/gridspace-parity-recovery-native-review.log`、`result-cadcbf3fcbf34cd5a145925bc48bf17d.xcresult`。実機4件は`/tmp/gridspace-parity-recovery-device.log`、`/tmp/gridspace-ios-parity-recovery-usb-QE8BwS/result-adcba0b7c90f46e38e40a81e461c777a.xcresult`でexit 0。ビルドは`/tmp/gridspace-parity-recovery-mac.log`、安全検査は`/tmp/gridspace-parity-recovery-shipping.log`。製品のSwift/TS/Vueはこの追加試験では変更していないため、Release・広域frontend型検査は再実行せず、前節の証拠・未完了を引き継ぐ。

今回の復旧値はlocalStorageのScratchpad文字列であり、Blobを含むjournalの実機復旧・退避ファイル保存/回収、実書込み中の強制終了、壊れたjournalや保存不可のUI、全保存状態・複数窓は未確認。新しいWebコードは実サーバーへ未配布。S1全体の完了やS2以降の合格にはしない。UGCの配布条件は同日にApple原文と照合し、[S0-3の実装差分](widgets-ugc.md#s0-3-配布条件と実装境界の照合)へ記録したが、審査承認やAPI公開許可を得たという意味ではない。


### Blobを含む起動前復旧と退避ファイルの保存・回収

2026-11-16。ScratchpadとAvatarWalk保存先の両方が競合する合成fixtureを追加した。移行前・取込み値・競合した現在値に、それぞれ異なる2 MiB Blobと未知のmetadataを持たせる。最初のSimulator試験は復旧適用でFAIL。Chromiumでは成功した同じ復旧が、永続profileのWebKitでは`NotFoundError`となった。IndexedDB所有のBlobを含む元journalを退避・置換する前に、4 MiB以下ずつバイト列を読んで独立したBlobへコピーするよう修正した。書込みtransactionの前にコピーを完了し、transaction内のバージョン再照合を維持した。

| 対象 | 結果・範囲 |
|---|---|
| 単体・ブラウザ | PASS。codec・移行・新しいBlobコピーのunit 20件、Chromium 12件、永続profileのWebKit 12件。FileのMIME/名前/更新時刻、全バイト、共有・循環参照、Map/Set、疎配列を保持し、読出し上限4 MiBを検査。コピー前の読取り後にjournalを変更する試験でも、transaction内の再照合で置換・退避を拒否する |
| Simulatorの通し試験 | PASS。iPhone 17 Pro / iOS 26.5。新しいBlob復旧と既存Files移行の2件が1実行で成功。通常のiOS選択UIで2保存先を移行前へ戻し、再起動後のeditor・identityを確認。退避記録をFilesへ保存し、再起動後に保存コピーを選び、通常の移行形式として拒否されること、拒否ダイアログを閉じて通常書出しできることを検査 |
| 回収ファイル | PASS。Simulatorのrunnerの`--verify-export --verify-recovery`がexit 0。復元後の通常snapshotと退避記録を回収し、合成identity、元journalの前後と確認時の現在値の2 MiB全バイト・MIME・未知metadata・reviewed hashを比較。通常の移行4レコードの比較も同じ実行で成功。原本・1バイト変更・未知metadata変更を使う検証器の負のprobeも別途実行 |
| 実機 | PASS。iPhone 16 / iOS 27.2.1。同じBlob復旧・再起動・Files保存・保存コピー再選択と通常移行としての拒否・通常書出しが1件の通し試験で成功。`--verify-recovery`による回収ファイルの全バイト・metadata・identity・hash比較もexit 0。通常アプリの起動も成功 |
| Files操作の途中失敗 | 製品のBlob復旧修正後、試験のフォルダ移動と拒否ダイアログ後の操作がFAIL。Filesの仮想化で画面外の新規フォルダがAXに現れず、browsingRootの識別子には移動前の名前が残ることをUI階層で確認。現在のnavigation titleと実一覧のスクロールへ修正し、拒否ダイアログも通常ボタンで閉じる。既存のFiles移行とともに通し再試験した。製品のFiles UIを試験専用に変えていない |
| ビルド・安全検査 | PASS。frontend production build、codec・移行・ブラウザストア・新しいBlobコピー・新規TSテスト・browser configの限定したstrict型検査、変更ファイルlint・SPDX 2954・locale safety（`--base HEAD`）、Python/JS構文。MacのCore 19件・SDK buildも成功済み。広域frontend型検査は前節のメモリ不足・中断を引き継ぎ、合格としない |

Simulatorの最終成功は`/tmp/gridspace-parity-blob-recovery-simulator-verified.log`、`/tmp/gridspace-ios-parity-blob-recovery-GqRCX9/result-602b084fe7c041eca4f9d1fe903570a5.xcresult`。回収した組は同じディレクトリの`artifacts/Parity-3129dd1f90a1/`と`artifacts/Recover-09010019c975/`。最初の製品復旧エラーは`/tmp/gridspace-parity-blob-recovery-simulator.log`、WebKitの再現は`/tmp/gridspace-parity-blob-recovery-webkit-diagnosis.log`。Files操作修正中の失敗は`/tmp/gridspace-parity-blob-recovery-simulator-final.log`、`/tmp/gridspace-parity-blob-recovery-simulator-files-fixed.log`、`/tmp/gridspace-parity-blob-recovery-simulator-files-final.log`へ記録した。最後のファイルはBlob復旧の保存・再選択までは成功したが、拒否ダイアログを閉じる操作を欠いたためFAILであり、最終成功と区別する。

実機の成功は`/tmp/gridspace-parity-blob-recovery-device.log`、`/tmp/gridspace-ios-parity-blob-recovery-usb-YzHpmN/result-ca542a16c0ef4a42a0f2165002ca905f.xcresult`。回収した組は同じディレクトリの`artifacts/Recover-124d80d76717/`。所有するサーバーとUSB接続維持プロセスを終了し、接続情報ファイルの削除と試験ポートの閉鎖を確認した。

ブラウザの最終結果は`/tmp/gridspace-parity-blob-recovery-webkit-final.log`と`/tmp/gridspace-parity-blob-recovery-chromium-final12.log`、unitは`/tmp/gridspace-parity-blob-recovery-unit-final2.log`、限定した型検査は`/tmp/gridspace-parity-blob-recovery-targeted-types.log`。ビルドは`/tmp/gridspace-parity-blob-recovery-frontend-build.log`、Mac検査は`/tmp/gridspace-parity-blob-recovery-mac.log`、安全検査は`/tmp/gridspace-parity-blob-recovery-shipping-complete.log`。試験用資格情報・証明書・端末情報・XCTestの入力ログは共有しない。

実書込み中の強制終了、壊れたjournal/保存不可のUI、全保存状態・容量上限・旧OS・複数窓は引き続き未確認。新しいWebコードは実サーバーへ未配布であり、S1全体や後段の完了とはしない。


### 復旧エラーの保持と同じTOTP欄での訂正

2026-11-16。復旧の退避作成途中に同期的な保存拒否を注入したPWA試験で、再試行画面が全体の「読み込みに失敗しました」へ置き換わる不具合を再現した。IndexedDB requestのcallbackから例外が漏れ、操作のPromiseがrejectする一方でglobal boot-error handlerも動いていた。通常の値書込み・完了処理にも同じ問題があり、追加した実IndexedDBの2ケースはassertionだけなら成功したが、Unhandled Error 2件で試験全体はexit 1となった。3か所に共通のcallback保護を入れ、同期例外ではtransactionを明示的にabortし、呼出し元のエラー/再試行処理へ返すよう修正した。

| 対象 | 結果・範囲 |
|---|---|
| 壊れたjournal | PASS。Chromium/WebKitのPWA、Simulatorと実機。hashが不正な記録では通常editorを起動せず、復旧前の値や選択/適用も出さない。再試行・document/プロセス再起動後も、実際のjournal・pending marker・現在値・アカウントIDが残る。PWAでは復旧待機中の`/api/i`不実行も検査。試験fixtureで外部から正しいhashへ修正した後に通常復旧が完了し、journal/markerだけが消えてeditorの値・identityが一致する。製品に自動修復やboot省略を追加していない |
| journal DBのアクセス拒否 | PASS。Chromium/WebKitのPWA。`IDBFactory.open`へSecurityErrorを注入し、再試行・document再起動後も通常bootを始めず、保存条件の回復後は同じ再試行ボタンで復旧。実際の記録・現在値・marker・アカウントIDの保持を検査 |
| 退避作成途中の保存拒否 | PASS。Chromium/WebKitのPWA。backup本体をaddした後のmetadata addへQuotaExceededErrorを注入。全体boot-errorへ逃げず、確認を解除して再確認を求める。最初のbackupを含めtransaction全体が取り消され、元のactive記録だけが残ることを実DBで検査。条件回復後の再確認・復旧で退避が1組だけ残り、元journal・確認時の現在値・復元値が一致する |
| 値書込みと完了処理の同期例外 | PASS。Chromium/WebKitの実ストレージ試験。DataCloneErrorを注入し、既存レコード・applying journal・markerを保持し、使用済みIDを作らず、Unhandled Errorも発生しない。両エンジンの15件すべてが成功 |
| 完了済みのBlob付きjournal | PASS。実ストレージ試験で、異なる2 MiBの前後値を持つjournalをcommittedにした直後から、新しいadapterで値・metadataを読み直せる。起動処理でjournal/markerを片付けても、適用後の全バイトと使用済みID・認証保存を保持。新adapterの試験であり、実書込み中のプロセス強制終了を証明したものではない |
| TOTPの同じ欄での訂正 | PASS。Simulatorと実機。不正な6桁を実際にサーバーが拒否し、残った入力をOSのテキスト編集メニューで選択して、新しい有効コードへ置換する。JSで値を直接設定せず、通常の送信で認証し、再起動後のidentityまで確認。既存の「不正コード拒否→再起動→新規入力」のケースは削除していない |
| TOTP試験の途中失敗 | Simulatorではダブルタップや、フォーカス前の長押し後の自動入力が置換にならずFAIL。UI階層でCut/Copy/Pasteのメニューとキーボードが閉じた状態を確認し、先に入力をフォーカスしてから選択する手順へ修正。最終のSimulator 1件と実機3件の実行で成功。製品のTOTP処理は変更していない |
| 通常移行の回帰確認 | PASS。最終のcallback保護でSimulator/実機とも実Files取込み・適用・再起動・書出し・保存コピー再選択が成功。回収した原本/書出しの合成4レコード・未知metadata・2 MiB全バイトも一致。Simulatorの親実行は後続のTOTP操作が失敗したため、保存済みファイルを原本hashが一致する1フォルダから別途回収・比較した。親実行全体の成功とは扱わない |
| 最終の実機実行 | PASS。iPhone 16 / iOS 27.2.1。壊れた記録・通常移行・同じTOTP欄訂正の3件が1実行ですべて成功。`--verify-export`と通常アプリへの起動復帰もexit 0 |
| ビルド・安全検査 | PASS。frontend production build、対象TSの限定したstrict型検査、`check-mac.sh`（Core 19件・SDK build）、変更対象lint・SPDX 2955・locale safety（`--base HEAD`）とdiff検査。広域frontend型検査の未完了は前節から引き継ぐ |

PWAの最終3件ずつは`/tmp/gridspace-recovery-errors-chromium-complete.log`と`/tmp/gridspace-recovery-errors-webkit-complete.log`。保存処理の最終15件ずつは`/tmp/gridspace-recovery-errors-storage-chromium-final15.log`と`/tmp/gridspace-recovery-errors-storage-webkit-final15.log`。最初の全体boot-errorは`/tmp/gridspace-recovery-errors-chromium.log`、通常書込み/完了のUnhandled Errorは`/tmp/gridspace-recovery-errors-sync-callbacks-before.log`へ記録した。

Simulatorの壊れた記録の成功と最初のTOTP失敗は`/tmp/gridspace-corrupt-and-totp-simulator.log`、`/tmp/gridspace-ios-parity-corrupt-native-4eJGX4/result-a4afbfba23b14f979a56e8d033e95799.xcresult`。通常移行の成功と後続TOTPの失敗は`/tmp/gridspace-corrupt-totp-and-migration-simulator-final.log`、`result-58181f360b854c0785d23e970cd32bba.xcresult`。その保存コピーは`artifacts/Parity-4e03aa20d33a/`へ回収し、`/tmp/gridspace-recovery-errors-simulator-export.log`で比較成功。TOTPの最終1件の成功は`/tmp/gridspace-totp-edit-focused-simulator.log`、`result-4145a21c848944cea891c4502c5612ff.xcresult`。

実機3件の成功は`/tmp/gridspace-recovery-errors-device.log`、`/tmp/gridspace-ios-parity-recovery-errors-usb-xrt5K7/result-07e17b7d7eed48fd8584a89d0441c9ac.xcresult`。回収した組は同じディレクトリの`artifacts/Parity-6f598611035d/`。ビルドは`/tmp/gridspace-recovery-errors-frontend-build-complete.log`、`/tmp/gridspace-recovery-errors-mac.log`、限定した型検査は`/tmp/gridspace-recovery-errors-targeted-types-final15.log`、安全検査は`/tmp/gridspace-recovery-errors-shipping-complete.log`。通常アプリの起動後に所有サーバー/USB接続維持を停止し、接続情報ファイルの削除と試験ポートの閉鎖を確認した。試験用資格情報・XCTestの入力ログ・端末情報は共有しない。

保存領域の拒否/容量不足はブラウザAPIへの例外注入であり、実機の保存設定変更や空き容量を使い切った試験ではない。全保存状態・実書込み中の強制終了・容量上限・旧OS・複数窓の比較、パスキー/CAPTCHA/復帰時の私有本文の再認可は残件。新しいWebコードは実サーバーへ未配布。S1全体や後段の完了とはしない。

### ネイティブの非表示通知と復帰待機

2026-11-16。S1-2の復帰処理として、document visibilityだけに依存していたGridSpaceの読取り処理へネイティブの非表示状態を接続した。`WebRendererLifecycle`は一時的な非アクティブ化では画面だけを覆い、バックグラウンド移行時に破棄を通知する。復帰時にも破棄を繰り返し、Vue反映の応答後に表示を再開する。既存Webの再認可要求は、その間に残した参照を使う。応答は認証の証明ではなく、WebトークンをSwiftへ渡す処理も追加していない。

5秒の応答待機超過・失敗では表示を覆ったまま再確認でき、自動再読み込みや投稿再送はしない。遷移・アカウント変更・再度のバックグラウンド移行・画面終了で待機を無効化し、以前の応答では画面を戻さない。対応する購読がない旧Webは既存の互換表示を保つ。この経路で新しい本文破棄を保証したとは扱わない。

Webの初期非表示を使うことで、非表示中に遅れてマウントしたClips・コレクション・返信が取得を開始する問題も修正した。投稿フォームの初期取得を延期した場合は、最初の表示時に本文・CW・添付metadata・投票を引き継ぎ、その後の復帰では入力を再初期化しない。レビューで見つかったKeepAlive非活性中の再取得延期と、Modalのref設定前に終了通知を送る問題も修正し、Dialogを経由する回帰試験を含めた。

| 対象 | 結果・範囲 |
|---|---|
| Webの共有処理 | PASS。9ファイル68件。通常のブラウザvisibility、ネイティブだけが非表示の場合、Vue反映待ち、購読の解除、例外時の他の購読処理、非表示中の初期取得延期、初回の投稿内容引継ぎと復帰後の編集保持を検査。HomeはAPIをmockし、本文・人物・添付・リアクションを参照へ置換、非表示中の要求停止、検証待機中の本文非表示、古い検証応答の拒否、失効後の除去を確認 |
| ネイティブの制御 | PASS。Simulatorと実機で新しい9ケース。実WKWebViewで注入APIの変更不可・偽の制御nonce拒否、非同期の破棄完了待ち、合成本文/人物の除去と通常入力の保持、購読例外、過去の応答・既知の購読からの無対応への後退の拒否、5秒timeout、再確認、終了時の取消を確認。認可APIの実連携比較ではない |
| PWAの実画面の復帰 | PASS。Simulatorと実機でScratchpadへ合成の通常入力を行い、ホーム移動とアプリ復帰を2回繰り返して値とWebView識別子が一致。これはプロセス強制終了やIME変換中の保持の確認ではない |
| 実機の回帰 | PASS。同じ通し実行でアプリ内35件・UI3件、skip/失敗なし。上の復帰、本人限定の通常Misskeyノートが退出・履歴・再起動で出ないこと、2アカウントの往復切替と再起動後のidentityを確認。通常Misskeyの本人限定ノートはGridSpace私有ノートの代用とはしない |
| ビルド・型・安全検査 | PASS。最終`check-mac.sh`のCore 19件・SDKビルド、署名付き実機ビルド、frontend build、共有lifecycleモジュールのstrict型検査、変更ファイルlint、SPDX 2958、locale safety、diff検査。Vueレビューの指摘を修正して再確認済み。全体vue-tscは前述のメモリ不足・中断を引き続き区別し、今回のPASSには含めない |

Web単体は`/tmp/gridspace-native-lifecycle-web-unit.log`、限定した型検査は`/tmp/gridspace-native-lifecycle-targeted-types.log`、frontend buildは`/tmp/gridspace-native-lifecycle-frontend-build.log`。最終Mac検査は`/tmp/gridspace-native-lifecycle-mac-final.log`、shippingは`/tmp/gridspace-native-lifecycle-shipping.log`（`--base HEAD`）。最初のMacビルドではSDKのcallback overloadの指定誤りで失敗し修正済み。単体試験作成中のmock/描画待機の失敗は`/tmp/gridspace-native-lifecycle-composer.log`、`/tmp/gridspace-native-lifecycle-late-mount.log`にあり、最終合格と区別する。

Simulatorのアプリ内全体実行は`/tmp/gridspace-native-lifecycle-simulator-all-final.log`で33件中32件PASS・PWA環境を要する既存1件SKIP。その後追加したtimeout/遷移取消を含む新しい9件の対象再試験は`/tmp/gridspace-native-lifecycle-simulator-nine.log`で全件PASS。実画面の復帰は`/tmp/gridspace-native-lifecycle-pwa-simulator.log`、`/tmp/gridspace-ios-parity-lifecycle-sim-1BwBsE/result-0aba36c684bc4da7ac36c4570ddc6ad6.xcresult`でPASS。実機の35件とUI3件の通し成功は`/tmp/gridspace-native-lifecycle-device.log`、`/tmp/gridspace-ios-parity-lifecycle-usb-4nhBJd/result-4e3b10ee2b774ad688c9ed0e5ae8a782.xcresult`。終了後は通常起動へ戻し、試験サーバーとUSB接続維持を終了した。資格情報・端末診断・入力ログは共有しない。

新しいWebは実サーバーへ未配布。実連携先のGridSpace私有APIによる復帰・許可撤回、返信/引用targetのprops等を含む全保持箇所、媒体URL・キャッシュ・OSスナップショット、複数窓、旧OS、IME変換中の比較は残っている。特にchannel返信/引用フォームへ渡した取得済みtargetの全参照破棄を、この共通通知だけで達成したとはしない。次は連携済みの2サーバーfixtureと保持箇所の照合を進める。S1全体や後続段階の完了にはしない。

### 返信・引用の対象ID化と2サーバー比較

2026-11-16。上の残件のうち、ダイアログのpropsに取得済みの返信・引用targetが残る問題を修正した。`gridspacePost`へ渡すデータを明示した許可項目に絞り、対象は`replyId`/`renoteId`だけにする。本文・人物を持つtargetはフォーム内の1つのrefで保持し、非表示時に破棄する。復帰時はprepareに加えて`gridspace/private-notes`のshowで対象ID・channel IDを照合し、両方が有効なときだけ表示する。失敗や世代の古い応答から以前のtargetを復元しない。

返信元から継承した未編集CWはtargetに属する値として破棄・再取得する。利用者が編集した本文・CW、選択した添付候補と投票は自分の下書きとして保持し、画面全体の再読み込みはしない。初期引継ぎと復帰後の編集保持を区別する。今回の変更だけで、メニューのクロージャー等も含む全参照やJavaScriptヒープ全体の消去を保証したとは扱わない。

`private-parity-server.mjs`はloopbackだけに2つの実backendを起動する。起動ごとの専用DB・Redis名前空間、短期CA・証明書、一般利用者・未連携利用者・連携元利用者・作者を生成し、OAuthの実同意・コールバック・finishを通して連携する。フォロワー限定の合成ノートとチャンネルの合成ノートを実APIで作り、未連携の別利用者には前者を取得できないことを検査する。チャンネル投稿のprepareと通常ログインの最初の要求も起動前提として検査する。DBへの認可情報の直接挿入、実アカウントの使用、本番設定やシステムの信頼設定の変更はない。

試験環境の実通信から、別々に2件のbackend不具合を修正した。ポート付きhostを`domainToASCII`へ渡すと空文字となり、ActivityPubで別の接続先をローカル扱いしていた問題は、hostとportを分けて正規化する。Node 26でIPリテラルを明示的なTLS SNIに設定できない問題は、IPの場合にSNIを省き、証明書のidentityは正規のpeer hostに対して検証する。transportのIPに一致する証明書だけでは許可しない。APIスキーマ・entity・migrationは変更していない。

| 検査 | 結果・範囲 |
|---|---|
| Web単体 | PASS。7ファイル39件。targetのIDだけの受渡し、許可した引継ぎ項目、復帰時の再取得・遅延応答・不一致・失効、継承CWの更新と編集CWの保持。実APIの比較とは別 |
| backend単体 | PASS。3ファイル45件。修正前はhostの回帰が11件、TLSの回帰が3件失敗。修正後はhost/port・Unicode・IPv4/IPv6・ActivityPubのローカル判定と、実TLSによるHost/SNI・canonical identity・不正証明書拒否を確認 |
| 実PWA比較 | PASS。Chromium/WebKitで、実bootstrapの非表示APIをdocument.hidden=falseのまま呼び、Vueの破棄完了応答・引用本文/人物のDOM除去、実API応答を遅延させた再認可待機、作者の変更反映と自分の下書き保持を確認。実際にprivate grantを撤回し、チャンネルへ新規投稿できる権限が残っていても旧targetの表示・送信が再開しないこと、実OAuth再認可後に新しいtargetと下書きが戻ることも成功。投稿送信はしていない |
| 比較の境界 | WebKitのmessage providerは合成で、Swiftからのライフサイクル通知・実機の試験とは区別する。自己署名の短期CAがServiceWorkerの信頼設定に入らないため、最終ブラウザ比較はServiceWorkerを明示的に無効化。オフライン・キャッシュの比較結果には含めない |
| iOSアプリの実連携比較 | PASS。iPhone 17 Pro Simulator / iOS 26.5で新しいUI試験1件。通常のログイン・再起動後に連携先のチャンネルノートを引用し、自分の下書きを入力。2回のホーム移動・アプリ復帰後に、引用対象と入力値が表示され、WebView識別子が一致し、復帰失敗のRetryが出ないことを確認。Swift・実bootstrap・実Web・2サーバーのAPIを通す。アプリ上でのgrant撤回の試験ではない |
| ビルド・型・安全検査 | PASS。`check-mac.sh`のCore 19件・SDKビルド、frontend/backend build、test-serverを含むbackend型検査、変更ファイルlintとtest-server専用lint、SPDX 2960・locale safety・diff検査。全体vue-tscは前述の未完了と区別 |

単体は`/tmp/gridspace-private-target-unit-full.log`、`/tmp/gridspace-private-pair-units-final.log`。修正前の再現は`/tmp/gridspace-private-pair-host-before.log`と`/tmp/gridspace-private-pair-tls-before.log`。frontend buildは`/tmp/gridspace-private-target-frontend-build.log`、backend buildは`/tmp/gridspace-private-pair-backend-final.log`、test-serverを含む型検査は`/tmp/gridspace-private-pair-types-verified.log`、専用lintは`/tmp/gridspace-private-pair-test-server-lint-final.log`。Mac検査は`/tmp/gridspace-private-target-mac.log`、安全検査は`/tmp/gridspace-private-target-shipping-last.log`（`--base HEAD`）。Vueレビューの指摘なし。全体vue-tscのメモリ不足・中断は前述どおり区別する。

最終の2サーバーfixtureは`/tmp/gridspace-ios-parity-pair-wblnlL`、ブラウザの成功は`/tmp/gridspace-private-target-real-chromium-with-login.log`と`/tmp/gridspace-private-target-real-webkit-with-login.log`。先行するloopback fixtureでも両エンジンが成功したが、最終fixtureでは通常ログインの前提も検査した。Simulatorの成功は`/tmp/gridspace-private-target-native-simulator-complete.log`、`result-254b38c872bf442da722222f862e509d.xcresult`。55.1秒の1件で失敗・skipなし。Simulatorを通常起動へ戻して所有サーバーを終了した。試験用資格情報・trace・XCTestの入力ログは共有しない。

終了後、所有していたworkerの終了・61812–61815の閉鎖に加え、今回の一連のpaired fixtureで作成した専用DB・Redis名前空間・live manifestが残っていないことを読取り検査した。結果は`/tmp/gridspace-private-pair-cleanup-verified.log`。共有のDB/Redisサービス自体は停止していない。

最初の比較失敗は、メニューのアイコンを含むaccessible nameの選択、上記backend不具合、fixtureの連合無効・署名pool未初期化、短期CAに対するServiceWorker拒否、撤回後も「対象付きprepare」が成功するという試験側の誤った前提を含む。最終試験は対象なしのチャンネルprepareで投稿権限を確認し、対象付きでは失効が反映されることを検査した。これらの失敗を最終合格と混同しない。

Simulatorの初回はテストコードのquery型指定でビルドが失敗。次はUNIX socket経由のfixtureで接続元IPが未設定となり、ログインが500で停止した。loopbackだけが到達する私有socketのproxyに合わせて転送元IPを設定し、起動時に通常ログイン要求も検査するよう修正。その後、メニューの選択と、modalの背後にある親ページもAX上で数える誤った期待を修正した。失敗は`/tmp/gridspace-private-target-native-simulator.log`、`...-final.log`、`...-with-login.log`、`...-menu-fixed.log`にあり、最終合格とは別に保持する。

実連携の全保持箇所、実機でのprivate grant撤回、媒体URL・URLCache・OSスナップショット・複数窓・旧OS・IMEの比較は残件。新しいWebは実サーバーへ未配布で、S1全体やS3以降の完了にはしない。

### 連携引用の実機復帰・許可撤回・再認可

2026-11-16。前節の実機残件のうち、チャンネル内引用のバックグラウンド復帰・人物更新・private grant撤回と再認可を実APIで比較した。通常のログイン後にアプリを再起動し、引用へ自分の入力を行い、ホーム移動と復帰を2回繰り返す。さらに非表示中に合成作者の名前を更新し、復帰後の表示更新を確認する。非表示中に実際のprivate grantを撤回した後は、旧本文・人物が出ず送信できないことを確認した。チャンネルへの新規投稿権限が残ることもAPIで検査し、それを対象本文の読取り許可と混同しない。実OAuthの同意・コールバック・finishで再認可すると、更新後の引用対象と自分の下書きが戻り、WebView識別子も一致する。UI試験から投稿送信はしない。

実機からMacの2サーバーへ接続するため、Debug試験だけで使うCONNECTプロキシと、origin別の試験証明書検証を追加した。接続先は2つの予約名とポートに固定し、実機用は指定したUSB端末、Mac用はloopbackからの接続だけを許可する。別の生成資格情報を要求し、他の宛先や期限切れは拒否する。TLSは終端しない。Webデータストアと制御用URLSessionにだけ設定し、直接通信へのfailoverは許可しない。システムのプロキシ・DNS・ルート・信頼設定は変更しない。Node worker内で予約した2名だけを解決し、OAuthのURL規則・Host・署名・TLS identityを保持する。

合成作者の更新とgrantの撤回・再認可は、テストrunnerのnative URLSessionから閉じた制御経路を呼んで実APIを実行する。制御要求にアクション以外の任意endpointは指定できず、生成秘密はWebやURLへ渡さない。制御通信のリダイレクトも許可しない。これをアプリの認証済みbridgeや、第一者tokenをSwiftへ移す実装とは扱わない。

| 検査 | 結果・範囲 |
|---|---|
| 実機 | PASS。同じ実行でアプリ内38件とUI1件、失敗・skipなし。上の通常ログイン・再起動・引用入力・2回の復帰・作者更新・許可撤回と再認可を実Swift/Web/APIで確認。アプリ内には匿名PWAの起動と、origin/指紋/期限・peerへの認証情報非送信・プロキシ制限・DebugのATS範囲の検査を含む |
| Simulator | PASS。iPhone 17 Pro / iOS 26.5、通常のloopback fixtureでアプリ内38件と更新後のUI1件が同じ実行で成功。作者更新・許可撤回・再認可と下書き復元までを含み、失敗・skipなし |
| CONNECTの比較 | PASS。宛先外・別ポート・不正なauthority・認証なし/誤認証・期限切れの拒否を検査。2つの実backendへのTLS接続でCA検証を有効にし、受け取った実leafの指紋とHTTP応答を照合。プロキシが証明書を置き換えないことを確認 |
| PWA | PASS。同じUSB用fixtureへMacのChromium/WebKitから接続し、前節の取得遅延・人物更新・許可撤回・OAuth再認可と下書き保持を再検査。匿名の両ブラウザ起動も成功。ServiceWorkerは前節と同様に対象外 |
| ビルドと安全検査 | PASS。`check-mac.sh`のCore 19件とSDKビルド、署名付き実機ビルド、Release SDKビルド、変更ファイルlint・SPDX 2960・locale safety・diff・試験JS/Python構文検査。Releaseの生成Info.plistに試験用ATS例外とFiles共有がないことも確認。全体vue-tscの既知の未完了を合格には含めない |

実機の通し成功は`/tmp/gridspace-paired-private-device-full.log`、fixtureは`/tmp/gridspace-ios-parity-pair-usb-iyd7zk`、`result-62e6f94755db4e568b58e95ca1ef2bd7.xcresult`。アプリ内38件は7.6秒、UI1件は55.8秒。終了後はrunnerが通常アプリを起動した。PWAは`/tmp/gridspace-paired-private-chromium.log`と`/tmp/gridspace-paired-private-webkit.log`、CONNECTは`/tmp/gridspace-paired-transport-buffered.log`。Mac/Releaseは`/tmp/gridspace-paired-private-mac.log`、`/tmp/gridspace-paired-private-release.log`。安全検査は`/tmp/gridspace-paired-private-shipping.log`（`--base HEAD`）。資格情報・端末情報・入力ログ・traceは共有しない。

Simulatorの通し成功は`/tmp/gridspace-paired-private-simulator-full.log`、`/tmp/gridspace-ios-parity-pair-sim-ZecnW2/result-6417c456d57d405e9da3433abdbca0fe.xcresult`。アプリ内38件は16.3秒、UI1件は62.5秒。試験後はSimulatorも通常起動へ戻した。

後片付けでは、所有したworker・USB接続維持の終了、61812–61816の閉鎖、生成したpaired fixture全体の専用DB・Redis名前空間・live manifestとUSB metadataの除去を読取り検査し、`/tmp/gridspace-paired-private-cleanup.log`で成功。共有DB/Redisサービスは停止していない。

初期の失敗には、OAuthがULAのIPをclient IDに許可しないこと、実機のloopbackへの直接通信、試験コードの`try`不足、DarwinのIPv6 parserがscope付き文字列を受理すること、proxy除外ドメインの期待値との不一致、自己署名の試験DNSに対するATS制約、iOS 27での結合されたAXテキストに対する完全一致指定があった。OAuthを緩めず予約DNSとプロキシへ変更し、proxy addressのscopeを拒否し、除外ドメインは公開C APIで明示的に消去・列挙検査した。CONNECTで早く届くTLSデータも保持するようにしたが、それだけでは起動は直らず、最終的にATS設定後に匿名PWAが0.7秒で起動した。Debugの2つの予約名だけの例外は[Appleの手動検証用の説明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionallowsinsecurehttploads)に従い、指紋・ホスト・期限・TLSバージョン・forward secrecyの検証は保持する。Releaseへは含めない。

失敗と切り分けは`/tmp/gridspace-paired-private-device.log`、`...-dns.log`、`...-dns-compiled.log`、`...-handles.log`、`...-navigation.log`、`...-challenge.log`、`...-buffered.log`、`...-ats.log`に保持する。最終の成功と区別する。実サーバーへ新しいWebは未配布で、媒体・キャッシュ・OSスナップショット・メニューの保持箇所・複数窓・旧OS・IME・パスキー/CAPTCHAは残件。S1全体やS3–S5の完了にはしない。
### ネイティブ主要画面の先行実装と非公開メニューの回帰確認

2026-11-16のユーザー指示に合わせ、SwiftUIのTL・検索・通知・プロフィール要約・ノート詳細・簡易投稿を先行実装した。[実装範囲と未対応項目](native-client.md)を参照。S1やS4全体の受入完了とは扱わない。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 23件**。MiAuthのorigin/state、UUID表記、ページ境界の重複、Web編集への本文/CW/公開範囲/返信ID、CWなしと空CWの区別を含む |
| 実機アプリ内 | **PASS 47件、skipなし**。通常APIのJSONと認証、異なるクライアント間で資格情報が混ざらないこと、Keychainの実保存・更新・削除とport分離、下書きと結果未確認の保存、既存のWeb/添付/復帰検証を含む |
| ネイティブUI・実機 | **PASS 1件**。実際の隔離サーバーでMiAuth check、TL、プロフィール、ノート詳細、背景復帰後の自分の下書き、CW付きfollowers投稿、通知、検索、ホーム、退出後の非表示を確認。操作試験はアプリ内試験とは別の実行 |
| ネイティブUI・Simulator | **PASS 1件**で同じ操作を比較。Nativeの主要画面にはWebViewが存在しないことも確認 |
| SimulatorのKeychain | **SKIPPED**。署名なしテストホストの`-34018`を実測。署名付き実機の保存試験はskipせず成功。その他のSimulatorアプリ内試験は成功 |
| frontend unit | **PASS 9ファイル51件**。popupのabort・遅いimport・確認待ち・drawer子メニュー、媒体変更/非表示/unmount、Lightbox/Modalのfocusと履歴/anchor復元、同一再検証とaction後の再検証、Web編集のCWを含む |
| 実API・Chromium/WebKit | **両方PASS**。実際のOAuth連携、古い本文の破棄、読込遅延、作者変更、grant撤回と再認可、自分の下書き保持。Native message providerは合成でありNative認証の証拠ではない。SW/cache試験ではない |
| Web互換・Simulator | **PASS UI 1件**。変更後のフロントエンドで連携チャンネル引用を操作し、背景復帰・許可撤回・再認可を実サーバーの値と比較 |
| ビルド・規約 | frontend全ビルド、署名付き実機ビルド、Release SDKビルド、変更ファイルlint、SPDX、locale safetyを確認。全体vue-tscの完走をこの結果で代替しない |

主な証拠はprivate一時領域の`gridspace-native-client-core-final.log`、`gridspace-native-client-device-units-final.log`、`gridspace-native-client-device-touch.log`、`gridspace-native-client-sim-complete-2.log`、`gridspace-native-client-web-units-complete.log`、`gridspace-native-web-{chromium,webkit}-regression.log`、`gridspace-native-client-web-quote-final.log`。実機UIの結果は`35fce3804ba4426d98a76c7e27fe4f68`、Simulator UIは`32af2c7168b24605b2a125074ae06f1c`。資格情報の不変化・view分割後の追加試験も成功し、実機47件は`f637b537a25e465faab3a2e804f9b58b`、SimulatorのNative UIは`7cb90bf7121f495384eed2db3199ae1d`、Web互換の引用は`2a383abf3edb400cb11c8d21ef6f9332`へ記録した。

実機・Simulatorの投稿は隔離DBの合成アカウントだけで行い、保存された件数・CW・visibilityを正規APIで照合した。本番へ投稿していない。認可の準備はfixtureの正規`miauth/gen-token`で行い、アプリへ渡すのは一回限りのsession IDだけ。ASWebAuthenticationSessionの実ログイン・同意UI、パスキー/CAPTCHA、全通知・全メディア・MFM/プラグイン・連携TL・複数窓は未完了。

途中の不合格は成功扱いしない。AsyncBytesのtask delegateへfixtureの厳密なpin検証を渡す修正、押せない余白と小さい操作領域の修正、一覧の破棄に依存しないIDスタックへの変更、検索権限を明示した新しいfixtureで再試験した。実機の自動操作許可待ちと通知による画面遷移の失敗もあった。端末の個人通知が含まれた失敗記録は外部送信せず削除した。並列XcodeGenの競合は生成を再利用するopt-inフラグと別run-dirで回避し、同じ投稿件数を変更するUI試験は直列に実行する。

Web側では非表示・権限変更時のメニューと媒体viewerをabortし、遅いimportや子メニューの再表示を止める。通常のメニュー選択後の確認は続けられる。同じ認可済みデータの再取得は開いたメニューを閉じず、actionの一時応答は新しいpropsへ戻す。これらは限定した単体・引用の回帰確認であり、全私有媒体・キャッシュの実機比較完了とは扱わない。

片付け後、今回の8設定に対応するDB・Redisキーは0件、61812–61816の試験リスナーとUSB metadata・live manifestは残っていない。端末は通常起動へ戻した。`check-mac.sh`とRelease SDKビルドも最後に成功し、Release plistにDebug用ATS例外・Files公開がないことを確認した。
## ネイティブMFMと画面操作テストの再試行（2026-11-16）

基本MFMをUIKitで表示し、同じ`mfm-js`のオフライン解析器をJavaScriptCoreで使う。対象・上限・高度な関数のWeb表示・静止画絵文字の制約は[ネイティブクライアント](native-client.md)へ記録した。S4全体の完了や全MFMのN/H互換とは扱わない。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 28件**。実際のWebパーサーから生成した8種類の構文fixtureとの比較、入力のデータ渡し、別context、サイズ上限、リモートメンション・タグ・検索のURL構築、実行scheme/資格情報/未知絵文字の拒否を含む |
| 実機アプリ内 | **PASS 53件、skipなし**。追加6件は装飾の組合せ、コードの空白、ぼかしの非表示と明示解除、数式・高度な関数のWeb表示、リンク、plainと未知絵文字、画像絵文字のコピー名。色の処理を調整後もこの6件は再試験して成功 |
| 実機UI | **PASS 2件**。隔離サーバーの実MiAuth checkでネイティブTLを開く。MFMの装飾、外部リンクの確認/取消、ぼかしの解除、背景復帰後の再非表示、数式から同じノートのWeb表示。既存のプロフィール・詳細・CW/followers投稿・下書き復帰・検索・通知・退出の回帰も同じ実行で成功 |
| Simulator | **PASS アプリ内52件、Keychain 1件SKIPPED**。UIの既存主要操作1件とMFM1件を別実行で確認。初回は確認画面の取消要素を取得できず失敗し、popoverの外側タップも扱う試験へ修正後、MFMの6件とUI1件が成功 |
| ビルド | **PASS** `check-mac.sh`、Release Simulator SDK、署名付き実機。通常起動へ戻した。ReleaseにDEBUGのATS例外・Files共有設定がないことも確認 |
| 生成物・規約 | **PASS** `build-mfm.mjs --check`、変更集合のlint/SPDX/locale safety、`git diff --check`。Web/Backend本体の変更はこの追加では行っていない |

実機は`gridspace-mfm-device-units.log`（`091404c14d434799906e497d485aa5d2`）と`gridspace-mfm-device-touch.log`（`6fa2eb40e2644b359cba3fc4f12ead60`）。Simulatorは`gridspace-mfm-simulator.log`の主要操作成功と、再試験`gridspace-mfm-simulator-touch.log`（`2186797cc7814658aa445a5efe90317f`）を区別する。Core・SDK・規約の証拠は`gridspace-mfm-{mac-final,release,shipping}.log`。結果はcheckout外の非公開一時領域にある。画像確認には合成アカウントだけのSimulator添付を使い、実機画面を撮影していない。

今回の実機UI操作では自動操作の再認証待ちによる停止はなかった。本番アカウント・本番投稿・実写真を使っていない。静止画絵文字の実HTTPダウンロードと失敗経路・アニメーション、全装飾引数、構文強調、選択・VoiceOver・設定・プラグインとの比較は残る。合成fixtureの両DBとRedis名前空間の残存が0件、61812–61816の待受けなし、USB保持プロセス終了とmetadata削除、live manifest/xctestrun削除を確認した。
## ネイティブの原本添付・ドライブ選択・添付付き下書き（2026-11-16）

写真/動画・Filesの原本選択、名前/説明/センシティブ指定、順次アップロード、添付だけの投稿、並べ替え、ドライブの最近のファイル選択を先行実装した。[範囲と保存・認証の境界](native-client.md#ネイティブの添付)を参照。アプリ用MiAuthにread/write:driveを追加したが、第一者トークンやsecure APIは使わない。加工・圧縮・撮影・連携ドライブなどを含むS4/S5全体の完了とは扱わない。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 28件**。MiAuthの要求権限追加を含む。`check-mac.sh`で実行 |
| 実機アプリ内 | **PASS 65件、skipなし**。原本のコピー・元URL消滅後の保持・サイズ/シンボリックリンク拒否・孤立ファイル回収、multipartのバイト列とheader注入防止、Bearer認証、添付のみのpayloadと順序、所有者不一致拒否、旧下書き互換、scopeと順序の保存、読めない保存記録の保持、部分成功・4xx・応答喪失・中止・古い選択の無効化、削除/並べ替え後の行binding、Photos providerのコピー前サイズ拒否を含む |
| 実機UI | **PASS 3件、同じ通し実行**。追加の1件では実MiAuth check→合成2ファイルの選択/属性入力→アプリ終了/再起動→原本復元/実アップロード→保存/再表示→並べ替え→本文なしのfollowers投稿→ドライブ再選択/下書き破棄を確認。既存のMFM・背景復帰・CW投稿・プロフィール/詳細・検索・通知・退出も成功 |
| 投稿とドライブの照合 | **PASS**。隔離サーバーの正規APIでノート件数+1、ドライブ件数+2、ファイルの順序/名前/説明/センシティブ属性、合成原本と2ファイルのMD5一致、再表示/再選択/下書き破棄でドライブ件数が増減しないことを比較 |
| Simulator | **PASS 対象再試験**。添付UI1件、MFMと既存主要操作の各1件を別実行で確認。61件構成のアプリ内は60 PASS + Keychain 1 SKIPPED、追加の状態管理4件も対象試験で成功。最新65件の全通しは実機の証拠を使う |
| SDK・規約 | **PASS** `check-mac.sh`、Release SDK、署名付き実機ビルド、生成物一致、変更ファイルlint/SPDX/locale safety、diff空白検査。ReleaseにDEBUGのATS例外・Files共有設定がないことを検査 |

Simulatorの通し試験で、投稿後に配列を空にすると破棄中のSwitchが古いindexを参照するクラッシュを検出した。添付IDによるbindingに変え、削除後の読み取り・再挿入禁止と並べ替えの単体試験を追加し、実機の投稿後まで再確認した。ファイル名入力のcaret位置、Form内のTextEditor/キーボードに吸収されるスクロール、小さい端末で画面外にある通知末尾の操作も自動試験へ反映した。

最終の実機結果は`gridspace-native-attachments-device-verified.log`、`fbd825019f684d7b953a9df1664e344e`。Simulatorの添付成功は`gridspace-native-attachments-simulator-drive.log`、`6000f359a7f742aa9fb51bb0cd4636e7`。後者より後の読めない下書き・Photos上限の追加は、最終実機65件とSDKで確認した。Core/SDK/規約は`gridspace-native-attachments-{mac-verified,release-verified,shipping-final}.log`。すべてcheckout外の非公開一時領域に保存している。実機画面を意図的に撮影せず、失敗した実機のresult bundle 2件は確認後に削除した。

実機を最新の通常起動へ戻した。本番アカウント・写真ライブラリ・本番への投稿/アップロードは使っていない。テストで作成したドライブ12項目に属する36 storage keyだけを回収し、残存0を確認。両方の専用DBとRedis名前空間も0、61812–61816の待受けなし、USB保持プロセス終了とlive manifest/xctestrun削除も確認した。

PhotosUI/Filesの実画面からの全選択経路、iCloud/大容量/全形式、原本保護属性の全状態比較、ドライブ属性変更時の送信停止と読めない記録のUI比較、強制終了/保存失敗の全境界、Webとの下書き同期、全加工・プラグイン・連携・VoiceOverは継続する。今回の限定した合格を、これらの互換性の証拠に広げない。
## ネイティブの会話・返信と通常投票（2026-11-16）

ノート詳細に親の会話と返信のページングを追加し、通常の単一/複数回答の投票、期限、投票済み状態、結果の再取得を実装した。[範囲・API・未対応](native-client.md#会話と投票)を参照。投票作成や連携先の代理操作、S4/S5全体の完了とは扱わない。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 30件**。単一/複数回答で既存票を再送できないこと、別項目への投票、範囲外index、正確な期限境界、未知の日付を開放しないこと、MiAuthのwrite:votes追加 |
| 実機アプリ内 | **PASS 76件、skipなし**。親のoffsetと返信のuntilId、境界の重複排除、非表示の対象で追加取得しないこと、片方の節の失敗、画面終了後の遅い応答破棄、整数の投票/204応答、応答喪失後の読取照合、再送抑止、未確認結果の停止、古い確認の世代失効を含む |
| 新規UI・Simulator | **PASS 2件**。正規APIで作った非表示の親、表示可能な親、31件以上の返信を読む。ページ送り後にネイティブ返信を送り、対象への件数増加を照合。投票の取消、単一回答のロック、複数の別項目への投票、期限切れの送信不可と0票を確認 |
| 実機UI | **PASS 既存3件 + 会話1件、および投票の対象再試験1件**。同じ通し実行では76件とUI4件が成功し、投票1件は検索結果の画面外にある選択肢を取得できず失敗。項目をスクロールして探す試験へ修正後、投票1件が成功。全5件を同じ最終実行で通したという意味ではない |
| 実APIの照合 | **PASS**。非表示の親は実際の公開範囲変更とpackerで作り、本文・人物・操作を描画しない。投票はAPIからsingle `[1,0]`、multiple `[1,1]`、expired `[0,0]`を照合。取消時は`[0,0]`のまま。期限切れへの直接APIも`ALREADY_EXPIRED`を返す |
| SDK・規約 | **PASS** `check-mac.sh`、Release SDK、署名付き実機ビルド、生成物一致、変更ファイルlint/SPDX/locale safety、diff空白検査。ReleaseにDEBUGのATS例外・Files共有設定がない |

実機の通し試験は`gridspace-native-social-device-complete.log`。result `4a000c069b2643ffa73e2e89e80f32b6`の集計は81件中80成功・1失敗・skipなし。画面診断を持つ失敗bundleは削除し、`gridspace-native-social-device-{summary,tests}.json`へ集計と各ケースの結果を残した。投票の再試験は`gridspace-native-social-device-poll.log`、`e4d974af9d9c49dfa0990be042a40133`。Simulatorは`gridspace-native-social-simulator-retry.log`、`9c477abcf64b4a538a92d275ce7cb796`。SDK/規約は`gridspace-native-social-{mac-final,release,shipping}.log`。資格情報と結果はcheckout外の非公開一時領域に置いた。

準備の初回は合成アカウント名が20文字を超えて500となり、アカウント作成前に停止した。許可される名前へ修正し、新しい隔離DBで再実行した。初回と再実行の4 DB/Redis名前空間は終了後の読取で残存0、2合成ドライブ項目の6 storage keyも残存0。61812–61816の待受け、USB保持プロセス、live manifest/xctestrunを片付けた。実機は通常起動へ戻した。本番の認証情報・本文・投票・写真は使っていない。

Webの全表示設定・プラグイン・カスタム絵文字、投票作成、複数窓/全ストリーミング更新/大規模会話/全障害境界、GridSpaceの連携先代理操作は継続する。既存のWeb操作も維持し、限定した合格を全機能の互換性へ広げない。

## ネイティブのプロフィール・投稿タブ・フォローと人物一覧（2026-11-16）

プロフィールの紹介文/項目、投稿・返信を含む・メディアのページング、フォロー/解除・鍵アカウントへの申請/取消、フォロー中/フォロワー一覧を追加した。[実装範囲と制約](native-client.md#プロフィールとフォロー)を参照。MiAuthへ`write:following`を追加し、既存トークンの権限不足では再ログインへ案内する。受信申請の管理・プロフィール編集・ミュート/ブロック・連携先の代理操作やS5全体を完了とは扱わない。

隔離した実Misskeyに公開/鍵/一覧非公開の合成人物、31人の合成フォロワー、31件以上の投稿、返信、合成TXT添付を作った。フォロー中一覧とフォロワー一覧の方向、関係IDのカーソル、投稿のフィルター、実際のフォロー/申請状態を照合する。今回も本番アカウント・本番投稿・写真ライブラリを使っていない。

初回Simulatorでは88件のアプリ内試験のうち87成功・Keychain 1 skip、プロフィールUIのうち2成功・1失敗だった（合計91件、89成功・1失敗・1 skip）。失敗は非公開一覧の`FORBIDDEN`がHTTP 400で返る仕様をHTTP 403だけで判定していたため。HTTPと意味上のエラーコードの両方を判定するよう修正し、実機の同じ操作で成功を確認した。

その後、関係変更を送信する前に投稿と待機中ページの世代を破棄し、関係の確認後に投稿も再取得する処理を追加した。前の関係で取得した遅いページの破棄、解除後に再取得を拒否された場合の本文消去、結果未確認の間の本文消去と再送抑止を単体試験へ加えた。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 33件**。MiAuthの8権限、自己/引っ越し/ブロック/関係不明の操作制限、申請と解除の区別、関係の所有者・方向・人物IDの照合を含む |
| 最終実機 | **PASS 93件、skipなし**。アプリ内90件とプロフィールUI3件を同じ実行で確認。投稿の再取得/待機中ページ破棄を含む最新版。フォローと解除、31人以上のフォロワーのページングと人物への遷移、鍵の申請と取消、一覧非公開の拒否、投稿/返信を含む/メディアと投稿のページ送りを正規APIで照合 |
| 実機回帰 | **PASS 97件、skipなし**。投稿再取得の最後の追加前にアプリ内89件とUI8件を同じ実行で成功。添付の復元/実アップロード/投稿、MFM/ぼかし/背景復帰、TL/検索/通知/退出、会話/返信、単一/複数/期限切れ投票とプロフィール3件を含む。最終93件と混ぜて同じ実行の成績とは扱わない |
| Simulatorの対象再試験 | **PASS 11件**。プロフィール状態9件、人物一覧2件。意味上の拒否、関係変更、遅い応答、未知の結果から読取で復帰する経路を含む。全UIの最終証拠は実機を使う |
| ビルド | **PASS** `check-mac.sh`、Release Simulator SDK、署名付き実機。ReleaseにDEBUGのATS例外・Files共有設定なし。既存`PrivacyShield.swift`のSwift 6移行用Sendable警告は残り、Swift 5設定のビルドを妨げていない |
| 生成物・規約 | **PASS** MFM生成物一致、構文検査、変更集合のlint/SPDX/locale safety（`--base HEAD`）、diff空白検査。今回の追加ではWeb/Backend本体のAPI・schema・migrationを変更していない |

最終実機は`gridspace-native-profile-device-verified.log`、result `6c7adb365f1243aebd236a3ede899172`。その前の97件は`gridspace-native-profile-device-final.log`、`00be4d9c345c43c59101795fde7a49d9`。Simulatorの初回失敗は`gridspace-native-profile-simulator.log`、`05e17222dbf642f2b763b2c61d4c99ee`、11件の対象再試験は`gridspace-native-profile-refresh-units.log`、`89ede454913343a184f587b641c80239`。SDK/規約の最終記録は`gridspace-native-profile-{check-mac,release,shipping}-verified.log`。すべてcheckout外の非公開一時領域に保存した。

今回の再試行ではiOSの自動操作認証待ちによる停止はなく、最新版をインストールして通常起動へ戻した。画面診断の画像は合成データだけのSimulatorに限定し、実機画面を意図的に撮影していない。片付け後は両専用DBとRedis名前空間の残存0、今回所有する9 storage keyの残存0、61812–61816の待受けなし、USB保持プロセス/metadataとlive manifest/xctestrunの削除を確認した。

システムMiAuthのログイン/同意UI、リモート配送の全状態、サーバー間競合、全公開範囲と関係管理、VoiceOver/大文字/全画面サイズ、編集・受信申請・ミュート/ブロック・連携先操作は継続する。限定した合格をS5全体の互換性へ広げない。

## ネイティブのリノート・引用・確認付き削除（2026-11-16）

通常のリノート/引用をネイティブの投稿画面へ接続し、返信と引用を分けた下書き、公開範囲・連合なしの保持、送信直前の対象再取得、自分のノート/リノートの確認付き削除を追加した。[範囲・不明な結果・未対応](native-client.md#リノート引用と削除)を参照。通常の`write:notes`を利用し、権限の追加やsecure APIの制限解除をしていない。

公開範囲と連合なしは`NoteCreateService`のリノート/返信処理とも照合した。homeをhome以下、自分のfollowersをfollowersに限定し、ローカルのみを引き継ぐ。作成応答の対象IDと作者が違う場合も、成功として下書きを消さず結果未確認にする。新しく取得した他人の本文・人物を下書きへ追加していない。

隔離サーバーで作った合成home/local-onlyのノートに対して、取消時の件数不変、リノートの作成、引用の保存/再表示/作成、リノート削除の取消と成功を比較する。APIの一覧に加え、成功したUI試験の対象IDを使う読取専用SQLで、外側のリノートが消え、元のノートとhome/local-onlyの引用1件が残ることも照合した。別のケースでは投稿画面を開いた後に作者が既存ノートをfollowers限定へ変え、送信を止めて自分の入力を保持し、引用/リノート件数が増えないことを確認する。

Simulatorの初回試験は取消ボタンが独立した要素として出ないダイアログで失敗し、外側タップも使うようにした。次は検索中に非表示となるアカウントメニューを探して失敗したため、タイムラインへ移動してからプロフィールを開く手順へ直した。検索欄が自動で折り畳まれる失敗もあり、検索欄を常時表示する配置へ変更した。診断用のテストコードにあった変数名の重複によるビルド失敗1回も修正した。これらの失敗を合格へ混ぜず、対象再試験と実機の結果を分けて記録する。

実機の最初の通し試験は107件中105成功・2失敗・skipなし。アプリ内100件と既存UI5件が成功し、新規UI2件は検索結果のボタンを取得できず失敗した。画像を使わない実機のテキスト診断で検索APIの接続喪失`-1005`を確認し、次の試験では準備APIも`-1004`となった。隔離プロキシの親プロセスが未処理の`ECONNRESET`でexit 1になっていたことを、実プロセスとログで確認した。

CONNECT拒否後を含む接続ソケットとTLSソケットに切断処理を付け、試験用プロセスが切断1件で落ちないようにした。403/407を受け取ったクライアントがTCP resetする検査を追加し、その後も接続先制限・認証・期限と両実サーバーのTLS/証明書pinが機能することを確認した。UI試験の検索読取は`-1005`時だけ画面の「再試行」を最大2回使えるようにした。書込の自動再送は追加していない。投稿画面では送信エラーを上部に表示する。

停止した親に属する2 workerを、PIDと専用configの一致を確認して終了した。停止環境の専用2 DBとRedis名前空間、所有する6 storage keyを回収し、残存0を確認してから新しい環境を作成した。準備で停止した実機試験は102件中100成功・2失敗・skipなしで、UIを合格とは扱わない。失敗した実機bundle 2件は集計・各ケースの結果をJSONへ保存後に削除した。

作り直した環境では、公開範囲変更後の送信停止が実機でも成功した。102件の実行は101成功・1失敗で、残る1件は送信完了を背後の検索欄の存在で判定していたため、リノート件数の照会が早すぎた。投稿画面が閉じるかエラーが出るまで待つ試験へ変更し、作成・引用・削除の対象再試験が成功した。この失敗bundleも集計と各ケースの結果を保存して削除し、実機の失敗bundleは合計3件を回収した。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 37件**。pureリノートと引用のID解決、非表示/ID不一致/チャンネル/他人のfollowers/specifiedの扱い、home以下の公開範囲、Webへの引用先とlocalOnlyのtrue/false/未指定を区別する契約を含む |
| 最終ソースの実機アプリ内 | **PASS 100件、skipなし**。追加のAPI契約2件、下書きの引用/返信/アカウント/対象の分離1件、削除の所有者/隠されたノート/応答喪失/未確定結果/遅い確認/失効した画面を扱う状態管理7件を含む |
| 実機の新規UI | **PASS 2種類、別の実行**。非公開変更後の送信停止と自分の入力保持1件、およびリノート作成・引用下書きの保存/再表示/作成・削除の取消と成功1件。最後の102件実行で2件を同時に通したという意味ではない |
| 既存の実機UI | **PASS 5件、前の通し実行**。添付の復元/アップロード/投稿、MFM/リンク/CW/背景復帰、通常投稿/検索/通知/退出、会話/返信、単一/複数/期限切れ投票。最終の全7件を同じ実行で通したとは扱わない |
| Simulator | **PASS 対象再試験**。100件のアプリ内は99成功・Keychain 1 skip。新規UIの非公開変更1件と、検索欄/待機手順を修正した後のリノート/引用/削除1件は別の実行で成功 |
| 実APIとDB | **PASS**。取消時0件、作成後pure 1/quote 1、home/localOnlyの保持、削除後pure 0/quote 1と元ノートの保持、非公開化後に新規作成0件をAPIで比較。Simulatorと実機の成功シナリオそれぞれで、正確な対象IDを使った読取専用SQLでも外側の削除と元ノート/引用の保持を確認 |
| テスト用通信 | **PASS**。拒否されたCONNECTのTCP reset後も、認証・接続先制限・期限・両実バックエンドのTLSとpinが機能。実機試験の終了後にも同じ検査を通し、停止したプロセスを成功扱いしていない |
| SDK・規約 | **PASS** `check-mac.sh`、Release Simulator SDK、署名付き実機、MFM生成物一致、構文検査、作業ツリーのlint/SPDX/locale safety（`--base HEAD`）、diff空白検査。ReleaseにDEBUGのATS例外/Files公開なし。既存のSwift 6移行用`PrivacyShield`警告は今回変更していない |

最終ソースの実機100件は`gridspace-native-actions-device-final-source.log`、`f19886615fad4fb7b5cb50a9d3937681`。実機のリノート/引用/削除の成功は`gridspace-native-actions-device-flow.log`、`2553bfc797784786a78e1c37d3193428`。送信停止の成功は`gridspace-native-actions-device-final.log`のケース別結果で、`gridspace-native-actions-device-modal-{summary,tests}.json`へ保存した。最初の107件と通信準備で停止した102件はそれぞれ`gridspace-native-actions-device-{summary,tests}.json`、`gridspace-native-actions-device-transport-{summary,tests}.json`に残している。

Simulatorの100件と送信停止は`gridspace-native-actions-simulator-retry.log`、`111edead6b97474fb578557fa24fcf18`、作成/削除の成功は`gridspace-native-actions-simulator-flow-verified.log`、`3977e47d6f174dd695718378af51ebfe`。最終Core/SDKは`gridspace-native-actions-{mac,release}-final-source.log`、規約は`gridspace-native-actions-shipping-complete.log`、通信は`gridspace-native-actions-transport-final.log`。証拠はcheckout外の非公開一時領域へ置き、本番のアカウント・本文・投票・写真は使っていない。実機の画像や動画を診断に使わず、画面構造のテキストだけを確認した。

編集・削除して編集、チャンネル/連携先の操作、宛先指定・投票作成、全プラグイン/設定、Webのアカウント/下書き同期、保存直後の強制終了や全I/O失敗、全画面サイズ/VoiceOverは継続する。限定した合格をS4/S5全体の完了へ広げない。

最後のWeb引き渡しのfalse/未指定の区別まで反映したソースで、Core 37件、実機アプリ内100件とSDK/Releaseを再確認し、最新アプリを通常起動へ戻した。作り直した環境も終了し、専用2 DBとRedis名前空間の残存0、storage key 0件を確認した。停止環境で回収した6 keyと合わせ、2組の専用DB/Redisに残存はない。旧/新環境と実機用のlive manifest/xctestrun、USB保持プロセス/metadataを削除し、61812–61816の待受けがないことも確認した。

## ネイティブ通知のページ送り・種類の絞り込み・一括既読（2026-11-16）

通知のページ送りと20種類の選択、未読数/状態の再取得、確認付きの一括既読を追加した。[仕様と未対応](native-client.md#通知の一覧絞り込みと一括既読)を参照。MiAuthには通常の`write:notifications`を追加し、旧権限では読取を保ったまま再ログインを案内する。通常の取得には常に`markAsRead: false`を付け、行ごとの未読状態を推測して描画しない。

`NotificationService.getNotifications`がフィルター前の生のページを上限件数で読むことを確認し、短いページでも追加読み込みを続けるようにした。通知IDのカーソルと重複排除を使い、空または進まないページで止める。一括既読ではアカウントを再照合し、POSTは1回、操作後の件数もサーバーから読み、新着を含む件数を楽観的に0へ変えない。応答喪失時の自動再送を追加していない。

隔離した実Misskeyに31人からのフォロー通知、返信・リアクション・アプリ通知を正規APIで作った。権限を持つMiAuthと、`write:notifications`を持たない旧権限のMiAuthを分け、実際の通知未読数と既読エンドポイントの受信回数/204回数を比較する。本番のアカウント・通知・本文・写真は使っていない。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 39件**。9権限のMiAuth、20種類の値、未知の種類でpayloadの形式が変わっても通知の外枠を読めること、アプリ/招待payload、日時、エクスポートのファイル経路でpath/query注入を許さないことを含む |
| 最終実機 | **PASS 118件、skipなし、同じ実行**。アプリ内113件と既存の主要操作UI3件、新規通知UI2件。添付の復元/アップロード/投稿、MFM/リンク/CW/背景復帰、通常投稿/検索/通知/退出の回帰も成功 |
| 追加のアプリ内 | **PASS 13件**。APIの種類/カーソル/常時未読維持と204操作の2件、通知状態管理11件。短いフィルターページ/空ページ/境界重複、フィルターの切替、権限拒否/認証失効時の破棄、別アカウントの拒否、遅い応答/古い確認、旧版のboolean状態、応答喪失/読取失敗/新着のある既読結果と再送抑止を含む |
| 新規実機UI | **PASS 2件**。旧権限で一覧を読め、既読POSTは403となり、未読数と成功回数が変わらず本文を保持する。もう1件はアプリ通知への切替/ヘッダー、フォローの絞り込み、追加ページの最古の人物とプロフィールへの移動、背景復帰、取消で既読にしないこと、確認後だけ全体を既読にすることを確認 |
| 実APIの照合 | **PASS**。閲覧/フィルター/ページ送り/プロフィール遷移/背景復帰/取消で未読数と既読POST回数を維持。旧権限では試行だけ+1、204は増えない。確認後は試行と204がそれぞれ+1となり、絞り込み外の通知も含め未読0。UIの状態再取得でも0を表示 |
| Simulator | **PASS 114件、Keychain 1 skip**。アプリ内113件中112成功・1 skipと新規UI2件が同じ再試験で成功。初回はアプリ内112件中111成功・1 skip、UI2件が失敗したので、その114件を合格とは扱わない |
| SDK・規約 | **PASS** `check-mac.sh`、Release Simulator SDK、署名付き実機、MFM生成物一致、構文検査、作業ツリーのlint/SPDX/locale safety（`--base HEAD`）、diff空白検査。ReleaseにDEBUGのATS例外/Files公開なし。テスト用CONNECTの制限/認証/期限/TLS/pinと接続切断の検査も成功 |

初回Simulatorでは、通知行へ付けた識別子が子の画像やボタンへ伝わり、人物ボタン固有の識別子を上書きしていた。画像だけを探す試験と人物への遷移が失敗したため、行の識別子を取り除き、本文の表示も直接確認するようにした。再試験では人物への遷移まで成功した。通知の読取・ページ送りそのものを失敗と混同せず、初回の2 UI失敗を記録している。

最終実機は`gridspace-native-notifications-device-final.log`、result `b5f724bcc2564d78b222fbe95993aaae`。Simulatorの再試験は`gridspace-native-notifications-simulator-retry.log`、`ebbc8345617b4f32be175dfa5d0d79f2`。Core/SDKは`gridspace-native-notifications-mac-final.log`、Releaseは`gridspace-native-notifications-release.log`、規約は`gridspace-native-notifications-shipping.log`、通信は`gridspace-native-notifications-transport.log`。資格情報と結果はcheckout外の非公開一時領域へ置いた。画像の診断は合成データだけのSimulatorに限定し、実機画面を意図的に撮影していない。

グループ・個別既読・連携先/チャンネル・APNs、全種別の詳細/承認操作/実績名/予約失敗の復旧、削除済み通知だけのページ境界、全ストリーム更新・複数窓・VoiceOverは継続する。今回の限定した合格をS4/S5全体の完了へ広げない。

最新アプリを実機の通常起動へ戻した。片付け後は専用2 DBとRedis名前空間の残存0、今回の添付回帰試験が所有する6 storage keyの残存0を確認した。live manifest/xctestrun、USB保持プロセス/metadataも削除し、61812–61816の待受けがないことを確認した。


## 接続先固定のネイティブ構成・絵文字・タイムラインUI（2026-11-16）

ユーザー指示によりWebフォールバック方針を撤回した。[現行計画](../ios-native-client.md)を原本とし、通常起動を`misskey.grid-space.io`固定のSwiftUI/UIKit画面へ変更した。Webタブ/サーバー入力と機能別のWebボタンを外し、タイムライン・検索・通知・自分のプロフィール、ネイティブのドライブ/添付プレビューへ接続した。認可にはASWebAuthenticationSessionを使い、通常の操作画面にWebViewを使わない。外部記事のリンクは確認後にシステムブラウザで開く。

下線付きフィードタブ、丸いアバター、左の人物/右の本文、固定の下部アイコン、青い投稿ボタンへ変更した。カスタム絵文字のカテゴリ/名前/別名検索、センシティブ表示切替、最近32件、標準1,915件の日本語/英語検索、カーソル/選択範囲への挿入、リアクションの変更/解除と実際の状態の再取得を実装した。別端末や応答喪失で既に追加済みの場合、新しい追加の意図を削除へ反転させない。解除の意図も表示時の選択へ結び付け、新しい選択を消さない。

| 検証 | 結果・範囲 |
|---|---|
| Core | **PASS 42件**。新規3件はバンドル1,915件/9カテゴリ/複合文字/日本語検索、幅・大文字小文字・別名・ローカル短縮表記、センシティブ/ローカル限定/ロール/いいねのみの制限を含む |
| 実機のアプリ内 | **PASS 126件、skipなし**。絵文字/リアクションの新規13件を含む。UTF-16範囲への置換、Formの再利用、本文変更後の挿入拒否、古い応答/別アカウント/非表示/認証失効、結果不明の再送抑止、別端末との変更競合を検査 |
| 実機の主要UI | **PASS 5種類、複数の実行と対象再試験を含む**。添付の順序・属性・バイト列・下書き・ドライブ再選択/破棄、MFM/リンク/ぼかし/背景復帰、通常投稿/CW/公開範囲/検索/通知/退出、絵文字を含む下書き復元と投稿、カスタム/標準の検索・変更・解除を確認。全131件が一度の実行で成功したとは扱わない |
| 絵文字のサーバー照合 | **PASS**。正規APIで合成PNG/制限付き絵文字を作成。カスタムの追加後に選択と件数1を照合し、標準絵文字への変更後も件数1・create成功2回、解除後は選択なし/件数0・create成功2回のままであることを確認。投稿本文も短縮表記とUnicodeを保持 |
| Simulator | **PASS 127件 + Keychain 1 skip、同じ再試験**。アプリ内126件中125成功/1 skipと絵文字UI2件。iPhone 17 Pro / iOS 26.5の新規専用端末を使い、初回の本人復元と投稿画面の競合も修正後に確認 |
| 画像の最終表示 | **PASS 追加UI 1件**。Simulator上で既知の合成PNGの黄色い画素を検査し、汎用アイコンを成功扱いにしない。取得・TLS・デコード・表示更新後の実画像を確認し、合成画面を目視確認。実機画面を意図的に撮影していない |
| 固定先の公開API | **PASS**。認証情報なしの読取で公開カタログ2,523個/32カテゴリ/412,593 bytesを取得し、アプリCoreのデコーダーで全件とHTTPS URL、使用可能な名前を検査。Python既定の識別名はCloudflare 1010となったため、ブラウザを装わない`GridSpace-iOS/0.1`を宣言して取得し、API/画像/動画の識別名も統一した。本番への投稿・ドライブ追加はしていない |
| SDK/署名 | **PASS** `check-mac.sh`、Release Simulator SDK、署名付き実機ビルド/インストール/通常起動。ReleaseのATS例外とFiles公開キーがないことを検査 |
| 規約/生成物 | **PASS** 変更ファイルのlint/SPDX/locale safety（未commit差分の`--base HEAD`）、diff空白検査、MFMと絵文字生成物の一致、試験スクリプトの構文検査。backend API/entity/migrationの変更は今回なし |

実機で標準タブバーと独自バーが二重になる表示と、List内の投稿ボタンの操作を修正した。通常のローカルノートにも付く`gridspaceReactions`を、連携先専用操作の印と誤認して拒否していた箇所を修正した。これは認証境界ではなく能力の情報であり、ネイティブは通常のノートAPIで再取得できる対象へ、サーバーの通常の権限検査を通して操作する。

画像はURLSessionのセッション/タスク双方の証明書検査を同じ処理へ接続し、表示更新でロード効果を作り直さない安定したコンテナへ変更した。画像を読み込んだ直後に汎用アイコンへ戻る問題を画像の画素検査で防いだ。初回の本人復元を別アカウントへの切替と区別し、起動直後に開いた投稿画面を閉じないようにした。既存のアカウントを変更/退出する際は経路と画面を破棄する。

途中の自動試験では、試験用コマンドの許可リスト漏れ、Toggleの要素種別とリアクション識別子の誤り、積み上がった試験投稿のスクロール、シートが閉じる前の次操作が失敗した。修正した対象を再試験し、失敗した実行を丸ごと合格へ置き換えていない。旧Simulatorはインストール/起動待ちで停止したため専用端末を作り直し、OSの初回移行後に再試験した。実機の失敗bundleはテキストの結果/必要な画面構造だけを回収して削除し、画像/動画を診断に使っていない。

実機の126件と主要4 UIの成功を含む途中実行は`gridspace-emoji-device-confirmed.log`とテキスト結果、最後の添付再試験は`gridspace-emoji-device-attachment-confirmed.log`・`0257e11cb5eb4c7e9c307d0f68e575d1`。絵文字UI2件の実機成功は`gridspace-emoji-device-emoji-passing.log`。Simulatorのアプリ内/絵文字UIは`gridspace-emoji-simulator-qa-validated.log`・`124a83bc205e4017a786478a57f838f0`、最終画像は`gridspace-emoji-simulator-pixels.log`・`665d2a695a9f4c849cf9c87726e72d5b`。最終SDK/Release/実機導入は`gridspace-emoji-{mac-shipping,release-shipping,device-shipping-install}.log`。生成物/規約は`gridspace-emoji-{generated-check,shipping-verified,diff-check}.log`。公開カタログのCore読取は`gridspace-emoji-live-catalog-check.log`。証拠はcheckout外の非公開領域へ置く。

写真加工/投票作成/宛先/編集、検索条件とページ送り、ストリーミング/位置保持、プロフィール編集、管理/コレクション/チャット、APNs/共有入口、連携先の私有API、非公開ロールの利用判定、全メディア形式/全OS/VoiceOverの比較は現行計画で継続する。Web画面の存在を対応済みの代わりにしない。

最新アプリを実機の通常起動へ戻した。実機試験環境は専用2 DB/Redis名前空間の残存0、33 storage keyの残存0を確認した。画面確認用の環境も専用2 DB/Redis名前空間の残存0、3 storage keyの残存0。live manifest/xctestrunとUSB保持情報を削除し、61812–61816の待受けなしを確認した。作成した専用Simulatorだけを削除した。

## 公開画像の共有キャッシュ（2026-11-16）

アバター、プロフィールバナー、本文/リアクション/ピッカーのカスタム絵文字を共通の`NativeAssetCache`へ接続した。公開ロゴを表示する場合にも同じ経路を使える。取得済みデータをメモリ8 MiB・ディスク64 MiBの範囲で再利用し、同じURLの同時取得をまとめる。アプリ再起動後のディスク復元、URL queryによる画像版の分離、容量超過時の古いデータの削除を行う。通常24時間、サーバー指定のmax-ageは上限7日。期限後はETag/Last-Modifiedを送り、304では既存データと更新方針を保持する。通信失敗時のみ最大7日の古いデータを利用し、no-cache/must-revalidateやHTTP拒否後には利用しない。no-store/private/Vary:*は保存しない。

画像はcookie/トークンを使わない既存TLS/リダイレクト検査の経路で取得する。ディスク名はURLのSHA-256で、URLや認証情報を記録せず、保存場所は保護付き・バックアップ対象外のCaches。投稿の添付画像/認証APIの本文は永続キャッシュ対象に追加していない。試験のキャッシュは実利用の保存先と分け、合成画像のテスト用ディレクトリは終了時に削除する。

- **PASS**: `check-mac.sh`のCore 42件とSimulator SDKビルド（`/tmp/gridspace-artwork-mac.log`）。
- **PASS**: 実機で新規キャッシュ10件。メモリ/ディスク復元、重複取得/待機側取消、期限/ETag/Last-Modified/304、保存禁止、no-cacheの304継承、オフライン/404/7日/must-revalidate、破損/非画像、容量/URL版、不適切なURLを検査。
- **PASS / SKIPPED**: 既存分を含む実機アプリ内136件中135成功・失敗0・旧Local PWA fixture未設定による1 skip（`/tmp/gridspace-artwork-device-all-tests.log`、`/tmp/gridspace-artwork-device-all-tests.xcresult`）。UI操作の新しい再試験はしていない。
- **PASS**: 変更集合のlint/SPDX/locale safety（`--base HEAD`、`/tmp/gridspace-artwork-shipping.log`）とdiff空白検査。
- **PASS**: 署名付きアプリを実機へインストールし通常起動（`/tmp/gridspace-artwork-device-install.log`）。本番の資格情報や投稿を試験に使っていない。

## 投稿入口の整理（2026-11-16）

ユーザー指示に合わせ、共通ツールバーの投稿ボタンとタイムライン先頭の「いまどうしてる？」欄を削除し、右下のフローティング投稿ボタンを残した。使われなくなった内部composeルートも削除し、既存の添付UI試験の入口をフローティングボタンへ変更した。返信/引用と投稿画面内の送信ボタンは維持する。

**PASS**: `check-mac.sh`（Core 42件、Simulator SDKビルド）、実機の`NativeEmojiTests` 13件（投稿欄/絵文字/リアクション）、署名付き実機ビルド、lint/SPDX/locale safety（`--base HEAD`）、diff空白検査。**SKIPPED**: 隔離backendが必要な添付UI試験の再実行（今回は入口のセレクターを更新）。ログは`/tmp/gridspace-compose-entry-{mac,device-tests,shipping,install}.log`。

## 引っ張って更新時のスクロール安定化（2026-11-16）

タイムラインのフィードタブをListの上端safeAreaInsetから外側のVStackへ移し、UIRefreshControlの更新中に上端insetを組み替えない構造へ変更した。更新処理をNativeTimelineModelへ分離し、プル更新中は表示済みのノートとページ送りの行を保持する。プル更新と通常の読み込みを同じ下部スピナーで表現せず、失敗/取消後もdeferで読み込み状態を解放する。重なったプル更新は増やさず、ページ送りを更新で置き換えた場合は古いページを混入させない。アカウント/フィード/表示世代の変更時は旧応答を失効させる。401/403では古い一覧を破棄し、401は再ログインへ接続する。

- **PASS**: 実機のモデル6件。更新中の行/ページ送り保持、重複更新、通信失敗/取消/再試行、別コンテキスト、ページ送りとの競合、401を検査。`/tmp/gridspace-refresh-device-tests.log`。
- **PASS**: 同じ実機でUI2件。合成HTTP応答を専用URLSessionだけに供給し、連続のプル更新後に先頭の縦位置へ復帰すること、タブ位置の維持、次のスクロール、通信失敗後の保持と再更新を実際のジェスチャーで確認。通常のアニメーションも有効にして2件を再実行し成功。`/tmp/gridspace-refresh-animated-device-tests.log` / `/tmp/gridspace-refresh-animated-device-tests.xcresult`。画像や本番の資格情報/データは使わず、実機画面を意図的に撮影していない。
- **PASS**: 変更集合のlint/SPDX/locale safety（`--base HEAD`、`/tmp/gridspace-refresh-shipping.log`）。UI fixtureはDEBUG専用・3つの明示起動引数と予約originでのみ有効とし、通常起動/Releaseの通信へ登録しない。
- **PASS**: `check-mac.sh`のCore 42件とSimulator SDKビルド（`/tmp/gridspace-refresh-mac.log`）、diff空白検査、署名付きアプリの実機インストール/通常起動（`/tmp/gridspace-refresh-install.log`）。

## 投稿画面・写真選択のUX（2026-11-16）

フォームの項目一覧から、本文と選択メディアを中心にしたScrollViewへ変更した。人物と公開範囲の小さなメニュー、入力時のキーボード表示、本文量に応じて伸びるUITextView、キーボード上の画像/絵文字/オプション、右上の青い投稿ボタンを使う。CW・Files・ドライブはオプションへまとめた。画像選択時は本文の直下にプレビューを寄せ、説明項目や手動アップロードのボタンを通常の投稿面へ並べない。

画像ボタンからPHPickerを直接開き、最大16件の残り枠と選択順を引き継ぐ。原本を保護付きの添付保存先へ取り込み、ImageIOで最大480pxのローカルプレビューを生成する。カードには順番、削除、ALT/センシティブ等の設定、並べ替えメニューを用意した。内部ドラッグの表現はownProcessへ限定する。既存ドライブの画像をプレビューする際は所有者を再検査し、取得したURLを下書きへ保存しない。画像加工・動画のローカルサムネイル・カメラ撮影・アップロード済みの属性編集は追加実装の対象。

「投稿」では未アップロードのファイルを既存の逐次アップロード経路で送って完了を待ち、所有権/属性を読み直してからノートを作成する。途中まで完了したIDを保持し、応答喪失による結果不明の添付は自動再送しない。アカウント・表示・編集・送信世代を検査する。写真選択の取消、本文のUTF-16選択範囲と絵文字挿入、下書き・原本の保護を維持する。

- **PASS**: 実機の添付状態/絵文字19件。新規2件で自動アップロードの待機・順序・完了済みIDの再利用と、結果不明時の投稿不許可/再送抑止を確認（`/tmp/gridspace-composer-design-device-unit.log`）。
- **PASS / SKIPPED**: 実機アプリ内144件中143成功・失敗0、旧Local PWA fixture未設定の1 skip（`/tmp/gridspace-composer-design-device-all-tests.log` / 同名`.xcresult`）。この実行後の変更は、画像選択時の本文の最小高さの調整で、次のUI再試験に含めた。
- **PASS**: 専用SimulatorのUI2件。画像ボタンからピッカーを開いて取消しても本文を保持すること、実際の写真ライブラリから合成PNG 2枚を選択し、カードの画像表示・ALT編集・メニューによる順序変更・下書き復元・手動アップロードなしでの投稿完了を確認した。サーバーは専用URLSessionのDEBUG用URLProtocolで合成し、multipart/原本取り込み/所有者検査/ノート作成のクライアント処理は実装経路を使った。実バックエンドの書込比較を置き換えるものではない。ドラッグ操作自体・VoiceOver・全画像/動画形式のUI比較は未実施。
- **PASS**: 最後の余白調整後にもUI2件が成功（`/tmp/gridspace-composer-design-sim-compact.log` / 同名`.xcresult`）。固定色の合成画像の実画素を検出して選択し、既定ライブラリの写真や汎用プレースホルダーを成功扱いにしない。目視した最終プレビューはcheckout外の`ios-native/post-composer.png`。
- **PASS**: 最終`check-mac.sh`のCore 42件とSimulator SDKビルド、Release SDKビルド、署名付き実機ビルド/インストール/通常起動（`/tmp/gridspace-composer-design-{final-mac,release,final-install}.log`）。Release plistに開発用ATS例外/Files公開キーがないことも確認。
- **PASS**: 変更集合のlint/SPDX/locale safety（`--base HEAD`、`/tmp/gridspace-composer-design-shipping.log`）、diff空白検査。backend API/entity/migration、他言語localeの変更は今回なし。

途中のUI試験は、初回のログイン復元待ち、iOSのプライベートアクセス説明、別プロセスの写真グリッドのアクセシビリティ判定、説明バナーの閉じるボタンとピッカーの取消の区別、シート終了前の次操作で失敗した。試験の要素と待機を修正し、最終の成功2件へ途中失敗を合算しない。半画面の写真表示では操作領域が隠れる構成を避け、写真一覧は大きく表示する。

本番への投稿や添付追加は行わず、本番の資格情報も試験に使っていない。写真の追加/選択/スクリーンショットは作成した専用Simulatorの合成データで行い、利用者のiPhoneの写真ライブラリは操作していない。実機のUI画面を意図的に撮影していない。試験後は専用Simulatorを削除し、iPhoneは通常起動へ戻した。

一般の試験環境や利用者のライブラリで写真UI試験を走らせないよう、専用Simulator名以外では開始前にskipするガードを追加し、構文検査を通した。通常アプリの変更ではない。最後の確認で専用Simulatorの削除とRelease plistの開発用キー不在、最終アプリの実機通常起動を確認した。

## タイムラインの左右スワイプ（2026-11-16）

ホーム/ローカル/グローバルを、iOS標準のページ形式のTabViewで切り替えるようにした。上のタブとページの選択を同じBindingへ接続し、タップでも移動する。下部のタイムライン/検索/通知/プロフィールの選択は変更しない。未ログインではホームを表示せず、両端から先へは循環しない。

各ページが独立したNativeTimelineModel/Listを持ち、縦スクロールとプル更新はListの標準操作を使う。ヘッダーをスクロール領域へ差し込まず、以前の更新時のinset対策を維持する。非選択ページはアクセシビリティから隠し、ページ破棄/表示世代の変更では既存のモデル失効を使う。合成の更新試験のカウンターはフィード別に分け、隣接ページの読取と選択ページの更新を混同しない。

- **PASS**: `check-mac.sh`のCore 42件とSimulator SDKビルド（`/tmp/gridspace-feed-swipe-mac.log`）。
- **PASS**: 実機のNativeTimelineTests 6件とNativeRefreshUITests 4件、同一実行で10件成功/skipなし（`/tmp/gridspace-feed-swipe-device-tests.log` / 同名`.xcresult`）。匿名のローカル→グローバル→ローカル、ログイン中のホームを含む往復、両端での操作、タブのタップ、下部ナビゲーションの維持、スワイプ後の縦スクロール/プル更新、更新失敗後の再試行と元の位置への復帰を確認。更新用fixtureは通常アニメーションも有効。
- **PASS**: 変更集合のlint/SPDX/locale safety（`--base HEAD`、`/tmp/gridspace-feed-swipe-shipping.log`）とdiff空白検査。

合成HTTP応答だけで試験し、本番の資格情報や投稿/添付の書込を使っていない。実機画面を意図的に撮影していない。今回は新しいSimulatorやバックエンドfixtureを作成していない。

署名付きの最新アプリをiPhoneへインストールし、通常起動へ戻した（`/tmp/gridspace-feed-swipe-install.log`）。

## ノートの余白とリアクションの半画面シート（2026-11-16）

ノートの縦padding 10ptとList既定の余白が重なる構成を外し、共通のrow insetを上8pt/左右12pt/下0ptへ統一した。本文側の間隔は4pt、本文内の要素間は6ptへ整理し、操作ボタンは44ptの高さを確保する。実機の合成ノートのアクセシビリティ情報で、アバターの左位置12pt、単行ノートの行間隔94ptを確認した。共有のNativeNoteRowを使うタイムライン/人物/会話へ適用する。

リアクション選択にはUIKit/SwiftUI標準のmedium/large detentを指定し、グラバーを表示する。毎回mediumから開き、上へのドラッグでlargeへ広げられる。検索は識別子を持つTextFieldへ整理し、FocusStateでフォーカスを検出してlargeへ移る。検索欄は当初フォーカスせずキーボードを出さない。選択で閉じ、再度開くとmediumへ戻る。投稿欄からの絵文字挿入は従来の大きなシートを保ち、検索部品を共有する。リアクションの権限/ロール/結果不明/応答失効の処理は変更しない。

- **PASS**: 実機のNativeEmojiTests 13件。選択範囲、再利用、変更/解除、重複操作と結果不明、アカウント/表示権限の失効の既存試験を確認（`/tmp/gridspace-reaction-sheet-device-tests.log`）。
- **PASS**: 余白変更後のNativeRefreshUITests 4件。縦スクロールの検査を特定の行番号に依存させず、先頭のノートが実際にスクロールすることへ変更した。スワイプ切り替え・境界・ヘッダー操作・連続更新・失敗後の再更新を含む（同ログ）。
- **PASS**: 実機のNativeReactionSheetUITests 2件を通常アニメーション有効で再試験。mediumの位置とキーボード非表示、ドラッグによるlarge、検索フォーカスによるlarge、標準絵文字の検索/選択、選択後のリアクション表示、再度開いた際のmediumを確認（`/tmp/gridspace-reaction-sheet-animated-device-tests.log` / 同名`.xcresult`）。
- **PASS**: 変更集合のlint/SPDX/locale safety（`--base HEAD`、`/tmp/gridspace-reaction-sheet-shipping.log`）、diff空白検査。新しいbackend API/entity/migrationや他言語localeの変更はなし。

初回の実行では上へのドラッグと検索/選択は通ったが、追加した下向きの速いドラッグがシートを閉じ、mediumに留まるという過剰な試験条件で1件失敗した。下方向の標準の閉じる操作を禁止する変更は加えず、要求された上方向の拡張へ試験の範囲を合わせた。初回の13+4成功と、最終シート2件の成功は複数の実行にまたがる。失敗bundleは安全なテキストのサマリー/合成画面の構造だけを保存し、画像/動画を含むbundle本体は削除した。

合成のHTTP応答と標準Unicode絵文字だけで検査し、本番への投稿・リアクション・添付追加や資格情報の利用を行っていない。実機画面を意図的に撮影していない。専用Simulatorや新しいbackend fixtureは起動していない。

**PASS**: 最終`check-mac.sh`のCore 42件/Simulator SDKビルド、署名付きアプリの実機インストール/通常起動（`/tmp/gridspace-reaction-sheet-{final-mac,install}.log`）。


## 動く絵文字と複数リアクション（2026-11-16）

本文、リアクションのチップ、絵文字ピッカーでGIF/APNG/WebPのアニメーションを再生する。公開画像の共通キャッシュを使い、各フレームを最大192pxへ縮小して必要なフレームだけ描画する。4 MiBのデータ上限、300フレーム/2048pxを超える画像の静止表示、本文ごとの再生Viewの上限64個を設けた。画面外ではフレーム更新を省き、背景移行、Viewの取り外し、「視差効果を減らす」で再生を止める。本文はTextKitの添付の字形位置/ベースラインへ、ピッカー/チップと共通のUIImageViewを置き、文字の選択と代替名のコピーを保持する。拡張APIの`name@.`のURLマップもそのまま再利用し、別形式のプロキシURLへ取り直さない。

このフォークの`notes/extended-reactions/show`で100件ずつ件数・自分の全選択を取得し、対応するノートでは専用のcreate/deleteへ1回送る。最大16種類の追加、1種類だけの解除、複数選択のチェック表示と解除メニュー、主リアクションの削除後に残る追加分を扱う。通常のリモートノートは従来の単一置換/解除を維持する。状態が不完全な場合は拡張書込みを止め、単一APIへ切り替えない。追加/解除の明示的な意図、応答喪失後の再送抑止、世代/本人/権限の照合を保つ。解除では追加時の絵文字利用条件を再適用しない。

- **PASS**: 最終`check-mac.sh`。Core 44件、Simulator SDKのarm64/x86_64ビルド（`/tmp/gridspace-animation-multi-final-mac.log`）。拡張状態の不変コピー、主がnilで追加分だけある状態、共有/チャンネルの判定、修飾付きの画像URLを検査。
- **PASS**: 実機のGridSpaceTestsは156件中155件合格・既存の1件skip、失敗なし。GIF/APNG/WebPのフレーム/時間、本文内での自動再生・View取り外し、複合Unicode後の添付位置・折り返し・本文除去、16種類の制限、既に追加/解除済みの競合、利用停止された絵文字の解除、結果不明、正しい拡張エンドポイント/絵文字/100件のバッチと欠落応答を含む（`/tmp/gridspace-animation-multi-verified2-device-tests.log` / 同名`.xcresult`）。
- **PASS**: 同じ実機のNativeReactionSheetUITests 3件。通常のアニメーションを有効にし、medium/large、検索、2種類の共存、解除メニューから主だけを削除して追加分が残ること、残った1種類の解除を検査。オフラインの合成GIFを使う。
- **PASS**: NativeRefreshUITests 4件。失敗後の再試行、連続した引っ張り更新、縦スクロールとフィードのスワイプ/見出し切替（`/tmp/gridspace-animation-multi-final-device-tests.log`、この実行全体は下記の行内表示試験が失敗したためFAILであり、合格扱いにしない）。
- **PASS**: changed-file lint / SPDX / locale safety（`--base HEAD`、`/tmp/gridspace-animation-multi-shipping.log`）、diffの空白検査。
- **SKIPPED**: 既存のLocalPWABootTestsの実backend fixture試験1件。今回その隔離backendは起動していない。本番へのリアクション作成/削除の試験は実施していない。

途中の行内表示試験ではTextKitのView providerが配置されず失敗した。字形に追従する再生Viewへ変更し、同じ受入条件（実際に配置されて自動で画像が変わること）を実機で再試験して通した。追加した折り返し試験のSwift構文エラーも修正して再実行した。失敗した実機bundleはテキストの結果だけ回収して削除し、画像/動画を診断に使っていない。

自作の2色/2フレーム画像と合成API応答を使い、渡された本番資格情報を利用していない。本番への投稿・リアクション・添付の追加や、端末の写真の参照/追加は行っていない。実機画面を意図的に撮影していない。新しいSimulator、backend fixture、DB/Redisは起動していない。

**PASS**: 最終の署名付き実機ビルド、インストール、起動引数なしの通常起動（`/tmp/gridspace-animation-multi-install-build.log`、`/tmp/gridspace-animation-multi-install.log`、`/tmp/gridspace-animation-multi-launch.log`）。


## タブのカスタマイズとチャンネル追加（2026-11-16）

上部タブ右端の編集ボタンから、ホーム/ローカル/グローバルの追加・削除、タブのドラッグ並べ替え、チャンネルの検索・追加を行う。タブは最大20個、種類/チャンネルIDで重複を防ぎ、空になった場合はローカルを残す。接続先/アカウント/匿名で設定を分離し、チャンネルのIDと表示名、タブの順序だけを端末のUserDefaultsへ保存する。ノートの本文・人物・検索結果・資格情報は設定へ保存しない。

チャンネルの一覧/名前と説明の検索はchannels/searchの30件/untilIdで取得し、古い検索応答や終了した画面への応答を拒否する。センシティブなチャンネルの説明は自動表示しない。追加済みとアーカイブ済みの追加を止める。ノートはchannels/timelineへchannelIdとuntilIdを渡し、表示可能な別チャンネルのノートが返れば拒否する。タブごとのページ/更新状態、横スワイプ、固定ヘッダー、引っ張って更新、既存のノート操作を共有する。保存した表示名は追加時のものを使う。サーバーへのフォロー/チャンネル作成やチャンネルを指定した投稿は今回の操作に含めない。

- **PASS**: Core 47件。Codableの復元/順序/重複、ID/件数/名前の補正、空の復帰、匿名の既定値、センシティブ/アーカイブ情報の読取（`/tmp/gridspace-channel-tabs-core.log`）。
- **PASS**: 実機のGridSpaceTests 164件中163件合格・既存fixture 1件skip、失敗なし。アカウント/匿名/別originの分離、再生成したモデルでの順序の復元、破損レコード、追加上限、重複、空のタブ、検索の競合/終了/失敗/再試行、ページ境界の重複とカーソル、チャンネルのノート取得/再取得とAPI引数を含む（`/tmp/gridspace-channel-tabs-final-device-tests.log`、この実行全体は下記のUI自動操作失敗があるためFAILとし、合格に数えない）。テキスト結果を保存して失敗bundleは削除した。
- **PASS**: 実機のNativeFeedTabsUITests 1件。匿名の合成APIだけでチャンネルの検索/追加、チャンネルのノート表示、スワイプ、引っ張って更新、再起動後の復元、実際の並べ替えハンドルで先頭へ移動、再起動後の順序、編集モードの−ボタンからの削除、削除後に再起動しても追加済みにならないことを検査（`/tmp/gridspace-channel-tabs-handle-device-tests.log` / 同名`.xcresult`）。
- **PASS**: 既存のNativeRefreshUITests 4件。連続更新の余白解放、失敗後の再試行、縦スクロールとフィードの左右スワイプ、ログイン済みの3タブ/端の停止/見出しタップ（`/tmp/gridspace-channel-tabs-device2-tests.log`。この実行全体は初回の新規UI試験が失敗したためFAIL）。
- **PASS**: changed-file lint / SPDX / locale safety（`--base HEAD`、`/tmp/gridspace-channel-tabs-shipping.log`）、diffの空白検査。
- **SKIPPED**: LocalPWABootTestsの実backend fixture 1件。今回は隔離backendを起動していない。本番へのチャンネル作成/フォロー/投稿を試験していない。

途中の試験では、常時編集モード中のNavigationLinkが無効となってチャンネル選択へ移れなかった。通常のButtonから独立した選択シートを開く形へ変更し、検索欄を常に表示して同じ流れを再試験した。テストコードの変数名の衝突、編集モードでスワイプ削除を試す誤り、並べ替えハンドルの端を狙った座標の不安定さも修正した。後者は実際のハンドルのアクセシビリティ要素を使い、並べ替えと再起動後の順序まで通過した。失敗した実行を丸ごと成功扱いにしていない。

自作の合成ノート/チャンネルと専用の設定領域だけを使い、本番の資格情報・投稿・写真は使っていない。実機画面を意図的に撮影せず、必要な画面構造を文字列として調べた。失敗した実機bundleはテキストの結果だけ保存し、画像/動画を診断に使わず削除した。新規Simulator、backend fixture、DB/Redisは起動していない。

**PASS**: 最終`check-mac.sh`でCore 47件、Simulator SDKのarm64/x86_64ビルド（`/tmp/gridspace-channel-tabs-final-mac.log`）。

**PASS**: 最終の署名付き実機ビルド、インストール、テスト引数なしの通常起動（`/tmp/gridspace-channel-tabs-install-build.log`、`/tmp/gridspace-channel-tabs-install.log`、`/tmp/gridspace-channel-tabs-launch.log`）。


## れぞらぶ側のチャンネル取得（2026-11-16）

前回はローカルのchannels/searchとchannels/timelineしか呼んでおらず、Web版が併用するgridspace/channelsが抜けていた。専用の一覧取得、表示元の切替、originで区別したタブ保存を追加した。ローカルと連携先のカーソル・障害を分離し、同じIDも混同しない。MiAuthの要求へread:gridspace-privateを追加し、旧トークンの権限不足には「ログインを更新」を表示する。Webトークンやsecureなlink/private-grant APIを使わず、ぐりすぺのプロキシAPIだけへ認証情報を送る。

連携先の本文は独立したDecodable型/一時メモリ/画面で読み、通常のClientNoteや操作APIへpeer IDを渡さない。gridspace/private-notesのchannelモードとopaque cursorを使う。validate/contextMode/channelIdで、ページ送り前と15秒ごとに読み込み済みIDを100件ずつ再確認する。origin・チャンネル・返されたID集合を検査し、非表示/終了/世代変更、失効/通信失敗で本文を破棄する。本文/CW、引用、添付名まで対応。私有添付の取得/表示、MFM装飾、投稿・リアクション・投票は未実装であり通常APIで代用しない。

- **PASS**: 最終check-mac.sh。Core 48件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-peer-channels-final-mac.log`）。旧ローカル記録の保持、origin付きID、正規化/復元、壊れたorigin/ID、新しい認証権限を検査。
- **PASS**: 実機GridSpaceTestsは172件中171件合格、既存fixture 1件skip。全体の実行は途中のUI失敗を含むためFAILとして記録（`/tmp/gridspace-peer-channels-final-device-tests.log`）。変更後のNativePeerChannelTests 6件も再試験して通過した（`/tmp/gridspace-peer-channels-lifecycle-tests.log`、この実行全体は再起動後のUI操作がFAIL）。opaque cursor、再認可、失効/削除、旧所有者の応答拒否、同じ世代のactivate、片側障害、独立した一覧ページ、origin変更、古い検索応答を検査。
- **PASS**: 実機NativePeerChannelUITests 3件が同じ実行で通過（`/tmp/gridspace-peer-channels-verified-device-tests.log` / 同名`.xcresult`）。同じIDのローカル/連携先、表示元、2ページ目、下部ナビとの非重複、再起動後に横スクロールして保存タブを選択、旧権限の案内とローカル一覧の維持、表示中の失効による本文削除を確認。
- **PASS**: ローカルNativeFeedTabsUITests 1件も再試験（`/tmp/gridspace-peer-channels-device2-tests.log`）。この実行全体は初期の連携先ページ送りでFAIL。
- **PASS**: lint / SPDX / locale safety（--base HEAD、`/tmp/gridspace-peer-channels-shipping.log`）とdiff空白検査。
- **SKIPPED**: LocalPWABootTestsの実backend fixture 1件。本番の認証更新、連携先の実際の本文、書込み操作は未試験。本番は認証なしの公開api/endpointsだけを読み、2つの連携APIが存在することを確認した。

途中で画面外のボタンを押そうとするテストの誤り、ページ送りが下部ナビに隠れる不具合、表示切替時の世代初期化の競合、横スクロールせず4個目のタブを押すテストの誤りを検出した。下端の余白、冪等なactivate、キャンセル済みタスクの拒否を実装し、実際のスクロール・選択状態・本文で再試験して通過した。失敗を丸ごと合格へ置換していない。

合成ノート/チャンネルと専用設定だけを使用し、本番の資格情報、投稿、写真を試験に使っていない。実機を意図的に撮影せず、必要な合成画面の構造を文字列で確認した。失敗bundleはテキスト結果だけ回収して削除し、画像/動画/端末診断は読んでいない。backend/frontendは参照のみで変更なし。新しいSimulator、backend fixture、DB/Redisを起動していない。

**PASS**: 最終の署名付き実機ビルド、インストール、テスト引数なしの通常起動（`/tmp/gridspace-peer-channels-install-build.log`、`/tmp/gridspace-peer-channels-install.log`、`/tmp/gridspace-peer-channels-launch.log`）。既存の本番ログインは維持し、新しい読取権限への再認証は利用者が「ログインを更新」から行う。


## リアクションの即時表示と人物アイコン（2026-11-16）

WebのMkReactionsViewer.reaction.vue、extended-reactions.ts、ReactionService / ExtendedReactionService / GridspaceReactionServiceとreaction-protocolを参照した。ぐりすぺのローカルノートと、バックエンドが連携対象として広告するれぞらぶのノートだけが複数対象で、1人・1ノート最大16種類。通常リモートは1種類。拡張の最初の1種類が通常連合へ流れ、追加分は拡張として保持される。任意ホストの文字列だけで拡張可能とは判定せず、既存のサーバー判定フィールドを使う。れぞらぶの専用読取チャンネル画面への書込は今回も対象外。

選択を仮反映するimmutableなClientNoteコピーと、明示的な追加/削除意図の直列キューを導入した。最初のネットワーク読取より前に絵文字・件数・選択色・本人アバターを更新し、送信中のProgressViewを除去。続く操作も仮反映して順番に実行する。バックグラウンドで最新ノート/本人/絵文字の利用条件を照合し、送信後に実状態を読む。制限や確定拒否は最新の確定状態へ戻し、後続キューを破棄する。応答喪失や成功後の照合失敗は未確定として止め、自動で再送しない。送信キューはセッションに属し、行の再利用やタブ移動で破棄しない。完了したノートの状態は最大256件を一時保持し、表示中の行は同じキューを共有する。アカウント変更/非アクティブ時は全モデルの内容と世代を無効化し、待機中の継続も解放する。通常リモートの変更は旧リアクションの削除と新規作成を順に実行する。

ローカル限定、引用元、センシティブ、利用ロール、いいね限定と連携先のリモート向けいいね限定を考慮する。連携先人物がこのサーバーに投稿したローカルチャンネルの場合はバックエンドと同様にローカルポリシーを使う。古い絵文字の解除では追加権限を要求しない。任意のリモートカスタム絵文字をローカルshortcodeへ変換して送らない。

絵文字の横に14ptアバターを最大10人並べる。Webと同じnotes/extended-reactions/listまたはnotes/reactionsをtype/limit 10で呼び、人物IDを重複排除し、異なる絵文字の応答を拒否する。本人の追加/解除は古い人物ページの応答を待たず反映する。表示は固定幅グリッドから可変幅の折返しへ変更し、件数はアクセシビリティラベルに残す。アバター画像は既存の共通キャッシュを使うが、人物ページは永続保存せず、画面終了/セッション変更で古い応答を拒否する。

- **PASS**: Core 50件とSimulator SDK arm64/x86_64ビルド（/tmp/gridspace-optimistic-mac.log）。仮反映の不変性、同じ絵文字の表記ゆれ、件数、通常リモートの単一性と受入ポリシーを検査。
- **PASS**: 実機の関連unit 46件（/tmp/gridspace-optimistic-unit.log）。最初の読取を保留中の即時追加/削除、連続キュー、確定拒否の復元、並行更新、16種類制限、廃止絵文字の解除、応答喪失、認証失効、人物一覧のAPI/limit/type、重複排除、セッション破棄後の遅延応答を検査。
- **PASS**: 実機NativeReactionSheetUITests 4件と最新NativeReactionUsersTests 2件（/tmp/gridspace-optimistic-ui.log / 同名.xcresult）。4秒遅延の送信で本人アイコン/件数/選択状態が2秒以内に反映され、待ちインジケーターがなく、解除を続けて押せること、両方の応答後も解除状態となることを検査。ローカル/連携先の人物表示、シートの半分/拡大/検索、2種類の共存と個別解除も通過した。
- **PASS**: shipping checks --base HEAD（/tmp/gridspace-optimistic-shipping.log）。既存未commit変更集合の対象lint、SPDX、locale safetyが合格。今回のbackend/frontendは参照だけで変更なし。
- **SKIPPED**: 本番アカウントでのリアクション送信。合成アカウント・合成ノートと専用設定だけを使い、本番の資格情報・投稿・写真は使っていない。新しいSimulator、backend fixture、DB/Redisは起動していない。実機を意図的に撮影せず、XCTestの文字情報で確認した。


**PASS（追加のライフサイクル検査）**: セッション共有化後のNativeEmojiTests 13件とNativeMultipleReactionTests 9件、および遅延UI 1件が通過（/tmp/gridspace-optimistic-lifecycle.log）。その後、キャッシュを超える件数でも表示中の行のキューが分裂しない保持方法と、実際の検索タブ往復を加え、unit 11件とUI 1件が通過した（/tmp/gridspace-optimistic-detach.log）。最終のNativeMultipleReactionTests 10件と同じタブ往復UI 1件も通過（/tmp/gridspace-optimistic-verified.log / 同名.xcresult）。非表示のノートへの更新は仮表示と待機キューを即座に破棄し、遅い応答が本文やリアクションを復元しないことを含む。いずれの実行もTEST SUCCEEDEDで、失敗bundleは今回なし。

**PASS（最終ビルド・配布）**: セッション共有化と非表示時の破棄を含む最終check-mac.shでCore 50件とSimulator SDK arm64/x86_64が合格（/tmp/gridspace-optimistic-shared-final-mac.log）。署名付き実機ビルド・インストール・テスト引数なしの通常起動も成功した（/tmp/gridspace-optimistic-install-build.log、/tmp/gridspace-optimistic-install.log、/tmp/gridspace-optimistic-launch.log）。既存の本番ログインを保持した。最終diff空白検査も合格。


## 絵文字一覧のキャッシュと既定の最近タブ（2026-11-16）

画像キャッシュとは別に、公開api/emojisの一覧をorigin別のメモリ/ディスクへ保存するようにした。起動時に認証情報を持たない専用NativeAPIで準備し、ピッカーが開いたら保存済みの一覧を先に表示する。APIのcacheSec: 3600に合わせて1時間再利用し、期限後は古い一覧を表示しながら更新する。通信失敗時の保持は最大7日。1ファイル8 MiB、メモリ4件、ディスク8件を上限とし、バックアップから除外する。公開の絵文字情報のみ保存し、本人・所属ロール・ノート・認証情報を保存しない。XCTestは通常キャッシュとは別のディレクトリを使い、UI試験の同じ実行内で再起動した場合だけ共有する。

「絵文字を取得中」のProgressViewを除去した。毎回「最近」から開き、標準/カスタムを混ぜて使用順に32件まで並べる。存在しない絵文字や重複を表示せず、センシティブの表示設定を維持する。「最近」で検索した場合は全カタログが対象になる。最近の選択は既存のorigin/アカウント別キーを維持し、試験の保存先だけ実行ごとに分離した。

リアクション用のピッカーには表示中ノートと確認済みの所属ロールを初期表示に渡し、利用条件の読取は裏で進める。実際の送信時にはNativeReactionModelが従来どおり最新ノート・本人・絵文字の権限を照合する。メタデータの読取に失敗した場合は選択を止めてエラーを示す。投稿本文への挿入では公開カタログだけを使う。

- **PASS**: check-mac.shでCore 50件とSimulator SDK arm64/x86_64ビルド（/tmp/gridspace-emoji-recents-mac.log）。
- **PASS**: 実機の関連unit 28件（/tmp/gridspace-emoji-recents-device.log）。カタログのメモリ/再起動後の再利用、originの分離、保存済み一覧が遅延更新より先に見えること、通信失敗時の保持と7日期限、並行取得の共通化、無効/重複名の除去、標準/カスタムを混ぜた使用順と全体検索、従来のリアクション権限/キューを検査。
- **PASS**: 同じ実行で実機NativeReactionSheetUITests 5件が通過。新しい試験は既定の「最近」、最近から全体検索、3種類を使った順序、プロセス再起動後の復元、一覧APIだけが通信不可でもカスタム絵文字を選択できること、「絵文字を取得中」と待ちインジケーターが出ないことを確認した。従来の遅延送信/タブ往復、シートの高さ/ドラッグ/検索、複数リアクションも通過（/tmp/gridspace-emoji-recents-device.log / 同名.xcresult）。
- **PASS**: shipping checks --base HEAD（/tmp/gridspace-emoji-recents-shipping.log）。既存未commit変更集合の対象lint、SPDX、locale safetyが合格。今回backend/frontendの編集なし。
- **SKIPPED**: 本番への書込と実backendのペアfixtureを必要とするNativeEmojiUITests。既定タブ変更に合わせて同試験のカスタムタブ選択は更新したが、今回実行していない。合成アカウント/ノート/画像と実行専用の保存領域だけを使用し、本番の資格情報・投稿・写真は使っていない。新しいSimulator、backend fixture、DB/Redisは起動せず、実機を意図的に撮影していない。

**PASS（最終UI）**: 公開カタログ専用の匿名APIへ分離した後も、最近の使用順・再起動・一覧API通信不可の実機UIを再試験して通過した（/tmp/gridspace-emoji-recents-final-device.log / 同名.xcresult）。認証APIの世代切替やキャンセルで公開カタログの更新を中断しない。今回の実行はすべてTEST SUCCEEDEDで、失敗bundleはない。

**PASS（最終ビルド・配布）**: 最終check-mac.shでCore 50件とSimulator SDK arm64/x86_64が合格（/tmp/gridspace-emoji-recents-final-mac.log）。署名付き実機ビルド・インストール・テスト引数なしの通常起動も成功した（/tmp/gridspace-emoji-recents-install-build.log、/tmp/gridspace-emoji-recents-install.log、/tmp/gridspace-emoji-recents-launch.log）。本番のログインと最近の選択を保持した。最終diff空白検査も合格。


## スクロール時の表示保持・画像の固定高・新着配信（2026-11-16）

表示用の縮小画像をNativeVisualMemoryへ保持し、戻った行は最初のフレームから同期的に再利用する。同じ画像の並行取得も共有する。公開アートワークの既存ディスクキャッシュに加え、表示用の画像を32 MiBのメモリへ保持する。投稿添付は別のセッション用メモリ32 MiBのみで、背景移行/アカウント変更で全世代を破棄し、古い非同期応答も保存/表示しない。ImageIOの縮小は別タスクで実行する。画面外の行が強い参照を持ち続けて上限を迂回しないよう、行の表示データ自体は解放し、再表示では上限付きキャッシュを使う。公開絵文字の表示データ8 MiBと本文の解析結果（概算コスト4 MiB）も同様に再利用する。原文/私有添付をディスクへ保存しない。

添付画像は取得前・取得後・センシティブ表示前を240ptで統一する。インライン絵文字は画像を待たずに最終サイズの正方形の文字枠を確保し、取得後も寸法を変えない。幅広の画像は余白付きの先頭フレームとaspectFitの再生Viewを使う。解析待ちにProgressViewを出さず、blurを含む本文を原文として先に露出させない。原文コピーは文字枠から絵文字名を復元する。

homeTimeline/localTimeline/globalTimeline/channelを、ぐりすぺのwss:/streamingで購読する。NativeAPIが保持するMiAuthトークンはAuthorization: Bearerにだけ入れ、URLのqueryへ入れず、れぞらぶへ直接送らない。既存のリダイレクト拒否とTLS検証を使う。購読ごとのIDでフレームを選別し、最大2 MiB/フレーム、保留256イベントで制限する。ping/pongと10秒の応答監視、1〜30秒の再接続を使い、ページ非表示/背景移行/アカウント変更で明示的に閉じる。接続完了後にRESTの先頭も取得して重複を除き、切断中に大きな間隔がある場合は先頭のページとカーソルから再開する。

先頭の判定はUIKitの実スクロール位置、adjustedContentInset、指の追跡/慣性と更新状態を使う。先頭で止まっている時だけ追加し、読書中は最大100件を保留して「新着」ボタンを表示する。手動で先頭へ戻るかボタンを押すと反映する。連続受信は100msごとにまとめて拡張リアクション状態を取得し、通常ノートへ型を落とさない。先頭で保持する一覧は最大500件にし、切り捨て後もページ送りを可能にする。

フォークのGridspaceNoteService/NoteCreateService、home/local/global/channelの配信処理、WebのMkStreamingNotesTimelineを参照した。れぞらぶの共有投稿はサーバーがローカルIDへ取り込み、gridspaceSharedを付けて同じnotesStreamへ流す。履歴の取込みは新着として配信されない。クライアントでuser.host == nilだけに絞り直さず、gridspaceSharedも受け付ける。ホームの連携本人・フォロー・可視性はサーバーが判定する。れぞらぶの専用チャンネルは普通のClientNote/WSへ流さず、15秒の認可再確認後、先頭にいる時に専用APIの最新ページを取得する。過去を読んでいる間に新着を挿入せず、opaque cursorも保つ。失効/通信失敗は従来どおり全文とカーソルを破棄する。

- **PASS**: 実機の関連unit 43件とUI 6件が同じ実行で成功（/tmp/gridspace-live-media-final-device.log / 同名.xcresult）。画像/MFM/絵文字の再利用、並行取得と世代破棄、先頭/読書中の新着、上限と再接続時の先頭切替、LTLの連携投稿判定、配信フレームのID/サイズ、専用チャンネルの新着と古いopaque cursor、権限失効、既存のアニメーション/画像キャッシュ/引っ張って更新/タブスワイプを検査した。
- **PASS**: 最終の表示参照解放とセッション別先頭判定を加えた後、unit 14件と実機UI 3件が成功（/tmp/gridspace-live-media-verified-device.log / 同名.xcresult）。画像は読込前後とスクロール往復後に240pt、本文の縦位置が変わらないこと、ローカル/連携先からの新着が先頭で流れ、過去閲覧中の位置が3pt以内で維持されること、新着ボタンで復帰すること、私有チャンネルの失効後の本文破棄を確認。
- **PASS**: 公開の実サーバーへ、認証なしでURLSessionWebSocketTaskの購読とping/pongを実行（/tmp/gridspace-public-stream-probe.log）。本文/ID/資格情報をログへ出さず、購読完了と接続維持の結果だけを記録した。本番へ投稿しない。
- **PASS**: shipping checks --base HEAD（/tmp/gridspace-live-media-shipping.log）。既存未commit変更集合の対象lint、SPDX、locale safetyが合格。backend/frontendは参照だけで変更なし。
- **FAIL→修正・再試験**: 最初のコンパイルでsendPingのコールバックが必要と判明し、継続と応答期限を使う形へ修正した。最初のunitではテキスト末尾のnil属性で検査用のboundsを上書きするテストの誤りを修正した（/tmp/gridspace-live-media-unit.log）。初期のUIではListの先頭判定用行に標準の最小高が残り、新着ボタン後の先頭判定に失敗した。最小高を明示し、先頭へ戻す意図とタブの位置に基づくUI検査へ直して、同じ2件が成功した（/tmp/gridspace-live-media-anchors.log）。失敗した実行を丸ごと合格へ置換していない。
- **SKIPPED**: 本番アカウントを使った私有WS本文や投稿/リアクション操作。通常WSの投稿編集/削除/リアクション更新の購読、私有ホームの統合、再起動後の読書位置保存は今回の対象外で残件。

実機UIは合成アカウント/ノート/所有画像と専用の保存領域だけを使用し、写真ライブラリや本番の資格情報を使っていない。意図的な実機撮影は行わず、失敗bundleはテキストの結果だけ書き出した後、画像/動画を開かずに削除した。新しいSimulator、backend fixture、DB/Redisは起動していない。

**PASS（最終ビルド・配布）**: 最終check-mac.shでCore 50件とSimulator SDK arm64/x86_64が合格（/tmp/gridspace-live-media-final-mac.log）。署名付き実機ビルド・インストール・テスト引数なしの通常起動も成功した（/tmp/gridspace-live-media-install-build.log、/tmp/gridspace-live-media-install.log、/tmp/gridspace-live-media-launch.log）。既存の本番ログイン/下書き/タブ/最近の絵文字を維持し、追加の認証権限は要求していない。最終diff空白検査も合格。


## 表示名の絵文字とリアクション更新配信（2026-11-16）

WebのMkUserNameのplain/nowrapを参照し、共通のNativeUserNameを実装した。標準絵文字とカスタム絵文字だけを描画し、文章のMFM装飾/リンクは解釈しない。TextKitの1行省略と既存のGIF/APNG/WebP再生を使い、取得前後で文字枠の寸法を変えない。表示名の初期データと画像は既存メモリ/公開画像キャッシュを使う。名前・URL・字体が同じ時はプレイヤーを再生成せず、プロフィールへのタップを子のテキストで遮らない。タイムライン、引用、プロフィール、人物一覧、通知/通知詳細、投稿画面、れぞらぶの専用チャンネルに適用した。専用チャンネルのauthor.emojisも独立した型で読み、普通のユーザーIDへ変換しない。リモートのemojisを優先し、同名のローカル絵文字を代用しない。ローカルは更新後の公開カタログURLを優先する。

セッション共通のNativeLiveReactionsが、表示中の通常ノートをsubNote/unsubNoteで購読する。タイムラインの新着接続と別の1接続を共有し、1行ごとのソケットを作らない。128 IDまで購読し、150msでまとめ、100件ずつnotes/extended-reactions/showを再取得する。reacted/unreacted/extendedReactionUpdatedの差分を直接足し引きしないので、ぐりすぺ/れぞらぶの拡張と普通の単一リアクションを同じ認可済みスナップショットで扱える。普通のリモートノートへ複数対応フラグを付けない。状態が不完全な連携先を単一リアクションへ落とさず、書込中/結果不明/古いローカル操作バージョンの応答で仮表示を上書きしない。件数が同じでも人物ページを取り直す。削除イベントや読取対象から消えたノートは隠し、古いフィードオブジェクトの再表示で復元しない。

可視行の購読には参照数を持たせ、複数画面で同じノートを表示しても共有する。背景移行・アカウント変更・終了で接続と旧読取を破棄する。WSSの認証ヘッダー/TLS/リダイレクト拒否は通常TLと同じものを使う。noteUpdatedのraw本文をユーザーへ適用せず、現在の権限で取得した結果だけを描画する。emojiAdded/emojiUpdated/emojiDeletedの公開通知も購読し、保存済み一覧を表示したままTTLを待たずカタログを更新する。

- **PASS**: 最終check-mac.shでCore 50件とSimulator SDK arm64/x86_64ビルド（/tmp/gridspace-names-reactions-final-mac.log）。
- **PASS**: 実機の関連unit 29件（/tmp/gridspace-names-reactions-unit.log / 同名.xcresult）。表示名のGIF/標準絵文字、装飾の非解釈、リモートURL、私有authorのメタデータ、更新URLと同じ文字枠、実際のTextKit再生View、更新フレームの型/ID、重複通知の共通化、同数での人物更新、削除、旧セッション応答、既存の複数リアクション/新着配信/カタログキャッシュを検査。
- **PASS**: 実機カタログ/MFM unit 12件、4秒遅延送信中の仮表示/タブ往復UI 1件、他人の追加/同数での人物入替/別絵文字の追加/解除を受信して描画するUI 1件（/tmp/gridspace-names-reactions-device.log）。この実行全体は下記の名前要素の探索でFAIL。
- **PASS**: 最新のunit 1件とUI 2件（/tmp/gridspace-names-reactions-verified.log / 同名.xcresult）。送信中の現在バージョンでも古いスナップショットが仮表示を消さないこと、完了後には新状態を適用できることを追加検査した。絵文字入り表示名のプロフィール/投稿画面への遷移と、追加/人物入替/解除のリアルタイム描画が同じ実行で成功。
- **PASS**: shipping checks --base HEAD（/tmp/gridspace-names-reactions-shipping.log）。既存未commit変更集合の対象lint、SPDX、locale safetyが合格。backend/frontendは参照だけで変更なし。
- **FAIL→修正・再試験**: 最初の表示名UIは、Buttonへ結合された子のアクセシビリティ要素を独立して探して失敗した。プロフィールボタンのラベルと、結合されないプロフィール/投稿画面の名前を検査する形へ直した。ネイティブ名ViewにもIDを設定し、ボタンの読み上げ名を明示して通過した。実行全体を合格へ置き換えていない。
- **SKIPPED**: 本番アカウントの投稿/リアクション送信、および私有チャンネルのリアクション操作。専用チャンネルは従来どおり認可付きの読取と失効検査を使い、普通のsubNoteへpeer IDを渡さない。

合成アカウント/ノート/所有画像と実行専用の保存領域だけを使用した。本番の資格情報・写真は使わず、意図的な実機撮影を行っていない。失敗bundleはテキスト結果を書き出した後、画像/動画を開かず削除した。新しいSimulator、backend fixture、DB/Redisは起動していない。

**PASS（公開WS・配布）**: 認証なしの実サーバーで、購読チャンネルなしのping先行接続とsubNote/unsubNoteの送信も確認した（/tmp/gridspace-note-updates-probe.log）。存在しない合成IDだけを使い、本文/資格情報を記録せず、投稿/リアクションを書き込んでいない。最終の署名付き実機ビルド、インストール、テスト引数なしの通常起動も成功（/tmp/gridspace-names-reactions-install-build.log、/tmp/gridspace-names-reactions-install.log、/tmp/gridspace-names-reactions-launch.log）。既存のログイン/設定を保持し、追加権限を要求していない。最終diff空白検査も合格。

## 2026-11-16 ネイティブTL・チャンネルの自動ページ取得

通常TL、ローカルチャンネル、連携先チャンネルの「もっと見る」を自動取得へ変更。Listのセル生成ではなく、実際のスクロール領域に対するフッターの位置を測り、末尾250pt手前で選択中のタブだけ読み込む。固定高のフッターを維持し、同時取得、終端、通常TLの進まないカーソルを抑止する。通常TLの失敗は既存行を保持して同じカーソルを明示的に再試行し、連携先はopaque cursor、ページ前の全保持ID再認可、失敗時の私有本文破棄を維持する。

- **PASS**: `check-mac.sh`（`/tmp/gridspace-autopaging-mac.log`）。Core 50件とSimulator SDK arm64/x86_64ビルド。
- **PASS**: 実機アプリ内17件（NativeTimelineTests 10件、NativePeerChannelTests 7件）。並行ページ取得の抑止、最終ページ、重複した全ページ、失敗時の行保持と同一カーソル再試行、更新との競合、私有チャンネルの再認可と失効を検査。
- **PASS**: shipping checks --base HEAD（`/tmp/gridspace-autopaging-shipping.log`）。既存未commit変更集合の対象lint、SPDX、locale safety。
- **FAIL→テスト修正**: 最初のUI実行では、再試行後の余分なフリックで古い行が画面外へ移ったことと、読取専用の本文にisHittableを要求して高速フリックで目的行を通過したことで2件失敗した。前者は追加入力なしに保持行の座標を比較し、後者は読み込み済み本文の存在で判定する形へ修正。失敗した実行全体を合格扱いにはしない。
- **FAIL→実装修正**: 初回のタブスワイプ後の更新テストも失敗した。SwiftUIのrefreshableが隣接タブ非選択時のクロージャーを保持し、追加したisSelectedの検査で更新を拒否していた。共有loadからこの検査を外し、自動ページ取得の選択判定とキャンセルはフッターのtaskへ限定した。アカウント/セッション世代の検査は維持する。
- **FAIL→実装修正（再試験）**: 2回目は自動ページ取得と更新の確認が進んだが、再試行後の保持行の位置比較で88ptの移動を検出した。独立したエラー行を除去するとListの末尾位置が補正されていたため、再試行UIを高さ88ptの共通フッター内へ移し、通常時・読込中・失敗時で行の高さを揃えた。再試験対象に継続する。
- **PASS**: フッター修正後の`check-mac.sh`（`/tmp/gridspace-autopaging-final-mac.log`）。Core 50件とSimulator SDK両アーキテクチャのビルドを再確認。
- **PASS（3回目の位置保持）**: 再試行成功時に保持行の画面座標が4pt以内に収まり、エラーを消しても位置が飛ばないことを確認した。通常TLの61件目までの自動取得と終端、連携先の自動ページ取得/タブ復元も合格。
- **FAIL→テスト操作の調整（3回目）**: ローカルチャンネルの特定の本文待ちだけが高速フリックで失敗した。スクロール用ヘルパーを短い制御ドラッグへ変更し、合成アクセシビリティのテキスト診断も追加して対象を再試験する。
- **PASS（最終コードで8 UIケース）**: 3回目の実行（`/tmp/gridspace-autopaging-final-device.log`）では8件中7件が合格。通常TLの2回の追加取得/終端、失敗後の同一ページ再試行と保持行の座標、連携先ページ取得/保存タブ復元、更新/タブ切替の4件を確認。唯一失敗したローカルチャンネルは、短いドラッグへ変更した単独再試験（`/tmp/gridspace-autopaging-channel-verified.log`）で合格した。製品コードはこの2実行間で変更していない。実行全体のFAILは残し、8ケースの合格を実行ごとに区別して記録する。

全実行はオフラインの合成アカウント/本文と独立した保存領域を使用し、本番への投稿・リアクション送信や写真ライブラリの操作は行っていない。実機を意図的に撮影せず、失敗した3 bundleはテキストのsummary JSONを出力した後、画像/動画を開かず削除した。成功した単独再試験のbundleだけを一時領域へ残す。Simulator、backend fixture、DB/Redisを新しく起動していない。

**PASS（配布）**: 実機向けの署名付きテストビルドを再インストールし、テスト引数なしで通常起動した（`/tmp/gridspace-autopaging-install.log`、`/tmp/gridspace-autopaging-launch.log`）。既存のログイン/設定を保持し、最終diff空白検査も合格。commit/PR/外部送信は行っていない。

## 2026-11-16 通常アプリの実機スクロール・CPUプロファイリング

合成TLではなく、端末へインストール済みのDebugアプリを通常起動し、実サーバーへ接続したTLをXCTestから上下スクロールしてTime Profilerで記録した。投稿・リアクション・アカウント変更はせず、本文や画像を診断ログへ添付せず、意図的な画面撮影も行っていない。`NativeLiveScrollProfiling`はテストランナーの`GRIDSPACE_PROFILE_LIVE_APP=1`を明示した時だけ動き、fixture引数を渡さず`activate()`する。通常のテスト実行ではスキップする。

- **PASS（修正前）**: Time Profilerの約20秒のスクロール記録（`/tmp/gridspace-scroll-cpu-before.trace`、集計`/tmp/gridspace-scroll-cpu-before-summary.json`）。サンプルの記録幅21.075秒、メインスレッド19,564サンプル/重み19.564秒。メインスレッドのサンプルに含まれる本文rendererが27.01%、絵文字フレーム生成が25.03%。これらは包含スタックの割合であり合算しない。静止時の別の約8秒の記録でも同じ処理が多く、画像生成29.9%、本文のsizeThatFits 24.1%だった。
- **原因と修正**: 絵文字の読込完了→resized→本文body→新しいNSTextAttachment→attributedTextが不一致→画像読込→resized、という循環があった。表示中の本文ごとに、本文ノード・origin・著者host・絵文字URL・文字サイズ・ぼかし公開状態・セッション世代をキーに整形済みテキストを1件保持する。サイズ調整ではattachmentの同一性を保ち、入力変更時だけ作り直す。非表示時に破棄し、永続保存しない。
- **PASS（回帰検査）**: 新しいattachmentが同じ内容でも不一致となる条件を再現し、連続20回のサイズ調整では同じテキストを返すこと、URL/フォント/ぼかし/世代/clearで更新することを追加検査した。実機単体20件（MFM 8、アニメーション5、表示名4、表示用メモリ3）とUI 3件（固定高/スクロール復帰、新着保留と反映、絵文字入り表示名の画面遷移）が合格（`/tmp/gridspace-scroll-fix-device.log`）。
- **PASS**: `check-mac.sh`のCore 50件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-scroll-fix-mac.log`）。shipping checks --base HEADの対象lint/SPDX/locale safetyも合格（`/tmp/gridspace-scroll-shipping.log`）。
- **FAIL / 未取得**: Animation HitchesとTime Profilerを併用した55秒記録は、停止後の保存処理が完了せず、エクスポートはDocument Missing Template Errorになった。自身のレコーダーを停止し、不完全なtraceだけ削除した。CPU単独の記録へ切り替えたため、FPS、フレーム落ち数、hitch率は測定結果として扱わない。端末へのpid/name指定attachもプロセス探索で失敗したため、同端末の全プロセスCPU記録からGridSpace/メインスレッドだけを抽出した。

サンプル重みは統計的なCPU時間の近似であり、フレーム時間や厳密なCPU占有時間ではない。実際のTLはスクロール位置や新着が変わるため、前後の本文集合は同一ではない。生trace、サンプルXML、バイナリ、xcresultは一時領域に置き、リポジトリには集計と手順のみ記録する。

**PASS（修正後・通常アプリ）**: 同じ18回の上下ドラッグ手順でTime Profilerの20秒記録を取り直した（`/tmp/gridspace-scroll-cpu-after.trace`、集計`/tmp/gridspace-scroll-cpu-after-summary.json`）。記録幅20.813秒、メイン3,892サンプル/重み3.892秒、全アプリ重み4.277秒。修正前の21.075秒/19.564秒と時間幅で補正すると、メインのサンプル重みは約79.86%減となった。絵文字フレーム生成は4,897→157サンプル、本文sizeThatFitsは1,190→82サンプル。残るメイン処理は主にSwiftUI/UIKit経由のスクロール処理であり、同じ割合のフレーム改善や全状況での滑らかさを保証する値ではない。静止時の別記録も8.917秒中451サンプル/重み0.451秒まで減少（`/tmp/gridspace-scroll-idle-after-summary.json`）。前後のアプリdylib UUIDをtraceと一致させてatosでシンボル化している。

通常アプリのスクロール用テストも前後とも合格（`/tmp/gridspace-scroll-cpu-before-test.log`、`/tmp/gridspace-scroll-cpu-after-test.log`）。修正後の署名付きビルドは実機試験でインストール済みで、最後にテスト引数なしの通常起動へ戻した（`/tmp/gridspace-scroll-final-launch.log`）。既存のログイン/設定を保持し、資格情報の再入力、commit/PR/外部送信は行っていない。

## 2026-11-16 画像の通信共有・チャンク受信・先読み

画像ごとにephemeral URLSessionを作り、AsyncBytesを1バイトずつDataへ追加していた処理を、接続を共有するNativeImageTransportへ変更した。URLSessionDataDelegateのチャンクを上限付きで蓄積し、HTTPの宣言サイズと実際の受信量の両方で8 MiBを制限する。添付画像の原本はディスクへ書かず、Cookie/資格情報ストアを使わず、HTTPへのリダイレクトを拒否する。条件付き読取ヘッダーだけを許可し、別ホストへのリダイレクトでは検証ヘッダーも外す。HTTP拒否・304は既存のキャッシュへ返し、一般添付の2xx成功も引き継ぐ。

通常TLとローカルチャンネルで、現れたノートの次の3投稿・各最大2枚のサムネイルを先読みする。CW・非表示ノート・センシティブ添付を除外し、連携先の私有チャンネルは対象外とする。同時2件、待機最大6件、スクロール位置に合わせて未開始分を入れ替える。画面の通常取得と同じpending/縮小済み画像を使い、セッション破棄時に待機・実行中の先読みも無効化する。画像の240pt固定枠は維持する。

- **PASS**: 実機単体22件（画像通信6、表示用メモリ6、公開画像キャッシュ10）と画像の固定高/スクロール復帰UI 1件（`/tmp/gridspace-image-speed-device.log`）。分割受信・不明/既知サイズの上限・キャンセル前後の完了・認証ヘッダー除外・リダイレクト・304/拒否・先読みとの取得共用・同時数・キュー入替・clear後の失効を検査。
- **PASS**: HTTPの2xx成功を保つ最終調整後、画像通信6件（201も追加検査）と画像UI 1件を再実行（`/tmp/gridspace-image-speed-final-device.log`）。
- **PASS（端末上の合成ベンチマーク）**: 1 MiBを32 KiBチャンクで配信するURLProtocol fixtureを、旧来の毎回セッション生成/1バイト受信と新方式で各3回取得して同一データを比較。最終実行の中央値は旧22.910ms、新0.360msだった。この値は回線・DNS・TLS・サーバー待ちを含まない受信処理の測定であり、実画像の表示が同じ比率で速くなるという意味ではない。接続再利用と画面外の先読みの効果もこのfixtureでは測定していない。
- **PASS**: 最終`check-mac.sh`のCore 50件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-image-speed-final-mac.log`）。shipping checks --base HEADも対象lint/SPDX/locale safetyが合格（`/tmp/gridspace-image-speed-shipping.log`）。

テストは合成データ・所有画像で行い、実ユーザーの写真ライブラリへアクセスせず、意図的な実機撮影を行っていない。新しいSimulator、backend fixture、DB/Redisは起動していない。

**PASS（通常アプリ・配布）**: テスト引数なしで実アカウントの通常アプリを起動し、既存の明示opt-inドライバーで上下18回のドラッグも実行して合格した（`/tmp/gridspace-image-speed-live-scroll.log`）。これは通常TLの操作確認であり、ネットワーク越しの全画像の表示時間を個別に測った結果ではない。最後に通常起動へ戻した（`/tmp/gridspace-image-speed-final-launch.log`）。最新の署名付きビルドは実機試験でインストール済み。既存のログイン/設定を保持し、commit/PR/外部送信は行っていない。

## 2026-11-16 通常アプリの残るスクロール負荷・絵文字フレームと最適化ビルド

再度、実アカウントの通常TLを上下18回ドラッグし、Time Profilerで20秒のCPU記録を取得した。現在のDebugアプリの記録幅20.859秒、メイン4,726サンプル/重み4.726秒、全アプリ5.082秒。メインの27.30%（1,290サンプル）がNativeEmojiFrames.image(at:)で、アニメーションの周回ごとにImageIOで同じフレームを生成していた（`/tmp/gridspace-scroll2-before.trace`、`/tmp/gridspace-scroll2-before-summary.json`）。

生成済みの公開絵文字フレームを内容のSHA-256/ピクセル寸法/フレーム番号で共有し、16 MiB/512枚のメモリに制限する。再生tickはキャッシュだけを同期参照し、未生成フレームは背景タスクで縮小・展開する。複数プレイヤーの同じフレームの生成は1回にまとめる。遅れた結果が、現在のフレーム・別の絵文字・サイズ変更・再生停止後の先頭フレームを上書きしないよう世代と要求番号を検査する。静止画、Reduce Motion、非表示/背景の停止、巨大画像の制限は維持する。

- **FAIL→修正**: 初回の回帰実行（`/tmp/gridspace-scroll2-regression.log`）で、先読みを待つ表示側が所有タスクより先に再開した際、完了画像を返した直後なのに同期キャッシュに未格納となる競合を既存テストが検出した。全待機者が世代を確認してから画像をキャッシュへ公開するよう修正し、異なる新規リクエストを消さないためリクエストIDも検査する。絵文字フレームの待機者にも同じ規則を適用した。失敗bundleはテキストsummaryを出力後、画像/動画を開かず削除した。
- **PASS**: 修正後の実機単体26件（絵文字アニメーション8、MFM 8、表示名4、表示用メモリ6）と固定高/画像・絵文字のスクロール復帰UI 1件（`/tmp/gridspace-scroll2-verified.log`）。別プレイヤー/周回での同一フレーム共有、サイズ/データの区別、背景生成、同時生成の重複防止、clear/再生停止/再利用後の古いフレーム排除、先読み競合を検査した。初回に実行した新着保留/反映UIと名前の画面遷移UIも合格している。
- **PASS**: 最終`check-mac.sh`のCore 50件、Simulator SDK arm64/x86_64ビルド（`/tmp/gridspace-scroll2-final-mac.log`）。shipping checks --base HEADの対象lint/SPDX/locale safetyも合格（`/tmp/gridspace-scroll2-shipping.log`）。
- **FAIL / 未取得**: Animation Hitches単独の8秒記録も、終了後の保存処理が45秒以内に完了しなかった。自身のレコーダーだけを停止し、不完全なtraceは削除した。FPSやhitch率を取得済みの数値として扱わない。

通常インストールもSwift最適化なしのDebugになっていたため、`check-device.sh --install`をReleaseへ変更した。`--test`と通常の開発ビルドはDebugを維持し、fixtureを通常利用へ持ち込まない。Releaseでも同じbundle ID/署名チームで更新するため、ログインと設定を保持する。`bash -n`の構文検査は合格。

**PASS（Releaseの通常アプリ）**: `check-device.sh --install`でCore 50件、`-O -whole-module-optimization`付きReleaseビルド、署名・更新インストール・通常起動が成功した（`/tmp/gridspace-scroll2-release-install.log`）。Debugの既存UIランナーからReleaseのUITargetAppPathを明示したopt-in設定で実TLを上下18回ドラッグし、Time Profilerを再取得した。traceのアプリUUID `897632FC-B81F-391A-A198-FDBAC393E897` とRelease dSYMが一致した（`/tmp/gridspace-scroll2-release-profile-summary.json`）。記録幅20.841秒、メイン4.136秒、全アプリ4.412秒。メイン上の画像フレーム生成は22サンプルで、修正前の1,290サンプルから減少した。全メイン重みの時間補正後の低下は約12.41%であり、フレームレートの改善率としては扱わない。Debug→ReleaseとTL内容の変化も含むため、個々の変更の効果を厳密に分離したA/B試験ではない。

**計測への自動操作の影響**: Release記録のメイン4,136サンプル中1,877（45.38%）にAXRuntime/UIAccessibility等が含まれていた。VoiceOverは無効であり、UITestの画面情報取得の負荷が混ざる。プロファイリング用の座標は毎回TLのツリーから求めず、一度測ったviewportからアプリ基準の座標へ変更した。変更後も実TLの18ドラッグが合格し、CPU記録幅20.836秒/メイン4.747秒になった（`/tmp/gridspace-scroll2-low-ax-summary.json`）。この値を性能の再悪化と断定せず、自動化・異なる本文集合・待機時間の影響を含む参考値とする。端末は低電力モードfalse、thermalState=1だった。システムシンボルは`xcodebuild -prepareDeviceSupport`で対象OS用を準備し、UUID一致を確認して解析した。AXを除く残りの多くはSwiftUIのViewGraph更新とCA transaction/layout/displayだった（`/tmp/gridspace-scroll2-system-summary.json`）。

**PASS（OSのスクロール指標・FPS/引っかかりを別経路で測定）**: CLIのAnimation Hitches保存失敗に代えて、[AppleのscrollingAndDecelerationMetric](https://developer.apple.com/documentation/xctest/xctossignpostmetric/scrollinganddecelerationmetric)を使う明示opt-inケースを追加し、Releaseの実TLで上下フリックを5測定セット実行した（`/tmp/gridspace-scroll2-hitch-metrics.log`、`/tmp/gridspace-scroll2-hitch-metrics.json`）。テストは合格し、報告値は以下だった。

| 指標 | 結果 |
|---|---|
| Frame Rate | 平均58.086fps、57.217–58.849fps |
| 測定セットのscroll duration | 平均2.386秒 |
| Number of Hitches | 5セットで3回（1、1、0、0、1） |
| Hitches Total Duration | 各16.616、49.889、0、0、16.613ms |
| Hitch Time Ratio | 平均7.016ms/s、最大21.112ms/s |

frame countはAPIから0と報告されたため、総描画フレーム数として利用しない。FPS/引っかかりはOSから報告された値をそのまま記録し、すべてのTL内容で滑らかになったとは評価しない。平均値だけでなく、短い引っかかりが残ることも確認した。元のDebug版について同じスクロール指標を取得していないため、FPS/引っかかりの前後改善率は算出しない。

最後に修正版のReleaseをテスト引数なしで通常起動へ戻した（`/tmp/gridspace-scroll2-final-launch.log`）。ログイン/設定を保持し、実ユーザーの本文・画像をレポートへ添付せず、意図的な端末撮影・投稿・リアクション送信・commit/PR/外部メッセージ送信は行っていない。

## 2026-11-16 ホームアイコンから選択中TLの先頭へ戻る

下部のホームアイコンで、現在選択している通常TL/ローカル・連携先チャンネルの先頭へ戻る。ノート詳細などのナビゲーションを閉じ、別の下部タブからもTLへ戻る。要求は毎回新しいUUIDと選択中のfeed IDで送り、未選択のフィードへ後から適用しない。フィード選択は維持し、保留中の通常TLの新着も先頭へ反映する。アカウント変更時に要求を破棄する。

- **PASS**: `check-mac.sh`のCore 50件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-home-top-mac.log`）。
- **PASS**: 通常/連携先TLの実機単体17件（`/tmp/gridspace-home-top-device.log`）。
- **PASS**: shipping checks --base HEAD（`/tmp/gridspace-home-top-shipping.log`）の対象lint/SPDX/locale safety。
- **PASS（実機UI 4件）**: ノート詳細からの復帰、保留中の新着の反映、選択中フィードだけの先頭復帰と他フィードの位置保持、検索タブからの復帰、連携先チャンネルの先頭復帰とタブ設定復元を確認（`/tmp/gridspace-home-top-device.log`）。実行全体が合格し、合成データだけを使用した。意図的な実機撮影、実アカウントでの投稿/リアクション送信は行っていない。

**PASS（配布）**: `check-device.sh --install`で署名付きReleaseを更新インストールし、テスト引数なしで通常起動した（`/tmp/gridspace-home-top-release-install.log`）。既存のログイン/設定を保持し、最終diff空白検査も合格。commit/PR/外部メッセージ送信は行っていない。

## 2026-11-16 本文なしリノート行の誤ったサーバー応答エラー

利用者の許可のもとiPhoneミラーリングで実画面を確認した。本文なしのリノートがTLへ掲載済みで、その行の操作欄の下に「サーバーからの応答を確認できませんでした。」「状態を再取得」が出ていた。これは投稿画面の送信エラーではなくNativeReactionModel.errorの表示だった。公開APIでも最近のリノートが存在し、text/CW=null、添付・投票・返信なし、ローカル著者、reactionStateComplete未付与のメタデータを確認した。本文・画像・資格情報は診断ログへ保存していない。

原因はNativeAPI.hydrateReactionsが意図どおりpure renoteを対象外にする一方、NativeNoteRowの初回表示がその行にも追加のrefreshを行い、NativeReactionModelがnilのreactionStateCompleteをinvalidResponseとしていたこと。行の自動読取とライブ更新のdirtyバッチからpure renoteを除外し、明示的な再取得でも意図的な状態欠落をエラーにしないよう修正した。純粋リノートのライブリアクション状態は適用せず、外側のリノート自身の削除通知の購読は維持する。本文のある引用と通常ノートのリアクションは従来どおり更新する。

- **PASS**: 実機単体43件（NativeAPI 24、ライブリアクション8、複数リアクション11）とUI 2件（`/tmp/gridspace-pure-renote-device.log`）。pure renoteの未付与状態を再取得してもエラーにしないこと、削除通知を維持しながら無用な状態読取をしないこと、引用の更新、行に誤エラーがないこと、原ノートのリノート画面へ正しく進むこと、通常リアクションの追加/人物入替/解除を検査した。UIで送信ボタンは押していない。
- **PASS**: `check-mac.sh`のCore 50件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-pure-renote-mac.log`）。shipping checks --base HEADの対象lint/SPDX/locale safety（`/tmp/gridspace-pure-renote-shipping.log`）。
- 実機テスト開始時に端末ロックでXcodeのpreflightが待機した。画面確認後にミラーリングを終了し、利用者のロック解除後に同じ実行が進み、全体が合格した。アプリのテスト失敗としては扱わない。

実サーバーへのリノートの再送・削除・新しい投稿やリアクション送信は行っていない。実画面は許可された確認にだけ使用し、スクリーンショットをリポジトリや検証添付へ保存していない。テストは合成データ・所有画像と専用保存領域を使用した。backend/frontendは読み取りのみで編集していない。

**PASS（配布、2026-11-17）**: `check-device.sh --install`で署名付きReleaseを更新インストールし、テスト引数なしで通常起動した（`/tmp/gridspace-pure-renote-release-install.log`）。既存のログイン/設定を保持した。commit/PR/外部メッセージ送信は行っていない。


## 2026-11-17 通知一覧をWeb版の見た目へ整理

WebのMkNotification/MkGridspaceNotification/MkNotificationLayoutとnotification.module.scssを参照し、ネイティブ一覧を42ptのアバター、小さな種類別アイコンまたはアニメーション絵文字、表示名と時刻、1行のノート要約へ変更した。通知の中でNativeNoteRowを展開せず、本文からノート、アバターと表示名からプロフィールへ進む。表示名と要約の絵文字は共通キャッシュを使う。CWは注意書きだけ、hiddenノートは非表示の案内だけを出し、添付画像そのものは一覧から読み込まない。

上部はコンパクトなタイトルと種類メニュー、未読数の小さなバッジ、一括既読のチェック、追加メニューへ整理した。未読状態の常時説明や再取得ボタンは外し、エラーや結果がある場合だけ案内する。未読状態の明示的な再取得、一括既読の確認、旧権限・不確定応答の扱い、通知を開くだけでは既読にしない仕様を維持した。Web版のメンション/ダイレクト専用一覧や連携先通知の統合は、この見た目の変更には追加していない。

- **PASS**: `check-mac.sh`のCore 50件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-notification-design-mac.log`）。
- **PASS**: 通知の単体12件と合成データのUI 1件（`/tmp/gridspace-notification-design-final-sim.log`）。CW/空のCW/hidden/リノート内のCW、未読の確認、絞り込み、プロフィールへの移動と復帰、既読確認のキャンセルと確定、ノートへの移動、WebViewを使わないことを確認。
- **FAIL → 修正・再試験PASS**: 初回の追加単体テストに必須のvisibilityが欠け、デコードで失敗した（`/tmp/gridspace-notification-design-sim.log`）。合成データを修正し、上記の12件を再実行した。初回UIは合格した。画面確認で種類ラベルの折り返しと区切り線の位置を見つけて修正し、再試験の画面も確認した。
- **PASS**: shipping checks --base HEADの対象lint/SPDX/locale safety（`/tmp/gridspace-notification-design-shipping.log`）。

UI検証にはDEBUG限定のオフラインURLProtocolと専用保存領域、所有する合成画像だけを使用した。公開/私有の実通知や実ユーザー画像を撮影せず、実サーバーへ既読操作・投稿・リアクションを送信していない。backend/frontendは読み取りのみ。

**PASS（配布）**: `check-device.sh --install`で署名付きReleaseを更新インストールし、テスト引数なしでiPhoneを通常起動した（`/tmp/gridspace-notification-design-release.log`）。Core 50件も再度合格した。既存のログイン/設定を保持し、commit/PR/外部メッセージ送信は行っていない。

**PASS（最終ダーク表示）**: 同じ合成データのUI 1件が合格し、日本語の相対時刻（「分前」）も検査した（`/tmp/gridspace-notification-design-dark-final.log`）。明暗両方の合成画面を目視し、アバター・通知バッジ・文字・区切り線を確認した。時刻はTextのlocale環境へ日本語を渡し、OS言語に引っ張られないよう調整した。

ダーク表示の初回検証は通知タブへ移らずTLのまま未読数を待って失敗し、その後の自動操作でXCTestランナーが停止した（`/tmp/gridspace-notification-design-dark-sim.log`）。初期認証済みホームの表示とタブの操作可否、通知ナビゲーションの完了を待つようUIテストを補い、上記の再試験は67.969秒・失敗0件で完了した。最終xcresultへ後から添付されたcrash logは先行実行のランナーPID 70205のものであり、アプリ本体や再試験ランナーPID 70688のクラッシュではない。実行全体のTEST SUCCEEDEDと終了コード0を確認した。最終の空白検査も合格。


## 2026-11-17 投稿後・TLのタブ切り替えで表示を保持

投稿成功時のsession.refreshContentがセッション世代を更新し、TLの再取得、表示位置の初期化、画像/MFMキャッシュとリアクション状態の破棄を起こしていた。投稿・返信・リノート/引用の確定成功では世代を変えず、確定したノートだけを同じセッションの画面へ通知するよう変更した。TLの対象なら既存の新着キューへ重複を除いて加え、途中を読んでいる間は行や位置を動かさない。先頭でのみ差し込み、プロフィールの対応するフィルターと元ノートの返信一覧にも追加する。元ノートの返信/リノート件数は、そのノートだけを裏で照合する。照合失敗は投稿失敗として表示せず、未確定・送信中のリアクションや古い世代を上書きしない。

通常TL/ローカルチャンネルのモデルはセッションが保持し、ページの再生成でも読み込み済みのノートとページ送りの状態を維持する。タブの切り替えで新しく購読した際の重複する先頭取得は行わず、実際の接続断の再接続では先頭から不足分を補完する。空のTLも読み込み済みとして扱う。削除したタブのモデルは破棄し、ログアウト・アカウント変更・背景移行では従来どおり全モデルと内容を消す。連携先専用の非公開チャンネルはこの保持対象へ混ぜず、認可付きAPIでの再確認と非表示時の破棄を維持した。

- **PASS**: Core 50件とSimulator SDK arm64/x86_64ビルド（`/tmp/gridspace-retain-timeline-mac.log`）。
- **PASS**: 単体46件（`/tmp/gridspace-retain-timeline-verified.log`）。TLの更新/ページ送り11、ライブTL10、ライブリアクション9、プロフィール10、会話5、セッション1。投稿の保留・重複除去・対象フィード/著者の検査、古いページ取得中に確定した投稿の保持、接続再開時と本当の再接続の区別、キャッシュの剪定/失効、返信/プロフィールのカーソル維持、古い照合やキャンセル済み画面の拒否を検査した。
- **PASS**: shipping checks --base HEADの対象lint/SPDX/locale safety（`/tmp/gridspace-retain-timeline-shipping.log`）。

初回試験では、照合後に古い行を再表示すると件数が戻るケースを検出した。元の行オブジェクトをソースの識別子として維持し、上記の再試験で修正を確認した。UI試験の繰り返し起動では、古い画面のキャンセル済みload完了後にlistenが呼ばれ、新しい画面の購読をstopLiveで止めてしまう競合も見つかった。合成データ限定の一時ログ（`/tmp/gridspace-retain-timeline-startup-trace.log`）で、キャンセル済みの処理が再度listenを呼ぶ順序を確認した。ページは取得後にも元の世代とキャンセルを確認し、listen自体も古い呼び出しをstopLiveより前で拒否する。再現する単体テストを追加して合格した。一時診断コードは削除した。途中の失敗は`/tmp/gridspace-retain-timeline-sim.log`、`/tmp/gridspace-retain-timeline-final-sim.log`、`/tmp/gridspace-retain-timeline-ui-final.log`、`/tmp/gridspace-retain-timeline-diagnostic.log`に記録した。

すべての投稿操作試験はDEBUGのオフラインURLProtocolと専用保存領域、所有する合成データだけを使用した。実アカウントへの投稿・リノート・リアクション送信、実通知の既読操作、実ユーザーの画面撮影は行っていない。backend/frontendは読み取りのみで編集していない。

**PASS（最終UI 2件）**: `/tmp/gridspace-retain-timeline-verified.log`の実行全体がTEST SUCCEEDED・終了コード0で完了した。合成ノートを途中までスクロールして投稿し、投稿前と同じ行・同じY座標（許容4pt）を維持すること、新着の確定反映、先頭での2回目の投稿、古い行が残ることを確認した。ホームからローカル・グローバルを経由して実際の左右スワイプで戻り、同じ行・同じ座標と取得済みの先頭を維持することも確認した。46件の単体テストと合わせて全件合格した。テストのfixtureは、再度の先頭取得があると全ノートIDと本文の取得番号が変わるため、不必要な取得を既存行の重複除去で見逃さない。

**PASS（配布）**: `check-device.sh --install`のCore 50件と署名付きReleaseビルドが合格し、iPhoneへ更新インストール、テスト引数なしで通常起動した（`/tmp/gridspace-retain-timeline-release.log`）。既存のログイン/設定を保持した。最終の空白検査も合格。commit/PR/外部メッセージ送信は行っていない。


## 2026-11-17 iOSクライアントのコミット前チェックポイント

利用者の指示により、iOSアプリ本体・Core・テスト・補助スクリプト・iOS CI・開発計画/検証記録の171ファイルをコミット対象としてまとめた。Webの移行/互換対応、backend、localeの作業ツリー差分はこのコミットへ含めない。ビルド生成物、端末の設定ファイル、認証情報は含めない。

- **PASS**: Core 50件を再実行（`/tmp/gridspace-ios-commit-core.log`）。直前のアプリ内46件・UI 2件、署名付きReleaseビルドとiPhoneへの更新/通常起動の合格記録も確認した。
- **PASS**: 絵文字カタログとMFMの`--check`で生成データを照合。第三者ライセンスの文面を変えずに行末空白を除くよう生成処理を揃え、Swift 2ファイルの末尾空行も整えた。
- **PASS**: shipping checks --base HEADの対象lint/SPDX/locale safety（`/tmp/gridspace-ios-commit-shipping.log`）。ステージ済みの空白検査、対象パス、生成物の除外、認証情報の混入も確認した。認証情報パターンへの一致は合成fixtureのテスト用文字列だけだった。
