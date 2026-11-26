/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

const iconNames = ['sakami', 'tekerets', 'sharuya', 'machiyoh', 'ningen'] as const;
const selectedIconName = iconNames[Math.floor(Math.random() * iconNames.length)];

// One choice per document, shared by every navigation layout and the favicon.
// Keep instance metadata intact: these images belong only to the web client.
export const webClientIconUrl = `/client-assets/gridspace/client-icons/${selectedIconName}.png`;
export const webClientFaviconUrl = `/client-assets/gridspace/client-icons/${selectedIconName}-favicon.png`;

export function applyWebClientFavicon(document: Document): void {
	let links = [...document.head.querySelectorAll<HTMLLinkElement>('link[rel~="icon"]')];
	if (links.length === 0) {
		const link = document.createElement('link');
		link.rel = 'icon';
		document.head.appendChild(link);
		links = [link];
	}
	for (const link of links) {
		link.href = webClientFaviconUrl;
		link.type = 'image/png';
		link.setAttribute('sizes', '64x64');
	}
}
