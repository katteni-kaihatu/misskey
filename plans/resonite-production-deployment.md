# Resonite previews: GridSpace production deployment

Deployed on 2026-11-23 (Asia/Tokyo) following the user's deployment request.

| Item | Value |
| --- | --- |
| Site | https://misskey.grid-space.io |
| Release | `2026.11.0-grid-space.31.78` |
| Runtime source | `20ef6204376646ca06c52e9ec8f928e87b7ce380` |
| Production base | `71216626ebf58395b0f993864508c64635f3fd47` (`31.77`) |
| Feature source | `4b4308d49a3a15b7ebdc610df0643e03802bc929` ([PR #3](https://github.com/katteni-kaihatu/misskey/pull/3)) |
| Image | `ghcr.io/katteni-kaihatu/grid-space-misskey@sha256:18a969e51324b0d0b6a26574dfa8abeffbb1ce33036aedcb3413051ad3a3a405` |
| Build | [Build and Publish Docker](https://github.com/katteni-kaihatu/misskey/actions/runs/45105976417) |

The feature branch started from `31.72`, while production already ran `31.77`.
The release merges the exact deployed production source with the reviewed feature
source, preserving Multi Note, linked channel Home behavior and the intervening
production repairs. Adjacent translation blocks were the only merge conflicts;
both `_multiNote` and `_resonitePreview` were retained and locale types regenerated.
No API definitions, entities, migration files or existing generated API types
changed relative to the production base.

The release adds Resonite world/session cards and native launch links. Equirectangular
thumbnails rotate slowly, support horizontal and vertical mouse/touch/keyboard
panning, pause while held, and resume three seconds after release. Pitch is bounded
to prevent inversion and retained when automatic rotation resumes. Motion settings,
offscreen cleanup and a static WebGL fallback remain supported.

## Validation

- PASS: 40 focused backend and 76 frontend tests on the integrated release, including
  existing note-link/Multi Note rendering and 18 panorama cases.
- PASS: SDK and locale builds, changed-file lint, SPDX, locale safety and diff checks.
- PASS: independent frontend/backend integration reviews; production behavior was
  retained and the feature implementation matches the reviewed source.
- PASS: the complete Linux/amd64 Docker build and image publication. Runtime image
  version, revision and digest match the release tag.
- PASS: healthy production container, public `/healthz`, metadata version and URI,
  versioned frontend entry, and a real public Resonite preview with full-resolution
  image-proxy output (no `preview=1`).
- PASS: the production browser rendered with no uncaught errors or failed client
  assets. No production note or reaction was created for validation.
- LIMITATION: the feature PR's broad OpenAPI validation and federation CI jobs remain
  unsuccessful. OpenAPI failures concern existing GridSpace schema annotations,
  and the federation run reported database/setup errors. These jobs are not claimed
  as passing; the release has no changes to those API definitions or federation
  code. The existing broad frontend typecheck baseline also remains applicable.

## Configuration and recovery

Only `web` was recreated on `grid-misskey` (`192.168.10.95`). Configuration hashes
matched before and after; PostgreSQL, Redis and the peer proxy retained their
container IDs and start times. The web image reference in
`/home/neo/misskey/compose.yaml` is pinned to the immutable digest above.

The private directory `/home/neo/misskey/backups/20261123-resonite-31.78` contains
the prior Compose file, a verified configuration archive, runtime inventory and
configuration checksums. No database restore, data rewrite or schema migration
was needed. This is a configuration/runtime recovery snapshot, not a new database
backup.

The immediate rollback image remains available:
`ghcr.io/katteni-kaihatu/grid-space-misskey@sha256:16cd1088ba61e450936c6e80c0532bc820b0ce769bcb0041433845ea0e529bc7`
(`31.77`). If recovery is required, check for intervening Compose edits, restore
only that web image reference and recreate only `web`, retaining current data.
Do not revert to pre-Multi-Note binaries or restore old database contents over
subsequent writes.

Changelog candidate: Add Resonite world/session previews with interactive panoramas.
