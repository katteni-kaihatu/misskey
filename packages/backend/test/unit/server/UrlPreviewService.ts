/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, describe, expect, test, vi } from 'vitest';
import { UrlPreviewService } from '@/server/web/UrlPreviewService.js';

vi.mock('@/core/HttpRequestService.js', () => ({ HttpRequestService: class {} }));
vi.mock('@/core/UtilityService.js', () => ({ UtilityService: class {} }));
vi.mock('@/core/LoggerService.js', () => ({ LoggerService: class {} }));
vi.mock('@/models/Meta.js', () => ({ MiMeta: class {} }));
vi.mock('@misskey-dev/summaly', () => ({ summaly: vi.fn() }));

const worldUrl = 'https://app.xrift.net/world/4b84ca2a-06cc-4351-a2df-adc904eec8e4';
const summary = { url: worldUrl, title: 'Generic XRift', icon: null, thumbnail: null, player: { url: null } };
const services: UrlPreviewService[] = [];

afterEach(() => {
	for (const service of services.splice(0)) service.dispose();
	vi.unstubAllGlobals();
});

function setup(apiKey: string | null = 'xrift_sk_test') {
	vi.stubGlobal('_SUMMALY_VERSION_', 'test');
	const meta = { xriftApiKey: apiKey, urlPreviewEnabled: true, urlPreviewSummaryProxyUrl: 'https://summary.example', urlPreviewSensitiveList: [] };
	const getJson = vi.fn(async (url: string) => url.startsWith('https://api.xrift.net/') ? {
		data: { id: worldUrl.split('/').at(-1), name: 'School', isPublic: true, thumbnailUrl: 'https://assets.xrift.net/world.jpg' },
	} : { ...summary, player: { url: null } });
	const logger = { info: vi.fn(), succ: vi.fn(), warn: vi.fn() };
	const send = vi.fn(async (url: string, _options?: unknown) => ({ ok: true, status: 200, headers: new Headers(), text: async () => '', json: async () => getJson(url) }));
	const service = new UrlPreviewService({ url: 'https://grid.example', mediaProxy: 'https://media.example' } as never, meta as never,
		{ getJson, send } as never, { isKeyWordIncluded: vi.fn(() => false) } as never, { getLogger: () => logger } as never);
	services.push(service);
	const reply = { header: vi.fn(), code: vi.fn() };
	const request = { query: { url: worldUrl } };
	return { service, meta, getJson, send, logger, request, reply, load: () => service.handle(request as never, reply as never) };
}

describe('XRift preview handling', () => {
	test('uses the official API before the summary proxy, proxies images, and caches results', async () => {
		const { load, getJson, send, reply } = setup();
		const first = await load();
		expect(first).toMatchObject({ title: 'School', xrift: { creator: null }, thumbnail: expect.stringContaining('https://media.example/preview.webp?') });
		expect(new URL((first as { thumbnail: string }).thumbnail).searchParams.get('preview')).toBe('1');
		expect(JSON.stringify(first)).not.toContain('xrift_sk_test');
		expect(await load()).toEqual(first);
		expect(getJson).toHaveBeenCalledTimes(3);
		expect(reply.header).toHaveBeenCalledWith('Cache-Control', 'max-age=300');
		expect(send.mock.calls.every(([, options]) => (options as { redirect?: string }).redirect === 'error')).toBe(true);
	});

	test('keeps ordinary OGP without an API key', async () => {
		const { load, getJson } = setup(null);
		expect(await load()).toMatchObject({ title: 'Generic XRift' });
		expect(getJson).toHaveBeenCalledTimes(1);
		expect(getJson.mock.calls[0][0]).toMatch(/^https:\/\/summary\.example/);
	});

	test('returns an error card on API failure and does not log upstream secrets', async () => {
		const { load, getJson, logger } = setup();
		getJson.mockRejectedValueOnce(new Error('upstream failure xrift_sk_test'));
		expect(await load()).toMatchObject({ xrift: { state: 'error' } });
		expect(await load()).toMatchObject({ xrift: { state: 'error' } });
		expect(getJson).toHaveBeenCalledTimes(1);
		expect(JSON.stringify(logger.warn.mock.calls)).not.toContain('xrift_sk_test');
	});

	test('key removal bypasses cached world details immediately', async () => {
		const { load, meta, getJson } = setup();
		await load();
		meta.xriftApiKey = null;
		expect(await load()).toMatchObject({ title: 'Generic XRift' });
		expect(getJson).toHaveBeenCalledTimes(4);
	});

	test('coalesces simultaneous requests and canonicalizes tracking parameters and language', async () => {
		const { service, getJson, reply } = setup();
		const requests = [worldUrl, `${worldUrl}/?source=share#world`, worldUrl.toUpperCase().replace('HTTPS://APP.XRIFT.NET/WORLD/', 'https://app.xrift.net/world/')];
		const results = await Promise.all(requests.map((url, i) => service.handle({ query: { url, lang: i ? 'en' : 'ja' } } as never, reply as never)));
		expect(results.every(result => (result as { title: string }).title === 'School')).toBe(true);
		expect(getJson).toHaveBeenCalledTimes(3);
	});

	test('disabled URL previews never access XRift', async () => {
		const { load, meta, getJson, reply } = setup();
		meta.urlPreviewEnabled = false;
		await load();
		expect(reply.code).toHaveBeenCalledWith(403);
		expect(getJson).not.toHaveBeenCalled();
	});
	test('honors a shared rate-limit reset across different resources', async () => {
		const { load, send, service, reply } = setup();
		send.mockResolvedValueOnce({ ok: false, status: 429, headers: new Headers({ 'X-RateLimit-Reset': String(Math.ceil(Date.now() / 1000) + 600) }), text: async () => '', json: async () => ({ data: {} }) });
		expect(await load()).toMatchObject({ xrift: { state: 'error' } });
		const result = await service.handle({ query: { url: worldUrl.replace('/world/', '/user/') } } as never, reply as never);
		expect(result).toMatchObject({ xrift: { state: 'error' } });
		expect(send).toHaveBeenCalledTimes(1);
	});
});

describe('Resonite preview handling', () => {
	const url = 'https://go.resonite.com/session/S-Test';
	test('fetches without credentials, coalesces requests and proxies the thumbnail', async () => {
		const { service, getJson, send, reply } = setup(null);
		getJson.mockImplementation(async () => ({ sessionId: 'S-Test', name: 'Public session', description: 'Welcome', hostUsername: 'Host', accessLevel: 'Anyone', hideFromListing: false, isValid: true, hasEnded: false, joinedUsers: 3, totalJoinedUsers: 20, maxUsers: 16, thumbnailUrl: 'https://thumbnails.resonite.com/test.webp' }) as never);
		const results = await Promise.all([url, `${url}?share=1`].map(input => service.handle({ query: { url: input } } as never, reply as never)));
		expect(results[0]).toMatchObject({ title: 'Public session', resonite: { state: 'available', currentUsers: 3, maxUsers: 16 }, thumbnail: expect.stringContaining('https://media.example/preview.webp?') });
		expect(results[1]).toEqual(results[0]);
		expect(new URL((results[0] as { thumbnail: string }).thumbnail).searchParams.has('preview')).toBe(false);
		expect(send).toHaveBeenCalledTimes(1);
		expect(send.mock.calls[0][1]).toMatchObject({ redirect: 'error', headers: { Accept: 'application/json' } });
		expect(JSON.stringify(send.mock.calls)).not.toContain('Authorization');
		expect(reply.header).toHaveBeenCalledWith('Cache-Control', 'max-age=60');
	});
	test('keeps the error card when the provider fails instead of loading an unrelated player', async () => {
		const { service, getJson, reply } = setup(null);
		getJson.mockRejectedValueOnce(new Error('provider unavailable'));
		expect(await service.handle({ query: { url } } as never, reply as never)).toMatchObject({ resonite: { state: 'error' } });
		expect(getJson).toHaveBeenCalledTimes(1);
	});
});
