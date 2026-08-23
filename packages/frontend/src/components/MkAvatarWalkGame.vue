<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div
	:class="[$style.root, { [$style.compact]: compact }]"
	@dragover.prevent.stop
	@drop.prevent.stop="onDrop"
>
	<input
		ref="fileInputEl"
		:class="$style.fileInput"
		type="file"
		accept=".vrm,model/vrm"
		@change="onFileSelected"
	>

	<div v-if="loadingStored" :class="$style.loading">
		<MkLoading/>
	</div>

	<button
		v-else-if="atlas == null"
		type="button"
		class="_button"
		:class="$style.dropZone"
		:disabled="operationLocked"
		@click="chooseVrm"
	>
		<i class="ti ti-cube-3d-sphere" :class="$style.dropIcon"></i>
		<strong>{{ i18n.ts._avatarWalk.dropVrm }}</strong>
		<span>{{ i18n.ts._avatarWalk.dropVrmDescription }}</span>
		<span :class="$style.localOnly"><i class="ti ti-device-desktop-lock"></i> {{ i18n.ts._avatarWalk.localOnly }}</span>
	</button>

	<template v-else>
		<div
			ref="gameFrameEl"
			:class="$style.gameFrame"
			@focusin="focused = true"
			@focusout="onGameFocusOut"
			@keydown="onKeydown"
			@keyup="onKeyup"
		>
			<canvas
				ref="canvasEl"
				:class="$style.canvas"
				:width="GAME_WIDTH * CANVAS_RENDER_SCALE"
				:height="GAME_HEIGHT * CANVAS_RENDER_SCALE"
				tabindex="0"
				:aria-label="i18n.ts._avatarWalk.gameCanvasLabel"
				@pointerdown="focusGame"
				@wheel.prevent="onWheel"
				@contextmenu.prevent
			></canvas>
			<div :class="[$style.focusStatus, { [$style.active]: focused }]">
				<i :class="focused ? 'ti ti-keyboard' : 'ti ti-hand-click'"></i>
				{{ focused ? i18n.ts._avatarWalk.controls : i18n.ts._avatarWalk.focusToPlay }}
			</div>
			<div
				:class="[$style.multiplayerStatus, { [$style.online]: avatarWalkConnectionStatus === 'connected' }]"
				role="status"
				aria-live="polite"
			>
				<i :class="avatarWalkConnectionStatus === 'connected' ? 'ti ti-users' : 'ti ti-cloud-off'"></i>
				{{ multiplayerStatusLabel }}
			</div>
			<div :class="$style.zoomControls">
				<button
					type="button"
					class="_button"
					:class="$style.zoomButton"
					:disabled="cameraZoom <= MIN_CAMERA_ZOOM"
					:aria-label="zoomOutLabel"
					:title="zoomOutLabel"
					@click="zoomOut"
				>
					−
				</button>
				<button
					type="button"
					class="_button"
					:class="$style.zoomLevel"
					:aria-label="resetZoomLabel"
					:title="resetZoomLabel"
					@click="resetZoom"
				>
					{{ zoomPercent }}%
				</button>
				<button
					type="button"
					class="_button"
					:class="$style.zoomButton"
					:disabled="cameraZoom >= MAX_CAMERA_ZOOM"
					:aria-label="zoomInLabel"
					:title="zoomInLabel"
					@click="zoomIn"
				>
					+
				</button>
			</div>
		</div>

		<div v-if="!compact" :class="$style.motionHotbar" role="toolbar" :aria-label="motionToolbarLabel">
			<button
				v-for="(motion, index) in motionItems"
				:key="motion.type"
				type="button"
				class="_button"
				:class="[$style.motionSlot, { [$style.active]: avatarWalkLocalPlayer.action?.type === motion.type }]"
				:aria-label="motion.label"
				:aria-pressed="avatarWalkLocalPlayer.action?.type === motion.type"
				:title="motion.label"
				@click="playAction(motion.type)"
			>
				<span :class="$style.motionNumber">{{ index + 1 }}</span>
				<i :class="motion.icon"></i>
				<span :class="$style.motionLabel">{{ motion.label }}</span>
			</button>
		</div>

		<div :class="$style.toolbar">
			<MkButton small inline :disabled="operationLocked" @click="chooseVrm">
				<i class="ti ti-refresh"></i> {{ i18n.ts._avatarWalk.replaceAvatar }}
			</MkButton>
			<MkButton small inline danger :disabled="operationLocked" @click="removeAvatar">
				<i class="ti ti-trash"></i> {{ i18n.ts._avatarWalk.removeAvatar }}
			</MkButton>
		</div>

		<div v-if="atlas.model.name || atlas.model.authors.length > 0 || atlas.model.licenseUrl" :class="$style.modelInfo" class="_selectable">
			<strong v-if="atlas.model.name">{{ atlas.model.name }}</strong>
			<span v-if="atlas.model.authors.length > 0">{{ i18n.ts.author }}: {{ atlas.model.authors.join(', ') }}</span>
			<a v-if="atlas.model.licenseUrl" class="_link" :href="atlas.model.licenseUrl" target="_blank" rel="noopener noreferrer">{{ i18n.ts.license }}</a>
		</div>
	</template>

	<div v-if="processing" :class="$style.processing" role="status" aria-live="polite">
		<MkLoading/>
		<strong>{{ progressLabel }}</strong>
		<div :class="$style.progressTrack">
			<div :class="$style.progressBar" :style="{ width: `${progressPercent}%` }"></div>
		</div>
		<span>{{ progressPercent }}%</span>
	</div>
</div>
</template>

<script lang="ts" setup>
import { computed, onActivated, onDeactivated, onMounted, onUnmounted, ref, shallowRef, useTemplateRef, watch } from 'vue';
import type * as Misskey from 'misskey-js';
import type { AvatarWalkAtlasProgress, StoredAvatarWalkAtlas } from '@/utility/avatar-walk-atlas.js';
import MkButton from '@/components/MkButton.vue';
import { i18n } from '@/i18n.js';
import * as os from '@/os.js';
import {
	AVATAR_WALK_ATLAS_UPDATED_EVENT,
	AVATAR_WALK_ACTIONS,
	AVATAR_WALK_MOTION_FRAME_COUNT,
	avatarWalkOperationLocked as operationLocked,
	generateAvatarWalkAtlas,
	InvalidVrmError,
	loadAvatarWalkAtlas,
	removeAvatarWalkAtlas,
	VrmFileTooLargeError,
} from '@/utility/avatar-walk-atlas.js';
import {
	removeAvatarWalkSharing,
	retryAvatarWalkPendingDeletes,
	syncAvatarWalkSharing,
} from '@/utility/avatar-walk-sharing.js';
import {
	acquireAvatarWalkMultiplayer,
	avatarWalkConnectionStatus,
	avatarWalkLocalPlayer,
	avatarWalkOnlineCount,
	avatarWalkRemotePlayers,
} from '@/utility/avatar-walk-multiplayer.js';

withDefaults(defineProps<{
	compact?: boolean;
}>(), {
	compact: false,
});

const GAME_WIDTH = 480;
const GAME_HEIGHT = 320;
const CANVAS_RENDER_SCALE = 2;
const DEFAULT_CAMERA_ZOOM = 0.75;
const MIN_CAMERA_ZOOM = 0.5;
const MAX_CAMERA_ZOOM = 1.1;
const CAMERA_ZOOM_STEP = 0.05;
const WORLD_WIDTH = 1600;
const WORLD_HEIGHT = 1200;
const PLAYER_SPEED = 180;
const PLAYER_RADIUS = 18;
const SPRITE_WIDTH = 92;
const SPRITE_HEIGHT = 138;
const SPRITE_FRAME_MS = 1000 / 6;
const MOTION_FRAME_MS = SPRITE_FRAME_MS;
const MOTION_DURATION = AVATAR_WALK_MOTION_FRAME_COUNT * MOTION_FRAME_MS;

const MOTION_DURATIONS: Record<Misskey.AvatarWalkActionType, number | null> = {
	sit: null,
	wave: MOTION_DURATION,
	bow: MOTION_DURATION,
	cheer: MOTION_DURATION,
};

type WorldTree = {
	x: number;
	y: number;
	radius: number;
	scale: number;
};

type MotionHotbarItem = {
	type: Misskey.AvatarWalkActionType;
	label: string;
	icon: string;
};

const trees: WorldTree[] = [
	{ x: 210, y: 180, radius: 34, scale: 1.05 },
	{ x: 360, y: 300, radius: 30, scale: 0.9 },
	{ x: 1180, y: 210, radius: 36, scale: 1.15 },
	{ x: 1360, y: 410, radius: 31, scale: 0.95 },
	{ x: 260, y: 880, radius: 38, scale: 1.2 },
	{ x: 520, y: 1010, radius: 32, scale: 1 },
	{ x: 1110, y: 940, radius: 34, scale: 1.05 },
	{ x: 1390, y: 1030, radius: 37, scale: 1.15 },
];

const fileInputEl = useTemplateRef('fileInputEl');
const gameFrameEl = useTemplateRef('gameFrameEl');
const canvasEl = useTemplateRef('canvasEl');
const atlas = shallowRef<StoredAvatarWalkAtlas | null>(null);
const loadingStored = ref(true);
const processing = ref(false);
const progress = ref<AvatarWalkAtlasProgress>({ stage: 'loading', completed: 0, total: 1 });
const focused = ref(false);
const cameraZoom = ref(DEFAULT_CAMERA_ZOOM);
const pressedKeys = new Set<string>();
let atlasImage: HTMLImageElement | null = null;
let atlasObjectUrl: string | null = null;
let animationFrameId: number | null = null;
let lastFrameTime: number | null = null;
let visible = true;
let pageActive = true;
let intersectionObserver: IntersectionObserver | null = null;
let atlasLoadSequence = 0;
let mounted = false;
let releaseMultiplayer: (() => void) | null = null;
let lastRemoteFrameTime: number | null = null;

type RemoteRenderPlayer = Misskey.AvatarWalkPlayer & {
	renderX: number;
	renderY: number;
};

type RemoteNameBadge = {
	label: string;
	x: number;
	y: number;
};

type RemoteAvatarImage = {
	url: string | null;
	image: HTMLImageElement | null;
	loader: HTMLImageElement | null;
	failedAt: number | null;
};

const remoteRenderPlayers = new Map<string, RemoteRenderPlayer>();
const remoteAvatarImages = new Map<string, RemoteAvatarImage>();
const remoteAtlasImages = new Map<string, RemoteAvatarImage>();

const progressPercent = computed(() => Math.round(progress.value.total === 0
	? 0
	: progress.value.completed / progress.value.total * 100));

const zoomPercent = computed(() => Math.round(cameraZoom.value * 100));
const zoomOutLabel = computed(() => `${zoomPercent.value}% · ${avatarWalkLocaleString('zoomOut', `− ${i18n.ts._avatarWalk.gameCanvasLabel}`)}`);
const zoomInLabel = computed(() => `${zoomPercent.value}% · ${avatarWalkLocaleString('zoomIn', `+ ${i18n.ts._avatarWalk.gameCanvasLabel}`)}`);
const resetZoomLabel = computed(() => `${zoomPercent.value}% · ${avatarWalkLocaleString('resetZoom', i18n.ts.reset)}`);
const motionToolbarLabel = computed(() => avatarWalkLocaleString('motions', i18n.ts.operations));
const motionItems = computed<MotionHotbarItem[]>(() => [
	{ type: 'sit', label: avatarWalkLocaleString('motionSit', `${i18n.ts.operations} 1`), icon: 'ti ti-armchair' },
	{ type: 'wave', label: avatarWalkLocaleString('motionWave', `${i18n.ts.operations} 2`), icon: 'ti ti-hand-stop' },
	{ type: 'bow', label: avatarWalkLocaleString('motionBow', `${i18n.ts.operations} 3`), icon: 'ti ti-pray' },
	{ type: 'cheer', label: avatarWalkLocaleString('motionCheer', `${i18n.ts.operations} 4`), icon: 'ti ti-mood-happy' },
]);
const multiplayerStatusLabel = computed(() => {
	if (avatarWalkConnectionStatus.value === 'unavailable') return i18n.ts.signinRequired;
	if (avatarWalkConnectionStatus.value !== 'connected') return i18n.ts.loading;
	return i18n.tsx.onlineUsersCount({ n: avatarWalkOnlineCount.value });
});
const progressLabel = computed(() => {
	if (progress.value.stage === 'loading') return i18n.ts._avatarWalk.loadingVrm;
	if (progress.value.stage === 'rendering') return i18n.ts._avatarWalk.renderingAtlas;
	return i18n.ts._avatarWalk.savingAtlas;
});

function avatarWalkLocaleString(key: keyof typeof i18n.ts._avatarWalk, fallback: string): string {
	if (!Object.hasOwn(i18n.ts._avatarWalk, key)) return fallback;
	const value = i18n.ts._avatarWalk[key];
	return typeof value === 'string' ? value : fallback;
}

function chooseVrm(): void {
	if (operationLocked.value) return;
	fileInputEl.value?.click();
}

function onFileSelected(event: Event): void {
	const input = event.currentTarget as HTMLInputElement;
	const file = input.files?.[0];
	input.value = '';
	if (file != null) void importVrm(file);
}

function onDrop(event: DragEvent): void {
	if (operationLocked.value) return;
	const file = event.dataTransfer?.files[0];
	if (file != null) void importVrm(file);
}

async function importVrm(file: File): Promise<void> {
	if (operationLocked.value) return;
	operationLocked.value = true;
	processing.value = true;
	progress.value = { stage: 'loading', completed: 0, total: 1 };
	pressedKeys.clear();
	try {
		await generateAvatarWalkAtlas(file, value => {
			progress.value = value;
		});
		await refreshAtlas();
		os.toast(i18n.ts._avatarWalk.avatarReady);
	} catch (error) {
		const text = error instanceof VrmFileTooLargeError
			? i18n.ts._avatarWalk.fileTooLarge
			: error instanceof InvalidVrmError
				? i18n.ts._avatarWalk.invalidVrm
				: i18n.ts._avatarWalk.generationFailed;
		await os.alert({ type: 'error', text });
	} finally {
		processing.value = false;
		operationLocked.value = false;
	}
}

async function removeAvatar(): Promise<void> {
	if (operationLocked.value) return;
	operationLocked.value = true;
	try {
		const { canceled } = await os.confirm({
			type: 'warning',
			text: i18n.ts._avatarWalk.removeConfirm,
		});
		if (canceled) return;
		await removeAvatarWalkAtlas();
		const sharedFileRemoved = await removeAvatarWalkSharing();
		await refreshAtlas();
		if (!sharedFileRemoved) await os.alert({ type: 'warning', text: i18n.ts._avatarWalk.sharedFileDeleteFailed });
	} catch {
		await os.alert({ type: 'error', text: i18n.ts._avatarWalk.storageFailed });
	} finally {
		operationLocked.value = false;
	}
}

async function refreshAtlas(): Promise<void> {
	const sequence = ++atlasLoadSequence;
	const stored = await loadAvatarWalkAtlas();
	if (!isCurrentAtlasLoad(sequence)) return;

	if (atlasObjectUrl != null) {
		URL.revokeObjectURL(atlasObjectUrl);
		atlasObjectUrl = null;
	}
	atlasImage = null;
	atlas.value = stored;
	if (stored == null) {
		updateMultiplayerState();
		updateAnimationState();
		return;
	}

	const objectUrl = URL.createObjectURL(stored.image);
	const image = new Image();
	await new Promise<void>((resolve, reject) => {
		image.onload = () => resolve();
		image.onerror = () => {
			URL.revokeObjectURL(objectUrl);
			reject(new Error('Failed to load avatar atlas'));
		};
		image.src = objectUrl;
	});
	if (!isCurrentAtlasLoad(sequence)) {
		URL.revokeObjectURL(objectUrl);
		return;
	}
	atlasObjectUrl = objectUrl;
	atlasImage = image;
	void syncAvatarWalkSharing(stored).catch(() => undefined);
	updateMultiplayerState();
	updateAnimationState();
}

function isCurrentAtlasLoad(sequence: number): boolean {
	return mounted && sequence === atlasLoadSequence;
}

function updateMultiplayerState(): void {
	const shouldConnect = pageActive && atlas.value != null;
	if (shouldConnect && releaseMultiplayer == null) {
		releaseMultiplayer = acquireAvatarWalkMultiplayer();
	} else if (!shouldConnect && releaseMultiplayer != null) {
		releaseMultiplayer();
		releaseMultiplayer = null;
		remoteRenderPlayers.clear();
		disposeAllRemoteAvatarImages();
		disposeAllRemoteAtlasImages();
	}
}

function focusGame(): void {
	canvasEl.value?.focus();
}

function onWheel(event: WheelEvent): void {
	if (event.deltaY === 0) return;
	focusGame();
	setCameraZoom(cameraZoom.value - Math.sign(event.deltaY) * CAMERA_ZOOM_STEP);
}

function zoomOut(): void {
	setCameraZoom(cameraZoom.value - CAMERA_ZOOM_STEP);
}

function zoomIn(): void {
	setCameraZoom(cameraZoom.value + CAMERA_ZOOM_STEP);
}

function resetZoom(): void {
	setCameraZoom(DEFAULT_CAMERA_ZOOM);
}

function playAction(type: Misskey.AvatarWalkActionType): void {
	pressedKeys.clear();
	avatarWalkLocalPlayer.moving = false;
	if (type === 'sit' && avatarWalkLocalPlayer.action?.type === 'sit') {
		avatarWalkLocalPlayer.action = null;
		return;
	}
	avatarWalkLocalPlayer.action = { type, startedAt: Date.now() };
}

function setCameraZoom(value: number): void {
	cameraZoom.value = clamp(Math.round(value * 100) / 100, MIN_CAMERA_ZOOM, MAX_CAMERA_ZOOM);
}

function onKeydown(event: KeyboardEvent): void {
	if (isMisskeyPostShortcut(event)) return;
	event.stopPropagation();
	if (!isMovementKey(event.code)) return;
	event.preventDefault();
	pressedKeys.add(event.code);
}

function onKeyup(event: KeyboardEvent): void {
	if (isMisskeyPostShortcut(event)) return;
	event.stopPropagation();
	if (!isMovementKey(event.code)) return;
	event.preventDefault();
	pressedKeys.delete(event.code);
}

function onGameFocusOut(event: FocusEvent): void {
	if (event.relatedTarget instanceof Node && gameFrameEl.value?.contains(event.relatedTarget)) return;
	focused.value = false;
	pressedKeys.clear();
	avatarWalkLocalPlayer.moving = false;
}

function isMovementKey(code: string): boolean {
	return code === 'KeyW' || code === 'KeyA' || code === 'KeyS' || code === 'KeyD' ||
		code === 'ArrowUp' || code === 'ArrowLeft' || code === 'ArrowDown' || code === 'ArrowRight';
}

function isMisskeyPostShortcut(event: KeyboardEvent): boolean {
	return event.key.toLowerCase() === 'n' && !event.ctrlKey && !event.metaKey && !event.altKey && !event.shiftKey;
}

function animate(time: number): void {
	animationFrameId = null;
	if (!shouldAnimate()) return;

	const delta = lastFrameTime == null ? 0 : Math.min((time - lastFrameTime) / 1000, 0.05);
	lastFrameTime = time;
	updatePlayer(delta);
	drawGame(time);
	animationFrameId = window.requestAnimationFrame(animate);
}

function shouldAnimate(): boolean {
	return pageActive && visible && !window.document.hidden && atlasImage != null && atlas.value != null && canvasEl.value != null;
}

function updateAnimationState(): void {
	if (shouldAnimate()) {
		if (animationFrameId == null) {
			lastFrameTime = null;
			animationFrameId = window.requestAnimationFrame(animate);
		}
	} else if (animationFrameId != null) {
		window.cancelAnimationFrame(animationFrameId);
		animationFrameId = null;
		lastFrameTime = null;
	}
}

function updatePlayer(delta: number): void {
	const action = getVisibleAction(avatarWalkLocalPlayer.action);
	if (avatarWalkLocalPlayer.action != null && action == null) avatarWalkLocalPlayer.action = null;
	if (!focused.value) return;
	let x = 0;
	let y = 0;
	if (pressedKeys.has('KeyA') || pressedKeys.has('ArrowLeft')) x--;
	if (pressedKeys.has('KeyD') || pressedKeys.has('ArrowRight')) x++;
	if (pressedKeys.has('KeyW') || pressedKeys.has('ArrowUp')) y--;
	if (pressedKeys.has('KeyS') || pressedKeys.has('ArrowDown')) y++;
	avatarWalkLocalPlayer.moving = x !== 0 || y !== 0;
	if (!avatarWalkLocalPlayer.moving) return;
	avatarWalkLocalPlayer.action = null;

	const length = Math.hypot(x, y);
	x /= length;
	y /= length;
	avatarWalkLocalPlayer.direction = (Math.round(Math.atan2(x, y) / (Math.PI / 4)) + 8) % 8;
	const distance = PLAYER_SPEED * delta;
	const nextX = avatarWalkLocalPlayer.x + x * distance;
	const nextY = avatarWalkLocalPlayer.y + y * distance;
	if (canMoveTo(nextX, avatarWalkLocalPlayer.y)) avatarWalkLocalPlayer.x = nextX;
	if (canMoveTo(avatarWalkLocalPlayer.x, nextY)) avatarWalkLocalPlayer.y = nextY;
}

function canMoveTo(x: number, y: number): boolean {
	if (x < PLAYER_RADIUS || x > WORLD_WIDTH - PLAYER_RADIUS || y < PLAYER_RADIUS || y > WORLD_HEIGHT - PLAYER_RADIUS) return false;
	if (x > 80 && x < 430 && y > 470 && y < 730) return false;
	return trees.every(tree => Math.hypot(x - tree.x, y - tree.y) > PLAYER_RADIUS + tree.radius);
}

function drawGame(time: number): void {
	const canvas = canvasEl.value;
	const storedAtlas = atlas.value;
	if (canvas == null || storedAtlas == null || atlasImage == null) return;
	const context = canvas.getContext('2d');
	if (context == null) return;
	context.setTransform(CANVAS_RENDER_SCALE, 0, 0, CANVAS_RENDER_SCALE, 0, 0);
	context.imageSmoothingEnabled = false;

	const viewWidth = GAME_WIDTH / cameraZoom.value;
	const viewHeight = GAME_HEIGHT / cameraZoom.value;
	const cameraX = Math.round(clamp(avatarWalkLocalPlayer.x - viewWidth / 2, 0, WORLD_WIDTH - viewWidth));
	const cameraY = Math.round(clamp(avatarWalkLocalPlayer.y - viewHeight / 2, 0, WORLD_HEIGHT - viewHeight));
	context.save();
	context.scale(cameraZoom.value, cameraZoom.value);
	drawGround(context, cameraX, cameraY, viewWidth, viewHeight);
	drawPond(context, cameraX, cameraY);
	drawMarket(context, cameraX, cameraY);

	const remotePlayers = updateRemoteRenderPlayers(time);
	const remoteNameBadges: RemoteNameBadge[] = [];
	const drawables: ({ type: 'tree'; y: number; tree: WorldTree } | { type: 'remote'; y: number; player: RemoteRenderPlayer } | { type: 'local'; y: number })[] = [
		...trees.map(tree => ({ type: 'tree' as const, y: tree.y, tree })),
		...remotePlayers.map(player => ({ type: 'remote' as const, y: player.renderY, player })),
		{ type: 'local', y: avatarWalkLocalPlayer.y },
	];
	drawables.sort((a, b) => a.y - b.y);
	for (const drawable of drawables) {
		if (drawable.type === 'tree') drawTree(context, drawable.tree, cameraX, cameraY);
		else if (drawable.type === 'remote') remoteNameBadges.push(drawRemotePlayer(context, drawable.player, time, cameraX, cameraY));
		else drawLocalPlayer(context, storedAtlas, time, cameraX, cameraY);
	}
	context.restore();
	for (const badge of remoteNameBadges) drawRemoteNameBadge(context, badge, cameraZoom.value);

	context.fillStyle = 'rgba(23, 33, 58, 0.5)';
	context.fillRect(0, GAME_HEIGHT - 13, GAME_WIDTH, 13);
}

function drawGround(context: CanvasRenderingContext2D, cameraX: number, cameraY: number, viewWidth: number, viewHeight: number): void {
	context.fillStyle = '#78a66a';
	context.fillRect(0, 0, viewWidth, viewHeight);
	const tileSize = 32;
	const startX = -cameraX % tileSize;
	const startY = -cameraY % tileSize;
	for (let y = startY; y < viewHeight; y += tileSize) {
		for (let x = startX; x < viewWidth; x += tileSize) {
			const worldX = Math.floor((x + cameraX) / tileSize);
			const worldY = Math.floor((y + cameraY) / tileSize);
			context.fillStyle = (worldX + worldY) % 2 === 0 ? '#80ae70' : '#76a267';
			context.fillRect(Math.floor(x), Math.floor(y), tileSize, tileSize);
		}
	}

	context.fillStyle = '#c3ad7b';
	context.fillRect(690 - cameraX, -cameraY, 220, WORLD_HEIGHT);
	context.fillRect(-cameraX, 520 - cameraY, WORLD_WIDTH, 170);
	context.strokeStyle = '#9b845d';
	context.lineWidth = 3;
	context.strokeRect(690 - cameraX, -cameraY, 220, WORLD_HEIGHT);
	context.strokeRect(-cameraX, 520 - cameraY, WORLD_WIDTH, 170);
}

function drawPond(context: CanvasRenderingContext2D, cameraX: number, cameraY: number): void {
	const x = 80 - cameraX;
	const y = 470 - cameraY;
	context.fillStyle = '#4c7f9e';
	context.beginPath();
	context.ellipse(x + 175, y + 130, 175, 130, 0, 0, Math.PI * 2);
	context.fill();
	context.strokeStyle = '#d4c68d';
	context.lineWidth = 9;
	context.stroke();
	context.strokeStyle = '#73abc2';
	context.lineWidth = 3;
	context.beginPath();
	context.arc(x + 130, y + 110, 45, 0.2, 2.6);
	context.stroke();
}

function drawMarket(context: CanvasRenderingContext2D, cameraX: number, cameraY: number): void {
	const x = 1110 - cameraX;
	const y = 520 - cameraY;
	context.fillStyle = '#6f4d3b';
	context.fillRect(x + 12, y + 45, 150, 90);
	context.fillStyle = '#d9c28f';
	context.fillRect(x + 24, y + 65, 126, 70);
	context.fillStyle = '#985b55';
	context.beginPath();
	context.moveTo(x, y + 50);
	context.lineTo(x + 87, y);
	context.lineTo(x + 175, y + 50);
	context.closePath();
	context.fill();
	context.fillStyle = '#4d382f';
	context.fillRect(x + 72, y + 92, 30, 43);
}

function drawTree(context: CanvasRenderingContext2D, tree: WorldTree, cameraX: number, cameraY: number): void {
	const x = tree.x - cameraX;
	const y = tree.y - cameraY;
	context.fillStyle = '#513b2d';
	context.fillRect(x - 7 * tree.scale, y - 42 * tree.scale, 14 * tree.scale, 45 * tree.scale);
	context.fillStyle = '#315c3e';
	context.beginPath();
	context.arc(x, y - 66 * tree.scale, 38 * tree.scale, 0, Math.PI * 2);
	context.fill();
	context.fillStyle = '#477a4b';
	context.beginPath();
	context.arc(x - 12 * tree.scale, y - 78 * tree.scale, 25 * tree.scale, 0, Math.PI * 2);
	context.fill();
}

function drawLocalPlayer(
	context: CanvasRenderingContext2D,
	storedAtlas: StoredAvatarWalkAtlas,
	time: number,
	cameraX: number,
	cameraY: number,
): void {
	const image = atlasImage;
	if (image == null) return;
	const screenX = avatarWalkLocalPlayer.x - cameraX;
	const screenY = avatarWalkLocalPlayer.y - cameraY;
	context.fillStyle = 'rgba(23, 33, 58, 0.35)';
	context.beginPath();
	context.ellipse(screenX, screenY + 2, 30, 10, 0, 0, Math.PI * 2);
	context.fill();

	drawAtlasPlayerSprite(context, image, storedAtlas, avatarWalkLocalPlayer.direction, avatarWalkLocalPlayer.moving, avatarWalkLocalPlayer.action, time, screenX, screenY, storedAtlas.version >= 2);
}

function updateRemoteRenderPlayers(time: number): RemoteRenderPlayer[] {
	const delta = lastRemoteFrameTime == null ? 0 : Math.min((time - lastRemoteFrameTime) / 1000, 0.1);
	lastRemoteFrameTime = time;
	const activeUserIds = new Set<string>();

	for (const player of avatarWalkRemotePlayers.values()) {
		activeUserIds.add(player.user.id);
		const existing = remoteRenderPlayers.get(player.user.id);
		if (existing == null) {
			remoteRenderPlayers.set(player.user.id, {
				...player,
				renderX: player.x,
				renderY: player.y,
			});
			continue;
		}

		const interpolation = 1 - Math.exp(-delta / 0.12);
		existing.renderX += (player.x - existing.renderX) * interpolation;
		existing.renderY += (player.y - existing.renderY) * interpolation;
		existing.x = player.x;
		existing.y = player.y;
		existing.direction = player.direction;
		existing.moving = player.moving;
		existing.action = player.action;
		existing.updatedAt = player.updatedAt;
		existing.user = player.user;
		existing.atlas = player.atlas;
	}

	for (const userId of remoteRenderPlayers.keys()) {
		if (!activeUserIds.has(userId)) {
			remoteRenderPlayers.delete(userId);
			disposeRemoteAvatarImage(userId);
			disposeRemoteAtlasImage(userId);
		}
	}

	return [...remoteRenderPlayers.values()];
}

function drawRemotePlayer(
	context: CanvasRenderingContext2D,
	player: RemoteRenderPlayer,
	time: number,
	cameraX: number,
	cameraY: number,
): RemoteNameBadge {
	const screenX = player.renderX - cameraX;
	const screenY = player.renderY - cameraY;

	context.fillStyle = 'rgba(23, 33, 58, 0.3)';
	context.beginPath();
	context.ellipse(screenX, screenY + 2, player.atlas == null ? 24 : 30, player.atlas == null ? 8 : 10, 0, 0, Math.PI * 2);
	context.fill();

	const sharedImage = getRemoteAtlasImage(player);
	let labelY: number;
	if (player.atlas != null && sharedImage != null) {
		drawAtlasPlayerSprite(context, sharedImage, player.atlas, player.direction, player.moving, player.action, time, screenX, screenY, true);
		labelY = Math.round(screenY - SPRITE_HEIGHT - 12);
	} else {
		const bob = player.moving ? Math.round(Math.sin(time / 90) * 3) : 0;
		const avatarSize = 48;
		const avatarX = Math.round(screenX - avatarSize / 2);
		const avatarY = Math.round(screenY - 66 + bob);
		context.save();
		context.beginPath();
		context.arc(screenX, avatarY + avatarSize / 2, avatarSize / 2, 0, Math.PI * 2);
		context.clip();
		context.fillStyle = '#596882';
		context.fillRect(avatarX, avatarY, avatarSize, avatarSize);
		const image = getRemoteAvatarImage(player);
		if (image != null) {
			context.imageSmoothingEnabled = true;
			context.drawImage(image, avatarX, avatarY, avatarSize, avatarSize);
		} else {
			context.fillStyle = '#ffffff';
			context.font = 'bold 22px sans-serif';
			context.textAlign = 'center';
			context.textBaseline = 'middle';
			context.fillText(player.user.username.slice(0, 1).toUpperCase(), screenX, avatarY + avatarSize / 2);
		}
		context.restore();

		context.strokeStyle = '#ffffff';
		context.lineWidth = 3;
		context.beginPath();
		context.arc(screenX, avatarY + avatarSize / 2, avatarSize / 2, 0, Math.PI * 2);
		context.stroke();
		labelY = avatarY - 20;
	}

	return {
		label: player.user.name ?? `@${player.user.username}`,
		x: screenX,
		y: labelY,
	};
}

type RenderAtlas = Pick<StoredAvatarWalkAtlas, 'cellWidth' | 'cellHeight' | 'idleFrameCount' | 'walkFrameCount' | 'motionCount' | 'motionFrameCount'>;

function drawAtlasPlayerSprite(
	context: CanvasRenderingContext2D,
	image: HTMLImageElement,
	atlas: RenderAtlas,
	direction: number,
	moving: boolean,
	action: Misskey.AvatarWalkAction | null,
	time: number,
	screenX: number,
	screenY: number,
	smoothing: boolean,
): void {
	const visibleAction = moving ? null : getVisibleAction(action);
	const motionFrame = visibleAction == null ? null : getMotionFrame(atlas, visibleAction);
	const frame = motionFrame ?? (moving
		? atlas.idleFrameCount + Math.floor(time / SPRITE_FRAME_MS) % atlas.walkFrameCount
		: Math.floor(time / SPRITE_FRAME_MS) % atlas.idleFrameCount);
	const previousImageSmoothing = context.imageSmoothingEnabled;
	context.save();
	context.imageSmoothingEnabled = smoothing;
	context.drawImage(
		image,
		direction * atlas.cellWidth,
		frame * atlas.cellHeight,
		atlas.cellWidth,
		atlas.cellHeight,
		Math.round(screenX - SPRITE_WIDTH / 2),
		Math.round(screenY - SPRITE_HEIGHT + 8),
		SPRITE_WIDTH,
		SPRITE_HEIGHT,
	);
	context.restore();
	context.imageSmoothingEnabled = previousImageSmoothing;
}

function getMotionFrame(atlas: RenderAtlas, action: Misskey.AvatarWalkAction): number | null {
	const motionIndex = AVATAR_WALK_ACTIONS.indexOf(action.type);
	const frameCount = atlas.motionFrameCount ?? 0;
	if (motionIndex < 0 || motionIndex >= (atlas.motionCount ?? 0) || frameCount === 0) return null;
	const elapsed = Math.max(0, Date.now() - action.startedAt);
	const actionFrame = action.type === 'sit'
		? Math.min(frameCount - 1, Math.floor(elapsed / MOTION_FRAME_MS))
		: Math.floor(elapsed / MOTION_FRAME_MS) % frameCount;
	return atlas.idleFrameCount + atlas.walkFrameCount + motionIndex * frameCount + actionFrame;
}

function getVisibleAction(action: Misskey.AvatarWalkAction | null): Misskey.AvatarWalkAction | null {
	if (action == null) return null;
	const duration = MOTION_DURATIONS[action.type];
	return duration == null || Date.now() - action.startedAt < duration ? action : null;
}

function drawRemoteNameBadge(context: CanvasRenderingContext2D, badge: RemoteNameBadge, zoom: number): void {
	const screenX = Math.round(badge.x * zoom);
	const labelY = Math.round(badge.y * zoom);
	const fontSize = 12 * zoom;
	const labelHeight = 17 * zoom;
	const horizontalPadding = 12 * zoom;
	context.font = `bold ${fontSize}px sans-serif`;
	context.textAlign = 'center';
	context.textBaseline = 'middle';
	const labelWidth = Math.min(150 * zoom, context.measureText(badge.label).width + horizontalPadding);
	context.fillStyle = 'rgba(23, 33, 58, 0.72)';
	context.fillRect(Math.round(screenX - labelWidth / 2), labelY, labelWidth, labelHeight);
	context.fillStyle = '#ffffff';
	context.fillText(badge.label, screenX, labelY + labelHeight / 2, labelWidth - 8 * zoom);
}

function getRemoteAtlasImage(player: RemoteRenderPlayer): HTMLImageElement | null {
	const url = player.atlas?.url ?? null;
	const cached = remoteAtlasImages.get(player.user.id);
	if (cached?.url === url) {
		if (cached.image != null || cached.loader != null || cached.failedAt == null) return cached.image;
		if (Date.now() - cached.failedAt < 5000) return null;
		disposeRemoteAtlasImage(player.user.id);
	} else if (cached != null) {
		disposeRemoteAtlasImage(player.user.id);
	}
	if (url == null) return null;

	const entry: RemoteAvatarImage = { url, image: null, loader: null, failedAt: null };
	remoteAtlasImages.set(player.user.id, entry);
	const image = new Image();
	entry.loader = image;
	image.onload = () => {
		if (remoteAtlasImages.get(player.user.id) !== entry) return;
		entry.image = image;
		entry.loader = null;
	};
	image.onerror = () => {
		if (remoteAtlasImages.get(player.user.id) !== entry) return;
		entry.loader = null;
		entry.failedAt = Date.now();
	};
	image.src = url;
	return null;
}

function getRemoteAvatarImage(player: RemoteRenderPlayer): HTMLImageElement | null {
	const url = player.user.avatarUrl;
	const cached = remoteAvatarImages.get(player.user.id);
	if (cached?.url === url) {
		if (cached.image != null || cached.loader != null || cached.failedAt == null) return cached.image;
		if (Date.now() - cached.failedAt < 5000) return null;
		disposeRemoteAvatarImage(player.user.id);
	} else if (cached != null) {
		disposeRemoteAvatarImage(player.user.id);
	}

	const entry: RemoteAvatarImage = { url, image: null, loader: null, failedAt: null };
	remoteAvatarImages.set(player.user.id, entry);
	const image = new Image();
	entry.loader = image;
	image.onload = () => {
		if (remoteAvatarImages.get(player.user.id) !== entry) return;
		entry.image = image;
		entry.loader = null;
	};
	image.onerror = () => {
		if (remoteAvatarImages.get(player.user.id) !== entry) return;
		entry.loader = null;
		entry.failedAt = Date.now();
	};
	image.src = url;
	return null;
}

function disposeRemoteAvatarImage(userId: string): void {
	const entry = remoteAvatarImages.get(userId);
	if (entry?.loader != null) {
		entry.loader.onload = null;
		entry.loader.onerror = null;
		entry.loader.removeAttribute('src');
	}
	remoteAvatarImages.delete(userId);
}

function disposeAllRemoteAvatarImages(): void {
	for (const userId of remoteAvatarImages.keys()) disposeRemoteAvatarImage(userId);
}

function disposeRemoteAtlasImage(userId: string): void {
	const entry = remoteAtlasImages.get(userId);
	if (entry?.loader != null) {
		entry.loader.onload = null;
		entry.loader.onerror = null;
		entry.loader.removeAttribute('src');
	}
	remoteAtlasImages.delete(userId);
}

function disposeAllRemoteAtlasImages(): void {
	for (const userId of remoteAtlasImages.keys()) disposeRemoteAtlasImage(userId);
}

function clamp(value: number, min: number, max: number): number {
	return Math.min(max, Math.max(min, value));
}

function onAtlasUpdated(): void {
	void refreshAtlas();
}

watch(canvasEl, canvas => {
	intersectionObserver?.disconnect();
	intersectionObserver = null;
	visible = true;
	if (canvas == null || !('IntersectionObserver' in window)) {
		updateAnimationState();
		return;
	}

	intersectionObserver = new IntersectionObserver(entries => {
		visible = entries[0]?.isIntersecting ?? true;
		if (!visible) stopMovement();
		updateAnimationState();
	});
	intersectionObserver.observe(canvas);
	updateAnimationState();
}, { flush: 'post' });

function onVisibilityChange(): void {
	if (window.document.hidden) stopMovement();
	updateAnimationState();
}

function stopMovement(): void {
	pressedKeys.clear();
	avatarWalkLocalPlayer.moving = false;
}

onActivated(() => {
	pageActive = true;
	updateMultiplayerState();
	updateAnimationState();
});

onDeactivated(() => {
	pageActive = false;
	stopMovement();
	updateMultiplayerState();
	updateAnimationState();
});

onMounted(async () => {
	mounted = true;
	window.addEventListener(AVATAR_WALK_ATLAS_UPDATED_EVENT, onAtlasUpdated);
	window.document.addEventListener('visibilitychange', onVisibilityChange);
	void retryAvatarWalkPendingDeletes().catch(() => undefined);

	try {
		await refreshAtlas();
	} catch {
		await os.alert({ type: 'error', text: i18n.ts._avatarWalk.storageFailed });
	} finally {
		loadingStored.value = false;
	}

	updateAnimationState();
});

onUnmounted(() => {
	mounted = false;
	atlasLoadSequence++;
	pageActive = false;
	updateMultiplayerState();
	window.removeEventListener(AVATAR_WALK_ATLAS_UPDATED_EVENT, onAtlasUpdated);
	window.document.removeEventListener('visibilitychange', onVisibilityChange);
	intersectionObserver?.disconnect();
	updateAnimationState();
	if (atlasObjectUrl != null) URL.revokeObjectURL(atlasObjectUrl);
	stopMovement();
	disposeAllRemoteAvatarImages();
	disposeAllRemoteAtlasImages();
});
</script>

<style lang="scss" module>
.root {
	position: relative;
	min-height: 260px;
	background: var(--MI_THEME-panel);
	overflow: clip;
}

.compact {
	min-height: 220px;
}

.fileInput {
	display: none;
}

.loading {
	display: grid;
	min-height: 260px;
	place-items: center;
}

.dropZone {
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	gap: 10px;
	width: 100%;
	min-height: 260px;
	padding: 24px;
	border: 2px dashed var(--MI_THEME-divider);
	background: var(--MI_THEME-panel);
	color: var(--MI_THEME-fg);
	text-align: center;

	&:hover,
	&:focus-visible {
		border-color: var(--MI_THEME-accent);
		background: var(--MI_THEME-accentedBg);
	}
}

.dropIcon {
	font-size: 42px;
	color: var(--MI_THEME-accent);
}

.localOnly {
	font-size: 0.82em;
	color: var(--MI_THEME-fgHighlighted);
}

.gameFrame {
	position: relative;
	background: var(--MI_THEME-bg);
}

.canvas {
	display: block;
	width: 100%;
	aspect-ratio: 3 / 2;
	background: var(--MI_THEME-bg);
	outline: none;

	&:focus-visible {
		box-shadow: inset 0 0 0 3px var(--MI_THEME-focus);
	}
}

.focusStatus {
	position: absolute;
	top: 8px;
	left: 8px;
	padding: 5px 9px;
	border-radius: var(--MI-radius);
	background: color-mix(in srgb, var(--MI_THEME-panel) 82%, transparent);
	color: var(--MI_THEME-fg);
	font-size: 0.76em;
	pointer-events: none;

	&.active {
		color: var(--MI_THEME-accent);
	}
}

.multiplayerStatus {
	position: absolute;
	bottom: 20px;
	left: 8px;
	display: flex;
	align-items: center;
	gap: 5px;
	padding: 5px 9px;
	border-radius: var(--MI-radius);
	background: color-mix(in srgb, var(--MI_THEME-panel) 82%, transparent);
	color: var(--MI_THEME-fgHighlighted);
	font-size: 0.76em;
	pointer-events: none;

	&.online {
		color: var(--MI_THEME-accent);
	}
}

.zoomControls {
	position: absolute;
	top: 8px;
	right: 8px;
	display: flex;
	align-items: center;
	padding: 3px;
	border: 1px solid var(--MI_THEME-divider);
	border-radius: var(--MI-radius);
	background: color-mix(in srgb, var(--MI_THEME-panel) 88%, transparent);
	color: var(--MI_THEME-fg);
}

.zoomButton,
.zoomLevel {
	display: grid;
	height: 28px;
	place-items: center;
	border-radius: calc(var(--MI-radius) - 2px);

	&:hover,
	&:focus-visible {
		background: var(--MI_THEME-buttonHoverBg);
	}

	&:disabled {
		opacity: 0.45;
	}
}

.zoomButton {
	width: 28px;
	font-size: 1.1em;
}

.zoomLevel {
	min-width: 46px;
	padding: 0 5px;
	font-size: 0.75em;
	font-variant-numeric: tabular-nums;
}

.motionHotbar {
	display: flex;
	justify-content: center;
	gap: 6px;
	padding: 8px 10px;
	border-top: 1px solid var(--MI_THEME-divider);
	border-bottom: 1px solid var(--MI_THEME-divider);
	background: color-mix(in srgb, var(--MI_THEME-bg) 72%, var(--MI_THEME-panel));
}

.motionSlot {
	position: relative;
	display: grid;
	grid-template-rows: 1fr auto;
	width: 58px;
	height: 52px;
	place-items: center;
	border: 1px solid var(--MI_THEME-divider);
	border-radius: calc(var(--MI-radius) - 2px);
	background: var(--MI_THEME-panel);
	color: var(--MI_THEME-fg);
	box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--MI_THEME-fg) 5%, transparent);

	> i {
		align-self: end;
		font-size: 20px;
	}

	&:hover,
	&:focus-visible {
		border-color: var(--MI_THEME-accent);
		background: var(--MI_THEME-buttonHoverBg);
	}

	&.active {
		border-color: var(--MI_THEME-accent);
		background: var(--MI_THEME-accentedBg);
		color: var(--MI_THEME-accent);
		box-shadow: inset 0 0 0 1px var(--MI_THEME-accent);
	}
}

.motionNumber {
	position: absolute;
	top: 3px;
	left: 5px;
	color: var(--MI_THEME-fgHighlighted);
	font-size: 9px;
	font-variant-numeric: tabular-nums;
}

.motionLabel {
	align-self: start;
	font-size: 9px;
	line-height: 1.2;
}

.toolbar {
	display: flex;
	flex-wrap: wrap;
	align-items: center;
	gap: 8px;
	padding: 10px;
	border-top: 1px solid var(--MI_THEME-divider);
}

.modelInfo {
	display: flex;
	flex-wrap: wrap;
	gap: 4px 12px;
	padding: 0 12px 12px;
	color: var(--MI_THEME-fgHighlighted);
	font-size: 0.8em;
}

.processing {
	position: absolute;
	z-index: 2;
	inset: 0;
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	gap: 12px;
	padding: 24px;
	background: color-mix(in srgb, var(--MI_THEME-panel) 92%, transparent);
	color: var(--MI_THEME-fg);
}

.progressTrack {
	width: min(280px, 80%);
	height: 8px;
	border-radius: var(--MI-radius);
	background: var(--MI_THEME-divider);
	overflow: hidden;
}

.progressBar {
	height: 100%;
	background: var(--MI_THEME-accent);
	transition: width 0.15s linear;
}

@container (max-width: 360px) {
	.toolbar {
		justify-content: center;
	}

	.modelInfo {
		display: none;
	}
}
</style>
