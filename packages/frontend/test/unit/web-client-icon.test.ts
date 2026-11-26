/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, describe, expect, test, vi } from 'vitest';

afterEach(() => {
	vi.restoreAllMocks();
	document.head.innerHTML = '';
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
			expect(link.getAttribute('href')).toBe(icons.webClientFaviconUrl);
			expect(link.type).toBe('image/png');
			expect(link.getAttribute('sizes')).toBe('64x64');
		}
		expect(icons.webClientFaviconUrl).toBe(icons.webClientIconUrl.replace('.png', '-favicon.png'));
		expect(random).toHaveBeenCalledTimes(1);
	});

	test('a fresh document can choose another artwork without persisting its choice', async () => {
		vi.resetModules();
		vi.spyOn(Math, 'random').mockReturnValue(0);
		const first = await import('@/utility/web-client-icon.js');
		vi.resetModules();
		vi.mocked(Math.random).mockReturnValue(0.999999);
		const second = await import('@/utility/web-client-icon.js');
		expect(first.webClientIconUrl).not.toBe(second.webClientIconUrl);
		second.applyWebClientFavicon(document);
		expect(document.head.querySelector('link[rel="icon"]')?.getAttribute('href')).toBe(second.webClientFaviconUrl);
	});

	test('server metadata, touch icons, manifests and pinned-tab icons stay intact', async () => {
		const { applyWebClientFavicon } = await import('@/utility/web-client-icon.js');
		document.head.innerHTML = '<meta property="og:image" content="/server.png"><link rel="apple-touch-icon" href="/touch.png"><link rel="manifest" href="/manifest.json"><link rel="mask-icon" href="/pinned.svg">';
		const existing = [...document.head.children].map(element => element.outerHTML);
		applyWebClientFavicon(document);
		expect([...document.head.children].slice(0, 4).map(element => element.outerHTML)).toEqual(existing);
		expect(document.head.querySelectorAll('link[rel="icon"]')).toHaveLength(1);
	});
});
