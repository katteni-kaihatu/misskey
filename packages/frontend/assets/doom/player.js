/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// The engine lives in an iframe so navigation destroys its loop and audio.
import createDoom from './engine.js';

const canvas = document.getElementById('screen');
const origin = location.origin;
const send = (type, data) => parent.postMessage({ type, ...data }, origin);
const held = new Set();
const keys = new Map([
	['ArrowUp', 0xad], ['KeyW', 0xad], ['ArrowDown', 0xaf], ['KeyS', 0xaf],
	['ArrowLeft', 0xac], ['ArrowRight', 0xae], ['KeyA', 0xa0], ['KeyD', 0xa1],
	['ControlLeft', 0xa3], ['ControlRight', 0xa3], ['KeyF', 0xa3],
	['Space', 0xa2], ['KeyE', 0xa2], ['ShiftLeft', 0xb6], ['ShiftRight', 0xb6],
	['Enter', 13], ['Escape', 27], ['Tab', 9],
	['Digit1', 49], ['Digit2', 50], ['Digit3', 51], ['Digit4', 52],
	['Digit5', 53], ['Digit6', 54], ['Digit7', 55],
]);
let engine;
let booting = false;
let manualPause = false;

function key(code, down) {
	if (!engine || !keys.has(code)) return;
	if (down === held.has(code)) return;
	if (down) held.add(code);
	else held.delete(code);
	// Two physical keys may map to the same engine key.
	if (!down && [...held].some(other => keys.get(other) === keys.get(code))) return;
	engine._gridspace_key(down ? 1 : 0, keys.get(code));
}

function releaseKeys() {
	for (const code of [...held]) key(code, false);
}

function pause(value) {
	releaseKeys();
	engine?._gridspace_pause(value ? 1 : 0);
}

async function capture() {
	if (!engine) return;
	const picture = document.createElement('canvas');
	picture.width = 640;
	picture.height = 400;
	const context = picture.getContext('2d');
	const pixels = context.createImageData(640, 400);
	const offset = engine._gridspace_pixels();
	const heap = engine.HEAPU8;
	for (let i = 0; i < pixels.data.length; i += 4) {
		pixels.data[i] = heap[offset + i + 2];
		pixels.data[i + 1] = heap[offset + i + 1];
		pixels.data[i + 2] = heap[offset + i];
		pixels.data[i + 3] = 255;
	}
	context.putImageData(pixels, 0, 0);
	const blob = await new Promise(resolve => picture.toBlob(resolve, 'image/png'));
	send('doom:captured', { blob });
}

async function start(data) {
	if (booting) return;
	booting = true;
	try {
		send('doom:loading');
		let wad = data.wad;
		if (!(wad instanceof Uint8Array)) {
			const response = await fetch('./freedoom1.wad.gz');
			if (!response.ok || !response.body) throw new Error('WAD download failed');
			wad = new Uint8Array(await new Response(response.body.pipeThrough(new DecompressionStream('gzip'))).arrayBuffer());
		}
		engine = await createDoom({
			canvas,
			noInitialRun: true,
			print: () => {},
			printErr: console.warn,
			onAbort: () => send('doom:error'),
		});
		engine.FS.writeFile('/game.wad', wad);
		engine.callMain(['-iwad', '/game.wad', '-warp', '1', '1', '-skill', String(data.skill), '-nomusic']);
		if (document.hidden) pause(true);
		canvas.focus();
		send('doom:started');
		let played = false;
		setInterval(() => {
			const stat = (field) => engine._gridspace_stat(field);
			if (stat(12)) return; // Attract-mode demos are never player results.
			const state = stat(0);
			if (state === 0 && stat(10) > 0) played = true;
			if (played && (state === 0 || state === 1 || state === 2)) {
				const result = {
					version: 1, game: data.custom ? 'doom' : 'freedoom',
					episode: stat(1), map: stat(2), skill: stat(3),
					kills: stat(4), totalKills: stat(5), items: stat(6), totalItems: stat(7),
					secrets: stat(8), totalSecrets: stat(9), ticks: stat(10),
					completed: state !== 0, dead: stat(11) <= 0,
				};
				send('doom:stats', { result });
				if (state !== 0) played = false;
			}
		}, 100);
	} catch (error) {
		console.error(error);
		send('doom:error');
	}
}

window.addEventListener('message', (event) => {
	if (event.source !== parent || event.origin !== origin) return;
	const data = event.data;
	if (!data || typeof data !== 'object') return;
	if (data.type === 'doom:start' && Number.isInteger(data.skill) && data.skill >= 1 && data.skill <= 5) void start(data);
	if (data.type === 'doom:key') key(data.code, data.down === true);
	if (data.type === 'doom:capture') void capture();
	if (data.type === 'doom:pause') {
		manualPause = data.paused === true;
		pause(manualPause || document.hidden);
		if (!manualPause) canvas.focus();
	}
});

canvas.addEventListener('click', () => canvas.focus());
window.addEventListener('keydown', (event) => {
	// Let the browser move focus out of the game, without SDL consuming Tab.
	if (event.code === 'Tab' && event.shiftKey) {
		releaseKeys();
		event.stopImmediatePropagation();
		return;
	}
	if (!keys.has(event.code) || event.ctrlKey && !event.code.startsWith('Control')) return;
	event.preventDefault();
	if (!event.repeat && !manualPause) key(event.code, true);
}, true);
window.addEventListener('keyup', (event) => {
	if (!keys.has(event.code)) return;
	event.preventDefault();
	key(event.code, false);
});
window.addEventListener('blur', releaseKeys);
document.addEventListener('visibilitychange', () => pause(manualPause || document.hidden));
send('doom:ready');
