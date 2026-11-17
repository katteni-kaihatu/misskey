/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type { SummalyResult } from '@misskey-dev/summaly';
import type { XriftPreview } from 'misskey-js';

export type XriftSummary = SummalyResult & { xrift: XriftPreview };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const apiBase = 'https://api.xrift.net/api/public/v1';
type JsonObject = Record<string, unknown>;

export function getXriftResource(url: string): { type: XriftPreview['type']; id: string; url: string } | null {
	try {
		const parsed = new URL(url);
		if (parsed.origin !== 'https://app.xrift.net' || parsed.username || parsed.password) return null;
		const match = /^\/(world|instance|user|marketplace)\/([^/]+)\/?$/.exec(parsed.pathname);
		if (!match || !uuid.test(match[2])) return null;
		const type = match[1] === 'marketplace' ? 'item' : match[1] as XriftPreview['type'];
		const id = match[2].toLowerCase();
		return { type, id, url: `https://app.xrift.net/${match[1]}/${id}` };
	} catch {
		return null;
	}
}

export function getXriftWorldUrl(url: string): string | null {
	const resource = getXriftResource(url);
	return resource?.type === 'world' ? resource.url : null;
}

/** Only XRift-owned HTTPS assets may enter the media proxy. */
export function xriftImageUrl(value: unknown): string | null {
	if (typeof value !== 'string') return null;
	try {
		const url = new URL(value);
		return url.origin === 'https://assets.xrift.net' && !url.username && !url.password ? url.href : null;
	} catch {
		return null;
	}
}

function object(value: unknown): JsonObject | null {
	return value != null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : null;
}

function count(value: unknown): number | undefined {
	return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : undefined;
}

function date(value: unknown): string | undefined {
	return typeof value === 'string' && Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : undefined;
}

function publicWorld(value: unknown, id?: string): JsonObject | null {
	const world = object(value);
	return world && typeof world.id === 'string' && uuid.test(world.id) && (!id || world.id.toLowerCase() === id) &&
		world.isPublic === true && (world.status == null || world.status === 'ACTIVE') && typeof world.name === 'string' && world.name.trim() ? world : null;
}

export async function fetchXriftSummary(url: string, apiKey: string | null, getJson: (url: string, headers: Record<string, string>) => Promise<unknown>): Promise<XriftSummary | null> {
	const resource = getXriftResource(url);
	if (!apiKey || !resource) return null;
	const summary: XriftSummary = {
		url: resource.url, title: null, description: null, thumbnail: null,
		thumbnailStyle: 'summary_large_image', icon: 'https://app.xrift.net/favicon.png', sitename: 'XRift',
		player: { url: null, width: null, height: null, allow: [] }, activityPub: null, fediverseCreator: null,
		xrift: { type: resource.type, state: 'available', creator: null },
	};
	const get = (path: string): Promise<unknown> => getJson(`${apiBase}${path}`, { Authorization: `Bearer ${apiKey}` });
	const optional = async (path: string): Promise<JsonObject | null> => {
		try { return object(await get(path)); } catch { return null; }
	};
	const fillWorld = async (world: JsonObject): Promise<void> => {
		summary.title = world.name as string;
		summary.description = typeof world.description === 'string' ? world.description : null;
		summary.thumbnail = xriftImageUrl(world.thumbnailUrl);
		summary.xrift.worldUrl = `https://app.xrift.net/world/${world.id}`;
		const ownerId = typeof world.ownerId === 'string' && uuid.test(world.ownerId) ? world.ownerId : null;
		const [owner, stats, instances] = await Promise.all([
			ownerId ? optional(`/users/${ownerId}`) : null,
			optional(`/worlds/${world.id}/stats`),
			optional(`/worlds/${world.id}/instances?limit=1`),
		]);
		const creator = object(owner?.data) ?? object(world.owner);
		summary.xrift.creator = typeof creator?.displayName === 'string' ? creator.displayName : null;
		const statistics = object(stats?.data);
		if (statistics && statistics.worldId === world.id) {
			summary.xrift.totalVisits = count(statistics.totalVisits);
			summary.xrift.visitsLast7Days = count(statistics.visitsLast7Days);
		}
		if (Array.isArray(instances?.data)) summary.xrift.publicInstances = count(object(instances.pagination)?.total);
	};

	try {
		const plural = resource.type === 'item' ? 'marketplace/items' : resource.type === 'user' ? 'users' : `${resource.type}s`;
		const data = object(object(await get(`/${plural}/${resource.id}`))?.data);
		if (!data || data.id !== resource.id) throw new Error('Invalid XRift resource');
		if (resource.type === 'item') {
			if (data.isPublic !== true || data.status !== 'ACTIVE') { summary.xrift.state = 'unavailable'; return summary; }
			if (typeof data.name !== 'string' || !data.name.trim()) throw new Error('Invalid XRift item');
			summary.title = data.name;
			summary.description = typeof data.description === 'string' ? data.description : null;
			summary.thumbnail = xriftImageUrl(data.thumbnailUrl);
			const owner = object(data.owner);
			summary.xrift.creator = typeof owner?.displayName === 'string' ? owner.displayName : null;
			summary.xrift.acquireCount = count(data.acquireCount);
		} else if (resource.type === 'user') {
			if (typeof data.displayName !== 'string' || !data.displayName.trim()) throw new Error('Invalid XRift user');
			summary.title = data.displayName;
			summary.thumbnail = xriftImageUrl(data.userIconUrl);
			summary.xrift.createdAt = date(data.createdAt);
			const worlds = await optional(`/users/${resource.id}/worlds?limit=50`);
			if (Array.isArray(worlds?.data)) {
				summary.xrift.totalWorlds = count(object(worlds.pagination)?.total);
				summary.xrift.worlds = worlds.data.slice(0, 50).flatMap(item => {
					const world = publicWorld(item);
					return world ? [{ url: `https://app.xrift.net/world/${world.id}`, title: world.name as string, thumbnail: xriftImageUrl(world.thumbnailUrl) }] : [];
				});
			}
		} else if (resource.type === 'instance') {
			if (typeof data.worldId !== 'string' || !uuid.test(data.worldId)) throw new Error('Invalid XRift instance');
			// Details alone do not establish that a room is public. Bound the
			// search to avoid draining the provider quota on unusually large worlds.
			let isPublic = false;
			for (let offset = 0; offset < 250; offset += 50) {
				const page = object(await get(`/worlds/${data.worldId}/instances?limit=50&offset=${offset}`));
				if (!Array.isArray(page?.data)) throw new Error('Invalid XRift instance list');
				if (page.data.some(item => object(item)?.id === resource.id && object(item)?.worldId === data.worldId)) { isPublic = true; break; }
				if (page.data.length < 50) break;
			}
			if (!isPublic) { summary.xrift.state = 'unavailable'; return summary; }
			const world = publicWorld(object(await get(`/worlds/${data.worldId}`))?.data, data.worldId);
			if (!world) { summary.xrift.state = 'unavailable'; return summary; }
			await fillWorld(world);
			summary.xrift.createdAt = date(data.createdAt);
		} else {
			const world = publicWorld(data, resource.id);
			if (!world) { summary.xrift.state = 'unavailable'; return summary; }
			await fillWorld(world);
		}
	} catch (error) {
		// Never serialize provider errors: they may contain the Authorization header.
		summary.xrift.state = object(error)?.statusCode === 404 ? 'unavailable' : 'error';
	}
	return summary;
}
