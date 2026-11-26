/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { createApp, h } from 'vue';
import { expect, it, vi } from 'vitest';
import MkSpaceTileFrame from '@/components/MkSpaceTileFrame.vue';

vi.mock('@/os.js', () => ({}));
vi.mock('@/i18n.js', () => ({ i18n: { ts: {} } }));

it('discards pending replies on frame reload and unmount, even when the next frame reuses the call ID', async () => {
	const ports: TestPort[] = [];
	class TestPort {
		postMessage = vi.fn();
		close = vi.fn();
		onmessage!: (ev: { data: unknown }) => Promise<void>;

		call() {
			return this.onmessage({ data: { t: 'call', method: 'test', id: 1, args: {} } });
		}
	}
	vi.stubGlobal('MessageChannel', class {
		port1 = new TestPort();
		port2 = {};
		constructor() {
			ports.push(this.port1);
		}
	});
	const first = Promise.withResolvers<string>();
	const last = Promise.withResolvers<string>();
	const call = vi.fn().mockReturnValueOnce(first.promise).mockResolvedValueOnce('current').mockReturnValueOnce(last.promise);
	const app = createApp({ render: () => h(MkSpaceTileFrame, {
		html: '', title: 'test', call,
		init: { me: { id: 'me', name: '', username: 'me', avatarUrl: null }, members: [], isHost: false, isLeader: false, hostOnly: false, origin: '', strings: {}, shared: {}, mine: {} },
	}) });
	const host = document.createElement('div');
	document.body.appendChild(host);
	try {
		app.mount(host);
		const frame = host.querySelector('iframe')!;
		vi.spyOn(frame.contentWindow!, 'postMessage').mockImplementation(() => {});
		const load = () => {
			frame.dispatchEvent(new Event('load'));
			return ports[ports.length - 1];
		};
		const old = load();
		const oldCall = old.call();
		const current = load();
		await current.call();
		first.resolve('old');
		await oldCall;
		expect(old.postMessage).not.toHaveBeenCalled();
		expect(current.postMessage.mock.calls).toEqual([[{ t: 'reply', id: 1, ok: true, value: 'current' }]]);
		const finalCall = current.call();
		app.unmount();
		last.reject(new Error('late'));
		await finalCall;
		expect(current.postMessage).toHaveBeenCalledTimes(1);
	} finally {
		if (host.firstChild) app.unmount();
		host.remove();
		vi.unstubAllGlobals();
		vi.restoreAllMocks();
	}
});
