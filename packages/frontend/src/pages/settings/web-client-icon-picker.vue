<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<fieldset :class="$style.root" :aria-describedby="`${id}-caption`">
	<legend :class="$style.legend"><SearchLabel>{{ i18n.ts._webClientIcon.title }}</SearchLabel></legend>
	<p :id="`${id}-caption`" :class="$style.caption"><SearchText>{{ i18n.ts._webClientIcon.description }}</SearchText></p>
	<div :class="$style.choices">
		<label v-for="option in options" :key="option.value" :class="[$style.choice, { [$style.selected]: selection === option.value }]">
			<input v-model="selection" type="radio" :name="id" :value="option.value" :class="$style.radio">
			<i v-if="option.value === 'random'" class="ti ti-arrows-shuffle" :class="$style.preview" aria-hidden="true"></i>
			<img v-else :src="`/client-assets/gridspace/client-icons/${option.value}.png`" :class="$style.preview" alt="">
			<span :class="$style.label">{{ option.label }}</span>
		</label>
	</div>
</fieldset>
</template>

<script lang="ts" setup>
import { computed, useId } from 'vue';
import type { WebClientIconPreference } from '@/utility/web-client-icon.js';
import { normalizeWebClientIconPreference, webClientIconNames } from '@/utility/web-client-icon.js';
import { i18n } from '@/i18n.js';

const model = defineModel<WebClientIconPreference>({ required: true });
const selection = computed({
	get: () => normalizeWebClientIconPreference(model.value),
	set: (value: WebClientIconPreference) => { model.value = value; },
});
const id = useId();
const authors = { sakami: '@sakami', tekerets: '@tekerets', sharuya: '@SHaruya', machiyoh: '@machiyoh', ningen: '@ningen' };
const options = computed(() => [
	{ value: 'random' as const, label: i18n.ts.random },
	...webClientIconNames.map(value => ({ value, label: i18n.tsx._webClientIcon.artworkBy({ name: authors[value] }) })),
]);
</script>

<style lang="scss" module>
.root {
	min-width: 0;
	margin: 0;
	padding: 0;
	border: 0;
}

.legend {
	padding: 0;
	font-size: 0.85em;
}

.caption {
	margin: 8px 0 12px;
	font-size: 0.85em;
	color: var(--MI_THEME-fg);
	opacity: 0.75;
}

.choices {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(116px, 1fr));
	gap: 8px;
}

.choice {
	position: relative;
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 8px;
	padding: 16px 8px 12px;
	border: 2px solid var(--MI_THEME-divider);
	border-radius: var(--MI-radius);
	cursor: pointer;

	&:hover {
		background: var(--MI_THEME-panelHighlight);
	}

	&:has(input:focus-visible) {
		outline: 2px solid var(--MI_THEME-accent);
		outline-offset: 2px;
	}
}

.selected {
	border-color: var(--MI_THEME-accent);
}

.radio {
	position: absolute;
	top: 8px;
	left: 8px;
	margin: 0;
	accent-color: var(--MI_THEME-accent);
}

.preview {
	display: block;
	width: 48px;
	height: 48px;
	object-fit: contain;
	font-size: 40px;
	line-height: 48px;
	text-align: center;
}

.label {
	font-size: 0.8em;
	text-align: center;
	overflow-wrap: anywhere;
}
</style>
