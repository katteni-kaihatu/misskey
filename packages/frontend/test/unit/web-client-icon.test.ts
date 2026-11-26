/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, describe, expect, test, vi } from 'vitest';
import { createApp, nextTick, ref } from 'vue';
import type { App } from 'vue';
import type { WebClientIconPreference } from '@/utility/web-client-icon.js';

let stopRotation: (() => void) | undefined;
let app: App | undefined;

afterEach(() => {
	stopRotation?.();
	stopRotation = undefined;
	app?.unmount();
	app = undefined;
	vi.useRealTimers();
	vi.restoreAllMocks();
	document.head.innerHTML = '';
	document.body.innerHTML = '';
});

describe('web client icon', () => {
	test('one document choice is shared by navigation and every tab-icon declaration', async () => {
		vi.resetModules();
		const random = vi.spyOn(Math, 'random').mockReturnValue(0.5);
		const icons = await import('@/utility/web-client-icon.js');
		document.head.innerHTML = '<link rel="icon" href="/old.ico" sizes="16x16" type="image/x-icon"><link rel="shortcut icon" href="/old.svg" sizes="any" type="image/svg+xml">';
		icons.applyWebClientFavicon(document);
		icons.applyWebClientFavicon(document);
		const declarations = [...document.head.querySelectorAll<HTMLLinkElement>('link[rel~="icon"]')];
		expect(declarations).toHaveLength(2);
		for (const link of declarations) {
			expect(link.getAttribute('href')).toBe(icons.webClientFaviconUrl.value);
			expect(link.type).toBe('image/png');
			expect(link.getAttribute('sizes')).toBe('64x64');
		}
		expect(icons.webClientFaviconUrl.value).toBe(icons.webClientIconUrl.value.replace('.png', '-favicon.png'));
		expect(random).toHaveBeenCalledTimes(1);
	});

	test('a fresh document can choose another artwork without persisting its choice', async () => {
		vi.resetModules();
		vi.spyOn(Math, 'random').mockReturnValue(0);
		const first = await import('@/utility/web-client-icon.js');
		vi.resetModules();
		vi.mocked(Math.random).mockReturnValue(0.999999);
		const second = await import('@/utility/web-client-icon.js');
		expect(first.webClientIconUrl.value).not.toBe(second.webClientIconUrl.value);
		second.applyWebClientFavicon(document);
		expect(document.head.querySelector('link[rel="icon"]')?.getAttribute('href')).toBe(second.webClientFaviconUrl.value);
	});

	test('navigation and favicon rotate together every five minutes without remounting the page', async () => {
		vi.resetModules();
		vi.useFakeTimers();
		vi.spyOn(Math, 'random').mockReturnValue(0);
		const icons = await import('@/utility/web-client-icon.js');
		document.body.innerHTML = '<div id="app"></div>';
		app = createApp({
			setup: () => ({ webClientIconUrl: icons.webClientIconUrl }),
			template: '<img :src="webClientIconUrl"><img :src="webClientIconUrl"><input value="unfinished post">',
		});
		app.mount('#app');
		stopRotation = icons.startWebClientIconRotation(document);
		const input = document.querySelector('input');
		const first = icons.webClientIconUrl.value;
		await vi.advanceTimersByTimeAsync(299_999);
		expect(icons.webClientIconUrl.value).toBe(first);
		await vi.advanceTimersByTimeAsync(1);
		await nextTick();
		expect(icons.webClientIconUrl.value).not.toBe(first);
		for (const image of document.querySelectorAll('img')) {
			expect(image.getAttribute('src')).toBe(icons.webClientIconUrl.value);
		}
		expect(document.querySelector('link[rel="icon"]')?.getAttribute('href')).toBe(icons.webClientIconUrl.value.replace('.png', '-favicon.png'));
		expect(document.querySelector('input')).toBe(input);
		expect(input?.value).toBe('unfinished post');
		const second = icons.webClientIconUrl.value;
		vi.mocked(Math.random).mockReturnValue(0.999999);
		await vi.advanceTimersByTimeAsync(300_000);
		await nextTick();
		expect(icons.webClientIconUrl.value).not.toBe(second);
		expect(document.querySelector('img')?.getAttribute('src')).toBe(icons.webClientIconUrl.value);
		expect(document.querySelector('link[rel="icon"]')?.getAttribute('href')).toBe(icons.webClientFaviconUrl.value);
	});

	test('repeated startup shares one timer, which can be stopped and restarted', async () => {
		vi.resetModules();
		vi.useFakeTimers();
		const icons = await import('@/utility/web-client-icon.js');
		stopRotation = icons.startWebClientIconRotation(document);
		expect(icons.startWebClientIconRotation(document)).toBe(stopRotation);
		expect(vi.getTimerCount()).toBe(1);
		const firstStop = stopRotation;
		stopRotation();
		expect(vi.getTimerCount()).toBe(0);
		const stopped = icons.webClientIconUrl.value;
		await vi.advanceTimersByTimeAsync(600_000);
		expect(icons.webClientIconUrl.value).toBe(stopped);
		stopRotation = icons.startWebClientIconRotation(document);
		firstStop();
		expect(icons.startWebClientIconRotation(document)).toBe(stopRotation);
		expect(vi.getTimerCount()).toBe(1);
	});

	test('server metadata, touch icons, manifests and pinned-tab icons stay intact', async () => {
		vi.resetModules();
		vi.useFakeTimers();
		const icons = await import('@/utility/web-client-icon.js');
		document.head.innerHTML = '<meta property="og:image" content="/server.png"><link rel="apple-touch-icon" href="/touch.png"><link rel="manifest" href="/manifest.json"><link rel="mask-icon" href="/pinned.svg">';
		const existing = [...document.head.children].map(element => element.outerHTML);
		stopRotation = icons.startWebClientIconRotation(document);
		await vi.advanceTimersByTimeAsync(600_000);
		expect([...document.head.children].slice(0, 4).map(element => element.outerHTML)).toEqual(existing);
		expect(document.head.querySelectorAll('link[rel="icon"]')).toHaveLength(1);
	});

	test('a saved fixed icon applies at startup and never rotates', async () => {
		vi.resetModules();
		vi.useFakeTimers();
		const icons = await import('@/utility/web-client-icon.js');
		const preference = ref<WebClientIconPreference>('tekerets');
		stopRotation = icons.startWebClientIconRotation(document, preference);
		expect(icons.webClientIconUrl.value).toContain('/tekerets.png');
		expect(document.querySelector('link[rel="icon"]')?.getAttribute('href')).toContain('/tekerets-favicon.png');
		expect(vi.getTimerCount()).toBe(0);
		await vi.advanceTimersByTimeAsync(900_000);
		expect(icons.webClientIconUrl.value).toContain('/tekerets.png');
	});

	test('preference changes immediately fix both icons and resume one fresh five-minute timer', async () => {
		vi.resetModules();
		vi.useFakeTimers();
		const icons = await import('@/utility/web-client-icon.js');
		const preference = ref<WebClientIconPreference>('random');
		stopRotation = icons.startWebClientIconRotation(document, preference);
		await vi.advanceTimersByTimeAsync(250_000);
		for (const name of icons.webClientIconNames) {
			preference.value = name;
			expect(icons.webClientIconUrl.value).toContain(`/${name}.png`);
			expect(document.querySelector('link[rel="icon"]')?.getAttribute('href')).toContain(`/${name}-favicon.png`);
			expect(vi.getTimerCount()).toBe(0);
		}
		const fixed = icons.webClientIconUrl.value;
		preference.value = 'random';
		expect(icons.webClientIconUrl.value).not.toBe(fixed);
		expect(vi.getTimerCount()).toBe(1);
		const random = icons.webClientIconUrl.value;
		await vi.advanceTimersByTimeAsync(299_999);
		expect(icons.webClientIconUrl.value).toBe(random);
		await vi.advanceTimersByTimeAsync(1);
		expect(icons.webClientIconUrl.value).not.toBe(random);
		const stopped = icons.webClientIconUrl.value;
		stopRotation();
		preference.value = 'sakami';
		expect(vi.getTimerCount()).toBe(0);
		expect(icons.webClientIconUrl.value).toBe(stopped);
	});

	test('unknown imported values fall back to random without becoming image paths', async () => {
		vi.resetModules();
		vi.useFakeTimers();
		const icons = await import('@/utility/web-client-icon.js');
		const preference = ref('../../outside' as WebClientIconPreference);
		stopRotation = icons.startWebClientIconRotation(document, preference);
		expect(icons.normalizeWebClientIconPreference(null)).toBe('random');
		expect(icons.webClientIconNames.some(name => icons.webClientIconUrl.value.endsWith(`/${name}.png`))).toBe(true);
		expect(vi.getTimerCount()).toBe(1);
	});
});
