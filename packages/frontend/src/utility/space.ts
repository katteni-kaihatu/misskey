/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type * as Misskey from 'misskey-js';
import { url as localUrl } from '@@/js/config.js';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { misskeyApi } from '@/utility/misskey-api.js';

const SPACE_CACHE_MS = 30 * 1000;
const spaceCache = new Map<string, { fetchedAt: number; promise: Promise<Misskey.entities.Space> }>();

/** 自分のサーバーの `/spaces/{id}` の形をした URL なら、スペースの ID を返す。 */
export function parseSpaceUrl(target: string): string | null {
	let parsed: URL;
	try {
		parsed = new URL(target);
	} catch {
		return null;
	}
	if (parsed.origin !== localUrl) return null;
	const matched = /^\/spaces\/([a-z0-9]+)\/?$/.exec(parsed.pathname);
	return matched?.[1] ?? null;
}

/** スペースを取る。同じスペースを何度も問い合わせないよう、ID ごとに少しの間覚えておく。 */
export function fetchSpaceCached(spaceId: string): Promise<Misskey.entities.Space> {
	const cached = spaceCache.get(spaceId);
	if (cached != null && Date.now() - cached.fetchedAt < SPACE_CACHE_MS) return cached.promise;
	const promise = misskeyApi('spaces/show', { spaceId });
	spaceCache.set(spaceId, { fetchedAt: Date.now(), promise });
	promise.catch(() => {
		if (spaceCache.get(spaceId)?.promise === promise) spaceCache.delete(spaceId);
	});
	return promise;
}

/** 「スペースをひらく」の入力を出して、作る。作ったスペースを返す。やめたら null。 */
export async function openSpaceCreateDialog(): Promise<Misskey.entities.Space | null> {
	if ($i == null) return null;

	const { canceled, result } = await os.form(i18n.ts._spaces.open, {
		name: {
			type: 'string',
			label: i18n.ts._spaces.name,
			default: i18n.tsx._spaces.defaultName({ name: $i.name ?? $i.username }),
			required: true,
		},
		access: {
			type: 'enum',
			label: i18n.ts._spaces.access,
			default: 'local',
			enum: [
				{ label: i18n.ts._spaces.accessLocal, value: 'local' },
				{ label: i18n.ts._spaces.accessFollowers, value: 'followers' },
			],
		},
		noteScope: {
			type: 'enum',
			label: i18n.ts._spaces.noteScope,
			default: 'local',
			enum: [
				{ label: i18n.ts._spaces.noteScopeLocal, value: 'local' },
				{ label: i18n.ts._spaces.noteScopePublic, value: 'public' },
				{ label: i18n.ts._spaces.noteScopeNone, value: 'none' },
			],
		},
	});
	if (canceled) return null;

	const name = (result.name ?? '').trim().slice(0, 128);
	if (name === '') return null;

	try {
		return await misskeyApi('spaces/create', {
			name,
			access: result.access as Misskey.entities.Space['access'],
			noteScope: result.noteScope as Misskey.entities.Space['noteScope'],
		});
	} catch (err) {
		const code = (err as { code?: string }).code;
		os.alert({
			type: 'error',
			text: code === 'ALREADY_OPEN' ? i18n.ts._spaces.alreadyOpen : i18n.ts.somethingHappened,
		});
		return null;
	}
}
