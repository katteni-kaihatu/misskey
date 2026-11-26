<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<!-- タイルは、権限を絞った枠の中で動かす。allow-scripts だけを許し、同じ出どころとしては扱わせない -->
<iframe
	ref="frame"
	:class="$style.frame"
	:style="{ height: `${expanded ? Math.max(height, EXPANDED_MIN_HEIGHT) : height}px` }"
	sandbox="allow-scripts"
	:srcdoc="srcdoc"
	:title="title"
	@load="onLoad"
></iframe>
</template>

<script lang="ts" setup>
import { onBeforeUnmount, ref, useTemplateRef } from 'vue';
import { url as localUrl } from '@@/js/config.js';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { buildTileDocument, TILE_PORT_MESSAGE } from '@/spaces/tile-frame.js';
import type { HostToTileMessage, TileInit, TileToHostMessage } from '@/spaces/tile-frame.js';

/**
 * タイルを動かす枠そのもの。枠との通信だけを受け持ち、値をどこに置くかは知らない。
 * スペースの中 (MkSpaceTile) でも、作成画面の試しの枠 (MkSpaceTilePreview) でも使う。
 */

const MIN_HEIGHT = 60;
const MAX_HEIGHT = 640;
const EXPANDED_MIN_HEIGHT = 360;

const props = defineProps<{
	/** タイルの HTML と JavaScript */
	html: string;
	/** 枠に最初に渡すもの。枠は1回だけ組み立てるので、あとから変えても伝わらない。変化は `send` で伝える */
	init: TileInit;
	title: string;
	/** 大きく出しているか */
	expanded?: boolean;
	/** 枠から頼まれたことを、本体がやる。結果だけが枠に返る */
	call: (method: string, params: Record<string, unknown>) => Promise<unknown>;
}>();

const emit = defineEmits<{
	(ev: 'setShared', key: string, value: unknown): void;
	(ev: 'setMine', key: string, value: unknown): void;
	(ev: 'signal', type: string, body: unknown): void;
	/** 枠が読み込まれて、通信路がつながった。読み直されたときも呼ばれる */
	(ev: 'ready'): void;
}>();

const frame = useTemplateRef('frame');
const height = ref(120);
let port: MessagePort | null = null;

/**
 * 枠の中身。1回だけ組み立てる。そのあとの変化は通信路で伝える。
 * 組み立て直すと枠が読み直されて、書いている途中のものが消えるので、ここでは変化を追わない。
 */
const srcdoc = buildTileDocument(props.html, props.init, localUrl);

function send(message: HostToTileMessage): void {
	port?.postMessage(message);
}

async function onTileMessage(source: MessagePort, ev: MessageEvent): Promise<void> {
	if (port !== source) return;
	const message = ev.data as TileToHostMessage | null;
	if (message == null || typeof message !== 'object') return;
	switch (message.t) {
		case 'setShared':
			if (typeof message.key === 'string') emit('setShared', message.key, message.value ?? null);
			break;
		case 'setMine':
			if (typeof message.key === 'string') emit('setMine', message.key, message.value ?? null);
			break;
		case 'signal':
			if (typeof message.type === 'string') emit('signal', message.type, message.body ?? null);
			break;
		case 'call': {
			const id = message.id;
			if (typeof id !== 'number' || typeof message.method !== 'string') break;
			try {
				const params = (typeof message.args === 'object' && message.args != null ? message.args : {}) as Record<string, unknown>;
				const value = await props.call(message.method, params);
				if (source === port) source.postMessage({ t: 'reply', id, ok: true, value });
			} catch (err) {
				if (source === port) source.postMessage({ t: 'reply', id, ok: false, value: err instanceof Error ? err.message : 'failed' });
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
			if (!canceled && port === source) window.open(message.url, '_blank', 'noopener');
			break;
		}
		case 'post':
			// 枠は投稿できない。本体が投稿フォームを開き、投稿するかどうかは本人が決める
			if (typeof message.text === 'string') void os.post({ initialText: message.text.slice(0, 3000), instant: true });
			break;
	}
}

function closePort(): void {
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
	port.onmessage = ev => onTileMessage(channel.port1, ev);
	target.postMessage({ type: TILE_PORT_MESSAGE }, '*', [channel.port2]);
	emit('ready');
}

onBeforeUnmount(closePort);

defineExpose({ send });
</script>

<style lang="scss" module>
.frame {
	display: block;
	width: 100%;
	border: none;
}
</style>
