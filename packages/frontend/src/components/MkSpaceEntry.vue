<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div v-if="spaces.length > 0" :class="$style.root" class="_gaps_s">
	<div :class="$style.label"><i class="ti ti-broadcast"></i> {{ i18n.ts._spaces.nowOpen }}</div>
	<MkSpaceCard v-for="space in spaces" :key="space.id" :spaceId="space.id" :initialSpace="space"/>
</div>
</template>

<script lang="ts" setup>
import { onActivated, onMounted, onUnmounted, ref } from 'vue';
import type * as Misskey from 'misskey-js';
import MkSpaceCard from '@/components/MkSpaceCard.vue';
import { i18n } from '@/i18n.js';
import { instance } from '@/instance.js';
import { $i } from '@/i.js';
import { misskeyApi } from '@/utility/misskey-api.js';

/** タイムラインの上に出す、開いているスペースの帯。開いているものが無ければ何も出さない。 */

const REFRESH_INTERVAL_MS = 60 * 1000;

const spaces = ref<Misskey.entities.Space[]>([]);
let timerId: number | null = null;

async function fetchSpaces(): Promise<void> {
	if ($i == null || instance.features?.spaces !== true) return;
	try {
		spaces.value = await misskeyApi('spaces/list', {});
	} catch {
		// 取れなかったときは前の表示のままにする
	}
}

onMounted(() => {
	void fetchSpaces();
	timerId = window.setInterval(fetchSpaces, REFRESH_INTERVAL_MS);
});
onActivated(fetchSpaces);
onUnmounted(() => {
	if (timerId != null) window.clearInterval(timerId);
});
</script>

<style lang="scss" module>
.root {
	margin-bottom: var(--MI-margin);
}

.label {
	font-size: 0.85em;
	font-weight: bold;
	opacity: 0.8;
}
</style>
