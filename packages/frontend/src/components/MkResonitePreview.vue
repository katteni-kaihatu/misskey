<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div :class="$style.root">
	<article :class="[$style.card, { [$style.live]: availableSession, [$style.full]: full }]" :aria-busy="loading">
		<div :class="$style.brand" role="img" aria-label="Resonite">
			<img :class="$style.wordmark" src="/client-assets/resonite/logo-white.svg" alt="" aria-hidden="true"/>
			<img :class="$style.symbol" src="/client-assets/resonite/symbol.svg" alt="" aria-hidden="true"/>
		</div>
		<div :class="[$style.visual, { [$style.placeholder]: !imageVisible }]">
			<MkPanorama v-if="imageVisible" :src="summary!.thumbnail!" :alt="summary?.title ?? ''" @error="imageFailed = true"/>
			<i v-if="!loading && state !== 'available'" :class="['ti', state === 'error' ? 'ti-alert-circle' : 'ti-world-off', $style.stateIcon]" aria-hidden="true"></i>
			<span v-if="availableSession && data?.currentUsers != null" :class="$style.occupancy"><i class="ti ti-users" aria-hidden="true"></i>{{ data.maxUsers != null ? i18n.tsx._resonitePreview.participants({ current: format(data.currentUsers), max: format(data.maxUsers) }) : i18n.tsx._resonitePreview.currentParticipants({ count: format(data.currentUsers) }) }}</span>
		</div>
		<div :class="$style.body">
			<img v-if="imageVisible" :class="$style.backdrop" :src="summary?.thumbnail ?? undefined" alt="" aria-hidden="true" loading="lazy" @error="imageFailed = true"/>
			<template v-if="loading">
				<span :class="$style.srOnly" role="status">{{ i18n.ts.loading }}</span>
				<div :class="[$style.skeleton, $style.skeletonType]"></div>
				<div :class="[$style.skeleton, $style.skeletonTitle]"></div>
				<div :class="$style.skeleton"></div>
				<div :class="[$style.skeleton, $style.skeletonButton]"></div>
			</template>
			<template v-else>
				<div :class="$style.labels">
					<span :class="[$style.type, { [$style.sessionType]: availableSession }]"><i :class="['ti', type === 'world' ? 'ti-world' : 'ti-users']" aria-hidden="true"></i>{{ type === 'world' ? i18n.ts._resonitePreview.world : i18n.ts._resonitePreview.session }}</span>
					<span v-if="full" :class="[$style.status, $style.fullStatus]">{{ i18n.ts._resonitePreview.full }}</span>
					<span v-else-if="state === 'available' && data?.featured" :class="[$style.status, $style.featured]"><i class="ti ti-star" aria-hidden="true"></i>{{ i18n.ts._resonitePreview.featured }}</span>
				</div>
				<h3 :class="$style.title">
					<template v-if="state === 'available' && data?.titleParts?.length"><span v-for="(part, index) in data.titleParts" :key="index" :style="{ color: readableResoniteColor(part.color) }">{{ part.text }}</span></template>
					<template v-else>{{ heading }}</template>
				</h3>
				<p v-if="state === 'available' && metadata" :class="$style.meta">{{ metadata }}</p>
				<p v-if="description" :class="[$style.description, { [$style.stateMessage]: state !== 'available' }]">{{ description }}</p>
				<div :class="$style.actions">
					<a :href="primaryUrl" :target="primaryUrl.startsWith('https:') ? '_blank' : undefined" :class="[$style.button, { [$style.primary]: state === 'available' }]" rel="nofollow noopener">{{ primaryLabel }}</a>
					<a v-if="state === 'available'" :href="link?.url ?? url" target="_blank" rel="nofollow noopener" :class="[$style.button, $style.secondary]">{{ i18n.ts._resonitePreview.viewWeb }}</a>
				</div>
			</template>
		</div>
	</article>
</div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import type { SummalyResult } from '@misskey-dev/summaly';
import type { ResonitePreview } from 'misskey-js';
import { useLowresTime } from '@@/js/use-lowres-time.js';
import { i18n } from '@/i18n.js';
import { prefer } from '@/preferences.js';
import { getResoniteLink } from '@/utility/resonite-link.js';
import { readableResoniteColor } from '@/utility/resonite-text.js';
import MkPanorama from '@/components/MkPanorama.vue';

const props = defineProps<{
	url: string;
	type: 'world' | 'session';
	summary: (SummalyResult & { resonite?: ResonitePreview }) | null;
	loading: boolean;
	failed: boolean;
}>();
const link = computed(() => getResoniteLink(props.url));
const data = computed(() => props.summary?.resonite);
const state = computed(() => props.failed ? 'error' : data.value?.state ?? 'available');
const availableSession = computed(() => props.type === 'session' && state.value === 'available' && !props.loading);
const full = computed(() => availableSession.value && data.value?.currentUsers != null && data.value.maxUsers != null && data.value.maxUsers > 0 && data.value.currentUsers >= data.value.maxUsers);
const worldLink = computed(() => data.value?.worldUrl ? getResoniteLink(data.value.worldUrl) : null);
const imageFailed = ref(false);
const imageVisible = computed(() => state.value === 'available' && !props.loading && !imageFailed.value && !!props.summary?.thumbnail && !props.summary.sensitive && !prefer.s.dataSaver.urlPreviewThumbnail);
const format = (value: number): string => value.toLocaleString();
const now = useLowresTime();
const metadata = computed(() => {
	const result: string[] = [];
	if (data.value?.creator) result.push(props.type === 'session' ? i18n.tsx._resonitePreview.host({ name: data.value.creator }) : data.value.creator);
	if (props.type === 'world' && data.value?.visits != null) result.push(i18n.tsx._resonitePreview.visits({ count: format(data.value.visits) }));
	const created = data.value?.createdAt ? Date.parse(data.value.createdAt) : NaN;
	if (availableSession.value && Number.isFinite(created)) {
		const minutes = Math.max(0, Math.floor((now.value - created) / 60_000));
		const time = minutes < 60 ? i18n.tsx._xriftPreview.minutes({ count: format(minutes) }) : i18n.tsx._xriftPreview.hoursMinutes({ hours: format(Math.floor(minutes / 60)), minutes: format(minutes % 60) });
		result.push(i18n.tsx._xriftPreview.startedAgo({ time }));
	}
	const updated = data.value?.updatedAt ? Date.parse(data.value.updatedAt) : NaN;
	if (props.type === 'world' && Number.isFinite(updated)) result.push(i18n.tsx._resonitePreview.updated({ date: new Date(updated).toLocaleDateString(undefined, { month: 'numeric', day: 'numeric' }) }));
	return result.join(' · ');
});
const heading = computed(() => state.value === 'error' ? i18n.ts._resonitePreview.error : state.value === 'ended' ? i18n.ts._resonitePreview.ended : state.value === 'unavailable' ? (props.type === 'world' ? i18n.ts._resonitePreview.worldUnavailable : i18n.ts._resonitePreview.sessionUnavailable) : props.summary?.title ?? 'Resonite');
const description = computed(() => state.value === 'error' ? i18n.ts._resonitePreview.openDirectly : state.value === 'ended' ? i18n.ts._resonitePreview.endedDescription : state.value === 'unavailable' ? i18n.ts._resonitePreview.unavailableDescription : props.summary?.description);
const primaryUrl = computed(() => ((full.value || state.value === 'ended') && worldLink.value ? worldLink.value.launchUrl : state.value === 'available' ? link.value?.launchUrl : link.value?.url) ?? props.url);
const primaryLabel = computed(() => (full.value || state.value === 'ended') && worldLink.value ? i18n.ts._resonitePreview.openWorld : state.value !== 'available' ? i18n.ts._resonitePreview.viewWeb : props.type === 'session' ? i18n.ts._resonitePreview.join : i18n.ts._resonitePreview.open);
</script>

<style lang="scss" module>
.root {
	--resonite-dark: #11151d;
	--resonite-panel: #2b2f35;
	--resonite-fg: #ffffff;
	--resonite-muted: #c4c6c8;
	--resonite-green: #59eb5c;
	--resonite-yellow: #f8f770;
	--resonite-red: #ff7676;
	--resonite-purple: #ba64f2;
	--resonite-cyan: #61d1fa;
	--resonite-orange: #e69e50;
	--resonite-border: color-mix(in srgb, var(--resonite-fg) 22%, transparent);
	container-type: inline-size;
	color: var(--resonite-fg);
}
.card { position: relative; display: grid; grid-template-columns: 45% minmax(0, 1fr); aspect-ratio: 20 / 9; border: 1px solid var(--resonite-border); border-radius: var(--MI-radius); overflow: hidden; background: var(--resonite-panel); font-size: 14px; box-sizing: border-box; &.live { border-color: var(--resonite-green); } &.full { border-color: var(--resonite-border); } }
.brand { position: absolute; right: 0; top: 0; z-index: 2; padding: 9px 12px 10px; border-bottom-left-radius: 12px; background: var(--resonite-dark); &::after { content: ''; position: absolute; bottom: 0; left: 0; right: 0; height: 3px; background: linear-gradient(90deg, var(--resonite-yellow), var(--resonite-green), var(--resonite-cyan), var(--resonite-purple), var(--resonite-red), var(--resonite-orange)); } }
.wordmark { display: block; width: 94px; height: auto; }
.symbol { display: none; }
.visual { position: relative; min-width: 0; min-height: 0; background: var(--resonite-dark); > img { width: 100%; height: 100%; object-fit: cover; display: block; } }
.placeholder { background: repeating-linear-gradient(135deg, var(--resonite-dark), var(--resonite-dark) 12px, color-mix(in srgb, var(--resonite-fg) 7%, var(--resonite-dark)) 12px, color-mix(in srgb, var(--resonite-fg) 7%, var(--resonite-dark)) 13px); }
.stateIcon { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-size: 32px; color: var(--resonite-muted); }
.occupancy { position: absolute; left: 10px; bottom: 10px; display: flex; align-items: center; gap: 6px; padding: 5px 9px; border: 1px solid var(--resonite-border); border-radius: 999px; background: var(--resonite-dark); font-size: 12px; font-weight: bold; }
.body { position: relative; isolation: isolate; min-width: 0; display: flex; flex-direction: column; gap: 8px; padding: 18px 20px; overflow: hidden; }
.backdrop { position: absolute; z-index: -1; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0.14; filter: blur(3px); mask-image: linear-gradient(to right, black, transparent 95%); pointer-events: none; }
.labels { display: flex; align-items: center; gap: 6px; flex-shrink: 0; padding-right: 100px; }
.type, .status { display: inline-flex; align-items: center; flex-shrink: 0; gap: 5px; border-radius: 6px; padding: 3px 8px; font-size: 12px; font-weight: bold; white-space: nowrap; }
.type { border: 1px solid var(--resonite-border); background: color-mix(in srgb, var(--resonite-fg) 12%, var(--resonite-panel)); }
.sessionType { background: var(--resonite-green); color: var(--resonite-dark); border-color: transparent; }
.featured { color: var(--resonite-yellow); background: var(--resonite-dark); }
.fullStatus { color: var(--resonite-dark); background: var(--resonite-red); }
.title { flex-shrink: 0; margin: 2px 0 0; font-size: 1.45em; line-height: 1.35; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; }
.meta { flex-shrink: 0; margin: 0; font-size: 0.83em; color: var(--resonite-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.description { min-height: 0; margin: 0; font-size: 0.9em; line-height: 1.55; white-space: pre-line; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; }
.actions { margin-top: auto; display: flex; flex-shrink: 0; gap: 8px; padding-top: 4px; }
.button { display: flex; align-items: center; justify-content: center; flex: 1; min-width: 0; min-height: 44px; box-sizing: border-box; padding: 7px 10px; border: 1px solid var(--resonite-border); border-radius: 999px; color: inherit; text-align: center; font-size: 0.85em; font-weight: bold; &:hover { text-decoration: none; background: color-mix(in srgb, var(--resonite-fg) 12%, var(--resonite-panel)); } &:focus-visible { outline: 2px solid var(--resonite-cyan); outline-offset: 2px; } }
.primary { background: var(--resonite-fg); border-color: transparent; color: var(--resonite-dark); &:hover { background: var(--resonite-muted); } }
.secondary { flex: 0 0 auto; }
.skeleton { flex-shrink: 0; height: 12px; border-radius: 4px; width: 80%; background: color-mix(in srgb, var(--resonite-fg) 14%, var(--resonite-panel)); }
.skeletonType { width: 25%; height: 20px; }
.skeletonTitle { width: 90%; height: 24px; }
.skeletonButton { margin-top: auto; width: 100%; height: 44px; border-radius: 999px; }
.srOnly { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
@container (min-width: 700px) { .description { -webkit-line-clamp: 4; } }
@container (max-width: 640px) {
	.body { padding: 16px; gap: 6px; }
	.title { font-size: 1.2em; }
	.description { font-size: 0.83em; line-height: 1.4; }
	.wordmark { width: 76px; }
	.labels { padding-right: 82px; }
}
@container (max-width: 560px) {
	.brand { padding: 6px 8px 8px; }
	.wordmark { width: 65px; }
	.labels { padding-right: 68px; }
	.type { padding: 2px 6px; font-size: 11px; }
	.status { padding: 2px 5px; gap: 3px; font-size: 10px; }
	.secondary { padding: 4px 6px; border-color: transparent; font-size: 10px; text-decoration: underline; }
}
@container (max-width: 420px) {
	.card { grid-template-columns: 35% minmax(0, 1fr); font-size: 12px; }
	.body { padding: 10px 12px; gap: 4px; }
	.brand { padding: 5px 7px 7px; border-bottom-left-radius: 9px; }
	.wordmark { display: none; }
	.symbol { display: block; width: 18px; height: 18px; }
	.labels { padding-right: 26px; }
	.type { font-size: 10px; > i { display: none; } }
	.status { font-size: 10px; padding: 2px 5px; }
	.title { font-size: 1.2em; -webkit-line-clamp: 1; }
	.meta { font-size: 0.78em; }
	.description:not(.stateMessage) { display: none; }
	.button { min-height: 40px; }
	.occupancy { left: 6px; bottom: 6px; padding: 3px 6px; font-size: 10px; gap: 4px; }
}
@container (max-width: 320px) { .body { padding: 8px; gap: 3px; } }
</style>
