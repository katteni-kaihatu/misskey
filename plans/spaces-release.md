# Spaces production release

2026-11-26, Asia/Tokyo. Release target: G `2026.11.0-grid-space.31.104`.

The release branch preserves Claude's `e9ae65720e`, `057c1e09f6`, `c30e38fe7f`, `8669a768c0`, and `92a642b756`, and merges the latest `master` without rebasing. The original Claude worktree is unchanged. The existing five-minute web icon rotation and selected-user search fixes are included.

Required application settings are `spaces.enabled`, `spaces.livekit.url`, `spaces.livekit.apiKey`, and `spaces.livekit.apiSecretEnv`. The named environment variable is `SPACES_LIVEKIT_SECRET`. Values and infrastructure details remain in private deployment material; do not copy the key, secret or VPS address into this repository or a PR. The existing LiveKit service is not reconfigured or restarted.

Production preflight found an empty `allowedPrivateNetworks`, no configured HTTP/SOCKS proxy or proxy environment variables, and `NODE_ENV=production`. The custom tile transport therefore has no configured private-network exception. The production control panel confirms object storage is enabled. The current image tile only permits this instance's `/files/` images, so object-storage images will not display in that tile; the limitation remains as documented in `spaces-tiles.md` section 14.

Backend review verified registration and SDK coverage for all 19 endpoints, credential requirements, and unique v4 error IDs. Release fixes coordinate background tile saves and room closure with a per-room PostgreSQL session lock, preserve retryable Redis save claims, and clean up asynchronous media and iframe operations. Focused regression tests cover these paths without physical media devices.

Both migrations are additive: `AddSpace1795667694109` and `AddSpaceTileDef1795676597727`. In an isolated synthetic PostgreSQL database, both were applied, reverted, reapplied, and checked with `pnpm --filter backend check-migrations`; pending DDL was zero. Never run their `down` methods on production after users start creating Spaces data. Application rollback retains the new tables and uses the prior application/configuration instead.

A fresh consistent production database dump, globals, configuration/TLS, runtime inventory and local uploads were archived privately before any settings changed. Every archive data block was decoded and checksums verified. The previous `.103` application image and configuration are retained in the private recovery inventory. Production database access is limited to the backup and migration tooling; functional checks use the normal application UI/API.

## Completed rollout

[PR #7](https://github.com/katteni-kaihatu/misskey/pull/7) merged into `master` as `347239a5823a6f9a40923c1f97d862749501f872`. Production is healthy on `.104`, image source `cd4dc99e64e2b5b50b53590dc7a2e12da48a9052`. All PR checks passed, including SDK generation comparison, locale verification and diagnostic inspection.

PASS: shipping checks; 56 backend Spaces tests; 10 frontend tests covering media/frame cleanup and existing icon rotation; backend source typecheck; API/SDK regeneration; full Linux/amd64 image build. Frontend typecheck remains at 101 pre-existing diagnostics, with no new diagnostics after accounting for shifted source lines and expanded API union descriptions. The isolated HTTP/streaming smoke passed room creation, announcements, listen membership, configured token URL, shared updates, summary creation and continued tile state.

The production database backup completed at 17:52:20 JST: 81,240,389 bytes, SHA-256 `c736be0b6babfef2c496d0826ec872ca92f070c562d30b4e053cb363cfcaa354`. Application recovery material is under `/home/neo/misskey/backups/20261126-spaces`, with the prior image tagged `spaces-rollback-g:20261126`. Private logs, scripts and screenshots are retained outside Git. The two expected migrations were applied to production and `check-migrations` reports zero pending DDL.

The first configuration probe failed before migration because replacement of the config file did not retain its application-readable group. The previous application stayed healthy. Configuration was restored, original ownership/mode were verified against the tar backup, and the rollout helper was corrected to preserve them and extended attributes. The candidate then successfully loaded its configuration and named environment variable before migration or application switching. Secrets moved only through captured process memory and encrypted SSH into the private environment file; neither the secret nor API key is in this repository or PR. LiveKit's server configuration and service were not modified or restarted.

Production PASS: `meta.features.spaces`, existing Multi Note feature flags, application health, matching source/image/version, client assets, ordinary timeline, `/spaces`, room creation, announcement card and token URL pointing at the configured production LiveKit. Chrome joined in listen-only mode; the microphone stayed off. The short-lived smoke room was closed through the UI and showed its ended state. The synthetic server and its two labeled database/Redis containers were stopped; no test volumes or private evidence were deleted.

Known limitation: image tiles still do not display images stored in the production object store. Physical microphone conversations, real screen sharing, mobile browsers and non-Chromium browsers were SKIPPED and require user verification. Previously documented custom tile author/network/CPU limitations remain in scope as accepted design limitations.

Changelog candidate: Add Spaces voice rooms, chat, screen sharing and shared/custom tiles backed by LiveKit.
