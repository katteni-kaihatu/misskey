# GridSpace external reader API release

Released on 2026-11-27. The user authorized implementation and release after reviewing the backend plan.

- Production: https://misskey.grid-space.io
- Version: `2026.11.1-grid-space.3`
- Runtime source: `9451b3fed15efc350560b2d878dfde84453dd5d2`
- Previous runtime: `a964a69bc0aa6618674cafa0f79faeceabbd8565`, version `2026.11.1-grid-space.2`
- Image: `ghcr.io/katteni-kaihatu/grid-space-misskey@sha256:6484c2214bbe8350fab631055afe9b5598dac593a91d3a51836f5fd53034b1fa`
- [Image build](https://github.com/katteni-kaihatu/misskey/actions/runs/46015816641)
- [Master integration PR](https://github.com/katteni-kaihatu/misskey/pull/14)
- [Client API contract](../docs/gridspace-client-api.md)

## Behavior

Three application-token endpoints provide capability discovery, the user's home timeline and notification reads. Separate permissions control timeline, notifications and additional peer/private access. Without private opt-in, the reader uses local timeline sources, including ordinary authorized ActivityPub posts, and does not hydrate peer-owned channel placements. Peer reads continue to require the existing linked or channel authorization.

The reader checks current account/token permissions before and after reads. Cursors are scoped to the application token, current permissions, linked authorization and source. The response projects only documented text fields; notification reads do not mark items read. Internal web-client endpoints and the peer protocol are unchanged. No entity or database migration was added. This release prepares the server; it does not publish an Even Hub application.

## Validation

- PASS: 94 tests across the reader, timeline coordinator with real Redis, notifications and link-authorization suites.
- PASS: 6 HTTP e2e tests against dedicated PostgreSQL and Redis containers, including MiAuth tokens, permission rejection, home reads and unchanged unread notifications.
- PASS: backend source typecheck and `pnpm build-misskey-js-with-types`.
- PASS: changed-file ESLint, SPDX, locale safety and whitespace checks.
- PASS: repository API review, with fixes and regression coverage for ordinary ActivityPub followers posts, one-way private-grant revocation and one-way-grant status.
- PASS: GitHub image build, SDK generation check, API comparison, locale, changelog and diagnostics jobs for the runtime source.
- BASELINE: the test-project typecheck reports 77 existing diagnostics. Running the same check on the previous runtime source produced the same normalized diagnostics; no reader-file diagnostic was present. This check is not reported as passing.
- PASS: the published image started in an isolated environment. Authenticated status, home and notification requests returned HTTP 200 with `private, no-store`; home returned fixture posts.
- PASS: production is healthy with zero restarts. Public HTTPS metadata and SSH-loopback metadata report the new version. All three endpoints are registered and reject unauthenticated requests with HTTP 401. The existing public local timeline returns HTTP 200; CORS preflight returns HTTP 204 with the expected allow-origin header.

## Deployment and recovery

Only the G application was replaced. The peer site, database schema, uploads, Redis and existing settings were preserved. The Compose image reference and telemetry service version were updated. Runtime mounts, port bindings, command and environment were checked against the pre-deployment snapshot.

The first switch was automatically rolled back because the verifier compared mount-list order. Comparing rendered Compose configurations established that the volume and port definitions were identical and that only the intended image/environment fields differed. The verifier was corrected to compare mounts without depending on order. The second switch passed all verification. No database restore was performed.

Private recovery evidence is outside Git at `C:/Users/neo/AppData/Local/MisskeyDeployments/20261127-even-g2-client`, restricted to the local user and SYSTEM. It includes the configuration archive, runtime snapshots, a 77,671,257-byte consistent PostgreSQL dump, image archive, checksums and test/deployment results. The dump was fully decoded with `pg_restore` before deployment. Remote recovery files are under `/home/neo/misskey/backups/20261127-even-g2-client`; the previous image is retained.

Because this release has no schema or data migration, application rollback uses the saved Compose configuration and previous image. Do not restore the database dump over later user writes for an application-only rollback.

Changelog candidate: Add scoped external-reader APIs for the home timeline and notifications, including explicit peer/private access for Even G2 clients.
