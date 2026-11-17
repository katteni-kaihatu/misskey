/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { describe, expect, test, vi } from 'vitest';
import { fetchXriftSummary, getXriftResource } from './xrift.js';

const id = '4b84ca2a-06cc-4351-a2df-adc904eec8e4';
const ownerId = '04aa9951-7d54-4569-ac33-e09f46dbbe3b';
const instanceId = '89c12f72-5e70-4da9-b029-eb9f725bf492';
const worldUrl = `https://app.xrift.net/world/${id}`;
const world = { id, name: 'School world', description: 'An afternoon at school.', isPublic: true, status: 'ACTIVE', ownerId, thumbnailUrl: `https://assets.xrift.net/worlds/${id}/thumbnail.jpg` };
const apiKey = 'xrift_sk_test';

function fixture(overrides: Record<string, unknown> = {}) {
	const routes: Record<string, unknown> = {
		[`/worlds/${id}`]: { data: world },
		[`/worlds/${id}/stats`]: { data: { worldId: id, totalVisits: 12345, visitsLast7Days: 234 } },
		[`/worlds/${id}/instances?limit=1`]: { data: [], pagination: { total: 2 } },
		[`/users/${ownerId}`]: { data: { id: ownerId, displayName: 'World creator', userIconUrl: 'https://assets.xrift.net/avatar.png', createdAt: '2026-01-01T00:00:00.000Z' } },
		[`/users/${ownerId}/worlds?limit=3`]: { data: [world, { ...world, isPublic: false }], pagination: { total: 12 } },
		[`/instances/${instanceId}`]: { data: { id: instanceId, worldId: id, createdAt: '2026-11-17T00:00:00.000Z' } },
		[`/worlds/${id}/instances?limit=50&offset=0`]: { data: [{ id: instanceId, worldId: id }], pagination: { total: 1 } },
		...overrides,
	};
	return vi.fn(async (url: string) => {
		const value = routes[url.replace('https://api.xrift.net/api/public/v1', '')];
		if (value instanceof Error) throw value;
		return value;
	});
}

describe('XRift URL summaries', () => {
	test('maps documented world, creator, statistics and instance count without an iframe', async () => {
		const get = fixture();
		const summary = await fetchXriftSummary(`${worldUrl}/?source=share#world`, apiKey, get);
		expect(summary).toMatchObject({ url: worldUrl, title: world.name, thumbnail: world.thumbnailUrl, xrift: { type: 'world', state: 'available', creator: 'World creator', totalVisits: 12345, visitsLast7Days: 234, publicInstances: 2 }, player: { url: null } });
		expect(get).toHaveBeenCalledTimes(4);
		for (const [url, headers] of get.mock.calls as unknown as [string, object][]) {
			expect(url).toMatch(/^https:\/\/api\.xrift\.net\/api\/public\/v1\//);
			expect(headers).toEqual({ Authorization: `Bearer ${apiKey}` });
		}
	});
	test('joins an instance to its public world', async () => {
		const summary = await fetchXriftSummary(`https://app.xrift.net/instance/${instanceId}`, apiKey, fixture());
		expect(summary).toMatchObject({ title: world.name, xrift: { type: 'instance', state: 'available', worldUrl, createdAt: '2026-11-17T00:00:00.000Z' } });
	});
	test('returns a profile and at most three public worlds', async () => {
		const summary = await fetchXriftSummary(`https://app.xrift.net/user/${ownerId}`, apiKey, fixture());
		expect(summary).toMatchObject({ title: 'World creator', thumbnail: 'https://assets.xrift.net/avatar.png', xrift: { type: 'user', totalWorlds: 12, worlds: [{ url: worldUrl, title: world.name }] } });
		expect(summary?.xrift.worlds).toHaveLength(1);
	});
	test('does not expose a room absent from the public instance list', async () => {
		const summary = await fetchXriftSummary(`https://app.xrift.net/instance/${instanceId}`, apiKey, fixture({ [`/worlds/${id}/instances?limit=50&offset=0`]: { data: [], pagination: { total: 0 } } }));
		expect(summary).toMatchObject({ title: null, thumbnail: null, xrift: { state: 'unavailable' } });
		expect(summary?.xrift.createdAt).toBeUndefined();
	});
	test.each([
		'https://example.com/world/' + id, 'https://app.xrift.net.evil.example/world/' + id,
		'https://app.xrift.net@evil.example/world/' + id, 'https://user:password@app.xrift.net/world/' + id,
		'https://app.xrift.net:444/world/' + id, 'http://app.xrift.net/world/' + id,
		'https://app.xrift.net/world/not-a-uuid', worldUrl + '/extra', 'https://app.xrift.net/worlds', 'invalid',
	])('does not request XRift data for %s', async url => {
		const get = fixture();
		expect(await fetchXriftSummary(url, apiKey, get)).toBeNull();
		expect(get).not.toHaveBeenCalled();
	});
	test('normalizes UUIDs and discards tracking parameters', () => {
		expect(getXriftResource(`${worldUrl.toUpperCase().replace('/WORLD/', '/world/')}?key=tracking#x`)).toEqual({ type: 'world', id, url: worldUrl });
	});
	test.each([{ ...world, isPublic: false }, { ...world, status: 'DELETED' }])('does not expose unavailable world metadata', async value => {
		const get = fixture({ [`/worlds/${id}`]: { data: value } });
		const summary = await fetchXriftSummary(worldUrl, apiKey, get);
		expect(summary).toMatchObject({ title: null, thumbnail: null, xrift: { state: 'unavailable' } });
		expect(get).toHaveBeenCalledTimes(1);
	});
	test.each([null, {}, { ...world, id: 'another-world' }, { ...world, name: ' ' }])('returns a safe state for malformed world data', async value => {
		const summary = await fetchXriftSummary(worldUrl, apiKey, fixture({ [`/worlds/${id}`]: { data: value } }));
		expect(summary?.xrift.state).not.toBe('available');
		expect(summary?.title).toBeNull();
	});
	test.each(['javascript:alert(1)', 'http://assets.xrift.net/image.png', 'https://evil.example/image.png', 'https://user:pass@assets.xrift.net/a', 'invalid'])('omits unsupported image %s', async thumbnailUrl => {
		const summary = await fetchXriftSummary(worldUrl, apiKey, fixture({ [`/worlds/${id}`]: { data: { ...world, thumbnailUrl } } }));
		expect(summary?.thumbnail).toBeNull();
	});
	test('keeps base world data when extra scopes are unavailable; missing counts are not zero', async () => {
		const forbidden = Object.assign(new Error('Forbidden'), { statusCode: 403 });
		const summary = await fetchXriftSummary(worldUrl, apiKey, fixture({ [`/users/${ownerId}`]: forbidden, [`/worlds/${id}/instances?limit=1`]: forbidden, [`/worlds/${id}/stats`]: { data: { worldId: id, totalVisits: -1, visitsLast7Days: '234' } } }));
		expect(summary).toMatchObject({ title: world.name, xrift: { state: 'available', creator: null } });
		expect(summary?.xrift.publicInstances).toBeUndefined();
		expect(summary?.xrift.totalVisits).toBeUndefined();
		expect(summary?.xrift.visitsLast7Days).toBeUndefined();
	});
	test.each([404, 403, 429, 500])('handles HTTP %i without exposing upstream messages', async statusCode => {
		const error = Object.assign(new Error('Secret: xrift_sk_test'), { statusCode });
		const summary = await fetchXriftSummary(`https://app.xrift.net/instance/${instanceId}`, apiKey, fixture({ [`/instances/${instanceId}`]: error }));
		expect(summary?.xrift.state).toBe(statusCode === 404 ? 'unavailable' : 'error');
		expect(JSON.stringify(summary)).not.toContain('Secret');
	});
	test('does not access the API without a configured key', async () => {
		const get = fixture();
		expect(await fetchXriftSummary(worldUrl, null, get)).toBeNull();
		expect(get).not.toHaveBeenCalled();
	});
});
