<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<MkContainer :showHeader="widgetProps.showHeader">
	<template #icon><i class="ti ti-walk"></i></template>
	<template #header>{{ i18n.ts._widgets.avatarWalk }}</template>
	<MkAvatarWalkGame compact/>
	<div :class="$style.footer">
		<MkButton small full @click="openInWindow">
			<i class="ti ti-app-window"></i> {{ i18n.ts.openInWindow }}
		</MkButton>
	</div>
</MkContainer>
</template>

<script lang="ts" setup>
import { useWidgetPropsManager } from './widget.js';
import type { WidgetComponentEmits, WidgetComponentExpose, WidgetComponentProps } from './widget.js';
import type { FormWithDefault, GetFormResultType } from '@/utility/form.js';
import MkButton from '@/components/MkButton.vue';
import MkAvatarWalkGame from '@/components/MkAvatarWalkGame.vue';
import MkContainer from '@/components/MkContainer.vue';
import { i18n } from '@/i18n.js';
import * as os from '@/os.js';

const name = 'avatarWalk';

const widgetPropsDef = {
	showHeader: {
		type: 'boolean',
		label: i18n.ts._widgetOptions.showHeader,
		default: true,
	},
} satisfies FormWithDefault;

type WidgetProps = GetFormResultType<typeof widgetPropsDef>;

const props = defineProps<WidgetComponentProps<WidgetProps>>();
const emit = defineEmits<WidgetComponentEmits<WidgetProps>>();

const { widgetProps, configure } = useWidgetPropsManager(name,
	widgetPropsDef,
	props,
	emit,
);

function openInWindow(): void {
	os.pageWindow('/avatar-walk');
}

defineExpose<WidgetComponentExpose>({
	name,
	configure,
	get id() {
		return props.widget?.id ?? null;
	},
});
</script>

<style lang="scss" module>
.footer {
	padding: 10px;
	border-top: 1px solid var(--MI_THEME-divider);
}
</style>
