/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type { SummalyResult } from '@misskey-dev/summaly';
import type { ResonitePreview, ResoniteTextPart } from 'misskey-js';

type JsonObject = Record<string, unknown>;
export type ResoniteResource = { type: 'world' | 'session'; url: string; apiPath: string };
export type ResoniteSummary = SummalyResult & { resonite: ResonitePreview };
const ownerId = /^(U|G)-[a-zA-Z0-9._-]{1,128}$/;
const recordId = /^R-[a-zA-Z0-9_-]{1,128}$/;
const sessionId = /^S-[a-zA-Z0-9_:-]{1,190}$/;
const object = (value: unknown): JsonObject | null => value != null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : null;
const count = (value: unknown): number | undefined => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : undefined;
const date = (value: unknown): string | undefined => typeof value === 'string' && Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : undefined;

export function getResoniteResource(input: string): ResoniteResource | null {
	try {
		const url = new URL(input);
		if (url.username || url.password) return null;
		const path = url.origin === 'https://go.resonite.com' ? url.pathname : url.origin === 'https://api.resonite.com' && url.pathname.startsWith('/open/') ? url.pathname.slice(5) : null;
		if (!path) return null;
		const parts = path.replace(/\/$/, '').split('/').slice(1).map(decodeURIComponent);
		if ((parts[0] === 'world' || parts[0] === 'record') && parts.length === 3 && ownerId.test(parts[1]) && recordId.test(parts[2])) {
			const owner = encodeURIComponent(parts[1]);
			const record = encodeURIComponent(parts[2]);
			return { type: 'world', url: `https://go.resonite.com/world/${owner}/${record}`, apiPath: `/users/${owner}/records/${record}` };
		}
		if (parts[0] === 'session' && parts.length === 2 && sessionId.test(parts[1])) {
			const id = encodeURIComponent(parts[1]);
			return { type: 'session', url: `https://go.resonite.com/session/${id}`, apiPath: `/sessions/${id}` };
		}
	} catch { /* Invalid URLs use the ordinary preview. */ }
	return null;
}

const palette: Record<string, string> = {
	'hero.yellow': '#f8f770', 'hero.green': '#59eb5c', 'hero.red': '#ff7676', 'hero.purple': '#ba64f2', 'hero.cyan': '#61d1fa', 'hero.orange': '#e69e50',
	'neutrals.dark': '#11151d', 'neutrals.mid': '#2b2f35', 'neutrals.mid-light': '#86888b', 'neutrals.light': '#e1e1e0',
	'mid.yellow': '#a0a14e', 'mid.green': '#3f9e44', 'mid.red': '#ae5458', 'mid.purple': '#824aab', 'mid.cyan': '#458fab', 'mid.orange': '#976c3d',
	'sub.yellow': '#484a2c', 'sub.green': '#24512c', 'sub.red': '#5d323a', 'sub.purple': '#492f64', 'sub.cyan': '#284c5d', 'sub.orange': '#48392a',
	'dark.yellow': '#2b2e26', 'dark.green': '#192d24', 'dark.red': '#1a1318', 'dark.purple': '#241e35', 'dark.cyan': '#1a2a36', 'dark.orange': '#292423',
	white: '#ffffff', black: '#000000', gray: '#808080', red: '#ff0000', green: '#008000', blue: '#0000ff', yellow: '#ffff00', cyan: '#00ffff', magenta: '#ff00ff', orange: '#ffa500', purple: '#800080', lime: '#00ff00', pink: '#ffc0cb', brown: '#a52a2a',
};

/** Only text and validated colors leave the server; provider markup is never HTML. */
export function parseResoniteText(value: unknown): ResoniteTextPart[] {
	if (typeof value !== 'string') return [];
	const source = value.slice(0, 4096).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
	const parts: ResoniteTextPart[] = [];
	const colors: (string | undefined)[] = [];
	let offset = 0;
	const append = (text: string): void => {
		if (!text || parts.length >= 128) return;
		const color = colors.at(-1);
		const previous = parts.at(-1);
		if (previous && previous.color === color) previous.text += text;
		else parts.push({ text, ...(color ? { color } : {}) });
	};
	for (const match of source.matchAll(/<[^>]{0,256}>/g)) {
		append(source.slice(offset, match.index));
		const colorMatch = /^<color(?:=|\s)\s*["']?([^"'>\s]+)["']?\s*>$/i.exec(match[0]);
		if (colorMatch) {
			const color = colorMatch[1].toLowerCase();
			colors.push(/^#(?:[a-f\d]{3,4}|[a-f\d]{6}|[a-f\d]{8})$/.test(color) ? color : Object.hasOwn(palette, color) ? palette[color] : undefined);
		} else if (/^<\/color\s*>$/i.test(match[0])) colors.pop();
		else if (/^<br\s*\/?>$/i.test(match[0])) append('\n');
		offset = match.index + match[0].length;
	}
	append(source.slice(offset));
	return parts;
}

function plain(value: unknown): string {
	return parseResoniteText(value).map(part => part.text).join('').trim();
}

export function resoniteImageUrl(value: unknown): string | null {
	if (typeof value !== 'string') return null;
	const asset = /^resdb:\/\/\/([a-f\d]{64})(?:\.[a-z\d]+)?$/i.exec(value);
	if (asset) return `https://assets.resonite.com/${asset[1]}`;
	try {
		const url = new URL(value);
		return url.protocol === 'https:' && !url.port && !url.username && !url.password && ['assets.resonite.com', 'thumbnails.resonite.com'].includes(url.hostname) ? url.href : null;
	} catch { return null; }
}

export async function fetchResoniteSummary(input: string, getJson: (url: string) => Promise<unknown>): Promise<ResoniteSummary | null> {
	const resource = getResoniteResource(input);
	if (!resource) return null;
	const preview: ResonitePreview = { type: resource.type, state: 'available' };
	const summary: ResoniteSummary = {
		url: resource.url, title: null, description: null, thumbnail: null, icon: null, sitename: 'Resonite',
		thumbnailStyle: 'summary_large_image', player: { url: null, width: null, height: null, allow: [] },
		activityPub: null, fediverseCreator: null, resonite: preview,
	};
	const get = async (path: string): Promise<JsonObject | null> => object(await getJson(`https://api.resonite.com${path}`));
	const publicWorld = (world: JsonObject | null): world is JsonObject => !!world && world.recordType === 'world' && world.isPublic === true && !!plain(world.name);
	try {
		const data = await get(resource.apiPath);
		if (!data) throw new Error('Invalid Resonite response');
		if (resource.type === 'world') {
			const expected = resource.apiPath.split('/');
			if (data.id !== decodeURIComponent(expected[4]) || data.ownerId !== decodeURIComponent(expected[2])) throw new Error('Mismatched Resonite world');
			if (!publicWorld(data)) { preview.state = 'unavailable'; return summary; }
			preview.creator = plain(data.ownerName) || undefined;
			preview.visits = count(data.visits);
			preview.updatedAt = date(data.lastModificationTime);
			preview.featured = Array.isArray(data.submissions) && data.submissions.some(entry => object(entry)?.featured === true);
			summary.thumbnail = resoniteImageUrl(data.thumbnailUri);
		} else {
			if (data.sessionId !== decodeURIComponent(resource.apiPath.split('/')[2])) throw new Error('Mismatched Resonite session');
			if (!['Anyone', 'RegisteredUsers'].includes(data.accessLevel as string) || data.hideFromListing !== false) { preview.state = 'unavailable'; return summary; }
			if (data.hasEnded === true) preview.state = 'ended';
			else if (data.isValid !== true || !plain(data.name)) { preview.state = 'unavailable'; return summary; }
			preview.creator = plain(data.hostUsername) || undefined;
			// totalJoinedUsers includes nested sessions and cannot be compared to maxUsers.
			preview.currentUsers = count(data.joinedUsers);
			preview.maxUsers = count(data.maxUsers);
			preview.createdAt = date(data.sessionBeginTime);
			summary.thumbnail = resoniteImageUrl(data.thumbnailUrl);
			const reference = object(data.correspondingWorldId);
			if (reference && ownerId.test(String(reference.ownerId)) && recordId.test(String(reference.recordId))) {
				const worldUrl = `https://go.resonite.com/world/${encodeURIComponent(String(reference.ownerId))}/${encodeURIComponent(String(reference.recordId))}`;
				try {
					const worldResource = getResoniteResource(worldUrl)!;
					const world = await get(worldResource.apiPath);
					if (publicWorld(world) && world.id === reference.recordId && world.ownerId === reference.ownerId) {
						preview.worldUrl = worldUrl;
						summary.description = plain(world.description) || null;
						summary.thumbnail ??= resoniteImageUrl(world.thumbnailUri);
					}
				} catch { /* The live session remains usable without its saved world. */ }
			}
		}
		preview.titleParts = parseResoniteText(data.name);
		summary.title = plain(data.name);
		summary.description = plain(data.description) || summary.description;
	} catch (error) {
		const status = object(error)?.statusCode;
		preview.state = status === 404 || status === 403 || status === 401 ? 'unavailable' : 'error';
	}
	return summary;
}
