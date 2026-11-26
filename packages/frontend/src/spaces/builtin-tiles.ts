/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import draw from './tiles/draw.js';
import image from './tiles/image.js';
import link from './tiles/link.js';
import memo from './tiles/memo.js';
import note from './tiles/note.js';
import poll from './tiles/poll.js';
import timer from './tiles/timer.js';
import todo from './tiles/todo.js';
import { i18n } from '@/i18n.js';

/** 本体が用意するタイル。 */
export type BuiltinTile = {
	kind: string;
	icon: string;
	/** 枠の中で動く HTML と JavaScript。null なら、枠ではなく本体が直接描く (Play だけ) */
	html: string | null;
	/** 一覧と見出しに出す名前 */
	name: string;
	/** タイルの中で `space.t(key)` で読む文言 */
	strings: Record<string, string>;
};

export function getBuiltinTiles(): BuiltinTile[] {
	const t = i18n.ts._spaces._tiles;
	return [
		{ kind: 'memo', icon: 'ti ti-note', html: memo, name: t._memo.name, strings: t._memo },
		{ kind: 'poll', icon: 'ti ti-chart-bar', html: poll, name: t._poll.name, strings: t._poll },
		{ kind: 'todo', icon: 'ti ti-checkbox', html: todo, name: t._todo.name, strings: t._todo },
		{ kind: 'timer', icon: 'ti ti-clock', html: timer, name: t._timer.name, strings: t._timer },
		{ kind: 'draw', icon: 'ti ti-brush', html: draw, name: t._draw.name, strings: t._draw },
		{ kind: 'image', icon: 'ti ti-photo', html: image, name: t._image.name, strings: t._image },
		{ kind: 'link', icon: 'ti ti-link', html: link, name: t._link.name, strings: t._link },
		{ kind: 'note', icon: 'ti ti-pencil', html: note, name: t._note.name, strings: t._note },
		{ kind: 'play', icon: 'ti ti-player-play', html: null, name: t._play.name, strings: t._play },
	];
}

export function getBuiltinTile(kind: string): BuiltinTile | null {
	return getBuiltinTiles().find(tile => tile.kind === kind) ?? null;
}
