<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader>
	<div class="_spacer" style="--MI_SPACER-w: 1100px;">
		<MkLoading v-if="loading"/>
		<MkResult v-else-if="notFound" type="notFound"/>
		<div v-else :class="$style.columns">
			<div class="_gaps">
				<MkInput v-model="name" :maxlength="100">
					<template #label>{{ i18n.ts._spaces._tileEditor.name }}</template>
				</MkInput>
				<MkTextarea v-model="description" :maxlength="1000">
					<template #label>{{ i18n.ts._spaces._tileEditor.description }}</template>
				</MkTextarea>
				<MkCodeEditor v-model="code" lang="html">
					<template #label>{{ i18n.ts._spaces._tileEditor.code }}</template>
				</MkCodeEditor>
				<MkTextarea v-model="fetchHosts" :spellcheck="false">
					<template #label>{{ i18n.ts._spaces._tileEditor.fetchHosts }}</template>
					<template #caption>{{ i18n.ts._spaces._tileEditor.fetchHostsCaption }}</template>
				</MkTextarea>
				<MkSwitch v-model="isPublic">
					<template #label>{{ i18n.ts._spaces._tileEditor.visibilityPublic }}</template>
					<template #caption>{{ i18n.ts._spaces._tileEditor.visibilityPublicCaption }}</template>
				</MkSwitch>
				<div class="_buttons">
					<MkButton primary rounded :disabled="name.trim() === '' || code.trim() === ''" @click="save"><i class="ti ti-check"></i> {{ i18n.ts.save }}</MkButton>
					<MkButton v-if="savedId != null" danger rounded @click="remove"><i class="ti ti-trash"></i> {{ i18n.ts.delete }}</MkButton>
				</div>
				<MkFolder>
					<template #icon><i class="ti ti-help-circle"></i></template>
					<template #label>{{ i18n.ts._spaces._tileEditor.apiReference }}</template>
					<pre :class="$style.reference">{{ i18n.ts._spaces._tileEditor.apiReferenceBody }}</pre>
				</MkFolder>
			</div>
			<div class="_gaps_s">
				<div :class="$style.previewHead">
					<span :class="$style.previewTitle">{{ i18n.ts._spaces._tileEditor.preview }}</span>
					<MkButton small rounded @click="run"><i class="ti ti-player-play"></i> {{ i18n.ts._spaces._tileEditor.run }}</MkButton>
				</div>
				<MkSwitch v-model="twoPeople">{{ i18n.ts._spaces._tileEditor.twoPeople }}</MkSwitch>
				<MkSpaceTilePreview :key="`${runCount}:${twoPeople}`" :code="runningCode" :defId="savedId" :twoPeople="twoPeople"/>
			</div>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import { ref } from 'vue';
import MkButton from '@/components/MkButton.vue';
import MkCodeEditor from '@/components/MkCodeEditor.vue';
import MkFolder from '@/components/MkFolder.vue';
import MkInput from '@/components/MkInput.vue';
import MkSwitch from '@/components/MkSwitch.vue';
import MkTextarea from '@/components/MkTextarea.vue';
import MkSpaceTilePreview from '@/components/MkSpaceTilePreview.vue';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { definePage } from '@/page.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { useRouter } from '@/router.js';
import sampleTile from '@/spaces/sample-tile.js';

const props = defineProps<{
	/** 書き換えるタイル。新しくつくるときは無い */
	defId?: string;
}>();

const router = useRouter();
const loading = ref(props.defId != null);
const notFound = ref(false);
/** 保存してあるタイルの ID。まだ保存していなければ null */
const savedId = ref<string | null>(null);
const name = ref('');
const description = ref('');
const code = ref(sampleTile);
const fetchHosts = ref('');
const isPublic = ref(true);
const twoPeople = ref(false);

/** 試しの枠で動いているコード。「動かす」を押したときにだけ変える */
const runningCode = ref(code.value);
const runCount = ref(0);

function run(): void {
	runningCode.value = code.value;
	runCount.value++;
}

function parseHosts(): string[] {
	return fetchHosts.value.split(/[\s,]+/).map(host => host.trim()).filter(host => host !== '');
}

async function load(): Promise<void> {
	if (props.defId == null) return;
	loading.value = true;
	try {
		const def = await misskeyApi('spaces/tile-defs/show', { defId: props.defId });
		// 書き換えられるのは作者だけ
		if (def.userId !== $i?.id || def.code == null) {
			notFound.value = true;
			return;
		}
		savedId.value = def.id;
		name.value = def.name;
		description.value = def.description;
		code.value = def.code;
		fetchHosts.value = def.fetchHosts.join('\n');
		isPublic.value = def.visibility === 'public';
		run();
	} catch {
		notFound.value = true;
	} finally {
		loading.value = false;
	}
}

async function save(): Promise<void> {
	const params = {
		name: name.value.trim(),
		description: description.value,
		code: code.value,
		fetchHosts: parseHosts(),
		visibility: isPublic.value ? 'public' as const : 'private' as const,
	};
	if (savedId.value == null) {
		const created = await os.apiWithDialog('spaces/tile-defs/create', params);
		savedId.value = created.id;
		fetchHosts.value = created.fetchHosts.join('\n');
		// 書き換えの URL に移る。ページは作り直され、保存したものを読み直す
		router.replace('/spaces/tiles/:defId/edit', { params: { defId: created.id } });
	} else {
		const updated = await os.apiWithDialog('spaces/tile-defs/update', { defId: savedId.value, ...params });
		// 形の合わないドメインはサーバーが落とす。残ったものを見せる
		fetchHosts.value = updated.fetchHosts.join('\n');
	}
	run();
}

async function remove(): Promise<void> {
	if (savedId.value == null) return;
	const { canceled } = await os.confirm({ type: 'warning', text: i18n.ts._spaces._tileEditor.deleteConfirm });
	if (canceled) return;
	await os.apiWithDialog('spaces/tile-defs/delete', { defId: savedId.value });
	router.push('/spaces/tiles');
}

void load();

definePage(() => ({
	title: props.defId != null ? i18n.ts._spaces.editTile : i18n.ts._spaces.createTile,
	icon: 'ti ti-puzzle',
}));
</script>

<style lang="scss" module>
.columns {
	display: grid;
	grid-template-columns: minmax(0, 1fr);
	gap: 24px;
	container-type: inline-size;

	@media (min-width: 1000px) {
		grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
		align-items: start;
	}
}

.previewHead {
	display: flex;
	align-items: center;
	gap: 8px;
}

.previewTitle {
	flex: 1;
	font-weight: bold;
}

.reference {
	margin: 0;
	white-space: pre-wrap;
	overflow-wrap: anywhere;
	font-size: 0.85em;
	line-height: 1.7;
}
</style>
