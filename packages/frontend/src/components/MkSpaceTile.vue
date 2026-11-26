<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<section :class="$style.root" class="_panel" :aria-label="definition?.name ?? tile.kind">
	<header :class="$style.header">
		<i v-if="definition != null" :class="[definition.icon, $style.icon]"></i>
		<span :class="$style.name">{{ definition?.name ?? tile.kind }}</span>
		<button v-if="expandable" class="_button" :class="$style.remove" :aria-label="expanded ? i18n.ts._spaces.shrinkTile : i18n.ts._spaces.expandTile" :title="expanded ? i18n.ts._spaces.shrinkTile : i18n.ts._spaces.expandTile" @click="emit('expand')">
			<i :class="expanded ? 'ti ti-arrows-minimize' : 'ti ti-arrows-maximize'"></i>
		</button>
		<button v-if="removable" class="_button" :class="$style.remove" :aria-label="i18n.ts._spaces.removeTile" :title="i18n.ts._spaces.removeTile" @click="emit('remove')">
			<i class="ti ti-x"></i>
		</button>
	</header>
	<!-- タイルは、権限を絞った枠の中で動かす。allow-scripts だけを許し、同じ出どころとしては扱わせない -->
	<!-- Play だけは、枠ではなく本体が直接描く。Play は AiScript で動き、Misskey の部品で描くため -->
	<div v-if="definition != null && definition.html == null">
		<MkFlashPlayer v-if="flashId != null" :flashId="flashId"/>
		<form v-else :class="$style.playForm" @submit.prevent="setFlash">
			<MkInput v-model="flashInput" :class="$style.playInput" :placeholder="i18n.ts._spaces._tiles._play.placeholder" :aria-label="i18n.ts._spaces._tiles._play.placeholder"/>
			<MkButton primary type="submit">{{ i18n.ts._spaces._tiles._play.set }}</MkButton>
		</form>
	</div>
	<iframe
		v-else-if="definition != null"
		ref="frame"
		:class="$style.frame"
		:style="{ height: `${expanded ? Math.max(height, EXPANDED_MIN_HEIGHT) : height}px` }"
		sandbox="allow-scripts"
		:srcdoc="srcdoc"
		:title="definition.name"
		@load="onLoad"
	></iframe>
	<div v-else :class="$style.unknown">{{ i18n.ts._spaces.unknownTile }}</div>
</section>
</template>

<script lang="ts" setup>
import { computed, onBeforeUnmount, ref, useTemplateRef, watch } from 'vue';
import type * as Misskey from 'misskey-js';
import { apiUrl, url as localUrl } from '@@/js/config.js';
import { versatileLang } from '@@/js/intl-const.js';
import MkButton from '@/components/MkButton.vue';
import MkInput from '@/components/MkInput.vue';
import MkFlashPlayer from '@/components/MkFlashPlayer.vue';
import { chooseDriveFile } from '@/utility/drive.js';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { miLocalStorage } from '@/local-storage.js';
import { getBuiltinTile } from '@/spaces/builtin-tiles.js';
import { buildTileDocument, TILE_PORT_MESSAGE, toTileUser } from '@/spaces/tile-frame.js';
import type { HostToTileMessage, TileToHostMessage } from '@/spaces/tile-frame.js';
import { getSpaceShared, onSpaceTileEvent, sendSpaceSignal, setSpaceShared, spaceSession as session } from '@/utility/space-session.js';

const MIN_HEIGHT = 60;
const MAX_HEIGHT = 640;
const EXPANDED_MIN_HEIGHT = 360;
/** タイルが本体に読ませられる Misskey のデータ。ログインなしの立場で読むので、公開されているものだけが返る */
const PUBLIC_ENDPOINTS = ['notes/show', 'users/show', 'flash/show'];

const props = defineProps<{
	tile: Misskey.entities.SpaceTile;
	/** 片づけるボタンを出すか */
	removable?: boolean;
	/** 「大きく出す」のボタンを出すか */
	expandable?: boolean;
	/** いま大きく出しているか */
	expanded?: boolean;
}>();

const emit = defineEmits<{
	(ev: 'remove'): void;
	(ev: 'expand'): void;
}>();

const frame = useTemplateRef('frame');
const height = ref(120);
const definition = computed(() => getBuiltinTile(props.tile.kind));
let port: MessagePort | null = null;
let offTileEvent: (() => void) | null = null;

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
const embeddedShared = getSpaceShared(props.tile.id);

/**
 * 枠の中身。タイルごとに1回だけ組み立てる。そのあとの変化は通信路で伝える。
 * いる人が変わるたびに組み立て直すと枠が読み直されて、書いている途中のものが消えるので、ここでは変化を追わない。
 */
const srcdoc = ((): string => {
	if (definition.value?.html == null || $i == null) return '';
	return buildTileDocument(definition.value.html, {
		shared: embeddedShared,
		mine: readMine(),
		me: toTileUser($i),
		members: session.members.map(member => toTileUser(member.user)),
		isHost: session.space?.hostId === $i.id,
		isLeader: session.leaderId === $i.id,
		origin: localUrl,
		strings: definition.value.strings,
	}, localUrl);
})();

function send(message: HostToTileMessage): void {
	port?.postMessage(message);
}

/** 枠から頼まれたことを、本体がやる。枠には結果だけを返す。 */
async function handleCall(method: string, args: unknown): Promise<unknown> {
	const params = (typeof args === 'object' && args != null ? args : {}) as Record<string, unknown>;
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
			throw new Error('unknown method');
	}
}

async function onTileMessage(ev: MessageEvent): Promise<void> {
	const message = ev.data as TileToHostMessage | null;
	if (message == null || typeof message !== 'object') return;
	switch (message.t) {
		case 'setShared':
			if (typeof message.key === 'string') setSpaceShared(props.tile.id, message.key, message.value ?? null);
			break;
		case 'setMine':
			if (typeof message.key === 'string') writeMine(message.key, message.value ?? null);
			break;
		case 'signal':
			if (typeof message.type === 'string') sendSpaceSignal(props.tile.id, message.type, message.body ?? null);
			break;
		case 'call': {
			const id = message.id;
			if (typeof id !== 'number' || typeof message.method !== 'string') break;
			try {
				send({ t: 'reply', id, ok: true, value: await handleCall(message.method, message.args) });
			} catch (err) {
				send({ t: 'reply', id, ok: false, value: err instanceof Error ? err.message : 'failed' });
			}
			break;
		}
		case 'resize':
			if (typeof message.height === 'number' && Number.isFinite(message.height)) height.value = Math.min(MAX_HEIGHT, Math.max(MIN_HEIGHT, Math.ceil(message.height)));
			break;
		case 'open': {
			// 枠は自分ではリンクを開けない。本体が確かめてから開く
			if (typeof message.url !== 'string' || !/^https?:\/\//.test(message.url)) break;
			const { canceled } = await os.confirm({ type: 'question', title: i18n.ts._spaces.openLinkConfirm, text: message.url });
			if (!canceled) window.open(message.url, '_blank', 'noopener');
			break;
		}
	}
}

function closePort(): void {
	offTileEvent?.();
	offTileEvent = null;
	port?.close();
	port = null;
}

/** 枠が読み込まれたら、通信路を渡す。枠は別の出どころなので、相手は絞れない。渡すのは通信路だけ */
function onLoad(): void {
	const target = frame.value?.contentWindow;
	if (target == null) return;
	closePort();
	const channel = new MessageChannel();
	port = channel.port1;
	port.onmessage = onTileMessage;
	target.postMessage({ type: TILE_PORT_MESSAGE }, '*', [channel.port2]);
	offTileEvent = onSpaceTileEvent(props.tile.id, {
		shared: (key, value, userId) => send({ t: 'shared', key, value, userId }),
		signal: (type, body, userId) => send({ t: 'signal', type, body, userId }),
	});
	// 枠を組み立ててから読み込まれるまでの間に変わった値を伝える。ページを移って戻り、枠が読み直されたときもここを通る
	const current = getSpaceShared(props.tile.id);
	for (const key of new Set([...Object.keys(embeddedShared), ...Object.keys(current)])) {
		if (JSON.stringify(embeddedShared[key] ?? null) !== JSON.stringify(current[key] ?? null)) send({ t: 'shared', key, value: current[key] ?? null, userId: '' });
	}
	send({ t: 'members', members: session.members.map(member => toTileUser(member.user)) });
	send({ t: 'leader', isLeader: session.leaderId === $i?.id });
}

watch(() => session.leaderId, (leaderId) => {
	send({ t: 'leader', isLeader: leaderId === $i?.id });
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
	closePort();
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

.remove {
	flex-shrink: 0;
	width: 28px;
	height: 28px;
	border-radius: 100%;

	&:hover {
		background: var(--MI_THEME-buttonHoverBg);
	}
}

.frame {
	display: block;
	width: 100%;
	border: none;
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
