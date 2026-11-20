/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable, OnApplicationShutdown } from '@nestjs/common';
import type { SummalyResult } from '@misskey-dev/summaly';
import { DI } from '@/di-symbols.js';
import type { Config } from '@/config.js';
import { HttpRequestService } from '@/core/HttpRequestService.js';
import type Logger from '@/logger.js';
import { deepClone } from '@/misc/clone.js';
import { query } from '@/misc/prelude/url.js';
import { MemoryKVCache } from '@/misc/cache.js';
import { StatusError } from '@/misc/status-error.js';
import { LoggerService } from '@/core/LoggerService.js';
import { UtilityService } from '@/core/UtilityService.js';
import { bindThis } from '@/decorators.js';
import { ApiError } from '@/server/api/error.js';
import { MiMeta } from '@/models/Meta.js';
import type { FastifyRequest, FastifyReply } from 'fastify';
import { createHash } from 'node:crypto';
import { fetchXriftSummary, getXriftResource, xriftImageUrl } from './xrift.js';
import type { XriftSummary } from './xrift.js';

@Injectable()
export class UrlPreviewService implements OnApplicationShutdown {
	private logger: Logger;
	private summaryCache: MemoryKVCache<SummalyResult>;
	private xriftSummaryCache = new MemoryKVCache<XriftSummary | null>(1000 * 60 * 5, 100);
	private xriftInFlight = new Map<string, Promise<XriftSummary | null>>();
	private xriftRateLimit: { keyVersion: string; until: number } | null = null;
	private readonly summalyDefaultUserAgent: string;

	constructor(
		@Inject(DI.config)
		private config: Config,

		@Inject(DI.meta)
		private meta: MiMeta,

		private httpRequestService: HttpRequestService,
		private utilityService: UtilityService,
		private loggerService: LoggerService,
	) {
		this.logger = this.loggerService.getLogger('url-preview');
		this.summaryCache = new MemoryKVCache<SummalyResult>(1000 * 60 * 60, 100); // 1h, 100件
		this.summalyDefaultUserAgent = `SummalyBot/${_SUMMALY_VERSION_} (${this.config.url}; +https://github.com/misskey-dev/summaly/blob/master/README.md)`;
	}

	@bindThis
	private wrap(url?: string | null): string | null {
		return url != null
			? `${this.config.mediaProxy}/preview.webp?${query({
				url,
				preview: '1',
			})}`
			: null;
	}

	@bindThis
	public async handle(
		request: FastifyRequest<{ Querystring: { url: string; lang?: string; } }>,
		reply: FastifyReply,
	): Promise<object | undefined> {
		const url = request.query.url;
		if (typeof url !== 'string') {
			reply.code(400);
			return;
		}

		const lang = request.query.lang;
		if (Array.isArray(lang)) {
			reply.code(400);
			return;
		}

		if (!this.meta.urlPreviewEnabled) {
			reply.code(403);
			return {
				error: new ApiError({
					message: 'URL preview is disabled',
					code: 'URL_PREVIEW_DISABLED',
					id: '58b36e13-d2f5-0323-b0c6-76aa9dabefb8',
				}),
			};
		}

		this.logger.info(this.meta.urlPreviewSummaryProxyUrl
			? `(Proxy) Getting preview of ${url}@${lang} ...`
			: `Getting preview of ${url}@${lang} ...`);

		try {
			const apiKey = this.meta.xriftApiKey;
			const resource = getXriftResource(url);
			let xrift: XriftSummary | null | undefined;
			if (resource && apiKey) {
				const keyVersion = createHash('sha256').update(apiKey).digest('hex');
				const cacheKey = `${resource.url}@${keyVersion}`;
				try {
					xrift = await this.xriftSummaryCache.fetchMaybe(cacheKey, () => {
						const pending = this.xriftInFlight.get(cacheKey);
						if (pending) return pending;
						const request = fetchXriftSummary(resource.url, apiKey, (apiUrl, headers) => this.fetchXriftJson(apiUrl, headers, keyVersion))
							.then(async result => {
								if (result?.xrift.state !== 'available') return result;
								// Public API does not promise world thumbnails. Only reuse the
								// OGP image, never its title or arbitrary provider metadata.
								const thumbnailFor = async (worldUrl: string): Promise<string | null> => {
									try {
										const ogp = await this.summaryCache.fetchMaybe(`${worldUrl}@_DEFAULT_`, () => this.meta.urlPreviewSummaryProxyUrl
											? this.fetchSummaryFromProxy(worldUrl) : this.fetchSummary(worldUrl));
										return xriftImageUrl(ogp?.thumbnail);
									} catch { return null; }
								};
								await Promise.all([
									result.xrift.worldUrl && !result.thumbnail ? thumbnailFor(result.xrift.worldUrl).then(image => { result.thumbnail = image; }) : null,
									// Bound extra HTML requests when a profile has many worlds.
									...(result.xrift.worlds ?? []).slice(0, 6).map(async world => { world.thumbnail ??= await thumbnailFor(world.url); }),
								]);
								return result;
							})
							.catch(() => {
								this.logger.warn('Failed to get XRift preview');
								return null;
							})
							.finally(() => this.xriftInFlight.delete(cacheKey));
						this.xriftInFlight.set(cacheKey, request);
						return request;
					});
				} catch {
					this.logger.warn('Failed to get XRift preview');
				}
			}
			const fetcher = async () => {
				const result = await (
					this.meta.urlPreviewSummaryProxyUrl
					? this.fetchSummaryFromProxy(url, lang)
					: this.fetchSummary(url, lang)
				);

				if (!result.url.startsWith('http://') && !result.url.startsWith('https://')) {
					return undefined;
				}

				if (result.player.url && !result.player.url.startsWith('http://') && !result.player.url.startsWith('https://')) {
					return undefined;
				}

				return result;
			};

			const summary = deepClone(xrift ?? await this.summaryCache.fetchMaybe(`${url}@${lang ?? '_DEFAULT_'}`, fetcher));

			if (summary == null) {
				throw new Error('Invalid summary');
			}

			this.logger.succ(`Got preview of ${url}: ${summary.title}`);

			summary.icon = this.wrap(summary.icon);
			summary.thumbnail = this.wrap(summary.thumbnail);
			if (xrift && 'xrift' in summary) {
				for (const world of (summary as XriftSummary).xrift.worlds ?? []) world.thumbnail = this.wrap(world.thumbnail);
				const preview = (summary as XriftSummary).xrift;
				if (preview.participantAvatars) preview.participantAvatars = preview.participantAvatars.map(avatar => this.wrap(avatar));
			}

			if (summary.sensitive !== true) {
				summary.sensitive = this.utilityService.isKeyWordIncluded(summary.url, this.meta.urlPreviewSensitiveList);
			}

			reply.header('Cache-Control', resource ? 'max-age=300' : 'max-age=86400, immutable');

			return summary;
		} catch (err) {
			this.logger.warn(`Failed to get preview of ${url}: ${err}`);

			reply.code(422);
			reply.header('Cache-Control', 'max-age=86400, immutable');
			return {
				error: new ApiError({
					message: 'Failed to get preview',
					code: 'URL_PREVIEW_FAILED',
					id: '09d01cb5-53b9-4856-82e5-38a50c290a3b',
				}),
			};
		}
	}

	private async fetchXriftJson(url: string, headers: Record<string, string>, keyVersion: string): Promise<unknown> {
		if (this.xriftRateLimit?.keyVersion === keyVersion && this.xriftRateLimit.until > Date.now()) {
			throw new StatusError('XRift rate limit', 429);
		}
		const response = await this.httpRequestService.send(url, {
			method: 'GET', headers: { Accept: 'application/json', ...headers }, timeout: 5000, size: 1024 * 256, redirect: 'error',
		}, { throwErrorWhenResponseNotOk: false, validators: [] });
		if (response.status === 429) {
			const reset = Number(response.headers.get('X-RateLimit-Reset')) * 1000;
			this.xriftRateLimit = { keyVersion, until: reset > Date.now() && Number.isFinite(reset) ? reset : Date.now() + 60 * 60 * 1000 };
		}
		if (!response.ok) {
			await response.text().catch(() => undefined);
			throw new StatusError('XRift request failed', response.status);
		}
		return response.json();
	}

	@bindThis
	private async fetchSummary(url: string, lang?: string): Promise<SummalyResult> {
		const { summaly } = await import('@misskey-dev/summaly');

		return summaly(url, {
			followRedirects: this.meta.urlPreviewAllowRedirect,
			lang: lang ?? 'ja-JP',
			agent: {
				http: this.httpRequestService.httpAgent,
				https: this.httpRequestService.httpsAgent,
			},
			userAgent: this.meta.urlPreviewUserAgent ?? this.summalyDefaultUserAgent,
			operationTimeout: this.meta.urlPreviewTimeout,
			contentLengthLimit: this.meta.urlPreviewMaximumContentLength,
			contentLengthRequired: this.meta.urlPreviewRequireContentLength,
		});
	}

	@bindThis
	private fetchSummaryFromProxy(url: string, lang?: string): Promise<SummalyResult> {
		const proxy = this.meta.urlPreviewSummaryProxyUrl!;
		const queryStr = query({
			url: url,
			lang: lang ?? 'ja-JP',
			followRedirects: this.meta.urlPreviewAllowRedirect,
			userAgent: this.meta.urlPreviewUserAgent ?? this.summalyDefaultUserAgent,
			operationTimeout: this.meta.urlPreviewTimeout,
			contentLengthLimit: this.meta.urlPreviewMaximumContentLength,
			contentLengthRequired: this.meta.urlPreviewRequireContentLength,
		});

		return this.httpRequestService.getJson<SummalyResult>(`${proxy}?${queryStr}`, 'application/json, */*', undefined, true);
	}

	@bindThis
	public dispose(): void {
		this.summaryCache.dispose();
		this.xriftSummaryCache.dispose();
	}

	@bindThis
	public onApplicationShutdown(): void {
		this.dispose();
	}
}
