/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export type DoomResult = {
	version: 1;
	game: 'doom' | 'freedoom';
	episode: number;
	map: number;
	skill: number;
	kills: number;
	totalKills: number;
	items: number;
	totalItems: number;
	secrets: number;
	totalSecrets: number;
	ticks: number;
	completed: boolean;
	dead: boolean;
};

const limits = { episode: 9, map: 99, skill: 5, kills: 100000, totalKills: 100000, items: 100000, totalItems: 100000, secrets: 100000, totalSecrets: 100000, ticks: 35 * 60 * 60 * 24 };

/** Treat iframe messages and shared links as untrusted, self-reported data. */
export function parseDoomResult(value: unknown): DoomResult | null {
	if (value == null || typeof value !== 'object') return null;
	const result = value as Record<string, unknown>;
	if (result.version !== 1 || (result.game !== 'doom' && result.game !== 'freedoom')) return null;
	if (typeof result.completed !== 'boolean' || typeof result.dead !== 'boolean') return null;
	for (const [key, max] of Object.entries(limits)) {
		const n = result[key];
		if (typeof n !== 'number' || !Number.isInteger(n) || n < 0 || n > max) return null;
	}
	if (Number(result.episode) < 1 || Number(result.map) < 1 || Number(result.skill) < 1) return null;
	if (Number(result.secrets) > Number(result.totalSecrets) || Number(result.items) > Number(result.totalItems)) return null;
	return Object.fromEntries(['version', 'game', ...Object.keys(limits), 'completed', 'dead'].map(key => [key, result[key]])) as DoomResult;
}

export function decodeDoomResult(encoded?: string): DoomResult | null {
	if (!encoded || encoded.length > 1000) return null;
	try {
		return parseDoomResult(JSON.parse(encoded));
	} catch {
		return null;
	}
}

export function doomScore(result: DoomResult): number {
	return result.kills * 100 + result.items * 10 + result.secrets * 250;
}

export function doomTime(ticks: number): string {
	const seconds = Math.floor(ticks / 35);
	return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

export function doomResultUrl(origin: string, result: DoomResult): string {
	const url = new URL('/play/doom', origin);
	url.searchParams.set('result', JSON.stringify(result));
	return url.href;
}

/** Only IWADs are accepted; local files are never uploaded to the server. */
export function isDoomIwad(data: Uint8Array): boolean {
	if (data.byteLength < 12 || data.byteLength > 64 * 1024 * 1024) return false;
	if (String.fromCharCode(...data.subarray(0, 4)) !== 'IWAD') return false;
	const header = new DataView(data.buffer, data.byteOffset, data.byteLength);
	const count = header.getUint32(4, true);
	const directory = header.getUint32(8, true);
	return count > 0 && directory >= 12 && directory + count * 16 <= data.byteLength;
}
