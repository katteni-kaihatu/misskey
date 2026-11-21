/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/vue';
import locales from 'i18n';
import { updateI18n } from '@/i18n.js';
import { prefer } from '@/preferences.js';
import MkPanorama from '@/components/MkPanorama.vue';

const mocks = vi.hoisted(() => ({ create: vi.fn(), resize: vi.fn(), render: vi.fn(), dispose: vi.fn() }));
vi.mock('@/utility/panorama-renderer.js', () => ({ createPanoramaRenderer: mocks.create }));
vi.mock('@/preferences.js', async () => {
	const { ref } = await import('vue');
	return { prefer: { s: { animation: true }, r: { animation: ref(true) } } };
});

let intersect: (visible: boolean) => void;
let documentState: DocumentVisibilityState;
let prefersReducedMotion: boolean;
let frames: Map<number, FrameRequestCallback>;
let frameId: number;

beforeAll(() => updateI18n(locales['ja-JP']));
beforeEach(() => {
	vi.clearAllMocks();
	documentState = 'visible';
	prefersReducedMotion = false;
	prefer.s.animation = true;
	prefer.r.animation.value = true;
	frames = new Map();
	frameId = 0;
	mocks.create.mockImplementation(() => ({ resize: mocks.resize, render: mocks.render, dispose: mocks.dispose }));
	vi.spyOn(document, 'visibilityState', 'get').mockImplementation(() => documentState);
	vi.spyOn(window, 'matchMedia').mockImplementation(() => ({ matches: prefersReducedMotion, addEventListener: vi.fn(), removeEventListener: vi.fn() }) as unknown as MediaQueryList);
	vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback) => { frames.set(++frameId, callback); return frameId; });
	vi.stubGlobal('cancelAnimationFrame', (id: number) => { frames.delete(id); });
	vi.stubGlobal('IntersectionObserver', class {
		constructor(callback: IntersectionObserverCallback) { intersect = visible => callback([{ isIntersecting: visible }] as IntersectionObserverEntry[], this as unknown as IntersectionObserver); }
		observe(): void {}
		disconnect(): void {}
	});
	vi.stubGlobal('ResizeObserver', class { observe(): void {} disconnect(): void {} });
});
afterEach(() => { cleanup(); prefer.s.animation = true; vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function load(width = 1024, height = 512) {
	const view = render(MkPanorama, { props: { src: '/panorama.webp', alt: 'World panorama' } });
	const image = view.getByRole('img') as HTMLImageElement;
	Object.defineProperties(image, { naturalWidth: { value: width }, naturalHeight: { value: height } });
	await fireEvent.load(image);
	return view;
}

describe('inline panoramas', () => {
	test('loads the renderer only while a panorama is visible and releases it offscreen', async () => {
		const view = await load();
		expect(mocks.create).not.toHaveBeenCalled();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		expect(view.getByRole('button', { name: 'パノラマの回転を停止' })).toBeTruthy();
		expect(frames.size).toBe(1);
		intersect(false);
		await waitFor(() => expect(mocks.dispose).toHaveBeenCalledTimes(1));
		expect(frames.size).toBe(0);
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(2));
		view.unmount();
		expect(mocks.dispose).toHaveBeenCalledTimes(2);
		expect(frames.size).toBe(0);
	});
	test('keeps ordinary images static', async () => {
		const view = await load(800, 600);
		intersect(true);
		await Promise.resolve();
		expect(mocks.create).not.toHaveBeenCalled();
		expect(view.queryByRole('button')).toBeNull();
		expect(view.getByRole('img', { name: 'World panorama' })).toBeTruthy();
	});
	test('can pause and resume rotation without dropping the view', async () => {
		const view = await load();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		await fireEvent.click(view.getByRole('button', { name: 'パノラマの回転を停止' }));
		expect(frames.size).toBe(0);
		expect(mocks.dispose).not.toHaveBeenCalled();
		await fireEvent.click(view.getByRole('button', { name: 'パノラマの回転を再開' }));
		expect(frames.size).toBe(1);
	});
	test('reduced motion starts paused and keyboard panning stays manual', async () => {
		prefersReducedMotion = true;
		const view = await load();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		expect(frames.size).toBe(0);
		expect(view.getByRole('button', { name: 'パノラマの回転を再開' })).toBeTruthy();
		await fireEvent.keyDown(view.getByRole('group', { name: 'World panorama' }), { key: 'ArrowRight' });
		expect(mocks.render).toHaveBeenLastCalledWith(0.15);
		expect(frames.size).toBe(0);
	});
	test('hidden documents release GPU resources', async () => {
		await load();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		documentState = 'hidden';
		document.dispatchEvent(new Event('visibilitychange'));
		await waitFor(() => expect(mocks.dispose).toHaveBeenCalledTimes(1));
		expect(frames.size).toBe(0);
	});
	test('respects the Misskey animation preference initially and when it changes', async () => {
		prefer.s.animation = false;
		const view = await load();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		expect(frames.size).toBe(0);
		await fireEvent.click(view.getByRole('button', { name: 'パノラマの回転を再開' }));
		expect(frames.size).toBe(1);
		prefer.r.animation.value = true;
		await Promise.resolve();
		prefer.r.animation.value = false;
		await waitFor(() => expect(frames.size).toBe(0));
	});
	test('WebGL failures keep the accessible still image', async () => {
		mocks.create.mockImplementation(() => { throw new Error('WebGL unavailable'); });
		const view = await load();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		expect(view.getByRole('img', { name: 'World panorama' })).toBeTruthy();
		expect(view.queryByRole('button')).toBeNull();
		expect(frames.size).toBe(0);
	});
});
