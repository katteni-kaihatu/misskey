# 静的索引と移行対応

基準: `f1bd2e3c4bebf931be8c49342691f03e3cdeb49b`、`2026.11.0-grid-space.31.33.1`。抽出元は[source-inventory.json](source-inventory.json)。初期はすべてWで利用可能にする計画であり、動作確認済みではない。目標とするN/Hには互換性の確認に合格した場合だけ切り替える。

この索引はソース定義を漏らさず追うための一覧である。受入時は[日常操作](daily-features.md)、[画面・設定・管理](routes-settings-admin.md)、[UGC](widgets-ugc.md)、[PWA・連携](platform-gridspace.md)の操作単位でも確認する。キー数やファイル数は機能数ではない。

## 全ルート宣言

| ID | 完全パス | 目標 | 段階 | 出典 |
|---|---|---|---|---|
| route-001 | `/` | H | S4 | [packages/frontend/src/router.definition.ts:26](../../packages/frontend/src/router.definition.ts#L26) |
| route-002 | `/timeline` | H | S4 | [packages/frontend/src/router.definition.ts:29](../../packages/frontend/src/router.definition.ts#L29) |
| route-003 | `/gridspace/pages/:linkedId` | W | S1・S6 | [packages/frontend/src/router.definition.ts:32](../../packages/frontend/src/router.definition.ts#L32) |
| route-004 | `/gridspace/gallery/:linkedId` | W | S1・S6 | [packages/frontend/src/router.definition.ts:35](../../packages/frontend/src/router.definition.ts#L35) |
| route-005 | `/@:username/pages/:pageName(*)` | W | S1・S6 | [packages/frontend/src/router.definition.ts:38](../../packages/frontend/src/router.definition.ts#L38) |
| route-006 | `/@:acct/following` | H | S5 | [packages/frontend/src/router.definition.ts:41](../../packages/frontend/src/router.definition.ts#L41) |
| route-007 | `/@:acct/followers` | H | S5 | [packages/frontend/src/router.definition.ts:44](../../packages/frontend/src/router.definition.ts#L44) |
| route-008 | `/@:acct/:page?` | H | S5 | [packages/frontend/src/router.definition.ts:48](../../packages/frontend/src/router.definition.ts#L48) |
| route-009 | `/notes/:noteId/:initialTab?` | H | S4 | [packages/frontend/src/router.definition.ts:52](../../packages/frontend/src/router.definition.ts#L52) |
| route-010 | `/list/:listId` | H | S5 | [packages/frontend/src/router.definition.ts:56](../../packages/frontend/src/router.definition.ts#L56) |
| route-011 | `/clips/:clipId/:peer?` | H | S5 | [packages/frontend/src/router.definition.ts:59](../../packages/frontend/src/router.definition.ts#L59) |
| route-012 | `/chat` | H | S5 | [packages/frontend/src/router.definition.ts:62](../../packages/frontend/src/router.definition.ts#L62) |
| route-013 | `/chat/user/:userId` | H | S5 | [packages/frontend/src/router.definition.ts:66](../../packages/frontend/src/router.definition.ts#L66) |
| route-014 | `/chat/room/:roomId` | H | S5 | [packages/frontend/src/router.definition.ts:70](../../packages/frontend/src/router.definition.ts#L70) |
| route-015 | `/chat/messages/:messageId` | H | S5 | [packages/frontend/src/router.definition.ts:74](../../packages/frontend/src/router.definition.ts#L74) |
| route-016 | `/instance-info/:host` | W | S1・S6 | [packages/frontend/src/router.definition.ts:78](../../packages/frontend/src/router.definition.ts#L78) |
| route-017 | `/settings` | H | S5 | [packages/frontend/src/router.definition.ts:82](../../packages/frontend/src/router.definition.ts#L82) |
| route-018 | `/settings/profile` | H | S5 | [packages/frontend/src/router.definition.ts:86](../../packages/frontend/src/router.definition.ts#L86) |
| route-019 | `/settings/avatar-decoration` | H | S5 | [packages/frontend/src/router.definition.ts:90](../../packages/frontend/src/router.definition.ts#L90) |
| route-020 | `/settings/privacy` | H | S5 | [packages/frontend/src/router.definition.ts:94](../../packages/frontend/src/router.definition.ts#L94) |
| route-021 | `/settings/emoji-palette` | H | S5 | [packages/frontend/src/router.definition.ts:98](../../packages/frontend/src/router.definition.ts#L98) |
| route-022 | `/settings/drive` | H | S5 | [packages/frontend/src/router.definition.ts:102](../../packages/frontend/src/router.definition.ts#L102) |
| route-023 | `/settings/drive/cleaner` | H | S5 | [packages/frontend/src/router.definition.ts:106](../../packages/frontend/src/router.definition.ts#L106) |
| route-024 | `/settings/notifications` | H | S5 | [packages/frontend/src/router.definition.ts:110](../../packages/frontend/src/router.definition.ts#L110) |
| route-025 | `/settings/email` | H | S5 | [packages/frontend/src/router.definition.ts:114](../../packages/frontend/src/router.definition.ts#L114) |
| route-026 | `/settings/security` | W | S1・S6 | [packages/frontend/src/router.definition.ts:118](../../packages/frontend/src/router.definition.ts#L118) |
| route-027 | `/settings/preferences` | H | S5 | [packages/frontend/src/router.definition.ts:122](../../packages/frontend/src/router.definition.ts#L122) |
| route-028 | `/settings/auto-translation` | H | S5 | [packages/frontend/src/router.definition.ts:126](../../packages/frontend/src/router.definition.ts#L126) |
| route-029 | `/settings/theme/install` | W | S1・S6 | [packages/frontend/src/router.definition.ts:130](../../packages/frontend/src/router.definition.ts#L130) |
| route-030 | `/settings/theme/manage` | W | S1・S6 | [packages/frontend/src/router.definition.ts:134](../../packages/frontend/src/router.definition.ts#L134) |
| route-031 | `/settings/theme` | W | S1・S6 | [packages/frontend/src/router.definition.ts:138](../../packages/frontend/src/router.definition.ts#L138) |
| route-032 | `/settings/navbar` | W | S1・S6 | [packages/frontend/src/router.definition.ts:142](../../packages/frontend/src/router.definition.ts#L142) |
| route-033 | `/settings/statusbar` | W | S1・S6 | [packages/frontend/src/router.definition.ts:146](../../packages/frontend/src/router.definition.ts#L146) |
| route-034 | `/settings/sounds` | H | S5 | [packages/frontend/src/router.definition.ts:150](../../packages/frontend/src/router.definition.ts#L150) |
| route-035 | `/settings/plugin/install` | W | S1・S6 | [packages/frontend/src/router.definition.ts:154](../../packages/frontend/src/router.definition.ts#L154) |
| route-036 | `/settings/plugin` | W | S1・S6 | [packages/frontend/src/router.definition.ts:158](../../packages/frontend/src/router.definition.ts#L158) |
| route-037 | `/settings/account-data` | W | S1・S6 | [packages/frontend/src/router.definition.ts:162](../../packages/frontend/src/router.definition.ts#L162) |
| route-038 | `/settings/mute-block` | H | S5 | [packages/frontend/src/router.definition.ts:166](../../packages/frontend/src/router.definition.ts#L166) |
| route-039 | `/settings/connect` | H | S5 | [packages/frontend/src/router.definition.ts:170](../../packages/frontend/src/router.definition.ts#L170) |
| route-040 | `/settings/apps` | H | S5 | [packages/frontend/src/router.definition.ts:174](../../packages/frontend/src/router.definition.ts#L174) |
| route-041 | `/settings/webhook/edit/:webhookId` | H | S5 | [packages/frontend/src/router.definition.ts:178](../../packages/frontend/src/router.definition.ts#L178) |
| route-042 | `/settings/webhook/new` | H | S5 | [packages/frontend/src/router.definition.ts:182](../../packages/frontend/src/router.definition.ts#L182) |
| route-043 | `/settings/deck` | W | S1・S6 | [packages/frontend/src/router.definition.ts:186](../../packages/frontend/src/router.definition.ts#L186) |
| route-044 | `/settings/custom-css` | W | S1・S6 | [packages/frontend/src/router.definition.ts:190](../../packages/frontend/src/router.definition.ts#L190) |
| route-045 | `/settings/profiles` | W | S1・S6 | [packages/frontend/src/router.definition.ts:194](../../packages/frontend/src/router.definition.ts#L194) |
| route-046 | `/settings/accounts` | H | S5 | [packages/frontend/src/router.definition.ts:198](../../packages/frontend/src/router.definition.ts#L198) |
| route-047 | `/settings/gridspace` | W | S1・S6 | [packages/frontend/src/router.definition.ts:202](../../packages/frontend/src/router.definition.ts#L202) |
| route-048 | `/settings/other` | H | S5 | [packages/frontend/src/router.definition.ts:206](../../packages/frontend/src/router.definition.ts#L206) |
| route-049 | `/settings/` | H | S5 | [packages/frontend/src/router.definition.ts:210](../../packages/frontend/src/router.definition.ts#L210) |
| route-050 | `/reset-password/:token?` | H | S1 | [packages/frontend/src/router.definition.ts:214](../../packages/frontend/src/router.definition.ts#L214) |
| route-051 | `/signup-complete/:code` | H | S1 | [packages/frontend/src/router.definition.ts:217](../../packages/frontend/src/router.definition.ts#L217) |
| route-052 | `/verify-email/:code` | H | S1 | [packages/frontend/src/router.definition.ts:220](../../packages/frontend/src/router.definition.ts#L220) |
| route-053 | `/announcements` | H | S5 | [packages/frontend/src/router.definition.ts:223](../../packages/frontend/src/router.definition.ts#L223) |
| route-054 | `/announcements/:announcementId` | H | S5 | [packages/frontend/src/router.definition.ts:226](../../packages/frontend/src/router.definition.ts#L226) |
| route-055 | `/about` | W | S1・S6 | [packages/frontend/src/router.definition.ts:229](../../packages/frontend/src/router.definition.ts#L229) |
| route-056 | `/contact` | W | S1・S6 | [packages/frontend/src/router.definition.ts:233](../../packages/frontend/src/router.definition.ts#L233) |
| route-057 | `/about-misskey` | W | S1・S6 | [packages/frontend/src/router.definition.ts:236](../../packages/frontend/src/router.definition.ts#L236) |
| route-058 | `/invite` | W | S1・S6 | [packages/frontend/src/router.definition.ts:239](../../packages/frontend/src/router.definition.ts#L239) |
| route-059 | `/ads` | W | S1・S6 | [packages/frontend/src/router.definition.ts:243](../../packages/frontend/src/router.definition.ts#L243) |
| route-060 | `/theme-editor` | W | S1・S6 | [packages/frontend/src/router.definition.ts:246](../../packages/frontend/src/router.definition.ts#L246) |
| route-061 | `/roles/:roleId` | H | S5 | [packages/frontend/src/router.definition.ts:250](../../packages/frontend/src/router.definition.ts#L250) |
| route-062 | `/user-tags/:tag` | H | S5 | [packages/frontend/src/router.definition.ts:253](../../packages/frontend/src/router.definition.ts#L253) |
| route-063 | `/explore` | H | S5 | [packages/frontend/src/router.definition.ts:256](../../packages/frontend/src/router.definition.ts#L256) |
| route-064 | `/search` | H | S5 | [packages/frontend/src/router.definition.ts:260](../../packages/frontend/src/router.definition.ts#L260) |
| route-065 | `/gridspace/private` | H | S5 | [packages/frontend/src/router.definition.ts:272](../../packages/frontend/src/router.definition.ts#L272) |
| route-066 | `/gridspace/channels/:channelId?` | H | S5 | [packages/frontend/src/router.definition.ts:276](../../packages/frontend/src/router.definition.ts#L276) |
| route-067 | `/authorize-follow` | H | S1 | [packages/frontend/src/router.definition.ts:281](../../packages/frontend/src/router.definition.ts#L281) |
| route-068 | `/authorize_interaction` | H | S1 | [packages/frontend/src/router.definition.ts:286](../../packages/frontend/src/router.definition.ts#L286) |
| route-069 | `/lookup` | W | S1・S6 | [packages/frontend/src/router.definition.ts:290](../../packages/frontend/src/router.definition.ts#L290) |
| route-070 | `/share` | H | S4 | [packages/frontend/src/router.definition.ts:294](../../packages/frontend/src/router.definition.ts#L294) |
| route-071 | `/api-console` | W | S1・S6 | [packages/frontend/src/router.definition.ts:298](../../packages/frontend/src/router.definition.ts#L298) |
| route-072 | `/scratchpad` | W | S1・S6 | [packages/frontend/src/router.definition.ts:302](../../packages/frontend/src/router.definition.ts#L302) |
| route-073 | `/preview` | W | S1・S6 | [packages/frontend/src/router.definition.ts:305](../../packages/frontend/src/router.definition.ts#L305) |
| route-074 | `/auth/:token` | H | S1 | [packages/frontend/src/router.definition.ts:308](../../packages/frontend/src/router.definition.ts#L308) |
| route-075 | `/miauth/:session` | H | S1 | [packages/frontend/src/router.definition.ts:311](../../packages/frontend/src/router.definition.ts#L311) |
| route-076 | `/oauth/authorize` | H | S1 | [packages/frontend/src/router.definition.ts:320](../../packages/frontend/src/router.definition.ts#L320) |
| route-077 | `/tags/:tag` | H | S5 | [packages/frontend/src/router.definition.ts:323](../../packages/frontend/src/router.definition.ts#L323) |
| route-078 | `/pages/new` | W | S1・S6 | [packages/frontend/src/router.definition.ts:326](../../packages/frontend/src/router.definition.ts#L326) |
| route-079 | `/pages/edit/:initPageId` | W | S1・S6 | [packages/frontend/src/router.definition.ts:330](../../packages/frontend/src/router.definition.ts#L330) |
| route-080 | `/pages` | W | S1・S6 | [packages/frontend/src/router.definition.ts:334](../../packages/frontend/src/router.definition.ts#L334) |
| route-081 | `/play/:id/edit` | W | S1・S6 | [packages/frontend/src/router.definition.ts:337](../../packages/frontend/src/router.definition.ts#L337) |
| route-082 | `/play/new` | W | S1・S6 | [packages/frontend/src/router.definition.ts:341](../../packages/frontend/src/router.definition.ts#L341) |
| route-083 | `/play/doom` | W | S1・S6 | [packages/frontend/src/router.definition.ts:345](../../packages/frontend/src/router.definition.ts#L345) |
| route-084 | `/play/:id` | W | S1・S6 | [packages/frontend/src/router.definition.ts:349](../../packages/frontend/src/router.definition.ts#L349) |
| route-085 | `/play` | W | S1・S6 | [packages/frontend/src/router.definition.ts:352](../../packages/frontend/src/router.definition.ts#L352) |
| route-086 | `/gallery/:postId/edit` | H | S5 | [packages/frontend/src/router.definition.ts:356](../../packages/frontend/src/router.definition.ts#L356) |
| route-087 | `/gallery/new` | H | S5 | [packages/frontend/src/router.definition.ts:360](../../packages/frontend/src/router.definition.ts#L360) |
| route-088 | `/gallery/:postId` | H | S5 | [packages/frontend/src/router.definition.ts:364](../../packages/frontend/src/router.definition.ts#L364) |
| route-089 | `/gallery` | H | S5 | [packages/frontend/src/router.definition.ts:367](../../packages/frontend/src/router.definition.ts#L367) |
| route-090 | `/channels/:channelId/edit` | H | S5 | [packages/frontend/src/router.definition.ts:370](../../packages/frontend/src/router.definition.ts#L370) |
| route-091 | `/channels/new` | H | S5 | [packages/frontend/src/router.definition.ts:374](../../packages/frontend/src/router.definition.ts#L374) |
| route-092 | `/channels/:channelId` | H | S5 | [packages/frontend/src/router.definition.ts:378](../../packages/frontend/src/router.definition.ts#L378) |
| route-093 | `/channels` | H | S5 | [packages/frontend/src/router.definition.ts:381](../../packages/frontend/src/router.definition.ts#L381) |
| route-094 | `/custom-emojis-manager` | W | S1・S6 | [packages/frontend/src/router.definition.ts:384](../../packages/frontend/src/router.definition.ts#L384) |
| route-095 | `/avatar-decorations` | W | S1・S6 | [packages/frontend/src/router.definition.ts:387](../../packages/frontend/src/router.definition.ts#L387) |
| route-096 | `/registry/keys/:domain/:path(*)?` | W | S1・S6 | [packages/frontend/src/router.definition.ts:391](../../packages/frontend/src/router.definition.ts#L391) |
| route-097 | `/registry/value/:domain/:path(*)?` | W | S1・S6 | [packages/frontend/src/router.definition.ts:394](../../packages/frontend/src/router.definition.ts#L394) |
| route-098 | `/registry` | W | S1・S6 | [packages/frontend/src/router.definition.ts:397](../../packages/frontend/src/router.definition.ts#L397) |
| route-099 | `/install-extentions` | W | S1・S6 | [packages/frontend/src/router.definition.ts:400](../../packages/frontend/src/router.definition.ts#L400) |
| route-100 | `/install-extensions` | W | S1・S6 | [packages/frontend/src/router.definition.ts:404](../../packages/frontend/src/router.definition.ts#L404) |
| route-101 | `/admin/user/:userId` | W | S1・S6 | [packages/frontend/src/router.definition.ts:408](../../packages/frontend/src/router.definition.ts#L408) |
| route-102 | `/admin/file/:fileId` | W | S1・S6 | [packages/frontend/src/router.definition.ts:411](../../packages/frontend/src/router.definition.ts#L411) |
| route-103 | `/admin` | W | S1・S6 | [packages/frontend/src/router.definition.ts:414](../../packages/frontend/src/router.definition.ts#L414) |
| route-104 | `/admin/overview` | W | S1・S6 | [packages/frontend/src/router.definition.ts:417](../../packages/frontend/src/router.definition.ts#L417) |
| route-105 | `/admin/users` | W | S1・S6 | [packages/frontend/src/router.definition.ts:421](../../packages/frontend/src/router.definition.ts#L421) |
| route-106 | `/admin/emojis` | W | S1・S6 | [packages/frontend/src/router.definition.ts:425](../../packages/frontend/src/router.definition.ts#L425) |
| route-107 | `/admin/emojis2` | W | S1・S6 | [packages/frontend/src/router.definition.ts:429](../../packages/frontend/src/router.definition.ts#L429) |
| route-108 | `/admin/avatar-decorations` | W | S1・S6 | [packages/frontend/src/router.definition.ts:433](../../packages/frontend/src/router.definition.ts#L433) |
| route-109 | `/admin/gridspace` | W | S1・S6 | [packages/frontend/src/router.definition.ts:437](../../packages/frontend/src/router.definition.ts#L437) |
| route-110 | `/admin/federation-job-queue` | W | S1・S6 | [packages/frontend/src/router.definition.ts:441](../../packages/frontend/src/router.definition.ts#L441) |
| route-111 | `/admin/job-queue` | W | S1・S6 | [packages/frontend/src/router.definition.ts:445](../../packages/frontend/src/router.definition.ts#L445) |
| route-112 | `/admin/files` | W | S1・S6 | [packages/frontend/src/router.definition.ts:449](../../packages/frontend/src/router.definition.ts#L449) |
| route-113 | `/admin/federation` | W | S1・S6 | [packages/frontend/src/router.definition.ts:453](../../packages/frontend/src/router.definition.ts#L453) |
| route-114 | `/admin/announcements` | W | S1・S6 | [packages/frontend/src/router.definition.ts:457](../../packages/frontend/src/router.definition.ts#L457) |
| route-115 | `/admin/ads` | W | S1・S6 | [packages/frontend/src/router.definition.ts:461](../../packages/frontend/src/router.definition.ts#L461) |
| route-116 | `/admin/roles/:id/edit` | W | S1・S6 | [packages/frontend/src/router.definition.ts:465](../../packages/frontend/src/router.definition.ts#L465) |
| route-117 | `/admin/roles/new` | W | S1・S6 | [packages/frontend/src/router.definition.ts:469](../../packages/frontend/src/router.definition.ts#L469) |
| route-118 | `/admin/roles/:id` | W | S1・S6 | [packages/frontend/src/router.definition.ts:473](../../packages/frontend/src/router.definition.ts#L473) |
| route-119 | `/admin/roles` | W | S1・S6 | [packages/frontend/src/router.definition.ts:477](../../packages/frontend/src/router.definition.ts#L477) |
| route-120 | `/admin/database` | W | S1・S6 | [packages/frontend/src/router.definition.ts:481](../../packages/frontend/src/router.definition.ts#L481) |
| route-121 | `/admin/abuses` | W | S1・S6 | [packages/frontend/src/router.definition.ts:485](../../packages/frontend/src/router.definition.ts#L485) |
| route-122 | `/admin/modlog` | W | S1・S6 | [packages/frontend/src/router.definition.ts:489](../../packages/frontend/src/router.definition.ts#L489) |
| route-123 | `/admin/settings` | W | S1・S6 | [packages/frontend/src/router.definition.ts:493](../../packages/frontend/src/router.definition.ts#L493) |
| route-124 | `/admin/branding` | W | S1・S6 | [packages/frontend/src/router.definition.ts:497](../../packages/frontend/src/router.definition.ts#L497) |
| route-125 | `/admin/moderation` | W | S1・S6 | [packages/frontend/src/router.definition.ts:501](../../packages/frontend/src/router.definition.ts#L501) |
| route-126 | `/admin/email-settings` | W | S1・S6 | [packages/frontend/src/router.definition.ts:505](../../packages/frontend/src/router.definition.ts#L505) |
| route-127 | `/admin/object-storage` | W | S1・S6 | [packages/frontend/src/router.definition.ts:509](../../packages/frontend/src/router.definition.ts#L509) |
| route-128 | `/admin/security` | W | S1・S6 | [packages/frontend/src/router.definition.ts:513](../../packages/frontend/src/router.definition.ts#L513) |
| route-129 | `/admin/relays` | W | S1・S6 | [packages/frontend/src/router.definition.ts:517](../../packages/frontend/src/router.definition.ts#L517) |
| route-130 | `/admin/external-services` | W | S1・S6 | [packages/frontend/src/router.definition.ts:521](../../packages/frontend/src/router.definition.ts#L521) |
| route-131 | `/admin/auto-translation` | W | S1・S6 | [packages/frontend/src/router.definition.ts:525](../../packages/frontend/src/router.definition.ts#L525) |
| route-132 | `/admin/performance` | W | S1・S6 | [packages/frontend/src/router.definition.ts:529](../../packages/frontend/src/router.definition.ts#L529) |
| route-133 | `/admin/invites` | W | S1・S6 | [packages/frontend/src/router.definition.ts:533](../../packages/frontend/src/router.definition.ts#L533) |
| route-134 | `/admin/abuse-report-notification-recipient` | W | S1・S6 | [packages/frontend/src/router.definition.ts:537](../../packages/frontend/src/router.definition.ts#L537) |
| route-135 | `/admin/system-webhook` | W | S1・S6 | [packages/frontend/src/router.definition.ts:541](../../packages/frontend/src/router.definition.ts#L541) |
| route-136 | `/admin/` | W | S1・S6 | [packages/frontend/src/router.definition.ts:545](../../packages/frontend/src/router.definition.ts#L545) |
| route-137 | `/my/notifications` | H | S4 | [packages/frontend/src/router.definition.ts:549](../../packages/frontend/src/router.definition.ts#L549) |
| route-138 | `/my/favorites` | H | S5 | [packages/frontend/src/router.definition.ts:553](../../packages/frontend/src/router.definition.ts#L553) |
| route-139 | `/my/achievements` | W | S1・S6 | [packages/frontend/src/router.definition.ts:557](../../packages/frontend/src/router.definition.ts#L557) |
| route-140 | `/my/drive/folder/:folder` | H | S4 | [packages/frontend/src/router.definition.ts:561](../../packages/frontend/src/router.definition.ts#L561) |
| route-141 | `/my/drive` | H | S4 | [packages/frontend/src/router.definition.ts:565](../../packages/frontend/src/router.definition.ts#L565) |
| route-142 | `/my/drive/file/:fileId` | H | S4 | [packages/frontend/src/router.definition.ts:569](../../packages/frontend/src/router.definition.ts#L569) |
| route-143 | `/my/follow-requests` | H | S5 | [packages/frontend/src/router.definition.ts:573](../../packages/frontend/src/router.definition.ts#L573) |
| route-144 | `/my/lists/:listId` | H | S5 | [packages/frontend/src/router.definition.ts:577](../../packages/frontend/src/router.definition.ts#L577) |
| route-145 | `/my/lists` | H | S5 | [packages/frontend/src/router.definition.ts:581](../../packages/frontend/src/router.definition.ts#L581) |
| route-146 | `/my/clips` | H | S5 | [packages/frontend/src/router.definition.ts:585](../../packages/frontend/src/router.definition.ts#L585) |
| route-147 | `/my/antennas/create` | H | S5 | [packages/frontend/src/router.definition.ts:589](../../packages/frontend/src/router.definition.ts#L589) |
| route-148 | `/my/antennas/:antennaId` | H | S5 | [packages/frontend/src/router.definition.ts:593](../../packages/frontend/src/router.definition.ts#L593) |
| route-149 | `/my/antennas` | H | S5 | [packages/frontend/src/router.definition.ts:597](../../packages/frontend/src/router.definition.ts#L597) |
| route-150 | `/timeline/list/:listId` | H | S4 | [packages/frontend/src/router.definition.ts:601](../../packages/frontend/src/router.definition.ts#L601) |
| route-151 | `/timeline/antenna/:antennaId` | H | S4 | [packages/frontend/src/router.definition.ts:605](../../packages/frontend/src/router.definition.ts#L605) |
| route-152 | `/clicker` | W | S1・S6 | [packages/frontend/src/router.definition.ts:609](../../packages/frontend/src/router.definition.ts#L609) |
| route-153 | `/games` | W | S1・S6 | [packages/frontend/src/router.definition.ts:613](../../packages/frontend/src/router.definition.ts#L613) |
| route-154 | `/avatar-walk` | W | S1・S6 | [packages/frontend/src/router.definition.ts:617](../../packages/frontend/src/router.definition.ts#L617) |
| route-155 | `/bubble-game` | W | S1・S6 | [packages/frontend/src/router.definition.ts:621](../../packages/frontend/src/router.definition.ts#L621) |
| route-156 | `/reversi` | W | S1・S6 | [packages/frontend/src/router.definition.ts:625](../../packages/frontend/src/router.definition.ts#L625) |
| route-157 | `/reversi/g/:gameId` | W | S1・S6 | [packages/frontend/src/router.definition.ts:629](../../packages/frontend/src/router.definition.ts#L629) |
| route-158 | `/qr` | W | S1・S6 | [packages/frontend/src/router.definition.ts:633](../../packages/frontend/src/router.definition.ts#L633) |
| route-159 | `/debug` | W | S1・S6 | [packages/frontend/src/router.definition.ts:637](../../packages/frontend/src/router.definition.ts#L637) |
| route-160 | `/redirect-test` | H | S1 | [packages/frontend/src/router.definition.ts:642](../../packages/frontend/src/router.definition.ts#L642) |
| route-161 | `/neos/directupload` | W | S1・S6 | [packages/frontend/src/router.definition.ts:646](../../packages/frontend/src/router.definition.ts#L646) |
| route-162 | `/:(*)` | W | S1・S6 | [packages/frontend/src/router.definition.ts:649](../../packages/frontend/src/router.definition.ts#L649) |

ルートのloginRequired、条件分岐、子ルート、redirect、query、hashの元の式はJSONを参照する。ルート直下・空の子ルート・エイリアスを一つの画面と見なして削除しない。catch-allがあっても、将来追加される未知の機能を自動的にネイティブ対応済みとは扱わない。

## 全設定キー 122件

各キーは初期のWで元の値を保持する。編集UIをN/Hへ移した場合も、元のアカウント・サーバー・端末ごとのスコープ、同期、未知の値を保つ。ネイティブ側で未実装の項目を初期値で上書きしない。

| キー | 目標 | 段階 | 受入の観点 | 出典 |
|---|---|---|---|---|
| `autoTranslation.enabled` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:60](../../packages/frontend/src/preferences/def.ts#L60) |
| `autoTranslation.targetLang` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:61](../../packages/frontend/src/preferences/def.ts#L61) |
| `accounts` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:63](../../packages/frontend/src/preferences/def.ts#L63) |
| `pinnedUserLists` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:70](../../packages/frontend/src/preferences/def.ts#L70) |
| `uploadFolder` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:74](../../packages/frontend/src/preferences/def.ts#L74) |
| `widgets` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:78](../../packages/frontend/src/preferences/def.ts#L78) |
| `deck.profile` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:96](../../packages/frontend/src/preferences/def.ts#L96) |
| `deck.profiles` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:100](../../packages/frontend/src/preferences/def.ts#L100) |
| `gridspacePaletteImports` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:105](../../packages/frontend/src/preferences/def.ts#L105) |
| `gridspacePaletteImportPending` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:109](../../packages/frontend/src/preferences/def.ts#L109) |
| `gridspaceProfileImportPending` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:113](../../packages/frontend/src/preferences/def.ts#L113) |
| `gridspaceSettingsImportRequest` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:117](../../packages/frontend/src/preferences/def.ts#L117) |
| `gridspaceSettingsApplied` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:121](../../packages/frontend/src/preferences/def.ts#L121) |
| `emojiPalettes` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:126](../../packages/frontend/src/preferences/def.ts#L126) |
| `emojiPaletteForReaction` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:154](../../packages/frontend/src/preferences/def.ts#L154) |
| `emojiPaletteForMain` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:158](../../packages/frontend/src/preferences/def.ts#L158) |
| `overridedDeviceKind` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:163](../../packages/frontend/src/preferences/def.ts#L163) |
| `themes` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:166](../../packages/frontend/src/preferences/def.ts#L166) |
| `lightTheme` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:185](../../packages/frontend/src/preferences/def.ts#L185) |
| `darkTheme` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:188](../../packages/frontend/src/preferences/def.ts#L188) |
| `syncDeviceDarkMode` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:191](../../packages/frontend/src/preferences/def.ts#L191) |
| `defaultNoteVisibility` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:194](../../packages/frontend/src/preferences/def.ts#L194) |
| `defaultNoteLocalOnly` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:197](../../packages/frontend/src/preferences/def.ts#L197) |
| `keepCw` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:200](../../packages/frontend/src/preferences/def.ts#L200) |
| `rememberNoteVisibility` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:203](../../packages/frontend/src/preferences/def.ts#L203) |
| `reportError` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:206](../../packages/frontend/src/preferences/def.ts#L206) |
| `collapseRenotes` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:209](../../packages/frontend/src/preferences/def.ts#L209) |
| `menu` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:212](../../packages/frontend/src/preferences/def.ts#L212) |
| `statusbars` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:228](../../packages/frontend/src/preferences/def.ts#L228) |
| `serverDisconnectedBehavior` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:231](../../packages/frontend/src/preferences/def.ts#L231) |
| `nsfw` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:234](../../packages/frontend/src/preferences/def.ts#L234) |
| `highlightSensitiveMedia` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:237](../../packages/frontend/src/preferences/def.ts#L237) |
| `animation` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:240](../../packages/frontend/src/preferences/def.ts#L240) |
| `animatedMfm` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:243](../../packages/frontend/src/preferences/def.ts#L243) |
| `advancedMfm` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:246](../../packages/frontend/src/preferences/def.ts#L246) |
| `showReactionsCount` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:249](../../packages/frontend/src/preferences/def.ts#L249) |
| `enableQuickAddMfmFunction` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:252](../../packages/frontend/src/preferences/def.ts#L252) |
| `loadRawImages` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:255](../../packages/frontend/src/preferences/def.ts#L255) |
| `imageNewTab` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:258](../../packages/frontend/src/preferences/def.ts#L258) |
| `disableShowingAnimatedImages` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:261](../../packages/frontend/src/preferences/def.ts#L261) |
| `emojiStyle` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:264](../../packages/frontend/src/preferences/def.ts#L264) |
| `menuStyle` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:267](../../packages/frontend/src/preferences/def.ts#L267) |
| `useBlurEffectForModal` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:270](../../packages/frontend/src/preferences/def.ts#L270) |
| `useBlurEffect` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:273](../../packages/frontend/src/preferences/def.ts#L273) |
| `useStickyIcons` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:276](../../packages/frontend/src/preferences/def.ts#L276) |
| `enableHighQualityImagePlaceholders` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:279](../../packages/frontend/src/preferences/def.ts#L279) |
| `showFixedPostForm` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:282](../../packages/frontend/src/preferences/def.ts#L282) |
| `showFixedPostFormInChannel` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:285](../../packages/frontend/src/preferences/def.ts#L285) |
| `enableInfiniteScroll` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:288](../../packages/frontend/src/preferences/def.ts#L288) |
| `useReactionPickerForContextMenu` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:291](../../packages/frontend/src/preferences/def.ts#L291) |
| `instanceTicker` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:294](../../packages/frontend/src/preferences/def.ts#L294) |
| `emojiPickerScale` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:297](../../packages/frontend/src/preferences/def.ts#L297) |
| `emojiPickerWidth` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:300](../../packages/frontend/src/preferences/def.ts#L300) |
| `emojiPickerHeight` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:303](../../packages/frontend/src/preferences/def.ts#L303) |
| `emojiPickerStyle` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:306](../../packages/frontend/src/preferences/def.ts#L306) |
| `squareAvatars` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:309](../../packages/frontend/src/preferences/def.ts#L309) |
| `showAvatarDecorations` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:312](../../packages/frontend/src/preferences/def.ts#L312) |
| `numberOfPageCache` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:315](../../packages/frontend/src/preferences/def.ts#L315) |
| `pollingInterval` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:318](../../packages/frontend/src/preferences/def.ts#L318) |
| `showNoteActionsOnlyHover` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:324](../../packages/frontend/src/preferences/def.ts#L324) |
| `showClipButtonInNoteFooter` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:327](../../packages/frontend/src/preferences/def.ts#L327) |
| `reactionsDisplaySize` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:330](../../packages/frontend/src/preferences/def.ts#L330) |
| `limitWidthOfReaction` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:333](../../packages/frontend/src/preferences/def.ts#L333) |
| `forceShowAds` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:336](../../packages/frontend/src/preferences/def.ts#L336) |
| `aiChanMode` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:339](../../packages/frontend/src/preferences/def.ts#L339) |
| `devMode` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:342](../../packages/frontend/src/preferences/def.ts#L342) |
| `mediaListWithOneImageAppearance` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:345](../../packages/frontend/src/preferences/def.ts#L345) |
| `showMediaListByGridInWideArea` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:348](../../packages/frontend/src/preferences/def.ts#L348) |
| `notificationPosition` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:351](../../packages/frontend/src/preferences/def.ts#L351) |
| `notificationStackAxis` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:354](../../packages/frontend/src/preferences/def.ts#L354) |
| `keepScreenOn` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:357](../../packages/frontend/src/preferences/def.ts#L357) |
| `useGroupedNotifications` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:360](../../packages/frontend/src/preferences/def.ts#L360) |
| `dataSaver` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:363](../../packages/frontend/src/preferences/def.ts#L363) |
| `autoplayEmbededPlayerOfUrlPreview` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:372](../../packages/frontend/src/preferences/def.ts#L372) |
| `hemisphere` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:375](../../packages/frontend/src/preferences/def.ts#L375) |
| `enableSeasonalScreenEffect` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:378](../../packages/frontend/src/preferences/def.ts#L378) |
| `enableHorizontalSwipe` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:381](../../packages/frontend/src/preferences/def.ts#L381) |
| `enablePullToRefresh` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:384](../../packages/frontend/src/preferences/def.ts#L384) |
| `useNativeUiForVideoAudioPlayer` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:387](../../packages/frontend/src/preferences/def.ts#L387) |
| `keepOriginalFilename` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:390](../../packages/frontend/src/preferences/def.ts#L390) |
| `alwaysConfirmFollow` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:393](../../packages/frontend/src/preferences/def.ts#L393) |
| `confirmWhenRevealingSensitiveMedia` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:396](../../packages/frontend/src/preferences/def.ts#L396) |
| `contextMenu` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:399](../../packages/frontend/src/preferences/def.ts#L399) |
| `skipNoteRender` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:402](../../packages/frontend/src/preferences/def.ts#L402) |
| `showSoftWordMutedWord` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:405](../../packages/frontend/src/preferences/def.ts#L405) |
| `confirmOnReact` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:408](../../packages/frontend/src/preferences/def.ts#L408) |
| `defaultFollowWithReplies` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:411](../../packages/frontend/src/preferences/def.ts#L411) |
| `makeEveryTextElementsSelectable` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:414](../../packages/frontend/src/preferences/def.ts#L414) |
| `showNavbarSubButtons` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:417](../../packages/frontend/src/preferences/def.ts#L417) |
| `showTitlebar` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:420](../../packages/frontend/src/preferences/def.ts#L420) |
| `showAvailableReactionsFirstInNote` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:423](../../packages/frontend/src/preferences/def.ts#L423) |
| `showPageTabBarBottom` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:426](../../packages/frontend/src/preferences/def.ts#L426) |
| `plugins` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:429](../../packages/frontend/src/preferences/def.ts#L429) |
| `mutingEmojis` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:439](../../packages/frontend/src/preferences/def.ts#L439) |
| `watermarkPresets` | H | S2/S4 | 既存画像加工を残し、プリセット/素材/出力を比較 | [packages/frontend/src/preferences/def.ts:445](../../packages/frontend/src/preferences/def.ts#L445) |
| `defaultWatermarkPresetId` | H | S2/S4 | 既存画像加工を残し、プリセット/素材/出力を比較 | [packages/frontend/src/preferences/def.ts:465](../../packages/frontend/src/preferences/def.ts#L465) |
| `imageFramePresets` | H | S2/S4 | 既存画像加工を残し、プリセット/素材/出力を比較 | [packages/frontend/src/preferences/def.ts:469](../../packages/frontend/src/preferences/def.ts#L469) |
| `defaultImageCompressionLevel` | H | S2/S4 | 既存画像加工を残し、プリセット/素材/出力を比較 | [packages/frontend/src/preferences/def.ts:489](../../packages/frontend/src/preferences/def.ts#L489) |
| `defaultVideoCompressionLevel` | H | S2/S4 | 既存画像加工を残し、プリセット/素材/出力を比較 | [packages/frontend/src/preferences/def.ts:492](../../packages/frontend/src/preferences/def.ts#L492) |
| `sound.masterVolume` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:496](../../packages/frontend/src/preferences/def.ts#L496) |
| `sound.notUseSound` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:499](../../packages/frontend/src/preferences/def.ts#L499) |
| `sound.useSoundOnlyWhenActive` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:502](../../packages/frontend/src/preferences/def.ts#L502) |
| `sound.on.note` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:505](../../packages/frontend/src/preferences/def.ts#L505) |
| `sound.on.noteMy` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:508](../../packages/frontend/src/preferences/def.ts#L508) |
| `sound.on.notification` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:511](../../packages/frontend/src/preferences/def.ts#L511) |
| `sound.on.reaction` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:514](../../packages/frontend/src/preferences/def.ts#L514) |
| `sound.on.chatMessage` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:517](../../packages/frontend/src/preferences/def.ts#L517) |
| `deck.alwaysShowMainColumn` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:521](../../packages/frontend/src/preferences/def.ts#L521) |
| `deck.navWindow` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:524](../../packages/frontend/src/preferences/def.ts#L524) |
| `deck.useSimpleUiForNonRootPages` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:527](../../packages/frontend/src/preferences/def.ts#L527) |
| `deck.columnAlign` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:530](../../packages/frontend/src/preferences/def.ts#L530) |
| `deck.columnGap` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:533](../../packages/frontend/src/preferences/def.ts#L533) |
| `deck.menuPosition` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:536](../../packages/frontend/src/preferences/def.ts#L536) |
| `deck.navbarPosition` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:539](../../packages/frontend/src/preferences/def.ts#L539) |
| `deck.wallpaper` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:542](../../packages/frontend/src/preferences/def.ts#L542) |
| `chat.showSenderName` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:546](../../packages/frontend/src/preferences/def.ts#L546) |
| `chat.sendOnEnter` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:549](../../packages/frontend/src/preferences/def.ts#L549) |
| `game.dropAndFusion` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:553](../../packages/frontend/src/preferences/def.ts#L553) |
| `experimental.stackingRouterView` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:560](../../packages/frontend/src/preferences/def.ts#L560) |
| `experimental.enableFolderPageView` | W/H | S1/S3/S5 | Webの意味と配置を保持。ネイティブに相当する値だけ別に適用 | [packages/frontend/src/preferences/def.ts:563](../../packages/frontend/src/preferences/def.ts#L563) |
| `experimental.enableHapticFeedback` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:566](../../packages/frontend/src/preferences/def.ts#L566) |
| `experimental.enableWebTranslatorApi` | H/N | S3–S5 | 既存scopeと未知値を保持し、対応するネイティブ動作を比較 | [packages/frontend/src/preferences/def.ts:569](../../packages/frontend/src/preferences/def.ts#L569) |

## 永続状態キー

設定以外の状態にも別途所有者を定める。表にある認証情報・秘密情報はエクスポートファイルに含めず、公開一覧にはキーの名前だけを記録する。

| キー | 保存scope | 目標 | 受入の観点 | 出典 |
|---|---|---|---|---|
| `accountSetupWizard` | 'account' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:19](../../packages/frontend/src/store.ts#L19) |
| `tips` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:23](../../packages/frontend/src/store.ts#L23) |
| `memo` | 'account' | H | 既存内容・自動保存を移行し、編集競合を防ぐ | [packages/frontend/src/store.ts:27](../../packages/frontend/src/store.ts#L27) |
| `memo2` | 'account' | H | 既存内容・自動保存を移行し、編集競合を防ぐ | [packages/frontend/src/store.ts:31](../../packages/frontend/src/store.ts#L31) |
| `morse` | 'account' | H | 既存内容・自動保存を移行し、編集競合を防ぐ | [packages/frontend/src/store.ts:35](../../packages/frontend/src/store.ts#L35) |
| `reactionAcceptance` | 'account' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:43](../../packages/frontend/src/store.ts#L43) |
| `mutedAds` | 'account' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:47](../../packages/frontend/src/store.ts#L47) |
| `visibility` | 'deviceAccount' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:51](../../packages/frontend/src/store.ts#L51) |
| `localOnly` | 'deviceAccount' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:55](../../packages/frontend/src/store.ts#L55) |
| `showPreview` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:59](../../packages/frontend/src/store.ts#L59) |
| `tl` | 'deviceAccount' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:63](../../packages/frontend/src/store.ts#L63) |
| `darkMode` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:77](../../packages/frontend/src/store.ts#L77) |
| `realtimeMode` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:81](../../packages/frontend/src/store.ts#L81) |
| `recentlyUsedEmojis` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:85](../../packages/frontend/src/store.ts#L85) |
| `gridspaceRecentEmojiImports` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:89](../../packages/frontend/src/store.ts#L89) |
| `recentlyUsedUsers` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:93](../../packages/frontend/src/store.ts#L93) |
| `menuDisplay` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:97](../../packages/frontend/src/store.ts#L97) |
| `postFormWithHashtags` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:101](../../packages/frontend/src/store.ts#L101) |
| `postFormHashtags` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:105](../../packages/frontend/src/store.ts#L105) |
| `additionalUnicodeEmojiIndexes` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:109](../../packages/frontend/src/store.ts#L109) |
| `pluginTokens` | 'deviceAccount' | H | 再認証/安全な資格情報管理。export禁止。logout失効 | [packages/frontend/src/store.ts:113](../../packages/frontend/src/store.ts#L113) |
| `accountTokens` | 'device' | H | 再認証/安全な資格情報管理。export禁止。logout失効 | [packages/frontend/src/store.ts:117](../../packages/frontend/src/store.ts#L117) |
| `accountInfos` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:121](../../packages/frontend/src/store.ts#L121) |
| `enablePreferencesAutoCloudBackup` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:126](../../packages/frontend/src/store.ts#L126) |
| `showPreferencesAutoCloudBackupSuggestion` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:130](../../packages/frontend/src/store.ts#L130) |
| `showStoragePersistenceSuggestion` | 'device' | H | 既存Web値とscopeを保持。再起動/アカウント変更時を確認 | [packages/frontend/src/store.ts:134](../../packages/frontend/src/store.ts#L134) |

## ナビゲーション

メニューの表示条件・未読表示・リンク・actionの元の式はJSONに保持する。25項目は設定やMoreからも到達できるようにし、ネイティブタブに入らない項目を削除しない。

| ID | 元の移動先/操作 | 目標 | 出典 |
|---|---|---|---|
| `notifications` | '/my/notifications' | H | [packages/frontend/src/navbar.ts:30](../../packages/frontend/src/navbar.ts#L30) |
| `drive` | '/my/drive' | H | [packages/frontend/src/navbar.ts:38](../../packages/frontend/src/navbar.ts#L38) |
| `followRequests` | '/my/follow-requests' | H | [packages/frontend/src/navbar.ts:44](../../packages/frontend/src/navbar.ts#L44) |
| `explore` | '/explore' | H | [packages/frontend/src/navbar.ts:50](../../packages/frontend/src/navbar.ts#L50) |
| `announcements` | '/announcements' | H | [packages/frontend/src/navbar.ts:55](../../packages/frontend/src/navbar.ts#L55) |
| `search` | '/search' | H | [packages/frontend/src/navbar.ts:61](../../packages/frontend/src/navbar.ts#L61) |
| `lookup` | action（元式はJSON） | H | [packages/frontend/src/navbar.ts:66](../../packages/frontend/src/navbar.ts#L66) |
| `qr` | '/qr' | H | [packages/frontend/src/navbar.ts:73](../../packages/frontend/src/navbar.ts#L73) |
| `lists` | '/my/lists' | H | [packages/frontend/src/navbar.ts:79](../../packages/frontend/src/navbar.ts#L79) |
| `antennas` | '/my/antennas' | H | [packages/frontend/src/navbar.ts:85](../../packages/frontend/src/navbar.ts#L85) |
| `favorites` | '/my/favorites' | H | [packages/frontend/src/navbar.ts:91](../../packages/frontend/src/navbar.ts#L91) |
| `pages` | '/pages' | H | [packages/frontend/src/navbar.ts:97](../../packages/frontend/src/navbar.ts#L97) |
| `play` | '/play' | H | [packages/frontend/src/navbar.ts:102](../../packages/frontend/src/navbar.ts#L102) |
| `gallery` | '/gallery' | H | [packages/frontend/src/navbar.ts:107](../../packages/frontend/src/navbar.ts#L107) |
| `clips` | '/my/clips' | H | [packages/frontend/src/navbar.ts:112](../../packages/frontend/src/navbar.ts#L112) |
| `channels` | '/channels' | H | [packages/frontend/src/navbar.ts:118](../../packages/frontend/src/navbar.ts#L118) |
| `chat` | '/chat' | H | [packages/frontend/src/navbar.ts:123](../../packages/frontend/src/navbar.ts#L123) |
| `achievements` | '/my/achievements' | H | [packages/frontend/src/navbar.ts:130](../../packages/frontend/src/navbar.ts#L130) |
| `games` | '/games' | H | [packages/frontend/src/navbar.ts:136](../../packages/frontend/src/navbar.ts#L136) |
| `ui` | action（元式はJSON） | H | [packages/frontend/src/navbar.ts:141](../../packages/frontend/src/navbar.ts#L141) |
| `about` | action（元式はJSON） | H | [packages/frontend/src/navbar.ts:162](../../packages/frontend/src/navbar.ts#L162) |
| `tools` | action（元式はJSON） | H | [packages/frontend/src/navbar.ts:169](../../packages/frontend/src/navbar.ts#L169) |
| `reload` | action（元式はJSON） | H | [packages/frontend/src/navbar.ts:176](../../packages/frontend/src/navbar.ts#L176) |
| `profile` | `/@${$i?.username}` | H | [packages/frontend/src/navbar.ts:183](../../packages/frontend/src/navbar.ts#L183) |
| `cacheClear` | action（元式はJSON） | H | [packages/frontend/src/navbar.ts:189](../../packages/frontend/src/navbar.ts#L189) |

## 特別な起動経路

| prefix | 目標 | 確認 | 出典 |
|---|---|---|---|
| `/share` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |
| `/auth` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |
| `/miauth` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |
| `/oauth` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |
| `/signup-complete` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |
| `/verify-email` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |
| `/install-extensions` | W/H | 認証・共有・拡張導入のパラメーター/取消/復帰を保持 | [packages/frontend/src/_boot_.ts:19](../../packages/frontend/src/_boot_.ts#L19) |

## ページVue全ファイル

ルートに直接現れないファイルも、ダイアログや子画面として使用される。未参照・不要とは断定しない。テスト/Storyの6ファイルを除く259件を列挙した。初期はWを維持し、最終的な方式は機能表と呼び出し元に従う。

| ファイル | 直接ルート参照 | 初期 |
|---|---|---|
| [packages/frontend/src/pages/_empty_.vue:1](../../packages/frontend/src/pages/_empty_.vue#L1) | route-049, route-136 | W |
| [packages/frontend/src/pages/_error_.vue:1](../../packages/frontend/src/pages/_error_.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/_loading_.vue:1](../../packages/frontend/src/pages/_loading_.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/about-misskey.vue:1](../../packages/frontend/src/pages/about-misskey.vue#L1) | route-057 | W |
| [packages/frontend/src/pages/about.emojis.vue:1](../../packages/frontend/src/pages/about.emojis.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/about.federation.vue:1](../../packages/frontend/src/pages/about.federation.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/about.overview.vue:1](../../packages/frontend/src/pages/about.overview.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/about.vue:1](../../packages/frontend/src/pages/about.vue#L1) | route-055 | W |
| [packages/frontend/src/pages/achievements.vue:1](../../packages/frontend/src/pages/achievements.vue#L1) | route-139 | W |
| [packages/frontend/src/pages/admin-file.chat.vue:1](../../packages/frontend/src/pages/admin-file.chat.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin-file.root.vue:1](../../packages/frontend/src/pages/admin-file.root.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin-file.vue:1](../../packages/frontend/src/pages/admin-file.vue#L1) | route-102 | W |
| [packages/frontend/src/pages/admin-user.vue:1](../../packages/frontend/src/pages/admin-user.vue#L1) | route-101 | W |
| [packages/frontend/src/pages/admin/RolesEditorFormula.vue:1](../../packages/frontend/src/pages/admin/RolesEditorFormula.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/abuse-report/notification-recipient.editor.vue:1](../../packages/frontend/src/pages/admin/abuse-report/notification-recipient.editor.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/abuse-report/notification-recipient.item.vue:1](../../packages/frontend/src/pages/admin/abuse-report/notification-recipient.item.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/abuse-report/notification-recipient.vue:1](../../packages/frontend/src/pages/admin/abuse-report/notification-recipient.vue#L1) | route-134 | W |
| [packages/frontend/src/pages/admin/abuses.vue:1](../../packages/frontend/src/pages/admin/abuses.vue#L1) | route-121 | W |
| [packages/frontend/src/pages/admin/ads.vue:1](../../packages/frontend/src/pages/admin/ads.vue#L1) | route-115 | W |
| [packages/frontend/src/pages/admin/announcements.vue:1](../../packages/frontend/src/pages/admin/announcements.vue#L1) | route-114 | W |
| [packages/frontend/src/pages/admin/auto-translation.vue:1](../../packages/frontend/src/pages/admin/auto-translation.vue#L1) | route-131 | W |
| [packages/frontend/src/pages/admin/bot-protection.vue:1](../../packages/frontend/src/pages/admin/bot-protection.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/branding.vue:1](../../packages/frontend/src/pages/admin/branding.vue#L1) | route-124 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager.local.list.logs.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager.local.list.logs.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager.local.list.search.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager.local.list.search.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager.local.list.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager.local.list.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager.logs.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager.logs.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager.register.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager.register.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager.remote.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager.remote.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/custom-emojis-manager2.vue:1](../../packages/frontend/src/pages/admin/custom-emojis-manager2.vue#L1) | route-107 | W |
| [packages/frontend/src/pages/admin/database.vue:1](../../packages/frontend/src/pages/admin/database.vue#L1) | route-120 | W |
| [packages/frontend/src/pages/admin/email-settings.vue:1](../../packages/frontend/src/pages/admin/email-settings.vue#L1) | route-126 | W |
| [packages/frontend/src/pages/admin/external-services.vue:1](../../packages/frontend/src/pages/admin/external-services.vue#L1) | route-130 | W |
| [packages/frontend/src/pages/admin/federation-job-queue.chart.chart.vue:1](../../packages/frontend/src/pages/admin/federation-job-queue.chart.chart.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/federation-job-queue.chart.vue:1](../../packages/frontend/src/pages/admin/federation-job-queue.chart.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/federation-job-queue.vue:1](../../packages/frontend/src/pages/admin/federation-job-queue.vue#L1) | route-110 | W |
| [packages/frontend/src/pages/admin/federation.vue:1](../../packages/frontend/src/pages/admin/federation.vue#L1) | route-113 | W |
| [packages/frontend/src/pages/admin/files.vue:1](../../packages/frontend/src/pages/admin/files.vue#L1) | route-112 | W |
| [packages/frontend/src/pages/admin/gridspace.vue:1](../../packages/frontend/src/pages/admin/gridspace.vue#L1) | route-109 | W |
| [packages/frontend/src/pages/admin/index.vue:1](../../packages/frontend/src/pages/admin/index.vue#L1) | route-103 | W |
| [packages/frontend/src/pages/admin/invites.vue:1](../../packages/frontend/src/pages/admin/invites.vue#L1) | route-133 | W |
| [packages/frontend/src/pages/admin/job-queue.chart.vue:1](../../packages/frontend/src/pages/admin/job-queue.chart.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/job-queue.job.vue:1](../../packages/frontend/src/pages/admin/job-queue.job.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/job-queue.vue:1](../../packages/frontend/src/pages/admin/job-queue.vue#L1) | route-111 | W |
| [packages/frontend/src/pages/admin/moderation.vue:1](../../packages/frontend/src/pages/admin/moderation.vue#L1) | route-125 | W |
| [packages/frontend/src/pages/admin/modlog.ModLog.vue:1](../../packages/frontend/src/pages/admin/modlog.ModLog.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/modlog.vue:1](../../packages/frontend/src/pages/admin/modlog.vue#L1) | route-122 | W |
| [packages/frontend/src/pages/admin/object-storage.vue:1](../../packages/frontend/src/pages/admin/object-storage.vue#L1) | route-127 | W |
| [packages/frontend/src/pages/admin/overview.active-users.vue:1](../../packages/frontend/src/pages/admin/overview.active-users.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.ap-requests.vue:1](../../packages/frontend/src/pages/admin/overview.ap-requests.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.federation.vue:1](../../packages/frontend/src/pages/admin/overview.federation.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.heatmap.vue:1](../../packages/frontend/src/pages/admin/overview.heatmap.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.instances.vue:1](../../packages/frontend/src/pages/admin/overview.instances.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.moderators.vue:1](../../packages/frontend/src/pages/admin/overview.moderators.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.pie.vue:1](../../packages/frontend/src/pages/admin/overview.pie.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.queue.chart.vue:1](../../packages/frontend/src/pages/admin/overview.queue.chart.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.queue.vue:1](../../packages/frontend/src/pages/admin/overview.queue.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.retention.vue:1](../../packages/frontend/src/pages/admin/overview.retention.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.stats.vue:1](../../packages/frontend/src/pages/admin/overview.stats.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.users.vue:1](../../packages/frontend/src/pages/admin/overview.users.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/overview.vue:1](../../packages/frontend/src/pages/admin/overview.vue#L1) | route-104 | W |
| [packages/frontend/src/pages/admin/performance.vue:1](../../packages/frontend/src/pages/admin/performance.vue#L1) | route-132 | W |
| [packages/frontend/src/pages/admin/relays.vue:1](../../packages/frontend/src/pages/admin/relays.vue#L1) | route-129 | W |
| [packages/frontend/src/pages/admin/roles.edit.vue:1](../../packages/frontend/src/pages/admin/roles.edit.vue#L1) | route-116, route-117 | W |
| [packages/frontend/src/pages/admin/roles.editor.vue:1](../../packages/frontend/src/pages/admin/roles.editor.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/roles.policy-editor.folder.vue:1](../../packages/frontend/src/pages/admin/roles.policy-editor.folder.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/roles.policy-editor.vue:1](../../packages/frontend/src/pages/admin/roles.policy-editor.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/roles.role.vue:1](../../packages/frontend/src/pages/admin/roles.role.vue#L1) | route-118 | W |
| [packages/frontend/src/pages/admin/roles.vue:1](../../packages/frontend/src/pages/admin/roles.vue#L1) | route-119 | W |
| [packages/frontend/src/pages/admin/security.vue:1](../../packages/frontend/src/pages/admin/security.vue#L1) | route-128 | W |
| [packages/frontend/src/pages/admin/server-rules.vue:1](../../packages/frontend/src/pages/admin/server-rules.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/settings.vue:1](../../packages/frontend/src/pages/admin/settings.vue#L1) | route-123 | W |
| [packages/frontend/src/pages/admin/system-webhook.item.vue:1](../../packages/frontend/src/pages/admin/system-webhook.item.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/admin/system-webhook.vue:1](../../packages/frontend/src/pages/admin/system-webhook.vue#L1) | route-135 | W |
| [packages/frontend/src/pages/admin/users.vue:1](../../packages/frontend/src/pages/admin/users.vue#L1) | route-105 | W |
| [packages/frontend/src/pages/ads.vue:1](../../packages/frontend/src/pages/ads.vue#L1) | route-059 | W |
| [packages/frontend/src/pages/announcement.vue:1](../../packages/frontend/src/pages/announcement.vue#L1) | route-054 | W |
| [packages/frontend/src/pages/announcements.vue:1](../../packages/frontend/src/pages/announcements.vue#L1) | route-053 | W |
| [packages/frontend/src/pages/antenna-timeline.vue:1](../../packages/frontend/src/pages/antenna-timeline.vue#L1) | route-151 | W |
| [packages/frontend/src/pages/api-console.vue:1](../../packages/frontend/src/pages/api-console.vue#L1) | route-071 | W |
| [packages/frontend/src/pages/auth.form.vue:1](../../packages/frontend/src/pages/auth.form.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/auth.vue:1](../../packages/frontend/src/pages/auth.vue#L1) | route-074 | W |
| [packages/frontend/src/pages/avatar-decoration-edit-dialog.vue:1](../../packages/frontend/src/pages/avatar-decoration-edit-dialog.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/avatar-decorations.vue:1](../../packages/frontend/src/pages/avatar-decorations.vue#L1) | route-095, route-108 | W |
| [packages/frontend/src/pages/avatar-walk.vue:1](../../packages/frontend/src/pages/avatar-walk.vue#L1) | route-154 | W |
| [packages/frontend/src/pages/channel-editor.vue:1](../../packages/frontend/src/pages/channel-editor.vue#L1) | route-090, route-091 | W |
| [packages/frontend/src/pages/channel.vue:1](../../packages/frontend/src/pages/channel.vue#L1) | route-092 | W |
| [packages/frontend/src/pages/channels.vue:1](../../packages/frontend/src/pages/channels.vue#L1) | route-093 | W |
| [packages/frontend/src/pages/chat/XMessage.vue:1](../../packages/frontend/src/pages/chat/XMessage.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/XRoom.vue:1](../../packages/frontend/src/pages/chat/XRoom.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/home.home.vue:1](../../packages/frontend/src/pages/chat/home.home.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/home.invitations.vue:1](../../packages/frontend/src/pages/chat/home.invitations.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/home.joiningRooms.vue:1](../../packages/frontend/src/pages/chat/home.joiningRooms.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/home.ownedRooms.vue:1](../../packages/frontend/src/pages/chat/home.ownedRooms.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/home.vue:1](../../packages/frontend/src/pages/chat/home.vue#L1) | route-012 | W |
| [packages/frontend/src/pages/chat/message.vue:1](../../packages/frontend/src/pages/chat/message.vue#L1) | route-015 | W |
| [packages/frontend/src/pages/chat/room.form.vue:1](../../packages/frontend/src/pages/chat/room.form.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/room.info.vue:1](../../packages/frontend/src/pages/chat/room.info.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/room.members.vue:1](../../packages/frontend/src/pages/chat/room.members.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/room.search.vue:1](../../packages/frontend/src/pages/chat/room.search.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/chat/room.vue:1](../../packages/frontend/src/pages/chat/room.vue#L1) | route-013, route-014 | W |
| [packages/frontend/src/pages/clicker.vue:1](../../packages/frontend/src/pages/clicker.vue#L1) | route-152 | W |
| [packages/frontend/src/pages/clip.vue:1](../../packages/frontend/src/pages/clip.vue#L1) | route-011 | W |
| [packages/frontend/src/pages/contact.vue:1](../../packages/frontend/src/pages/contact.vue#L1) | route-056 | W |
| [packages/frontend/src/pages/custom-emojis-manager.vue:1](../../packages/frontend/src/pages/custom-emojis-manager.vue#L1) | route-094, route-106 | W |
| [packages/frontend/src/pages/debug.vue:1](../../packages/frontend/src/pages/debug.vue#L1) | route-159 | W |
| [packages/frontend/src/pages/drive.file.info.vue:1](../../packages/frontend/src/pages/drive.file.info.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/drive.file.notes.vue:1](../../packages/frontend/src/pages/drive.file.notes.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/drive.file.vue:1](../../packages/frontend/src/pages/drive.file.vue#L1) | route-142 | W |
| [packages/frontend/src/pages/drive.vue:1](../../packages/frontend/src/pages/drive.vue#L1) | route-140, route-141 | W |
| [packages/frontend/src/pages/drop-and-fusion.game.vue:1](../../packages/frontend/src/pages/drop-and-fusion.game.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/drop-and-fusion.vue:1](../../packages/frontend/src/pages/drop-and-fusion.vue#L1) | route-155 | W |
| [packages/frontend/src/pages/emoji-edit-dialog.vue:1](../../packages/frontend/src/pages/emoji-edit-dialog.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/emojis.emoji.vue:1](../../packages/frontend/src/pages/emojis.emoji.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/explore.featured.vue:1](../../packages/frontend/src/pages/explore.featured.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/explore.roles.vue:1](../../packages/frontend/src/pages/explore.roles.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/explore.users.vue:1](../../packages/frontend/src/pages/explore.users.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/explore.vue:1](../../packages/frontend/src/pages/explore.vue#L1) | route-063 | W |
| [packages/frontend/src/pages/favorites.vue:1](../../packages/frontend/src/pages/favorites.vue#L1) | route-138 | W |
| [packages/frontend/src/pages/flash/doom.vue:1](../../packages/frontend/src/pages/flash/doom.vue#L1) | route-083 | W |
| [packages/frontend/src/pages/flash/flash-edit.vue:1](../../packages/frontend/src/pages/flash/flash-edit.vue#L1) | route-081, route-082 | W |
| [packages/frontend/src/pages/flash/flash-index.vue:1](../../packages/frontend/src/pages/flash/flash-index.vue#L1) | route-085 | W |
| [packages/frontend/src/pages/flash/flash.vue:1](../../packages/frontend/src/pages/flash/flash.vue#L1) | route-084 | W |
| [packages/frontend/src/pages/follow-requests.vue:1](../../packages/frontend/src/pages/follow-requests.vue#L1) | route-143 | W |
| [packages/frontend/src/pages/gallery/edit.root.vue:1](../../packages/frontend/src/pages/gallery/edit.root.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/gallery/edit.vue:1](../../packages/frontend/src/pages/gallery/edit.vue#L1) | route-086, route-087 | W |
| [packages/frontend/src/pages/gallery/index.vue:1](../../packages/frontend/src/pages/gallery/index.vue#L1) | route-089 | W |
| [packages/frontend/src/pages/gallery/post.vue:1](../../packages/frontend/src/pages/gallery/post.vue#L1) | route-004, route-088 | W |
| [packages/frontend/src/pages/games.vue:1](../../packages/frontend/src/pages/games.vue#L1) | route-153 | W |
| [packages/frontend/src/pages/gridspace-channels.vue:1](../../packages/frontend/src/pages/gridspace-channels.vue#L1) | route-066 | W |
| [packages/frontend/src/pages/gridspace-private.vue:1](../../packages/frontend/src/pages/gridspace-private.vue#L1) | route-065 | W |
| [packages/frontend/src/pages/install-extensions.vue:1](../../packages/frontend/src/pages/install-extensions.vue#L1) | route-100 | W |
| [packages/frontend/src/pages/instance-info.vue:1](../../packages/frontend/src/pages/instance-info.vue#L1) | route-016 | W |
| [packages/frontend/src/pages/invite.vue:1](../../packages/frontend/src/pages/invite.vue#L1) | route-058 | W |
| [packages/frontend/src/pages/list.vue:1](../../packages/frontend/src/pages/list.vue#L1) | route-010 | W |
| [packages/frontend/src/pages/lookup.vue:1](../../packages/frontend/src/pages/lookup.vue#L1) | route-069 | W |
| [packages/frontend/src/pages/miauth.vue:1](../../packages/frontend/src/pages/miauth.vue#L1) | route-075 | W |
| [packages/frontend/src/pages/my-antennas/create.vue:1](../../packages/frontend/src/pages/my-antennas/create.vue#L1) | route-147 | W |
| [packages/frontend/src/pages/my-antennas/edit.vue:1](../../packages/frontend/src/pages/my-antennas/edit.vue#L1) | route-148 | W |
| [packages/frontend/src/pages/my-antennas/index.vue:1](../../packages/frontend/src/pages/my-antennas/index.vue#L1) | route-149 | W |
| [packages/frontend/src/pages/my-clips/index.vue:1](../../packages/frontend/src/pages/my-clips/index.vue#L1) | route-146 | W |
| [packages/frontend/src/pages/my-lists/index.vue:1](../../packages/frontend/src/pages/my-lists/index.vue#L1) | route-145 | W |
| [packages/frontend/src/pages/my-lists/list.vue:1](../../packages/frontend/src/pages/my-lists/list.vue#L1) | route-144 | W |
| [packages/frontend/src/pages/neos/direct-upload.vue:1](../../packages/frontend/src/pages/neos/direct-upload.vue#L1) | route-161 | W |
| [packages/frontend/src/pages/not-found.vue:1](../../packages/frontend/src/pages/not-found.vue#L1) | route-101, route-102, route-103, route-109, route-162 | W |
| [packages/frontend/src/pages/note.vue:1](../../packages/frontend/src/pages/note.vue#L1) | route-009 | W |
| [packages/frontend/src/pages/notifications.vue:1](../../packages/frontend/src/pages/notifications.vue#L1) | route-137 | W |
| [packages/frontend/src/pages/oauth.vue:1](../../packages/frontend/src/pages/oauth.vue#L1) | route-076 | W |
| [packages/frontend/src/pages/page-editor/els/page-editor.el.image.vue:1](../../packages/frontend/src/pages/page-editor/els/page-editor.el.image.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/page-editor/els/page-editor.el.note.vue:1](../../packages/frontend/src/pages/page-editor/els/page-editor.el.note.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/page-editor/els/page-editor.el.section.vue:1](../../packages/frontend/src/pages/page-editor/els/page-editor.el.section.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/page-editor/els/page-editor.el.text.vue:1](../../packages/frontend/src/pages/page-editor/els/page-editor.el.text.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/page-editor/page-editor.blocks.vue:1](../../packages/frontend/src/pages/page-editor/page-editor.blocks.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/page-editor/page-editor.container.vue:1](../../packages/frontend/src/pages/page-editor/page-editor.container.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/page-editor/page-editor.vue:1](../../packages/frontend/src/pages/page-editor/page-editor.vue#L1) | route-078, route-079 | W |
| [packages/frontend/src/pages/page.vue:1](../../packages/frontend/src/pages/page.vue#L1) | route-003, route-005 | W |
| [packages/frontend/src/pages/pages.vue:1](../../packages/frontend/src/pages/pages.vue#L1) | route-080 | W |
| [packages/frontend/src/pages/preview.vue:1](../../packages/frontend/src/pages/preview.vue#L1) | route-073 | W |
| [packages/frontend/src/pages/qr.read.raw-viewer.vue:1](../../packages/frontend/src/pages/qr.read.raw-viewer.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/qr.read.vue:1](../../packages/frontend/src/pages/qr.read.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/qr.show.vue:1](../../packages/frontend/src/pages/qr.show.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/qr.vue:1](../../packages/frontend/src/pages/qr.vue#L1) | route-158 | W |
| [packages/frontend/src/pages/registry.keys.vue:1](../../packages/frontend/src/pages/registry.keys.vue#L1) | route-096 | W |
| [packages/frontend/src/pages/registry.value.vue:1](../../packages/frontend/src/pages/registry.value.vue#L1) | route-097 | W |
| [packages/frontend/src/pages/registry.vue:1](../../packages/frontend/src/pages/registry.vue#L1) | route-098 | W |
| [packages/frontend/src/pages/reset-password.vue:1](../../packages/frontend/src/pages/reset-password.vue#L1) | route-050 | W |
| [packages/frontend/src/pages/reversi/game.board.vue:1](../../packages/frontend/src/pages/reversi/game.board.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/reversi/game.setting.vue:1](../../packages/frontend/src/pages/reversi/game.setting.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/reversi/game.vue:1](../../packages/frontend/src/pages/reversi/game.vue#L1) | route-157 | W |
| [packages/frontend/src/pages/reversi/index.vue:1](../../packages/frontend/src/pages/reversi/index.vue#L1) | route-156 | W |
| [packages/frontend/src/pages/role.vue:1](../../packages/frontend/src/pages/role.vue#L1) | route-061 | W |
| [packages/frontend/src/pages/scratchpad.vue:1](../../packages/frontend/src/pages/scratchpad.vue#L1) | route-072 | W |
| [packages/frontend/src/pages/search.community.vue:1](../../packages/frontend/src/pages/search.community.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/search.note.vue:1](../../packages/frontend/src/pages/search.note.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/search.user.vue:1](../../packages/frontend/src/pages/search.user.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/search.vue:1](../../packages/frontend/src/pages/search.vue#L1) | route-064 | W |
| [packages/frontend/src/pages/settings/2fa.qrdialog.vue:1](../../packages/frontend/src/pages/settings/2fa.qrdialog.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/2fa.vue:1](../../packages/frontend/src/pages/settings/2fa.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/account-data.vue:1](../../packages/frontend/src/pages/settings/account-data.vue#L1) | route-037 | W |
| [packages/frontend/src/pages/settings/accounts.vue:1](../../packages/frontend/src/pages/settings/accounts.vue#L1) | route-046 | W |
| [packages/frontend/src/pages/settings/apps.vue:1](../../packages/frontend/src/pages/settings/apps.vue#L1) | route-040 | W |
| [packages/frontend/src/pages/settings/auto-translation.vue:1](../../packages/frontend/src/pages/settings/auto-translation.vue#L1) | route-028 | W |
| [packages/frontend/src/pages/settings/avatar-decoration.decoration.vue:1](../../packages/frontend/src/pages/settings/avatar-decoration.decoration.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/avatar-decoration.dialog.vue:1](../../packages/frontend/src/pages/settings/avatar-decoration.dialog.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/avatar-decoration.vue:1](../../packages/frontend/src/pages/settings/avatar-decoration.vue#L1) | route-019 | W |
| [packages/frontend/src/pages/settings/connect.vue:1](../../packages/frontend/src/pages/settings/connect.vue#L1) | route-039 | W |
| [packages/frontend/src/pages/settings/custom-css.vue:1](../../packages/frontend/src/pages/settings/custom-css.vue#L1) | route-044 | W |
| [packages/frontend/src/pages/settings/deck.vue:1](../../packages/frontend/src/pages/settings/deck.vue#L1) | route-043 | W |
| [packages/frontend/src/pages/settings/drive-cleaner.vue:1](../../packages/frontend/src/pages/settings/drive-cleaner.vue#L1) | route-023 | W |
| [packages/frontend/src/pages/settings/drive.ImageFrameItem.vue:1](../../packages/frontend/src/pages/settings/drive.ImageFrameItem.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/drive.WatermarkItem.vue:1](../../packages/frontend/src/pages/settings/drive.WatermarkItem.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/drive.vue:1](../../packages/frontend/src/pages/settings/drive.vue#L1) | route-022 | W |
| [packages/frontend/src/pages/settings/email.vue:1](../../packages/frontend/src/pages/settings/email.vue#L1) | route-025 | W |
| [packages/frontend/src/pages/settings/emoji-palette.palette.vue:1](../../packages/frontend/src/pages/settings/emoji-palette.palette.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/emoji-palette.vue:1](../../packages/frontend/src/pages/settings/emoji-palette.vue#L1) | route-021 | W |
| [packages/frontend/src/pages/settings/gridspace.vue:1](../../packages/frontend/src/pages/settings/gridspace.vue#L1) | route-047 | W |
| [packages/frontend/src/pages/settings/index.vue:1](../../packages/frontend/src/pages/settings/index.vue#L1) | route-017 | W |
| [packages/frontend/src/pages/settings/migration.vue:1](../../packages/frontend/src/pages/settings/migration.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/mute-block.emoji-mute.vue:1](../../packages/frontend/src/pages/settings/mute-block.emoji-mute.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/mute-block.instance-mute.vue:1](../../packages/frontend/src/pages/settings/mute-block.instance-mute.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/mute-block.vue:1](../../packages/frontend/src/pages/settings/mute-block.vue#L1) | route-038 | W |
| [packages/frontend/src/pages/settings/mute-block.word-mute.vue:1](../../packages/frontend/src/pages/settings/mute-block.word-mute.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/navbar.vue:1](../../packages/frontend/src/pages/settings/navbar.vue#L1) | route-032 | W |
| [packages/frontend/src/pages/settings/notifications.notification-config.vue:1](../../packages/frontend/src/pages/settings/notifications.notification-config.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/notifications.vue:1](../../packages/frontend/src/pages/settings/notifications.vue#L1) | route-024 | W |
| [packages/frontend/src/pages/settings/other.vue:1](../../packages/frontend/src/pages/settings/other.vue#L1) | route-048 | W |
| [packages/frontend/src/pages/settings/plugin.install.vue:1](../../packages/frontend/src/pages/settings/plugin.install.vue#L1) | route-035 | W |
| [packages/frontend/src/pages/settings/plugin.vue:1](../../packages/frontend/src/pages/settings/plugin.vue#L1) | route-036 | W |
| [packages/frontend/src/pages/settings/preferences.vue:1](../../packages/frontend/src/pages/settings/preferences.vue#L1) | route-027 | W |
| [packages/frontend/src/pages/settings/privacy.vue:1](../../packages/frontend/src/pages/settings/privacy.vue#L1) | route-020 | W |
| [packages/frontend/src/pages/settings/profile.vue:1](../../packages/frontend/src/pages/settings/profile.vue#L1) | route-018 | W |
| [packages/frontend/src/pages/settings/profiles.vue:1](../../packages/frontend/src/pages/settings/profiles.vue#L1) | route-045 | W |
| [packages/frontend/src/pages/settings/security.vue:1](../../packages/frontend/src/pages/settings/security.vue#L1) | route-026 | W |
| [packages/frontend/src/pages/settings/sounds.sound.vue:1](../../packages/frontend/src/pages/settings/sounds.sound.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/sounds.vue:1](../../packages/frontend/src/pages/settings/sounds.vue#L1) | route-034 | W |
| [packages/frontend/src/pages/settings/statusbar.statusbar.vue:1](../../packages/frontend/src/pages/settings/statusbar.statusbar.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/settings/statusbar.vue:1](../../packages/frontend/src/pages/settings/statusbar.vue#L1) | route-033 | W |
| [packages/frontend/src/pages/settings/theme.install.vue:1](../../packages/frontend/src/pages/settings/theme.install.vue#L1) | route-029 | W |
| [packages/frontend/src/pages/settings/theme.manage.vue:1](../../packages/frontend/src/pages/settings/theme.manage.vue#L1) | route-030 | W |
| [packages/frontend/src/pages/settings/theme.vue:1](../../packages/frontend/src/pages/settings/theme.vue#L1) | route-031 | W |
| [packages/frontend/src/pages/settings/webhook.edit.vue:1](../../packages/frontend/src/pages/settings/webhook.edit.vue#L1) | route-041 | W |
| [packages/frontend/src/pages/settings/webhook.new.vue:1](../../packages/frontend/src/pages/settings/webhook.new.vue#L1) | route-042 | W |
| [packages/frontend/src/pages/share.vue:1](../../packages/frontend/src/pages/share.vue#L1) | route-070 | W |
| [packages/frontend/src/pages/signup-complete.vue:1](../../packages/frontend/src/pages/signup-complete.vue#L1) | route-051 | W |
| [packages/frontend/src/pages/tag.vue:1](../../packages/frontend/src/pages/tag.vue#L1) | route-077 | W |
| [packages/frontend/src/pages/theme-editor.vue:1](../../packages/frontend/src/pages/theme-editor.vue#L1) | route-060 | W |
| [packages/frontend/src/pages/timeline.vue:1](../../packages/frontend/src/pages/timeline.vue#L1) | route-001, route-002 | W |
| [packages/frontend/src/pages/user-list-timeline.vue:1](../../packages/frontend/src/pages/user-list-timeline.vue#L1) | route-150 | W |
| [packages/frontend/src/pages/user-tag.vue:1](../../packages/frontend/src/pages/user-tag.vue#L1) | route-062 | W |
| [packages/frontend/src/pages/user/achievements.vue:1](../../packages/frontend/src/pages/user/achievements.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/activity.following.vue:1](../../packages/frontend/src/pages/user/activity.following.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/activity.notes.vue:1](../../packages/frontend/src/pages/user/activity.notes.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/activity.pv.vue:1](../../packages/frontend/src/pages/user/activity.pv.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/activity.vue:1](../../packages/frontend/src/pages/user/activity.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/clips.vue:1](../../packages/frontend/src/pages/user/clips.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/files.vue:1](../../packages/frontend/src/pages/user/files.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/flashs.vue:1](../../packages/frontend/src/pages/user/flashs.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/follow-list.vue:1](../../packages/frontend/src/pages/user/follow-list.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/followers.vue:1](../../packages/frontend/src/pages/user/followers.vue#L1) | route-007 | W |
| [packages/frontend/src/pages/user/following.vue:1](../../packages/frontend/src/pages/user/following.vue#L1) | route-006 | W |
| [packages/frontend/src/pages/user/gallery.vue:1](../../packages/frontend/src/pages/user/gallery.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/home.vue:1](../../packages/frontend/src/pages/user/home.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/index.activity.vue:1](../../packages/frontend/src/pages/user/index.activity.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/index.files.vue:1](../../packages/frontend/src/pages/user/index.files.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/index.timeline.vue:1](../../packages/frontend/src/pages/user/index.timeline.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/index.vue:1](../../packages/frontend/src/pages/user/index.vue#L1) | route-008 | W |
| [packages/frontend/src/pages/user/linked-history.vue:1](../../packages/frontend/src/pages/user/linked-history.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/lists.vue:1](../../packages/frontend/src/pages/user/lists.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/notes.vue:1](../../packages/frontend/src/pages/user/notes.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/pages.vue:1](../../packages/frontend/src/pages/user/pages.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/raw.vue:1](../../packages/frontend/src/pages/user/raw.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/user/reactions.vue:1](../../packages/frontend/src/pages/user/reactions.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/verify-email.vue:1](../../packages/frontend/src/pages/verify-email.vue#L1) | route-052 | W |
| [packages/frontend/src/pages/welcome.entrance.classic.vue:1](../../packages/frontend/src/pages/welcome.entrance.classic.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/welcome.entrance.simple.vue:1](../../packages/frontend/src/pages/welcome.entrance.simple.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/welcome.setup.vue:1](../../packages/frontend/src/pages/welcome.setup.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/welcome.timeline.note.vue:1](../../packages/frontend/src/pages/welcome.timeline.note.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/welcome.timeline.vue:1](../../packages/frontend/src/pages/welcome.timeline.vue#L1) | 子/動的/補助。使用箇所を機能表で確認 | W |
| [packages/frontend/src/pages/welcome.vue:1](../../packages/frontend/src/pages/welcome.vue#L1) | route-001 | W |

## 再調査

```powershell
node plans/ios-native-parity/collect-source-inventory.mjs --root . --output "$env:TEMP/gridspace-ios-current-inventory.json"
```

基準JSONとの差分を確認する。新しいルート・ウィジェット・キー・ページは、未分類のままネイティブで処理せず、Wを残して機能表へ追記する。ソースハッシュが変わった既存機能も再調査する。抽出時はアプリコードを実行せず、設定値も評価せずに元の式のまま残す。
