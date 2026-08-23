<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader>
	<div class="_spacer" style="--MI_SPACER-w: 960px;">
		<div :class="$style.root" class="_panel">
			<MkAvatarWalkGame/>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import MkAvatarWalkGame from '@/components/MkAvatarWalkGame.vue';
import { i18n } from '@/i18n.js';
import { definePage } from '@/page.js';

definePage(() => ({
	title: i18n.ts.avatarWalkGame,
	icon: 'ti ti-walk',
}));
</script>

<style lang="scss" module>
.root {
	max-width: 960px;
	margin: 0 auto;
}
</style>
