<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader>
	<div class="_spacer" style="--MI_SPACER-w: 700px; --MI_SPACER-min: 16px; --MI_SPACER-max: 32px;">
		<div class="_gaps_m">
			<MkInfo>
				<div class="_gaps_s">
					<strong>{{ i18n.ts._autoTranslation.providerCredit }}</strong>
					<div>{{ i18n.ts._autoTranslation.adminDescription }}</div>
					<div><MkLink url="https://huggingface.co/pfnet/plamo-3-translate-0.8b">{{ i18n.ts._autoTranslation.aboutProvider }}</MkLink></div>
				</div>
			</MkInfo>
			<MkSwitch v-model="config.enabled">{{ i18n.ts._autoTranslation.enableServer }}</MkSwitch>
			<MkInput v-model="config.baseUrl" type="url">
				<template #label>{{ i18n.ts._autoTranslation.baseUrl }}</template>
				<template #caption>{{ i18n.ts._autoTranslation.baseUrlDescription }}</template>
			</MkInput>
			<MkInput v-model="config.model"><template #label>{{ i18n.ts._autoTranslation.model }}</template></MkInput>
			<MkInput v-model="apiKey" type="password" autocomplete="new-password">
				<template #label>{{ i18n.ts._autoTranslation.apiKey }}</template>
				<template #caption>{{ config.apiKeyConfigured ? i18n.ts._autoTranslation.keyConfigured : i18n.ts._autoTranslation.keyNotConfigured }}</template>
			</MkInput>
			<MkSwitch v-model="clearKey">{{ i18n.ts._autoTranslation.clearKey }}</MkSwitch>
			<MkSwitch v-model="config.allowPrivateNetwork">
				{{ i18n.ts._autoTranslation.allowPrivateNetwork }}
				<template #caption>{{ i18n.ts._autoTranslation.privateNetworkDescription }}</template>
			</MkSwitch>
			<MkInput v-model="config.maxConcurrency" type="number" :min="1" :max="16"><template #label>{{ i18n.ts._autoTranslation.maxConcurrency }}</template></MkInput>
			<div class="_buttons">
				<MkButton primary :disabled="busy" @click="save">{{ i18n.ts.save }}</MkButton>
				<MkButton :disabled="busy" @click="testConnection">{{ i18n.ts._autoTranslation.saveAndTest }}</MkButton>
			</div>
		</div>
	</div>
</PageWithHeader>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue';
import MkButton from '@/components/MkButton.vue';
import MkInfo from '@/components/MkInfo.vue';
import MkInput from '@/components/MkInput.vue';
import MkLink from '@/components/MkLink.vue';
import MkSwitch from '@/components/MkSwitch.vue';
import { misskeyApi } from '@/utility/misskey-api.js';
import { i18n } from '@/i18n.js';
import { definePage } from '@/page.js';
import * as os from '@/os.js';

const config = reactive(await misskeyApi('admin/auto-translation/get-config'));
const apiKey = ref('');
const clearKey = ref(false);
const busy = ref(false);

async function persist() {
	const { apiKeyConfigured: _configured, ...settings } = config;
	const saved = await misskeyApi('admin/auto-translation/update-config', {
		...settings, ...(clearKey.value ? { apiKey: null } : apiKey.value ? { apiKey: apiKey.value } : {}),
	});
	Object.assign(config, saved);
	apiKey.value = '';
	clearKey.value = false;
}

async function save() {
	busy.value = true;
	try {
		await persist();
		os.success();
	} catch (err) {
		os.alert({ type: 'error', text: i18n.ts._autoTranslation.configFailed });
	} finally {
		busy.value = false;
	}
}

async function testConnection() {
	busy.value = true;
	try {
		await persist();
		await misskeyApi('admin/auto-translation/test-connection');
		os.alert({ type: 'success', text: i18n.ts._autoTranslation.connectionSucceeded });
	} catch {
		os.alert({ type: 'error', text: i18n.ts._autoTranslation.connectionFailed });
	} finally {
		busy.value = false;
	}
}

definePage(() => ({ title: i18n.ts._autoTranslation.title, icon: 'ti ti-language' }));
</script>
