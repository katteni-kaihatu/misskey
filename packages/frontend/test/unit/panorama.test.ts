/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/vue';
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
afterEach(() => { cleanup(); vi.useRealTimers(); prefer.s.animation = true; vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function load(width = 1024, height = 512) {
	const view = render(MkPanorama, { props: { src: '/panorama.webp', alt: 'World panorama' } });
	const image = view.getByRole('img') as HTMLImageElement;
	Object.defineProperties(image, { naturalWidth: { value: width }, naturalHeight: { value: height } });
	await fireEvent.load(image);
	return view;
}

async function readyPanorama() {
	const view = await load();
	intersect(true);
	await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
	const target = view.getByRole('group', { name: 'World panorama' });
	let captured: number | null = null;
	Object.defineProperties(target, {
		setPointerCapture: { value: (id: number) => { captured = id; } },
		hasPointerCapture: { value: (id: number) => captured === id },
		releasePointerCapture: { value: () => { captured = null; } },
		clientWidth: { value: 300 },
		clientHeight: { value: 200 },
	});
	return { view, target };
}

describe('inline panoramas', () => {
	test('loads the renderer only while a panorama is visible and releases it offscreen', async () => {
		const view = await load();
		expect(mocks.create).not.toHaveBeenCalled();
		intersect(true);
		await waitFor(() => expect(mocks.create).toHaveBeenCalledTimes(1));
		expect(view.queryByRole('button')).toBeNull();
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
	test('pauses immediately while held, then resumes three seconds after release', async () => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		await fireEvent.pointerDown(target, { pointerId: 1, button: 0 });
		expect(frames.size).toBe(0);
		await vi.advanceTimersByTimeAsync(5000);
		expect(frames.size).toBe(0);
		expect(mocks.dispose).not.toHaveBeenCalled();
		await fireEvent.pointerUp(target, { pointerId: 1 });
		await vi.advanceTimersByTimeAsync(2999);
		expect(frames.size).toBe(0);
		await vi.advanceTimersByTimeAsync(1);
		expect(frames.size).toBe(1);
	});
	test('diagonal dragging pans both axes and another press resets the resume delay', async () => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		await fireEvent.pointerDown(target, { pointerId: 1, button: 0, clientX: 100, clientY: 100 });
		await fireEvent.pointerMove(target, { pointerId: 1, clientX: 200, clientY: 150 });
		expect(mocks.render).toHaveBeenLastCalledWith(-Math.PI / 6, Math.PI / 8);
		await fireEvent.pointerUp(target, { pointerId: 1 });
		await vi.advanceTimersByTimeAsync(2000);
		await fireEvent.pointerDown(target, { pointerId: 2, button: 0 });
		await vi.advanceTimersByTimeAsync(4000);
		expect(frames.size).toBe(0);
		await fireEvent.pointerUp(target, { pointerId: 2 });
		await vi.advanceTimersByTimeAsync(3000);
		expect(frames.size).toBe(1);
	});
	test('limits vertical panning before the view flips and preserves it during rotation', async () => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		const limit = 85 * Math.PI / 180;
		await fireEvent.pointerDown(target, { pointerId: 1, button: 0, clientY: 100 });
		await fireEvent.pointerMove(target, { pointerId: 1, clientY: 10000 });
		expect(mocks.render).toHaveBeenLastCalledWith(0, limit);
		await fireEvent.pointerMove(target, { pointerId: 1, clientY: -10000 });
		expect(mocks.render).toHaveBeenLastCalledWith(0, -limit);
		await fireEvent.pointerUp(target, { pointerId: 1 });
		await vi.advanceTimersByTimeAsync(3000);
		for (const time of [0, 100]) {
			const [id, callback] = frames.entries().next().value!;
			frames.delete(id);
			callback(time);
		}
		expect(mocks.render).toHaveBeenLastCalledWith(expect.any(Number), -limit);
	});
	test.each([['ArrowUp', 0.15], ['ArrowDown', -0.15]])('%s pans vertically', async (key, pitch) => {
		const { target } = await readyPanorama();
		await fireEvent.keyDown(target, { key });
		expect(mocks.render).toHaveBeenLastCalledWith(0, pitch);
		expect(frames.size).toBe(0);
	});
	test.each(['pointercancel', 'lostpointercapture'])('%s releases the hold without leaving rotation stuck', async event => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		await fireEvent.pointerDown(target, { pointerId: 1, button: 0 });
		await fireEvent(target, new PointerEvent(event, { pointerId: 1 }));
		await vi.advanceTimersByTimeAsync(3000);
		expect(frames.size).toBe(1);
	});
	test('reduced motion starts paused and keyboard panning stays manual', async () => {
		prefersReducedMotion = true;
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		expect(frames.size).toBe(0);
		await fireEvent.keyDown(target, { key: 'ArrowRight' });
		expect(mocks.render).toHaveBeenLastCalledWith(0.15, 0);
		await vi.advanceTimersByTimeAsync(3000);
		expect(frames.size).toBe(0);
	});
	test('keyboard panning also resumes after three seconds', async () => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		await fireEvent.keyDown(target, { key: 'ArrowLeft' });
		expect(mocks.render).toHaveBeenLastCalledWith(-0.15, 0);
		expect(frames.size).toBe(0);
		await vi.advanceTimersByTimeAsync(3000);
		expect(frames.size).toBe(1);
	});
	test.each([' ', 'Enter'])('holding %s pauses without changing the view', async key => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		const renders = mocks.render.mock.calls.length;
		await fireEvent.keyDown(target, { key });
		await vi.advanceTimersByTimeAsync(5000);
		expect(frames.size).toBe(0);
		expect(mocks.render).toHaveBeenCalledTimes(renders);
		await fireEvent.keyUp(target, { key });
		await vi.advanceTimersByTimeAsync(2999);
		expect(frames.size).toBe(0);
		await vi.advanceTimersByTimeAsync(1);
		expect(frames.size).toBe(1);
	});
	test('losing focus releases a held key', async () => {
		const { target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		await fireEvent.keyDown(target, { key: ' ' });
		await fireEvent.blur(target);
		await vi.advanceTimersByTimeAsync(3000);
		expect(frames.size).toBe(1);
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
		prefer.r.animation.value = false;
		await readyPanorama();
		expect(frames.size).toBe(0);
		prefer.r.animation.value = true;
		await Promise.resolve();
		expect(frames.size).toBe(1);
		prefer.r.animation.value = false;
		await waitFor(() => expect(frames.size).toBe(0));
	});
	test('unmounting clears a pending resume timer', async () => {
		const { view, target } = await readyPanorama();
		vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
		await fireEvent.pointerDown(target, { pointerId: 1, button: 0 });
		await fireEvent.pointerUp(target, { pointerId: 1 });
		expect(vi.getTimerCount()).toBe(1);
		view.unmount();
		expect(vi.getTimerCount()).toBe(0);
		await vi.advanceTimersByTimeAsync(3000);
		expect(frames.size).toBe(0);
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
