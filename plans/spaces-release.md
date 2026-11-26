# Spaces production release

2026-11-26, Asia/Tokyo. Release target: G `2026.11.0-grid-space.31.104`.

The release branch preserves Claude's `e9ae65720e`, `057c1e09f6`, `c30e38fe7f`, `8669a768c0`, and `92a642b756`, and merges the latest `master` without rebasing. The original Claude worktree is unchanged. The existing five-minute web icon rotation and selected-user search fixes are included.

Required application settings are `spaces.enabled`, `spaces.livekit.url`, `spaces.livekit.apiKey`, and `spaces.livekit.apiSecretEnv`. The named environment variable is `SPACES_LIVEKIT_SECRET`. Values and infrastructure details remain in private deployment material; do not copy the key, secret or VPS address into this repository or a PR. The existing LiveKit service is not reconfigured or restarted.

Production preflight found an empty `allowedPrivateNetworks`, no configured HTTP/SOCKS proxy or proxy environment variables, and `NODE_ENV=production`. The custom tile transport therefore has no configured private-network exception. The production control panel confirms object storage is enabled. The current image tile only permits this instance's `/files/` images, so object-storage images will not display in that tile; the limitation remains as documented in `spaces-tiles.md` section 14.

Backend review verified registration and SDK coverage for all 19 endpoints, credential requirements, and unique v4 error IDs. Release fixes coordinate background tile saves and room closure with a per-room PostgreSQL session lock, preserve retryable Redis save claims, and clean up asynchronous media and iframe operations. Focused regression tests cover these paths without physical media devices.

Both migrations are additive: `AddSpace1795667694109` and `AddSpaceTileDef1795676597727`. In an isolated synthetic PostgreSQL database, both were applied, reverted, reapplied, and checked with `pnpm --filter backend check-migrations`; pending DDL was zero. Never run their `down` methods on production after users start creating Spaces data. Application rollback retains the new tables and uses the prior application/configuration instead.

A fresh consistent production database dump, globals, configuration/TLS, runtime inventory and local uploads were archived privately before any settings changed. Every archive data block was decoded and checksums verified. The previous `.103` application image and configuration are retained in the private recovery inventory. Production database access is limited to the backup and migration tooling; functional checks use the normal application UI/API.

Final image build, PR integration and production smoke results will be appended after completion. Physical microphone conversations, real screen sharing, mobile browsers and non-Chromium browsers require user verification. Previously documented custom tile author/network/CPU limitations remain in scope as accepted design limitations.

Changelog candidate: Add Spaces voice rooms, chat, screen sharing and shared/custom tiles backed by LiveKit.
