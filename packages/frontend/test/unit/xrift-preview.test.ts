/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { afterEach, beforeAll, describe, expect, test } from 'vitest';
import { cleanup, render } from '@testing-library/vue';
import locales from 'i18n';
import { updateI18n } from '@/i18n.js';
import MkXriftPreview from '@/components/MkXriftPreview.vue';
import { World, Room, Profile, Item } from '@/components/MkXriftPreview.stories.impl.js';
import { preferState } from '../setup.unit.js';

beforeAll(() => updateI18n(locales['ja-JP']));
afterEach(cleanup);

describe('XRift cards', () => {
	test('items display their creator, acquisition count and a marketplace link', () => {
		const view = render(MkXriftPreview, { props: Item.args });
		expect(view.getByText('アイテム')).toBeTruthy();
		expect(view.getByText('42人が入手')).toBeTruthy();
		expect(view.getByText('Item creator')).toBeTruthy();
		expect(view.getByRole('link', { name: 'アイテムを見る' }).getAttribute('href')).toBe(Item.args.url);
		expect(view.container.querySelector('iframe')).toBeNull();
	});
	test('unavailable items keep a direct link and hide cached details', () => {
		const view = render(MkXriftPreview, { props: { ...Item.args, summary: { ...Item.args.summary, xrift: { type: 'item', state: 'unavailable', creator: null } } } });
		expect(view.getByText('このアイテムは利用できません')).toBeTruthy();
		expect(view.queryByText('Picture Frame')).toBeNull();
		expect(view.getByRole('link', { name: 'XRiftで開く' }).getAttribute('href')).toBe(Item.args.url);
	});
	test('shows the world type, visits, branding and a working entry link', () => {
		const view = render(MkXriftPreview, { props: World.args });
		expect(view.getByText('ワールド')).toBeTruthy();
		expect(view.getByText('12,345 visits')).toBeTruthy();
		expect(view.getByRole('img', { name: 'XRift' })).toBeTruthy();
		expect(view.getByRole('link', { name: 'ワールドに入る' }).getAttribute('href')).toBe(World.args.url);
	});
	test('an instance shows its active state, world context and join action', () => {
		const view = render(MkXriftPreview, { props: Room.args });
		expect(view.getByText('インスタンス')).toBeTruthy();
		expect(view.queryByText('LIVE')).toBeNull();
		expect(view.getByText('開催中')).toBeTruthy();
		expect(view.getByRole('link', { name: 'このインスタンスに参加' }).getAttribute('href')).toBe(Room.args.url);
		expect(view.getByText('ワールド「Cozy Workspace Cafe」のインスタンスです。URLからそのまま参加できます。')).toBeTruthy();
		const time = view.getByText('1時間24分前に開始');
		expect(time.closest('p')?.textContent).toContain('ワールド作者');
		expect(view.queryByText('12,345 visits')).toBeNull();
	});
	test('profiles show a count and links to their public worlds', () => {
		const view = render(MkXriftPreview, { props: Profile.args });
		expect(view.getByText('12')).toBeTruthy();
		expect(view.getByRole('link', { name: 'Cozy Workspace Cafe' }).getAttribute('href')).toBe(World.args.url);
	});
	test('profiles without public worlds omit the count and keep the profile action beside the identity', () => {
		const view = render(MkXriftPreview, { props: { ...Profile.args, summary: { ...Profile.args.summary, xrift: { ...Profile.args.summary.xrift, totalWorlds: 0, worlds: [] } } } });
		expect(view.queryByText('公開ワールド')).toBeNull();
		expect(view.queryByText('0')).toBeNull();
		const name = view.getByRole('heading', { name: 'ワールド作者' });
		const link = view.getByRole('link', { name: 'プロフィールを見る' });
		expect(name.parentElement?.parentElement).toBe(link.parentElement);
	});
	test('keeps worlds beyond the third in the scrollable list', () => {
		const worlds = Array.from({ length: 8 }, (_, i) => ({ url: `${World.args.url}?world=${i}`, title: `World ${i}`, thumbnail: null }));
		const view = render(MkXriftPreview, { props: { ...Profile.args, summary: { ...Profile.args.summary, xrift: { ...Profile.args.summary.xrift, totalWorlds: 8, worlds } } } });
		expect(view.getByRole('region', { name: '公開ワールド' })).toBeTruthy();
		expect(view.getByRole('link', { name: 'World 7' })).toBeTruthy();
		expect(view.getByRole('button', { name: '前のワールドを表示' })).toBeTruthy();
		expect(view.getByRole('button', { name: '次のワールドを表示' })).toBeTruthy();
	});
	test('does not present unavailable counts as zero or an active room', () => {
		const view = render(MkXriftPreview, { props: { ...Room.args, summary: { ...Room.args.summary, xrift: { type: 'instance', state: 'error', creator: null } } } });
		expect(view.queryByText('LIVE')).toBeNull();
		expect(view.queryByText('公開中のインスタンスはありません')).toBeNull();
		expect(view.getByRole('link', { name: 'XRiftで開く' })).toBeTruthy();
	});
	test('keeps a usable action for private or missing resources', () => {
		const view = render(MkXriftPreview, { props: { ...World.args, summary: { ...World.args.summary, xrift: { type: 'world', state: 'unavailable', creator: null } } } });
		expect(view.getByText('非公開のワールド')).toBeTruthy();
		expect(view.getByRole('link', { name: 'XRiftで開く' })).toBeTruthy();
	});
	test('an actual zero room count invites the first visitor', () => {
		const view = render(MkXriftPreview, { props: { ...World.args, summary: { ...World.args.summary, xrift: { ...World.args.summary.xrift, publicInstances: 0 } } } });
		expect(view.getByRole('link', { name: 'ワールドに入る' })).toBeTruthy();
	});
	test('keeps the world description when there are no public instances', () => {
		const view = render(MkXriftPreview, { props: { ...World.args, summary: { ...World.args.summary, xrift: { ...World.args.summary.xrift, publicInstances: 0 } } } });
		expect(view.getByText(World.args.summary.description!)).toBeTruthy();
		expect(view.queryByText('公開中のインスタンスはありません')).toBeNull();
	});
	test('uses the empty-instance message only when the world has no description', () => {
		const view = render(MkXriftPreview, { props: { ...World.args, summary: { ...World.args.summary, description: ' ', xrift: { ...World.args.summary.xrift, publicInstances: 0 } } } });
		expect(view.getByText('公開中のインスタンスはありません')).toBeTruthy();
	});
	test('sensitive and data saver modes also hide profile world images', () => {
		const saved = preferState.dataSaver;
		try {
			preferState.dataSaver = { urlPreviewThumbnail: true };
			const summary = { ...Profile.args.summary, thumbnail: 'https://media.example/avatar', xrift: { ...Profile.args.summary.xrift, worlds: [{ url: World.args.url, title: 'Cafe', thumbnail: 'https://media.example/image' }] } };
			const view = render(MkXriftPreview, { props: { ...Profile.args, summary } });
			expect(view.queryAllByRole('img')).toEqual([view.getByRole('img', { name: 'XRift' })]);
		} finally { preferState.dataSaver = saved; }
	});
	test('hides both the main thumbnail and decorative backdrop for sensitive worlds', () => {
		const summary = { ...World.args.summary, thumbnail: 'https://media.example/image', sensitive: true };
		const view = render(MkXriftPreview, { props: { ...World.args, summary } });
		expect(view.container.querySelectorAll('img[src="https://media.example/image"]')).toHaveLength(0);
		expect(view.getByRole('img', { name: 'XRift' })).toBeTruthy();
	});
});
