/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// Real paired backend/API and PWA comparison. The WebKit message provider is
// synthetic; the injected bootstrap and Web lifecycle code are actual sources.
// This is not a physical-device or a native authentication test.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, realpath, writeFile } from 'node:fs/promises';
import { resolve, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

process.umask(0o077);
const root = fileURLToPath(new URL('../../../', import.meta.url));
const directory = await realpath(resolve(process.argv[2] ?? ''));
assert.ok(basename(directory).startsWith('gridspace-ios-parity-pair-'));
const run = JSON.parse(await readFile(join(directory, 'run.json'), 'utf8'));
const proxied = run.pair.client.origin === 'https://g.ios-parity.test:61813';
assert.equal(run.pair.client.origin, proxied ? 'https://g.ios-parity.test:61813' : 'https://127.0.0.1:61813');
assert.equal(run.pair.source.origin, proxied ? 'https://r.ios-parity.test:61815' : 'https://127.0.0.1:61815');
if (proxied) assert.ok(/^[0-9a-f]{64}$/.test(run.environment.GRIDSPACE_PARITY_PROXY_PASSWORD));
const engine = process.env.GRIDSPACE_PARITY_BROWSER ?? 'chromium';
assert.ok(['chromium', 'webkit'].includes(engine));
const requireFrontend = createRequire(join(root, 'packages/frontend/package.json'));
const { expect } = requireFrontend('@playwright/test');
const browser = await requireFrontend('playwright')[engine].launch({ headless: true });
// The temporary CA is scoped to test requests. It is not installed into the
// browser's ServiceWorker trust store; cache/offline parity is a separate test.
const context = await browser.newContext({ ignoreHTTPSErrors: true, serviceWorkers: 'block', viewport: { width: 390, height: 844 }, locale: 'ja-JP',
	...(proxied ? { proxy: { server: 'http://127.0.0.1:61816', username: 'paired-parity', password: run.environment.GRIDSPACE_PARITY_PROXY_PASSWORD } } : {}) });
const { client, source, channel, channelNote } = run.pair;
assert.equal(client.user.username, 'paired_user');
assert.equal(source.old.username, 'paired_old');
assert.equal(source.author.username, 'paired_author');
const api = async (site, endpoint, body = {}, token) => {
	const response = await context.request.post(site.origin + '/api/' + endpoint, { maxRedirects: 0, data: { ...body, ...(token ? { i: token } : {}) } });
	const result = response.status() === 204 ? undefined : await response.json();
	if (!response.ok()) {
		const code = /^[A-Z_]+$/.test(result?.error?.code) ? result.error.code : 'HTTP_ERROR';
		throw new Error(`${endpoint}: HTTP ${response.status()} ${code}`);
	}
	return result;
};
async function authorize() {
	const started = await api(client, 'gridspace/private-grant', { action: 'start' }, client.user.token);
	assert.equal(new URL(started.authorizationUrl).origin, source.origin);
	const response = await context.request.get(started.authorizationUrl, { maxRedirects: 0 });
	assert.equal(response.status(), 200);
	const transaction = (await response.text()).match(/name="misskey:oauth:transaction-id" content="([^"]+)"/)?.[1];
	assert.ok(transaction);
	const decision = await context.request.post(source.origin + '/oauth/decision', { form: { transaction_id: transaction, login_token: source.old.token }, maxRedirects: 0 });
	assert.equal(decision.status(), 302);
	const callback = new URL(decision.headers().location);
	assert.equal(callback.origin, client.origin);
	await api(client, 'gridspace/private-grant', { action: 'finish', code: callback.searchParams.get('code'), state: callback.searchParams.get('state'), issuer: callback.searchParams.get('iss'), clientKey: started.clientKey }, client.user.token);
	assert.equal((await api(client, 'gridspace/private-grant', {}, client.user.token)).granted, true);
}
const key = randomBytes(32).toString('hex');
let releaseRead = () => {};
let revoked = false;
let page;
await context.tracing.start({ screenshots: true, snapshots: true });
try {
	if (!(await api(client, 'gridspace/private-grant', {}, client.user.token)).granted) await authorize();
	const account = { ...await api(client, 'i', {}, client.user.token), token: client.user.token };
	await api(client, 'i/registry/set', { scope: ['client', 'base'], key: 'accountSetupWizard', value: -1 }, client.user.token);
	const originalAuthor = 'Original paired author ' + engine;
	const updatedAuthor = 'Updated paired author ' + engine;
	await api(source, 'i/update', { name: originalAuthor }, source.author.token);
	const bootstrap = (await readFile(join(root, 'apps/ios/App/BridgeBootstrap.js'), 'utf8')).replace('__GRIDSPACE_RENDERER_LIFECYCLE_KEY__', key);
	await context.addInitScript(({ origin, account }) => {
		if (location.origin !== origin || window !== window.top) return;
		localStorage.setItem('account', JSON.stringify(account));
		localStorage.setItem('lang', 'ja-JP');
		localStorage.setItem('neverShowDonationInfo', 'true');
		localStorage.setItem('modifiedVersionMustProminentlyOfferInAgplV3Section13Read', 'true');
	}, { origin: client.origin, account });
	await context.addInitScript({ content: `(() => {
		if (window !== window.top) return;
		let epoch = crypto.randomUUID();
		Object.defineProperty(window, 'webkit', {configurable:true, value:{messageHandlers:{gridspaceBridge:{postMessage:async request => {
			if (request.operation === 'session.changed') epoch = crypto.randomUUID();
			return {protocolVersion:1, requestId:request.requestId, operation:request.operation, accountEpoch:epoch, status:'success',
				payload:{schemaVersion:1, authenticatedOperations:false, operations:['capabilities','ready','session.changed']}};
		}}}}});
	})();\n${bootstrap}\nvoid window.gridspaceNative?.rendererLifecycle.apply(false, ${JSON.stringify(key)});` });
	page = await context.newPage();
	page.setDefaultTimeout(30000);
	const errors = [];
	page.on('pageerror', error => {
		errors.push(error.name);
		void writeFile(join(directory, 'private-quote-' + engine + '-pageerror.txt'), error.stack || error.message || String(error), { mode: 0o600 });
	});
	await context.route('**/*', route => {
		const origin = new URL(route.request().url()).origin;
		return [client.origin, source.origin].includes(origin) ? route.continue() : route.abort();
	});
	await page.goto(`${client.origin}/gridspace/private?noteId=${channelNote.id}&channelId=${channel.id}`, { waitUntil: 'domcontentloaded' });
	const card = page.locator('[data-gridspace-private-note]').filter({ hasText: channelNote.text }).first();
	await expect(card).toBeVisible();
	await card.getByRole('button', { name: 'リノート', exact: true }).click();
	await page.getByRole('menuitem', { name: /チャンネル内引用$/ }).or(page.getByRole('button', { name: /チャンネル内引用$/ })).first().click();
	const form = page.locator('[data-gridspace-post-form]');
	await expect(form.getByText(channelNote.text, { exact: true })).toBeVisible();
	await expect(form.getByText(originalAuthor, { exact: true })).toBeVisible();
	const draft = 'Synthetic own quote draft ' + engine;
	await form.getByRole('textbox', { name: 'テキスト', exact: true }).fill(draft);
	const visibility = async hidden => {
		const ack = await page.evaluate(({ hidden, key }) => window.gridspaceNative.rendererLifecycle.apply(hidden, key), { hidden, key });
		assert.deepEqual(ack, { version: 1, supported: true, hidden });
	};
	assert.equal(await page.evaluate(() => document.hidden), false);
	await visibility(true);
	await expect(form.getByText(channelNote.text, { exact: true })).toHaveCount(0);
	await expect(form.getByText(originalAuthor, { exact: true })).toHaveCount(0);
	await api(source, 'i/update', { name: updatedAuthor }, source.author.token);
	let held = false;
	const readGate = new Promise(done => { releaseRead = done; });
	await page.route('**/api/gridspace/private-notes', async route => {
		const params = route.request().postDataJSON();
		if (!held && params.mode === 'show' && params.noteId === channelNote.id) {
			held = true;
			const response = await route.fetch();
			await readGate;
			await route.fulfill({ response });
		} else await route.continue();
	});
	await visibility(false);
	await expect.poll(() => held).toBe(true);
	await expect(form.getByText(channelNote.text, { exact: true })).toHaveCount(0);
	releaseRead();
	await expect(form.getByText(updatedAuthor, { exact: true })).toBeVisible();
	await expect(form.getByRole('textbox', { name: 'テキスト', exact: true })).toHaveValue(draft);
	await page.unroute('**/api/gridspace/private-notes');
	console.log(engine + ': real target reauthorization waits, replaces actor data, and preserves own draft PASS');
	await visibility(true);
	await api(client, 'gridspace/private-grant', { action: 'revoke' }, client.user.token); revoked = true;
	assert.equal((await api(client, 'gridspace/private-grant', {}, client.user.token)).granted, false);
	// Channel posting uses the current client identity; that permission alone
	// must never restore a target previously read using the revoked old grant.
	const prepared = await api(client, 'gridspace/channel-post', { action: 'prepare', channelId: channel.id }, client.user.token);
	assert.equal(prepared.canReply, true);
	await visibility(false);
	await expect(form.getByRole('alert')).toBeVisible();
	await expect(form.getByText(channelNote.text, { exact: true })).toHaveCount(0);
	await expect(form.getByText(updatedAuthor, { exact: true })).toHaveCount(0);
	await expect(form.getByTestId('post-form-submit')).toBeDisabled();
	await authorize(); revoked = false;
	await visibility(true); await visibility(false);
	await expect(form.getByText(updatedAuthor, { exact: true })).toBeVisible();
	await expect(form.getByRole('textbox', { name: 'テキスト', exact: true })).toHaveValue(draft);
	assert.deepEqual(errors, []);
	await form.screenshot({ path: join(directory, 'private-quote-' + engine + '.png') });
	console.log(engine + ': actual grant revocation blocks the old target; OAuth reauthorization restores it without losing the draft PASS');
} catch (error) {
	if (page && !page.isClosed()) {
		await page.screenshot({ path: join(directory, 'private-quote-' + engine + '-failure.png') });
		await writeFile(join(directory, 'private-quote-' + engine + '-failure.aria'), await page.locator('body').ariaSnapshot(), { mode: 0o600 });
	}
	throw error;
} finally {
	releaseRead();
	try { if (revoked) await authorize(); } finally { await context.tracing.stop({ path: join(directory, 'private-quote-' + engine + '.zip') }); await context.close(); await browser.close(); }
}
