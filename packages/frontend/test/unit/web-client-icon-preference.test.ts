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

test('fixed and random choices survive reload and stay separate for each account and guests', async () => {
	const io = storage();
	const alice = new PreferencesManager(io, { id: 'alice' });
	await alice.cloudReady;
	expect(alice.s.webClientIcon).toBe('random');
	alice.commit('webClientIcon', 'sharuya');
	const reloaded = new PreferencesManager(io, { id: 'alice' });
	const bob = new PreferencesManager(io, { id: 'bob' });
	const guest = new PreferencesManager(io, null);
	await Promise.all([reloaded.cloudReady, bob.cloudReady, guest.cloudReady]);
	expect(reloaded.s.webClientIcon).toBe('sharuya');
	expect(bob.s.webClientIcon).toBe('random');
	expect(guest.s.webClientIcon).toBe('random');
	reloaded.commit('webClientIcon', 'random');
	const randomized = new PreferencesManager(io, { id: 'alice' });
	await randomized.cloudReady;
	expect(randomized.s.webClientIcon).toBe('random');
});

test('the existing saved-profile synchronization updates the icon ref in another tab', async () => {
	const io = storage();
	const first = new PreferencesManager(io, { id: 'alice' });
	const second = new PreferencesManager(io, { id: 'alice' });
	await Promise.all([first.cloudReady, second.cloudReady]);
	first.on('saved', profile => second.reloadProfile(profile));
	first.commit('webClientIcon', 'ningen');
	expect(second.r.webClientIcon.value).toBe('ningen');
	first.commit('webClientIcon', 'random');
	expect(second.r.webClientIcon.value).toBe('random');
});

test('account-scoped icon settings cannot disable their required account scope, while ordinary settings still can', async () => {
	const manager = new PreferencesManager(storage(), { id: 'alice' });
	await manager.cloudReady;
	expect(manager.getPerPrefMenu('webClientIcon').at(-2)).toMatchObject({ type: 'switch', disabled: true });
	expect(manager.getPerPrefMenu('animation').at(-2)).toMatchObject({ type: 'switch', disabled: false });
});
