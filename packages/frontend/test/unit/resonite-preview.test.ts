/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import { afterEach, beforeAll, describe, expect, test } from 'vitest';
import { cleanup, render } from '@testing-library/vue';
import locales from 'i18n';
import { updateI18n } from '@/i18n.js';
import { preferState } from '../setup.unit.js';
import { getResoniteLink } from '@/utility/resonite-link.js';
import { readableResoniteColor } from '@/utility/resonite-text.js';
import MkResonitePreview from '@/components/MkResonitePreview.vue';
import { World, Session, Full, Ended, Unavailable, Error as ErrorStory } from '@/components/MkResonitePreview.stories.impl.js';

beforeAll(() => updateI18n(locales['ja-JP']));
afterEach(cleanup);

describe('Resonite previews', () => {
	test('world cards preserve colored titles and offer native and web links', () => {
		const view = render(MkResonitePreview, { props: World.args });
		expect(view.getByText('ワールド')).toBeTruthy();
		expect(view.getByText('24 visits', { exact: false })).toBeTruthy();
		expect(view.getByText(World.args.summary.description!)).toBeTruthy();
		expect(view.getByText('Cozy').style.color).toMatch(/^(#61d1fa|rgb\(97, 209, 250\))$/);
		expect(view.getByRole('link', { name: 'Resoniteで開く' }).getAttribute('href')).toBe('resrec:///U-Example/R-12345678-1234-1234-1234-123456789abc');
		expect(view.getByRole('link', { name: 'Webで見る' }).getAttribute('href')).toBe(World.args.url);
		expect(view.container.querySelector('iframe')).toBeNull();
	});
	test('session cards display actual occupancy and a join link', () => {
		const view = render(MkResonitePreview, { props: Session.args });
		expect(view.getByText('5/32人')).toBeTruthy();
		expect(view.getByText('セッション')).toBeTruthy();
		expect(view.getByText('ホスト Example host', { exact: false })).toBeTruthy();
		expect(view.getByRole('link', { name: 'Resoniteで参加' }).getAttribute('href')).toBe('ressession:///S-Example');
	});
	test('full and ended sessions can open their verified public world', () => {
		const view = render(MkResonitePreview, { props: Full.args });
		expect(view.getByText('満員')).toBeTruthy();
		expect(view.getByRole('link', { name: 'ワールドを開く' }).getAttribute('href')).toBe('resrec:///U-Example/R-12345678-1234-1234-1234-123456789abc');
		view.unmount();
		const ended = render(MkResonitePreview, { props: Ended.args });
		expect(ended.getByText('このセッションは終了しました')).toBeTruthy();
		expect(ended.queryByText('5/32人')).toBeNull();
		expect(ended.getByRole('link', { name: 'ワールドを開く' })).toBeTruthy();
	});
	test('unavailable and error cards retain a web link without stale details', () => {
		const view = render(MkResonitePreview, { props: Unavailable.args });
		expect(view.queryByText('Cozy Cave')).toBeNull();
		expect(view.getByRole('link', { name: 'Webで見る' }).getAttribute('href')).toBe(World.args.url);
		view.unmount();
		const failed = render(MkResonitePreview, { props: ErrorStory.args });
		expect(failed.getByText('情報を取得できませんでした')).toBeTruthy();
		expect(failed.getByRole('link', { name: 'Webで見る' })).toBeTruthy();
	});
	test('data saver and sensitivity suppress both the thumbnail and backdrop', () => {
		const saved = preferState.dataSaver;
		preferState.dataSaver = { urlPreviewThumbnail: true };
		try {
			const view = render(MkResonitePreview, { props: { ...World.args, summary: { ...World.args.summary, thumbnail: 'https://images.example/world.png' } } });
			expect(view.container.querySelectorAll('img[src="https://images.example/world.png"]')).toHaveLength(0);
			view.unmount();
		} finally { preferState.dataSaver = saved; }
		const sensitive = render(MkResonitePreview, { props: { ...World.args, summary: { ...World.args.summary, sensitive: true, thumbnail: 'https://images.example/world.png' } } });
		expect(sensitive.container.querySelectorAll('img[src="https://images.example/world.png"]')).toHaveLength(0);
	});
	test('missing counts stay absent and untrusted fallback URLs are ignored', () => {
		const view = render(MkResonitePreview, { props: { ...Session.args, summary: { ...Session.args.summary, resonite: { type: 'session', state: 'available', worldUrl: 'javascript:alert(1)' } } } });
		expect(view.queryByText('0人')).toBeNull();
		expect(view.getByRole('link', { name: 'Resoniteで参加' }).getAttribute('href')).toBe('ressession:///S-Example');
	});
});

describe('Resonite native links', () => {
	test('keeps readable colors and raises the brightness of dark colors', () => {
		expect(readableResoniteColor('#61d1fa')).toBe('#61d1fa');
		expect(readableResoniteColor('#000')).not.toBe('#000000');
		expect(readableResoniteColor('#ffffff00')).toMatch(/^#[a-f0-9]{6}$/);
		expect(readableResoniteColor('url(https://evil)')).toBeUndefined();
	});
	test('normalizes old API open links and custom session ids', () => {
		expect(getResoniteLink('https://api.resonite.com/open/session/S-U-Test%3AHeadless?source=share')).toEqual({ type: 'session', url: 'https://go.resonite.com/session/S-U-Test%3AHeadless', launchUrl: 'ressession:///S-U-Test:Headless' });
	});
	test.each(['https://go.resonite.com.evil/world/U-Test/R-test', 'https://user@go.resonite.com/world/U-Test/R-test', 'javascript:alert(1)', 'https://go.resonite.com/session/S-%2fother', 'https://go.resonite.com/world/U-Test/R-test/extra'])('does not create a native launch URL for %s', url => {
		expect(getResoniteLink(url)).toBeNull();
	});
});
