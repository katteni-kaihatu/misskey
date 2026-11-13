<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader>
	<div class="_spacer" style="--MI_SPACER-w: 900px;">
		<div class="_gaps">
			<MkA to="/play"><i class="ti ti-arrow-left"></i> Play</MkA>
			<section class="_panel" :class="$style.intro">
				<h1>{{ i18n.ts._doom.title }}</h1>
				<p>{{ i18n.ts._doom.description }}</p>
				<div v-if="!started" class="_gaps">
					<MkSelect v-model="skill" :items="skillOptions">
						<template #label>{{ i18n.ts._doom.difficulty }}</template>
					</MkSelect>
					<div :class="$style.actions">
						<MkButton primary rounded @click="start"><i class="ti ti-player-play"></i> {{ i18n.ts.start }}</MkButton>
						<MkButton rounded @click="fileInput?.click()"><i class="ti ti-file-upload"></i> {{ i18n.ts._doom.selectWad }}</MkButton>
						<MkButton v-if="wad" rounded @click="clearWad">{{ i18n.ts._doom.useFreedoom }}</MkButton>
					</div>
					<p v-if="wadName" class="_breakAll">{{ wadName }}</p>
					<input ref="fileInput" type="file" accept=".wad" hidden @change="selectWad">
				</div>
				<p :class="$style.caption">{{ i18n.ts._doom.wadNotice }}</p>
			</section>

			<section v-if="started" ref="player" class="_panel" :class="$style.player">
				<div v-if="status === 'loading'" role="status" :class="$style.message">{{ i18n.ts.loading }}</div>
				<div v-if="status === 'error'" role="alert" :class="$style.message">{{ i18n.ts._doom.loadError }}</div>
				<iframe
					ref="frame"
					:class="$style.frame"
					src="/client-assets/doom/index.html"
					:title="i18n.ts._doom.title"
					sandbox="allow-scripts allow-same-origin"
					allow="autoplay; fullscreen"
				></iframe>
				<div :class="$style.toolbar">
					<MkButton :disabled="status !== 'playing'" rounded @click="togglePause"><i :class="paused ? 'ti ti-player-play' : 'ti ti-player-pause'"></i> {{ paused ? i18n.ts._doom.resume : i18n.ts._doom.pause }}</MkButton>
					<MkButton rounded @click="stop"><i class="ti ti-player-stop"></i> {{ i18n.ts._doom.stop }}</MkButton>
					<MkButton :disabled="status !== 'playing'" rounded @click="fullscreen"><i class="ti ti-maximize"></i> {{ i18n.ts._doom.fullscreen }}</MkButton>
				</div>
				<div v-if="status === 'playing'" :class="$style.touch" :aria-label="i18n.ts._doom.touchControls">
					<button v-for="control in controls" :key="control.code" type="button" class="_button" :class="$style.touchButton" :aria-label="control.label" :disabled="paused" @pointerdown.prevent="press($event, control.code)" @pointerup.prevent="release(control.code)" @pointercancel="release(control.code)" @lostpointercapture="release(control.code)" @contextmenu.prevent @keydown.enter.prevent="sendKey(control.code, true)" @keyup.enter.prevent="release(control.code)" @keydown.space.prevent="sendKey(control.code, true)" @keyup.space.prevent="release(control.code)">
						<i :class="control.icon"></i>
					</button>
				</div>
			</section>

			<section v-if="displayResult" class="_panel" :class="$style.result">
				<h2>{{ i18n.ts._doom.result }}</h2>
				<p>{{ displayResult.game === 'freedoom' ? 'Freedoom' : 'DOOM' }} · E{{ displayResult.episode }}M{{ displayResult.map }} · {{ i18n.ts._doom.difficulty }} {{ displayResult.skill }}</p>
				<p v-if="displayResult.completed">{{ i18n.ts._doom.completed }}</p>
				<p v-else-if="displayResult.dead">{{ i18n.ts._doom.gameOver }}</p>
				<dl :class="$style.stats">
					<div><dt>{{ i18n.ts._doom.score }}</dt><dd>{{ doomScore(displayResult).toLocaleString() }}</dd></div>
					<div><dt>{{ i18n.ts._doom.time }}</dt><dd>{{ doomTime(displayResult.ticks) }}</dd></div>
					<div><dt>{{ i18n.ts._doom.kills }}</dt><dd>{{ displayResult.kills }} / {{ displayResult.totalKills }}</dd></div>
					<div><dt>{{ i18n.ts._doom.items }}</dt><dd>{{ displayResult.items }} / {{ displayResult.totalItems }}</dd></div>
					<div><dt>{{ i18n.ts._doom.secrets }}</dt><dd>{{ displayResult.secrets }} / {{ displayResult.totalSecrets }}</dd></div>
				</dl>
				<p :class="$style.caption">{{ i18n.ts._doom.scoreRule }}</p>
				<p v-if="!result" :class="$style.caption">{{ i18n.ts._doom.sharedResult }}</p>
				<div :class="$style.actions">
					<MkButton primary rounded :disabled="sharingBusy" @click="postResult"><i class="ti ti-pencil"></i> {{ i18n.ts.shareWithNote }}</MkButton>
					<MkButton rounded @click="copyResult"><i class="ti ti-copy"></i> {{ i18n.ts._doom.copyResult }}</MkButton>
					<MkButton rounded :disabled="sharingBusy" @click="saveImage"><i class="ti ti-download"></i> {{ i18n.ts._doom.saveImage }}</MkButton>
					<MkButton v-if="canShare" rounded :disabled="sharingBusy" @click="shareResult"><i class="ti ti-share"></i> {{ i18n.ts.share }}</MkButton>
				</div>
			</section>

			<section class="_panel" :class="$style.help">
				<h2>{{ i18n.ts._doom.controls }}</h2>
				<p>{{ i18n.ts._doom.keyboard }}</p>
				<p>{{ i18n.ts._doom.touchHelp }}</p>
				<p :class="$style.caption">{{ i18n.ts._doom.audioNotice }}</p>
				<p :class="$style.caption">
					<a href="https://github.com/ozkl/doomgeneric" target="_blank" rel="noopener noreferrer">doomgeneric</a> ·
					<a href="https://freedoom.github.io/" target="_blank" rel="noopener noreferrer">Freedoom 0.13.0</a> ·
					<a href="/client-assets/doom/source.tar.gz">{{ i18n.ts._doom.engineSource }}</a> ·
					<a href="/client-assets/doom/DOOM-LICENSE.txt">{{ i18n.ts.license }}</a> ·
					<a href="/client-assets/doom/FREEDOOM-LICENSE.txt">{{ i18n.ts._doom.dataLicense }}</a>
				</p>
			</section>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import { computed, onDeactivated, onMounted, onUnmounted, ref, shallowRef } from 'vue';
import { url } from '@@/js/config.js';
import MkButton from '@/components/MkButton.vue';
import MkSelect from '@/components/MkSelect.vue';
import { i18n } from '@/i18n.js';
import { definePage } from '@/page.js';
import * as os from '@/os.js';
import { pleaseLogin } from '@/utility/please-login.js';
import { isSupportShare } from '@/utility/navigator.js';
import { uploadFile } from '@/utility/drive.js';
import { decodeDoomResult, doomResultUrl, doomScore, doomTime, isDoomIwad, parseDoomResult } from '@/utility/doom.js';
import type { DoomResult } from '@/utility/doom.js';

const props = defineProps<{ shared?: string }>();
const skill = ref(3);
const skillOptions = computed(() => [
	{ value: 1, label: i18n.ts._doom.easy },
	{ value: 2, label: i18n.ts._doom.normal },
	{ value: 3, label: i18n.ts._doom.hard },
	{ value: 4, label: i18n.ts._doom.veryHard },
	{ value: 5, label: i18n.ts._doom.nightmare },
]);
const controls = computed(() => [
	{ code: 'ArrowLeft', icon: 'ti ti-arrow-back-up', label: i18n.ts._doom.turnLeft },
	{ code: 'KeyW', icon: 'ti ti-arrow-up', label: i18n.ts._doom.forward },
	{ code: 'ArrowRight', icon: 'ti ti-arrow-forward-up', label: i18n.ts._doom.turnRight },
	{ code: 'KeyS', icon: 'ti ti-arrow-down', label: i18n.ts._doom.backward },
	{ code: 'KeyF', icon: 'ti ti-target', label: i18n.ts._doom.fire },
	{ code: 'KeyE', icon: 'ti ti-hand-click', label: i18n.ts._doom.use },
	{ code: 'Enter', icon: 'ti ti-corner-down-left', label: i18n.ts._doom.confirm },
]);
const frame = shallowRef<HTMLIFrameElement>();
const player = shallowRef<HTMLElement>();
const fileInput = shallowRef<HTMLInputElement>();
const wad = shallowRef<Uint8Array | null>(null);
const wadName = ref('');
const started = ref(false);
const paused = ref(false);
const status = ref<'loading' | 'playing' | 'error'>('loading');
const result = shallowRef<DoomResult | null>(null);
const displayResult = computed(() => result.value ?? decodeDoomResult(props.shared));
const canShare = isSupportShare();
const sharingBusy = ref(false);
let timer: number | undefined;
let captureDone: ((blob: Blob | null) => void) | undefined;
let cancelUpload: (() => void) | undefined;
let shareGeneration = 0;

function send(data: Record<string, unknown>) {
	frame.value?.contentWindow?.postMessage(data, window.location.origin);
}

function start() {
	result.value = null;
	paused.value = false;
	status.value = 'loading';
	started.value = true;
	timer = window.setTimeout(() => { status.value = 'error'; }, 90000);
}

function stop() {
	window.clearTimeout(timer);
	captureDone?.(null);
	started.value = false;
	paused.value = false;
}

function dispose() {
	shareGeneration++;
	cancelUpload?.();
	cancelUpload = undefined;
	sharingBusy.value = false;
	stop();
}

function receive(event: MessageEvent) {
	const source = frame.value?.contentWindow;
	if (!started.value || !source || event.origin !== window.location.origin || event.source !== source) return;
	if (event.data?.type === 'doom:ready') {
		send({ type: 'doom:start', skill: skill.value, wad: wad.value, custom: wad.value !== null });
	} else if (event.data?.type === 'doom:started') {
		window.clearTimeout(timer);
		status.value = 'playing';
	} else if (event.data?.type === 'doom:error') {
		window.clearTimeout(timer);
		status.value = 'error';
	} else if (event.data?.type === 'doom:stats') {
		const parsed = parseDoomResult(event.data.result);
		if (parsed) result.value = parsed;
	} else if (event.data?.type === 'doom:captured') {
		const blob = event.data.blob;
		captureDone?.(blob instanceof Blob && blob.type === 'image/png' && blob.size < 5 * 1024 * 1024 ? blob : null);
	}
}

async function selectWad(event: Event) {
	const input = event.target as HTMLInputElement;
	const file = input.files?.[0];
	input.value = '';
	if (!file) return;
	try {
		if (file.size > 64 * 1024 * 1024) throw new Error('WAD too large');
		const data = new Uint8Array(await file.arrayBuffer());
		if (!isDoomIwad(data)) throw new Error('Invalid IWAD');
		wad.value = data;
		wadName.value = file.name;
	} catch {
		await os.alert({ type: 'error', text: i18n.ts._doom.invalidWad });
	}
}

function clearWad() {
	wad.value = null;
	wadName.value = '';
}

function togglePause() {
	paused.value = !paused.value;
	send({ type: 'doom:pause', paused: paused.value });
}

function sendKey(code: string, down: boolean) {
	if (paused.value || status.value !== 'playing') return;
	send({ type: 'doom:key', code, down });
}

function press(event: PointerEvent, code: string) {
	(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
	sendKey(code, true);
}

function release(code: string) {
	send({ type: 'doom:key', code, down: false });
}

async function fullscreen() {
	try {
		await player.value?.requestFullscreen();
	} catch {
		await os.alert({ type: 'error', text: i18n.ts._doom.fullscreenError });
	}
}

function sharing() {
	const value = displayResult.value;
	if (!value) return null;
	const text = i18n.tsx._doom.shareText({
		game: value.game === 'freedoom' ? 'Freedoom' : 'DOOM',
		stage: `E${value.episode}M${value.map}`,
		score: doomScore(value).toLocaleString(),
		kills: value.kills, totalKills: value.totalKills,
		secrets: value.secrets, totalSecrets: value.totalSecrets,
		time: doomTime(value.ticks),
	});
	return { title: i18n.ts._doom.title, text, url: doomResultUrl(url, value) };
}

function pauseForShare() {
	if (started.value && status.value === 'playing' && !paused.value) togglePause();
}

async function resultImage(share: { title: string; text: string }): Promise<File> {
	const screenshot = started.value && status.value === 'playing' ? await new Promise<Blob | null>(resolve => {
		const timeout = window.setTimeout(() => captureDone?.(null), 2000);
		captureDone = blob => {
			window.clearTimeout(timeout);
			captureDone = undefined;
			resolve(blob);
		};
		send({ type: 'doom:capture' });
	}) : null;
	const bitmap = screenshot ? await createImageBitmap(screenshot) : null;
	const canvas = window.document.createElement('canvas');
	canvas.width = 800;
	canvas.height = bitmap ? 700 : 200;
	const context = canvas.getContext('2d');
	if (!context) throw new Error('Canvas unavailable');
	// Fixed colors keep downloaded result cards readable outside the current theme.
	context.fillStyle = '#121416';
	context.fillRect(0, 0, canvas.width, canvas.height);
	if (bitmap) {
		context.drawImage(bitmap, 0, 0, 800, 500);
		bitmap.close();
	}
	const top = bitmap ? 500 : 0;
	context.fillStyle = '#f5f5f5';
	context.font = 'bold 28px sans-serif';
	context.fillText(share.title, 24, top + 42);
	context.font = '20px sans-serif';
	share.text.split('\n').forEach((line, index) => context.fillText(line, 24, top + 84 + index * 34, 752));
	const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('Image encoding failed')), 'image/png'));
	return new File([blob], 'misskey-doom.png', { type: 'image/png' });
}

async function postResult() {
	const share = sharing();
	if (!share || sharingBusy.value) return;
	pauseForShare();
	sharingBusy.value = true;
	const generation = shareGeneration;
	try {
		if (!await pleaseLogin({ openOnRemote: { type: 'share', params: { text: `${share.text}\n${share.url}` } } })) return;
		if (generation !== shareGeneration) return;
		const image = await resultImage(share);
		if (generation !== shareGeneration) return;
		const upload = uploadFile(image, { name: image.name, isSensitive: true, caption: share.text });
		cancelUpload = upload.abort;
		const timeout = window.setTimeout(upload.abort, 30000);
		let file;
		try {
			file = await upload.filePromise.catch(() => null);
		} finally {
			window.clearTimeout(timeout);
			if (cancelUpload === upload.abort) cancelUpload = undefined;
		}
		if (generation !== shareGeneration) return;
		os.post({ initialText: `${share.text}\n${share.url}`, initialFiles: file ? [file] : undefined, instant: true });
	} catch {
		if (generation === shareGeneration) os.post({ initialText: `${share.text}\n${share.url}`, instant: true });
	} finally {
		if (generation === shareGeneration) sharingBusy.value = false;
	}
}

async function saveImage() {
	const share = sharing();
	if (!share || sharingBusy.value) return;
	pauseForShare();
	sharingBusy.value = true;
	try {
		const file = await resultImage(share);
		const objectUrl = URL.createObjectURL(file);
		const anchor = window.document.createElement('a');
		anchor.href = objectUrl;
		anchor.download = file.name;
		anchor.click();
		window.setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
	} catch {
		await os.alert({ type: 'error', text: i18n.ts._doom.shareError });
	} finally {
		sharingBusy.value = false;
	}
}

async function copyResult() {
	const share = sharing();
	if (!share) return;
	pauseForShare();
	try {
		await navigator.clipboard.writeText(`${share.text}\n${share.url}`);
		os.toast(i18n.ts.copiedToClipboard);
	} catch {
		await os.alert({ type: 'error', text: i18n.ts._doom.copyError });
	}
}

async function shareResult() {
	const share = sharing();
	if (!share || sharingBusy.value) return;
	pauseForShare();
	sharingBusy.value = true;
	try {
		const file = await resultImage(share).catch(() => null);
		await navigator.share(file && navigator.canShare?.({ files: [file] }) ? { ...share, files: [file] } : share);
	} catch (error) {
		if (error instanceof Error && error.name === 'AbortError') return;
		await os.alert({ type: 'error', text: i18n.ts._doom.shareError });
	} finally {
		sharingBusy.value = false;
	}
}

onMounted(() => window.addEventListener('message', receive));
onDeactivated(dispose);
onUnmounted(() => {
	dispose();
	window.removeEventListener('message', receive);
});

definePage(() => ({ title: i18n.ts._doom.title, icon: 'ti ti-device-gamepad', path: '/play/doom' }));
</script>

<style lang="scss" module>
.intro, .help, .result {
	padding: 24px;

	h1, h2 { margin: 0 0 12px; }
	h1 { font-size: 1.5em; }
	h2 { font-size: 1.15em; }
	p { line-height: 1.7; }
}

.caption {
	font-size: .85em;
	color: var(--MI_THEME-fg);
	opacity: .75;
}

.actions, .toolbar, .touch {
	display: flex;
	flex-wrap: wrap;
	align-items: center;
	gap: 12px;
}

.frame {
	display: block;
	width: 100%;
	aspect-ratio: 8 / 5;
	border: 0;
}

.message { padding: 16px; }
.toolbar { padding: 16px; }

.player:fullscreen {
	display: flex;
	flex-direction: column;
	background: var(--MI_THEME-panel);
	overflow: auto;

	.frame { flex: 1; min-height: 0; aspect-ratio: auto; }
	.toolbar, .touch { flex-shrink: 0; }
}

.touch {
	padding: 0 16px 16px;
	touch-action: none;
}

.touchButton {
	min-width: 48px;
	min-height: 48px;
	background: var(--MI_THEME-buttonBg);
	border-radius: var(--MI-radius);
	font-size: 1.25em;
	user-select: none;
	&:active { background: var(--MI_THEME-accentedBg); }
}

.stats {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
	gap: 16px;
	margin: 24px 0;

	dt { font-size: .85em; }
	dd { margin: 6px 0 0; font-size: 1.4em; font-variant-numeric: tabular-nums; }
}
</style>
