<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div class="_gaps_s">
	<div v-for="person in people" :key="person.user.id" :class="$style.person" class="_panel">
		<div :class="$style.who"><i class="ti ti-user"></i> {{ person.user.name }}</div>
		<MkSpaceTileFrame
			:ref="(el) => setFrame(person.user.id, el)"
			:html="code"
			:init="person.init"
			:title="person.user.name"
			:call="handleCall"
			@setShared="(key, value) => onSetShared(person.user.id, key, value)"
			@signal="(type, body) => onSignal(person.user.id, type, body)"
			@ready="onReady(person.user.id)"
		/>
	</div>
	<div :class="$style.caption">{{ i18n.ts._spaces._tileEditor.previewCaption }}</div>
</div>
</template>

<script lang="ts" setup>
import { url as localUrl } from '@@/js/config.js';
import type { HostToTileMessage, TileInit, TileUser } from '@/spaces/tile-frame.js';
import MkSpaceTileFrame from '@/components/MkSpaceTileFrame.vue';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { handleCommonTileCall } from '@/spaces/tile-calls.js';
import { toTileUser } from '@/spaces/tile-frame.js';

/**
 * 自作タイルを、スペースにつながずに試しに動かす。
 * 共有する値と知らせは、この部品の中だけで回す。2人にすると、枠を2つ並べて、片方の操作がもう片方に届くことを確かめられる。
 * コードを変えて動かし直すときは、親が key を変えて、この部品ごと作り直す。
 */

const props = defineProps<{
	/** タイルの HTML と JavaScript */
	code: string;
	/** 保存してあるタイルの ID。`space.fetch` を試すのに要る。まだ保存していなければ null */
	defId?: string | null;
	/** 2人で試すか */
	twoPeople?: boolean;
}>();

type FrameHandle = { send: (message: HostToTileMessage) => void };

const me: TileUser = $i != null ? toTileUser($i) : { id: 'preview-me', name: 'me', username: 'me', avatarUrl: null };
const guest: TileUser = { id: 'preview-guest', name: i18n.ts._spaces._tileEditor.guest, username: 'guest', avatarUrl: null };
const users = props.twoPeople ? [me, guest] : [me];

function initFor(user: TileUser): TileInit {
	return {
		shared: {},
		mine: {},
		me: user,
		members: users,
		// 1人目をホストで担当とする
		isHost: user.id === me.id,
		isLeader: user.id === me.id,
		hostOnly: false,
		origin: localUrl,
		strings: {},
	};
}

const people = users.map(user => ({ user, init: initFor(user) }));
const frames = new Map<string, FrameHandle>();

function setFrame(userId: string, el: unknown): void {
	if (el == null) frames.delete(userId); else frames.set(userId, el as FrameHandle);
}

/** 共有する値のいま。あとからつながった枠に渡すために持っておく */
const shared = new Map<string, unknown>();

/** 枠がつながった。それまでに書かれた値を渡す */
function onReady(userId: string): void {
	for (const [key, value] of shared) frames.get(userId)?.send({ t: 'shared', key, value, userId: '' });
}

/** 共有する値。書いた本人の枠はもう値を持っているので、ほかの枠にだけ伝える */
function onSetShared(userId: string, key: string, value: unknown): void {
	if (value == null) shared.delete(key); else shared.set(key, value);
	for (const [otherId, frame] of frames) {
		if (otherId !== userId) frame.send({ t: 'shared', key, value, userId });
	}
}

/** 保存しない知らせ。スペースの中と同じく、送った本人にも届く */
function onSignal(userId: string, type: string, body: unknown): void {
	for (const frame of frames.values()) frame.send({ t: 'signal', type, body, userId });
}

async function handleCall(method: string, params: Record<string, unknown>): Promise<unknown> {
	if (method === 'fetch') {
		if (typeof params.url !== 'string') throw new Error('invalid url');
		// 読みに行く先は、保存してある宣言で確かめる。保存する前は試せない
		if (props.defId == null) throw new Error(i18n.ts._spaces._tileEditor.fetchNeedsSave);
		return await misskeyApi('spaces/tiles/fetch', { defId: props.defId, url: params.url });
	}
	const result = await handleCommonTileCall(method, params);
	if (result === undefined) throw new Error('unknown method');
	return result;
}
</script>

<style lang="scss" module>
.person {
	overflow: hidden;
	border: solid 1px var(--MI_THEME-divider);
}

.who {
	padding: 6px 12px;
	border-bottom: solid 1px var(--MI_THEME-divider);
	font-size: 0.85em;
	font-weight: bold;
}

.caption {
	font-size: 0.85em;
	opacity: 0.7;
}
</style>
