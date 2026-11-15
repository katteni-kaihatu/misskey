# PWA基盤・GridSpace固有機能の実装計画付録

確認日: 2026-11-15。対象コミット: `f1bd2e3c4bebf931be8c49342691f03e3cdeb49b`。この付録はソース調査結果と実装案を区別して記す。iPhone・iPad・WKWebViewでの実行確認はまだ行っていない。通常画面、設定の全項目、標準ウィジェットの全種類は別の機能表と合わせて扱う。

## 調査で確認した前提

- `secure: true` のAPIはMiAuthトークンでは呼べない。`packages/backend/src/server/api/ApiCallService.ts` の `isSecure = user != null && token == null` と `AuthenticateService.ts` の認証結果による制約である。ここでいうnative user tokenはMisskeyの第一者ログイン用トークンの種類であり、iOSアプリ用という意味ではない。
- ログイン情報は `packages/frontend/src/i.ts` の `miLocalStorage` にある。SafariのPWAとWKWebViewがその情報を自動共有するとは扱わない。
- 現在のService Workerはナビゲーションをネットワークから取得し、失敗時にオフライン案内を返す。タイムライン全体をオフライン保存する実装ではない。`packages/sw/src/sw.ts` と `scripts/lang.ts` では主に言語キャッシュを扱う。
- GridSpaceの非公開投稿は通常の投稿キャッシュ、localStorage、IndexedDBへ保存しない。バックグラウンドに移ると本文・投稿者・添付情報を破棄し、復帰時に表示済みの全IDを再認可する。`MkGridspacePrivateNotes.vue` と `gridspace-note-suspension.ts` に実装がある。
- ペア先のIDを通常APIのローカルIDとして扱えない。`gridspace:<kind>:<id>`、出典のorigin、actor URI、チャンネル文脈を区別する。取得失敗を空一覧・未読0と同一視しない。

## 段階と担当方式

| 段階 | 作業 |
|---|---|
| S0 | 機能表・ソース根拠・互換性確認項目を固定する |
| S1 | 既存Webを動かすiOSホスト、第一者Web認証、画面遷移を整える |
| S2 | 写真・ファイル選択をネイティブ化し、既存アップロードへ渡す |
| S3 | 共通実行環境・状態・アカウント・限定ブリッジを実装する |
| S4 | タイムラインと投稿画面を互換性確認後にネイティブ化する |
| S5 | ソーシャル機能・標準ウィジェットを順にネイティブ化する |
| S6 | 実機・権限・障害・配布条件を検証して公開する |

NはiOS側が担当する機能、HはWebとネイティブで処理・状態を共有する機能、Wは既存Webの画面・認証を維持する機能を表す。Wも完成版の対応方式であり、機能未対応を意味しない。後続段階のN/Hは提案であり、S0時点で実装済みではない。

## PWA・アプリ共通機能

表内のパスはリポジトリルート相対。Fは `packages/frontend/src/`、Bは `packages/backend/src/`、SWは `packages/sw/src/`、FSは `packages/frontend-shared/` の略。

| ID | 保持する機能・条件 | ソース根拠 | 方式・段階 | 互換性の確認条件 |
|---|---|---|---|---|
| P01 | 単体アプリ起動、名前・アイコン・背景色・テーマ色、管理者のmanifest上書き | B/server/web/ClientServerService.ts | N S1/S6 | コールド起動とテーマを確認。インスタンスごとの設定のうちバイナリ更新が必要な項目を明示する |
| P02 | ルート起動、指定画面起動、`/?safemode=true` | 同上、F/_boot_.ts | H S1 | 壊れたプラグインやCSSを動かさずセーフモードへ入れる |
| P03 | 共有先としてtitle/text/urlを受信 | manifest、F/pages/share.vue | N/H S1/S2 | 共有拡張が内容・アカウントを保持し、キャンセル後は元のアプリへ戻る |
| P04 | 共有投稿の公開範囲、localOnly、宛先、返信、Renote、添付 | F/pages/share.vue | H S2/S4 | URL引数の変換、不可視投稿、無効IDを確認。誤宛先投稿・二重投稿を防ぐ |
| P05 | 本文・ローカルリンク・リモートリンクのコピーと外部共有 | F/utility/get-note-menu.ts、gridspace-note-menu.ts、copy-to-clipboard.ts | N S1 | 出典を区別したURLを共有し、取り消しで状態を失わない |
| P06 | 写真・カメラ・Filesの選択、複数添付、選択順 | F/os.ts、components/MkPostForm.vue | N/H S2 | 既存uploaderへ渡し、順序・名前・説明・センシティブ設定・画像編集を保持する |
| P07 | ダウンロード、Drive保存、アカウントデータと設定の入出力 | F/pages/settings/account-data.vue、profiles.vue、preferences.vue、preferences/utility.ts、utility/drive.ts | N/H S2/S3 | 既存形式、ファイル名、MIME、取消・失敗・部分成功を確認する |
| P08 | Push登録・解除、アカウントごとの購読、既読同期設定 | F/components/MkPushNotificationAllowButton.vue、B/server/api/endpoints/sw/*.ts | W→N S1/S6 | APNs経路完成までは同等としない。二重配送とログアウト後配送を防ぐ |
| P09 | 通知、アンテナ未読、チャット新着、全既読通知 | SW/types.ts、sw.ts | N/H S6 | 全イベントをAPNsとアプリ内通知に対応させ、正しいアカウントへ送る |
| P10 | 通知からフォロー、ユーザー表示、返信、Renote、申請承認・却下、設定表示 | SW/sw.ts、scripts/operations.ts | N/H S6 | OS上の表示制限がある操作も、対応画面で同じ操作が可能であることを確認する |
| P11 | 通知本文・言語・種別、まとめ方、絵文字アイコン、古い通知の抑制 | SW/scripts/create-notification.ts、sw.ts | N/H S6 | 意味・まとめ方を保持し、1日超のイベントを抑制する現行処理と比較する |
| P12 | 通知クリック・クローズ時の既読化、全アカウントの全既読 | SW/sw.ts、scripts/operations.ts | H S6 | iOSが通知消去を通知しない場合の差を明示し、同じ既読操作をアプリ内に用意する |
| P13 | オフライン・タイムアウト・5xx時の案内と再読込 | SW/sw.ts、scripts/lang.ts | N/H S1 | 機内モードと障害を確認する。既存にない全文オフライン閲覧を実装済みと数えない |
| P14 | 更新検出、キャッシュ削除、言語初期化 | F/utility/initialize-sw.ts、SW/sw.ts | H S1/S3 | Web資産とホストのバージョンを照合し、下書きを失わず再起動・再読込できる |
| P15 | 前景のストリームheartbeat、切断・復帰 | F/stream.ts | H S3/S4 | アカウントごとに接続責任を定め、復帰後に差分を補う。背景の常時接続を前提にしない |
| P16 | 画面をスリープさせない設定 | F/boot/common.ts | N S3 | 使用画面だけidle timerへ反映し、退出時に戻す |
| P17 | 通知・共有・投稿・人物・チャンネル・Play・Page・認証callbackのリンク | F/router.definition.ts、SW/scripts/operations.ts、F/_boot_.ts | N/H S1 | origin、アカウント、query、fragmentを保持し、未知画面はWebへ戻す |
| P18 | 外部ブラウザ、新窓、ポップアップ、ページ窓、戻る・閉じる | F/os.ts、utility/get-note-menu.ts、pages/share.vue、boot/common.ts | N/H S1 | 画面履歴の担当を一つにし、外部originには特権ブリッジを渡さない |
| P19 | zen、safemode、login ID、UI種別による起動 | F/boot/common.ts、SW/scripts/operations.ts、scripts/login-id.ts | H S1 | モードと選択アカウントが正しく再現される |
| P20 | 言語、日付表示、テーマ、システムdark mode、reduce motion | FS/js/config.ts、F/preferences/def.ts、local-storage.ts | H S3 | 明示設定とシステム設定を区別し、Webとネイティブの表示を一致させる |
| P21 | 文字サイズ、フォント、アニメーション、MFM、GIF、ぼかし等の設定 | F/pages/settings/preferences.vue、preferences/def.ts | H S3/S4 | ネイティブが担当する設定だけ更新し、Web専用の値を削除しない |
| P22 | キーボード操作、フォーカス、モーダル、横スワイプ、再読込、無限スクロール | F/preferences/def.ts、boot/common.ts、os.ts | N/H S3/S4 | タッチ・外部キーボード・VoiceOverを確認し、取消後に入力位置を戻す |
| P23 | データセーバーのメディア・アバター・URLプレビュー・コード設定 | F/preferences/def.ts、pages/settings/preferences.vue | H S3/S4 | 禁止された先読み・デコードを行わず、センシティブ設定も守る |
| P24 | 第一者ログイン、パスワード、TOTP、パスキー、復旧コード、登録・再設定・メール確認 | F/pages/settings/2fa.vue、_boot_.ts、サインイン画面 | W/H S1 | WebAuthnのドメイン条件を実機確認する。MiAuthだけで第一者認証を置き換えない |
| P25 | MiAuth、OAuth、従来アプリ認証、外部拡張のインストール | F/_boot_.ts、pages/miauth.vue、B/server/oauth/OAuth2ProviderService.ts | W/H S1 | 同意範囲、取り消し、callback state、出典を保持する |
| P26 | 複数アカウント・サーバー切替 | F/accounts.ts、store.ts、preferences/def.ts | H S3 | 切替中の古い応答を捨て、トークン・通知・下書きが他アカウントへ混入しない |
| P27 | ログアウト、保存情報削除、購読解除、任意の事前バックアップ | F/signout.ts | H S3 | 対象のKeychain・Web保存・キャッシュを消し、古い状態から復活させない |
| P28 | パスワード変更、ログイントークン再生成、履歴、2FA・パスキー管理 | F/pages/settings/security.vue、2fa.vue | W S1 | 第一者認証と再認証を維持し、ネイティブ化は認証方式の検証後に限る |
| P29 | フォロー承認、相互自動承認、ローカル・リモート登録期間条件、表示範囲、検索・AI学習、チャット許可 | F/pages/settings/privacy.vue | W/H S1/S5 | 設定画面へ到達でき、ネイティブ表示・操作もサーバーポリシーを守る |
| P30 | アカウント別名、他サーバーへの移行 | F/pages/settings/migration.vue | W S1 | 移行元・先、確認、不可逆状態、移行済み操作制限を保持する |
| P31 | 設定プロファイル、device/account/server scope、クラウド同期 | F/preferences.ts、preferences/manager.ts、Bのi/registry各API | H S3 | 未知キーを往復保持し、scopeを一致させ、更新責任と競合解消を定める |
| P32 | 自動バックアップ、入出力、復元・初期化、タブ間同期 | F/preferences.ts、preferences/utility.ts、utility/typed-broadcast-channel.ts | H S3 | ループ・古い上書きを防ぎ、既存バックアップを復元できる |
| P33 | 投稿・チャット下書き、絵文字履歴、プラグイン状態、メモ、初期設定、TL条件 | F/local-storage.ts、store.ts | H S3 | データ種別ごとに移行・保持期限を決め、更新失敗でも下書きを失わない |
| P34 | IndexedDB不可時のlocalStorage代替 | F/utility/idb-proxy.ts | H S1/S3 | 保存不可・容量不足を検知し、回復可能な案内を出す |
| P35 | サーバーのPWAを独立して利用し続ける | manifest、SW、認証・設定処理 | H S1/S6 | iOS導入によりSafari側の利用・設定・保存物を勝手に消さない |

## GridSpace固有機能

| ID | 保持する機能・条件 | ソース根拠 | 方式・段階 | 互換性の確認条件 |
|---|---|---|---|---|
| G01 | ペア連携の開始・完了・状態・解除・再試行・再認証 | F/pages/settings/gridspace.vue、B/server/api/endpoints/gridspace/link.ts | W S1 | 双方向、準備中・競合・失敗・解除を確認し、client keyを外部へ渡さない |
| G02 | 非公開閲覧・返信・反応・通知・チャンネル・申請管理の許可 | 同上、private-grant.ts | W/H S1/S3 | 許可前や取消後は利用不可。権限不足を空成功にしない |
| G03 | プロフィールのコピー、対象・除外・失敗表示 | profile-import.ts、B/core/gridspace/profile-protocol.ts | W S1 | 再試行の重複を防ぎ、元・先のアカウントを取り違えない |
| G04 | 絵文字パレットと最近使った絵文字のコピー | F/utility/gridspace-palette.ts、pages/settings/gridspace.vue | W/H S3/S5 | 安定ID、メイン・リアクション用設定、最近32件の現地優先順を保持する |
| G05 | リスト取り込み、フォロー展開、進捗・項目状態・再試行 | F/components/MkGridspaceListImport.vue、list-import.ts、GridspaceFollowExpansionService.ts | W S1 | 鍵・申請待ち・拒否・失敗を区別し、再試行で再送しない |
| G06 | 設定コピー、同意、移植可能キー、除外規則 | F/utility/gridspace-settings.ts、settings-import.ts | W/H S3 | 許可リスト、scope、スキップを保持。トークン・プラグイン・処理記録は移送しない |
| G07 | レイアウト参照の変換：フォルダ・ウィジェット・Deck・リスト・statusbar・透かし | F/utility/gridspace-layout.ts、layout-reference.ts | W/H S3/S5 | 変換失敗は警告。移入AiScriptAppは自動実行しない。移入先固有ロールを誤解決しない |
| G08 | Play取り込みと進捗・再認証・再試行 | play-import.ts、F/pages/settings/gridspace.vue | W S1/S3 | 内容と設定を保持し、部分失敗・取消・再試行を確認する |
| G09 | ペア投稿の公開・ホーム・フォロワー・指定・チャンネル閲覧と匿名公開解決 | F/pages/gridspace-private.vue、private-notes.ts、note-link.ts | H S3/S4 | 閲覧不可本文を漏らさず、公開投稿は正しい公開URLへ遷移する |
| G10 | ホーム・履歴・検索・プロフィール・文脈のローカル／ペア混合ページング | F/utility/gridspace-home-merge.ts、B/core/gridspace/private-protocol.ts、history.ts | H S3/S4 | URI重複除去、同時刻、共通境界を保持し、欠落・重複ページを防ぐ |
| G11 | 非公開投稿のhome/search/profile/show/channel/mentions/direct/favorites/clip/antenna/context/validate | B/core/gridspace/private-protocol.ts | H S3/S4 | 全モードの日付・順序・cursor・認可を照合する |
| G12 | 投稿・ユーザーのコミュニティ検索、期間・人物条件、相手側可用性 | search.ts、search-info.ts、search-protocol.ts | H S3/S5 | 検索範囲と不可視投稿の扱いを保持し、障害を空検索結果にしない |
| G13 | 非公開添付取得・表示、文脈付きリンク | private-file.ts、private-protocol.ts、B/server/gridspace/GridSpaceServerService.ts | H S3/S4 | 本文・画像の永続キャッシュを避け、背景・取消時に破棄する |
| G14 | 非公開返信・引用とペアチャンネル投稿のprepare/send/status | private-reply.ts、channel-post.ts、F/utility/gridspace-reply-request.ts | H S3/S4 | request IDで再試行し二重投稿を防ぐ。expectedActorUriを照合する |
| G15 | ペア先への非公開添付アップロード | private-upload.ts、action-protocol.ts、F/components/MkGridspacePostForm.vue | W/H S2/S4 | 添付先アカウント、容量、属性、権限を保持し、ローカルDriveへ誤送信しない |
| G16 | 非公開投稿の反応・投票・複数リアクション | private-action.ts、action-protocol.ts | H S3/S4 | prepare・canInteract、追加・削除・一覧、既投票、revisionとactorを照合する |
| G17 | ペア投稿メニュー：お気に入り・クリップ・ミュート・ピン・削除・翻訳・通報 | F/utility/gridspace-note-menu.ts、B/core/gridspace/note-menu-protocol.ts | W/H S3/S4 | 全操作の状態・再認可・確認を維持し、source IDを通常APIへ渡さない |
| G18 | 自分の投稿・チャンネル投稿のRenote、公開ローカル表現への解決 | F/utility/gridspace-channel-renote.ts、renote-target.ts | H S3/S4 | 確定拒否と結果不明を区別し、同一request IDで結果を確認する |
| G19 | ペア通知の件数・一覧・既読・フォロー申請承認／却下 | F/utility/gridspace-notification-state.ts、notifications各API | H S3/S5/S6 | 自分・ペア・チャンネルの件数、障害時?、既読ACK、出典リンクを保持する |
| G20 | ペアチャンネルの注目・お気に入り・フォロー・所有・検索と操作 | B/core/gridspace/channel-protocol.ts、channels.ts、channel-update.ts | W/H S3/S5 | 検索、archive、sensitive、ownerとfollow/favorite状態を保持する |
| G21 | 所有チャンネル投稿の削除 | channel-delete.ts | W/H S3/S4 | 第一者認証・所有権・確認を守り、両表示を更新する |
| G22 | ペアPage・ギャラリー・クリップの新着・注目・人物・期間・詳細 | content.ts、content-protocol.ts、F/components/MkGridspaceContentList.vue | W/H S3/S5 | origin、paging、可視性を保持し、UGC表示と編集はWebを利用できる |
| G23 | 管理対象アンテナ・Page・クリップ・ギャラリーの参照・更新 | F/utility/gridspace-managed-api.ts、managed-resource.ts/protocol | W/H S3/S5 | 名前空間ID、alias重複除去、更新・削除・like・favorite・クリップ所属を保持する |
| G24 | ペアお気に入り・クリップお気に入り・コレクション操作 | collections.ts、F/utility/gridspace-managed-api.ts | W/H S3/S5 | 混合一覧、所有権、上限、既追加、元アカウントの権限を照合する |
| G25 | 従来方式のペアDrive一覧・ファイル・取り込み | drive.ts、drive-import.ts、F/components/MkGridspaceDrive.vue | W/H S2/S5 | フォルダ、paging、type、権限、メタデータ、取り込みの冪等性を確認する |
| G26 | 共有Drive、有効化後の準備・seed状態、ファイル／フォルダ操作、解除制限 | F/pages/settings/gridspace.vue、B/core/gridspace/GridspaceSharedDriveService.ts | W/H S2/S5 | driveShared/driveSeeded、共有中の解除不可、更新・削除・追加先を照合する |
| G27 | ペア所属表示、人物識別、利用不能表示 | member.ts、GridspaceIdentityService.ts、F/utility/is-unavailable-gridspace-note.ts | H S3/S4 | 出典と本人を誤表示せず、切替後に古い人物情報を再表示しない |
| G28 | 非公開データの背景移行・取消・再認可 | F/components/MkGridspacePrivateNotes.vue、utility/gridspace-note-suspension.ts | H S3/S4 | 本文・人物・添付を破棄し復帰時再認可。OSのアプリ切替画像も保護する |
| G29 | 管理者の連携状態・アカウント・ジョブ・再試行・Drive | F/pages/admin/gridspace.vue、B/server/api/endpoints/admin/gridspace/*.ts | W S1 | 第一者認証・管理者権限、絞り込み、詳細、回復操作を維持する |
| G30 | ローカル／リモートの登録期間・鍵・承認条件とペアへのフォロー展開 | F/pages/settings/privacy.vue、GridspaceFollowGuardService.ts | W/H S1/S5 | サーバーの承認判定を回避せず、申請と実フォローを区別する |
| G31 | 複数リアクションの配送・revision・pushと旧相手poll fallback | F/utility/extended-reactions.ts、GridspaceReactionService.ts、GridspaceReactionDeliveryService.ts | H S3/S4 | 古い更新を拒否し、復帰時に再取得。capabilityに応じて購読方式を選ぶ |

## GridSpace API全件

`B/server/api/endpoint-list.ts` に37件ある。ユーザー向け32件、管理者向け5件。「第一者限定」は `secure: true` または同等の個別制限を意味する。スコープがあるAPIでも、リンクの状態やサーバー側の認可を別途確認する。

| API | 認証上の条件・用途 |
|---|---|
| gridspace/member | 公開可能なペア所属情報 |
| gridspace/history | 公開可能な履歴。認証に応じた閲覧判定 |
| gridspace/search | 投稿・人物検索。認証に応じた閲覧判定 |
| gridspace/search-info | 検索対象originとcapability |
| gridspace/notifications | 第一者限定、通知一覧・件数 |
| gridspace/notifications/read | 第一者限定、既読操作 |
| gridspace/notifications/follow-request | 第一者限定、申請操作 |
| gridspace/private-grant | 第一者限定、許可管理 |
| gridspace/private-notes | read:gridspace-private |
| gridspace/private-file | read:gridspace-private |
| gridspace/private-reply | write:gridspace-reply |
| gridspace/private-upload | 第一者限定、添付受信 |
| gridspace/note-menu | 第一者限定、投稿メニュー |
| gridspace/private-action | 第一者限定、反応・投票 |
| gridspace/palette | 第一者限定、絵文字移入 |
| gridspace/profile-import | 第一者限定、プロフィール移入 |
| gridspace/collections | 第一者限定、コレクション参照 |
| gridspace/list-import | 第一者限定、リスト移入 |
| gridspace/play-import | 第一者限定、Play移入 |
| gridspace/renote-target | 第一者限定、Renote対象の解決 |
| gridspace/drive | 第一者限定、ペアDrive参照 |
| gridspace/drive-import | 第一者限定、ファイル移入 |
| gridspace/settings-import | 第一者限定、設定移入 |
| gridspace/layout-reference | 第一者限定、参照IDの移入先解決 |
| gridspace/channels | read:gridspace-private |
| gridspace/channel-post | write:gridspace-channel |
| gridspace/channel-delete | 第一者限定、所有投稿削除 |
| gridspace/channel-update | write:gridspace-channel |
| gridspace/link | 第一者限定、ペア連携 |
| gridspace/content | 公開可能なPage・ギャラリー・クリップ |
| gridspace/managed-resource | 第一者限定、write:account指定、管理対象リソース |
| gridspace/note-link | 匿名の公開解決は可能。認証済み閲覧は処理内でMiAccessTokenを拒否するため第一者限定 |
| admin/gridspace/status | 第一者＋管理者限定 |
| admin/gridspace/links | 第一者＋管理者限定 |
| admin/gridspace/jobs | 第一者＋管理者限定 |
| admin/gridspace/retry | 第一者＋管理者限定 |
| admin/gridspace/drive | 第一者＋管理者限定 |

## 共通実装の設計案

以下は追加実装の提案であり、既存仕様とは区別する。

1. 第一者トークンはWebの信頼する認証文脈に留める。URL・一般的なJSメッセージ・UGCへ書き出さない。ネイティブからの操作は第一者シェル内で許可した操作名と検証した引数に限定する。任意のエンドポイントを呼べるブリッジや `secure` の一括解除を採用しない。
2. 第一者認証を持つWebが扱う登録処理とAPNsの端末登録を、一度だけ使えるチャレンジで結び付ける案をS3で検証する。端末用の秘密はサーバーだけに保存する。新しいネイティブ専用認証方式が必要なら、別のプロトコル設計・認可レビューを行う。
3. origin・account・session generationを要求と応答へ付ける。アカウント切替中の旧応答を捨てる。WebViewのデータストアをアカウントごとに分けるか、停止中のシェルで切り替えるかを決める。
4. 投稿・人物・リソースIDをoriginと型で識別する。通常APIとペア代理APIを共通アダプターで振り分ける。未知の画面は第一者Webへ戻し、外部Webには特権メッセージを登録しない。
5. ネイティブとWebの状態更新を一つの処理に集約する。設定は既知の担当キーだけを更新し、未知のキーを保ったバージョン付きの形式で往復する。二重更新、古いクラウド値による上書き、同期のループを検出する。
6. 非公開の本文・添付は永続化せず、バックグラウンドへの移行・連携取消時に破棄する。iOSのアプリ切替画面に使われる画像も保護する。復帰時は再認可してから描画する。
7. 写真選択を置き換える際は、既存アップローダーの入力仕様を維持する。通常のDriveと非公開ペアアップロードを区別し、編集・透かし・圧縮・説明・センシティブ属性を保つ。
8. ストリームと通知は別の処理として扱う。フォアグラウンドでは購読・再接続、バックグラウンドではAPNsを使う。Web PushのままiOSネイティブ通知に対応したとは数えない。

## 検証の組み合わせと未確認事項

S0で確認項目を固定し、S6までに実機での結果を記録する。未ログイン／第一者／MiAuth、ローカル／ペア／移行済み／取消済み、相手正常／不在／権限不足、Wi-Fi／携帯回線／機内モード／タイムアウトを組み合わせる。起動・画面復帰・Webプロセスの再生成・強制終了・ストレージ不足・権限取消・アカウント切替中の応答を確認する。写真への限定アクセス、外部キーボード、文字拡大、VoiceOver、Reduce Motionも含む。

以下の項目は未確認のため、実装開始時に確定する。

- 最低対応iOSバージョンと検証する端末の組み合わせ。WKWebViewでのWebAuthn、Service Worker、各メディア形式、ダウンロード、権限・保存動作は未検証。
- 稼働中サーバーのmanifest上書き・capability・ロール設定。ソース上の機能を列挙したのであり、全利用者で有効と確認したものではない。
- 第一者Webホストと限定ブリッジの具体的な認可・メッセージ形式、APNs端末登録のチャレンジ。上記は提案段階である。
- App StoreのUGC・プラグイン条件への適合。WebView利用だけで配布可能と断定しない。
- この付録はP01–P35とG01–G31の機能群を対象とする。全ルート・ウィジェット・設定の網羅率は別表と機械的に突き合わせる。
