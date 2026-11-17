<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div :class="$style.root">
	<article :class="[$style.card, { [$style.landscape]: type !== 'user', [$style.profileSize]: type === 'user', [$style.profile]: type === 'user' && state === 'available' && !loading, [$style.live]: isLive }]" :aria-busy="loading">
		<div v-if="type !== 'user' || state !== 'available' || loading" :class="$style.brandCorner" role="img" aria-label="XRift">
			<img :class="[$style.brand, $style.brandFull]" src="/client-assets/xrift/logo-white.svg" alt="" aria-hidden="true" width="886" height="259"/>
			<img :class="$style.brandCompact" src="/client-assets/xrift/icon.png" alt="" aria-hidden="true" width="512" height="512"/>
		</div>
		<template v-if="type === 'user' && state === 'available' && !loading">
			<div :class="$style.profileHeading">
				<div :class="$style.avatar">
					<img v-if="imageVisible" :src="summary?.thumbnail ?? undefined" :alt="summary?.title ?? ''" loading="lazy" @error="imageFailed = true"/>
					<i v-else class="ti ti-user" aria-hidden="true"></i>
				</div>
				<div :class="$style.profileIdentity">
					<img :class="$style.brand" src="/client-assets/xrift/logo-white.svg" alt="XRift" width="886" height="259"/>
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
				<span v-if="!loading && state !== 'available'" :class="$style.visualIcon" aria-hidden="true"><i :class="['ti', state === 'error' ? 'ti-alert-circle' : type === 'user' ? 'ti-user-off' : 'ti-lock']"></i></span>
			</div>
			<div :class="$style.body">
				<img v-if="imageVisible && state === 'available' && !loading" :src="summary?.thumbnail ?? undefined" alt="" aria-hidden="true" :class="$style.bodyBackdrop" loading="lazy" @error="imageFailed = true"/>
				<template v-if="loading">
					<span :class="$style.srOnly" role="status">{{ i18n.ts.loading }}</span>
					<div :class="[$style.skeleton, $style.skeletonBrand]"></div>
					<div :class="[$style.skeleton, $style.skeletonTitle]"></div>
					<div :class="[$style.skeleton, $style.skeletonText]"></div>
					<div :class="[$style.skeleton, $style.skeletonButton]"></div>
				</template>
				<template v-else>
					<div :class="$style.brandRow">
						<span :class="[$style.type, { [$style.activeType]: isLive }]">
							<i v-if="type === 'world'" class="ti ti-world" aria-hidden="true"></i>
							<i v-else-if="type === 'instance'" class="ti ti-users" aria-hidden="true"></i>
							<i v-else-if="type === 'item'" class="ti ti-package" aria-hidden="true"></i>
							<i v-else class="ti ti-user" aria-hidden="true"></i>
							<span>{{ typeLabel }}</span>
						</span>
						<span v-if="isLive" :class="$style.activeStatus"><span :class="$style.dot"></span>{{ i18n.ts._xriftPreview.active }}</span>
					</div>
					<h3 :class="$style.title">{{ heading }}</h3>
					<p v-if="state === 'available' && (data?.creator || metaDetail)" :class="[$style.meta, { [$style.instanceMeta]: isLive }]">
						<span v-if="data?.creator" :class="$style.creator">{{ data.creator }}</span><span v-if="data?.creator && metaDetail" :class="$style.metaSeparator" aria-hidden="true"> · </span><span v-if="metaDetail" :class="$style.metaDetail">{{ metaDetail }}</span>
					</p>
					<p v-if="message" :class="[$style.description, { [$style.stateMessage]: state !== 'available' }]">{{ message }}</p>
					<div :class="$style.footer">
						<div :class="$style.actions">
							<a :href="url" target="_blank" rel="nofollow noopener" :class="[$style.button, { [$style.primary]: state === 'available' }]">{{ actionLabel }}</a>
						</div>
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
const typeLabel = computed(() => props.type === 'world' ? i18n.ts._xriftPreview.world : props.type === 'instance' ? i18n.ts._xriftPreview.room : props.type === 'item' ? i18n.ts._xriftPreview.item : i18n.ts._xriftPreview.user);
const heading = computed(() => {
	if (state.value === 'error') return i18n.ts._xriftPreview.error;
	if (state.value === 'unavailable') return props.type === 'world' ? i18n.ts._xriftPreview.worldUnavailable : props.type === 'instance' ? i18n.ts._xriftPreview.roomUnavailable : props.type === 'item' ? i18n.ts._xriftPreview.itemUnavailable : i18n.ts._xriftPreview.userUnavailable;
	return props.summary?.title ?? 'XRift';
});
const message = computed(() => {
	if (state.value === 'error') return i18n.ts._xriftPreview.openDirectly;
	if (state.value === 'unavailable') return props.type === 'instance' ? i18n.ts._xriftPreview.roomUnavailableDescription : i18n.ts._xriftPreview.unavailableDescription;
	if (isLive.value && props.summary?.title) return i18n.tsx._xriftPreview.instanceDescription({ name: props.summary.title });
	if (props.summary?.description?.trim()) return props.summary.description;
	if (props.type === 'world' && data.value?.publicInstances === 0) return i18n.ts._xriftPreview.noRooms;
	return null;
});
const actionLabel = computed(() => {
	if (state.value !== 'available') return i18n.ts._xriftPreview.open;
	if (props.type === 'user') return i18n.ts._xriftPreview.viewProfile;
	if (props.type === 'item') return i18n.ts._xriftPreview.viewItem;
	if (props.type === 'instance') return isLive.value ? i18n.ts._xriftPreview.joinRoom : i18n.ts._xriftPreview.open;
	return i18n.ts._xriftPreview.enter;
});
const joinedAt = computed(() => data.value?.createdAt ? new Date(data.value.createdAt).toLocaleDateString(undefined, { year: 'numeric', month: 'long' }) : null);
const now = useLowresTime();
const elapsed = computed(() => {
	if (!data.value?.createdAt) return null;
	const minutes = Math.max(0, Math.floor((now.value - Date.parse(data.value.createdAt)) / 60_000));
	if (!Number.isFinite(minutes)) return null;
	return minutes < 60 ? i18n.tsx._xriftPreview.minutes({ count: format(minutes) }) : i18n.tsx._xriftPreview.hoursMinutes({ hours: format(Math.floor(minutes / 60)), minutes: format(minutes % 60) });
});
const metaDetail = computed(() => isLive.value && elapsed.value
	? i18n.tsx._xriftPreview.startedAgo({ time: elapsed.value })
	: props.type === 'item' && data.value?.acquireCount != null ? i18n.tsx._xriftPreview.acquisitions({ count: format(data.value.acquireCount) })
	: data.value?.totalVisits != null ? i18n.tsx._xriftPreview.visits({ count: format(data.value.totalVisits) }) : null);

function hideFailedImage(event: Event): void {
	(event.target as HTMLImageElement).hidden = true;
}
</script>

<style lang="scss" module>
.root {
	// Match app.xrift.net: dark purple with translucent white surfaces.
	// Keep the provider palette local to the embedded card in every theme.
	--xrift-visual: #1a1025;
	--xrift-fg: #ffffff;
	--xrift-ink: #000000;
	--xrift-panel: color-mix(in srgb, var(--xrift-fg) 18%, var(--xrift-visual));
	--xrift-well: color-mix(in srgb, var(--xrift-ink) 20%, var(--xrift-panel));
	--xrift-border: color-mix(in srgb, var(--xrift-fg) 25%, var(--xrift-panel));
	--xrift-muted: color-mix(in srgb, var(--xrift-fg) 85%, var(--xrift-panel));
	--xrift-hover: color-mix(in srgb, var(--xrift-fg) 10%, var(--xrift-panel));
	--xrift-live: #4bb34f;
	--xrift-active: #8fd694;
	--xrift-brand: #5b3baf;
	--xrift-focus: #a6c8ff;
	container-type: inline-size;
	color: var(--xrift-fg);
}
.card {
	position: relative;
	display: grid;
	grid-template-columns: 45% minmax(0, 1fr);
	aspect-ratio: 16 / 9;
	box-sizing: border-box;
	overflow: hidden;
	border: 1px solid var(--xrift-border);
	border-radius: var(--MI-radius);
	background: var(--xrift-panel);
	font-size: 14px;
	&.live { border-color: var(--xrift-live); }
	&.landscape { aspect-ratio: 20 / 9; }
}
.visual {
	position: relative;
	min-width: 0;
	min-height: 0;
	background: var(--xrift-visual);
	> img { display: block; width: 100%; height: 100%; object-fit: cover; }
}
.visualIcon { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; font-size: 28px; color: var(--xrift-muted); }
.placeholder { background: repeating-linear-gradient(135deg, var(--xrift-visual), var(--xrift-visual) 12px, color-mix(in srgb, var(--xrift-fg) 8%, var(--xrift-visual)) 12px, color-mix(in srgb, var(--xrift-fg) 8%, var(--xrift-visual)) 13px); }
.body { position: relative; isolation: isolate; min-width: 0; padding: 20px; display: flex; flex-direction: column; gap: 10px; overflow: hidden; }
.bodyBackdrop { position: absolute; z-index: -1; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0.16; filter: blur(3px); mask-image: linear-gradient(to right, black, transparent 95%); pointer-events: none; }
.brandRow { display: flex; align-items: center; gap: 7px; padding-right: 64px; flex-shrink: 0; }
.brand { display: block; width: 54px; height: auto; flex-shrink: 0; }
.brandCorner { position: absolute; top: 0; right: 0; z-index: 2; padding: 8px 12px; border-bottom-left-radius: 12px; background: var(--xrift-brand); }
.brandCompact { display: none; }
.type { display: inline-flex; align-items: center; min-width: 0; gap: 5px; padding: 4px 8px; border: 1px solid var(--xrift-border); border-radius: 6px; background: color-mix(in srgb, var(--xrift-fg) 15%, transparent); color: var(--xrift-fg); font-size: 12px; font-weight: 750; line-height: 1.2; white-space: nowrap; > i { flex-shrink: 0; } > span { min-width: 0; overflow: hidden; text-overflow: ellipsis; } }
.activeType { color: var(--xrift-visual); background: var(--xrift-active); border-color: transparent; }
.activeStatus { display: inline-flex; align-items: center; gap: 5px; padding: 4px 7px; border-radius: 5px; color: var(--xrift-active); background: color-mix(in srgb, var(--xrift-active) 15%, var(--xrift-visual)); font-size: 10px; font-weight: bold; white-space: nowrap; }
.title { flex-shrink: 0; margin: 0; font-size: 1.35em; line-height: 1.35; font-weight: 750; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; }
.meta { flex-shrink: 0; margin: 0; color: var(--xrift-muted); font-size: 0.83em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.instanceMeta { display: flex; align-items: baseline; gap: 3px; .creator { min-width: 0; overflow: hidden; text-overflow: ellipsis; } .metaDetail { flex-shrink: 0; } }
.description { min-height: 0; margin: 0; font-size: 0.9em; line-height: 1.55; white-space: pre-line; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; }
.footer { display: flex; flex-shrink: 0; flex-direction: column; gap: 6px; margin-top: auto; }
.actions { display: flex; flex-shrink: 0; gap: 8px; padding-top: 4px; }
.actions .button { min-height: 44px; }
.button {
	display: flex; align-items: center; justify-content: center; min-width: 0; min-height: 38px; box-sizing: border-box; flex: 1;
	padding: 8px 12px; border: 1px solid var(--xrift-border); border-radius: 999px; color: inherit;
	font-size: 0.85em; line-height: 1.3; font-weight: bold; text-align: center;
	&:hover { text-decoration: none; background: var(--xrift-hover); }
	&:focus-visible { outline: 2px solid var(--xrift-focus); outline-offset: 2px; }
	&.primary { background: var(--xrift-fg); color: var(--xrift-ink); border-color: transparent; &:hover { opacity: 0.85; } }
}
.dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.profileSize { max-height: 320px; }
.card.profile { display: flex; flex-direction: column; aspect-ratio: auto; padding: 20px; gap: 14px; }
.profileHeading { display: flex; gap: 18px; align-items: center; min-height: 0; }
.avatar { display: grid; place-items: center; width: 72px; height: 72px; flex-shrink: 0; border-radius: 50%; background: var(--xrift-well); color: var(--xrift-muted); overflow: hidden; > img { width: 100%; height: 100%; object-fit: cover; } > i { font-size: 32px; } }
.profileIdentity { flex: 1; min-width: 0; .title { margin: 5px 0; } .meta { white-space: normal; overflow-wrap: anywhere; } }
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
@container (max-width: 640px) {
	.body { padding: 16px; gap: 8px; }
	.title { font-size: 1.15em; }
	.description { font-size: 0.83em; line-height: 1.4; }
	.actions { padding-top: 0; }
}
@container (max-width: 560px) {
	.brandCorner { padding: 5px; border-bottom-left-radius: 7px; }
	.brandFull { display: none; }
	.brandCompact { display: block; width: 18px; height: 18px; }
	.brandRow { padding-right: 20px; }
	.card.profile { padding: 14px; gap: 10px; }
	.avatar { width: 60px; height: 60px; }
}
@container (max-width: 420px) {
	.card { grid-template-columns: 35% minmax(0, 1fr); font-size: 12px; }
	.body { padding: 12px; gap: 6px; }
	.title { font-size: 1.1em; -webkit-line-clamp: 1; }
	.brandRow { gap: 5px; }
	.type { padding: 2px 6px; font-size: 10px; > i { display: none; } }
	.activeStatus { padding: 3px 5px; gap: 3px; font-size: 9px; }
	.body .meta { font-size: 0.75em; }
	.description:not(.stateMessage) { display: none; }
	.button { min-height: 36px; padding: 7px 8px; }
	.actions .button { min-height: 40px; }
	.footer { gap: 4px; }
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
	.card.live .title { -webkit-line-clamp: 1; }
	.body { padding: 10px; gap: 4px; }
	.activeStatus { padding: 3px; font-size: 8px; }
}
@media (prefers-reduced-motion: reduce) {
	.worldGrid { scroll-behavior: auto; }
}
</style>
