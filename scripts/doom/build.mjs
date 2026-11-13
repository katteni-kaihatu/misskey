/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// Rebuild the checked-in runtime and its complete corresponding source archive.
import { mkdtemp, mkdir, readFile, writeFile, copyFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';

const root = fileURLToPath(new URL('../../', import.meta.url));
const output = resolve(root, 'packages/frontend/assets/doom');
const revision = 'e257a09527062bfb986b6e5e0780839b6cbd5b71';
const image = 'emscripten/emsdk:4.0.20@sha256:460fff8f8ac87e11b16447fbd66538a686eafa0e4fb977aa0989ed19fe2079f7';
const temp = await mkdtemp(join(tmpdir(), 'gridspace-doom-'));

function run(command, args, cwd = temp) {
	const result = spawnSync(command, args, { cwd, stdio: 'inherit', shell: false });
	if (result.error) throw result.error;
	if (result.status !== 0) throw new Error(`${command} exited with ${result.status}`);
}

async function download(url, path) {
	const response = await fetch(url);
	if (!response.ok) throw new Error(`${url}: ${response.status}`);
	await writeFile(path, new Uint8Array(await response.arrayBuffer()));
}

await mkdir(output, { recursive: true });
await download(`https://codeload.github.com/ozkl/doomgeneric/tar.gz/${revision}`, join(temp, 'upstream.tar.gz'));
run('tar', ['-xzf', 'upstream.tar.gz']);
const source = join(temp, `doomgeneric-${revision}`);
const engine = join(source, 'doomgeneric');
await copyFile(join(root, 'scripts/doom/bridge.c'), join(engine, 'gridspace_bridge.c'));
await copyFile(join(root, 'LICENSE'), join(source, 'GRIDSPACE-LICENSE'));
// Preserve the upstream platform, adding only an exported key entry point.
await writeFile(join(engine, 'doomgeneric_emscripten.c'), (await readFile(join(engine, 'doomgeneric_emscripten.c'), 'utf8')) + `
EMSCRIPTEN_KEEPALIVE void gridspace_key(int pressed, int key) {
    unsigned int next = (s_KeyQueueWriteIndex + 1) % KEYQUEUE_SIZE;
    if (next == s_KeyQueueReadIndex) return;
    s_KeyQueue[s_KeyQueueWriteIndex] = (pressed << 8) | (key & 255);
    s_KeyQueueWriteIndex = next;
}
`);
const makefile = await readFile(join(engine, 'Makefile.emscripten'), 'utf8');
const objects = makefile.match(/^SRC_DOOM = (.+)$/m)?.[1];
if (!objects) throw new Error('Upstream source list missing');
const files = objects.split(' ').map(name => name.replace(/\.o$/, '.c'));
const build = `#!/bin/sh
set -eu
cd /src/doomgeneric
emcc ${files.join(' ')} gridspace_bridge.c -O2 -DFEATURE_SOUND \\
  -Wno-incompatible-function-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration \\
  -sUSE_SDL=2 -sUSE_SDL_MIXER=2 -sSDL2_MIXER_FORMATS='[]' \\
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sENVIRONMENT=web -sINVOKE_RUN=0 \\
  -sALLOW_MEMORY_GROWTH=1 -sEXPORTED_RUNTIME_METHODS='["FS","callMain","HEAPU8"]' \\
  -sEXPORTED_FUNCTIONS='["_main","_gridspace_stat","_gridspace_key","_gridspace_pause","_gridspace_pixels"]' \\
  -o engine.js
`;
await writeFile(join(source, 'build-gridspace.sh'), build);
run('docker', ['run', '--rm', '--mount', `type=bind,source=${source},target=/src`, image, 'sh', '/src/build-gridspace.sh']);
for (const name of ['engine.js', 'engine.wasm']) await copyFile(join(engine, name), join(output, name));
// Do not include binaries/build caches in the corresponding source archive.
run('tar', ['-czf', join(output, 'source.tar.gz'), '--exclude=engine.js', '--exclude=engine.wasm', '-C', temp, `doomgeneric-${revision}`]);
await copyFile(join(source, 'LICENSE'), join(output, 'DOOM-LICENSE.txt'));

await download('https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip', join(temp, 'freedoom.zip'));
run('tar', ['-xf', 'freedoom.zip']);
const freedoom = join(temp, (await readdir(temp)).find(name => name === 'freedoom-0.13.0'));
await writeFile(join(output, 'freedoom1.wad.gz'), gzipSync(await readFile(join(freedoom, 'freedoom1.wad')), { level: 9 }));
await copyFile(join(freedoom, 'COPYING.txt'), join(output, 'FREEDOOM-LICENSE.txt'));
const hashes = {};
for (const name of ['engine.js', 'engine.wasm', 'source.tar.gz', 'freedoom1.wad.gz']) {
	hashes[name] = createHash('sha256').update(await readFile(join(output, name))).digest('hex');
}
await writeFile(join(output, 'manifest.json'), JSON.stringify({ engine: `https://github.com/ozkl/doomgeneric/tree/${revision}`, compiler: image, freedoom: '0.13.0', hashes }, null, '\t') + '\n');
console.log(`DOOM runtime built in ${output}; temporary sources: ${temp}`);
