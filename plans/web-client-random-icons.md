# Random artwork for the Gridspace web client

2026-11-26, Asia/Tokyo. The owner selected the five submissions listed in [artwork credits](../assets/gridspace/web-client-icons/README.md) and requested random icons in both the main web navigation and browser tab.

The frontend chooses one of the five artists' icons on document load, then rotates to a different artwork every five minutes. Vertical/horizontal navigation, the title bar and visitor header/dashboard share that reactive module choice with the favicon. SPA navigation and layout changes do not reset the timer or choose another icon. Reloading or opening another document makes a new independent initial choice, which may repeat the previous icon. Background-tab timer throttling or device sleep may delay rotation. No preference or account data stores the selection.

The tab uses the matching 64px PNG through `link rel="icon"`. The navigation uses a 128px PNG of the same complete artwork. These derivatives preserve transparency and aspect ratio, and the downloaded originals remain unchanged with source attribution. The PNG sizes follow the browser icon declaration mechanism described in [MDN's link reference](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/link).

Only the G frontend changes. Instance metadata, ActivityPub, the canonical `/favicon.ico`, Apple touch icons, the web app manifest, the R deployment and third-party clients keep their existing sources. The HTML server response retains its configured icon; the main web client changes the current document's icon after boot. Embed entry points do not call this main boot routine.

Validation includes a DOM regression suite for a shared document choice, a new choice after reload, missing/multiple favicon declarations, five-minute rotations updating a mounted Vue template and favicon without replacing the page or input, idempotent timer startup/cleanup, and preservation of server metadata, touch icons, manifests and pinned-tab declarations across rotations. Generated PNG dimensions/signatures and original byte checksums are checked separately. The two icon-only navigation buttons have existing localized accessible names.

Changelog candidate: Rotate the Gridspace web navigation and tab icon among five selected community artworks every five minutes.

## Release verification

G `2026.11.0-grid-space.31.102`, runtime source `b27582dddf7dd0cf4531d3d97843b70a753a5dbb`, is deployed and healthy. Three DOM cases, changed-source/test lint, generator syntax, SPDX, locale safety, frontend build and full Linux/amd64 image build pass. Frontend typechecking reports the same 101 diagnostics on archived `origin/master` and the candidate, with no diagnostic differences; it is a pre-existing baseline, not a passing global typecheck.

An isolated empty-database preview was tested in Chrome with a synthetic account. The navigation and favicon matched; SPA navigation retained `machiyoh`, while a fresh document chose `tekerets`. The production browser then loaded `ningen`, again matching the navigation and favicon. All ten served PNGs match their committed checksums. The favicon test reads the browser-control tool's recorded original URL when its control badge is active.

Public icon metadata, server HTML icon declarations, canonical favicon bytes, Apple touch icon bytes and the complete app manifest match the pre-release values. The R application was not deployed or changed.

A fresh consistent G database backup of 80,813,110 bytes, globals, compose/config/TLS, runtime inventory and local uploads was fully verified before rollout. Recovery files and the previous `.101` image are retained under `/home/neo/misskey/backups/20261126-web-client-icons`; private local evidence is under `C:/Users/neo/AppData/Local/MisskeyDeployments/20261126-web-client-icons`.

The first image unpack attempt encountered a full application filesystem. The `.101` service remained healthy and its compose file was restored. Only unused `.97`, `.98` and `.99` application images, verified to have no container references or rollback tags, were removed. Databases and recovery backups were preserved. The new image was then successfully unpacked and executed in network-isolated version verification before the successful switch. The private rollout helper now requires that execution check before changing compose.

## Five-minute rotation release

The owner requested automatic rotation on 2026-11-26 after the initial rollout. G `2026.11.0-grid-space.31.103`, source `7952eae8dbad4b914a18e5995d9edde933683cf1`, is deployed and healthy. Shared computed refs update existing Vue templates; one idempotent interval starts in main common boot. Each tick chooses uniformly among the other four artworks. The returned stop handle is identity-guarded so an old handle cannot orphan a newer timer, and HMR disposes the active interval.

Five unit tests pass, including a mounted Vue template, unchanged input during rotation, repeated five-minute ticks, timer cleanup/restart and unchanged public icon metadata. Changed-source/test lint, SPDX, locale safety, frontend production build and the complete Linux/amd64 image build pass. Frontend typechecking has exactly the same 101 baseline diagnostics, with zero new or removed diagnostics. Independent review identified the stale cleanup handle case, which was corrected and covered by the timer test.

Chrome confirmed real elapsed-time rotation without reloading: the isolated preview changed from `machiyoh` to `sakami` across a SPA search navigation, and production changed from `sakami` at 17:32:13 JST to `machiyoh` at 17:37:46 JST. In each document the loaded navigation image matched its favicon before and after rotation. Canonical favicon, touch icon, manifest and public metadata match the pre-release values; all ten served PNGs still match the original release checksums. R, backend APIs, federation, database schema and account preferences are unchanged.

A fresh consistent database dump of 81,171,823 bytes completed at 17:24:04 JST, SHA-256 `c2db199e6cd3d4ea77336adce58b2cefd7f4f166bce94d90aaf2f3352da085e9`. Its checksums, archive structure and all database data blocks were verified together with config/TLS, globals, runtime inventory and local uploads. Application recovery files are retained at `/home/neo/misskey/backups/20261126-web-icons-rotation`, with the previous `.102` image tagged `web-icon-rotation-rollback-g:20261126`. The `.103` image passed unpack/execution verification before compose changed. Private evidence is named `20261126-web-icons-rotation`; the isolated browser fixture contains only synthetic data.
