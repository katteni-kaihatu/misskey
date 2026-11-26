/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render } from '@testing-library/vue';
import { shallowRef } from 'vue';
import Viewer from '@/components/MkReactionsViewer.vue';
import { prefer } from '@/preferences.js';

const mocks = vi.hoisted(() => ({ add: vi.fn(), remove: vi.fn(), fetch: vi.fn(), menu: vi.fn(), confirm: vi.fn(), tooltip: vi.fn(), popup: vi.fn(() => ({ dispose: vi.fn() })) }));
vi.mock('@@/js/config.js', () => ({ host: 'g.test' }));
vi.mock('@/utility/synced-reaction-aliases.js', () => ({ useSyncedReactionAliases: () => shallowRef({ ':cat@r.test:': ':cat@.:' }) }));
vi.mock('@/utility/extended-reactions.js', () => ({ addExtendedReaction: mocks.add, deleteExtendedReaction: mocks.remove, fetchReactionUsers: mocks.fetch }));
vi.mock('@/preferences.js', async () => ({ prefer: { s: { animation: false, dataSaver: {}, confirmOnReact: false }, r: { reactionUserDisplay: (await import('vue')).ref('avatars') } } }));
vi.mock('@/i.js', () => ({ $i: { id: 'me' } }));
vi.mock('@/custom-emojis.js', () => ({ customEmojisMap: new Map([['cat', {}]]) }));
vi.mock('@/os.js', () => ({ confirm: mocks.confirm, popupMenu: mocks.menu, alert: vi.fn(), popup: mocks.popup }));
vi.mock('@/utility/misskey-api.js', () => ({ misskeyApi: vi.fn(), misskeyApiGet: vi.fn() }));
vi.mock('@/composables/use-tooltip.js', () => ({ useTooltip: mocks.tooltip }));
vi.mock('@/utility/emoji-mute.js', () => ({ checkMuted: () => ({ value: false }), mute: vi.fn(), unmute: vi.fn() }));
vi.mock('@/utility/emoji-palette.js', () => ({ addToEmojiPalette: vi.fn() }));
vi.mock('@/utility/media-proxy.js', () => ({ getStaticImageUrl: (url: string) => url }));
vi.mock('@/utility/sound.js', () => ({ playMisskeySfx: vi.fn() }));
vi.mock('@/utility/haptic.js', () => ({ haptic: vi.fn() }));
vi.mock('@/store.js', () => ({ store: {} }));
vi.mock('@/composables/use-note-capture.js', () => ({ noteEvents: { emit: vi.fn() } }));
vi.mock('@/i18n.js', () => ({ i18n: { ts: { more: 'More', info: 'Info', emojiMute: 'Mute', addToEmojiPalette: 'Palette', cancelReactionConfirm: 'Remove?' }, tsx: {} } }));
vi.mock('@/components/MkCustomEmojiDetailedDialog.vue', () => ({ default: { template: '<div/>' } }));
vi.mock('@/components/MkReactionsViewer.details.vue', () => ({ default: { template: '<div/>' } }));
vi.mock('@/components/MkReactionIcon.vue', () => ({ default: { props: ['reaction'], template: '<span>{{ reaction }}</span>' } }));
vi.mock('@/components/MkReactionEffect.vue', () => ({ default: { template: '<div/>' } }));

beforeEach(() => { vi.clearAllMocks(); prefer.r.reactionUserDisplay.value = 'avatars'; mocks.confirm.mockResolvedValue({ canceled: false }); mocks.fetch.mockResolvedValue([]); mocks.add.mockResolvedValue(undefined); mocks.remove.mockResolvedValue(undefined); });
afterEach(cleanup);
const base = { noteId: 'note', reactions: { ':cat@r.test:': 1, ':cat@.:': 1 }, reactionEmojis: {}, myReaction: null, extendedReactions: true };
const global = { directives: { ripple: {} }, stubs: { MkAvatar: { props: ['user'], template: '<span :data-user="user.id"/>' } } };

test('one button adds the local emoji and fetches avatars for both raw keys', async () => {
	mocks.fetch.mockImplementation(async (_id, reaction) => [{ user: { id: reaction } }]);
	const view = render(Viewer, { props: base, global });
	expect(view.getAllByRole('button')).toHaveLength(1);
	await vi.waitFor(() => expect(view.container.querySelectorAll('[data-user]')).toHaveLength(2));
	await fireEvent.click(view.getByRole('button'));
	expect(mocks.add).toHaveBeenCalledWith('note', ':cat@.:');
});

test('selected grouped reactions remove the original keys after one confirmation', async () => {
	const view = render(Viewer, { props: { ...base, myReactions: [':cat@r.test:', ':cat@.:'] }, global });
	expect(view.getByRole('button').getAttribute('aria-pressed')).toBe('true');
	await fireEvent.click(view.getByRole('button'));
	await vi.waitFor(() => expect(mocks.remove).toHaveBeenCalledTimes(2));
	expect(mocks.remove.mock.calls).toEqual([['note', ':cat@r.test:'], ['note', ':cat@.:']]);
	expect(mocks.confirm).toHaveBeenCalledTimes(1);
});

test('delegated additions qualify the source emoji, while lists and removals keep both original keys', async () => {
	const transport = { canToggle: () => true, toggle: vi.fn(), previews: () => [], users: vi.fn(async () => []), showUsers: vi.fn() };
	const view = render(Viewer, { props: { ...base, reactions: { ':cat@.:': 1, ':cat@g.test:': 1 }, reactionHost: 'r.test', transport }, global });
	expect(view.getAllByRole('button')).toHaveLength(1);
	await fireEvent.click(view.getByRole('button'));
	expect(transport.toggle).toHaveBeenCalledWith(':cat@r.test:');
	await fireEvent.contextMenu(view.getByRole('button'));
	mocks.menu.mock.calls[0][0].find((item: { text: string }) => item.text === 'More').action();
	expect(transport.showUsers).toHaveBeenCalledWith([':cat@.:', ':cat@g.test:']);
	await view.rerender({ myReactions: [':cat@.:', ':cat@g.test:'] });
	transport.toggle.mockClear();
	await fireEvent.click(view.getByRole('button'));
	await vi.waitFor(() => expect(transport.toggle.mock.calls).toEqual([[':cat@.:'], [':cat@g.test:']]));
});

test('numeric mode uses the grouped count without loading avatar previews and keeps reaction toggling', async () => {
	prefer.r.reactionUserDisplay.value = 'count';
	const view = render(Viewer, { props: { ...base, reactions: { ':cat@r.test:': 7, ':cat@.:': 5 } }, global });
	expect(view.getByRole('button').textContent).toBe(':cat@.:12');
	expect(mocks.fetch).not.toHaveBeenCalled();
	expect(view.container.querySelector('[data-user]')).toBeNull();
	await fireEvent.click(view.getByRole('button'));
	expect(mocks.add).toHaveBeenCalledWith('note', ':cat@.:');
	await view.rerender({ reactions: { ':cat@r.test:': 8, ':cat@.:': 5 } });
	expect(view.getByRole('button').textContent).toBe(':cat@.:13');
	expect(mocks.fetch).not.toHaveBeenCalled();
});

test('switching modes drops in-flight avatar responses and switching back reloads previews', async () => {
	let resolve!: (value: { user: { id: string } }[]) => void;
	mocks.fetch.mockImplementation(() => new Promise(r => { resolve = r; }));
	const view = render(Viewer, { props: { ...base, reactions: { ':cat@.:': 2 } }, global });
	prefer.r.reactionUserDisplay.value = 'count';
	await vi.waitFor(() => expect(view.getByRole('button').textContent).toBe(':cat@.:2'));
	resolve([{ user: { id: 'late' } }]);
	await Promise.resolve();
	expect(view.container.querySelector('[data-user]')).toBeNull();
	mocks.fetch.mockResolvedValue([{ user: { id: 'fresh' } }]);
	prefer.r.reactionUserDisplay.value = 'avatars';
	await vi.waitFor(() => expect(view.container.querySelector('[data-user="fresh"]')).not.toBeNull());
	expect(view.getByRole('button').textContent).toBe(':cat@.:');
});

test('numeric mode still fetches local reaction details on demand', async () => {
	prefer.r.reactionUserDisplay.value = 'count';
	mocks.fetch.mockResolvedValue([{ user: { id: 'reactor' } }]);
	render(Viewer, { props: base, global });
	expect(mocks.fetch).not.toHaveBeenCalled();
	await mocks.tooltip.mock.calls[0][1](shallowRef(true));
	expect(mocks.fetch).toHaveBeenCalledTimes(2);
	expect(mocks.popup.mock.calls[0][1]).toMatchObject({ users: [{ id: 'reactor' }], count: 2 });
});

test('peer reactions switch between avatar previews and numeric totals, retaining on-demand details', async () => {
	const actor = { uri: 'https://r.test/users/1', username: 'reactor', host: 'r.test', name: null, avatarUrl: 'https://r.test/avatar.png' };
	const transport = { canToggle: () => true, toggle: vi.fn(), previews: vi.fn(() => [actor]), users: vi.fn(async () => [actor]), showUsers: vi.fn() };
	const view = render(Viewer, { props: { ...base, reactions: { ':cat@.:': 15 }, reactionHost: 'r.test', transport }, global });
	await vi.waitFor(() => expect(view.container.querySelectorAll('img')).toHaveLength(1));
	transport.previews.mockClear();
	prefer.r.reactionUserDisplay.value = 'count';
	await vi.waitFor(() => expect(view.getByRole('button').textContent).toBe(':cat@.:15'));
	expect(view.container.querySelector('img')).toBeNull();
	expect(transport.previews).not.toHaveBeenCalled();
	await mocks.tooltip.mock.calls[0][1](shallowRef(true));
	expect(transport.users).toHaveBeenCalledWith(':cat@.:');
	expect(mocks.popup.mock.calls[0][1]).toMatchObject({ actors: [actor], count: 15 });
	prefer.r.reactionUserDisplay.value = 'avatars';
	await vi.waitFor(() => expect(view.container.querySelectorAll('img')).toHaveLength(1));
});
