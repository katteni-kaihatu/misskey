/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { describe, expect, test, vi } from 'vitest';
import { fetchResoniteSummary, getResoniteResource, parseResoniteText, resoniteImageUrl } from './resonite.js';

const worldUrl = 'https://go.resonite.com/world/U-Test/R-12345678-1234-1234-1234-123456789abc';
const sessionUrl = 'https://go.resonite.com/session/S-U-Test:Headless';
const world = { id: 'R-12345678-1234-1234-1234-123456789abc', ownerId: 'U-Test', name: '<color=hero.cyan>Cozy Cave</color>', description: 'A pile of blankets by a fire', ownerName: 'Nix', isPublic: true, recordType: 'world', visits: 24, thumbnailUri: `resdb:///${'a'.repeat(64)}.webp`, lastModificationTime: '2026-11-19T02:08:44Z', submissions: [{ featured: true }] };
const session = { sessionId: 'S-U-Test:Headless', name: 'Cozy session', description: 'Welcome', hostUsername: 'Host', joinedUsers: 5, totalJoinedUsers: 40, maxUsers: 32, sessionBeginTime: '2026-11-22T00:00:00Z', accessLevel: 'Anyone', hideFromListing: false, isValid: true, hasEnded: false, thumbnailUrl: 'https://thumbnails.resonite.com/session.webp', correspondingWorldId: { ownerId: world.ownerId, recordId: world.id } };

describe('Resonite link previews', () => {
	test.each([worldUrl, worldUrl.replace('/world/', '/record/'), worldUrl.replace('go.resonite.com/world/', 'api.resonite.com/open/world/')])('normalizes public world links %s', url => {
		expect(getResoniteResource(`${url}?tracking=1#details`)).toEqual({ type: 'world', url: worldUrl, apiPath: `/users/${world.ownerId}/records/${world.id}` });
	});
	test('accepts custom session ids and encoded colons', () => {
		expect(getResoniteResource(sessionUrl)?.apiPath).toBe('/sessions/S-U-Test%3AHeadless');
		expect(getResoniteResource(sessionUrl.replace(':Headless', '%3AHeadless'))).toEqual(getResoniteResource(sessionUrl));
	});
	test.each(['https://go.resonite.com.evil/world/U-Test/R-test', 'http://go.resonite.com/world/U-Test/R-test', 'https://go.resonite.com:8443/world/U-Test/R-test', 'https://user@go.resonite.com/world/U-Test/R-test', 'https://go.resonite.com/world/U-Test/R-test/extra', 'https://go.resonite.com/session/S-%2Ftest', 'https://go.resonite.com/world/%2e%2e/R-test', 'https://go.resonite.com/session/%'])('rejects unsafe or unrelated URLs without fetching: %s', async url => {
		const get = vi.fn();
		expect(await fetchResoniteSummary(url, get)).toBeNull();
		expect(get).not.toHaveBeenCalled();
	});
	test('maps public world metadata and converts assets without returning executable records', async () => {
		const result = await fetchResoniteSummary(worldUrl, async () => ({ ...world, assetUri: 'resdb:///private.brson' }));
		expect(result).toMatchObject({ title: 'Cozy Cave', description: world.description, thumbnail: `https://assets.resonite.com/${'a'.repeat(64)}`, resonite: { state: 'available', creator: 'Nix', visits: 24, featured: true, titleParts: [{ text: 'Cozy Cave', color: '#61d1fa' }] } });
		expect(JSON.stringify(result)).not.toContain('assetUri');
	});
	test.each([{ isPublic: false }, { recordType: 'object' }])('does not disclose private or non-world records: %j', async patch => {
		const result = await fetchResoniteSummary(worldUrl, async () => ({ ...world, ...patch }));
		expect(result).toMatchObject({ title: null, description: null, thumbnail: null, resonite: { state: 'unavailable' } });
		expect(result?.resonite.creator).toBeUndefined();
	});
	test('maps current session occupancy and verifies the corresponding public world', async () => {
		const get = vi.fn(async (url: string) => url.includes('/sessions/') ? session : world);
		const result = await fetchResoniteSummary(sessionUrl, get);
		expect(result).toMatchObject({ title: 'Cozy session', description: 'Welcome', resonite: { creator: 'Host', currentUsers: 5, maxUsers: 32, worldUrl } });
		expect(get).toHaveBeenCalledTimes(2);
	});
	test('uses saved world description when the session has none', async () => {
		const result = await fetchResoniteSummary(sessionUrl, async url => url.includes('/sessions/') ? { ...session, description: '' } : world);
		expect(result?.description).toBe(world.description);
	});
	test.each([{ accessLevel: 'Private' }, { accessLevel: 'Contacts' }, { hideFromListing: true }, { isValid: false }])('hides restricted or invalid session details: %j', async patch => {
		const get = vi.fn(async () => ({ ...session, ...patch }));
		const result = await fetchResoniteSummary(sessionUrl, get);
		expect(result).toMatchObject({ title: null, description: null, thumbnail: null, resonite: { state: 'unavailable' } });
		expect(get).toHaveBeenCalledTimes(1);
	});
	test('ended sessions retain only a verified public world as a fallback', async () => {
		const result = await fetchResoniteSummary(sessionUrl, async url => url.includes('/sessions/') ? { ...session, hasEnded: true, isValid: false } : world);
		expect(result?.resonite).toMatchObject({ state: 'ended', worldUrl });
	});
	test('secondary world failures do not break the session card', async () => {
		const result = await fetchResoniteSummary(sessionUrl, async url => {
			if (url.includes('/sessions/')) return session;
			throw new Error('No world');
		});
		expect(result?.resonite.state).toBe('available');
		expect(result?.resonite.worldUrl).toBeUndefined();
	});
	test('missing metadata is not shown as zero and mismatched ids are rejected', async () => {
		const result = await fetchResoniteSummary(sessionUrl, async () => ({ ...session, correspondingWorldId: null, joinedUsers: -1, maxUsers: NaN }));
		expect(result?.resonite.currentUsers).toBeUndefined();
		expect(result?.resonite.maxUsers).toBeUndefined();
		expect((await fetchResoniteSummary(worldUrl, async () => ({ ...world, id: 'R-other' })))?.resonite.state).toBe('error');
	});
	test.each([401, 403, 404, 429, 500])('maps failure %s to a bounded state', async statusCode => {
		const result = await fetchResoniteSummary(worldUrl, async () => { throw Object.assign(new Error('private server detail'), { statusCode }); });
		expect(result?.resonite.state).toBe([401, 403, 404].includes(statusCode) ? 'unavailable' : 'error');
		expect(JSON.stringify(result)).not.toContain('private server detail');
	});
	test('rich names preserve only text and known colors', () => {
		expect(parseResoniteText('<color=#ff0000>A<color="hero.cyan">B</color>C</color><img src=x onerror=alert(1)><br>D')).toEqual([{ text: 'A', color: '#ff0000' }, { text: 'B', color: '#61d1fa' }, { text: 'C', color: '#ff0000' }, { text: '\nD' }]);
		expect(parseResoniteText('<color="url(https://evil)">text</color>')).toEqual([{ text: 'text' }]);
		expect(parseResoniteText('<color=__proto__>text</color>')).toEqual([{ text: 'text' }]);
	});
	test('accepts only trusted image hosts', () => {
		expect(resoniteImageUrl(session.thumbnailUrl)).toBe(session.thumbnailUrl);
		expect(resoniteImageUrl('https://thumbnails.resonite.com.evil/a.png')).toBeNull();
		expect(resoniteImageUrl('http://assets.resonite.com/a')).toBeNull();
		expect(resoniteImageUrl('https://user@assets.resonite.com/a')).toBeNull();
	});
});
