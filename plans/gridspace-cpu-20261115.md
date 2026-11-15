# GridSpace CPU reduction — 2026-11-15

## Deployment

- User authorized the fix and production deployment in this chat.
- Target: `misskey.grid-space.io`, VM `grid-misskey` (`192.168.10.95`).
- Source commit: `80f724b606bf0272a14d8bcac80b05a82673abf1` on `codex/gridspace-cpu-fix`.
- Version: `2026.11.0-grid-space.31.29` (previously `.31.28`).
- Image: `ghcr.io/katteni-kaihatu/grid-space-misskey@sha256:78984fe7efb634f81d80bb816279f97bce7a14aebb1366432a7602a5c783ada7`.
- Build: https://github.com/katteni-kaihatu/misskey/actions/runs/43687886330 (success).
- Web container started at 16:06:39 JST. Only the web service was recreated. PostgreSQL, Redis and the peer proxy kept running. No schema migration was added.
- `/home/neo/misskey/compose.yaml` now pins the image digest. The previous Compose file and image metadata are under `/home/neo/misskey/backups/cpu-fix-31.29/` with restricted permissions. The previous image remains available.

## Cause and changes

Follow expansion ran every three seconds in both the primary and queue worker. Its join plan made about 160,000 user lookups even when every expansion receipt was complete. Candidate discovery now resolves linked counterparts before probing existing composite subscription indexes, and materializes candidates before filtering receipts. A read-only comparison against production data found the same 1,686 candidates; the exploratory query took 29 ms instead of 365 ms. PostgreSQL regression tests also cover pending requests, completed/skipped receipts, retries, revoked/mirrored links and cursor pagination.

All five GridSpace periodic services now share one timer owner per process. Ordinary clustering uses the primary; server-only clustering designates one worker and preserves that role when it is replaced. Duplicate application contexts do not register a second timer, and `noDaemons` disables the timers. Existing processing locks and authorization checks remain in place.

Actor visibility SQL expanded 186 host patterns into constants, spending about 28 ms planning a query whose execution took about 0.3 ms. It now uses one array parameter and an `unnest` relation, matching the existing note-host filtering approach. PostgreSQL tests compare results with the previous predicate, including local users, subdomains, case and wildcard behavior. Repeated actor checks within a delegated note response, including renote previews, share a promise. A later request checks permissions again.

## Validation

- PASS: `pnpm --filter backend test --run src/core/gridspace` — 350 tests, 49 files; 5 existing conditional lab tests skipped in one file.
- PASS: backend TypeScript check using the installed TypeScript CLI.
- PASS: `node scripts/check-shipping.mjs --base dcb2be7137deefbdf47e258518bfefb2009b0acc` — changed-file lint, SPDX and locale safety.
- PASS: published image revision and version matched the source before switching production.
- PASS: public `/api/meta` returned HTTP 200 and `.31.29`; `/healthz` returned HTTP 200; web remained healthy with zero restarts.
- PASS: three authenticated delegated home reads returned HTTP 200 in 305, 302 and 298 ms. Before deployment, three reads took 2,483, 1,624 and 789 ms. These are live observations with different note counts, not a controlled latency benchmark.
- PASS: passive SQL observation found four follow-discovery queries in 12 seconds, all from the primary process, and no old discovery query. All 202 observed actor-check queries used the new host predicate.
- PASS: initial post-deploy log window contained no slow queries or errors; normal federation processing continued.

## CPU observations

The VM has two vCPUs. Container figures below are normalized to total VM CPU capacity, not Docker's one-core percentage.

| Observation | Window | VM total | PostgreSQL | Web |
| --- | --- | --- | --- | --- |
| 15:59:29–15:59:44 JST, before | 15 s | 66.24% | 52.61% | 10.42% |
| 16:06:59–16:07:29 JST, after | 30 s | 20.80% | 6.03% | 10.21% |
| 16:07:56–16:08:26 JST, after | 30 s | 24.23% | 7.88% | 11.03% |

Traffic and cache state were not held constant. The measurements establish a substantial reduction during these windows, not a guaranteed percentage under every workload.

## Rollback

The previous image tag is `ghcr.io/katteni-kaihatu/grid-space-misskey:2026.11.0-grid-space.31.28` (source `0383a8962655fab5817c3e6ce8f7697a2d962786`). After checking for intervening changes to Compose, restore only the web image reference and run `docker compose up -d --no-deps --pull never --wait web` from `/home/neo/misskey`. No database restore or reverse migration is required for this change.

Changelog candidate: Fix: Reduce CPU usage from GridSpace background processing and actor visibility checks.
