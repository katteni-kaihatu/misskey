/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type { SummalyResult } from '@misskey-dev/summaly';

export type XriftSummary = SummalyResult & {
	xrift: { creator: string | null };
};

export function getXriftWorldUrl(url: string): string | null {
	const parsed = new URL(url);
	if (parsed.origin !== 'https://app.xrift.net' || parsed.username || parsed.password) return null;
	const match = /^\/world\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/i.exec(parsed.pathname);
	return match ? `https://app.xrift.net/world/${match[1].toLowerCase()}` : null;
}

export async function fetchXriftSummary(url: string, apiKey: string | null, getJson: (url: string, headers: Record<string, string>) => Promise<unknown>): Promise<XriftSummary | null> {
	if (!apiKey) return null;
	const worldUrl = getXriftWorldUrl(url);
	if (!worldUrl) return null;
	const id = worldUrl.split('/').at(-1)!;
	const response = await getJson(`https://api.xrift.net/api/public/v1/worlds/${id}`, { Authorization: `Bearer ${apiKey}` });
	if (typeof response !== 'object' || response == null || !('data' in response) || typeof response.data !== 'object' || response.data == null) throw new Error('Invalid XRift world');
	const world = response.data as Record<string, unknown>;
	if (world.id !== id || world.isPublic !== true || (world.status != null && world.status !== 'ACTIVE') || typeof world.name !== 'string' || !world.name.trim()) {
		throw new Error('XRift world is unavailable');
	}
	const owner = typeof world.owner === 'object' && world.owner != null ? world.owner as Record<string, unknown> : null;
	let thumbnail: string | null = null;
	if (typeof world.thumbnailUrl === 'string') {
		try {
			const image = new URL(world.thumbnailUrl);
			if (image.origin === 'https://assets.xrift.net' && !image.username && !image.password) thumbnail = image.href;
		} catch { /* Ignore invalid optional thumbnails. */ }
	}

	return {
		url: `https://app.xrift.net/world/${id}`,
		title: world.name,
		description: typeof world.description === 'string' ? world.description : null,
		thumbnail,
		thumbnailStyle: 'summary_large_image',
		icon: 'https://app.xrift.net/favicon.png',
		sitename: 'XRift',
		player: { url: null, width: null, height: null, allow: [] },
		activityPub: null,
		fediverseCreator: null,
		xrift: { creator: typeof owner?.displayName === 'string' ? owner.displayName : null },
	};
}
