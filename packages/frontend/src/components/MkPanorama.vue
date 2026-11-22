<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div
	ref="root" :class="[$style.root, { [$style.ready]: ready }]"
	:role="ready ? 'group' : undefined" :aria-label="ready ? alt : undefined" :tabindex="ready ? 0 : undefined"
	@pointerdown="beginDrag" @pointermove="drag" @pointerup="endDrag" @pointercancel="endDrag" @lostpointercapture="endDrag"
	@keydown.left.prevent.stop="turn(-0.15)" @keydown.right.prevent.stop="turn(0.15)"
	@keydown.space.prevent.stop="beginKeyHold" @keydown.enter.prevent.stop="beginKeyHold"
	@keyup.space.prevent.stop="endKeyHold" @keyup.enter.prevent.stop="endKeyHold" @blur="endKeyHold()"
>
	<img ref="image" :src="src" :alt="ready ? '' : alt" loading="lazy" crossorigin="anonymous" draggable="false" @load="loaded = true" @error="emit('error')"/>
	<canvas :key="canvasVersion" ref="canvas" :class="$style.canvas" aria-hidden="true" @webglcontextlost.prevent="contextLost"></canvas>
</div>
</template>

<script setup lang="ts">
import { computed, onActivated, onBeforeUnmount, onDeactivated, onMounted, ref, watch } from 'vue';
import { useDocumentVisibility } from '@@/js/use-document-visibility.js';
import { prefer } from '@/preferences.js';
import type { PanoramaRenderer } from '@/utility/panorama-renderer.js';

const props = defineProps<{ src: string; alt: string }>();
const emit = defineEmits<{ error: [] }>();
const root = ref<HTMLDivElement | null>(null);
const image = ref<HTMLImageElement | null>(null);
const canvas = ref<HTMLCanvasElement | null>(null);
const canvasVersion = ref(0);
const loaded = ref(false);
const visible = ref(false);
const active = ref(true);
const ready = ref(false);
const failed = ref(false);
const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
const reducedMotion = ref(motion.matches);
const interacting = ref(false);
const paused = computed(() => interacting.value || reducedMotion.value || !prefer.r.animation.value);
const visibility = useDocumentVisibility();
const eligible = computed(() => loaded.value && visible.value && active.value && visibility.value === 'visible' && !failed.value &&
	!!image.value && image.value.naturalWidth >= 512 && Math.abs(image.value.naturalWidth / image.value.naturalHeight - 2) < 0.03);
let renderer: PanoramaRenderer | null = null;
let observer: IntersectionObserver | null = null;
let resizeObserver: ResizeObserver | null = null;
let generation = 0;
let starting = false;
let frame: number | null = null;
let lastTime: number | null = null;
let yaw = 0;
let dragPointer: number | null = null;
let dragX = 0;
let resumeTimer: number | null = null;
const heldKeys = new Set<string>();

function clearResumeTimer(): void {
	if (resumeTimer != null) window.clearTimeout(resumeTimer);
	resumeTimer = null;
}

function pauseForInteraction(): void {
	clearResumeTimer();
	interacting.value = true;
	stopAnimation();
}

function resumeAfterInteraction(): void {
	clearResumeTimer();
	if (dragPointer != null || heldKeys.size > 0 || !ready.value || !eligible.value) return;
	resumeTimer = window.setTimeout(() => {
		resumeTimer = null;
		interacting.value = false;
	}, 3000);
}

function beginKeyHold(event: KeyboardEvent): void {
	if (!ready.value) return;
	heldKeys.add(event.key);
	pauseForInteraction();
}

function endKeyHold(event?: KeyboardEvent): void {
	if (heldKeys.size === 0) return;
	if (event) heldKeys.delete(event.key);
	else heldKeys.clear();
	resumeAfterInteraction();
}

function stopAnimation(): void {
	if (frame != null) cancelAnimationFrame(frame);
	frame = null;
	lastTime = null;
}

function dispose(): void {
	generation++;
	starting = false;
	stopAnimation();
	clearResumeTimer();
	heldKeys.clear();
	const pointer = dragPointer;
	dragPointer = null;
	if (pointer != null && root.value?.hasPointerCapture(pointer)) root.value.releasePointerCapture(pointer);
	interacting.value = false;
	const previous = renderer;
	renderer = null;
	previous?.dispose();
	if (previous) canvasVersion.value++;
	ready.value = false;
}

function animate(time: number): void {
	frame = null;
	if (!renderer || !eligible.value || paused.value) return;
	if (lastTime == null) lastTime = time;
	const elapsed = time - lastTime;
	if (elapsed >= 1000 / 15) {
		yaw += Math.min(elapsed, 200) / 1000 * Math.PI / 90;
		renderer.render(yaw);
		lastTime = time;
	}
	frame = requestAnimationFrame(animate);
}

function updateAnimation(): void {
	stopAnimation();
	if (ready.value && eligible.value && !paused.value) frame = requestAnimationFrame(animate);
}

function resize(): void {
	if (!renderer || !root.value) return;
	const size = root.value.getBoundingClientRect();
	renderer.resize(size.width, size.height);
	renderer.render(yaw);
}

async function updateRenderer(): Promise<void> {
	if (!eligible.value) { dispose(); return; }
	if (renderer || starting) return;
	starting = true;
	const current = ++generation;
	try {
		const { createPanoramaRenderer } = await import('@/utility/panorama-renderer.js');
		if (current !== generation || !eligible.value || !canvas.value || !image.value) return;
		renderer = createPanoramaRenderer(canvas.value, image.value);
		resize();
		ready.value = true;
		updateAnimation();
	} catch {
		if (current === generation) { dispose(); failed.value = true; }
	} finally {
		if (current === generation) starting = false;
	}
}

function turn(delta: number): void {
	if (!ready.value) return;
	pauseForInteraction();
	yaw += delta;
	renderer?.render(yaw);
	resumeAfterInteraction();
}

function beginDrag(event: PointerEvent): void {
	if (!ready.value || event.button !== 0 || dragPointer != null) return;
	pauseForInteraction();
	dragPointer = event.pointerId;
	dragX = event.clientX;
	root.value?.setPointerCapture(event.pointerId);
}

function drag(event: PointerEvent): void {
	if (dragPointer !== event.pointerId || !root.value) return;
	turn(-(event.clientX - dragX) / Math.max(1, root.value.clientWidth) * Math.PI / 2);
	dragX = event.clientX;
}

function endDrag(event: PointerEvent): void {
	if (dragPointer !== event.pointerId) return;
	dragPointer = null;
	if (root.value?.hasPointerCapture(event.pointerId)) root.value.releasePointerCapture(event.pointerId);
	resumeAfterInteraction();
}

function contextLost(event: Event): void {
	if (!renderer || event.target !== canvas.value) return;
	failed.value = true;
	dispose();
}

function motionChanged(): void { reducedMotion.value = motion.matches; }

watch(eligible, () => { void updateRenderer(); }, { flush: 'post' });
watch(paused, updateAnimation);
watch(() => props.src, () => { loaded.value = false; failed.value = false; yaw = 0; dispose(); });

onMounted(() => {
	loaded.value = Boolean(image.value?.complete && image.value.naturalWidth);
	observer = new IntersectionObserver(entries => { visible.value = entries[0]?.isIntersecting ?? false; });
	if (root.value) observer.observe(root.value);
	resizeObserver = new ResizeObserver(resize);
	if (root.value) resizeObserver.observe(root.value);
	motion.addEventListener('change', motionChanged);
});
onActivated(() => { active.value = true; });
onDeactivated(() => { active.value = false; dispose(); });
onBeforeUnmount(() => { active.value = false; observer?.disconnect(); resizeObserver?.disconnect(); motion.removeEventListener('change', motionChanged); dispose(); });
</script>

<style lang="scss" module>
.root { position: relative; width: 100%; height: 100%; overflow: hidden; touch-action: pan-y; > img { display: block; width: 100%; height: 100%; object-fit: cover; } &:focus-visible { outline: 2px solid var(--MI_THEME-focus); outline-offset: -2px; } }
.canvas { position: absolute; inset: 0; width: 100%; height: 100%; opacity: 0; pointer-events: none; }
.ready { cursor: grab; > img { opacity: 0; } > .canvas { opacity: 1; } &:active { cursor: grabbing; } }
</style>
