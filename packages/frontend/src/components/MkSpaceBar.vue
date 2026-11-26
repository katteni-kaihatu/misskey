<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div v-if="session.status === 'joined' && session.space != null && session.pageSpaceId !== session.space.id" :class="$style.root" class="_panel _shadow">
	<MkA :to="`/spaces/${session.space.id}`" :class="$style.main" :aria-label="i18n.ts._spaces.backToSpace">
		<i class="ti ti-broadcast" :class="$style.icon"></i>
		<div :class="$style.text">
			<div :class="$style.name">{{ session.space.name }}</div>
			<div :class="$style.sub">{{ i18n.ts._spaces.inSpace }} · {{ i18n.tsx._spaces.memberCount({ n: session.members.length }) }}</div>
		</div>
	</MkA>
	<button
		class="_button"
		:class="[$style.button, { [$style.active]: session.mode === 'voice' }]"
		:disabled="session.callStatus !== 'connected'"
		:aria-label="session.mode === 'voice' ? i18n.ts._spaces.micOff : i18n.ts._spaces.micOn"
		:title="session.mode === 'voice' ? i18n.ts._spaces.micOff : i18n.ts._spaces.micOn"
		@click="toggleSpaceMicrophone()"
	>
		<i :class="session.mode === 'voice' ? 'ti ti-microphone' : 'ti ti-microphone-off'"></i>
	</button>
	<button class="_button" :class="[$style.button, $style.leave]" :aria-label="i18n.ts._spaces.leave" :title="i18n.ts._spaces.leave" @click="leaveSpace()">
		<i class="ti ti-door-exit"></i>
	</button>
</div>
</template>

<script lang="ts" setup>
import { i18n } from '@/i18n.js';
import { leaveSpace, spaceSession as session, toggleSpaceMicrophone } from '@/utility/space-session.js';
</script>

<style lang="scss" module>
.root {
	position: fixed;
	z-index: 1000;
	left: 50%;
	bottom: calc(env(safe-area-inset-bottom, 0px) + 72px);
	transform: translateX(-50%);
	display: flex;
	align-items: center;
	gap: 4px;
	width: min(360px, calc(100vw - 24px));
	padding: 6px 8px 6px 12px;
	border: solid 1px var(--MI_THEME-divider);
	border-radius: 999px;
}

.main {
	flex: 1;
	min-width: 0;
	display: flex;
	align-items: center;
	gap: 10px;
	color: var(--MI_THEME-fg);
	text-decoration: none;

	&:hover {
		text-decoration: none;
	}
}

.icon {
	flex-shrink: 0;
	color: var(--MI_THEME-accent);
	font-size: 20px;
}

.text {
	min-width: 0;
}

.name {
	font-weight: bold;
	font-size: 0.9em;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.sub {
	font-size: 0.75em;
	opacity: 0.7;
}

.button {
	flex-shrink: 0;
	display: flex;
	align-items: center;
	justify-content: center;
	width: 38px;
	height: 38px;
	border-radius: 100%;
	background: var(--MI_THEME-buttonBg);

	&:hover {
		background: var(--MI_THEME-buttonHoverBg);
	}

	&:disabled {
		opacity: 0.5;
	}
}

.active {
	background: var(--MI_THEME-accent);
	color: var(--MI_THEME-fgOnAccent);

	&:hover {
		background: var(--MI_THEME-accent);
	}
}

.leave {
	color: var(--MI_THEME-error);
}
</style>
