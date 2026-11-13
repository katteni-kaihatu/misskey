/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test } from 'vitest';
import { decodeDoomResult, doomResultUrl, doomScore, doomTime, isDoomIwad, parseDoomResult } from '@/utility/doom.js';
import type { DoomResult } from '@/utility/doom.js';

const result: DoomResult = {
	version: 1, game: 'freedoom', episode: 1, map: 2, skill: 3,
	kills: 10, totalKills: 12, items: 4, totalItems: 5, secrets: 1, totalSecrets: 2,
	ticks: 35 * 125, completed: true, dead: false,
};

describe('DOOM result sharing', () => {
	test('round trips a result in a public URL without account data', () => {
		const url = new URL(doomResultUrl('https://example.com', result));
		expect(url.pathname).toBe('/play/doom');
		expect(decodeDoomResult(url.searchParams.get('result') ?? undefined)).toEqual(result);
		expect(doomScore(result)).toBe(1290);
		expect(doomTime(result.ticks)).toBe('2:05');
	});

	test('rejects malformed, oversized and unsupported shared results', () => {
		for (const data of [undefined, '', '{', 'x'.repeat(1001), 'null', '[]']) {
			expect(decodeDoomResult(data)).toBeNull();
		}
		for (const patch of [
			{ version: 2 }, { game: '<script>' }, { game: ['doom'] }, { episode: 0 }, { map: 100 },
			{ skill: 6 }, { kills: -1 }, { ticks: Infinity }, { ticks: 1.5 },
			{ secrets: 3 }, { items: 6 }, { completed: 'true' },
		]) expect(parseDoomResult({ ...result, ...patch })).toBeNull();
	});

	test('accepts extra kills from respawning enemies and drops unrelated data', () => {
		expect(parseDoomResult({ ...result, kills: 20, token: 'private' })).toEqual({ ...result, kills: 20 });
	});
});

describe('DOOM IWAD validation', () => {
	test('requires an IWAD with an in-bounds lump directory', () => {
		const wad = new Uint8Array(28);
		wad.set(new TextEncoder().encode('IWAD'));
		const view = new DataView(wad.buffer);
		view.setUint32(4, 1, true);
		view.setUint32(8, 12, true);
		expect(isDoomIwad(wad)).toBe(true);
		view.setUint32(8, 13, true);
		expect(isDoomIwad(wad)).toBe(false);
		wad.set(new TextEncoder().encode('PWAD'));
		expect(isDoomIwad(wad)).toBe(false);
		expect(isDoomIwad(new Uint8Array(5))).toBe(false);
	});
});
