/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, extname } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(join(root, 'packages/frontend/package.json'));
const { chromium } = require('playwright');
const assets = join(root, 'packages/frontend/assets/doom');
const output = await mkdtemp(join(tmpdir(), 'gridspace-doom-smoke-'));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = createServer(async (request, response) => {
	const name = new URL(request.url, 'http://localhost').pathname.slice(1);
	if (name === 'favicon.ico') { response.writeHead(204).end(); return; }
	if (!name) {
		response.setHeader('Content-Type', 'text/html');
		response.end(`<button id="start">Start</button><script>
		window.messages = [];
		addEventListener('message', event => {
			if (event.origin !== location.origin) return;
			messages.push(event.data);
			if (event.data.type === 'doom:ready') event.source.postMessage({type:'doom:start',skill:3}, location.origin);
		});
		document.getElementById('start').onclick = () => {
			const frame = document.createElement('iframe');
			frame.src = '/index.html'; frame.width = 800; frame.height = 500;
			frame.sandbox = 'allow-scripts allow-same-origin'; document.body.append(frame);
		};</script>`);
		return;
	}
	if (!/^[a-zA-Z0-9.-]+$/.test(name)) { response.writeHead(404).end(); return; }
	try {
		response.setHeader('Content-Type', types[extname(name)] ?? 'application/octet-stream');
		response.end(await readFile(join(assets, name)));
	} catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ headless: true, channel: process.env.PLAYWRIGHT_CHANNEL });
try {
	const page = await browser.newPage({ viewport: { width: 1000, height: 750 } });
	const errors = [];
	page.on('pageerror', error => errors.push(error.message));
	page.on('console', message => { if (message.type() === 'error') console.error(message.text()); });
	await page.goto(`http://127.0.0.1:${server.address().port}`);
	await page.click('#start');
	await page.waitForFunction(() => window.messages.some(message => message.type === 'doom:stats'), { timeout: 60000 });
	await page.frameLocator('iframe').locator('canvas').click();
	await page.keyboard.down('w');
	await page.waitForTimeout(1000);
	await page.keyboard.up('w');
	await page.keyboard.press('f');
	const latest = () => page.evaluate(() => window.messages.filter(message => message.type === 'doom:stats').at(-1).result);
	const result = await latest();
	assert.equal(result.game, 'freedoom');
	assert.equal(result.episode, 1);
	assert.equal(result.map, 1);
	assert.ok(result.ticks > 20);
	assert.ok(result.totalKills > 0);
	await page.keyboard.press('Shift+Tab');
	assert.equal(await page.evaluate(() => document.activeElement.id), 'start');
	await page.evaluate(() => document.querySelector('iframe').contentWindow.postMessage({ type: 'doom:pause', paused: true }, location.origin));
	await page.waitForTimeout(300);
	const paused = await latest();
	await page.waitForTimeout(500);
	assert.equal((await latest()).ticks, paused.ticks);
	await page.evaluate(() => document.querySelector('iframe').contentWindow.postMessage({ type: 'doom:capture' }, location.origin));
	await page.waitForFunction(() => window.messages.some(message => message.type === 'doom:captured'));
	const png = await page.evaluate(async () => Array.from(new Uint8Array(await window.messages.find(message => message.type === 'doom:captured').blob.arrayBuffer())));
	assert.ok(png.length > 10000);
	await writeFile(join(output, 'capture.png'), new Uint8Array(png));
	await page.screenshot({ path: join(output, 'doom.png') });
	await page.evaluate(() => document.querySelector('iframe').contentWindow.postMessage({ type: 'doom:pause', paused: false }, location.origin));
	await page.waitForTimeout(400);
	assert.ok((await latest()).ticks > paused.ticks);
	await page.evaluate(() => document.querySelector('iframe').remove());
	await page.waitForTimeout(200);
	const count = await page.evaluate(() => window.messages.length);
	await page.waitForTimeout(400);
	assert.equal(await page.evaluate(() => window.messages.length), count);
	assert.deepEqual(errors, []);
	console.log(JSON.stringify({ result: 'PASS', stats: result, screenshot: join(output, 'doom.png') }));
} finally {
	await browser.close();
	server.close();
}
