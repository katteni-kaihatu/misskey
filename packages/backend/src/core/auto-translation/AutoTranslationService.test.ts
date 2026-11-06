/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Agent, createServer } from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';
import { afterAll, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import { Redis } from 'ioredis';
import type { DataSource } from 'typeorm';
import type { NotesRepository } from '@/models/_.js';
import type { MiLocalUser } from '@/models/User.js';
import type { NoteEntityService } from '@/core/entities/NoteEntityService.js';
import type { RoleService } from '@/core/RoleService.js';
import type { HttpRequestService } from '@/core/HttpRequestService.js';
import { MiAutoTranslationConfig } from '@/models/AutoTranslationConfig.js';
import UpdateConfig from '@/server/api/endpoints/admin/auto-translation/update-config.js';
import { AutoTranslationService } from './AutoTranslationService.js';

describe('AutoTranslationService', () => {
	const redis = new Redis({ host: '127.0.0.1', port: 56312, db: 14 });
	const agent = new Agent();
	let config: MiAutoTranslationConfig;
	let visible = true;
	let hidden = false;
	let allowed = true;
	let text = 'Hello @alice :blobcat:';
	let calls = 0;
	let active = 0;
	let peak = 0;
	let mode = 'ok';
	const bodies: Record<string, unknown>[] = [];
	const server = createServer(async (req, res) => {
		if (req.headers.authorization !== 'Bearer test-only-secret') { res.writeHead(401).end(); return; }
		if (req.url === '/v1/models') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ data: [{ id: 'test-model' }] })); return; }
		calls++;
		active++;
		peak = Math.max(peak, active);
		const chunks: Buffer[] = [];
		for await (const chunk of req) chunks.push(chunk);
		const body = JSON.parse(Buffer.concat(chunks).toString());
		bodies.push(body);
		await delay(30);
		active--;
		if (mode === 'failure') { res.writeHead(503).end('secret upstream body'); return; }
		if (mode === 'redirect') { res.writeHead(302, { Location: '/v1/models' }).end(); return; }
		res.setHeader('Content-Type', 'application/json');
		res.end(JSON.stringify({ choices: [{ finish_reason: mode === 'truncated' ? 'length' : 'stop', message: {
			content: mode === 'broken-marker' ? 'lost markers' : body.messages[0].content.replace('Hello', 'こんにちは'),
		} }] }));
	});
	const repository = {
		createQueryBuilder: () => ({ addSelect: () => ({ where: () => ({ getOne: async () => ({ ...config }) }) }) }),
		save: vi.fn(async (value: MiAutoTranslationConfig) => { config = { ...value }; return value; }),
	};
	const noteRepository = { findOneBy: vi.fn(async ({ id }: { id: string }) => id === 'missing' ? null : { id, text, cw: null }) };
	const noteEntity = { isVisibleForMe: vi.fn(async () => visible), pack: vi.fn(async () => ({ isHidden: hidden })) };
	const service = new AutoTranslationService(
		{ getRepository: () => repository } as unknown as DataSource, redis,
		noteRepository as unknown as NotesRepository, noteEntity as unknown as NoteEntityService,
		{ getUserPolicies: async () => ({ canUseTranslator: allowed }) } as unknown as RoleService,
		{ getAgentByUrl: () => agent } as unknown as HttpRequestService,
	);
	const me = { id: 'viewer' } as MiLocalUser;
	beforeAll(async () => { await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve)); });
	beforeEach(async () => {
		await redis.flushdb();
		config = Object.assign(new MiAutoTranslationConfig(), { id: 1, enabled: true,
			baseUrl: `http://127.0.0.1:${(server.address() as { port: number }).port}/v1`, model: 'test-model', apiKey: 'test-only-secret',
			allowPrivateNetwork: true, maxConcurrency: 3, revision: 'v1' });
		visible = true; hidden = false; allowed = true; calls = 0; active = 0; peak = 0; mode = 'ok'; bodies.length = 0;
		text = 'Hello @alice :blobcat:';
	});
	afterAll(async () => { await redis.quit(); agent.destroy(); await new Promise<void>(resolve => server.close(() => resolve())); });
	test('never returns the saved credential and preserves it on partial updates', async () => {
		expect(JSON.stringify(await service.getAdminConfig())).not.toContain('test-only-secret');
		await service.updateConfig({ model: 'test-model' });
		expect(config.apiKey).toBe('test-only-secret');
		await expect(service.updateConfig({ maxConcurrency: 17 })).rejects.toMatchObject({ reason: 'invalid_config' });
		await expect(service.updateConfig({ baseUrl: 'http://example.com', allowPrivateNetwork: false })).rejects.toMatchObject({ reason: 'invalid_config' });
		await expect(service.updateConfig({ baseUrl: 'https://user:secret@example.com/v1' })).rejects.toMatchObject({ reason: 'invalid_config' });
	});
	test('redacts request credentials and suppresses database error details', async () => {
		const endpoint = new UpdateConfig(service);
		const params = { apiKey: 'new-secret' };
		repository.save.mockRejectedValueOnce(new Error('SQL params: new-secret'));
		await expect(endpoint.exec(params, me, null)).rejects.toMatchObject({ code: 'TRANSLATION_FAILED' });
		expect(params).not.toHaveProperty('apiKey');
		await service.updateConfig({ id: 2, revision: 'attacker' } as never);
		expect(config.id).toBe(1);
		expect(config.revision).not.toBe('attacker');
	});
	test('same-language and non-prose notes do not call the model', async () => {
		text = '今日はいい天気ですね';
		expect((await service.translateNote('n', 'ja-JP', me)).status).toBe('sameLanguage');
		text = ':blobcat: https://example.com `code`';
		expect((await service.translateNote('n', 'ja', me)).status).toBe('skipped');
		expect(calls).toBe(0);
	});
	test('deduplicates requests and checks permissions before cached results', async () => {
		const results = await Promise.all(Array.from({ length: 16 }, () => service.translateNote('n', 'ja', me)));
		expect(calls).toBe(1);
		expect(results[0].text).toBe('こんにちは @alice :blobcat:');
		visible = false;
		await expect(service.translateNote('n', 'ja', me)).rejects.toMatchObject({ reason: 'not_visible' });
		visible = true; hidden = true;
		await expect(service.translateNote('n', 'ja', me)).rejects.toMatchObject({ reason: 'not_visible' });
		hidden = false; allowed = false;
		await expect(service.translateNote('n', 'ja', me)).rejects.toMatchObject({ reason: 'unavailable' });
		expect(calls).toBe(1);
	});
	test('content, language, and provider changes invalidate results', async () => {
		await service.translateNote('n', 'ja', me);
		await service.translateNote('n', 'fr', me);
		text += ' edited';
		await service.translateNote('n', 'ja', me);
		await service.updateConfig({ model: 'test-model' });
		await service.translateNote('n', 'ja', me);
		expect(calls).toBe(4);
	});
	test('enforces a global concurrency bound and releases all slots', async () => {
		await Promise.all(Array.from({ length: 20 }, (_, i) => service.translateNote(`n${i}`, 'ja', me)));
		expect(peak).toBe(3);
		expect(await redis.zcard('auto-translation:running')).toBe(0);
		expect(await redis.zcard('auto-translation:waiting')).toBe(0);
	});
	test.each(['failure', 'redirect', 'truncated', 'broken-marker'])('rejects %s without caching failures', async failureMode => {
		mode = failureMode;
		await expect(service.translateNote('n', 'ja', me)).rejects.toMatchObject({ reason: 'upstream' });
		mode = 'ok';
		expect((await service.translateNote('n', 'ja', me)).status).toBe('translated');
		expect(calls).toBe(2);
	});
	test('checks model availability with the saved bearer key', async () => { await service.testConnection(); });
});
