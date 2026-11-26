<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div :class="$style.root">
	<MkLoading v-if="loading"/>
	<div v-else-if="flash == null" :class="$style.message">{{ i18n.ts._spaces._tiles._play.notFound }}</div>
	<template v-else>
		<div :class="$style.head">
			<span :class="$style.title">{{ flash.title }}</span>
			<button v-if="started" class="_button" :class="$style.reload" :aria-label="i18n.ts.reload" :title="i18n.ts.reload" @click="run"><i class="ti ti-reload"></i></button>
		</div>
		<div v-if="!started" :class="$style.ready">
			<div v-if="flash.summary" :class="$style.summary">{{ flash.summary }}</div>
			<MkButton primary rounded @click="start">{{ i18n.ts._spaces._tiles._play.start }}</MkButton>
		</div>
		<MkAsUi v-else-if="root" :component="root" :components="components"/>
	</template>
</div>
</template>

<script lang="ts" setup>
import { onBeforeUnmount, ref, shallowRef, watch } from 'vue';
import type { Ref } from 'vue';
import type * as Misskey from 'misskey-js';
import { utils } from '@syuilo/aiscript';
import type { Interpreter } from '@syuilo/aiscript';
import { compareVersions } from 'compare-versions';
import { url } from '@@/js/config.js';
import type { AsUiComponent, AsUiRoot } from '@/aiscript/ui.js';
import MkAsUi from '@/components/MkAsUi.vue';
import MkButton from '@/components/MkButton.vue';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { registerAsUiLib } from '@/aiscript/ui.js';
import { aiScriptReadline, createAiScriptEnv } from '@/aiscript/api.js';

/**
 * Play を、ページの外 (スペースのタイルなど) で動かす部品。
 * 動かし方は Play のページ (pages/flash/flash.vue) と同じ。Play は見ている人それぞれの画面で別々に動く。
 */

const props = defineProps<{
	flashId: string;
}>();

const loading = ref(true);
const flash = ref<Misskey.entities.Flash | null>(null);
const started = ref(false);
const aiscript = shallowRef<Interpreter | null>(null);
const root = ref<AsUiRoot>();
const components = ref<Ref<AsUiComponent>[]>([]);
/** 動かし直すたびに増やす。読み込みを待っている間に片づけられた・動かし直されたものを捨てるのに使う */
let generation = 0;

function isLegacy(version: string | null): boolean {
	if (version == null) return true;
	try {
		return compareVersions(version, '1.0.0') < 0;
	} catch {
		return false;
	}
}

async function fetchFlash(): Promise<void> {
	generation++;
	aiscript.value?.abort();
	started.value = false;
	loading.value = true;
	try {
		flash.value = await misskeyApi('flash/show', { flashId: props.flashId });
	} catch {
		flash.value = null;
	} finally {
		loading.value = false;
	}
}

function start(): void {
	started.value = true;
	void run();
}

async function run(): Promise<void> {
	const current = ++generation;
	aiscript.value?.abort();
	const target = flash.value;
	if (target == null) return;

	const version = utils.getLangVersion(target.script);
	const { Interpreter, Parser, values } = (isLegacy(version) ? (await import('@syuilo/aiscript-0-19-0')) : await import('@syuilo/aiscript')) as typeof import('@syuilo/aiscript');
	// 読み込みを待っている間に、タイルが片づけられたり動かし直されたりしていたら、動かさない
	if (current !== generation) return;
	const parser = new Parser();
	components.value = [];

	const interpreter = new Interpreter({
		...createAiScriptEnv({
			storageKey: 'flash:' + target.id,
		}),
		...registerAsUiLib(components.value, (_root) => {
			root.value = _root.value;
		}),
		THIS_ID: values.STR(target.id),
		THIS_URL: values.STR(`${url}/play/${target.id}`),
	}, {
		in: aiScriptReadline,
		out: () => {
			// nop
		},
		err: (err) => {
			os.alert({
				type: 'error',
				title: 'AiScript Error',
				text: String(err),
			});
		},
		log: () => {
			// nop
		},
	});
	aiscript.value = interpreter;

	try {
		await interpreter.exec(parser.parse(target.script));
	} catch (err) {
		os.alert({
			type: 'error',
			title: 'AiScript Error',
			text: String(err),
		});
	}
}

watch(() => props.flashId, fetchFlash, { immediate: true });

onBeforeUnmount(() => {
	generation++;
	aiscript.value?.abort();
});
</script>

<style lang="scss" module>
.root {
	padding: 10px 12px;
}

.head {
	display: flex;
	align-items: center;
	gap: 8px;
	margin-bottom: 8px;
}

.title {
	flex: 1;
	min-width: 0;
	font-weight: bold;
	overflow-wrap: anywhere;
}

.reload {
	flex-shrink: 0;
	width: 28px;
	height: 28px;
	border-radius: 100%;

	&:hover {
		background: var(--MI_THEME-buttonHoverBg);
	}
}

.ready {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 10px;
	padding: 8px 0;
}

.summary {
	font-size: 0.9em;
	opacity: 0.8;
	overflow-wrap: anywhere;
}

.message {
	opacity: 0.7;
	font-size: 0.9em;
}
</style>
