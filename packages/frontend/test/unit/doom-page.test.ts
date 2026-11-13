/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { fireEvent, render, waitFor } from '@testing-library/vue';
import { nextTick } from 'vue';
import locales from 'i18n';
import { i18n, updateI18n } from '@/i18n.js';
import Doom from '@/pages/flash/doom.vue';
import type { RenderResult } from '@testing-library/vue';
import type { DoomResult } from '@/utility/doom.js';

const mocks = vi.hoisted(() => ({ post: vi.fn(), alert: vi.fn(), toast: vi.fn(), login: vi.fn(), upload: vi.fn() }));
vi.mock('@/os.js', () => ({ post: mocks.post, alert: mocks.alert, toast: mocks.toast }));
vi.mock('@/page.js', () => ({ definePage: vi.fn() }));
vi.mock('@/utility/please-login.js', () => ({ pleaseLogin: mocks.login }));
vi.mock('@/utility/drive.js', () => ({ uploadFile: mocks.upload }));
vi.mock('@/components/MkButton.vue', async () => {
	const { defineComponent, h } = await import('vue');
	return { default: defineComponent({ props: ['disabled'], emits: ['click'], setup: (props, { slots, emit }) => () => h('button', { disabled: props.disabled, onClick: () => emit('click') }, slots.default?.()) }) };
});
vi.mock('@/components/MkSelect.vue', async () => {
	const { defineComponent, h } = await import('vue');
	return { default: defineComponent({ setup: () => () => h('select') }) };
});

const result: DoomResult = { version: 1, game: 'freedoom', episode: 1, map: 1, skill: 3, kills: 2, totalKills: 29, items: 1, totalItems: 49, secrets: 0, totalSecrets: 4, ticks: 350, completed: false, dead: false };
let view: RenderResult | undefined;

function mount(shared?: string) {
	view = render(Doom, { props: { shared }, global: { stubs: { PageWithHeader: { template: '<main><slot/></main>' }, MkA: { template: '<a><slot/></a>' } } } });
	return view;
}

function message(frame: HTMLIFrameElement, data: unknown, origin = window.location.origin, source = frame.contentWindow) {
	window.dispatchEvent(new MessageEvent('message', { origin, source, data }));
}

function activeFrame(page: RenderResult) {
	const frame = page.container.querySelector('iframe')!;
	Object.defineProperty(frame, 'contentWindow', { value: { postMessage: vi.fn() }, configurable: true });
	return frame;
}

beforeEach(() => {
	vi.clearAllMocks();
	updateI18n(locales['ja-JP']);
	mocks.login.mockResolvedValue(true);
});
afterEach(() => { view?.unmount(); vi.restoreAllMocks(); vi.useRealTimers(); });

describe('DOOM Play page', () => {
	test('shows a public shared result without starting the engine or posting', () => {
		const page = mount(JSON.stringify(result));
		expect(page.getByText('210')).toBeTruthy();
		expect(page.container.querySelector('iframe')).toBeNull();
		expect(mocks.post).not.toHaveBeenCalled();
		expect(mocks.upload).not.toHaveBeenCalled();
	});

	test('accepts only its active frame and disposes it when stopped', async () => {
		const page = mount();
		await fireEvent.click(page.getByRole('button', { name: i18n.ts.start }));
		const frame = activeFrame(page);
		message(frame, { type: 'doom:stats', result }, 'https://untrusted.example');
		message(frame, { type: 'doom:stats', result }, window.location.origin, window);
		await nextTick();
		expect(page.queryByText('210')).toBeNull();
		message(frame, { type: 'doom:started' });
		message(frame, { type: 'doom:stats', result });
		await nextTick();
		expect(page.getByText('210')).toBeTruthy();
		await fireEvent.click(page.getByRole('button', { name: '終了して設定に戻る' }));
		expect(page.container.querySelector('iframe')).toBeNull();
		message(frame, { type: 'doom:stats', result: { ...result, kills: 99 } });
		await nextTick();
		expect(page.getByText('210')).toBeTruthy();
	});

	test('pauses before opening login and never posts if login is cancelled', async () => {
		const page = mount();
		await fireEvent.click(page.getByRole('button', { name: i18n.ts.start }));
		const frame = activeFrame(page);
		message(frame, { type: 'doom:started' });
		message(frame, { type: 'doom:stats', result });
		await nextTick();
		const sent = vi.spyOn(frame.contentWindow!, 'postMessage');
		mocks.login.mockImplementation(async () => {
			expect(sent).toHaveBeenCalledWith({ type: 'doom:pause', paused: true }, window.location.origin);
			return false;
		});
		await fireEvent.click(page.getByRole('button', { name: 'ノートで共有' }));
		expect(mocks.login).toHaveBeenCalledOnce();
		expect(mocks.post).not.toHaveBeenCalled();
		expect(mocks.upload).not.toHaveBeenCalled();
	});

	test('opens the existing composer with the score card and result link', async () => {
		const page = mount(JSON.stringify(result));
		vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({ fillRect: vi.fn(), fillText: vi.fn() } as unknown as CanvasRenderingContext2D);
		vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation(callback => callback(new Blob(['png'], { type: 'image/png' })));
		const file = { id: 'score-card' };
		mocks.upload.mockReturnValue({ filePromise: Promise.resolve(file), abort: vi.fn() });
		await fireEvent.click(page.getByRole('button', { name: i18n.ts.shareWithNote }));
		await waitFor(() => expect(mocks.post).toHaveBeenCalledOnce());
		expect(mocks.upload).toHaveBeenCalledWith(expect.any(File), expect.objectContaining({ isSensitive: true }));
		expect(mocks.post).toHaveBeenCalledWith({
			initialText: expect.stringContaining('/play/doom?result='),
			initialFiles: [file], instant: true,
		});
		expect(mocks.post.mock.calls[0][0].initialText).toContain('210点');
	});

	test('aborts a stalled image upload and falls back to a text result', async () => {
		vi.useFakeTimers();
		const page = mount(JSON.stringify(result));
		vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({ fillRect: vi.fn(), fillText: vi.fn() } as unknown as CanvasRenderingContext2D);
		vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation(callback => callback(new Blob(['png'], { type: 'image/png' })));
		let rejectUpload!: (reason: Error) => void;
		const abort = vi.fn(() => rejectUpload(new Error('Aborted')));
		mocks.upload.mockReturnValue({ filePromise: new Promise((_, reject) => { rejectUpload = reject; }), abort });
		await fireEvent.click(page.getByRole('button', { name: i18n.ts.shareWithNote }));
		await vi.advanceTimersByTimeAsync(0);
		expect(mocks.upload).toHaveBeenCalledOnce();
		await vi.advanceTimersByTimeAsync(30000);
		expect(abort).toHaveBeenCalledOnce();
		expect(mocks.post).toHaveBeenCalledWith(expect.objectContaining({ initialFiles: undefined, instant: true }));
		expect(page.getByRole('button', { name: i18n.ts.shareWithNote }).hasAttribute('disabled')).toBe(false);
	});
});
