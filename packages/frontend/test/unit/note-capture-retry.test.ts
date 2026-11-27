/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, expect, test, vi } from 'vitest';
import { render } from '@testing-library/vue';
import { defineComponent } from 'vue';
import type { entities } from 'misskey-js';
import { useNoteCapture, noteEvents } from '@/composables/use-note-capture.js';

const { fetchState } = vi.hoisted(() => ({ fetchState: vi.fn() }));
vi.mock('@@/js/interval.js', () => ({ createVisibilityAwareInterval: vi.fn() }));
vi.mock('@/i.js', () => ({ $i: null }));
vi.mock('@/store.js', () => ({ store: { s: { realtimeMode: false } } }));
vi.mock('@/preferences.js', () => ({ prefer: { s: { pollingInterval: 3 } } }));
vi.mock('@/stream.js', () => ({ useStream: vi.fn() }));
vi.mock('@/utility/misskey-api.js', () => ({ misskeyApi: vi.fn() }));
vi.mock('@/utility/extended-reactions.js', () => ({
	fetchExtendedReactions: fetchState, supportsExtendedReactions: () => true, watchSharedReactions: () => () => {},
	reactionRetryDelay: (error: { code?: string }) => error.code === 'RATE_LIMIT_EXCEEDED' ? 60000 : undefined,
}));

afterEach(() => { fetchState.mockReset(); vi.useRealTimers(); });

test.each([{ code: 'RATE_LIMIT_EXCEEDED', delay: 60000 }, { code: 'NETWORK_ERROR', delay: 1000 }])('events during a failed request do not bypass $code backoff', async ({ code, delay }) => {
	vi.useFakeTimers();
	let reject!: (error: unknown) => void;
	fetchState.mockReturnValueOnce(new Promise((_resolve, fail) => { reject = fail; })).mockResolvedValue(undefined);
	const wrapper = render(defineComponent({ setup() {
		useNoteCapture({ note: { id: 'note', user: { host: null }, createdAt: new Date().toISOString(), reactions: {}, reactionCount: 0, reactionEmojis: {}, visibility: 'public' } as entities.Note, parentNote: null });
		return () => null;
	} }));
	try {
		noteEvents.emit('extendedUpdated:note');
		await vi.advanceTimersByTimeAsync(100);
		reject({ code });
		await vi.advanceTimersByTimeAsync(0);
		noteEvents.emit('extendedUpdated:note');
		await vi.advanceTimersByTimeAsync(delay - 1);
		expect(fetchState).toHaveBeenCalledTimes(1);
		await vi.advanceTimersByTimeAsync(1);
		expect(fetchState).toHaveBeenCalledTimes(2);
	} finally { wrapper.unmount(); }
	await vi.advanceTimersByTimeAsync(120000);
	expect(fetchState).toHaveBeenCalledTimes(2);
});
