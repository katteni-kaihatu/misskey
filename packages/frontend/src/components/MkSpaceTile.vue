<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<section :class="$style.root" class="_panel" :aria-label="title">
	<header :class="$style.header">
		<i :class="[definition?.icon ?? 'ti ti-puzzle', $style.icon]"></i>
		<span :class="$style.name">{{ title }}<span v-if="author != null" :class="$style.author">@{{ author }}</span></span>
		<button v-if="hostControls" class="_button" :class="[$style.remove, { [$style.active]: tile.hostOnly }]" :aria-label="tile.hostOnly ? i18n.ts._spaces.tileHostOnlyOff : i18n.ts._spaces.tileHostOnlyOn" :title="tile.hostOnly ? i18n.ts._spaces.tileHostOnlyOff : i18n.ts._spaces.tileHostOnlyOn" :aria-pressed="tile.hostOnly" @click="toggleHostOnly">
			<i :class="tile.hostOnly ? 'ti ti-lock' : 'ti ti-lock-open'"></i>
		</button>
		<i v-else-if="tile.hostOnly" class="ti ti-lock" :class="$style.icon" role="img" :title="i18n.ts._spaces.tileHostOnly" :aria-label="i18n.ts._spaces.tileHostOnly"></i>
		<button v-if="expandable" class="_button" :class="$style.remove" :aria-label="expanded ? i18n.ts._spaces.shrinkTile : i18n.ts._spaces.expandTile" :title="expanded ? i18n.ts._spaces.shrinkTile : i18n.ts._spaces.expandTile" @click="emit('expand')">
			<i :class="expanded ? 'ti ti-arrows-minimize' : 'ti ti-arrows-maximize'"></i>
		</button>
		<button v-if="removable" class="_button" :class="$style.remove" :aria-label="i18n.ts._spaces.removeTile" :title="i18n.ts._spaces.removeTile" @click="emit('remove')">
			<i class="ti ti-x"></i>
		</button>
	</header>
	<!-- 作者があとから読みに行く先を足しても、許し直すまでは読めない。許せるのは、置いた本人とホスト -->
	<div v-if="pendingHosts.length > 0 && removable" :class="$style.notice">
		<div :class="$style.noticeText">{{ i18n.ts._spaces.tileFetchPending }}<br><code>{{ pendingHosts.join(', ') }}</code></div>
		<MkButton small @click="allowHosts">{{ i18n.ts._spaces.tileFetchAllowNow }}</MkButton>
	</div>
	<!-- Play だけは、枠ではなく本体が直接描く。Play は AiScript で動き、Misskey の部品で描くため -->
	<div v-if="definition != null && definition.html == null">
		<MkFlashPlayer v-if="flashId != null" :flashId="flashId"/>
		<div v-else-if="isLocked()" :class="$style.unknown">{{ i18n.ts._spaces.tileHostOnly }}</div>
		<form v-else :class="$style.playForm" @submit.prevent="setFlash">
			<MkInput v-model="flashInput" :class="$style.playInput" :placeholder="i18n.ts._spaces._tiles._play.placeholder" :aria-label="i18n.ts._spaces._tiles._play.placeholder"/>
			<MkButton primary type="submit">{{ i18n.ts._spaces._tiles._play.set }}</MkButton>
		</form>
	</div>
	<MkSpaceTileFrame
		v-else-if="frameSource != null"
		ref="frame"
		:html="frameSource.html"
		:init="frameSource.init"
		:title="title"
		:expanded="expanded"
		:call="handleCall"
		@setShared="onSetShared"
		@setMine="writeMine"
		@signal="onSignal"
		@ready="onReady"
	/>
	<MkLoading v-else-if="loading"/>
	<div v-else :class="$style.unknown">{{ message }}</div>
</section>
</template>

<script lang="ts" setup>
import { computed, onBeforeUnmount, ref, shallowRef, useTemplateRef, watch } from 'vue';
import type * as Misskey from 'misskey-js';
import { url as localUrl } from '@@/js/config.js';
import MkButton from '@/components/MkButton.vue';
import MkInput from '@/components/MkInput.vue';
import MkFlashPlayer from '@/components/MkFlashPlayer.vue';
import MkSpaceTileFrame from '@/components/MkSpaceTileFrame.vue';
import { misskeyApi } from '@/utility/misskey-api.js';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { miLocalStorage } from '@/local-storage.js';
import { getBuiltinTile } from '@/spaces/builtin-tiles.js';
import { fetchTileDef, handleCommonTileCall } from '@/spaces/tile-calls.js';
import { toTileUser } from '@/spaces/tile-frame.js';
import type { HostToTileMessage, TileInit } from '@/spaces/tile-frame.js';
import { getSpaceShared, onSpaceTileEvent, sendSpaceSignal, setSpaceShared, spaceSession as session } from '@/utility/space-session.js';

const props = defineProps<{
	tile: Misskey.entities.SpaceTile;
	/** 片づけるボタンを出すか */
	removable?: boolean;
	/** 「大きく出す」のボタンを出すか */
	expandable?: boolean;
	/** いま大きく出しているか */
	expanded?: boolean;
	/** 「ホストだけが操作できる」の切り替えを出すか (自分がホストか) */
	hostControls?: boolean;
}>();

const emit = defineEmits<{
	(ev: 'remove'): void;
	(ev: 'expand'): void;
}>();

const frame = useTemplateRef('frame');
const definition = computed(() => getBuiltinTile(props.tile.kind));
let offTileEvent: (() => void) | null = null;

/** 枠に入れるもの。きほんのタイルはすぐ決まる。自作タイルは、コードを取ってから決まる */
const frameSource = shallowRef<{ html: string; init: TileInit } | null>(null);
const loading = ref(false);
const message = ref(i18n.ts._spaces.unknownTile);
const author = ref<string | null>(null);
const title = computed(() => definition.value?.name ?? props.tile.def?.name ?? props.tile.kind);

/** タイルが読みに行くと宣言している先のうち、まだ許されていないもの */
const pendingHosts = computed(() => (props.tile.def?.fetchHosts ?? []).filter(host => !props.tile.allowedHosts.includes(host)));

async function allowHosts(): Promise<void> {
	const hosts = props.tile.def?.fetchHosts ?? [];
	const { canceled } = await os.confirm({ type: 'question', title: i18n.ts._spaces.tileFetchConfirm, text: hosts.join('\n') });
	if (canceled) return;
	await os.apiWithDialog('spaces/tiles/update', { tileId: props.tile.id, allowedHosts: hosts });
}

async function toggleHostOnly(): Promise<void> {
	await os.apiWithDialog('spaces/tiles/update', { tileId: props.tile.id, hostOnly: !props.tile.hostOnly });
}

/** 自分だけの値の保存先。アカウントを切り替えても混ざらないよう、アカウントごとに分ける */
const mineKey = `spaceTileMine:${$i?.id ?? ''}:${props.tile.id}` as const;

function readMine(): Record<string, unknown> {
	try {
		const raw = miLocalStorage.getItem(mineKey);
		const parsed: unknown = raw == null ? {} : JSON.parse(raw);
		return (typeof parsed === 'object' && parsed != null && !Array.isArray(parsed)) ? parsed as Record<string, unknown> : {};
	} catch {
		return {};
	}
}

function writeMine(key: string, value: unknown): void {
	const mine = readMine();
	if (value == null) delete mine[key]; else mine[key] = value;
	miLocalStorage.setItem(mineKey, JSON.stringify(mine));
}

/** 枠に最初に埋め込んだ共有の値。枠が読み込まれたあと、いまの値との差を伝えるのに使う */
let embeddedShared: Record<string, unknown> = {};

/**
 * 枠に入れるものを決める。タイルごとに1回だけ。そのあとの変化は通信路で伝える。
 * いる人が変わるたびに組み立て直すと枠が読み直されて、書いている途中のものが消えるので、ここでは変化を追わない。
 */
function prepareFrame(html: string, strings: Record<string, string>): void {
	if ($i == null) return;
	embeddedShared = getSpaceShared(props.tile.id);
	frameSource.value = {
		html,
		init: {
			shared: embeddedShared,
			mine: readMine(),
			me: toTileUser($i),
			members: session.members.map(member => toTileUser(member.user)),
			isHost: session.space?.hostId === $i.id,
			isLeader: session.leaderId === $i.id,
			hostOnly: props.tile.hostOnly,
			origin: localUrl,
			strings,
		},
	};
}

if (definition.value != null) {
	if (definition.value.html != null) prepareFrame(definition.value.html, definition.value.strings);
} else if (props.tile.def != null) {
	// 自作タイル。コードは定義から取る。同じ版は取り直さない
	loading.value = true;
	fetchTileDef(props.tile.def.id, props.tile.def.updatedAt, props.tile.id).then(def => {
		author.value = def.user.username;
		if (def.code != null) prepareFrame(def.code, {});
	}).catch(() => {
		message.value = i18n.ts._spaces.tileLoadFailed;
	}).finally(() => {
		loading.value = false;
	});
} else if (props.tile.kind === 'custom') {
	message.value = i18n.ts._spaces.deletedTile;
}

function send(msg: HostToTileMessage): void {
	frame.value?.send(msg);
}

/** 枠から頼まれたことを、本体がやる。枠には結果だけを返す。 */
async function handleCall(method: string, params: Record<string, unknown>): Promise<unknown> {
	if (method === 'fetch') {
		if (typeof params.url !== 'string') throw new Error('invalid url');
		// 読みに行くのはサーバー。許した先かどうかも、サーバーが確かめる
		return await misskeyApi('spaces/tiles/fetch', { tileId: props.tile.id, url: params.url });
	}
	const result = await handleCommonTileCall(method, params);
	if (result === undefined) throw new Error('unknown method');
	return result;
}

/** 「ホストだけが操作できる」タイルで、自分がホストでないか */
function isLocked(): boolean {
	return props.tile.hostOnly && session.space?.hostId !== $i?.id;
}

function onSetShared(key: string, value: unknown): void {
	if (isLocked()) {
		// サーバーは受け取らない。枠は先に自分の値を変えているので、いまの値を送り返して元に戻す
		send({ t: 'shared', key, value: getSpaceShared(props.tile.id)[key] ?? null, userId: '' });
		return;
	}
	setSpaceShared(props.tile.id, key, value);
}

function onSignal(type: string, body: unknown): void {
	if (!isLocked()) sendSpaceSignal(props.tile.id, type, body);
}

/** 枠が読み込まれて、通信路がつながった。ページを移って戻り、枠が読み直されたときもここを通る */
function onReady(): void {
	offTileEvent?.();
	offTileEvent = onSpaceTileEvent(props.tile.id, {
		shared: (key, value, userId) => send({ t: 'shared', key, value, userId }),
		signal: (type, body, userId) => send({ t: 'signal', type, body, userId }),
	});
	// 枠を組み立ててから読み込まれるまでの間に変わった値を伝える
	const current = getSpaceShared(props.tile.id);
	for (const key of new Set([...Object.keys(embeddedShared), ...Object.keys(current)])) {
		if (JSON.stringify(embeddedShared[key] ?? null) !== JSON.stringify(current[key] ?? null)) send({ t: 'shared', key, value: current[key] ?? null, userId: '' });
	}
	send({ t: 'members', members: session.members.map(member => toTileUser(member.user)) });
	send({ t: 'leader', isLeader: session.leaderId === $i?.id });
	send({ t: 'hostOnly', hostOnly: props.tile.hostOnly });
}

watch(() => session.leaderId, (leaderId) => {
	send({ t: 'leader', isLeader: leaderId === $i?.id });
});

watch(() => props.tile.hostOnly, (hostOnly) => {
	send({ t: 'hostOnly', hostOnly });
});

// ---- Play のタイル (本体が直接描く) ----

const flashId = ref<string | null>(null);
const flashInput = ref('');
let offPlayEvent: (() => void) | null = null;

if (props.tile.kind === 'play') {
	const current = getSpaceShared(props.tile.id).flashId;
	flashId.value = typeof current === 'string' ? current : null;
	offPlayEvent = onSpaceTileEvent(props.tile.id, {
		shared: (key, value) => {
			if (key === 'flashId') flashId.value = typeof value === 'string' ? value : null;
		},
		signal: () => undefined,
	});
}

/** 置く Play を決める。URL でも ID でも受ける。 */
function setFlash(): void {
	if (isLocked()) return;
	const value = flashInput.value.trim();
	const id = /\/play\/([a-zA-Z0-9]+)/.exec(value)?.[1] ?? value;
	if (!/^[a-zA-Z0-9]{1,64}$/.test(id)) return;
	setSpaceShared(props.tile.id, 'flashId', id);
	flashId.value = id;
}

watch(() => session.members, (members) => {
	send({ t: 'members', members: members.map(member => toTileUser(member.user)) });
});

onBeforeUnmount(() => {
	offTileEvent?.();
	offPlayEvent?.();
});
</script>

<style lang="scss" module>
.root {
	overflow: hidden;
	border: solid 1px var(--MI_THEME-divider);
}

.header {
	display: flex;
	align-items: center;
	gap: 8px;
	padding: 6px 8px 6px 12px;
	border-bottom: solid 1px var(--MI_THEME-divider);
	font-size: 0.9em;
	font-weight: bold;
}

.icon {
	opacity: 0.8;
}

.name {
	flex: 1;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.author {
	margin-left: 6px;
	font-weight: normal;
	opacity: 0.7;
}

.active {
	color: var(--MI_THEME-accent);
}

.notice {
	display: flex;
	align-items: center;
	gap: 8px;
	padding: 8px 12px;
	border-bottom: solid 1px var(--MI_THEME-divider);
	font-size: 0.85em;
}

.noticeText {
	flex: 1;
	min-width: 0;
	overflow-wrap: anywhere;
}

.remove {
	flex-shrink: 0;
	width: 28px;
	height: 28px;
	border-radius: 100%;

	&:hover {
		background: var(--MI_THEME-buttonHoverBg);
	}
}

.playForm {
	display: flex;
	align-items: center;
	gap: 8px;
	padding: 10px 12px;
}

.playInput {
	flex: 1;
}

.unknown {
	padding: 16px;
	opacity: 0.7;
	font-size: 0.9em;
}
</style>
