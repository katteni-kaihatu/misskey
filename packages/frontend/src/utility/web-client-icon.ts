/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { computed, shallowRef, watch } from 'vue';
import type { Ref } from 'vue';

export const webClientIconNames = ['sakami', 'tekerets', 'sharuya', 'machiyoh', 'ningen'] as const;
export type WebClientIconPreference = 'random' | typeof webClientIconNames[number];
const iconNames = webClientIconNames;
const selectedIconIndex = shallowRef(Math.floor(Math.random() * iconNames.length));
let stopRotation: (() => void) | undefined;

// A shared reactive choice keeps every navigation layout and the favicon together.
// Keep instance metadata intact: these images belong only to the web client.
export const webClientIconUrl = computed(() => `/client-assets/gridspace/client-icons/${iconNames[selectedIconIndex.value]}.png`);
export const webClientFaviconUrl = computed(() => `/client-assets/gridspace/client-icons/${iconNames[selectedIconIndex.value]}-favicon.png`);

export function applyWebClientFavicon(document: Document): void {
	let links = [...document.head.querySelectorAll<HTMLLinkElement>('link[rel~="icon"]')];
	if (links.length === 0) {
		const link = document.createElement('link');
		link.rel = 'icon';
		document.head.appendChild(link);
		links = [link];
	}
	for (const link of links) {
		link.href = webClientFaviconUrl.value;
		link.type = 'image/png';
		link.setAttribute('sizes', '64x64');
	}
}

export function normalizeWebClientIconPreference(value: unknown): WebClientIconPreference {
	return iconNames.some(name => name === value) ? value as typeof iconNames[number] : 'random';
}

export function startWebClientIconRotation(document: Document, preference: Readonly<Ref<WebClientIconPreference>> = shallowRef<WebClientIconPreference>('random')): () => void {
	if (stopRotation) return stopRotation;
	let timer: number | undefined;

	function rotate() {
		// Choose uniformly among the other four artworks without retrying randomness.
		const offset = 1 + Math.floor(Math.random() * (iconNames.length - 1));
		selectedIconIndex.value = (selectedIconIndex.value + offset) % iconNames.length;
		applyWebClientFavicon(document);
	}

	const stopWatching = watch(preference, (value, oldValue) => {
		window.clearInterval(timer);
		timer = undefined;
		const choice = normalizeWebClientIconPreference(value);
		if (choice === 'random') {
			if (oldValue !== undefined && normalizeWebClientIconPreference(oldValue) !== 'random') rotate();
			timer = window.setInterval(rotate, 5 * 60 * 1000);
		} else {
			selectedIconIndex.value = iconNames.indexOf(choice);
		}
		applyWebClientFavicon(document);
	}, { immediate: true, flush: 'sync' });
	const stop = () => {
		if (stopRotation !== stop) return;
		stopWatching();
		window.clearInterval(timer);
		stopRotation = undefined;
	};
	stopRotation = stop;
	return stop;
}

if (import.meta.hot) {
	import.meta.hot.dispose(() => stopRotation?.());
}
