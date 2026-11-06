/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { entities } from 'misskey-js';

const mocks = vi.hoisted(() => ({ api: vi.fn(), account: { id: 'alice' } }));
vi.mock('@/utility/misskey-api.js', () => ({ misskeyApi: mocks.api }));
vi.mock('@/i.js', () => ({ $i: mocks.account }));

describe('automatic translation client', () => {
	beforeEach(() => { vi.resetModules(); mocks.api.mockReset(); });
	test('coalesces requests and limits active calls to two', async () => {
		let active = 0;
		let peak = 0;
		mocks.api.mockImplementation(async () => {
			active++; peak = Math.max(peak, active);
			await new Promise(resolve => setTimeout(resolve, 5));
			active--;
			return { status: 'translated', text: 'test', cw: null, sourceLang: 'en', targetLang: 'ja' };
		});
		const { requestAutoTranslation } = await import('@/utility/auto-translation.js');
		const note = { id: 'n', text: 'Hello', cw: null } as entities.Note;
		await Promise.all(Array.from({ length: 20 }, (_, i) => requestAutoTranslation({ ...note, id: `n${i % 10}` }, 'ja', () => true)));
		expect(peak).toBe(2);
		expect(mocks.api).toHaveBeenCalledTimes(10);
	});
	test('does not dispatch a stale queued request', async () => {
		const releases: (() => void)[] = [];
		mocks.api.mockImplementation(async () => { await new Promise<void>(resolve => { releases.push(resolve); }); return {}; });
		const { requestAutoTranslation } = await import('@/utility/auto-translation.js');
		const note = { id: 'n', text: 'Hello', cw: null } as entities.Note;
		const first = requestAutoTranslation(note, 'ja', () => true);
		const second = requestAutoTranslation({ ...note, id: 'n2' }, 'ja', () => true);
		let current = true;
		const third = requestAutoTranslation({ ...note, id: 'n3' }, 'ja', () => current);
		const assertion = expect(third).rejects.toThrow('cancelled');
		current = false;
		releases[0]();
		await first;
		await assertion;
		releases[1]();
		await second;
		expect(mocks.api).toHaveBeenCalledTimes(2);
	});
	test('keeps a shared queued request when another visible consumer remains', async () => {
		const releases: (() => void)[] = [];
		mocks.api.mockImplementation(async () => { await new Promise<void>(resolve => releases.push(resolve)); return { text: 'translated' }; });
		const { requestAutoTranslation } = await import('@/utility/auto-translation.js');
		const note = { id: 'n', text: 'Hello', cw: null } as entities.Note;
		const first = requestAutoTranslation({ ...note, id: 'one' }, 'ja', () => true);
		const second = requestAutoTranslation({ ...note, id: 'two' }, 'ja', () => true);
		let current = true;
		const stale = requestAutoTranslation(note, 'ja', () => current);
		const visible = requestAutoTranslation(note, 'ja', () => true);
		current = false;
		releases[0]();
		await first;
		expect(mocks.api).toHaveBeenCalledTimes(3);
		releases[1](); releases[2]();
		await Promise.all([second, stale, visible]);
	});
});
