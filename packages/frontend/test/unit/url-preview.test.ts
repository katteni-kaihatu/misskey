/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, test, assert, afterEach } from 'vitest';
import { render, cleanup, type RenderResult } from '@testing-library/vue';
import type { XriftPreview } from 'misskey-js';
import type { SummalyResult } from '@misskey-dev/summaly';
import { components } from '@/components/index.js';
import { directives } from '@/directives/index.js';
import MkUrlPreview from '@/components/MkUrlPreview.vue';
import { preferState } from '../setup.unit.js';

describe('MkUrlPreview', () => {
	const renderPreviewBy = async (summary: Partial<SummalyResult> & { xrift?: XriftPreview }): Promise<RenderResult> => {
		if (!summary.player) {
			summary.player = {
				url: null,
				width: null,
				height: null,
				allow: [],
			};
		}

		fetchMock.mockOnceIf((req) => {
			const url = new URL(req.url);
			return url.pathname === '/url';
		}, () => {
			return {
				status: 200,
				body: JSON.stringify(summary),
			};
		});

		const result = render(MkUrlPreview, {
			props: { url: summary.url! },
			global: { directives, components },
		});

		await new Promise<void>(resolve => {
			const observer = new MutationObserver(() => {
				resolve();
				observer.disconnect();
			});
			observer.observe(result.container, { childList: true, subtree: true });
		});

		return result;
	};

	const renderAndOpenPreview = async (summary: Partial<SummalyResult>): Promise<HTMLIFrameElement | null> => {
		const mkUrlPreview = await renderPreviewBy(summary);
		const buttons = mkUrlPreview.getAllByRole('button');
		buttons[0].click();
		// Wait for the click event to be fired
		await Promise.resolve();

		return mkUrlPreview.container.querySelector('iframe');
	};

	afterEach(() => {
		fetchMock.resetMocks();
		cleanup();
	});

	test('Should render the description', async () => {
		const mkUrlPreview = await renderPreviewBy({
			url: 'https://example.local',
			description: 'Mocked description',
		});
		mkUrlPreview.getByText('Mocked description');
	});

	const xriftSummary = {
		url: 'https://app.xrift.net/world/4b84ca2a-06cc-4351-a2df-adc904eec8e4',
		title: 'School world',
		description: 'An afternoon at school.',
		thumbnail: 'https://example.local/proxied-thumbnail.webp',
		icon: 'https://example.local/proxied-icon.webp',
		sitename: 'XRift',
		xrift: { type: 'world', state: 'available', creator: 'World creator' } as XriftPreview,
	};

	test('renders an XRift world card with its creator and proxied thumbnail', async () => {
		const preview = await renderPreviewBy({ ...xriftSummary });
		preview.getByText('School world');
		preview.getByText('World creator');
		preview.getByText('An afternoon at school.');
		assert.strictEqual(preview.getByRole('img', { name: 'School world' }).getAttribute('src'), xriftSummary.thumbnail);
		const link = preview.getByRole('link');
		assert.strictEqual(link.getAttribute('href'), xriftSummary.url);
		assert.strictEqual(link.getAttribute('target'), '_blank');
		assert.isNull(preview.container.querySelector('iframe'));
	});

	test('hides XRift thumbnails when data saver is enabled', async () => {
		const dataSaver = preferState.dataSaver;
		try {
			preferState.dataSaver = { urlPreviewThumbnail: true };
			const preview = await renderPreviewBy({ ...xriftSummary });
			assert.isNull(preview.queryByRole('img', { name: 'School world' }));
			preview.getByText('World creator');
		} finally {
			preferState.dataSaver = dataSaver;
		}
	});
	test('revalidates XRift metadata instead of reusing an old browser-cached list', async () => {
		await renderPreviewBy({ ...xriftSummary });
		const request = fetchMock.mock.calls.find(([url]) => String(url).startsWith('/url?'));
		assert.strictEqual(request?.[1]?.cache, 'no-cache');
	});

	test('hides sensitive XRift thumbnails', async () => {
		const preview = await renderPreviewBy({ ...xriftSummary, sensitive: true });
		assert.isNull(preview.queryByRole('img', { name: 'School world' }));
	});

	test('falls back to an ordinary card without XRift metadata', async () => {
		const preview = await renderPreviewBy({ url: xriftSummary.url, title: 'XRift', description: 'Generic OGP' });
		preview.getByText('Generic OGP');
		assert.isNull(preview.queryByText('World creator'));
		assert.strictEqual(preview.getByRole('link').getAttribute('href'), xriftSummary.url);
	});

	test('Having a player should render a button', async () => {
		const mkUrlPreview = await renderPreviewBy({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: null,
				height: null,
				allow: [],
			},
		});
		const buttons = mkUrlPreview.getAllByRole('button');
		assert.strictEqual(buttons.length, 2, 'two buttons');
	});

	test('Having a player should setup the iframe', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: null,
				height: null,
				allow: [],
			},
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.src, 'https://example.local/player?autoplay=1&auto_play=1');
		assert.strictEqual(
			iframe?.sandbox.toString(),
			'allow-popups allow-popups-to-escape-sandbox allow-scripts allow-storage-access-by-user-activation allow-same-origin',
		);
	});

	test('Having a player with `allow` field should set permissions', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: null,
				height: null,
				allow: ['fullscreen', 'web-share'],
			},
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.allow, 'fullscreen;web-share');
	});

	test('A Summaly proxy response without allow falls back to the default', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: null,
				height: null,
				allow: undefined as any,
			},
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.allow, 'autoplay;encrypted-media;fullscreen');
	});

	test('Filtering the allow list from the Summaly proxy', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: null,
				height: null,
				allow: ['autoplay', 'camera', 'fullscreen'],
			},
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.allow, 'autoplay;fullscreen');
	});

	test('Having a player width should keep the fixed aspect ratio', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: 400,
				height: 200,
				allow: [],
			},
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.parentElement?.style.paddingTop, '50%');
	});

	test('Having a player width should keep the fixed height', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://example.local',
			player: {
				url: 'https://example.local/player',
				width: null,
				height: 200,
				allow: [],
			},
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.parentElement?.style.paddingTop, '200px');
	});

	test('Loading a tweet in iframe', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://twitter.com/i/web/status/1685072521782325249',
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.getAttribute('allow'), 'fullscreen;web-share');
		assert.strictEqual(iframe?.getAttribute('sandbox'), 'allow-popups allow-popups-to-escape-sandbox allow-scripts allow-same-origin');
	});

	test('Loading a post in iframe', async () => {
		const iframe = await renderAndOpenPreview({
			url: 'https://x.com/i/web/status/1685072521782325249',
		});
		assert.exists(iframe, 'iframe should exist');
		assert.strictEqual(iframe?.getAttribute('allow'), 'fullscreen;web-share');
		assert.strictEqual(iframe?.getAttribute('sandbox'), 'allow-popups allow-popups-to-escape-sandbox allow-scripts allow-same-origin');
	});
});
