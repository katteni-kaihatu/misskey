/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test, vi } from 'vitest';
import { fetchXriftSummary } from './xrift.js';

const id = '4b84ca2a-06cc-4351-a2df-adc904eec8e4';
const worldUrl = `https://app.xrift.net/world/${id}`;
const apiKey = 'xrift_sk_test';
const world = {
	id,
	name: 'School world',
	description: 'An afternoon at school.',
	isPublic: true,
	status: 'ACTIVE',
	thumbnailUrl: `https://assets.xrift.net/worlds/${id}/thumbnail.jpg`,
	owner: { displayName: 'World creator' },
};

describe('XRift URL summaries', () => {
	test('maps public world metadata to a summary without an iframe', async () => {
		const getJson = vi.fn().mockResolvedValue({ data: world });
		const summary = await fetchXriftSummary(`${worldUrl}/?source=share#world`, apiKey, getJson);
		expect(getJson).toHaveBeenCalledExactlyOnceWith(`https://api.xrift.net/api/public/v1/worlds/${id}`, { Authorization: `Bearer ${apiKey}` });
		expect(summary).toMatchObject({
			url: worldUrl,
			title: world.name,
			description: world.description,
			thumbnail: world.thumbnailUrl,
			thumbnailStyle: 'summary_large_image',
			sitename: 'XRift',
			xrift: { creator: world.owner.displayName },
			player: { url: null },
		});
	});

	test.each([
		'https://example.com/world/' + id,
		'https://app.xrift.net.evil.example/world/' + id,
		'https://app.xrift.net@evil.example/world/' + id,
		'https://user:password@app.xrift.net/world/' + id,
		'https://app.xrift.net:444/world/' + id,
		'http://app.xrift.net/world/' + id,
		'https://app.xrift.net/world/not-a-uuid',
		worldUrl + '/extra',
		'https://app.xrift.net/worlds',
	])('does not request XRift data for %s', async url => {
		const getJson = vi.fn();
		expect(await fetchXriftSummary(url, apiKey, getJson)).toBeNull();
		expect(getJson).not.toHaveBeenCalled();
	});

	test.each([
		null,
		{},
		{ ...world, id: 'another-world' },
		{ ...world, isPublic: false },
		{ ...world, status: 'DELETED' },
		{ ...world, name: ' ' },
	])('rejects unavailable or malformed world data', async data => {
		await expect(fetchXriftSummary(worldUrl, apiKey, vi.fn().mockResolvedValue({ data }))).rejects.toThrow();
	});

	test.each(['javascript:alert(1)', 'http://assets.xrift.net/image.png', 'https://evil.example/image.png', 'invalid'])('omits unsupported thumbnail %s', async thumbnailUrl => {
		const summary = await fetchXriftSummary(worldUrl, apiKey, vi.fn().mockResolvedValue({ data: { ...world, thumbnailUrl } }));
		expect(summary?.thumbnail).toBeNull();
	});

	test('tolerates missing optional metadata', async () => {
		const summary = await fetchXriftSummary(worldUrl, apiKey, vi.fn().mockResolvedValue({ data: { ...world, status: undefined, thumbnailUrl: null, description: null, owner: null } }));
		expect(summary).toMatchObject({ title: world.name, description: null, thumbnail: null, xrift: { creator: null } });
	});

	test('propagates API failure for the caller to fall back to ordinary OGP', async () => {
		await expect(fetchXriftSummary(worldUrl, apiKey, vi.fn().mockRejectedValue(new Error('Unavailable')))).rejects.toThrow('Unavailable');
	});

	test('does not access either API without a configured key', async () => {
		const getJson = vi.fn();
		expect(await fetchXriftSummary(worldUrl, null, getJson)).toBeNull();
		expect(getJson).not.toHaveBeenCalled();
	});
});
