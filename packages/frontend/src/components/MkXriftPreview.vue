<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div :class="$style.root">
	<article :class="[$style.card, { [$style.profileSize]: type === 'user', [$style.profile]: type === 'user' && state === 'available' && !loading, [$style.live]: isLive }]" :aria-busy="loading">
		<template v-if="type === 'user' && state === 'available' && !loading">
			<div :class="$style.profileHeading">
				<div :class="$style.avatar">
					<img v-if="imageVisible" :src="summary?.thumbnail ?? undefined" :alt="summary?.title ?? ''" loading="lazy" @error="imageFailed = true"/>
					<i v-else class="ti ti-user" aria-hidden="true"></i>
				</div>
				<div :class="$style.profileIdentity">
					<span :class="$style.brand">XRIFT</span>
					<h3 :class="$style.title">{{ summary?.title }}</h3>
					<p v-if="joinedAt" :class="$style.meta">{{ i18n.tsx._xriftPreview.joinedAt({ date: joinedAt }) }}</p>
				</div>
				<a :href="url" target="_blank" rel="nofollow noopener" :class="[$style.button, $style.primary, $style.profileAction]">{{ i18n.ts._xriftPreview.viewProfile }}</a>
			</div>
			<div v-if="data?.totalWorlds != null && data.totalWorlds > 0" :class="$style.worlds">
				<div :class="$style.worldsHeader">
					<p :class="$style.worldCount">{{ i18n.ts._xriftPreview.publicWorlds }} <strong>{{ format(data.totalWorlds) }}</strong></p>
					<div v-if="(data.worlds?.length ?? 0) > 3" :class="$style.scrollActions">
						<button class="_button" :class="$style.scrollButton" :aria-label="i18n.ts._xriftPreview.previousWorlds" :disabled="!canScrollLeft" @click="scrollWorlds(-1)"><i class="ti ti-chevron-left" aria-hidden="true"></i></button>
						<button class="_button" :class="$style.scrollButton" :aria-label="i18n.ts._xriftPreview.nextWorlds" :disabled="!canScrollRight" @click="scrollWorlds(1)"><i class="ti ti-chevron-right" aria-hidden="true"></i></button>
					</div>
				</div>
				<div v-if="data.worlds?.length" ref="worldScroller" :class="$style.worldGrid" role="region" :aria-label="i18n.ts._xriftPreview.publicWorlds" tabindex="0" @scroll.passive="updateWorldScrollState" @keydown.left.prevent="scrollWorlds(-1)" @keydown.right.prevent="scrollWorlds(1)">
					<a v-for="world in data.worlds" :key="world.url" :href="world.url" :aria-label="world.title" target="_blank" rel="nofollow noopener" :class="$style.worldLink">
						<div :class="$style.worldImage">
							<img v-if="world.thumbnail && !hideImages" :src="world.thumbnail" alt="" loading="lazy" @error="hideFailedImage"/>
						</div>
						<span>{{ world.title }}</span>
					</a>
				</div>
			</div>
		</template>
		<template v-else>
			<div :class="[$style.visual, { [$style.placeholder]: !imageVisible || state !== 'available' || loading }]">
				<img v-if="imageVisible && state === 'available' && !loading" :src="summary?.thumbnail ?? undefined" :alt="summary?.title ?? ''" loading="lazy" @error="imageFailed = true"/>
				<span v-if="isLive" :class="[$style.badge, $style.liveBadge]"><span :class="$style.dot"></span>{{ i18n.ts._xriftPreview.live }}</span>
				<span v-else-if="state === 'available' && !loading && data?.publicInstances" :class="$style.badge"><span :class="$style.dot"></span>{{ i18n.tsx._xriftPreview.roomsOpen({ count: format(data.publicInstances) }) }}</span>
				<span v-if="!loading && state !== 'available'" :class="$style.visualIcon" aria-hidden="true"><i :class="['ti', state === 'error' ? 'ti-alert-circle' : type === 'user' ? 'ti-user-off' : 'ti-lock']"></i></span>
				<div v-if="isLive && elapsed" :class="$style.elapsed"><small>{{ i18n.ts._xriftPreview.started }}</small><strong>{{ elapsed }}</strong></div>
			</div>
			<div :class="$style.body">
				<template v-if="loading">
					<span :class="$style.srOnly" role="status">{{ i18n.ts.loading }}</span>
					<div :class="[$style.skeleton, $style.skeletonBrand]"></div>
					<div :class="[$style.skeleton, $style.skeletonTitle]"></div>
					<div :class="[$style.skeleton, $style.skeletonText]"></div>
					<div :class="[$style.skeleton, $style.skeletonButton]"></div>
				</template>
				<template v-else>
					<div :class="$style.brandRow"><span :class="$style.brand">XRIFT</span><span :class="$style.type">{{ typeLabel }}</span></div>
					<p v-if="isLive" :class="$style.invitation">{{ i18n.ts._xriftPreview.invitation }}</p>
					<h3 :class="$style.title">{{ heading }}</h3>
					<p v-if="state === 'available' && (data?.creator || data?.totalVisits != null)" :class="$style.meta">
						<span v-if="data.creator">{{ data.creator }}</span><span v-if="data.creator && data.totalVisits != null" aria-hidden="true"> · </span><span v-if="data.totalVisits != null">{{ i18n.tsx._xriftPreview.visits({ count: format(data.totalVisits) }) }}</span>
					</p>
					<p v-if="message" :class="[$style.description, { [$style.stateMessage]: state !== 'available' }]">{{ message }}</p>
					<dl v-if="type === 'world' && state === 'available' && hasStats" :class="$style.stats">
						<div v-if="data?.totalVisits != null"><dt>{{ i18n.ts._xriftPreview.totalVisits }}</dt><dd>{{ format(data.totalVisits) }}</dd></div>
						<div v-if="data?.visitsLast7Days != null"><dt>{{ i18n.ts._xriftPreview.last7Days }}</dt><dd>{{ format(data.visitsLast7Days) }}</dd></div>
						<div v-if="data?.publicInstances != null"><dt>{{ i18n.ts._xriftPreview.publicRooms }}</dt><dd>{{ format(data.publicInstances) }}</dd></div>
					</dl>
					<div :class="$style.actions">
						<a :href="url" target="_blank" rel="nofollow noopener" :class="[$style.button, { [$style.primary]: state === 'available' }]">{{ actionLabel }}</a>
						<a v-if="isLive && data?.worldUrl" :href="data.worldUrl" target="_blank" rel="nofollow noopener" :class="[$style.button, $style.secondary]">{{ i18n.ts._xriftPreview.viewWorld }}</a>
					</div>
				</template>
			</div>
		</template>
	</article>
</div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useLowresTime } from '@@/js/use-lowres-time.js';
import type { SummalyResult } from '@misskey-dev/summaly';
import type { XriftPreview } from 'misskey-js';
import { i18n } from '@/i18n.js';
import { prefer } from '@/preferences.js';

const props = defineProps<{
	url: string;
	type: XriftPreview['type'];
	summary: (SummalyResult & { xrift?: XriftPreview }) | null;
	loading: boolean;
	failed: boolean;
}>();
const data = computed(() => props.summary?.xrift);
const worldScroller = ref<HTMLElement | null>(null);
const canScrollLeft = ref(false);
const canScrollRight = ref(false);
watch(worldScroller, (element, _, onCleanup) => {
	updateWorldScrollState();
	if (!element || typeof ResizeObserver === 'undefined') return;
	const observer = new ResizeObserver(updateWorldScrollState);
	observer.observe(element);
	onCleanup(() => observer.disconnect());
}, { flush: 'post' });
watch(() => data.value?.worlds, updateWorldScrollState, { flush: 'post' });

function updateWorldScrollState(): void {
	const element = worldScroller.value;
	canScrollLeft.value = !!element && element.scrollLeft > 1;
	canScrollRight.value = !!element && element.scrollLeft + element.clientWidth < element.scrollWidth - 1;
}

function scrollWorlds(direction: number): void {
	worldScroller.value?.scrollBy({ left: direction * worldScroller.value.clientWidth });
}

const state = computed(() => props.failed ? 'error' : data.value?.state ?? 'available');
const isLive = computed(() => props.type === 'instance' && state.value === 'available' && data.value != null && !props.loading);
const hideImages = computed(() => props.summary?.sensitive === true || prefer.s.dataSaver.urlPreviewThumbnail);
const imageFailed = ref(false);
const imageVisible = computed(() => !hideImages.value && !imageFailed.value && Boolean(props.summary?.thumbnail));
const format = (value: number): string => value.toLocaleString();
const typeLabel = computed(() => props.type === 'world' ? i18n.ts._xriftPreview.world : props.type === 'instance' ? i18n.ts._xriftPreview.room : i18n.ts._xriftPreview.user);
const hasStats = computed(() => data.value?.totalVisits != null || data.value?.visitsLast7Days != null || data.value?.publicInstances != null);
const heading = computed(() => {
	if (state.value === 'error') return i18n.ts._xriftPreview.error;
	if (state.value === 'unavailable') return props.type === 'world' ? i18n.ts._xriftPreview.worldUnavailable : props.type === 'instance' ? i18n.ts._xriftPreview.roomUnavailable : i18n.ts._xriftPreview.userUnavailable;
	return props.summary?.title ?? 'XRift';
});
const message = computed(() => {
	if (state.value === 'error') return i18n.ts._xriftPreview.openDirectly;
	if (state.value === 'unavailable') return props.type === 'instance' ? i18n.ts._xriftPreview.roomUnavailableDescription : i18n.ts._xriftPreview.unavailableDescription;
	if (props.type === 'world' && data.value?.publicInstances === 0) return i18n.ts._xriftPreview.noRooms;
	return props.summary?.description;
});
const actionLabel = computed(() => {
	if (state.value !== 'available') return i18n.ts._xriftPreview.open;
	if (props.type === 'user') return i18n.ts._xriftPreview.viewProfile;
	if (props.type === 'instance') return isLive.value ? i18n.ts._xriftPreview.joinRoom : i18n.ts._xriftPreview.open;
	return data.value?.publicInstances === 0 ? i18n.ts._xriftPreview.enterFirst : i18n.ts._xriftPreview.enter;
});
const joinedAt = computed(() => data.value?.createdAt ? new Date(data.value.createdAt).toLocaleDateString(undefined, { year: 'numeric', month: 'long' }) : null);
const now = useLowresTime();
const elapsed = computed(() => {
	if (!data.value?.createdAt) return null;
	const minutes = Math.max(0, Math.floor((now.value - Date.parse(data.value.createdAt)) / 60_000));
	if (!Number.isFinite(minutes)) return null;
	return minutes < 60 ? i18n.tsx._xriftPreview.minutes({ count: format(minutes) }) : i18n.tsx._xriftPreview.hoursMinutes({ hours: format(Math.floor(minutes / 60)), minutes: format(minutes % 60) });
});

function hideFailedImage(event: Event): void {
	(event.target as HTMLImageElement).hidden = true;
}
</script>

<style lang="scss" module>
.root {
	// The supplied XRift design deliberately keeps its dark palette in every
	// Misskey theme. Keep these colors local to the embedded card.
	--xrift-panel: #463d50;
	--xrift-visual: #2c2336;
	--xrift-well: #372e42;
	--xrift-border: #766d7e;
	--xrift-fg: #ffffff;
	--xrift-muted: #c9c1d2;
	--xrift-ink: #170f23;
	--xrift-hover: #574d61;
	--xrift-live: #4bb34f;
	--xrift-focus: #a6c8ff;
	container-type: inline-size;
	color: var(--xrift-fg);
}
.card {
	display: grid;
	grid-template-columns: 42% minmax(0, 1fr);
	aspect-ratio: 16 / 9;
	box-sizing: border-box;
	overflow: hidden;
	border: 1px solid var(--xrift-border);
	border-radius: var(--MI-radius);
	background: var(--xrift-panel);
	font-size: 14px;
	&.live { border-color: var(--xrift-live); }
}
.visual {
	position: relative;
	min-width: 0;
	min-height: 0;
	background: var(--xrift-visual);
	> img { display: block; width: 100%; height: 100%; object-fit: cover; }
}
.visualIcon { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; font-size: 28px; color: var(--xrift-muted); }
.placeholder { background: repeating-linear-gradient(135deg, var(--xrift-visual), var(--xrift-visual) 12px, var(--xrift-border) 12px, var(--xrift-border) 13px); }
.body { min-width: 0; padding: 20px; display: flex; flex-direction: column; gap: 9px; overflow: hidden; }
.brandRow { display: flex; align-items: center; gap: 7px; }
.brand { font-size: 11px; font-weight: 800; letter-spacing: 0.03em; }
.type { padding: 1px 5px; border: 1px solid var(--xrift-border); border-radius: 3px; font: 700 9px/1.2 monospace; letter-spacing: 0.06em; }
.title { margin: 0; font-size: 1.35em; line-height: 1.35; font-weight: 750; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; }
.meta { margin: 0; color: var(--xrift-muted); font-size: 0.83em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.description { margin: 0; font-size: 0.9em; line-height: 1.55; white-space: pre-line; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; }
.invitation { margin: 0; font-size: 0.85em; font-weight: bold; }
.stats {
	display: flex; gap: 6px; margin: 0;
	> div { flex: 1; min-width: 0; padding: 7px; background: var(--xrift-well); border-radius: 6px; }
	dt { color: var(--xrift-muted); font-size: 0.72em; white-space: nowrap; }
	dd { margin: 2px 0 0; font-size: 1.2em; font-weight: bold; font-variant-numeric: tabular-nums; }
}
.actions { display: flex; gap: 8px; margin-top: auto; padding-top: 8px; }
.button {
	display: flex; align-items: center; justify-content: center; min-width: 0; min-height: 38px; box-sizing: border-box; flex: 1;
	padding: 8px 12px; border: 1px solid var(--xrift-border); border-radius: 999px; color: inherit;
	font-size: 0.85em; line-height: 1.3; font-weight: bold; text-align: center;
	&:hover { text-decoration: none; background: var(--xrift-hover); }
	&:focus-visible { outline: 2px solid var(--xrift-focus); outline-offset: 2px; }
	&.primary { background: var(--xrift-fg); color: var(--xrift-ink); border-color: transparent; &:hover { opacity: 0.85; } }
}
.badge { position: absolute; top: 10px; left: 10px; padding: 5px 8px; border-radius: 999px; background: var(--xrift-panel); font-size: 10px; font-weight: bold; display: flex; align-items: center; gap: 5px; }
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--xrift-live); }
.liveBadge { background: var(--xrift-live); color: var(--xrift-ink); .dot { background: currentColor; } }
.elapsed { position: absolute; left: 12px; right: 12px; bottom: 12px; padding: 10px; background: var(--xrift-panel); border-radius: 8px; small { display: block; font-size: 10px; color: var(--xrift-muted); } strong { display: block; margin-top: 3px; font-size: 1.35em; } }
.profileSize { max-height: 320px; }
.card.profile { display: flex; flex-direction: column; aspect-ratio: auto; padding: 20px; gap: 14px; }
.profileHeading { display: flex; gap: 18px; align-items: center; min-height: 0; }
.avatar { display: grid; place-items: center; width: 72px; height: 72px; flex-shrink: 0; border-radius: 50%; background: var(--xrift-well); color: var(--xrift-muted); overflow: hidden; > img { width: 100%; height: 100%; object-fit: cover; } > i { font-size: 32px; } }
.profileIdentity { flex: 1; min-width: 0; .brand { color: var(--xrift-muted); } .title { margin: 5px 0; } }
.worlds { min-height: 0; overflow: hidden; }
.worldsHeader { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 8px; }
.worldCount { margin: 0; font-size: 0.8em; color: var(--xrift-muted); }
.scrollActions { display: flex; gap: 4px; }
.scrollButton { display: grid; place-items: center; width: 32px; height: 28px; border-radius: 6px; color: var(--xrift-fg); background: var(--xrift-well); &:disabled { opacity: 0.35; cursor: default; } &:not(:disabled):hover { background: var(--xrift-hover); } &:focus-visible { outline: 2px solid var(--xrift-focus); outline-offset: -2px; } }
.worldGrid { display: grid; grid-auto-flow: column; grid-auto-columns: calc((100% - 16px) / 3); gap: 8px; padding: 2px 0 6px; overflow-x: auto; overscroll-behavior-x: contain; scroll-snap-type: x proximity; scroll-behavior: smooth; scrollbar-width: thin; scrollbar-color: var(--xrift-border) transparent; direction: ltr; &:focus-visible { outline: 2px solid var(--xrift-focus); outline-offset: -2px; } }
.worldLink { min-width: 0; font-size: 0.75em; color: inherit; scroll-snap-align: start; > span { display: block; margin-top: 5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; } &:focus-visible { outline: 2px solid var(--xrift-focus); outline-offset: -2px; } }
.worldImage { aspect-ratio: 12 / 5; max-height: 104px; overflow: hidden; border-radius: 6px; background: var(--xrift-well); > img { display: block; width: 100%; height: 100%; object-fit: cover; } > img[hidden] { display: none; } }
.profileAction { flex: 0 0 auto; max-width: 45%; }
.skeleton { height: 10px; border-radius: 4px; background: var(--xrift-well); }
.skeletonBrand { width: 35%; }
.skeletonTitle { height: 20px; width: 90%; }
.skeletonText { width: 60%; }
.skeletonButton { margin-top: auto; height: 38px; border-radius: 999px; }
.srOnly { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
@container (max-width: 560px) {
	.body { padding: 14px; gap: 7px; }
	.title { font-size: 1.15em; }
	.description:not(.stateMessage), .stats, .invitation { display: none; }
	.stats > div { padding: 5px; }
	.card.profile { padding: 14px; gap: 10px; }
	.avatar { width: 60px; height: 60px; }
}
@container (max-width: 420px) {
	.card { grid-template-columns: 33% minmax(0, 1fr); font-size: 12px; }
	.body { padding: 12px; gap: 6px; }
	.title { font-size: 1.1em; }
	.description:not(.stateMessage), .stats, .invitation, .elapsed, .secondary { display: none; }
	.badge { top: 7px; left: 7px; font-size: 9px; padding: 4px 6px; }
	.button { min-height: 36px; padding: 7px 8px; }
	.actions { padding-top: 4px; }
	.card.profile { padding: 12px; gap: 12px; }
	.profileHeading { gap: 10px; }
	.avatar { width: 48px; height: 48px; }
	.profileAction { padding: 8px 10px; }
	.worldGrid { grid-auto-columns: calc((100% - 10px) / 3); gap: 5px; }
	.worldImage { aspect-ratio: 1.6; }
	.worldLink > span { display: none; }
	.worldCount { font-size: 0.75em; }
}
@container (max-width: 320px) {
	.meta { display: none; }
	.body { padding: 10px; gap: 4px; }
}
@media (prefers-reduced-motion: reduce) {
	.worldGrid { scroll-behavior: auto; }
}
</style>
