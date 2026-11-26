/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test, vi } from 'vitest';
import { normalizeSpaceTileHosts } from './SpaceTileDefService.js';
import { parseSpaceTileFetchUrl, SpaceTileFetchService } from './SpaceTileFetchService.js';

type Args = ConstructorParameters<typeof SpaceTileFetchService>;

function response(status: number, headers: Record<string, string>, body = ''): unknown {
	return { status, headers: { get: (name: string) => headers[name.toLowerCase()] ?? null }, text: async () => body };
}

function fixture(responses: unknown[]) {
	const cache = new Map<string, string>();
	const redis = {
		get: vi.fn(async (key: string) => cache.get(key) ?? null),
		set: vi.fn(async (key: string, value: string) => { cache.set(key, value); return 'OK'; }),
	};
	const http = { send: vi.fn(async () => responses.shift()) };
	const service = new SpaceTileFetchService(redis as unknown as Args[0], http as unknown as Args[1]);
	return { service, redis, http };
}

describe('hosts a tile may read', () => {
	test('hosts are lowercased and de-duplicated; addresses and bare names are dropped', () => {
		expect(normalizeSpaceTileHosts(['API.Example.com', 'api.example.com', ' b.example.org '])).toEqual(['api.example.com', 'b.example.org']);
		expect(normalizeSpaceTileHosts(['localhost', '127.0.0.1', '10.0.0.1', 'example.com:8080', 'https://example.com', 'a..b', '-a.com', '[::1]', '*.example.com'])).toEqual([]);
	});

	test('only https URLs on an allowed host can be read', () => {
		const allowed = ['api.example.com'];
		expect(parseSpaceTileFetchUrl('https://api.example.com/v1?q=1', allowed)?.href).toBe('https://api.example.com/v1?q=1');
		expect(parseSpaceTileFetchUrl('https://API.example.com/', allowed)).not.toBeNull();
		expect(parseSpaceTileFetchUrl('http://api.example.com/', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('https://evil.example.com/', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('https://api.example.com.evil.test/', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('https://user:pw@api.example.com/', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('https://api.example.com:8443/', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('https://api.example.com@evil.test/', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('not a url', allowed)).toBeNull();
		expect(parseSpaceTileFetchUrl('https://api.example.com/', [])).toBeNull();
	});
});

describe('reading a URL for a tile', () => {
	test('the body comes back as text and redirects are not followed automatically', async () => {
		const f = fixture([response(200, { 'content-type': 'application/json' }, '{"a":1}')]);
		expect(await f.service.fetch('https://api.example.com/a', ['api.example.com'])).toEqual({ status: 200, contentType: 'application/json', text: '{"a":1}' });
		expect(f.http.send).toHaveBeenCalledWith('https://api.example.com/a', expect.objectContaining({ method: 'GET', redirect: 'manual' }), expect.anything());
	});

	test('a URL that is not allowed is never requested', async () => {
		const f = fixture([]);
		expect(await f.service.fetch('https://evil.test/', ['api.example.com'])).toBeNull();
		expect(f.http.send).not.toHaveBeenCalled();
	});

	test('a redirect is followed only to an allowed host', async () => {
		const ok = fixture([response(302, { location: '/b' }), response(200, {}, 'done')]);
		expect((await ok.service.fetch('https://api.example.com/a', ['api.example.com']))?.text).toBe('done');
		expect(ok.http.send).toHaveBeenLastCalledWith('https://api.example.com/b', expect.anything(), expect.anything());

		const away = fixture([response(302, { location: 'https://evil.test/steal' })]);
		expect(await away.service.fetch('https://api.example.com/a', ['api.example.com'])).toBeNull();
		expect(away.http.send).toHaveBeenCalledTimes(1);

		const downgrade = fixture([response(301, { location: 'http://api.example.com/a' })]);
		expect(await downgrade.service.fetch('https://api.example.com/a', ['api.example.com'])).toBeNull();
	});

	test('an endless chain of redirects gives up', async () => {
		const f = fixture(Array.from({ length: 10 }, () => response(302, { location: '/again' })));
		expect(await f.service.fetch('https://api.example.com/a', ['api.example.com'])).toBeNull();
		expect(f.http.send).toHaveBeenCalledTimes(6);
	});

	test('the same URL is read once and then remembered for a while', async () => {
		const f = fixture([response(200, {}, 'first'), response(200, {}, 'second')]);
		await f.service.fetch('https://api.example.com/a', ['api.example.com']);
		expect((await f.service.fetch('https://api.example.com/a', ['api.example.com']))?.text).toBe('first');
		expect(f.http.send).toHaveBeenCalledTimes(1);
	});

	test('a result read under wider permission is not handed to a tile with narrower permission', async () => {
		const f = fixture([response(302, { location: 'https://b.example.org/secret' }), response(200, {}, 'from b'), response(302, { location: 'https://b.example.org/secret' })]);
		expect((await f.service.fetch('https://api.example.com/a', ['api.example.com', 'b.example.org']))?.text).toBe('from b');
		expect(await f.service.fetch('https://api.example.com/a', ['api.example.com'])).toBeNull();
	});
});
