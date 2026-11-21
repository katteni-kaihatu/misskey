## (1) 全体判定

前回の骨格指摘（旧方式との併存、initiator・role、place前の削除、返信の表現、状態同期、旧API）は、ほぼ契約として解消しています。返信を既存の `replyId` と原本側guest返信へ寄せ、分散返信索引を撤回した判断は既存実装と整合します。根拠は `GridspaceNoteService.ts:164-175` で、相手の返信ミラーは自サーバーの原本URIへ `inReplyTo` を張り直して取り込まれます。

ただし、新たな矛盾が1件（P0）と、重要な不足が2件（P1）残っています。

- **P0**: 通常投稿先を含む原本を「誰の表現で表示し、どこへ操作するか」が二重に定義されています。
- **P1**: チャンネル専用原本は、原本側サーバー自身の標準APIからの見え方が未定義です。
- **P1**: guestが書いた専用返信を消す経路がありません。

この3点を固めれば、残りは実装に着手できます。

照合は読み取りのみで行いました。ぐりすぺの `9a15160548` とれぞらぶの `57ee8ed337` を比べると、差分は GridspaceNoteService・Link・SharedDrive・FollowExpansion とテストだけです。Reaction・Reply・Private・Timeline・Notification・NoteCreate は同一なので、以下の行番号はれぞらぶのチェックアウト（`57ee8ed337`）のものです。

## (2) 前回17指摘の状況

| 指摘 | 状況 | 備考 |
|---|---|---|
| P0-1 旧作成方式 | 解消 | 来歴と authorOrigin を分離。新UIの単一宛先も新APIに統一 |
| P0-2 initiator/role | 解消 | 監査表あり。再利用するguest経路の `assertSource` 依存は実装時に分離が必要（後述） |
| P0-3 水和/所有者 | 一部解消 | 4通りの取得は定義済み。ミラーとの関係が新P0 |
| P0-4 place前の削除 | 解消 | 既存の墓標との統一はP2 |
| P0-5 replyId/AP | 解消 | 既存の返信ミラー取込（`GridspaceNoteService.ts:174-175`）と整合 |
| P0-6 反応の所有 | 一部解消 | 保存先の規則は正しいが、新P0により前回の失敗例が再発し得る |
| P0-7 旧API/集計 | 解消 | ピンの保存先はP2 |
| P1-8 状態同期 | 解消 | |
| P1-9 prepare/孤立原本 | 解消 | |
| P1-10 並び順 | 解消 | ローカル掲載側の並べ替えキーはP2 |
| P1-11 URI変更通知 | 一部解消 | outboxの列不足（P2） |
| P1-12 掲載先ポリシー | 解消 | |
| P1-13 会話の整合 | 解消 | 索引案の撤回で論点が消えた |
| P1-14 本人の識別 | 解消 | |
| P2-15 信頼とURI | 解消 | |
| P2-16 チップ | 解消 | |
| P2-17 保持期間 | 解消 | ローカル計画との文書間不整合（P2） |

## (3) 残る指摘

### P0（計画の不足・文書内の矛盾）通常投稿先を含む原本の表示表現と操作先

- **矛盾している記述:** 契約案L110は「所有者はcanonical URIで固定し、通常ミラーで変えない」「local優先の `assertOwners` を修正する」としています。一方でL66・L118・L122は「既存ミラーを使い、反応・返信の保存先はミラー」としています。
- **既存実装との関係:**
  - 現行はミラーがあればlocalを所有者にします（`GridspaceTimelineService.ts:154-155,320-324`）。この仕組みで、反応の合算とミラーへの操作が成り立っています。
  - 所有者を原本側（peer）に固定すると、表示は委譲取得になります。委譲取得の反応状態は `extendedReactions.show(…, {id: link.localUserId})` から作られます（`GridspacePrivateService.ts:596`）。
  - `show()` は閲覧者IDを `${peerOrigin}/users/${viewerId}` として相手側で解決します（`GridspaceReactionService.ts:137,160`）。新しいguest閲覧者ではこのIDの対応が成り立ちません。
  - 操作が委譲先のActionServiceに流れると、guest行として原本側に保存されます。この行は所有行の判定（`GridspaceReactionService.ts:37`）で相手ホスト分として除外されるため、前回P0-6の「反応が消える」失敗が再発します。
- **未定義の分岐:** ミラーがまだ配送されていない状態で、チャンネル文脈から反応する場合。返信には「親を確保」とあるが、反応には同じ記述がありません。
- **固める内容:**
  - 「原本URIで固定する所有者」は一覧の経路集合と重複除去にだけ適用すると明記します。
  - 通常投稿先を含む原本は、閲覧側にミラーがあればミラーで表示し、操作IDもミラーにします。
  - ミラーがなければ取込みを先に行うか、操作不可・読み取り専用にします。

### P1（計画の不足）チャンネル専用原本・会話内返信の、原本側での基本可視性

- **計画の記述:** L93は「未掲載は投稿者だけ」「既存会話も投稿者以外は現在の有効経路が必要」としています。
- **コアの現状:**
  - コアの可視性判定（`NoteEntityService.ts:315` と、同期が必要とされる `QueryService.generateVisibilityQuery`）には掲載経路の概念がありません。
  - `public`・`localOnly` の原本は、原本側のローカル利用者や匿名閲覧者から `notes/show`・children・conversation・SSRで読めます。
  - 匿名の公開リンクは `GridspacePublicNoteService.ts:31-35` で、`channelId` がないため通常の公開ノートとして通ってしまいます。
- **閲覧経路が相手側チャンネルだけの場合:** 原本側のローカル閲覧者や返信者の認可には、相手側の掲載証明が必要です。しかし `notes/create` の返信経路（`create()`/`fetchAndCreate`）がそれをどう取得し、いつ検証するかが未定義です。
- **影響範囲の表にも載っていません:** `multi-note-timeline.md:130-142` と peer.md:39-48 に、上記の可視性判定・endpoint・PublicNoteServiceがありません。
- **固める内容:** 次のいずれかを決めます。
  - 既存チャンネル投稿と同じく原本側では公開とし、L93を緩める。
  - コアの可視性に経路条件を足し、相手側に到達できない時は閲覧不可（fail-closed）にする。

### P1（計画の不足）guestが書いた専用返信の削除

- 既存の `peerDelete` は `channelId` の一致が前提です（`GridspaceChannelService.ts:81`）。監査表も「旧操作を横流ししない」としています。
- その結果、guestが原本側に置いた会話内返信を本人が消す操作が、どこにも定義されていません。
- 同じく `channelId` が必須の既存経路として、添付アップロード（`GridspaceActionService.ts:165-184`）とguest通知の検証（`GridspaceNotificationService.ts:252`）があります。前者はL126で「既存を使う」とされているので、拡張対象として明記が必要です。

### P2（計画の不足）

- **outboxの列:** 既存のoutboxとchangeテーブルは `canonicalUri, noteId, kind, affectedUserId` だけです（migration `1794875013623` L24-26）。L164にある channel origin・ID・世代・イベントIDを入れる列か別表を明記します。
- **ピンの保存先:** `MiChannel.pinnedNoteIds: string[]`（`Channel.ts:64`）には掲載参照を入れられません。保存先と、旧 `channels/show` での見え方を決めます。
- **旧APIでのミラー:** 相手原本でもローカルにミラー（実在するMiNote）がある場合、旧 `channels/timeline` の部分集合に含めるかが未定義です。
- **墓標の統一:** 掲載のURI削除記録と既存の `MiGridspaceNoteTombstone`（`GridspaceNoteService.ts:186-194`）を同じ記録にするか、双方を検査するかを明記します。
- **段階1の表への追加:** `GridspaceReactionNotificationService.receive` の判定（L87: ローカル・localOnly・`channelId=null`）は新しい専用原本も通します。DeliveryService:42-45 と合わせて表に加えます。
- **ローカル掲載の並べ替えキー:** `note_channel_placement` には `sortAt`・`canonicalUri` がありません。新カーソル（L154）の統合時に使う導出キーを明記します。
- **文書間の不整合:**
  - timeline.md:57 は原本削除時のCASCADEと監査保持の未決を書いています。これは契約案L59・L150（状態保持・期限なし）、multi-note.md:121 と食い違います。
  - timeline.md:181 と multi-note.md:187 は「全掲載先消失」を未決としていますが、契約案L93では決定済みです。
  - design-spec:278 は `MkGridspacePostForm` を段階2の入口として未決としていますが、peer.md:92 は「新掲載APIを使う」と決めています。

### 明示的に残された判断（再指摘しない）

- 契約案L232: includeDefault の移行時CHECK違反、`canPublicNote`、`allowRenoteToExternal`
- multi-note.md:183-187、timeline.md:173-181 の各項目

### 既存実装の制約（計画が分離すると明記済み。実装時の注意）

- guestの解決は `assertSource()`・`resolvePerson` に依存します（`GridspaceChannelAuthService.ts:26-28,52`）。初回は相手のAP actorを取得できる必要があります。
- 自サイトのguest資格は `isClient` が前提です（同 L31）。

## (4) 着手できる範囲と、先に固める範囲

**着手可:**

- 段階1の通常共有修正と includeDefault（残された判断を確定した後）
- prepare/place/status/remove/delete-origin、両側の永続キュー、URI削除記録・ロック、receipt
- 通常返信（ミラーへのreplyId）
- 専用返信の作成経路と投票
- 反応の分類関数の置換（新規の誤分類箇所を含む）
- 通知の拡張

**先に固める:**

1. P0: 表示表現と操作先の規則（段階4の水和・所有者の実装前）
2. P1: 専用原本の原本側での可視性（段階2の新規書込開始前。ローカル複数掲載にも影響）
3. P1: guest返信の削除・添付の経路（段階5の前）
4. P2の列・保存先・文書間の不整合（該当する工程の前に追記すれば足りる）
