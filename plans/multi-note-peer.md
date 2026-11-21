# Multi Note：ぐりすぺ連携と影響範囲

- 作成日: 2026-11-20
- 対象ブランチ: `feat/multi-note`
- 状態: 両方向の実装・検証を終えた時点の要件を更新した。最新の実装との差分は掲載契約案と検証記録を参照する。本文の調査・段階案は当初の設計経緯として残す。
- レビュー結果は、れぞらぶ側の `feat/multi-note:plans/multi-note-claude-review.md` に記載する。
- 共通の製品仕様とWeb UIは、れぞらぶ側の `feat/multi-note:plans/multi-note.md` に記載する。
- ローカル複数掲載のDB・fanout・ストリーム・検索の詳細は、れぞらぶ側の `feat/multi-note:plans/multi-note-timeline.md` に記載する。
- 最新ブリッジを基にした掲載記録・操作・会話・表示の具体案: [multi-note-placement-protocol.md](multi-note-placement-protocol.md)。相手原本は掲載先で参照として扱い、チャンネルの所在と本文の所在を区別する。

## 既存ブリッジを使う前提と両方向の要件（2026-11-21）

今回の必須M1〜M8と後回しD1〜D5は掲載契約案に集約する。必須は保存/配信先、既存閲覧制限、用途別書込権限、削除・退会・再送、新方式の会話/反応/投票、一覧統合、作成結果不明時の復旧。本文・添付URLの完全失効、未掲載原本の本人限定化、既存全履歴の返信修復、通常AP投票全体の排他再設計、全匿名閲覧への新しい掲載証明は後回しとする。

Multi Noteの予約投稿と投稿後の掲載先追加・再追加は要件から除外する。公開チャンネルはセンシティブ属性だけで除外せず、必要なCWは投稿者が付ける。両サーバーで同じ原本・CWを使い、自動CWや掲載先別のCW制御は追加しない。候補・掲載・明示したチャンネルの閲覧の一律除外は両リポジトリで撤去し、追加20件と従来48件の受け入れテスト、両方向のブラウザ操作で検証済み。

本文URL・標準API・会話・添付URLは既存の公開条件を使い、有効掲載が0件でも本人限定にはしない。掲載側からの一覧/ホーム/ピン/集計は有効掲載だけを使う。既存の停止・ブロック・サインイン要求・非表示時刻は両取得経路で維持する。

れぞらぶの既存GridSpace実装は `C:/Users/neo/GitHub/resonite-love-gridspace` の `codex/gridspace-bridge` にある。最新化後の調査基点はれぞらぶ `57ee8ed337`、ぐりすぺ `9a15160548`。計画用のれぞらぶ `feat/multi-note` はブリッジを含まない旧基点なので、アプリケーション実装前に作業基点をそろえる。両サイトの既存ブリッジを拡張する計画とし、本番配備リビジョンはこの調査では未確認。

目標は、どちらのサイトからも相手側のチャンネルを同じ操作で選べること。投稿者として選んでいるアカウントのサーバーで原本を1件作り、両サイトの掲載先が同じ原本URIを参照する。チャンネル専用本文は既存の権限付き取得を拡張して読み、掲載のための保存用ミラーを必須にしない。通常共有済みなら既存の同一URIのノート表現も利用できる。通常投稿先の有無、会話、リアクション、削除はこの原本との対応を保つ。

現行チャンネル操作は `channelRole: source/client` と `link.initiator` に方向が依存する。新操作は現在actorのguest認可と双方向capabilityを分離して追加し、旧private・collection・リンク操作の役割を全体で変更しない。ChannelAuth/Channel/Private/Link/Reply/Notificationの監査対象と互換条件は掲載契約案に記載する。

## 現行の連携から分かる制約

- 連携チャンネルは、クライアント側から `gridspace/channels` で一覧し、`gridspace/channel-post` で1チャンネル宛てに投稿する。`GridspaceReplyService` は連携先に新しいノートを作る。投稿者はログイン中のぐりすぺ側アカウントとして扱われる。
- `GridspaceNoteService` の通常の共有対象は `channelId` のない `public` / `home` 投稿。現在のチャンネル投稿はこの共有経路に入らない。
- `GridspacePrivateService` のチャンネル表示、会話、ファイル取得は `channelId` を認可文脈に使う。`GridspaceChannelService.peerDelete` は `noteId` と `channelId` の一致で削除対象を決める。
- `GridspaceReactionService` は通常共有投稿のリアクション集約と連携チャンネル投稿のリアクションを別条件で扱う。共通投稿に両方の経路が重なる場合の重複計上を防ぐ必要がある。
- 現在のチャンネル連携は `source` / `client` の役割を持ち、既存コードではクライアント側からソース側のチャンネルを使う方向に限られる。両方向の投稿先選択に対応するには役割と認可の拡張が必要。

## ぐりすぺ固有のタイムライン差分

共通のローカル複数掲載は両サーバーに実装する。ただし、ぐりすぺのホーム・ハイブリッドには `GridspaceIdentityService.linkedUserId()` による連携アカウントの表示経路がある。`notes/timeline.ts` と `notes/hybrid-timeline.ts` は、そのアカウントのユーザータイムラインRedisキーも読み、対応するWebSocketストリームも連携アカウントを本人相当として扱う。通常投稿先のないチャンネル専用原本を、`channelId=null` だけを理由にこの経路へ流さない。通常＋チャンネルの原本は、連携アカウントとチャンネルを両方フォローしていても1行にする。

ぐりすぺのローカル・ハイブリッドは `gridspaceShared=true` のリモート原本も表示する。通常投稿先がある原本だけをこの通常経路の対象にし、チャンネル専用原本は除外する。`GridspaceNoteService` の通常共有判定、原本作成時の `gridspaceShared`、検索索引の通常投稿先フラグをそろえる。`GridspacePrivateService` の通常・チャンネル判定は段階1から共通処理へ移す。相手原本を新たな掲載記録から取得する文脈の追加は段階2で扱う。

最新版には `timeline/GridspaceTimelineService` の統合取得、`TimelineMergeService` の原本URI重複除去、表示更新用の `gridspace_timeline_outbox` がある。これを再利用し、掲載追加・解除を既存セッションの更新へつなぐ。現在のチャンネル取得はpeer側を前提にするため、両方向化では `channelOrigin` と `noteOrigin` を分ける。詳細は掲載契約案を参照する。

Claudeレビューで、段階1の書込前に修正が必要な通常共有経路が明らかになった。`canShareGridspaceNote` は `channelId=null` だけで通常共有を判定するため、新方式のチャンネル専用原本では誤判定する。作成時の `gridspaceShared` に加え、`GridspaceNoteService.read()`、`GridspaceSearchService` のID一覧、`GridspaceActionService` のリアクション等の照合を通常投稿先フラグで守る。連携先チャンネルへの複数掲載を段階2に分けても、この修正は段階1の公開条件に含める。

### 段階1で修正する通常共有の経路

| 経路 | 必須修正 |
| --- | --- |
| `note-protocol.ts` の `canShareGridspaceNote` | 通常投稿先の共通判定と既存の `public/home` 条件を使う。旧行の互換条件も共通処理へ集める |
| `NoteCreateService` | 全作成経路でフラグを確定し、チャンネル専用原本は `localOnly=true`、`gridspaceShared=false` を保存する。旧APIにも掲載表を同時に書く |
| `GridspaceNoteService.read()` | ID指定でも通常共有対象か再確認し、チャンネル専用原本の `gridspaceShared` をtrueに変更しない |
| `GridspaceSearchService` | 通常共有向けID一覧を新しい判定で絞る。権限付きチャンネル検索にはその文脈の判定を使う |
| `GridspacePrivateService` | home、context、withChannelNotes、関連ノート、添付、collectionの通常・チャンネル判定を共通化する。段階2まで延期しない |
| `GridspaceActionService` | チャンネルなしの通常共有アクションでは通常投稿先を必須にする。チャンネルIDの一致だけで認可しない |
| `GridspaceNotificationService` | 単一 `channelId` に依存するチャンネル通知の抽出・検証を監査し、新しい掲載文脈の扱いを定義する |
| `GridspaceReactionDeliveryService` / `GridspaceReactionNotificationService.receive` | 通常反応配送とlocalOnly・channelId=nullの通知条件を共通分類へ移し、新専用原本を通常系へ入れない |
| コア公開条件・公開リンク | Query/NoteEntity/shouldHideNote、skipHideの送信先、notes/show・children・conversation・SSR・公開リンク・通知・ストリームで既存制限を維持する。本文の直接取得に有効掲載や通常投稿先を必須化せず、通常共有の対象判定と分ける |
| RSS・一括削除 | FeedServiceの通常RSSはincludeDefaultで絞る。DeleteAccountProcessorServiceはgridspaceShared=falseの原本にも墓標・全宛先への削除配送を作る |
| 返信・非同期処理 | `GridspaceReplyService` の親一致を単一 `channelId` に依存させず、通常投稿先と有効掲載を確認する。ローカル操作の拒否は `fetchAndCreate` を通る呼出元で共通化し、`create` は公開条件を確定する。通常＋チャンネルの連合Announce受信を壊さない |

共通の取得処理では通常共有と権限付きチャンネル取得の文脈を必須で指定する。指定なしを許可する既定値を置かず、DB・Redis・WebSocketとも同じ掲載先条件を使う。`gridspaceShared` の値だけを読み取り許可の根拠にしない。

検証では通常・チャンネル専用・通常＋チャンネルの各原本を、連携アカウントを持つ利用者、複数チャンネルのフォロワー、ミュート利用者から見る。fanout ON/OFF、DB fallback、WebSocket、SQL/Meilisearchのどの経路でも、表示対象とノートIDの重複が一致することを確認する。

## 原本と掲載の責務

新しいルート原本は投稿者のホーム側に作り、本文、CW、添付、アンケート、削除を管理する。掲載先はチャンネルと原本URIを結ぶ記録を持つ。相手原本にローカルノート行がなくても扱い、相手IDを自分のnote IDにしない。既存channel-postとチャンネル専用会話のguest返信は原本側で保存するため、noteOriginとauthorOriginが異なる。来歴は保存した作成経路で判別し、既存URIを書き換えない。

```text
ぐりすぺの原本URI ── ぐりすぺ内の掲載先
        │
        │ 署名・認可・冪等キー
        ▼
れぞらぶの掲載記録 ── れぞらぶ内のチャンネル
        └─ 本文は原本側から認可付きで取得
```

サーバー間実装では、ぐりすぺ側の投稿者がれぞらぶ側を選ぶ経路と、れぞらぶ側の投稿者がぐりすぺ側を選ぶ経路を同じ契約で扱う。候補取得・認可・掲載・会話・削除を逆方向でも検証する。検証中の有効化範囲は限定できるが、製品仕様は両方向とする。両サイト内のローカル複数掲載も同じ保存形式で提供する。

同一サーバー内の初期UIでは、通常の投稿先とチャンネルを独立して選べる。通常の投稿欄は通常投稿先を選択済み、チャンネル画面からはそのチャンネルだけを選択済みで開く。通常＋チャンネルとチャンネルだけの両方を原本1件で扱い、チャンネル数の固定上限は設けない。チャンネルだけの原本は通常タイムラインと通常のGridSpace共有から除外する。通常投稿先もある場合は、既存の公開範囲・連合設定とGridSpace共有条件をそれぞれ適用し、掲載先のチャンネルには別の複製を作らない。

ローカル複数掲載の段階1では ActivityPub の形式や新しい拡張は不要。通常＋チャンネルで連合ONの場合は、原本につき既存形式の `Create<Note>` アクティビティを1つ生成し、チャンネル掲載情報を ActivityPub に載せない。チャンネルだけなら配送しない。原本削除時の `Delete` も連合済みの原本につき1つ生成する。段階2の署名付き `prepare` / `place` は GridSpace 固有の連携プロトコルで、ActivityPub の変更とは分けて扱う。

## 連携プロトコル案

1. 投稿欄は候補の `origin`、`channelId`、表示名、権限状態を保持する。相手1チャンネルだけの新UI投稿も新掲載APIを使い、旧channel-postの保存方式と分ける。
2. 原本作成前に、選択したすべての相手掲載先へ `prepare` を行う。両側のポリシーを一時プレビューとハッシュで確認する。初回の通信失敗・拒否では確定せず下書きを保持する。
3. 原本1件、ローカル掲載、全宛先の索引、作成receipt、希望状態の永続配送を同じトランザクションで保存し、`place` する。相手は現在の権限・原本内容を再確認する。掲載の一意キーは `(原本URI, channelId)`。結果は両側の永続キューと `status/sync` で照合する。
4. 連携先は掲載記録を確定し、本文・添付は表示時に原本側から認可付きで取得する。チャンネルだけへの投稿を通常の公開共有へ流さない。`canShareGridspaceNote` は通常投稿先の選択状態も確認し、`channelId = null` でもチャンネル専用原本を従来の `public` / `home` 共有対象として扱わない。通常共有済みの原本では、既存ミラーと掲載記録が同じ原本URIを指すようにし、リアクション・通知を重複させない。
5. 確定後の障害は同じ原本でpendingとし、再認可・再試行する。全掲載が失敗・解除された原本は通常配信せず、投稿者の管理画面に残す。本文の直接取得は既存の公開条件を維持する。管理者解除は終端状態とし、投稿後の掲載先追加・再追加は要件に含めない。
6. 原本削除は退会による一括削除も含め、未配送も含む全宛先へ伝える。掲載行がなくてもURI墓標を残し、placeと同じロックで復活を防ぐ。管理者解除は掲載だけに作用し、本文・添付URLを一律に失効させない。一時不可を削除扱いしない。

### 共通の会話とリアクション

通常投稿先を含む原本への返信は、返信者側に既存の通常ミラーを確保し、ローカル `replyId` を持つ通常返信として保存する。親を取得できない場合は失敗・再試行とし、ルート投稿へ変換しない。リアクションは現在のactorのホーム側が集合を所有し、既存revision同期を使う。チャンネルから開いても保存先を切り替えない。

通常原本の表示・myReaction・操作IDも閲覧側の実在ミラーへそろえ、未取得時は取込みが終わるまで操作不可とする。canonical URIで固定する所有者は原本の識別・経路集合を指し、通常系のlocal優先表示を廃止する意味にはしない。

チャンネル専用原本への返信・子孫は会話ルートの原本側に保存し、既存peerReplyのguest actor・receipt・ローカル親行を使う。会話内返信は一覧掲載・連合なし。専用反応も原本側へ集約し、ExtendedReactionServiceの追加/解除を新来歴に対応させる。投票は通常の連合経路を維持し、ペア内localOnly/専用は署名付きの原本側処理と結果表示へ振り分ける。別linked actorは別人として扱い、分散返信索引は作らない。

guest宛ての返信・子孫・反応通知は既存チャンネル通知の限定取得へ追加し、現在actorの本人確認・既読・通知IDによる再送重複除去を検証する。本文・添付・通知プレビューに同じ閲覧条件を適用する。通常返信のAP inReplyToは既存replyIdから生成し、AP形式は変えない。これらの往復が成立するまでは新しい共通会話を公開しない。

新専用返信は本人URIと保存した来歴によるdelete-replyを用意し、親や掲載が消えても本人が削除できる。ActionServiceのuploadSource/lockUpload/peerUploadには会話ルートと用途別書込許可を渡す。read用証明を返信・添付へ流用させない。本文の標準API取得と添付URL・保管方式は既存の公開条件を維持し、掲載消失による本人限定化や認可付きファイル配信基盤は追加しない。

## Web UI への追加

- `MkPostForm.vue` の投稿先は「通常の投稿」の選択状態と `{ origin, channelId }[]` を保持する。チャンネル画面からはそのチャンネルだけを選択済みにし、通常投稿先を追加できる。新UIの `MkGridspacePostForm.vue` も新掲載APIを使う。旧クライアントの単一channel-postは維持する。連携先に書けない利用者には理由と設定への導線を表示する。
- `MkCombinedChannelList.vue` が扱う同名チャンネルを投稿先シートでも発信元とセットで示す。お気に入り・フォロー中・検索結果の同じチャンネルを重複表示しない。
- `MkGridspacePrivateNote.vue` と通常の `MkNote.vue` は原本URIを表示上の同一投稿として扱う。チャンネル文脈を失わずに投稿詳細へ遷移し、アクセス権のない掲載先の名前は出さない。
- 一部成功時は「投稿済み／掲載待ち／掲載失敗」を投稿先別に示す。ユーザーが再送する操作は掲載だけに限定する。本文の下書きやアップロード済み添付を再送で重複作成しない。
- 連携先の状態を読めないときは古い候補を有効と推定しない。本文と選択は保持し、状態が戻ってから再確認する。
- 両フォームの下書きに確定待ちの作成キー・ハッシュを保持し、本人＋キーのreceipt照会で応答消失から復旧する。専用投稿・解除・未掲載の案内は既存の公開条件を明示し、非公開や本人限定と誤解させない。
- 相手原本の掲載は統合タイムライン対応版で表示し、旧Web/iOS/外部APIは表現可能な部分集合になることを示す。掲載先チップは確認不能と解除を区別し、確認期限後に古い状態を確定扱いしない。カーソル、集計・ピン、URI変更通知とレビュー指摘の現在の分類は掲載契約案に記載する。

## 影響ファイルの目安

| 領域 | 主要ファイル | 確認する性質 |
| --- | --- | --- |
| 連携入口・権限 | `GridspaceChannelAuthService.ts`、`GridspaceChannelService.ts`、`GridspaceLinkService.ts`、`gridspace/channel-post.ts` | 役割の方向、現在のアカウント、権限世代、失効、掲載解除 |
| 原本共有 | `GridspaceNoteService.ts`、`note-protocol.ts`、`GridspacePublicNoteService.ts`、`NoteCreateService.ts` | 段階1から通常投稿先を確認。チャンネル専用原本の分離、URIとミラーの一意性、削除時の墓標 |
| 通常共有の検索・操作 | `GridspaceSearchService.ts`、`GridspaceActionService.ts` | 段階1からID一覧・直接取得・アクションのすべてで共通判定を適用 |
| 読取・会話 | `GridspacePrivateService.ts`、`GridspaceReplyService.ts`、`GridspaceActionService.ts`、`GridspaceNoteService.ts`、`private-protocol.ts` | 既存公開条件、ローカル親行、guest返信、本人削除、用途別書込許可、新規親未解決の再試行 |
| 標準API・SSR | Query/NoteEntity/shouldHideNote、GridspacePublicNoteService、notes/show・children・conversation、SSR/embed・通知/ストリーム | 既存閲覧制限を維持。直接取得と通常配信を分離し、全packへの掲載ACLは追加しない |
| フィード・退会 | `server/web/FeedService.ts`、`queue/processors/DeleteAccountProcessorService.ts` | RSSの通常投稿先判定、専用原本の一括削除配送 |
| 新方式の投票 | `PollService.ts`、`notes/polls/vote.ts`、`NoteEntityService.ts` | localOnly/専用の原本投票、guest下位ガード、票数/isVoted反映。AP全体の再設計は後回し |
| 統合タイムライン | `timeline/GridspaceTimelineService.ts`、`TimelineLocalSource.ts`、`TimelineMergeService.ts`、`TimelineReferenceService.ts`、`timeline-protocol.ts` | チャンネルと原本の所在の分離、URI重複除去、掲載変更の再認可・表示更新 |
| 掲載・配送 | 新しい相手原本の掲載表、掲載配送記録、capabilityと掲載API | ローカルnote行がない参照、世代・冪等性、両方向の再送と解除 |
| リアクション・通知 | `GridspaceReactionService.ts`、`GridspaceReactionDeliveryService.ts`、`GridspaceReactionNotificationService.ts`、`GridspaceNotificationService.ts` | 通常ミラー操作と専用原本側操作の分類、集約・通知の重複防止 |
| Web | `MkPostForm.vue`、`MkGridspacePostForm.vue`、`MkCombinedChannelList.vue`、`MkGridspacePrivateNote.vue`、`pages/gridspace-channels.vue` | 選択、権限失効、一部失敗、共通投稿への遷移 |
| 型・iOS | `packages/misskey-js/src/autogen/`、`apps/ios/Core/Sources/GridSpaceCore/NativePeerChannel.swift` | API型生成、未知フィールドの読取、旧クライアントの誤操作防止 |

## 検証と公開条件

両サーバーを立てた結合テストで、原本1件・複数掲載、ホーム重複除去、共通返信/反応/投票、添付、個別削除/退会、解除、リンク失効、片側停止、再送とフォーム復旧を確認する。既存閲覧制限を迂回せず、通常経路へ専用投稿が混入しないことを検査する。掲載解除後の直接URL・添付の完全失効は合格条件にしない。

段階1の有効化前には、チャンネル専用原本に対する通常共有のID指定取得、検索ID一覧、チャンネルなしのアクション、作成時の共有フラグを検証する。`read()` の呼出後も共有フラグが変わらず、原本が相手サーバーの通常タイムラインへ入らないことを確認する。旧APIと新APIの通常・チャンネル専用・通常＋チャンネルの各原本で、DB/Redis/WebSocketとアンケート推薦の除外指定の結果を比較する。

段階1は両サーバー・全ワーカーへの読取と作成処理の配備、旧版プロセス停止、バックフィル・再索引、取得経路の照合後に新規書込を有効にする。有効化後は対応前の旧版へ戻してはいけない。機能停止は新規書込を止めるフラグで行い、作成済みの新旧原本を読むコード、掲載表、永続ジョブを残す。

連携先への複数掲載は段階2のプロトコル対応を確認してから有効化する。片側が旧版なら連携先候補を選択不可にする。既存の `gridspace/channel-post` による単一チャンネル投稿は互換性のため残す。

## 先に試す技術検証

1. チャンネル専用原本を通常のGridSpace共有経路へ出さずに、署名付きの対象チャンネル経路だけで取り込めるか。
2. 相手側利用者の返信を原本の同じ会話へ戻し、閲覧権と削除を両側で保てるか。
3. 2つのチャンネル経由で同じ原本を見ても、ホーム、リアクション、通知が重複しないか。

この3点が通るまで、連携先への複数掲載はUIの選択候補として公開しない。
