<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader>
	<div class="_spacer" style="--MI_SPACER-w: 700px;">
		<MkLoading v-if="loading"/>
		<MkResult v-else-if="def == null" type="notFound"/>
		<div v-else class="_gaps">
			<div class="_gaps_s">
				<div :class="$style.name">{{ def.name }}</div>
				<div :class="$style.author">{{ i18n.ts._spaces._tileEditor.by }}: <MkA :to="`/@${def.user.username}`">@{{ def.user.username }}</MkA></div>
				<div v-if="def.description" :class="$style.description">{{ def.description }}</div>
				<div v-if="def.fetchHosts.length > 0" :class="$style.hosts">{{ i18n.ts._spaces._tileEditor.fetchHosts }}: <code>{{ def.fetchHosts.join(', ') }}</code></div>
			</div>
			<div v-if="isAuthor || $i?.isModerator || $i?.isAdmin" class="_buttons">
				<MkButton v-if="isAuthor" rounded @click="router.push('/spaces/tiles/:defId/edit', { params: { defId: def.id } })"><i class="ti ti-pencil"></i> {{ i18n.ts.edit }}</MkButton>
				<MkButton danger rounded @click="remove"><i class="ti ti-trash"></i> {{ i18n.ts.delete }}</MkButton>
			</div>
			<MkFolder :defaultOpen="true">
				<template #icon><i class="ti ti-player-play"></i></template>
				<template #label>{{ i18n.ts._spaces._tileEditor.preview }}</template>
				<div class="_gaps_s">
					<MkSwitch v-model="twoPeople">{{ i18n.ts._spaces._tileEditor.twoPeople }}</MkSwitch>
					<MkSpaceTilePreview v-if="def.code != null" :key="`${twoPeople}`" :code="def.code" :defId="isAuthor ? def.id : null" :twoPeople="twoPeople"/>
				</div>
			</MkFolder>
			<MkFolder>
				<template #icon><i class="ti ti-code"></i></template>
				<template #label>{{ i18n.ts._spaces._tileEditor.code }}</template>
				<MkCode v-if="def.code != null" :code="def.code" lang="html"/>
			</MkFolder>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import { computed, ref, watch } from 'vue';
import type * as Misskey from 'misskey-js';
import MkButton from '@/components/MkButton.vue';
import MkCode from '@/components/MkCode.vue';
import MkFolder from '@/components/MkFolder.vue';
import MkSwitch from '@/components/MkSwitch.vue';
import MkSpaceTilePreview from '@/components/MkSpaceTilePreview.vue';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { definePage } from '@/page.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { useRouter } from '@/router.js';

const props = defineProps<{
	defId: string;
}>();

const router = useRouter();
const loading = ref(true);
const def = ref<Misskey.entities.SpaceTileDef | null>(null);
const twoPeople = ref(false);
const isAuthor = computed(() => def.value != null && def.value.userId === $i?.id);

async function fetchDef(): Promise<void> {
	loading.value = true;
	try {
		def.value = await misskeyApi('spaces/tile-defs/show', { defId: props.defId });
	} catch {
		def.value = null;
	} finally {
		loading.value = false;
	}
}

async function remove(): Promise<void> {
	if (def.value == null) return;
	const { canceled } = await os.confirm({ type: 'warning', text: i18n.ts._spaces._tileEditor.deleteConfirm });
	if (canceled) return;
	await os.apiWithDialog('spaces/tile-defs/delete', { defId: def.value.id });
	router.push('/spaces/tiles');
}

watch(() => props.defId, fetchDef, { immediate: true });

definePage(() => ({
	title: def.value?.name ?? i18n.ts._spaces.browseTiles,
	icon: 'ti ti-puzzle',
}));
</script>

<style lang="scss" module>
.name {
	font-size: 1.3em;
	font-weight: bold;
	overflow-wrap: anywhere;
}

.author,
.hosts {
	font-size: 0.9em;
	opacity: 0.8;
	overflow-wrap: anywhere;
}

.description {
	white-space: pre-wrap;
	overflow-wrap: anywhere;
}
</style>
