/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { mainRouter } from '@/router.js';
import { makeHotkey } from '@/utility/hotkey.js';
import { postFromHotkey } from '@/utility/post-from-hotkey.js';

const mocks = vi.hoisted(() => ({
	user: { id: 'user' } as { id: string } | null,
	apiWithDialog: vi.fn(),
	post: vi.fn(),
}));

vi.mock('@/i.js', () => ({ get $i() { return mocks.user; } }));
vi.mock('@/os.js', () => ({ apiWithDialog: mocks.apiWithDialog, post: mocks.post }));
vi.mock('@/router.js', async () => {
	const { Nirax } = await import('@/lib/nirax.js');
	return {
		mainRouter: new Nirax([
			{ path: '/', component: {} },
			{ path: '/channels', component: {} },
			{ path: '/channels/new', component: {} },
			{ path: '/channels/:channelId/edit', component: {} },
			{ path: '/channels/:channelId', component: {} },
		], '/', true, {}),
	};
});

function pressN(): Promise<void> {
	let result = Promise.resolve();
	makeHotkey({
		n: () => {
			result = postFromHotkey();
		},
	})(new KeyboardEvent('keydown', { key: 'n', bubbles: true, cancelable: true }));
	return result;
}

describe('N key post destination', () => {
	const channel = { id: 'channel-a', name: 'Channel A', color: '#000000', isSensitive: false, allowRenoteToExternal: true, userId: null };

	beforeEach(() => {
		vi.resetAllMocks();
		mocks.user = { id: 'user' };
		mocks.apiWithDialog.mockResolvedValue(channel);
		mainRouter.replaceByPath('/');
	});

	afterEach(() => {
		document.body.replaceChildren();
	});

	test('opens a post addressed to the displayed channel', async () => {
		mainRouter.replaceByPath('/channels/channel-a');

		await pressN();

		expect(mocks.apiWithDialog).toHaveBeenCalledWith('channels/show', { channelId: 'channel-a' });
		expect(mocks.post).toHaveBeenCalledExactlyOnceWith({ channel });
	});

	test.each(['/', '/channels', '/channels/new', '/channels/channel-a/edit'])('opens a normal post on %s', async (path) => {
		mainRouter.replaceByPath(path);

		await pressN();

		expect(mocks.apiWithDialog).not.toHaveBeenCalled();
		expect(mocks.post).toHaveBeenCalledExactlyOnceWith();
	});

	test('uses the newly displayed channel after navigation', async () => {
		mainRouter.replaceByPath('/channels/channel-a');
		await pressN();
		const nextChannel = { ...channel, id: 'channel-b', name: 'Channel B' };
		mocks.apiWithDialog.mockResolvedValue(nextChannel);
		mainRouter.replaceByPath('/channels/channel-b');

		await pressN();

		expect(mocks.apiWithDialog).toHaveBeenLastCalledWith('channels/show', { channelId: 'channel-b' });
		expect(mocks.post).toHaveBeenLastCalledWith({ channel: nextChannel });
	});

	test('does not open a stale channel post if navigation occurs while loading', async () => {
		let resolveChannel!: (value: typeof channel) => void;
		mocks.apiWithDialog.mockReturnValue(new Promise(resolve => { resolveChannel = resolve; }));
		mainRouter.replaceByPath('/channels/channel-a');
		const pending = pressN();

		mainRouter.replaceByPath('/channels/channel-b');
		resolveChannel(channel);
		await pending;

		expect(mocks.post).not.toHaveBeenCalled();
	});

	test('does not fall back to a normal post when loading the channel fails', async () => {
		mainRouter.replaceByPath('/channels/channel-a');
		mocks.apiWithDialog.mockRejectedValue(new Error('Channel unavailable'));

		await pressN();

		expect(mocks.post).not.toHaveBeenCalled();
	});

	test('does not open a post while signed out', async () => {
		mainRouter.replaceByPath('/channels/channel-a');
		mocks.user = null;

		await pressN();

		expect(mocks.apiWithDialog).not.toHaveBeenCalled();
		expect(mocks.post).not.toHaveBeenCalled();
	});

	test.each(['input', 'textarea'])('does not intercept typing in a %s', async (tagName) => {
		mainRouter.replaceByPath('/channels/channel-a');
		const input = document.createElement(tagName);
		document.body.appendChild(input);
		input.focus();

		await pressN();

		expect(mocks.apiWithDialog).not.toHaveBeenCalled();
		expect(mocks.post).not.toHaveBeenCalled();
	});
});
