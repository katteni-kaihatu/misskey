/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type { Endpoints, entities } from 'misskey-js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { $i } from '@/i.js';

type Capabilities = Endpoints['auto-translation/capabilities']['res'];
export type TranslationResult = Endpoints['auto-translation/translate-note']['res'];

// Only in-flight requests are shared. Every later read rechecks server permissions.
const pending = new Map<string, { promise: Promise<TranslationResult>; consumers: Set<() => boolean> }>();
let capabilities: { account: string; expires: number; promise: Promise<Capabilities> } | undefined;
let running = 0;
const queue: (() => void)[] = [];

export function getAutoTranslationCapabilities(refresh = false): Promise<Capabilities> {
	const account = $i?.id ?? '';
	if (!account) return Promise.resolve({ available: false, languages: [] });
	if (refresh || !capabilities || capabilities.account !== account || capabilities.expires < Date.now()) {
		const promise = misskeyApi('auto-translation/capabilities');
		capabilities = { account, expires: Date.now() + 30_000, promise };
		promise.catch(() => { if (capabilities?.promise === promise) capabilities = undefined; });
	}
	return capabilities.promise;
}

export async function requestAutoTranslation(note: entities.Note, targetLang: string, isCurrent: () => boolean): Promise<TranslationResult> {
	const account = $i?.id;
	if (!account || !isCurrent()) throw new Error('cancelled');
	const key = JSON.stringify([account, note.id, note.text, note.cw, targetLang]);
	const existing = pending.get(key);
	if (existing) {
		existing.consumers.add(isCurrent);
		try {
			return await existing.promise;
		} finally {
			existing.consumers.delete(isCurrent);
		}
	}
	if (queue.length >= 64) throw new Error('busy');
	const consumers = new Set([isCurrent]);
	const promise = (async () => {
		if (running >= 2) {
			await new Promise<void>(resolve => queue.push(resolve));
		} else {
			running++;
		}
		try {
			if (![...consumers].some(current => current()) || $i?.id !== account) throw new Error('cancelled');
			return await misskeyApi('auto-translation/translate-note', { noteId: note.id, targetLang });
		} finally {
			const next = queue.shift();
			if (next) next();
			else running--;
		}
	})();
	pending.set(key, { promise, consumers });
	try {
		return await promise;
	} finally {
		consumers.delete(isCurrent);
		if (pending.get(key)?.promise === promise) pending.delete(key);
	}
}
