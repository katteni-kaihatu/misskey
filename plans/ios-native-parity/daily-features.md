# 日常操作の機能一覧と移行条件

調査基準: `C:/Users/neo/GitHub/grid-space-misskey`、コミット `f1bd2e3c4bebf931be8c49342691f03e3cdeb49b`、2026-11-15 JST。ソースの読み取りによる調査であり、実機・ブラウザ・本番サーバーで動作を確認した結果ではない。対象は日常操作とし、ルート、管理画面、設定、ウィジェット、UGC実行環境の一覧は別表で補う。

全行の初期方式は W（アプリ内の既存Web画面）。N はネイティブ、H はネイティブとWebの併用を表す。目標方式は実装案であり、完了を示さない。受入条件を満たすまでは既存Web画面を利用可能にする。写真選択の改善はS2、UGC共通実行環境はS3、日常操作はS4、ソーシャル・整理機能はS5、全体の受入はS6を想定する。S3と記載した項目は、UGCの互換性を確認してからネイティブへ移行する。全行をS6でも回帰確認する。

認証は各APIの `secure` 属性を調べ、必要な資格情報を使う。MiAuthだけで全機能を利用できるとは仮定しない。ローカル・連携先のリソースIDと実行アカウントを混同しない。書き込みのタイムアウトは結果不明として扱い、`notes/create` などを自動再送しない。

## 根拠ファイル

略号のパスは、特記がなければ `packages/frontend/src/` 配下。移植時は列挙したファイル全体と呼び出し先を読み直す。

| 略号 | パス |
|---|---|
| TL | `timelines.ts:9`、`pages/timeline.vue:7`、`components/MkStreamingNotesTimeline.vue:109`、`components/MkRlRelaySocialTimeline.vue` |
| TLP | `components/MkNotesTimeline.vue:7`、`components/MkNoteListLayout.vue:7`、`utility/paginator.ts` |
| HOME | `utility/use-gridspace-home.ts:19`、`utility/gridspace-home-merge.ts`、`utility/gridspace-note-suspension.ts` |
| NOTE | `components/MkNote.vue:7`、`components/MkNoteDetailed.vue:7`、`composables/use-note.ts:96` |
| MENU | `utility/get-note-menu.ts:35`、`utility/get-user-menu.ts:23`、`utility/gridspace-note-menu.ts:25` |
| MFM | `packages/frontend-shared/js/mfm-renderer.ts:132`、`components/MkNoteText.vue:7` |
| REACT | `utility/extended-reactions.ts:10`、`composables/use-note-capture.ts`、`components/MkReactionsViewer.vue`、`utility/reaction-picker.ts` |
| FORM | `components/MkPostForm.vue:183`、`components/MkPostFormActionBar.vue:7`、`components/MkPostFormAttaches.vue`、`components/MkPollEditor.vue:7` |
| UP | `composables/use-uploader.ts:23`、`utility/drive.ts`、`os.ts:724` |
| DRAFT | `components/MkNoteDraftsDialog.vue:7`、`components/MkPostForm.vue:234` |
| MEDIA | `components/MkMediaList.vue:7`、`components/MkMediaImage.vue`、`components/MkMediaAudio.vue`、`components/MkMediaVideo.vue`、`components/MkLightbox.item.vue`、`components/MkLightbox.item.controls.vue`、`components/MkLightbox.item.fileinfo.vue` |
| 3D | `components/MkMedia3d.vue:7`、`utility/three-d-file.ts:8`、`utility/three-d-viewer.ts:40` |
| TRANS | `components/MkAutoTranslatedNote.vue:7`、`utility/auto-translation.ts`、`utility/get-note-menu.ts:285` |
| GFORM | `components/MkGridspacePostForm.vue:7`、`utility/gridspace-reply-request.ts:7`、`utility/gridspace-post.ts` |
| GNOTE | `components/MkGridspacePrivateNote.vue:7`、`components/MkGridspaceNoteActions.vue:7`、`components/MkGridspacePrivateNoteRow.vue` |
| DRIVE | `components/MkDrive.vue:7`、`utility/get-drive-file-menu.ts:18`、`pages/drive.file.info.vue:7`、`pages/drive.file.notes.vue` |
| GDRIVE | `components/MkGridspaceDrive.vue`、`components/MkDrive.vue:224` |
| GALLERY | `pages/gallery/index.vue:7`、`pages/gallery/post.vue:7`、`pages/gallery/edit.root.vue:7` |
| NOTIFY | `pages/notifications.vue:7`、`components/MkStreamingNotificationsTimeline.vue:7`、`components/MkNotification.vue`、`packages/misskey-js/src/consts.ts:19` |
| GNOTIFY | `utility/use-gridspace-notifications.ts:19`、`utility/gridspace-notification-state.ts`、`components/MkGridspaceNotifications.vue` |
| SEARCH | `pages/search.vue:7`、`pages/search.note.vue:7`、`pages/search.user.vue:7`、`pages/search.community.vue:7` |
| USER | `pages/user/index.vue:7`、`pages/user/home.vue:7`、`pages/user/notes.vue`、`pages/user/files.vue`、`pages/user/following.vue`、`pages/user/followers.vue`、`components/MkFollowButton.vue:7`、`pages/follow-requests.vue:7` |
| COLLECTION | `pages/my-lists/list.vue:7`、`pages/my-lists/index.vue`、`components/MkAntennaEditor.vue:7`、`pages/my-antennas/`、`pages/my-clips/index.vue`、`pages/clip.vue:7`、`pages/favorites.vue` |
| CHANNEL | `pages/channels.vue:7`、`pages/channel.vue:7`、`pages/channel-editor.vue:7`、`pages/gridspace-channels.vue`、`components/MkCombinedChannelList.vue` |
| CHAT | `pages/chat/home.vue:7`、`pages/chat/home.home.vue`、`pages/chat/home.invitations.vue`、`pages/chat/home.joiningRooms.vue`、`pages/chat/home.ownedRooms.vue`、`pages/chat/room.vue:7`、`pages/chat/room.form.vue:7`、`pages/chat/room.members.vue`、`pages/chat/room.info.vue`、`pages/chat/room.search.vue`、`pages/chat/XMessage.vue:7` |
| EXPLORE | `pages/explore.vue:7`、`pages/explore.featured.vue:7`、`pages/explore.users.vue:7`、`pages/explore.roles.vue` |
| NEOS | `pages/neos/direct-upload.vue:7` |

## タイムライン

| ID | 機能・範囲 | 根拠 | 初期→目標 / 段階 | 受入条件 |
|---|---|---|---|---|
| D-TL-01 | ホーム | TL, HOME | W→N / S4 | 閲覧可能な投稿と順序が一致。通常APIだけで連携先の限定投稿を落とさない |
| D-TL-02 | ローカル | TL | W→N / S4 | アカウント・サーバーのltlAvailableに従う |
| D-TL-03 | ソーシャル | TL | W→N / S4 | ログイン・LTL条件と返信・ファイル絞り込みが一致 |
| D-TL-04 | グローバル | TL | W→N / S4 | gtlAvailableと未ログイン時の公開範囲が一致 |
| D-TL-05 | RLリレー | TL | W→N / S4 | クライアント側の参加ホスト絞り込みを再現 |
| D-TL-06 | RLリレーソーシャル | TL | W→N / S4 | 投稿集合と結合順が一致。VRTLとは別に確認 |
| D-TL-07 | VRTL | TL | W→N / S4 | vrtlAvailable、withLocalOnly、ページ送りが一致 |
| D-TL-08 | VSTL | TL | W→N / S4 | ログイン条件、返信などのフィルターが一致 |
| D-TL-09 | リストTL・固定リストタブ | TL, COLLECTION | W→N / S4 | リストIDとメンバーごとの返信表示設定を維持 |
| D-TL-10 | アンテナTL | TL, COLLECTION | W→N / S4 | 未読・条件・ページ送り・投稿除外を維持 |
| D-TL-11 | チャンネルTL | TL, CHANNEL | W→N / S4 | ローカル・連携先ID、未読、アーカイブ状態を維持 |
| D-TL-12 | ロールTL | TL | W→N / S4 | ロールIDと閲覧権限を維持 |
| D-TL-13 | メンション・ダイレクトノートTL | NOTIFY | W→N / S4 | チャットと区別し、連携先・限定投稿も表示 |
| D-TL-14 | 未ログインTL閲覧 | TL | W→N / S4 | ローカル・グローバル・VRTLの許可範囲と操作制限を維持 |
| D-TL-15 | リノート表示切替 | TL | W→N / S4 | 保存設定と取得結果が一致 |
| D-TL-16 | 返信表示・ファイルのみの排他 | TL | W→N / S4 | 対象TLで同時指定を防ぎ、切替時のページ送りを正常化 |
| D-TL-17 | センシティブ・連合なし表示 | TL | W→N / S4 | メディア・チャンネル・リレー固有条件を混同しない |
| D-TL-18 | 固定投稿欄・リスト等の選択 | TL | W→H / S4 | 設定、アカウント、未送信の内容を維持 |
| D-TL-19 | リアルタイム・定期取得・間隔・音 | TL, REACT | W→N / S4 | 復帰時に補完し、接続重複や非表示中の不要取得を防ぐ |
| D-TL-20 | 閲覧中の新着保留 | TLP | W→N / S4 | 位置を動かさず、ボタン・先頭移動で新着を反映 |
| D-TL-21 | 更新・追加読込・無限スクロール | TLP | W→N / S4 | 自動取得無効時も操作可能。空・失敗・終端を区別 |
| D-TL-22 | 日付区切り・投稿間隔 | TLP | W→N / S4 | タイムゾーンと順序、表示設定の意図を維持 |
| D-TL-23 | 広告挿入枠 | TLP | W→H / S4 | 現在の配信内容・操作を無断で欠落させない |
| D-TL-24 | 通常投稿と連携限定投稿の統合 | HOME | W→H→N / S4 | 日時・カーソル境界、認可、連携先障害を再現 |
| D-TL-25 | 限定本文の非表示・再認可 | HOME, GNOTE | W→N / S4 | 非表示・失効・ログアウトで本文とメディアを破棄し、再認可 |

## 投稿表示と操作

| ID | 機能・範囲 | 根拠 | 初期→目標 / 段階 | 受入条件 |
|---|---|---|---|---|
| D-NT-01 | 投稿者・アイコン・所属・日時・公開範囲 | NOTE | W→N / S4 | リノート者と投稿者、ホスト、装飾、各状態を識別 |
| D-NT-02 | 返信元・会話の前後・子投稿 | NOTE | W→N / S4 | 削除・非公開・欠損した親も扱い、会話位置を維持 |
| D-NT-03 | リノート表示・折畳み・参照先欠損 | NOTE | W→N / S4 | 投稿者とリノート者、展開操作が一致 |
| D-NT-04 | 入れ子の引用 | NOTE, GNOTE | W→H→N / S4 | CW・限定認可と深さの制限を維持 |
| D-NT-05 | CW・長文の開閉 | NOTE | W→N / S4 | 開くまで限定本文・メディア・翻訳を不要に処理しない |
| D-NT-06 | 非公開・削除・閲覧不可の表示 | NOTE, GNOTE | W→N / S4 | 古い限定本文を通常投稿としてキャッシュ表示しない |
| D-NT-07 | ソフト・ハードワードミュート | NOTE | W→N / S4 | 理由・手動表示・センシティブ条件を維持 |
| D-NT-08 | プラグインによる表示加工・非表示 | NOTE, plugin.ts | W→H / S3,S4 | 元の順序で実行。nullで非表示、例外時の挙動も確認 |
| D-NT-09 | MFM基本文字装飾・引用・中央寄せ | MFM | W→N / S4 | 入れ子・改行・選択・読み上げの比較資料に合格 |
| D-NT-10 | MFMリンク・メンション・タグ・検索 | MFM | W→N / S4 | エスケープ、リモート解決、遷移先を維持 |
| D-NT-11 | コードブロック・インラインコード | MFM | W→H→N / S4 | 空白・コピー・言語別色付けを確認 |
| D-NT-12 | 行内・独立数式 | MFM | W→W/H / S3 | 数式表示を維持。未対応時に単なる文字列へ落とさない |
| D-NT-13 | カスタム・Unicode絵文字と操作 | MFM, REACT | W→N / S4 | URL・名前・欠損・アニメーション抑制・コピー・リアクション |
| D-NT-14 | tada,jelly,twitch,shake,spin,jump,bounce,rainbow,sparkle | MFM | W→H→N / S4 | 関数引数・入れ子・動きを減らす設定が一致 |
| D-NT-15 | flip,x2,x3,x4,font,blur,rotate,position,scale,fg,bg,border,ruby,unixtime,clickable | MFM | W→H→N / S3,S4 | 全分岐と引数を比較。clickableのスクリプト連携も維持 |
| D-NT-16 | 猫語変換 | MFM | W→N / S4 | 投稿者属性と設定を維持し、コピー原文を改変しない |
| D-NT-17 | URLプレビュー・外部埋込 | NOTE | W→H / S4 | CW・設定・外部サービス失敗の代替表示 |
| D-NT-18 | いいねのみ・通常リアクション | NOTE, REACT | W→N / S4 | 受入制限と既存リアクションの置換規則 |
| D-NT-19 | 複数リアクション | REACT | W→N / S4 | myReactions、件数、revision/version、16表示と全件詳細 |
| D-NT-20 | リアクション検索・履歴・お気に入り | REACT | W→N / S4 | リモート絵文字・削除・センシティブ権限・パレット |
| D-NT-21 | リアクション者・リノート者一覧 | NOTE, REACT | W→N / S4 | 種類別ページ送り・版更新・同一投稿の表示同期 |
| D-NT-22 | 返信・リノート・引用・チャンネル引用 | MENU | W→N / S4 | アカウント、チャンネル、公開範囲、連合なし、所有権 |
| D-NT-23 | 投票・複数回答・結果・期限 | NOTE | W→N / S4 | 投票済み状態、期限、確認、代理操作を維持 |
| D-NT-24 | 常時翻訳・原文切替・再試行 | TRANS | W→N / S4 | 表示中・認可済みだけ実行。言語・古い応答を管理 |
| D-NT-25 | 手動翻訳 | MENU, GNOTE | W→N / S4 | 利用権限、元言語、限定投稿の通信経路 |
| D-NT-26 | 本文・URL・IDコピー、共有 | MENU | W→N / S4 | 正規URL・連携URLと共有してよい本文を選ぶ |
| D-NT-27 | 埋込コード生成 | MENU | W→W / S1 | 生成・コピー画面を利用可能にする |
| D-NT-28 | お気に入り・クリップ・スレッドミュート | MENU | W→N / S4 | 上限・状態・エラーと連携先クリップIDを維持 |
| D-NT-29 | 自分の投稿・チャンネルのピン留め | MENU | W→N / S4 | 所有者・権限・上限、サーバー確定後の状態 |
| D-NT-30 | 削除・削除して編集 | MENU | W→N / S4 | 現行は削除後に作り直す操作。未実装の直接編集と混同しない |
| D-NT-31 | アンテナから一時除外・通報 | MENU | W→N / S4 | 除外期間、確認、通報内容 |
| D-NT-32 | ユーザーメニュー・プラグイン操作 | MENU | W→H / S3,S4 | 登録操作をすべて呼べ、失敗を確認可能 |
| D-NT-33 | キーボード操作・メニュー・選択 | NOTE | W→N / S4 | iPadキー操作と長押し、本文選択が競合しない |
| D-NT-34 | 連携先のリアクション・投票 | GNOTE | W→H→N / S4 | prepare・expectedActorUri・再認可。ローカルIDと混同しない |
| D-NT-35 | 限定投稿の各種メニュー | MENU | W→H→N / S4 | 実行主体・認可・お気に入り・クリップ・削除などを維持 |

## 投稿フォーム・下書き・アップロード

| ID | 機能・範囲 | 根拠 | 初期→目標 / 段階 | 受入条件 |
|---|---|---|---|---|
| D-CP-01 | テキスト・日本語変換・選択 | FORM | W→N / S4 | 再変換、絵文字、選択位置を写真選択・回転後も維持 |
| D-CP-02 | 返信・引用の対象表示と解除 | FORM | W→N / S4 | 宛先・公開範囲・連携引用解決を維持 |
| D-CP-03 | 本文・CWの文字数制限とカウンター | FORM | W→N / S4 | サーバー本文上限、CW100字、未確定入力の扱い |
| D-CP-04 | 公開・ホーム・フォロワー・指定宛先 | FORM | W→N / S4 | 既定値・記憶設定、意図せぬ公開範囲拡大を防ぐ |
| D-CP-05 | 指定宛先の追加・削除 | FORM | W→N / S4 | 完全なアカウントIDと未指定メンションの扱い |
| D-CP-06 | 連合なし・設定記憶・初回警告 | FORM | W→N / S4 | チャンネル・指定宛先時の既存送信規則 |
| D-CP-07 | 別アカウントとして投稿 | FORM | W→H→N / S4 | 資格情報、上限、下書き、ファイル所有者を分離 |
| D-CP-08 | リアクション受入設定5種類 | FORM | W→N / S4 | null、いいね、リモート、センシティブの条件 |
| D-CP-09 | メンション・タグ・絵文字補完 | FORM | W→N / S4 | 入力位置、トリガー、履歴、リモート、日本語変換 |
| D-CP-10 | MFM簡易挿入・プレビュー | FORM | W→H→N / S4 | 全選択肢と表示結果の一致 |
| D-CP-11 | ハッシュタグ欄と入力履歴 | FORM | W→N / S4 | 本文末への追加方法・改行・保存状態 |
| D-CP-12 | プラグインの投稿欄操作・送信前処理 | FORM, plugin.ts | W→H / S3,S4 | ハンドラー順、フォーム変更、最終送信内容 |
| D-CP-13 | 迷惑になりうる公開投稿の確認 | FORM | W→N / S4 | 続行・中止・ホーム変更の選択肢を維持 |
| D-CP-14 | 写真・ファイル選択 | FORM, UP | W→H→N / S2,S4 | 名前・形式・メタデータ・順序・上限・キャンセル |
| D-CP-15 | ドライブ・連携ドライブから添付 | FORM, DRIVE, GDRIVE | W→H→N / S4 | 所有権、取り込み、センシティブ条件、ID区分 |
| D-CP-16 | 画像・ファイル・ドライブ項目の貼付とドロップ | FORM, UP | W→N / S4 | iPad操作、名前、失敗・キャンセルを維持 |
| D-CP-17 | 連携投稿URLの貼付による引用 | FORM | W→H→N / S4 | URL解決、入力との競合、画面移動・非表示時の失効 |
| D-CP-18 | 添付並べ替え・削除・名前・センシティブ・説明 | FORM, UP | W→N / S4 | 送信順と未送信・送信済みファイルの属性 |
| D-CP-19 | 画像の切抜き・リサイズ | UP | W→H / S2 | 形式・向き・出力画像を確認するまではWeb処理 |
| D-CP-20 | 画像エフェクト | UP | W→W/H / S2 | 既存の全設定と出力を残す |
| D-CP-21 | 透かしプリセット・複数レイヤー編集 | UP | W→W/H / S2 | 文字・画像・QR・縞・水玉・市松、既定値・利用権限 |
| D-CP-22 | フレームプリセット・編集 | UP | W→W/H / S2 | 説明・日付・アカウント情報と合成結果 |
| D-CP-23 | 画像圧縮なし・低・中・高 | UP | W→H→N / S2,S4 | サイズ・品質・対象形式、アニメーション除外 |
| D-CP-24 | 動画圧縮なし・低・中・高 | UP | W→H→N / S2,S4 | mediabunnyでの実処理あり。形式・ビットレート・長さ・音声 |
| D-CP-25 | 前処理・送信の進捗、中止、再試行 | UP | W→H/N / S2 | 一時ファイル漏れ・重複送信・画面停止を防ぐ |
| D-CP-26 | 順次アップロード後の投稿 | FORM, UP | W→N / S4 | 部分失敗時に下書きと完了済みファイルを維持 |
| D-CP-27 | ローカル自動下書き | DRAFT, FORM | W→N / S4 | アカウント・返信・引用・チャンネル別、明示移行と復元 |
| D-CP-28 | サーバー下書きの保存・一覧・件数・復元・変更・削除 | DRAFT | W→H→N / S4 | secure認証、全フィールド、利用上限 |
| D-CP-29 | 予約投稿・一覧・解除 | DRAFT, FORM | W→H→N / S4 | サーバー日時・状態・失敗通知。予約再設定UIは現状コメントアウト |
| D-CP-30 | リセット・キャンセル確認とキー送信 | FORM | W→N / S4 | 未保存内容を無断で消さず、変換確定Enterで送信しない |
| D-CP-31 | 投稿成功後のイベント・表示更新・実績 | FORM | W→H/N / S4 | 成功確認後にだけ下書きを消し、既存の副作用も維持 |
| D-CP-32 | 通常投稿の結果不明タイムアウト | FORM | W→N / S4 | notes/createを自動再送せず、未確定状態と内容を残す |
| D-CP-33 | 連携先への返信・チャンネル投稿 | GFORM | W→H→N / S4 | 実行アカウント、宛先、認可、投票・CW・添付・上限 |
| D-CP-34 | 連携先投稿の再試行・破棄 | GFORM | W→N / S4 | 既存UUIDの操作意味を維持。限定本文を永続化しない |
| D-CP-35 | 連携投稿の内容転送・権限失効・非表示 | GFORM | W→H→N / S4 | 世代番号・中止・主体確認。失効時に本文を消し再認可 |
| D-CP-36 | Neos外部直接投稿 | NEOS | W→W / S1 | URL・完了マーカー・終了を維持。localOnly等の未適用は既存挙動として記録 |

## メディアとドライブ

| ID | 機能・範囲 | 根拠 | 初期→目標 / 段階 | 受入条件 |
|---|---|---|---|---|
| D-MD-01 | 画像一覧・単一画像の縦横比設定 | MEDIA | W→N / S4 | 1〜複数件レイアウト、位置変動とセンシティブ表示 |
| D-MD-02 | サムネイル・原寸の遅延読込、blurhash、代替説明 | MEDIA | W→N / S4 | 非表示設定・失敗・読込中、読み上げ |
| D-MD-03 | 全画面スワイプ・移動・拡大・閉じる | MEDIA | W→N / S4 | 元画面の位置、表示領域、回転、iPadを確認 |
| D-MD-04 | ピクセル表示・ファイル情報・再非表示 | MEDIA | W→H/N / S4 | 補助操作・説明も省かない |
| D-MD-05 | 音声・動画のインライン・全画面再生 | MEDIA | W→H/N / S4 | 再生・シーク・音量・消音・待機・ループ・0.25〜2倍・利用可能なPiP |
| D-MD-06 | 標準/独自プレーヤー・音声可視化 | MEDIA | W→H / S4 | Webの独自表示を残し、音声と画面寿命を管理 |
| D-MD-07 | その他添付の表示・ダウンロード | MEDIA | W→H/N / S4 | 名前・種類・説明・認可、Files/共有の受渡 |
| D-MD-08 | 3Dモデル・Gaussian Splat表示 | 3D | W→W/H / S3 | fbx/glb/gltf/obj/stl/ply/spz/splat/ksplat/sog/rad、読込・再試行・終了・保存・センシティブ |
| D-MD-09 | 限定メディアの取得と失効 | GNOTE, MEDIA | W→H/N / S4 | 認可Blobをメモリ内で保持し、失効・非表示でビューアとURLを破棄 |
| D-MD-10 | 3D回転・移動・ズーム・アニメーション・プレビュー落下 | 3D | W→W/H / S3 | WebGL/Spark、キャプチャ・落下・GPU解放を実機確認 |
| D-DR-01 | フォルダー階層・パンくず・ルート | DRIVE | W→H→N / S5 | パス、位置、フォルダー選択モード |
| D-DR-02 | 単数/複数選択・形式/センシティブ絞込 | DRIVE | W→H→N / S5 | 選択順・禁止項目・キャンセル、各フォームからの利用 |
| D-DR-03 | 日付・サイズ・名前の昇順/降順 | DRIVE | W→N / S5 | APIの符号と日付順での月別表示 |
| D-DR-04 | フォルダー作成・名前・移動・削除 | DRIVE | W→H→N / S5 | 循環参照、子要素、権限エラー |
| D-DR-05 | ファイル一括移動・フォルダーへドロップ | DRIVE | W→H→N / S5 | 複数選択とタッチでの代替操作 |
| D-DR-06 | 端末・貼付・ドロップでアップロード | DRIVE, UP | W→H→N / S2,S5 | 画像処理とアップロード先フォルダー設定 |
| D-DR-07 | URLからアップロード | DRIVE | W→W/H / S5 | 完了マーカー・待機・エラー、重複再試行防止 |
| D-DR-08 | ファイル名・説明・センシティブ・削除 | DRIVE | W→N / S5 | 削除確認とサーバー確定状態 |
| D-DR-09 | ファイル詳細と添付投稿一覧 | DRIVE | W→N / S5 | 所有者向け情報、投稿の閲覧権限 |
| D-DR-10 | URL/IDコピー・保存・ファイルから投稿 | DRIVE | W→N / S5 | アカウント、名前、受渡内容 |
| D-DR-11 | ドライブのリアルタイム更新 | DRIVE | W→N / S5 | 現フォルダーの作成・更新・削除と再接続 |
| D-DR-12 | 連携先ドライブ・取り込み | GDRIVE | W→H→N / S5 | 利用不可と空を区別。出所IDと取り込み規則 |

## 検索・プロフィール・コレクション

| ID | 機能・範囲 | 根拠 | 初期→目標 / 段階 | 受入条件 |
|---|---|---|---|---|
| D-SR-01 | 投稿検索とページ送り | SEARCH | W→N / S5 | 検索構文・利用可否・失敗表示を維持 |
| D-SR-02 | 日時と全体/ローカル/サーバー/ユーザー範囲 | SEARCH | W→N / S5 | アカウント・連合ポリシー、ホスト・本人指定 |
| D-SR-03 | ぐりすぺ両コミュニティ検索 | SEARCH | W→H→N / S5 | 無効カーソル・履歴変更・部分結果表示と連携ID |
| D-SR-04 | ユーザー検索 | SEARCH | W→N / S5 | ローカル・リモート・両方、Unicodeアカウント、ページ送り |
| D-SR-05 | APオブジェクト・URL・アカウント・タグ照会 | SEARCH | W→N / S5 | 外部取得前の確認と正しい詳細遷移 |
| D-SR-06 | みつける: 人気投稿・おすすめ投票 | EXPLORE | W→N / S5 | 並び順、おすすめ投票のチャンネル除外 |
| D-SR-07 | ローカル/リモートのユーザーとタグ探索 | EXPLORE | W→N / S5 | 固定・人気・更新・新規登録・発見済の区別 |
| D-SR-08 | ロールとメンバー探索 | EXPLORE | W→N / S5 | 閲覧権限とロールTLへの遷移 |
| D-US-01 | プロフィールのバナー・説明・フィールド・挨拶 | USER | W→H/N / S5 | MFM・絵文字・リンク検証・折畳み |
| D-US-02 | 引越し・リモート注意・鍵・bot・システム表示 | USER | W→N / S5 | 各状態と移動先アカウントを維持 |
| D-US-03 | 投稿/ファイル/活動/実績/反応/クリップ/リスト/Pages/Play/ギャラリー/rawタブ | USER | W→H / S5 | 全タブ利用可能。グラフ・raw・UGCはWebを維持 |
| D-US-04 | フォロー・解除・申請・申請取消 | USER | W→N / S5 | ローカル/リモート待機、鍵、確認と状態更新 |
| D-US-05 | 受信・送信フォロー申請 | USER | W→N / S5 | 承認・拒否・取消、現在の関係表示 |
| D-US-06 | フォロー・フォロワー一覧 | USER | W→N / S5 | 公開設定とページ送り、非公開の関係を推測表示しない |
| D-US-07 | 投稿通知・返信表示の相手別設定 | MENU | W→N / S5 | フォロー設定の保存と効果 |
| D-US-08 | 期限付きミュート・リノートミュート・ブロック | MENU | W→N / S5 | 無期限/10分/1時間/1日/1週、確認と表示抑制 |
| D-US-09 | 被フォロー解除・通報・外部情報更新 | MENU | W→H/N / S5 | 権限・確認・通報内容 |
| D-US-10 | 非公開メモ・リスト/アンテナ追加 | MENU, USER | W→N / S5 | メモの非公開性と登録対象 |
| D-US-11 | 名前/URL/RSS/IDコピー・QR・外部・埋込 | MENU | W→H/N / S5 | 出所と正規URL、クリップボード・書出し |
| D-US-12 | ダイレクトノート・チャット・プラグイン操作 | MENU | W→H→N / S3,S5 | 別の操作として保持し、拡張の登録操作も呼ぶ |
| D-CO-01 | リスト作成・表示・編集・削除・公開設定 | COLLECTION | W→N / S5 | 利用上限と出所に応じた管理API |
| D-CO-02 | リストのメンバーと返信設定 | COLLECTION | W→N / S5 | 正しいID、重複、人数制限 |
| D-CO-03 | アンテナ作成・表示・編集・削除 | COLLECTION | W→N / S5 | AND/ORキーワード・除外・ユーザー・bot・返信・ローカル・添付・大小文字・センシティブチャンネル |
| D-CO-04 | 保存済みアンテナの旧ソース指定 | COLLECTION | W→N / S5 | 作成UIでは隠れたlistソース等を勝手に削除しない |
| D-CO-05 | お気に入り投稿 | COLLECTION | W→N / S5 | ローカル・連携・限定と失効処理 |
| D-CO-06 | クリップ作成・編集・削除・公開設定 | COLLECTION | W→N / S5 | 名前・説明・上限・連携先の管理ID |
| D-CO-07 | クリップ内投稿操作・お気に入り・共有・埋込 | COLLECTION, MENU | W→H→N / S5 | 実行主体、件数、正規URL |
| D-CO-08 | 連携コレクションの部分表示・利用不可 | COLLECTION | W→H→N / S5 | 障害・失効を削除や空として扱わない |
| D-CH-01 | チャンネルの人気/お気に入り/フォロー/所有/検索 | CHANNEL | W→N / S5 | 名前のみ/説明含む検索、連携先を含む一覧 |
| D-CH-02 | チャンネル概要・固定投稿・人気・TL・検索 | CHANNEL | W→H→N / S5 | アーカイブ状態と固定投稿欄設定 |
| D-CH-03 | チャンネルのフォロー・お気に入り・ミュート・未読 | CHANNEL | W→N / S5 | 期限と通知状態 |
| D-CH-04 | チャンネル作成・編集・アーカイブ | CHANNEL | W→W / S1 | 名前・MFM説明・色・センシティブ・外部リノート・バナー・固定順 |
| D-CH-05 | 連携チャンネルの閲覧・投稿・管理 | CHANNEL, GFORM, GNOTE | W→H→N / S5 | 実行主体、認可、限定メディアとexpectedActorUri |
| D-GA-01 | ギャラリーの探索/新着/人気/いいね/自分 | GALLERY | W→N / S5 | 取得範囲と連携先の利用状態 |
| D-GA-02 | ギャラリー詳細・いいね・共有・通報 | GALLERY | W→H→N / S5 | センシティブ、確定件数、連携先の対象とURL |
| D-GA-03 | ギャラリー作成・編集・削除・添付順・センシティブ | GALLERY | W→W / S1 | 画像編集機能、出所の管理画面、所有権と確認 |

## 通知とチャット

| ID | 機能・範囲 | 根拠 | 初期→目標 / 段階 | 受入条件 |
|---|---|---|---|---|
| D-NF-01 | 全通知・メンション・ダイレクトノート | NOTIFY | W→N / S4 | 連携・限定を含み、チャットと区別 |
| D-NF-02 | 全通知種別 | NOTIFY | W→N / S4 | note/follow/mention/reply/renote/quote/reaction/pollEnded/scheduledNotePosted/scheduledNotePostFailed/receiveFollowRequest/followRequestAccepted/app/roleAssigned/chatRoomInvitationReceived/achievementEarned/exportCompleted/test/login/createToken |
| D-NF-03 | 種別絞込・解除 | NOTIFY | W→N / S4 | 含む/除くを一致させ、未閲覧を誤って既読化しない |
| D-NF-04 | リアクション・リノートのグループ化 | NOTIFY, GNOTIFY | W→N / S4 | 実行者・件数・出所と既読状態 |
| D-NF-05 | 既読・全既読・未読バッジ | NOTIFY, GNOTIFY | W→N / S4 | 出所別件数と世代競合、Webとの同期 |
| D-NF-06 | リアルタイム・再接続・追加読込・失敗 | NOTIFY | W→N / S4 | 取り逃し補完と重複通知/既読処理防止 |
| D-NF-07 | ローカル・連携先・チャンネル通知統合 | GNOTIFY | W→H→N / S4 | カーソル境界、部分障害と失効 |
| D-NF-08 | APNs経由の詳細遷移・バッジ | NOTIFY、基盤調査 | W→N / S4 | Web Push移植とは別実装。該当項目・ロック画面の情報量 |
| D-CT-01 | 履歴・個別チャット開始・部屋作成 | CHAT | W→N / S5 | available/readonly/unavailableと相手の許可範囲 |
| D-CT-02 | 所有部屋・参加部屋・招待 | CHAT | W→N / S5 | 承認・無視、招待限定の情報を漏らさない |
| D-CT-03 | 入室・退出・ユーザー招待 | CHAT | W→N / S5 | 所有者/参加者権限、ローカルユーザー制限、確認 |
| D-CT-04 | 部屋名・説明・削除・ミュート | CHAT | W→N / S5 | 所有者/管理/モデレーターとミュート状態 |
| D-CT-05 | メンバー・送信済み招待と管理 | CHAT | W→N / S5 | 許可される操作と取消・拒否状態 |
| D-CT-06 | 個別/部屋メッセージTL・過去履歴 | CHAT | W→N / S5 | 日付・順序・末尾位置・新着印・キーボード回避 |
| D-CT-07 | メッセージMFM・URL・添付 | CHAT, MFM, MEDIA | W→H→N / S5 | 投稿と同じ文字・メディア比較資料に合格 |
| D-CT-08 | 文字・1添付の送信と各入力元 | CHAT | W→H→N / S2,S5 | 1ファイル制限、画像処理、権限、認証 |
| D-CT-09 | 絵文字・Enter設定・ローカル下書き | CHAT | W→N / S5 | 変換中送信を防ぎ、相手/部屋/アカウント別に保存 |
| D-CT-10 | メッセージのリアクション・取消 | CHAT | W→N / S5 | ユーザーと反応の組、イベント同期、重複防止 |
| D-CT-11 | コピー・自分の削除・相手の通報 | CHAT | W→N / S5 | 権限・詳細リンク、偽の成功表示を防ぐ |
| D-CT-12 | 全体/会話内検索・詳細リンク | CHAT | W→N / S5 | 正しい会話位置と閲覧権限 |
| D-CT-13 | 既読・受信・削除・反応のリアルタイム更新 | CHAT | W→N / S5 | 表示中会話のみ既読、復帰時の補完 |
| D-CT-14 | 通知・効果音・送信者名表示 | CHAT, NOTIFY | W→H/N / S5 | 設定と既読競合を維持 |

## 移植時に維持する条件

1. `useGridspaceHome`は通常投稿と認可された限定投稿を結合する。`notes/timeline`だけを使ったホームでは機能が不足する。日時・カーソル境界の扱いと、非表示時に限定投稿の本文を破棄する処理を移植する。
2. `MkGridspacePostForm`には別の実行主体、認可、保留UUID、再試行・破棄がある。通常投稿のURLだけ差し替える方式にはしない。`gridspace-reply-request.ts`では操作IDだけを保存し、本文・CW・宛先を保存しない。
3. 写真選択の改善と画像編集の移植を分ける。最初は標準写真選択から既存アップローダーへ渡し、切抜き・効果・透かし・フレーム・動画圧縮を残す。
4. MFMの全関数と引数を含む比較資料を作る。未対応の表現を知らせずに省略せず、Webで正しく表示する経路を維持する。投稿ごとに大量のWebViewを置く構成は既定案にしない。
5. プラグイン、連携先、限定Blob、翻訳、反応は同じ投稿の表示に作用する。画面の設計より先に、アカウント・出所を区別してデータと通信を設計する。
6. 一般の投稿・アップロード・削除・チャット送信は、APIごとに冪等性を確認するまで結果不明時に自動再送しない。連携投稿のUUIDを一般投稿へ流用しない。
7. 権限不足、非公開、失効、一時障害、空の結果は別状態として表示する。Webへの切替時も判別を維持する。
8. アンテナ作成UIのlistソースと予約の再設定ボタンは現在コメントアウトされている。Neos直接投稿では読み取ったlocalOnly/visibilityを送信していない。現状の仕様として記録し、未実装機能を既存機能として数えない。
9. 検証用にローカル・リモート・連携・鍵・制限付き・未ログインの状態を用意する。連携障害/失効、リアルタイム/定期取得、長文/入れ子、カスタム絵文字、動画/音声/3D、失敗/結果不明の書き込みを含める。
10. 3D表示はThree.jsとSparkの回転・拡大・移動・モデルアニメーション・キャプチャを使う。対象ファイルでWebXR/VR開始操作は見つからなかった。VRM読み込みは別のavatar-walk機能にあり、一般の3D添付形式一覧には`.vrm`がない。ウィジェット調査と統合する。

本表は176行あり、1行に密接に関係する複数の選択肢を含む。この行数はPWA全体の機能数を意味しない。すべて実装予定であり、移植済み・検証済みとは判定していない。
