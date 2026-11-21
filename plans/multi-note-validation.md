# Multi Note validation — 2026-11-21

Implementation is maintained on `feat/multi-note` in both feature worktrees. The user authorized local commits on 2026-11-21. No production deployment, push or PR was performed.

## Channel color bands — 2026-11-21

Restored the left color band for Multi Note in both clients. The existing narrow bar is divided vertically into at most three distinct colors from active placements. Channel origin and ID define a stable order across originals, mirrors and delegated views. Hexadecimal case and shorthand normalize before deduplication. Pending, removed, failed, unavailable and colorless placements contribute no color. Legacy channel posts retain one color. Timeline, detailed and scoped reference cards use the shared renderer; native hidden notes do not forward their placement colors.

- **PASS:** The three nearest frontend suites pass **31 cases per fork**, covering legacy rendering, native/mirror/detail/delegated/reference propagation, three-color cap, duplicate normalization, reordered API rows and placement updates/removal. Both changed-file lint/SPDX/locale checks and independent Vue review pass.
- **BASELINE:** Full frontend typecheck remains at exactly **63 pre-existing diagnostics per fork**. Normalizing diagnostic locations produces the same complete messages as the preceding integration revision; comparison evidence is `.config/multi-note-channel-colors-types-comparison.json`. No new type diagnostic remains.
- **PASS:** Both frontend and asset builds and task app restarts completed. Public HTML serves the final bundles G `nXfLIZWlg-DhrTidsv.js` and R `hHdd32NwJ-YDCHQ-JQ.js`. No backend/API/schema/locale input changed, so SDK generation and migrations were not needed for this change.
- **PASS:** Four new fixture channels and seven original notes were used without changing existing posts or channels. Browser checks confirm G's timeline shows one, two and capped three-color bars; G detail, the R mirror and R guest conversation show the same red/blue/green selection for four active colors. R native legacy/two/four cases show one/two/three colors. The detailed bar stays 5px wide and its three segments have equal heights to pixel rounding. Browser accounts remained `mn_ui_2111`.

Private fixtures and build/test logs are under `.config/multi-note-channel-colors-*`. Screenshots include `g-detail.jpg`, `g-timeline.jpg`, `r-mirror.jpg` and `r-guest.jpg` with that prefix. The R guest screenshot cleanly shows the three-color band. Full frontend tests were not rerun for this visual-only change; the nearest suites, full type comparison, builds and real browser surfaces were used instead.

Changelog candidate: Display up to three active channel colors in the note's left band.

## Production integration — 2026-11-21

Integrated the production tags `2026.11.0-grid-space.31.72` (`003b639fd4`) and `2026.11.0-resonite-love.31.71` (`bb8fdb38a3`) into the two feature branches. The production APIs still reported those versions at the final recheck. Both pre-merge feature heads remain available as backup branches. [Integration record](multi-note-production-integration.md) and [independent compatibility audit](multi-note-production-feature-audit.md) describe the seven cross-feature regressions and their fixes.

- **PASS:** Full frontend suites: G **740 tests / 91 files**, R **706 / 87**. G's broader backend run passed **561 / 55**. Isolated PostgreSQL/Redis E2E passed **17 cases on each fork**, including relay opt-out, follower and relay queue separation, durable replay, canonical source normalization and a destination archive race held across insertion.
- **PASS:** Both full SDK generation pipelines, backend source typechecks, full builds, final frontend/asset builds, changed-file lint, SPDX and locale safety. G's final shipping wrapper exceeded Windows' command-length limit for the 174 backend paths; all other packages passed in the wrapper, and the same 174 paths were linted successfully from the backend package root in batches of 40. Evidence: `.config/multi-note-production-{shipping-final,backend-lint-batches}.log`. R's wrapper passed directly. No repository-wide lint success is claimed.
- **BASELINE:** Fresh full frontend typechecks have **63 diagnostics in each fork**, against **65** from independent frozen-lockfile reconstructions of the exact production commits. There are zero new diagnostics and two resolved diagnostics. Sixty-one messages match exactly; two existing WidgetZou visibility errors differ only in the SDK type's abbreviated field count. The final reset fix was typechecked again in both forks. Full frontend typecheck is not reported as PASS.
- **PASS:** Four PostgreSQL archives were restored independently and their table/migration/user/note/channel counts matched. Each fork's four production migrations passed up/down/up on a disposable restore. Forward migration of the existing lab databases produced G **380** and R **379** history entries; both have **zero pending DDL**. Published migration blobs match the production tags. No migration was added by the integration fixes.
- **PASS:** Public-host checks total **141**: `test-multi-note-production.mjs` **57**, existing acceptance **48**, sensitive channels **20**, and mirror placements with real WebSocket delivery **16**. They verify both directions, actual E follower delivery and ActivityPub audiences, persisted delivery flags, all five scoped reference actions, cross-server favorite destinations and single receipt replay, source visibility after removal/block/deletion, clips and emoji sync. Relay exclusion itself is asserted directly in the isolated queue E2E; external follower arrival alone is not used to prove relay exclusion.

The four completed live result records are `.config/multi-note-production-d1e872b9e7.json`, `multi-note-acceptance-results.json` (`0a7a50434e`), `multi-note-sensitive-results.json` (`498d80c6dd`) and `multi-note-mirror-placements-results.json` (`fb19b9f2`). Each has completed=true and only passing rows. Original user source `attcxa5eys17005v` and mirror `attcxa5ey3sg006h` retain their two source placements.

Browser tests used the existing disposable picker accounts and then restored `mn_ui_2111` on both origins. They verified the three delivery options, combined favorites and origin chips, G default-plus-local-plus-peer posting with relay opt-out, R channel-only posting absent from the ordinary home, canonical peer reading, N on a peer placement channel, the five renote actions and actual scoped quote submission.

The final browser check exposed a reset interaction absent from the original 141 server checks: the old signed upper bound excluded a newly placed quote. The client now distinguishes a fresh reset from expired-cursor restoration, reads the current head through the old tail, and keeps off-top queueing and authorization checks. After both client rebuilds and app restarts, the open G view of an R channel received the new-note banner. Releasing it displayed the new scoped quote plus all three prior rows without page reload. The quote preview remained readable. Final client and regression-test files match across forks; server/API/migration code did not change in this last fix.

Screenshots are ignored local evidence: `.config/multi-note-production-{g-delivery,r-delivery,g-post,reference-menu,live-quote}.jpg`. Final client entries are G `nXfLIZWlg-vItnXTnq.js` and R `hHdd32NwJ-DTciJ1fj.js`; public HTML and asset HTTP 200 were verified. G, R and E remain running at their existing kokopi.me URLs.

The frontend type baseline above remains unresolved. The checks do not claim exhaustive testing of every production feature or deferred D1–D5 behavior. GridSpace-only XRift/URL preview tests passed separately (49 cases), while a live upstream XRift API success was not required or claimed.

Changelog candidate: Integrate production changes with Multi Note, preserving delivery modes, channel references and live timeline refresh.

## Scope and review

One canonical original can use the default distribution route, multiple local/peer channels, or channel routes alone. Existing public-channel viewing and Drive URL rules apply. The required/deferred boundary is [M1–M8 / D1–D5](multi-note-placement-protocol.md).

### Requirement revision after the recorded test run

On 2026-11-21 the user removed scheduling and post-creation placement addition/re-addition from Multi Note's requirements and future roadmap. Authors supply necessary CW on the shared original; automatic/mandatory/per-placement CW and special mixed-sensitivity selection rules are not required. Public sensitive channels must not be categorically excluded, while existing viewing preferences, permissions and moderation remain applicable. Old D6 is withdrawn.

That documentation-only revision identified sensitivity-only exclusions. The subsequent implementation removes them in both forks and validates public sensitive/non-sensitive placements with one unchanged author-supplied CW. The 48-check ordinary regression suite has been rerun successfully on the updated servers; the new sensitivity suite adds 20 passing real-HTTP checks. This implementation/validation gap is closed.

### Sensitive-channel implementation and tests

The local and peer destination APIs, composer validation, transaction checks, active placement metadata, normal mirror chips, explicit channel/pin reads and channel/deck entry points now support public sensitive channels. Existing viewer preferences and profile-discovery conditions remain applicable. CW is optional and is neither created nor changed by placement logic.

Focused Astra review caught an unlinked-author unified-profile path using only the old `channelId`. Both forks now use the same placement-aware profile/default conditions as `users/notes` for list and rehydration. The targeted reviewer found no unresolved issue after the fix.

- `node scripts/gridspace/test-multi-note-sensitive.mjs`: **20/20 PASS**, G and R in both directions. It verifies candidates, ordinary/sensitive local mixes, all four placements with both viewer origins and pins, shared normal mirrors and legacy APIs, guest reply/reaction/vote, optional CW, profile visibility for unlinked authors, blocked channel-owner metadata, archived transaction rejection and deletion of all routes/pins.
- `node scripts/gridspace/test-multi-note.mjs`: **48/48 PASS again** on the same rebuilt servers.
- R local creation E2E: **9/9**; peer placement PostgreSQL tests: **15/15**; timeline/profile SQL tests: **18/18**; composer tests: **56/56**; channel/deck tests: **24/24**.
- G selected frontend regression: **54/54** in 7 suites. Both runtime builds, G backend source typecheck and both final shipping checks pass. G frontend typecheck still has **66 baseline diagnostics**, with none in the changed sensitivity files.
- API schemas and entities are unchanged. No new SDK schema generation or migration is required. Each fork's i18n declarations were regenerated from its own ja-JP source, preserving fork-specific keys.

The in-app browser selected the normal route, one ordinary channel and both origins' sensitive channels, entered one CW, and posted successfully. The peer channel initially displayed that CW with the normal reveal control and then the same body after reveal. Reverse posting from a sensitive channel to the peer sensitive channel succeeded without CW and produced no automatic CW. Screenshot artifacts: `.config/multi-note-sensitive-compose.jpg`, `.config/multi-note-sensitive-peer.jpg` and `.config/multi-note-sensitive-reverse.jpg`.

The [backend review](multi-note-implementation-astra-review.md) and [frontend review](multi-note-frontend-astra-review.md) preserve initial findings and their resolutions. The final targeted backend review found no unresolved Critical/Major issue in the reviewed fixes. The two recorded limitations are the need for a URI-aware editor to remove peer URI pins and a narrow crash window that can retain Redis stream deduplication keys without expiry.

## Ordinary shared mirror placement regression

Both forks now obtain source-owned channel metadata and verify the root marker on ordinary shared mirrors, including existing null-kind mirror rows. The origin read is HMAC authenticated, limited to unique batches of 100 IDs and 8 KiB request bodies, and returns no post body. It remains available when new placements are disabled. No ActivityPub object, public API schema, entity or migration changed in this fix.

- `node scripts/gridspace/test-multi-note-mirror-placements.mjs`: **16/16 PASS** against the public G/R hosts. Both directions cover `notes/show`, ordinary home/global HTTP timelines and actual authenticated home WebSocket events, two source-only chips, source/receiver chip deduplication, ordinary non-root controls, nested Renotes, current name/color/removal state, viewer and origin channel-owner blocks/mutes, and roots with no remaining channels. Setup explicitly waits for remote follow acceptance before opening the subscription. An earlier attempt without that wait received no home event and failed; the final run includes the corrected prerequisite.
- `node scripts/gridspace/test-multi-note.mjs`: **48/48 PASS again** after the mirror fix.
- `node scripts/gridspace/test-multi-note-sensitive.mjs`: **20/20 PASS again** after the mirror fix.
- G near backend suites: **58/58** in placement DB/protocol, peer server and WebSocket filtering, plus **1/1** packer regression covering joined/unjoined nested references, shared origins and cyclic quotes. The corresponding R suites pass. Actual note/detail renderer tests pass **4/4** in both forks.
- Both backend source typechecks and runtime builds pass. Both `check-shipping.mjs --base <bridge-baseline>` runs pass changed-file lint, SPDX and locale safety. The new standalone test runner passes `node --check`. No SDK generation or migration was required because their inputs did not change.
- The final targeted Astra review confirms the three intermediate findings are resolved: subscriber-specific root classification, nested page batching and strict peer response validation. No unresolved Critical/Major remains in that reviewed scope.

The original user post was preserved: R original `attcxa5eys17005v` and G mirror `attcxa5ey3sg006h` return the same two active R placements. The browser reload of the G mirror visibly shows the normal route, Browser Channel One and Browser Channel Two. Following a chip opens the expected peer channel with the same `kk` post. Screenshot: `.config/multi-note-mirror-placements-kk.jpg`. Fixtures and final result rows are ignored under `.config/multi-note-mirror-placements-{fixtures,results}.json`.

## Combined favorites picker

The picker now starts with favorites from both origins in one list, with no server selector. It uses existing themed button/menu and search-input components. After the user's next correction, each channel is displayed on one line with an adjacent `ぐりすぺ` or `れぞらぶ` site chip, including selected destinations. Full names and origins remain available in tooltips. Both sources keep separate cursors and retry state. Existing public/sensitive-channel selection and original-note behavior are unchanged; no backend or public schema changed.

- G: `pnpm --filter frontend test test/unit/note-destinations.test.ts test/unit/multi-note-composer.test.ts test/unit/multi-note.test.ts test/unit/note-article.test.ts`: **31/31 PASS**. R's three corresponding picker/composer/state suites pass **27/27**. The picker cases include both favorites, independent same-ID choices, combined search, per-origin pagination/retry/deduplication, stale filter/account/capability responses and disabled/peer-disabled operation.
- Both final frontend builds pass, and both task-owned apps were restarted for their cached asset manifests. Both final shipping checks pass lint, SPDX and locale safety.
- Full frontend typecheck is **BASELINE**, 66 diagnostics in each fork and no diagnostics in the three changed files. G's 66 before/after diagnostic lines are identical. No broad typecheck success is claimed.
- Limited Vue review found no Critical/Major issue. Its Minor active-menu accessibility finding was fixed with `i18n.ts.inUse`; the reviewer confirmed the fix in both forks.
- Browser: G and R open on the combined favorites list with two local and two peer favorites. Same-name channels from each site can be checked independently. The existing themed category popup shows the active category, and G's search finds the matching channel from both sites while retaining the prior selection. Screenshots: `.config/multi-note-picker-favorites.jpg`, `.config/multi-note-picker-search.jpg`, `.config/multi-note-picker-reverse.jpg`.

The browser used fresh test accounts and restored the previous UI accounts afterward. No user post was submitted, edited or removed. The fixture credentials and build/server logs are ignored under `.config/`.

The single-line site-chip revision passes the same **31 G / 27 R** near tests and both shipping checks again. Each fork's own i18n build generates the two ja-JP local/peer label keys and its existing locale declarations. Both frontend builds pass; the limited Vue review found no issue. Both full frontend typechecks retain **66 BASELINE diagnostics**, with none in the changed files. The browser verifies one-line candidates and selected chips, correct site-name mapping in both directions and separate same-name selections. Latest screenshots: `.config/multi-note-inline-site-g.jpg` and `.config/multi-note-inline-site-r.jpg`; both browser accounts were restored afterward.

The following spelling-only correction to `れぞらぶ` passes **6/6 picker cases in each fork**, each fork's own i18n/frontend builds and both final shipping checks. Generated lab locale data confirms G local/peer names are `ぐりすぺ` / `れぞらぶ` and R is the reverse. Earlier screenshot artifacts retain the former spelling. The apparent same-name pairs in search are distinct test channels created on both sites; live API reads confirm different IDs for each origin. No fixture was deleted or renamed.

## Shared load-more control

The user requested one load-more action for the combined channel picker. The shared button loads both sources' pending pages, retrying failures without dropping successful rows or the current selection. It stays available for healthy pages during a peer outage and becomes retry-only when healthy sources are exhausted. All-exhausted pages remove the control; in-flight requests disable it. Per-origin cursor state remains internal. No backend, locale or public schema changed.

- Both forks' selected picker/composer/state/article suites: **32/32 PASS** each, including **7 picker cases**. These cover one button, both page cursors, slow-peer double-click prevention, partial failure, independent retry, deduplication, selection preservation, exhaustion and initial-peer-outage/healthy-page progress. Final picker-only reruns also pass **7/7** in each fork.
- The targeted Vue review's retry-priority and unused-origin-state findings were fixed and independently rechecked. No unresolved finding remains in that scope.
- Both frontend builds and final shipping checks pass. G full frontend typecheck is **BASELINE**, 66 unchanged diagnostic lines, none in the changed files. Test query option type errors found during the first check were corrected before the final run.
- Browser on both G and R: one button, **20 G + 20 R** candidates initially, then **40 G + 40 R** after one click. Evidence is recorded in `.config/multi-note-unified-more-browser.json` and screenshots `.config/multi-note-unified-more-{g,r}.jpg`. Both prior UI accounts were restored; no user post or channel fixture was changed.

## Isolated servers

| Role | URL | Database / Redis ports |
| --- | --- | --- |
| G | https://multi-note-g-20261121.kokopi.me | 15532 / 16479 |
| R | https://multi-note-r-20261121.kokopi.me | 25532 / 26479 |
| E, ordinary Misskey | https://multi-note-e-20261121.kokopi.me | 35532 / 36479 |

Registration is disabled. Federation is restricted to the three lab servers. Credentials, configs and raw results are ignored under `.config/`. R uses the new dedicated `multi_note_r` database; the earlier lab tables with no migration history were preserved. No unrelated containers or data were removed.

## Passed checks

- Both backend source typechecks pass.
- Both mandatory `pnpm build-misskey-js-with-types` pipelines pass, including SDK build and API Extractor. TypeScript 6 AST compatibility has two generator regression cases. A deterministic JSDoc whitespace correction retains all text and paragraph boundaries.
- Both lab databases pass `pnpm --filter backend check-migrations` with zero pending DDL. New migrations also passed down/up on disposable databases.
- Both `node scripts/check-shipping.mjs --base <bridge-baseline>` checks pass: changed-file lint, SPDX and locale safety. The later small reply-visibility fix also passes its file lint, SPDX and whitespace checks.
- G frontend integration: 16 files, 153 passing cases. R composer and related tests: 8 suites, 50 passing cases. Local creation: 49 validator cases and 7 HTTP E2E cases, including process-stop recovery and SQL acknowledgement loss with one event per stream.
- Targeted backend suites cover distribution, SQL/Redis/WS mirror projection, ranking separation, active placement authorization, durable source/target transitions, guest operations, votes, media, notifications, canonical pagination and late-arriving mirror pins. Detailed evidence is in [implementation status](multi-note-implementation-status.md).
- The final public-host run of `node scripts/gridspace/test-multi-note.mjs` passes **48/48** checks. This includes both directions, one normal mirror across routes, legacy channel real-note subsets, no fixed five-channel cap, receipt replay/deletion, public URL preservation, guest reply/reaction/vote/media/notification operations, ordinary external AP delivery/reply/reaction/vote, dedicated AP exclusion, early deletion, terminal removal and account retirement.

## Browser evidence

The in-app browser uses disposable UI accounts. It has verified default plus two local channels, channel-only posting absent from the ordinary home, both directions of peer-channel selection/posting, and a shared conversation with guest reply, pressed reaction and a voted poll.

For response-loss recovery, the browser paused a successful HTTP 200 `notes/create` response and failed only that response. After reload, opening the composer displayed the recovered-result message. The observed recovery request was `notes/create-status`; there was no second `notes/create` request.

Screenshots are ignored test artifacts:

- `.config/multi-note-r-channel-ui.jpg`
- `.config/multi-note-cross-site-conversation.jpg`
- `.config/multi-note-r-to-g-ui.jpg`
- `.config/multi-note-public-reply.jpg`

The actual two-tab test passed: both tabs opened the same saved channel draft; the first tab submitted and its successful response was held; the second tab edited the draft; after releasing the first response, the second tab retained its edit through reload and reopening the composer. The channel contained exactly one original first-tab post and no post with the second tab's unsent text. Screenshot: `.config/multi-note-two-tabs-draft.jpg`.

Browser testing also caught a public conversation reply being labelled as followers-only. Both forks now derive the label/icon from the prepared visibility, with no assumed label before preparation. Three visibility cases, the final Vue review and the final live browser verification pass.

## Write-disabled operation

Each server was disabled independently and restored. Each direction passed two initial pin assertions, six disabled-operation checks and two restoration checks. Existing chips, all four viewer/channel-origin combinations, pins and delegated reads remain available. New placements into the disabled server are refused from both origins. Original deletion still removes the remote placement and pin in both directions. Both flags are restored to true and both public capabilities are true.

The repeatable checker is `scripts/gridspace/test-multi-note-flag.mjs prepare|during|after G|R`. The operator toggles only the selected lab configuration and restarts that task-owned app between phases; the checker itself does not manage processes or toggle configuration. Restore the flag even if a check fails. Evidence is in ignored `.config/multi-note-flag-G.json` and `.config/multi-note-flag-R.json`.

## Baseline diagnostics and limits

The full G frontend `vue-tsc` check has 66 existing diagnostics. An isolated reconstruction of baseline `9a15160548` has 67; comparison by file/code/location found zero new diagnostics and one resolved diagnostic. The two `main-boot.ts` implicit-any diagnostics are unchanged. This broad check is recorded as BASELINE, not PASS. Production Meilisearch and all deferred D1–D5 scenarios are not claimed as tested.

The R backend test-fixture typecheck has 48 existing diagnostics, compared with 53 on clean baseline `57ee8ed337`. Four new fixture diagnostics were fixed and five old diagnostics were also resolved. The remaining 48 were matched to baseline text/locations. G has 49 diagnostics: those 48 plus one unchanged G-only UrlPreviewService fixture; its whole baseline count was not reconstructed. The three corrected test files pass 44 targeted cases and file lint in each fork. Full test-fixture typechecks are not reported as PASS.
