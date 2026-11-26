<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader v-model:tab="tab" :tabs="headerTabs" :actions="headerActions">
	<div class="_spacer" style="--MI_SPACER-w: 700px;">
		<div class="_gaps">
			<MkButton primary rounded style="margin: 0 auto;" @click="router.push('/spaces/tiles/new')">
				<i class="ti ti-plus"></i> {{ i18n.ts._spaces.createTile }}
			</MkButton>
			<MkLoading v-if="defs == null"/>
			<MkResult v-else-if="defs.length === 0" type="empty" :text="i18n.ts._spaces.noCustomTiles"/>
			<div v-else class="_gaps_s">
				<MkA v-for="def in defs" :key="def.id" :to="`/spaces/tiles/${def.id}`" :class="$style.item" class="_panel">
					<div :class="$style.name"><i class="ti ti-puzzle"></i> {{ def.name }}<i v-if="def.visibility === 'private'" class="ti ti-lock" :class="$style.private" role="img" :title="i18n.ts._spaces.privateTile" :aria-label="i18n.ts._spaces.privateTile"></i></div>
					<div v-if="def.description" :class="$style.description">{{ def.description }}</div>
					<div :class="$style.author">@{{ def.user.username }}</div>
				</MkA>
			</div>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import { computed, onActivated, ref, watch } from 'vue';
import type * as Misskey from 'misskey-js';
import MkButton from '@/components/MkButton.vue';
import { i18n } from '@/i18n.js';
import { definePage } from '@/page.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { useRouter } from '@/router.js';

const router = useRouter();
const tab = ref<'everyone' | 'mine'>('everyone');
const defs = ref<Misskey.entities.SpaceTileDef[] | null>(null);

async function fetchDefs(): Promise<void> {
	const target = tab.value;
	defs.value = null;
	// 取れなかったら、空の一覧として見せる
	const result = await misskeyApi(target === 'mine' ? 'spaces/tile-defs/my' : 'spaces/tile-defs/list', { limit: 100 }).catch(() => []);
	// 取っている間にタブが変わっていたら捨てる
	if (target === tab.value) defs.value = result;
}

watch(tab, fetchDefs);
// 初回もここを通る。作成画面から戻ってきたときにも取り直す
onActivated(fetchDefs);

const headerTabs = computed(() => [{
	key: 'everyone',
	title: i18n.ts._spaces.customTiles,
	icon: 'ti ti-layout-grid',
}, {
	key: 'mine',
	title: i18n.ts._spaces.myTiles,
	icon: 'ti ti-user',
}]);

const headerActions = computed(() => [{
	icon: 'ti ti-refresh',
	text: i18n.ts.reload,
	handler: fetchDefs,
}]);

definePage(() => ({
	title: i18n.ts._spaces.browseTiles,
	icon: 'ti ti-layout-grid',
}));
</script>

<style lang="scss" module>
.item {
	display: block;
	padding: 12px 16px;
	text-decoration: none;
	color: inherit;

	&:hover {
		text-decoration: none;
		background: var(--MI_THEME-buttonHoverBg);
	}
}

.name {
	font-weight: bold;
	overflow-wrap: anywhere;
}

.private {
	margin-left: 6px;
	opacity: 0.7;
}

.description {
	margin-top: 4px;
	font-size: 0.9em;
	overflow-wrap: anywhere;
}

.author {
	margin-top: 4px;
	font-size: 0.85em;
	opacity: 0.7;
}
</style>
