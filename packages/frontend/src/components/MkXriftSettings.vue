<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<MkFolder>
	<template #label>{{ i18n.ts._urlPreviewSetting.xrift }}</template>
	<template v-if="form.modified.value" #footer><MkFormFooter :form="form"/></template>
	<div class="_gaps_m">
		<div>{{ keyConfigured ? i18n.ts._urlPreviewSetting.xriftKeyConfigured : i18n.ts.notSet }}</div>
		<MkInput v-model="form.state.apiKey" type="password" autocomplete="new-password" :ariaLabel="i18n.ts._urlPreviewSetting.xriftApiKey" :disabled="form.state.removeKey">
			<template #label>{{ i18n.ts._urlPreviewSetting.xriftApiKey }}</template>
			<template #caption>{{ i18n.ts._urlPreviewSetting.xriftApiKeyDescription }}</template>
		</MkInput>
		<label v-if="keyConfigured"><input v-model="form.state.removeKey" type="checkbox"> {{ i18n.ts._urlPreviewSetting.xriftRemoveKey }}</label>
		<MkInfo warn>{{ i18n.ts._urlPreviewSetting.xriftTermsNotice }}</MkInfo>
		<div class="_gaps_s">
			<a class="_link" href="https://docs.xrift.net/public-api/v1" target="_blank" rel="noopener noreferrer">{{ i18n.ts._urlPreviewSetting.xriftApiDocs }}</a>
			<a class="_link" href="https://xrift.net/terms" target="_blank" rel="noopener noreferrer">{{ i18n.ts.termsOfService }}</a>
		</div>
	</div>
</MkFolder>
</template>

<script lang="ts" setup>
import MkFolder from '@/components/MkFolder.vue';
import MkFormFooter from '@/components/MkFormFooter.vue';
import MkInput from '@/components/MkInput.vue';
import MkInfo from '@/components/MkInfo.vue';
import { useForm } from '@/composables/use-form.js';
import { i18n } from '@/i18n.js';
import * as os from '@/os.js';

const keyConfigured = defineModel<boolean>('configured', { required: true });
const form = useForm({ apiKey: '', removeKey: false }, async (state) => {
	const apiKey = state.removeKey ? null : state.apiKey.trim();
	if (!state.removeKey && !apiKey) return;
	await os.apiWithDialog('admin/update-meta', { xriftApiKey: apiKey });
	keyConfigured.value = apiKey != null;
	form.state.apiKey = '';
	form.state.removeKey = false;
});
</script>
