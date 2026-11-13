# DOOM runtime

The Play entry at `/play/doom` uses the real DOOM engine through
[doomgeneric](https://github.com/ozkl/doomgeneric), with Freedoom Phase 1 game
data. No commercial DOOM assets are shipped. Users may load a local DOOM or
DOOM II IWAD; it is never uploaded. The initial download is lazy, after Start.

The runtime runs in a disposable iframe, with its own keyboard listeners,
WebAssembly memory, SDL sound and main loop. Leaving the page or pressing Stop
destroys that iframe. Result messages are accepted only from that iframe and
the same origin, then validated before display or sharing.

Results contain per-level kills, items, secrets, engine ticks (35 per second),
skill and completion state. The additional score is `kills * 100 + items * 10
+ secrets * 250`. DOOM's original counters are preserved. Shared result URLs
are public, self-reported snapshots, not authenticated leaderboard entries.
Posting uses the existing Misskey composer with a score card image; sharing
never silently publishes. Images contain the game framebuffer while running,
or a score-only card after stopping. Images can also be saved or shared through
the device's share sheet. Share images are marked sensitive in Misskey.

## Rebuilding

Run from the repository root, with Node.js, Docker and `tar` on PATH:

```sh
node scripts/doom/build.mjs
```

Run the browser smoke check with `node scripts/doom/smoke.mjs`. It uses the
frontend's Playwright installation. Set `PLAYWRIGHT_CHANNEL=msedge` to use an
installed Edge browser instead of downloading Playwright's Chromium.

The script pins the doomgeneric revision and Emscripten image digest, builds
SDL2 sound effects (no MIDI music), downloads Freedoom 0.13.0, and emits the
runtime, compressed IWAD, licenses, complete corresponding source archive and
SHA-256 manifest. Internet access is required only to rebuild; deployed games
load all assets from the Misskey instance. The source archive includes the
modified platform, the telemetry bridge and the exact compilation command.

`DOOM-LICENSE.txt` contains upstream GPL-2.0-or-later terms. Misskey's bridge
uses AGPL-3.0-only; its license is included as `GRIDSPACE-LICENSE` in the
source archive. `FREEDOOM-LICENSE.txt` covers the unmodified Freedoom data.

## Manual checks

- Open Play, follow DOOM, start, move, fire and use a door. Check live counters.
- Pause/resume, switch tabs, stop and leave the route: no stuck keys or audio.
- Finish a stage: the completion snapshot is available during intermission.
- Copy a result and open its URL signed out; verify counters match.
- Open the Misskey composer and system share sheet, then cancel each.
- Load a local IWAD; reject PWADs, invalid headers and files over 64 MiB.
- Check touch movement plus fire, narrow screens and fullscreen.
