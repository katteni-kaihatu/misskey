<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div class="_gaps_m">
	<MkInfo>{{ i18n.ts._autoTranslation.description }}</MkInfo>
	<MkInfo v-if="!capability.available" warn>{{ i18n.ts._autoTranslation.unavailable }}</MkInfo>
	<MkSwitch v-model="enabled" :disabled="!capability.available && !enabled">{{ i18n.ts._autoTranslation.enableClient }}</MkSwitch>
	<MkSelect v-model="targetLang" :items="languages"><template #label>{{ i18n.ts._autoTranslation.targetLang }}</template></MkSelect>
</div>
</template>

<script setup lang="ts">
import MkInfo from '@/components/MkInfo.vue';
import MkSelect from '@/components/MkSelect.vue';
import MkSwitch from '@/components/MkSwitch.vue';
import { getAutoTranslationCapabilities } from '@/utility/auto-translation.js';
import { prefer } from '@/preferences.js';
import { i18n } from '@/i18n.js';
import { definePage } from '@/page.js';

const capability = await getAutoTranslationCapabilities(true);
const enabled = prefer.model('autoTranslation.enabled');
const targetLang = prefer.model('autoTranslation.targetLang');
const displayNames = new Intl.DisplayNames([navigator.language], { type: 'language' });
const languages = capability.languages.map(value => ({ value, label: displayNames.of(value) ?? value }));

definePage(() => ({ title: i18n.ts._autoTranslation.title, icon: 'ti ti-language' }));
</script>
