/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type { entities } from 'misskey-js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { noteEvents } from '@/composables/use-note-capture.js';

export function supportsExtendedReactions(note: entities.Note): boolean {
	return note.user.host == null || note.gridspaceReactions === true || (note.gridspaceShared === true && !note.channel && ['public', 'home'].includes(note.visibility));
}

export type ExtendedReactionState = {
	noteId: string;
	reactions: Record<string, number>;
	reactionEmojis: Record<string, string>;
	myReaction: string | null;
	myReactions: string[];
	shared?: boolean;
	push?: boolean;
	complete?: boolean;
	revision?: string;
	reactionVersions?: Record<string, string>;
};

const subscriptions = new Map<() => void, boolean>();
let refreshTimer: number | undefined;
const resume = () => {
	if (!window.document.hidden) for (const callback of subscriptions.keys()) callback();
};

/** Push-capable peers use note streams; polling remains only for older peers/modes. */
export function watchSharedReactions(refresh: () => void, push = false): () => void {
	if (subscriptions.size === 0) window.document.addEventListener('visibilitychange', resume);
	subscriptions.set(refresh, push);
	refreshTimer ??= window.setInterval(() => {
		if (!window.document.hidden) for (const [callback, usesPush] of subscriptions) if (!usesPush) callback();
	}, 10000);
	return () => {
		subscriptions.delete(refresh);
		if (subscriptions.size === 0) {
			window.clearInterval(refreshTimer); refreshTimer = undefined;
			window.document.removeEventListener('visibilitychange', resume);
		}
	};
}

// Batch timeline requests and share each response between repeated note views.
const pending = new Map<string, { resolve: (state: ExtendedReactionState | undefined) => void; reject: (reason: unknown) => void; }[]>();
let showTimer: number | undefined;
let showing = false;
let nextShowAt = 0;
const inFlight = new Map<string, Promise<ExtendedReactionState | undefined>>();
const cooldowns = new Map<string, { until: number; error: unknown }>();

export function reactionRetryDelay(error: unknown): number | undefined {
	if (typeof error !== 'object' || error == null || !('code' in error) || error.code !== 'RATE_LIMIT_EXCEEDED') return undefined;
	const reset = 'info' in error && typeof error.info === 'object' && error.info != null && 'reset' in error.info ? Number(error.info.reset) * 1000 : 0;
	return Number.isFinite(reset) && reset > Date.now() ? Math.min(300000, Math.max(1000, reset - Date.now() + 1000)) : 60000;
}

function rateLimited(endpoint: string, error: unknown): void {
	const delay = reactionRetryDelay(error);
	if (delay !== undefined) cooldowns.set(endpoint, { until: Date.now() + delay, error });
}

function scheduleShow(): void {
	if (showTimer !== undefined || showing || pending.size === 0) return;
	// Per-note retry/update timers run in separate tasks. A microtask cannot batch
	// them, even when all timers expire together. Leave a small gathering window.
	showTimer = window.setTimeout(() => {
		showTimer = undefined;
		void flushShow();
	}, Math.max(25, nextShowAt - Date.now(), (cooldowns.get('show')?.until ?? 0) - Date.now()));
}

async function flushShow(): Promise<void> {
	const batch = [...pending.entries()].slice(0, 100);
	for (const [id] of batch) pending.delete(id);
	showing = true;
	// Keep a single tab below the endpoint's 120 requests/minute budget.
	nextShowAt = Date.now() + 600;
	try {
		const states = await misskeyApi('notes/extended-reactions/show', { noteIds: batch.map(([id]) => id) });
		for (const [id, callbacks] of batch) {
			const state = states.find(item => item.noteId === id);
			for (const callback of callbacks) callback.resolve(state);
		}
	} catch (error) {
		rateLimited('show', error);
		for (const [, callbacks] of batch) for (const callback of callbacks) callback.reject(error);
	} finally {
		showing = false;
		scheduleShow();
	}
}

export function fetchExtendedReactions(noteId: string): Promise<ExtendedReactionState | undefined> {
	const existing = inFlight.get(noteId);
	if (existing) return existing;
	const promise = new Promise<ExtendedReactionState | undefined>((resolve, reject) => {
		const callbacks = pending.get(noteId) ?? [];
		callbacks.push({ resolve, reject });
		pending.set(noteId, callbacks);
	});
	inFlight.set(noteId, promise);
	const clear = () => { inFlight.delete(noteId); };
	void promise.then(clear, clear);
	scheduleShow();
	return promise;
}

// Repeated note views and hover tooltips share the same short-lived reactor page.
// The revision is part of the key, so changes never reuse an earlier page.
const reactorPages = new Map<string, { expires: number; promise: Promise<entities.NoteReaction[]> }>();
export function fetchReactionUsers(noteId: string, type: string, extended: boolean, count: number, version?: string | number): Promise<entities.NoteReaction[]> {
	const now = Date.now();
	for (const [key, entry] of reactorPages) if (entry.expires <= now) reactorPages.delete(key);
	const key = JSON.stringify([noteId, type, extended, count, version]);
	const cached = reactorPages.get(key);
	if (cached) return cached.promise;
	const cooldown = cooldowns.get(extended ? 'list' : 'ordinary-list');
	if (cooldown && cooldown.until > now) return Promise.reject(cooldown.error);
	const promise = misskeyApi(extended ? 'notes/extended-reactions/list' : 'notes/reactions', { noteId, type, limit: 10 });
	if (reactorPages.size >= 500) reactorPages.delete(reactorPages.keys().next().value!);
	const entry = { expires: Infinity, promise };
	reactorPages.set(key, entry);
	void promise.then(() => { entry.expires = Date.now() + 5000; }, error => {
		rateLimited(extended ? 'list' : 'ordinary-list', error);
		if (reactorPages.get(key) === entry) reactorPages.delete(key);
	});
	return promise;
}

export async function addExtendedReaction(noteId: string, reaction: string): Promise<void> {
	await misskeyApi('notes/extended-reactions/create', { noteId, reaction });
	noteEvents.emit(`extendedUpdated:${noteId}`);
}

export async function deleteExtendedReaction(noteId: string, reaction: string): Promise<void> {
	await misskeyApi('notes/extended-reactions/delete', { noteId, reaction });
	noteEvents.emit(`extendedUpdated:${noteId}`);
}
