/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { createServer } from 'node:http';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import type { entities } from 'misskey-js';
import { api, castAsError, post, signup } from '../utils.js';

describe('automatic translation API', () => {
	let admin: entities.SignupResponse;
	let alice: entities.SignupResponse;
	let bob: entities.SignupResponse;
	let calls = 0;
	const provider = createServer(async (req, res) => {
		if (req.headers.authorization !== 'Bearer e2e-only-key') { res.writeHead(401).end(); return; }
		res.setHeader('Content-Type', 'application/json');
		if (req.url === '/v1/models') { res.end(JSON.stringify({ data: [{ id: 'translation-test' }] })); return; }
		const chunks: Buffer[] = [];
		for await (const chunk of req) chunks.push(chunk);
		const body = JSON.parse(Buffer.concat(chunks).toString());
		if (req.url === '/v1/language-detection') {
			const language = body.text.includes('使った') ? 'ja' : 'en';
			res.end(JSON.stringify({ predictions: [{ language, probability: 0.7 }] }));
			return;
		}
		calls++;
		res.end(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: body.messages[0].content.replace('Hello', 'こんにちは') } }] }));
	});
	beforeAll(async () => {
		admin = await signup({ username: 'root' });
		alice = await signup({ username: 'alice' });
		bob = await signup({ username: 'bob' });
		await new Promise<void>(resolve => provider.listen(0, '127.0.0.1', resolve));
	});
	afterAll(async () => { await new Promise<void>(resolve => provider.close(() => resolve())); });
	test('requires login and administrator access', async () => {
		expect((await api('auto-translation/capabilities', {})).status).toBe(401);
		for (const endpoint of ['admin/auto-translation/get-config', 'admin/auto-translation/update-config', 'admin/auto-translation/test-connection'] as const) {
			expect((await api(endpoint, {}, alice)).status).toBe(403);
		}
		expect((await api('auto-translation/capabilities', {}, alice)).body.available).toBe(false);
	});
	test('saves a separate provider without returning its secret', async () => {
		const saved = await api('admin/auto-translation/update-config', {
			enabled: true, baseUrl: `http://127.0.0.1:${(provider.address() as { port: number }).port}/v1`,
			model: 'translation-test', apiKey: 'e2e-only-key', allowPrivateNetwork: true, maxConcurrency: 16,
		}, admin);
		expect(saved.status).toBe(200);
		expect(saved.body.apiKeyConfigured).toBe(true);
		expect(JSON.stringify(saved.body)).not.toContain('e2e-only-key');
		const read = await api('admin/auto-translation/get-config', {}, admin);
		expect(read.body).toEqual(saved.body);
		expect((await api('admin/auto-translation/update-config', { maxConcurrency: 17 }, admin)).status).toBe(400);
		expect((await api('admin/auto-translation/test-connection', {}, admin)).status).toBe(204);
		expect((await api('auto-translation/capabilities', {}, alice)).body.available).toBe(true);
	});
	test('skips same-language notes and translates foreign notes', async () => {
		const japanese = await post(alice, { text: '今日はよく晴れています' });
		const skipped = await api('auto-translation/translate-note', { noteId: japanese.id, targetLang: 'ja' }, alice);
		expect(skipped.body.status).toBe('sameLanguage');
		const mixed = await post(alice, { text: 'Example Editorを使ったよ' });
		expect((await api('auto-translation/translate-note', { noteId: mixed.id, targetLang: 'ja' }, alice)).body.status).toBe('sameLanguage');
		const short = await post(alice, { text: '夜が更ける' });
		expect((await api('auto-translation/translate-note', { noteId: short.id, targetLang: 'ja' }, alice)).body.status).toBe('sameLanguage');
		expect(calls).toBe(0);
		const english = await post(alice, { text: 'Hello @alice :blobcat:' });
		const translated = await api('auto-translation/translate-note', { noteId: english.id, targetLang: 'ja' }, alice);
		expect(translated.status).toBe(200);
		expect(translated.body.text).toBe('こんにちは @alice :blobcat:');
		expect((await api('auto-translation/translate-note', { noteId: english.id, targetLang: 'invalid' }, alice)).status).toBe(400);
	});
	test('does not disclose cached translations of private notes', async () => {
		const note = await post(alice, { text: 'Hello private note', visibility: 'specified', visibleUserIds: [alice.id] });
		expect((await api('auto-translation/translate-note', { noteId: note.id, targetLang: 'ja' }, alice)).status).toBe(200);
		const denied = await api('auto-translation/translate-note', { noteId: note.id, targetLang: 'ja' }, bob);
		expect(denied.status).toBe(400);
		expect(castAsError(denied.body).error.code).toBe('CANNOT_TRANSLATE_INVISIBLE_NOTE');
	});
	test('supports clearing the credential while disabled', async () => {
		const cleared = await api('admin/auto-translation/update-config', { enabled: false, apiKey: null }, admin);
		expect(cleared.body.apiKeyConfigured).toBe(false);
		expect((await api('auto-translation/capabilities', {}, alice)).body.available).toBe(false);
	});
});
