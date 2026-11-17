/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { afterEach, beforeAll, describe, expect, test } from 'vitest';
import { cleanup, render } from '@testing-library/vue';
import locales from 'i18n';
import { updateI18n } from '@/i18n.js';
import MkXriftPreview from '@/components/MkXriftPreview.vue';
import { World, Room, Profile } from '@/components/MkXriftPreview.stories.impl.js';
import { preferState } from '../setup.unit.js';

beforeAll(() => updateI18n(locales['ja-JP']));
afterEach(cleanup);

describe('XRift cards', () => {
	test('shows visits, public rooms and a working world link', () => {
		const view = render(MkXriftPreview, { props: World.args });
		expect(view.getAllByText('12,345').length).toBeGreaterThan(0);
		expect(view.getByText('2ルーム公開中')).toBeTruthy();
		expect(view.getByRole('link', { name: 'ブラウザで入る' }).getAttribute('href')).toBe(World.args.url);
	});
	test('a room has distinct join and world links and elapsed time', () => {
		const view = render(MkXriftPreview, { props: Room.args });
		expect(view.getByText('LIVE')).toBeTruthy();
		expect(view.getByRole('link', { name: 'このルームに参加' }).getAttribute('href')).toBe(Room.args.url);
		expect(view.getByRole('link', { name: 'ワールドを見る' }).getAttribute('href')).toBe(World.args.url);
		expect(view.getByText(/1時間24分/)).toBeTruthy();
	});
	test('profiles show a count and links to their public worlds', () => {
		const view = render(MkXriftPreview, { props: Profile.args });
		expect(view.getByText('12')).toBeTruthy();
		expect(view.getByRole('link', { name: 'Cozy Workspace Cafe' }).getAttribute('href')).toBe(World.args.url);
	});
	test('does not present unavailable counts as zero or an active room', () => {
		const view = render(MkXriftPreview, { props: { ...Room.args, summary: { ...Room.args.summary, xrift: { type: 'instance', state: 'error', creator: null } } } });
		expect(view.queryByText('LIVE')).toBeNull();
		expect(view.queryByText('公開中のルームはありません')).toBeNull();
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
	test('sensitive and data saver modes also hide profile world images', () => {
		const saved = preferState.dataSaver;
		try {
			preferState.dataSaver = { urlPreviewThumbnail: true };
			const summary = { ...Profile.args.summary, thumbnail: 'https://media.example/avatar', xrift: { ...Profile.args.summary.xrift, worlds: [{ url: World.args.url, title: 'Cafe', thumbnail: 'https://media.example/image' }] } };
			const view = render(MkXriftPreview, { props: { ...Profile.args, summary } });
			expect(view.queryAllByRole('img')).toHaveLength(0);
		} finally { preferState.dataSaver = saved; }
	});
});
