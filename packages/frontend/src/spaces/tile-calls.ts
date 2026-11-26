/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type * as Misskey from 'misskey-js';
import { apiUrl } from '@@/js/config.js';
import { versatileLang } from '@@/js/intl-const.js';
import { chooseDriveFile } from '@/utility/drive.js';
import { misskeyApi } from '@/utility/misskey-api.js';

/** タイルが本体に読ませられる Misskey のデータ。ログインなしの立場で読むので、公開されているものだけが返る */
const PUBLIC_ENDPOINTS = ['notes/show', 'users/show', 'flash/show'];

/**
 * 枠から頼まれたことのうち、スペースの中でも試しの枠でも同じに動くもの。
 * 知らない頼みごとなら undefined を返す (呼ぶ側が、自分の分を足す)。
 */
export async function handleCommonTileCall(method: string, params: Record<string, unknown>): Promise<unknown> {
	switch (method) {
		case 'misskey': {
			if (typeof params.endpoint !== 'string' || !PUBLIC_ENDPOINTS.includes(params.endpoint)) throw new Error('endpoint not allowed');
			// 本人の立場では読まない。トークンを付けずに呼ぶ
			const res = await window.fetch(`${apiUrl}/${params.endpoint}`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(typeof params.params === 'object' && params.params != null ? params.params : {}),
				credentials: 'omit',
			});
			if (!res.ok) throw new Error('request failed');
			return await res.json();
		}
		case 'pickFile': {
			const [file] = await chooseDriveFile({ multiple: false });
			if (file == null) throw new Error('canceled');
			return { id: file.id, name: file.name, type: file.type, url: file.url, thumbnailUrl: file.thumbnailUrl };
		}
		case 'preview': {
			if (typeof params.url !== 'string' || !/^https?:\/\//.test(params.url)) throw new Error('invalid url');
			const res = await window.fetch(`/url?url=${encodeURIComponent(params.url)}&lang=${versatileLang}`);
			if (!res.ok) throw new Error('request failed');
			const info = await res.json() as { title?: string | null; description?: string | null; sitename?: string | null };
			return { title: info.title ?? null, description: info.description ?? null, sitename: info.sitename ?? null };
		}
		default:
			return undefined;
	}
}

const defCache = new Map<string, Promise<Misskey.entities.SpaceTileDef>>();

/**
 * 自作タイルの定義を、コードごと取る。同じ版 (ID と書き換えた時刻の組) は取り直さない。
 * `tileId` は、自分だけのタイルを、それが置いてあるスペースにいる人が読むときに要る。
 */
export function fetchTileDef(defId: string, updatedAt: string, tileId?: string): Promise<Misskey.entities.SpaceTileDef> {
	const key = `${defId}:${updatedAt}`;
	const cached = defCache.get(key);
	if (cached != null) return cached;
	const promise = misskeyApi('spaces/tile-defs/show', { defId, tileId });
	defCache.set(key, promise);
	// 取れなかったものは覚えない
	promise.catch(() => defCache.delete(key));
	return promise;
}
