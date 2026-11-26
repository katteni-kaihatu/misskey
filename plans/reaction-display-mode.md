# Reaction display preference

Implemented for Gridspace on 2026-11-26 (Asia/Tokyo), following the owner's request.

Settings → Preferences → Timeline and notes → リアクションの表示方法 offers アイコン (`avatars`, default) and 数字 (`count`). The account-dependent `reactionUserDisplay` preference uses existing local persistence, profiles, optional cloud synchronization and cross-tab synchronization. Other accounts and guests retain the avatar default. The existing note-footer `showReactionsCount` switch keeps its separate purpose.

Numeric mode shows the grouped reaction total supplied by the parent component, including emoji aliases and peer sources. It does not count avatar previews, which may be capped or deduplicated. It skips avatar-preview requests and invalidates pending responses when switching modes; returning to avatars reloads previews. Tooltip details, reaction lists and reaction toggling remain available in both modes. Unknown preference values fall back to avatars. The previous preference-schema compatibility and BroadcastChannel v3 fixes remain intact.

This changes the G frontend only. R, backend APIs, stored notes, database schema and federation payloads are unchanged.

## Validation

- PASS: 27 tests across the reaction renderer, reaction grouping/user aggregation, preference persistence/account isolation, cross-tab synchronization and preference-schema compatibility suites.
- PASS: changed-source/test ESLint, SPDX, locale safety, whitespace checks and the complete Linux/amd64 production image build.
- BASELINE: frontend typecheck retains the same 101 existing diagnostics; no new diagnostics.
- PASS: independent Astra Vue review; the identified avatar-spacing regression was corrected before packaging.
- PASS: Chrome on an isolated synthetic database showed two avatars by default and `👍 2` with no avatars in numeric mode. The numeric choice persisted in a newly loaded document; selecting avatars in the settings tab restored both avatars in the already open note tab. No console errors. During the cross-tab check, 16.48 seconds elapsed with 0.016 seconds of browser task time and 0.003 seconds of script time.
- PASS: production settings show the new option with アイコン selected. The verification did not change the user's preferences.

Screenshots: [avatars](../docs/screenshots/reaction-display-avatars.jpg), [count](../docs/screenshots/reaction-display-count.jpg), [setting](../docs/screenshots/reaction-display-setting.jpg). All screenshot accounts and notes are synthetic. Temporary preview containers, network and bridge were removed after testing.

## Release and recovery

G `2026.11.0-grid-space.31.107` is deployed and healthy. The packaged source is `2345b4811150a1c4608c95b3d06ae5e70ada794a`; subsequent changes only type the test mock and record validation. Server HTML/client assets, ordinary timeline responses, existing relay restrictions, Multi Note, peer support and Spaces were verified. The production config checksum is unchanged.

Before rollout, a fresh consistent 81,727,645-byte PostgreSQL dump, globals, config/TLS, runtime inventory and local uploads were retained. Checksums, archive structure and every database data block were decoded successfully. The database dump SHA-256 is `7e5ad69d3170e63cacc5d81eda3470356071563e72ecb3fd175658b2c1391d83`. Recovery files are in `/home/neo/misskey/backups/20261126-reaction-display`, and the previous `.106` image has the rollback tag `reaction-display-rollback-g:20261126`. The candidate image was unpacked and executed successfully before changing compose. Only an unused `.53` application image, verified to have no container references or other tags, was removed for disk headroom.

Changelog candidate: Add a reaction display setting to choose avatars (default) or numeric counts.
