/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import type { entities } from 'misskey-js';
import { misskeyApi } from '@/utility/misskey-api.js';

const { apiMock } = vi.hoisted(() => ({ apiMock: vi.fn() }));
vi.mock('@/utility/misskey-api.js', () => ({ misskeyApi: apiMock }));
vi.mock('@/composables/use-note-capture.js', () => ({ noteEvents: { emit: vi.fn() } }));
type Reactions = typeof import('@/utility/extended-reactions.js');
let fetchExtendedReactions: Reactions['fetchExtendedReactions'];
let fetchReactionUsers: Reactions['fetchReactionUsers'];
let supportsExtendedReactions: Reactions['supportsExtendedReactions'];
let watchSharedReactions: Reactions['watchSharedReactions'];
let reactionRetryDelay: Reactions['reactionRetryDelay'];
beforeEach(async () => {
	vi.resetModules(); apiMock.mockReset();
	({ fetchExtendedReactions, fetchReactionUsers, supportsExtendedReactions, watchSharedReactions, reactionRetryDelay } = await import('@/utility/extended-reactions.js'));
});
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

describe('paired extended reactions', () => {
	test('push subscriptions do not poll and resynchronize when the tab becomes visible', async () => {
		vi.useFakeTimers();
		const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
		const refresh = vi.fn(); const stop = watchSharedReactions(refresh, true);
		await vi.advanceTimersByTimeAsync(120000);
		expect(refresh).not.toHaveBeenCalled();
		hidden.mockReturnValue(true); document.dispatchEvent(new Event('visibilitychange'));
		expect(refresh).not.toHaveBeenCalled();
		hidden.mockReturnValue(false); document.dispatchEvent(new Event('visibilitychange'));
		expect(refresh).toHaveBeenCalledTimes(1);
		stop(); document.dispatchEvent(new Event('visibilitychange'));
		expect(refresh).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(0);
	});
	test('enables only local notes or marked public/home peer notes', () => {
		const note = { user: { host: null }, visibility: 'public' } as entities.Note;
		expect(supportsExtendedReactions(note)).toBe(true);
		expect(supportsExtendedReactions({ ...note, user: { host: 'other.example' } } as entities.Note)).toBe(false);
		const peer = { ...note, user: { host: 'peer.example' }, gridspaceShared: true } as entities.Note;
		expect(supportsExtendedReactions(peer)).toBe(true);
		expect(supportsExtendedReactions({ ...peer, visibility: 'home', localOnly: true })).toBe(true);
		expect(supportsExtendedReactions({ ...peer, visibility: 'followers' })).toBe(false);
		expect(supportsExtendedReactions({ ...peer, gridspaceShared: false, gridspaceReactions: true, visibility: 'followers' })).toBe(true);
		expect(supportsExtendedReactions({ ...peer, channel: { id: 'channel' } } as entities.Note)).toBe(false);
	});
	test('deduplicates mounted copies and batches no more than 100 notes', async () => {
		vi.useFakeTimers();
		const api = vi.mocked(misskeyApi);
		api.mockImplementation((async (_endpoint: string, options: { noteIds: string[] }) => options.noteIds.map(noteId => ({ noteId }))) as never);
		const waiting = Promise.all([...Array.from({ length: 101 }, (_, n) => fetchExtendedReactions(String(n))), fetchExtendedReactions('0')]);
		await vi.advanceTimersByTimeAsync(1000);
		const values = await waiting;
		expect(api).toHaveBeenCalledTimes(2);
		expect(api.mock.calls[0][1]).toMatchObject({ noteIds: Array.from({ length: 100 }, (_, n) => String(n)) });
		expect(values[0]).toBe(values[101]);
	});
	test('shares one timer, pauses in hidden tabs and disposes the last subscription', async () => {
		vi.useFakeTimers();
		const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
		const first = vi.fn(); const second = vi.fn();
		const stopFirst = watchSharedReactions(first); const stopSecond = watchSharedReactions(second);
		expect(vi.getTimerCount()).toBe(1);
		await vi.advanceTimersByTimeAsync(10000);
		expect(first).toHaveBeenCalledTimes(1); expect(second).toHaveBeenCalledTimes(1);
		hidden.mockReturnValue(true); await vi.advanceTimersByTimeAsync(10000);
		expect(first).toHaveBeenCalledTimes(1);
		stopFirst(); hidden.mockReturnValue(false); await vi.advanceTimersByTimeAsync(10000);
		expect(second).toHaveBeenCalledTimes(2); expect(first).toHaveBeenCalledTimes(1);
		stopSecond(); expect(vi.getTimerCount()).toBe(0);
	});
	test('shares a pending show across different microtasks but reads again after completion', async () => {
		vi.useFakeTimers();
		let resolve!: (value: unknown) => void;
		const api = vi.mocked(misskeyApi).mockImplementation(() => new Promise(r => { resolve = r; }) as never);
		const first = fetchExtendedReactions('pending');
		await vi.advanceTimersByTimeAsync(25);
		const second = fetchExtendedReactions('pending');
		expect(api).toHaveBeenCalledTimes(1);
		resolve([{ noteId: 'pending' }]);
		expect(await first).toBe(await second);
		const third = fetchExtendedReactions('pending');
		await vi.advanceTimersByTimeAsync(600);
		expect(api).toHaveBeenCalledTimes(2);
		resolve([{ noteId: 'pending' }]); await third;
	});
	test('shares avatars with hover and duplicate views, but refreshes changed membership and expired results', async () => {
		vi.useFakeTimers();
		const api = vi.mocked(misskeyApi).mockResolvedValue([] as never);
		await Promise.all([fetchReactionUsers('avatars', '👍', true, 2, 'a'), fetchReactionUsers('avatars', '👍', true, 2, 'a')]);
		await fetchReactionUsers('avatars', '👍', true, 2, 'a');
		expect(api).toHaveBeenCalledTimes(1);
		await fetchReactionUsers('avatars', '👍', true, 2, 'b');
		expect(api).toHaveBeenCalledTimes(2);
		await vi.advanceTimersByTimeAsync(5001);
		await fetchReactionUsers('avatars', '👍', true, 2, 'b');
		expect(api).toHaveBeenCalledTimes(3);
	});
	test('does not cache failed reactor requests', async () => {
		const api = vi.mocked(misskeyApi).mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce([] as never);
		await expect(fetchReactionUsers('retry', '👍', true, 1, 'a')).rejects.toThrow('offline');
		await expect(fetchReactionUsers('retry', '👍', true, 1, 'a')).resolves.toEqual([]);
		expect(api).toHaveBeenCalledTimes(2);
	});
	test('combines separate per-note update timers into one show request', async () => {
		vi.useFakeTimers();
		const api = vi.mocked(misskeyApi).mockImplementation((async (_endpoint, input: { noteIds: string[] }) => input.noteIds.map(noteId => ({ noteId }))) as never);
		const waiting: Promise<unknown>[] = [];
		for (let i = 0; i < 80; i++) window.setTimeout(() => { waiting.push(fetchExtendedReactions(`timer${i}`)); }, 100);
		await vi.advanceTimersByTimeAsync(1000);
		await Promise.all(waiting);
		expect(api).toHaveBeenCalledTimes(1);
		expect(api.mock.calls[0][1]).toMatchObject({ noteIds: expect.any(Array) });
		expect((api.mock.calls[0][1] as { noteIds: string[] }).noteIds).toHaveLength(80);
	});
	test('a show 429 pauses the whole queue instead of retrying once per note', async () => {
		vi.useFakeTimers();
		const error = { code: 'RATE_LIMIT_EXCEEDED', info: { reset: 'invalid' } };
		const api = vi.mocked(misskeyApi).mockRejectedValueOnce(error)
			.mockImplementation((async (_endpoint, input: { noteIds: string[] }) => input.noteIds.map(noteId => ({ noteId }))) as never);
		const first = fetchExtendedReactions('limited').catch(value => value);
		await vi.advanceTimersByTimeAsync(25);
		expect(await first).toBe(error);
		expect(reactionRetryDelay(error)).toBe(60000);
		const waiting = Promise.all(Array.from({ length: 50 }, (_, i) => fetchExtendedReactions(`after${i}`)));
		await vi.advanceTimersByTimeAsync(59000);
		expect(api).toHaveBeenCalledTimes(1);
		await vi.advanceTimersByTimeAsync(1025);
		expect(await waiting).toHaveLength(50);
		expect(api).toHaveBeenCalledTimes(2);
	});
	test('list 429 cooldown is shared by different notes and expires', async () => {
		vi.useFakeTimers();
		const error = { code: 'RATE_LIMIT_EXCEEDED' };
		const api = vi.mocked(misskeyApi).mockRejectedValueOnce(error).mockResolvedValue([] as never);
		await expect(fetchReactionUsers('first', '👍', true, 1)).rejects.toBe(error);
		await expect(fetchReactionUsers('second', '👍', true, 1)).rejects.toBe(error);
		expect(api).toHaveBeenCalledTimes(1);
		await vi.advanceTimersByTimeAsync(60001);
		await expect(fetchReactionUsers('second', '👍', true, 1)).resolves.toEqual([]);
		expect(api).toHaveBeenCalledTimes(2);
	});
});
