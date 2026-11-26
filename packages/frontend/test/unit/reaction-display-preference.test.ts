/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { expect, test, vi } from 'vitest';
import { PreferencesManager } from '@/preferences/manager.js';
import type { PossiblyNonNormalizedPreferencesProfile, StorageProvider } from '@/preferences/manager.js';

vi.mock('@/os.js', () => ({}));

function storage(): StorageProvider {
	let saved: PossiblyNonNormalizedPreferencesProfile | null = null;
	return {
		load: () => saved && structuredClone(saved),
		save: ({ profile }) => { saved = JSON.parse(JSON.stringify(profile)); },
		cloudGet: async () => null,
		cloudGetBulk: async () => ({}),
		cloudSet: async () => {},
	};
}

test('defaults to avatars, retains a numeric choice after reload, and keeps accounts separate', async () => {
	const io = storage();
	const first = new PreferencesManager(io, { id: 'alice' });
	await first.cloudReady;
	expect(first.s.reactionUserDisplay).toBe('avatars');
	first.commit('reactionUserDisplay', 'count');
	const reloaded = new PreferencesManager(io, { id: 'alice' });
	const other = new PreferencesManager(io, { id: 'bob' });
	const guest = new PreferencesManager(io, null);
	await Promise.all([reloaded.cloudReady, other.cloudReady, guest.cloudReady]);
	expect(reloaded.s.reactionUserDisplay).toBe('count');
	expect(other.s.reactionUserDisplay).toBe('avatars');
	expect(guest.s.reactionUserDisplay).toBe('avatars');
});

test('syncs a changed choice to another tab without replacing unrelated reactive arrays', async () => {
	const io = storage();
	const first = new PreferencesManager(io, { id: 'alice' });
	const second = new PreferencesManager(io, { id: 'alice' });
	await Promise.all([first.cloudReady, second.cloudReady]);
	const plugins = second.s.plugins;
	first.on('saved', profile => second.reloadProfile(profile));
	first.commit('reactionUserDisplay', 'count');
	expect(second.r.reactionUserDisplay.value).toBe('count');
	expect(second.s.plugins).toBe(plugins);
	first.commit('reactionUserDisplay', 'avatars');
	expect(second.r.reactionUserDisplay.value).toBe('avatars');
});
