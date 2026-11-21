# Multi Note implementation status

## Objective and accepted scope

Implement the accepted M1–M8 plan in both forks, test it, start isolated test servers through kokopi.me, and verify the user flows in a browser. The user confirmed kokopi.me after the original request said copilot.me.

Public channels keep their existing public URL and Drive behavior. Removing a placement removes its list, home route, pin and aggregate membership; it does not make the original private. D1–D5 remain deferred. No production deployment, push, PR or merge is requested.

## Latest requirement revision — 2026-11-21

The user removed Multi Note scheduling and post-creation placement addition/re-addition from the requirements, including future work. Necessary CW is supplied by the author and shared with the original note; automatic/mandatory/per-placement CW and special mixed-sensitivity selection rules are not required. A public channel must not be rejected solely because it is sensitive. Existing viewing preferences, authorization and moderation remain in force. The old D6 roadmap is withdrawn; a future non-public access model remains a separate D1 consideration.

The subsequent implementation removes sensitivity-only exclusions in both forks: destination selection, local transaction validation and packing, peer candidates/prepare/place/lookup/mirror chips, explicit channel timelines and pins, and page/deck entry points. Authors retain a single optional CW on the original. Actual profile discovery rules, block/mute/archive restrictions, external-Renote policy and moderation remain in force. The revised requirement is now implemented and validated; it is not an open gap.

Focused Astra review found an unlinked-author unified-profile query still using legacy `channelId`. Both forks now apply the same viewer-specific placement conditions as `users/notes` for list reads and rehydration. The reviewer confirmed resolution. The new public-host sensitivity runner passes 20/20 checks, including this profile matrix, both directions, CW preservation and absence, pins, guest actions, blocks, archive refusal and deletion. The existing 48-check runner also passes on the rebuilt servers. Browser tests verify three channel destinations plus the normal route with one author CW, and reverse sensitive-only posting without automatic CW.

## Combined channel picker — 2026-11-21

The user requested a styled category dropdown, favorites as the initial category, and a combined local/peer list without a server selector. Both forks now use the existing small button/popup-menu and search-input components. Local and peer candidates appear together, interleaved by their category order. Following the user's further correction, each candidate is one line with the channel name and an adjacent `ぐりすぺ` or `れぞらぶ` site chip. Selected destinations use the same compact labels. Long names are ellipsized while the site chip remains visible; tooltips retain the full name and origin. Same-name/same-ID channels on different origins remain independently selectable.

Each origin maintains its own page cursor, loading state and retry. A failed origin does not remove the successful origin's candidates or the selected destinations. Filter/account/capability changes discard stale responses. Empty favorites offer a search action. The site labels add two ja-JP keys, reversed for each fork's local/peer roles, and each fork regenerates its own i18n types and assets. No backend, public API schema or migration changed.

G's selected frontend suites pass 31/31 cases; R passes the corresponding 27 cases before the unchanged 4-case article renderer suite. Both final frontend builds and shipping checks pass. Full frontend typechecks remain BASELINE at 66 diagnostics in each fork, with no changed-file diagnostics; G's before/after diagnostic lines match exactly. The limited Vue review's only Minor finding, identifying the active category inside the menu to screen readers, was fixed with the existing in-use caption and verified by the reviewer.

The browser verified both origins' initial favorites and independent same-name selections, the styled menu's active caption, and search across both sites while retaining the selection. Disposable UI accounts were used; the previous `mn_ui_2111` browser accounts were restored and no post was submitted. Screenshots: `.config/multi-note-picker-favorites.jpg`, `.config/multi-note-picker-search.jpg`, `.config/multi-note-picker-reverse.jpg`.

The subsequent single-line refinement was also rebuilt and verified in both browsers, including correct local/peer site-name mapping and selected-chip labels. The same 31 G / 27 R near tests and both shipping checks pass; full frontend typechecks remain at 66 baseline diagnostics with none in the changed files. Latest screenshots: `.config/multi-note-inline-site-g.jpg`, `.config/multi-note-inline-site-r.jpg`.

The user then corrected the site-name spelling to `れぞらぶ`. Both ja-JP label values, test expectations and plans are corrected; each fork's i18n/frontend builds and six picker regression cases pass, as do both shipping checks. The live lab assets contain the corrected label; the earlier screenshots predate that spelling correction. Same-name `UI確認・雑談` / `UI確認・作品共有` pairs are independently created test channels on G and R, with different IDs. They are not duplicate rows of one channel; selection and deduplication continue to use origin plus channel ID. No fixture or user post was changed for the spelling correction.

The user also requested a single pagination control. Both forks now show one shared load-more button. One click advances every non-exhausted source and retries failed sources, preserving successful results and the selection. A healthy source with more pages keeps the load-more action available even if its peer stays offline. Once healthy sources are exhausted, the same control becomes a retry action for failures alone; it disappears when all pages are exhausted. In-flight requests disable the control to prevent duplicate page loads.

Both forks pass 32 near frontend cases, including 7 picker cases. The targeted Vue review caught an initial retry-priority path that prevented a healthy source from advancing during a peer outage; the corrected priority and regression pass, with no unresolved review finding. Both frontend builds and final shipping checks pass. G's full frontend typecheck retains the exact 66 baseline diagnostic lines and none in the changed files. No backend, locale, public API or migration changed for this pagination revision.

Browser verification from each site shows one button and 40 candidates (20 G plus 20 R) before one click, then 80 (40 G plus 40 R) after it. Both prior UI accounts were restored; no post or channel fixture was modified. Evidence: `.config/multi-note-unified-more-browser.json`, `.config/multi-note-unified-more-g.jpg`, `.config/multi-note-unified-more-r.jpg`.

Changelog candidate: Combine both sites' channel destinations and pagination in one picker with compact site-name chips.

## Ordinary shared mirror placement display — 2026-11-21

The user's existing `kk` post exposed a display gap: its origin showed two local channel placements, while the ordinary peer mirror had neither source-owned channel metadata nor a verified root marker. Both forks now resolve this metadata through a signed, read-only origin lookup, batched up to 100 source IDs. Existing mirrors are fixed on the next read without rewriting their stored note or reposting. The ActivityPub object and public API schemas are unchanged.

HTTP packing and WebSocket subscriber filtering use the same viewer-specific root confirmation. Source/receiver chips are merged without duplicate channels, with current names and removal state. Author visibility and channel-owner blocks/mutes still apply; an inaccessible source or malformed peer response never confirms a root. Quoted notes and their replies share a page-wide placement lookup, with related database reads batched by depth and cyclic quotes stopped.

Astra's targeted review found three issues during this fix: stale root classification in WebSocket messages, extra peer calls for nested references, and insufficient validation of peer placement UUIDs/owner URIs/duplicate channels. All three were fixed; the final targeted review found no unresolved Critical/Major issue in this scope.

The rebuilt G/R servers pass the new 16-check mirror suite, including real authenticated home WebSocket events in both directions, plus the existing 48 ordinary and 20 sensitivity checks. The harness waits for ActivityPub follow acceptance before opening a home subscription; the initial pre-acceptance subscription attempt received no post and is not counted as a passing run. Near tests pass 59 backend and 4 renderer cases; both backend source typechecks and final shipping checks pass. Broader baseline diagnostics remain as recorded in [validation](multi-note-validation.md).

In the browser, the unchanged G mirror `attcxa5ey3sg006h` now displays the normal route and both R channels from origin `attcxa5eys17005v`. Clicking Browser Channel One opens its peer channel page and shows that same existing post. Screenshot: `.config/multi-note-mirror-placements-kk.jpg`. No user post was edited or removed.

Changelog candidate: Fix missing channel destinations on ordinary shared mirrors between GridSpace and Resonite Love.

## Checkouts and baseline preservation

| Role | Worktree | Feature baseline |
| --- | --- | --- |
| R, implementation source | `C:/Users/neo/.codex/worktrees/resolove-multi-note/misskey` | `57ee8ed337c1bd4cc45c5db813802424270eded5` |
| G, integration target | `C:/Users/neo/.codex/worktrees/gridspace-multi-note/grid-space-misskey` | `9a15160548501114f17b1ffc112c674ded5980b8` |

Both checkouts are now on `feat/multi-note`. Their former planning branch history is preserved as `codex/multi-note-plan-base-20261121` in each repository. Untracked plans were retained. The user authorized local commits on 2026-11-21. Push remains outside the requested scope.

## Ownership

Implementation agents edit R only. The root agent reviews, integrates and transfers implementation differences to G, preserving fork-specific code.

| Agent | Responsibility |
| --- | --- |
| `/root` | Integration, cross-fork transfer, contracts, acceptance tests, browser verification and final checks |
| `astra_core_creation` | Models, migrations, repository/DI/module/endpoint registration, local placements, create/receipt/status, NoteCreateService, NoteEntityService, config/meta capability |
| `astra_implementation_contracts` | Shared distribution helpers, Query/Fanout/Search/Featured/Feed, ordinary timeline endpoints and streams, shared-note/history guards and parent import |
| `astra_peer_placements` | Remote placement models and service, peer transport/routes, target state and durable delivery, remove/retry and individual/account deletion hooks |
| `astra_guest_operations` | Guest replies, reactions, votes, uploads, deletion and notifications, private DTO/action adaptation |
| `astra_unified_timeline` | Local/peer collection and note-origin combinations, reference/cursor/merge/hydration, changes, pins and aggregation |
| `astra_multi_note_frontend` | Composer selection, chips, menus, draft/request recovery, frontend tests and ja-JP keys |
| `astra_remote_ui` | Local/peer channel and deck pages, delegated note detail/actions, canonical pins and conversation links |
| `astra_notifications` | Limited guest notification retrieval/read/count, producer adaptation and optional body-free invalidation |
| `astra_test_environment` | Isolated lab manifest/compose/setup, dependencies, test infrastructure and tunnel process management |
| `astra_multi_note_review` | Independent read-only backend API and implementation review during integration |

Shared registry/module/migration edits belong to core_creation. Other owners communicate their additions to that agent. No two agents should edit the same existing file without coordinating the boundary.

## Shared contract

- `MiNote.includeDefault: boolean | null`; null is legacy compatibility only. All updated creation paths assign a boolean.
- `MiNote.multiNoteKind: 'root' | 'conversation-reply' | null` and `multiNoteRootId: string | null` without a foreign key.
- Local entity `MiNoteChannelPlacement`, table `note_channel_placement`: UUID id, nullable noteId, channelId, canonicalUri, sortAt, active/removed/origin-deleted, optional removal metadata; unique noteId+channelId and channelId+canonicalUri.
- `MiNoteCreateReceipt`: userId+clientRequestId composite key, inputHash, canonicalUri, nullable noteId, deleted. No cascading loss of delivery state on account deletion.
- New create fields: includeDefault, channelIds, channelTargets `{origin, channelId}[]`, clientRequestId. Old channelId and new destination fields cannot be mixed. New fields apply to root channel posts; ordinary notes, replies, quotes and schedules retain their existing requests.
- `notes/create-status({clientRequestId})` returns `{status: 'missing' | 'created' | 'deleted', createdNote: Note | null}`. Check existing receipts before peer prepare.
- Optional packed fields: includeDefault, multiNoteKind, channelPlacements with origin/channelId/canonicalUri/name/color/state and optional placementId.
- Helper owner B provides `includesDefault`, `isConversationOnly`, `defaultNoteCondition`, `channelPlacementCondition` in `misc/note-distribution.ts`.
- Local service provides `activeLocalChannelIds(note)` and batched placement packing. Core and peer owners coordinate remote prepare/stage inside the original-note transaction.
- Runtime write feature defaults off via `config.multiNote.enabled`. Meta advertises features.multiNote and features.multiNotePeer. Existing reads/deletion delivery continue when writes are disabled.
- Local-only targets use the local write capability without depending on peer availability. Remote targets require peer/timeline capability on both servers. Receipt recovery is always independent of peer availability.
- Dedicated peer operations retain the existing private endpoints with `conversationUri` and separate `placementActorId` credentials. Dedicated deletion is `gridspace/delete-reply({canonicalUri,requestId})`.

## Isolated lab

| Role | URL | HTTP | PostgreSQL | Redis |
| --- | --- | --- | --- | --- |
| G | `https://multi-note-g-20261121.kokopi.me` | 13110 | 15532 | 16479 |
| R | `https://multi-note-r-20261121.kokopi.me` | 13111 | 25532 | 26479 |
| E, ordinary external peer | `https://multi-note-e-20261121.kokopi.me` | 13112 | 35532 | 36479 |

Compose project: `gridspace-multi-note`. New configs and secrets stay ignored. Do not reuse existing lab databases/volumes or stop unrelated processes. Use Node 26.13.1 and pnpm 12.17.0. Seed administrators and restrict registration/federation before opening tunnels. Record task-owned PIDs and logs without credentials.

## Gates and evidence

- [x] Latest bridge baselines selected; planning histories retained.
- [x] Public-channel scope and kokopi.me host confirmed.
- [x] Models, creation transaction and common API contracts implemented.
- [x] Ordinary distribution paths and old-data compatibility covered.
- [x] Bidirectional placement delivery, removal and deletion covered.
- [x] Replies, reactions, polls, attachments and notifications covered.
- [x] Unified timeline and composer integrated.
- [x] Implementation transferred to G and fork differences reviewed.
- [x] Targeted unit and integration tests passed.
- [x] New migrations passed up/down/up and schema-clean validation.
- [x] misskey-js regenerated and relevant type/build checks passed; broad baseline diagnostics are recorded separately.
- [x] Isolated G/R/E servers started and reachable through kokopi.me.
- [x] Browser tests verified normal+channels, channels-only, both directions, receipt recovery, actual two-tab draft preservation and conversations/actions. Deletion/retirement passed real HTTP checks.
- [x] Changed-file lint, SPDX and locale safety passed.
- [x] Write-disabled read/pin/deletion delivery smoke and final live reply-visibility label verified.
- [x] Revised requirement: remove categorical exclusion of public sensitive channels, preserve the author's shared CW and existing viewer filtering, and verify local/peer creation and read paths.

Implementation evidence below applies to R unless explicitly identified as G or public-lab verification. Final integration gates remain open.

## Initial integration checkpoint (superseded below)

- G/R dependencies installed with their required Node 26.13.1 and pnpm 12.17.0. Lockfiles are unchanged.
- Six new lab PostgreSQL/Redis containers are healthy and bound to loopback only.
- E is at `C:/Users/neo/.codex/worktrees/multi-note-external/misskey`, detached ordinary Misskey `b28be53907`. It uses its own Node 26.4.0 / pnpm 11.25.0, built and migrated successfully.
- E was seeded on loopback, registration disabled, federation restricted to G/R, and then exposed through strict host-key SSH. Its top/login render and public meta HTTP 200 were checked in Chrome. Screenshot: ignored G `.config/multi-note-e-public.png`.
- E foreground server session 13555, listener PID 36076; tunnel session 24176. Do not stop unrelated sessions.
- The environment agent's compound background launch was rejected by automatic review; it was replaced with a separate foreground session and separate readiness/seed operations. No host-key bypass was used.
- Lab helper: set `GRIDSPACE_LAB_PROFILE=multi-note` before dynamically importing `scripts/gridspace/lab.mjs`. Manifest `scripts/gridspace/multi-note-sites.json`; ignored repo list `.config/multi-note-repositories.json`.
- Lab commands: `node scripts/gridspace/multi-note-lab.mjs setup <repoR> <repoE>`, `seed`, `tunnel G|R|E`; runner `scripts/gridspace/run-lab.ps1` uses each checkout's ignored `gridspace-lab.yml`.
- B reports 7 suites / 42 tests plus its 44-file ESLint and whitespace checks passed, including temporary-table PostgreSQL tests. Full fanout and real Meilisearch validation remains.
- N reports its first 4 notification suites / 79 cases passed. Existing polling remains a fallback for optional body-free push invalidation.
- Composer and remote UI targeted tests are passing at intermediate revisions; final generated-type checks remain.
- Root's R backend dependency/workspace build passed, including misskey-reversi. Optional Nest Express resolution and ineffective-dynamic-import warnings occurred; the build exited 0.
- A reports local creation tests 49/49 and e2e bundle build passed. Concurrent receipt replay skips postNoteCreated, and placement packing uses batched hints.
- Root added `scripts/gridspace/test-multi-note.mjs` in G. Syntax check passed; it has NOT been run against G/R yet. Guest actions, deletion/retirement and external AP checks will be extended during integration.
- G/R app build/migrate/start, SDK generation, cross-fork transfer, integration acceptance, browser feature tests and final review are still pending.

## Intermediate integration follow-up, 2026-11-21

- A: backend source typecheck, 49 creation validator cases and 6 real HTTP E2E cases pass. New migrations pass down/up and schema check with zero pending DDL. SQL creation dispatch recovery includes receipt/deletion and concurrent replay regression tests.
- B: distribution tests cover SQL/Redis/WS projection of actual shared normal mirrors into legacy channel subsets, canonical URI aliases, and separate default/channel ranking. Additional 14 PostgreSQL/projection and 27 reaction tests pass. A reviewer subsequently found anonymous placement metadata in ordinary WS payloads; B is applying viewer-specific filtering.
- C: 57 protocol/DB cases pass, including one incoming rate allowance for six placements, deletion-before-place, terminal moderator removal, retry policy and batch viewer authorization. Canonical URI lookup partial index has been migration checked. Lab retirement tests are being added separately.
- D: guest reply/action/poll/media implementation and 117 earlier cases pass; final DTO follow-up adds 14 passing cases for unavailable placement checks. G lab guest HTTP acceptance module is ready but has not run.
- E/F2: unified reads, write-disabled read capability, normal-mirror read-only fallback and canonical pins implemented. F2 targeted validation is 129/130; one old gridspace-list-dispatch expectation also fails on unchanged R baseline. Pin keyboard reordering tests pass.
- N: notification tests pass (91 backend, 17 frontend) and atomic Redis notification receipt is verified. External ordinary AP acceptance module is in progress.
- F1: frozen original payload, cross-tab reservation/settlement lock and preservation of newer edits are implemented; five actual composer tests pass. Final handling of unequivocal first-request rejection and reviewer recheck remain.
- Independent API follow-up found WS metadata filtering and missing/repeated streaming dispatch risks. These are assigned to B and A; they are not being waived as deferred scope.
- SDK generation initially failed under TypeScript 6 development AST validation because openapi-typescript produces quoted enum identifiers inside unions. A is implementing a small generator compatibility fix and regression test. The mandatory final generator command has not passed yet.
- F2 owns baseline-aware R-to-G transfer, preserving fork timer/locale/API differences and skipping whole generated-file copies. B transferred ownership before any G implementation writes.
- Root added `test-multi-note.mjs` plus calls to isolated guest/external/retirement modules. Syntax check passes; public G/R acceptance and browser feature checks remain pending.
- Root opened E in the in-app browser and verified the disposable server and whitelist federation notice. This is environment evidence, not feature acceptance.
- Environment owner found R lab tables with no migration history, preserved them, and is moving only the dedicated R lab config to a fresh named DB. Manifest safeguards will explicitly match that name.

## Final integration evidence

- R-to-G transfer was checked across 189 allowed source/test/template paths. Fork-specific timers, router/Storybook/locale details and G-specific tests were preserved. SDK/i18n outputs were regenerated in G, not copied wholesale. The CI test template also enables Multi Note explicitly.
- Both mandatory SDK pipelines, source backend typechecks, current lab migration checks and complete changed-file shipping gates pass. G frontend unit validation is 153/153. G baseline frontend typecheck is 67 diagnostics, current 66, with no new diagnostic. A final backend test-fixture type comparison found four new fixture diagnostics and is correcting only those fixtures.
- Root ran the final public-host acceptance runner successfully: **48/48**. Earlier failures were test assumptions (an error-code matcher, G anonymous visitor restrictions on guest authors, and an external fixture username longer than 20 characters), corrected before the clean final run.
- Root browser verified default plus two local channels, dedicated home exclusion, both directions of cross-site posting, a shared poll/reaction/reply thread, and successful response-loss recovery with only a status lookup after reload. Two real tabs retained a newer edited draft through another tab's successful completion and reload; the posted original count is one and the newer draft was not sent.
- Browser testing caught a misleading followers-only label for a public conversation reply. R/G now use the prepared visibility; the three-case regression, final Vue review and G frontend suite pass. Latest bundles were rebuilt and app manifests refreshed. Final live verification remains.
- Detailed commands, environment and limitations are recorded in [multi-note-validation.md](multi-note-validation.md). Raw results, credentials and screenshots remain ignored `.config/` artifacts.
- Feature-stop validation passed in each direction and both configurations were restored: initial pin assertions, existing chips/reads/pins, refused new placements, two-way deletion, and capability restoration. Root finally reloaded the latest R bundle and verified the public conversation reply label/globe in the live form.
- Backend test-fixture audit corrected four introduced diagnostics in three test files in both forks. R clean baseline has 53 diagnostics, current 48, all remaining matched to baseline; G current has those 48 plus one unchanged G-only UrlPreviewService fixture. The corrected files pass 44 targeted cases in each fork. Broad test-fixture typechecks are BASELINE/limited evidence, not PASS.
- Final runtime after the sensitivity update: G server session 88197 / PID 84508, R session 59205 / PID 61184, E session 13555 / PID 36076. Existing SSH tunnel processes G 62636, R 41024 and E 63424 remain active. Credentials are local ignored fixtures; registration remains disabled. Existing user accounts and data were preserved. No commit, push, PR or production deployment was performed.

## Sensitivity update validation

- R local creation E2E: 9/9, dedicated PostgreSQL/Redis/HTTP, including unchanged author CW, no forced CW and archive/block refusal without a creation receipt.
- R peer placement DB: 15/15, both directions, sensitive candidates/prepare/place/lookup/mirror chips and retained moderation/mute/block checks.
- R timeline/distribution: 18/18, explicit channel/pin symmetry and unlinked unified-profile discovery rules, including rehydration.
- R composer suites: 8 suites, 56/56. R channel/deck component checks: 24/24. G selected component/utility regression: 7 suites, 54/54.
- Full runtime builds pass in both forks. G backend source typecheck passes. G frontend full typecheck retains 66 diagnostics and none in the changed sensitivity files, consistent with the recorded baseline. Both final shipping checks pass.
- API schemas and entities are unchanged; no new SDK contract or database migration is required. Each fork regenerates its own i18n types from ja-JP. The obsolete sensitive-destination refusal label is removed.
- Public-host commands: `node scripts/gridspace/test-multi-note-sensitive.mjs` (20/20) and `node scripts/gridspace/test-multi-note.mjs` (48/48). The new driver's initial limit of 100 was corrected to the existing API maximum of 50 before the clean final run; no application change was needed for that harness error.
- New ignored artifacts: `.config/multi-note-sensitive-results.json`, `.config/multi-note-sensitive-fixtures.json`, `.config/multi-note-sensitive-compose.jpg`, `.config/multi-note-sensitive-peer.jpg`, `.config/multi-note-sensitive-reverse.jpg`. The snapshot used for the fork-preserving transfer is ignored under `.config/multi-note-sensitive-snapshot/`.
