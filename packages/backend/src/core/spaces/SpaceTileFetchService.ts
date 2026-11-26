/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { createHash } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import * as Redis from 'ioredis';
import { DI } from '@/di-symbols.js';
import { bindThis } from '@/decorators.js';
import { HttpRequestService } from '@/core/HttpRequestService.js';

export type SpaceTileFetchResult = {
	status: number;
	contentType: string | null;
	text: string;
};

export const SPACE_TILE_FETCH_MAX_BYTES = 1024 * 1024;
const FETCH_TIMEOUT_MS = 10 * 1000;
const FETCH_MAX_REDIRECTS = 5;
const FETCH_CACHE_SECONDS = 30;

/** 読んでよい URL なら、その URL を返す。https で、ホスト名が許した先にあるものだけ。 */
export function parseSpaceTileFetchUrl(raw: string, allowedHosts: readonly string[]): URL | null {
	let url: URL;
	try {
		url = new URL(raw);
	} catch {
		return null;
	}
	if (url.protocol !== 'https:') return null;
	if (url.username !== '' || url.password !== '') return null;
	if (url.port !== '' && url.port !== '443') return null;
	if (!allowedHosts.includes(url.hostname.toLowerCase())) return null;
	return url;
}

/**
 * 自作タイルの `space.fetch` の代わりに、外部の URL を読む。
 * 読むのはサーバーなので、取得先には見ている人の IP も Cookie も渡らない。
 * Misskey のふつうの外向きの通信と同じ道を使うので、内側のアドレスには届かない。
 */
@Injectable()
export class SpaceTileFetchService {
	constructor(
		@Inject(DI.redis)
		private redisClient: Redis.Redis,

		private httpRequestService: HttpRequestService,
	) {
	}

	/**
	 * `allowedHosts` にある先だけを GET で読む。読めない URL なら null。
	 * リダイレクトは、移った先も許した先にあるときだけ追う。
	 */
	@bindThis
	public async fetch(rawUrl: string, allowedHosts: readonly string[]): Promise<SpaceTileFetchResult | null> {
		const first = parseSpaceTileFetchUrl(rawUrl, allowedHosts);
		if (first == null) return null;

		// 同じ URL を人数分取りに行かないよう、少しの間だけ覚えておく。
		// 許した先が違えば、リダイレクトをたどれる範囲も違う。別の許可で読んだ結果を返さないよう、許した先も鍵に含める
		const cacheKey = `spaceTileFetch:${createHash('sha256').update(JSON.stringify([first.href, [...allowedHosts].sort()])).digest('hex')}`;
		const cached = await this.redisClient.get(cacheKey);
		if (cached != null) {
			try {
				return JSON.parse(cached) as SpaceTileFetchResult;
			} catch {
				// 壊れていたら取り直す
			}
		}

		let url = first;
		for (let hop = 0; hop <= FETCH_MAX_REDIRECTS; hop++) {
			const res = await this.httpRequestService.send(url.href, {
				method: 'GET',
				headers: { Accept: 'application/json, text/*, */*' },
				timeout: FETCH_TIMEOUT_MS,
				size: SPACE_TILE_FETCH_MAX_BYTES,
				redirect: 'manual',
			}, { throwErrorWhenResponseNotOk: false });

			if (res.status >= 300 && res.status < 400 && res.headers.get('location') != null) {
				let next: URL | null;
				try {
					next = parseSpaceTileFetchUrl(new URL(res.headers.get('location')!, url).href, allowedHosts);
				} catch {
					next = null;
				}
				if (next == null) return null;
				url = next;
				continue;
			}

			const result: SpaceTileFetchResult = {
				status: res.status,
				contentType: res.headers.get('content-type'),
				text: await res.text(),
			};
			await this.redisClient.set(cacheKey, JSON.stringify(result), 'EX', FETCH_CACHE_SECONDS);
			return result;
		}
		return null;
	}
}
