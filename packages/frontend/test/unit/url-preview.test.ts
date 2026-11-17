/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, test, assert, beforeEach, afterEach, vi } from 'vitest';
import { render, cleanup, fireEvent, type RenderResult } from '@testing-library/vue';
import type { XriftPreview } from 'misskey-js';
import type { SummalyResult } from '@misskey-dev/summaly';
import { preferState } from '../setup.unit.js';
import { components } from '@/components/index.js';
import { directives } from '@/directives/index.js';
import MkUrlPreview from '@/components/MkUrlPreview.vue';
import { openImageLightbox } from '@/components/MkImageLightboxController';

vi.mock('@/components/MkImageLightboxController', () => ({
	openImageLightbox: vi.fn(),
}));

describe('MkUrlPreview', () => {
	beforeEach(() => {
		fetchMock.mockClear();
	});

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

	const renderAndOpenPreview = async (summary: Partial<SummalyResult> & { xrift?: XriftPreview }): Promise<HTMLIFrameElement | null> => {
		const mkUrlPreview = await renderPreviewBy(summary);
		const buttons = mkUrlPreview.getAllByRole('button');
		buttons[0].click();
		// Wait for the click event to be fired
		await Promise.resolve();

		return mkUrlPreview.container.querySelector('iframe');
	};

	afterEach(() => {
		fetchMock.resetMocks();
		vi.clearAllMocks();
		cleanup();
	});

	const catalystImageBase = 'https://citlali.natsuneko.com/r2/57dd6525-2f7d-4179-b01e-5265ec608e88/8f2c300f-cdf0-4ed8-9e67-bc54aa775007';

	test.each(['medium', 'tiny', 'original', 'blur', 'medium/', 'medium?download=1#image'])('Renders a Catalyst direct image (%s) without fetching a page preview', (variant) => {
		const url = `${catalystImageBase}/${variant}`;
		const result = render(MkUrlPreview, { props: { url }, global: { directives, components } });
		const image = result.getByRole('img') as HTMLImageElement;

		assert.strictEqual(image.src, url);
		assert.strictEqual(image.loading, 'lazy');
		assert.strictEqual(result.getByRole('link').getAttribute('href'), url);
		assert.strictEqual(fetchMock.mock.calls.length, 0);
	});

	test('Opens the linked image in the lightbox without changing its variant', async () => {
		const url = `${catalystImageBase}/blur`;
		const result = render(MkUrlPreview, { props: { url }, global: { directives, components } });
		const image = result.getByRole('img') as HTMLImageElement;

		await fireEvent.click(result.getByRole('button'));

		assert.deepEqual(vi.mocked(openImageLightbox).mock.calls, [[{ src: url, alt: image.alt }]]);
	});

	test('Keeps the original link when the direct image fails to load', async () => {
		const url = `${catalystImageBase}/medium`;
		const result = render(MkUrlPreview, { props: { url }, global: { directives, components } });

		await fireEvent.error(result.getByRole('img'));

		assert.isNull(result.queryByRole('img'));
		assert.isNull(result.queryByRole('button'));
		assert.strictEqual(result.getByRole('link').getAttribute('href'), url);
	});

	test('Does not load the direct image when URL preview thumbnails are disabled', () => {
		const originalDataSaver = preferState.dataSaver;
		preferState.dataSaver = { urlPreviewThumbnail: true };
		try {
			const url = `${catalystImageBase}/medium`;
			const result = render(MkUrlPreview, { props: { url }, global: { directives, components } });

			assert.isNull(result.queryByRole('img'));
			assert.isNull(result.queryByRole('button'));
			assert.strictEqual(result.getByRole('link').getAttribute('href'), url);
			assert.strictEqual(fetchMock.mock.calls.length, 0);
		} finally {
			preferState.dataSaver = originalDataSaver;
		}
	});

	test.each([
		`${catalystImageBase}/unknown`,
		`${catalystImageBase}/medium/extra`,
		'https://citlali.natsuneko.com/status/example',
		'https://example.local/r2/user/image/medium',
		'https://citlali.natsuneko.com.example.local/r2/user/image/medium',
	])('Uses the regular preview for other URLs (%s)', async (url) => {
		const result = await renderPreviewBy({ url, description: 'Regular preview' });

		result.getByText('Regular preview');
		assert.isNull(result.queryByRole('img'));
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
	test('recognizes marketplace item URLs as XRift cards', async () => {
		const preview = await renderPreviewBy({ ...xriftSummary, url: xriftSummary.url.replace('/world/', '/marketplace/'), xrift: { type: 'item', state: 'available', creator: 'Item creator', acquireCount: 15 } });
		preview.getByText('アイテム');
		assert.strictEqual(preview.getByRole('link').getAttribute('href'), xriftSummary.url.replace('/world/', '/marketplace/'));
	});

	test('hides sensitive XRift thumbnails', async () => {
		const preview = await renderPreviewBy({ ...xriftSummary, sensitive: true });
		assert.isNull(preview.queryByRole('img', { name: 'School world' }));
	});

	test.each(['world', 'instance', 'user'])('falls back to an ordinary %s card without XRift metadata', async type => {
		const url = xriftSummary.url!.replace('/world/', `/${type}/`);
		const preview = await renderPreviewBy({ url, title: 'XRift', description: 'Generic OGP' });
		preview.getByText('Generic OGP');
		assert.isNull(preview.queryByText('World creator'));
		assert.isFalse(preview.getByRole('article').hasAttribute('aria-busy'));
		preview.getByRole('heading', { level: 1, name: 'XRift' });
		assert.strictEqual(preview.getByRole('link').getAttribute('href'), url);
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
