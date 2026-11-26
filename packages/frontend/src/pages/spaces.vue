<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader :actions="headerActions">
	<div class="_spacer" style="--MI_SPACER-w: 700px;">
		<div class="_gaps">
			<MkButton primary rounded style="margin: 0 auto;" @click="open">
				<i class="ti ti-plus"></i> {{ i18n.ts._spaces.open }}
			</MkButton>
			<MkLoading v-if="spaces == null"/>
			<MkResult v-else-if="spaces.length === 0" type="empty" :text="i18n.ts._spaces.noOpenSpaces"/>
			<div v-else class="_gaps_s">
				<MkSpaceCard v-for="space in spaces" :key="space.id" :spaceId="space.id" :initialSpace="space"/>
			</div>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import { computed, onActivated, onMounted, ref } from 'vue';
import type * as Misskey from 'misskey-js';
import MkButton from '@/components/MkButton.vue';
import MkSpaceCard from '@/components/MkSpaceCard.vue';
import { i18n } from '@/i18n.js';
import { definePage } from '@/page.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { openSpaceCreateDialog } from '@/utility/space.js';
import { useRouter } from '@/router.js';

const router = useRouter();
const spaces = ref<Misskey.entities.Space[] | null>(null);

async function fetchSpaces(): Promise<void> {
	spaces.value = await misskeyApi('spaces/list', {});
}

async function open(): Promise<void> {
	const space = await openSpaceCreateDialog();
	if (space != null) router.push('/spaces/:spaceId', { params: { spaceId: space.id } });
}

onMounted(fetchSpaces);
onActivated(fetchSpaces);

const headerActions = computed(() => [{
	icon: 'ti ti-refresh',
	text: i18n.ts.reload,
	handler: fetchSpaces,
}]);

definePage(() => ({
	title: i18n.ts._spaces.title,
	icon: 'ti ti-broadcast',
}));
</script>
