<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<MkA v-if="space != null" :to="`/spaces/${space.id}`" :class="[$style.root, { [$style.ended]: space.endedAt != null }]" class="_panel" @click.stop>
	<div :class="$style.icon"><i class="ti ti-broadcast"></i></div>
	<div :class="$style.body">
		<div :class="$style.name">{{ space.name }}</div>
		<div :class="$style.meta">
			<MkAvatar :user="space.host" :class="$style.avatar" :indicator="false"/>
			<MkUserName :user="space.host" :nowrap="true"/>
		</div>
	</div>
	<div :class="$style.status">
		<template v-if="space.endedAt == null">
			<span :class="$style.live"><i class="ti ti-users"></i> {{ i18n.tsx._spaces.memberCount({ n: space.memberCount }) }}</span>
		</template>
		<template v-else>
			<span>{{ i18n.ts._spaces.ended }}</span>
			<span>{{ i18n.tsx._spaces.memberCount({ n: space.participantCount }) }}</span>
		</template>
	</div>
</MkA>
</template>

<script lang="ts" setup>
import { computed, onMounted, ref } from 'vue';
import type * as Misskey from 'misskey-js';
import { i18n } from '@/i18n.js';
import { fetchSpaceCached } from '@/utility/space.js';

const props = defineProps<{
	spaceId: string;
	/** 一覧などですでに持っているスペース。あれば問い合わせない */
	initialSpace?: Misskey.entities.Space;
}>();

const fetched = ref<Misskey.entities.Space | null>(null);
// 一覧が取り直されたら、その新しい内容を出す
const space = computed(() => props.initialSpace ?? fetched.value);

onMounted(async () => {
	if (space.value != null) return;
	try {
		fetched.value = await fetchSpaceCached(props.spaceId);
	} catch {
		// 見つからないスペースは何も出さない
	}
});
</script>

<style lang="scss" module>
.root {
	display: flex;
	align-items: center;
	gap: 12px;
	padding: 12px 14px;
	border: solid 1px var(--MI_THEME-divider);
	text-decoration: none;
	color: var(--MI_THEME-fg);

	&:hover {
		text-decoration: none;
		border-color: var(--MI_THEME-accent);
	}
}

.ended {
	opacity: 0.7;
}

.icon {
	flex-shrink: 0;
	display: flex;
	align-items: center;
	justify-content: center;
	width: 40px;
	height: 40px;
	border-radius: 100%;
	background: var(--MI_THEME-accentedBg);
	color: var(--MI_THEME-accent);
	font-size: 20px;
}

.body {
	flex: 1;
	min-width: 0;
}

.name {
	font-weight: bold;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.meta {
	display: flex;
	align-items: center;
	gap: 6px;
	margin-top: 2px;
	font-size: 0.85em;
	opacity: 0.8;
	min-width: 0;
}

.avatar {
	flex-shrink: 0;
	width: 18px;
	height: 18px;
}

.status {
	flex-shrink: 0;
	display: flex;
	flex-direction: column;
	align-items: flex-end;
	font-size: 0.85em;
}

.live {
	color: var(--MI_THEME-accent);
	font-weight: bold;
}
</style>
