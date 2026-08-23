/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { createStore, del, get, set } from 'idb-keyval';
import { ref } from 'vue';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import type { VRM, VRMMeta, VRMPose } from '@pixiv/three-vrm';

const STORAGE_KEY = 'avatarWalkGame::atlas';
const SHARED_STORAGE_KEY = 'avatarWalkGame::sharedAtlas';
const ATLAS_STORE = createStore('MisskeyAvatarWalk', 'atlas');
const ATLAS_VERSION = 5;
const CELL_WIDTH = 256;
const CELL_HEIGHT = 384;
const DIRECTION_COUNT = 8;
const IDLE_FRAME_COUNT = 4;
const WALK_FRAME_COUNT = 6;
const MOTION_FRAME_COUNT = 4;
export const AVATAR_WALK_ACTIONS = ['sit', 'wave', 'bow', 'cheer'] as const;
const FRAME_COUNT = IDLE_FRAME_COUNT + WALK_FRAME_COUNT + AVATAR_WALK_ACTIONS.length * MOTION_FRAME_COUNT;
const SHARED_ATLAS_SCALE = 0.5;

export const AVATAR_WALK_ATLAS_UPDATED_EVENT = 'misskey:avatarWalkAtlasUpdated';
export const MAX_VRM_FILE_SIZE = 100 * 1024 * 1024;

export type AvatarWalkAtlasProgress = {
	stage: 'loading' | 'rendering' | 'saving';
	completed: number;
	total: number;
};

export type StoredAvatarWalkAtlas = {
	version: 1 | 2 | 3 | 4 | typeof ATLAS_VERSION;
	image: Blob;
	cellWidth: number;
	cellHeight: number;
	directionCount: number;
	idleFrameCount: number;
	walkFrameCount: number;
	motionCount?: number;
	motionFrameCount?: number;
	createdAt: number;
	model: {
		name?: string;
		authors: string[];
		licenseUrl?: string;
	};
};

export type StoredSharedAvatarWalkAtlasActive = {
	fileId: string;
	sourceCreatedAt: number;
	version: number;
	cellWidth: number;
	cellHeight: number;
	directionCount: number;
	idleFrameCount: number;
	walkFrameCount: number;
	motionCount?: number;
	motionFrameCount?: number;
};

export type StoredSharedAvatarWalkAtlas = {
	ownerUserId: string;
	active: StoredSharedAvatarWalkAtlasActive | null;
	pendingDeleteFileIds: string[];
};

export type SharedAvatarWalkAtlasImage = Omit<StoredSharedAvatarWalkAtlasActive, 'fileId' | 'sourceCreatedAt'> & {
	image: Blob;
};

export const avatarWalkOperationLocked = ref(false);

export async function loadAvatarWalkAtlas(): Promise<StoredAvatarWalkAtlas | null> {
	let atlas = await get<StoredAvatarWalkAtlas>(STORAGE_KEY, ATLAS_STORE);
	if (atlas == null) {
		atlas = await get<StoredAvatarWalkAtlas>(STORAGE_KEY);
		if (atlas != null) {
			await set(STORAGE_KEY, atlas, ATLAS_STORE);
			await del(STORAGE_KEY);
		}
	}
	if ((atlas?.version !== 1 && atlas?.version !== 2 && atlas?.version !== 3 && atlas?.version !== 4 && atlas?.version !== ATLAS_VERSION) || !(atlas.image instanceof Blob)) return null;
	return atlas;
}

export async function removeAvatarWalkAtlas(): Promise<void> {
	await Promise.all([
		del(STORAGE_KEY, ATLAS_STORE),
		del(STORAGE_KEY),
	]);
	window.dispatchEvent(new CustomEvent(AVATAR_WALK_ATLAS_UPDATED_EVENT));
}

export async function loadSharedAvatarWalkAtlas(ownerUserId: string): Promise<StoredSharedAvatarWalkAtlas | null> {
	const shared = await get<StoredSharedAvatarWalkAtlas>(sharedStorageKey(ownerUserId), ATLAS_STORE);
	if (shared == null || shared.ownerUserId !== ownerUserId || !Array.isArray(shared.pendingDeleteFileIds)) return null;
	const active = normalizeSharedAtlasActive(shared.active);
	if (shared.active != null && active == null) return null;
	return {
		ownerUserId,
		active,
		pendingDeleteFileIds: shared.pendingDeleteFileIds.filter(fileId => typeof fileId === 'string' && fileId.length > 0),
	};
}

export async function saveSharedAvatarWalkAtlas(shared: StoredSharedAvatarWalkAtlas): Promise<void> {
	await set(sharedStorageKey(shared.ownerUserId), shared, ATLAS_STORE);
}

export async function removeSharedAvatarWalkAtlas(ownerUserId: string): Promise<void> {
	await del(sharedStorageKey(ownerUserId), ATLAS_STORE);
}

export async function loadLegacySharedAvatarWalkAtlas(): Promise<StoredSharedAvatarWalkAtlasActive | null> {
	return normalizeSharedAtlasActive(await get(SHARED_STORAGE_KEY, ATLAS_STORE));
}

export async function removeLegacySharedAvatarWalkAtlas(): Promise<void> {
	await del(SHARED_STORAGE_KEY, ATLAS_STORE);
}

export async function createSharedAvatarWalkAtlasImage(atlas: StoredAvatarWalkAtlas): Promise<SharedAvatarWalkAtlasImage> {
	const cellWidth = Math.round(atlas.cellWidth * SHARED_ATLAS_SCALE);
	const cellHeight = Math.round(atlas.cellHeight * SHARED_ATLAS_SCALE);
	const bitmap = await createImageBitmap(atlas.image);
	const canvas = window.document.createElement('canvas');
	canvas.width = cellWidth * atlas.directionCount;
	canvas.height = cellHeight * getAtlasFrameCount(atlas);
	const context = canvas.getContext('2d');
	if (context == null) {
		bitmap.close();
		throw new Error('Canvas 2D is unavailable');
	}

	try {
		context.imageSmoothingEnabled = true;
		context.imageSmoothingQuality = 'high';
		context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
		const image = await canvasToBlob(canvas, 'image/webp', 0.84);
		return {
			image,
			version: atlas.version,
			cellWidth,
			cellHeight,
			directionCount: atlas.directionCount,
			idleFrameCount: atlas.idleFrameCount,
			walkFrameCount: atlas.walkFrameCount,
			motionCount: atlas.motionCount,
			motionFrameCount: atlas.motionFrameCount,
		};
	} finally {
		bitmap.close();
		canvas.remove();
	}
}

function sharedStorageKey(ownerUserId: string): string {
	return `${SHARED_STORAGE_KEY}::${ownerUserId}`;
}

function normalizeSharedAtlasActive(value: unknown): StoredSharedAvatarWalkAtlasActive | null {
	if (value == null || typeof value !== 'object') return null;
	const active = value as Partial<StoredSharedAvatarWalkAtlasActive>;
	if (
		typeof active.fileId !== 'string' || active.fileId.length === 0 ||
		typeof active.sourceCreatedAt !== 'number' || !Number.isFinite(active.sourceCreatedAt) ||
		typeof active.version !== 'number' ||
		typeof active.cellWidth !== 'number' ||
		typeof active.cellHeight !== 'number' ||
		typeof active.directionCount !== 'number' ||
		typeof active.idleFrameCount !== 'number' ||
		typeof active.walkFrameCount !== 'number' ||
		(active.motionCount !== undefined && typeof active.motionCount !== 'number') ||
		(active.motionFrameCount !== undefined && typeof active.motionFrameCount !== 'number')
	) return null;
	return active as StoredSharedAvatarWalkAtlasActive;
}

function getAtlasFrameCount(atlas: Pick<StoredAvatarWalkAtlas, 'idleFrameCount' | 'walkFrameCount' | 'motionCount' | 'motionFrameCount'>): number {
	return atlas.idleFrameCount + atlas.walkFrameCount + (atlas.motionCount ?? 0) * (atlas.motionFrameCount ?? 0);
}

export async function generateAvatarWalkAtlas(
	file: File,
	onProgress?: (progress: AvatarWalkAtlasProgress) => void,
): Promise<StoredAvatarWalkAtlas> {
	if (!file.name.toLowerCase().endsWith('.vrm')) throw new InvalidVrmError();
	if (file.size > MAX_VRM_FILE_SIZE) throw new VrmFileTooLargeError();

	onProgress?.({ stage: 'loading', completed: 0, total: 1 });
	const fileBytes = await file.arrayBuffer();
	if (!hasGlbSignature(fileBytes)) throw new InvalidVrmError();

	const renderCanvas = window.document.createElement('canvas');
	renderCanvas.width = CELL_WIDTH;
	renderCanvas.height = CELL_HEIGHT;
	const atlasCanvas = window.document.createElement('canvas');
	atlasCanvas.width = CELL_WIDTH * DIRECTION_COUNT;
	atlasCanvas.height = CELL_HEIGHT * FRAME_COUNT;
	const atlasContext = atlasCanvas.getContext('2d');
	if (atlasContext == null) throw new Error('Canvas 2D is unavailable');
	atlasContext.imageSmoothingEnabled = true;

	const renderer = new THREE.WebGLRenderer({
		canvas: renderCanvas,
		alpha: true,
		antialias: true,
		powerPreference: 'high-performance',
		preserveDrawingBuffer: true,
	});
	renderer.setSize(CELL_WIDTH, CELL_HEIGHT, false);
	renderer.setPixelRatio(1);
	renderer.outputColorSpace = THREE.SRGBColorSpace;
	renderer.toneMapping = THREE.ACESFilmicToneMapping;
	renderer.toneMappingExposure = 1.1;
	renderer.setClearColor(0x000000, 0);

	let vrm: VRM | null = null;
	try {
		const loadingManager = new THREE.LoadingManager();
		loadingManager.setURLModifier((url) => {
			if (url.startsWith('blob:') || url.startsWith('data:')) return url;
			throw new InvalidVrmError();
		});

		const loader = new GLTFLoader(loadingManager);
		loader.register(parser => new VRMLoaderPlugin(parser));
		const gltf = await loader.parseAsync(fileBytes, '');
		vrm = gltf.userData.vrm as VRM | undefined ?? null;
		if (vrm == null) throw new InvalidVrmError();

		VRMUtils.rotateVRM0(vrm);
		const scene = new THREE.Scene();
		const avatarRoot = new THREE.Group();
		avatarRoot.add(vrm.scene);
		scene.add(avatarRoot);

		const hemisphereLight = new THREE.HemisphereLight(0xf8f5ff, 0x414b67, 2.2);
		const keyLight = new THREE.DirectionalLight(0xfff2dc, 3.2);
		keyLight.position.set(3, 6, 5);
		const fillLight = new THREE.DirectionalLight(0xb8d7ff, 1.1);
		fillLight.position.set(-4, 2, -3);
		scene.add(hemisphereLight, keyLight, fillLight);

		vrm.scene.updateWorldMatrix(true, true);
		const initialBounds = new THREE.Box3().setFromObject(vrm.scene);
		if (initialBounds.isEmpty()) throw new InvalidVrmError();
		const initialCenter = initialBounds.getCenter(new THREE.Vector3());
		vrm.scene.position.x -= initialCenter.x;
		vrm.scene.position.y -= initialBounds.min.y;
		vrm.scene.position.z -= initialCenter.z;
		vrm.scene.updateWorldMatrix(true, true);

		const bounds = new THREE.Box3().setFromObject(vrm.scene);
		const size = bounds.getSize(new THREE.Vector3());
		if (!Number.isFinite(size.y) || size.y <= 0) throw new InvalidVrmError();

		const viewHeight = Math.max(size.y * 1.18, 0.5);
		const viewWidth = viewHeight * (CELL_WIDTH / CELL_HEIGHT);
		const camera = new THREE.OrthographicCamera(
			-viewWidth / 2,
			viewWidth / 2,
			viewHeight / 2,
			-viewHeight / 2,
			0.01,
			size.y * 20,
		);
		const target = new THREE.Vector3(0, size.y * 0.5, 0);
		camera.position.copy(target).add(new THREE.Vector3(0, size.y * 2.4, size.y * 4.2));
		camera.lookAt(target);
		camera.updateProjectionMatrix();

		const total = DIRECTION_COUNT * FRAME_COUNT;
		let completed = 0;
		onProgress?.({ stage: 'rendering', completed, total });

		for (let direction = 0; direction < DIRECTION_COUNT; direction++) {
			avatarRoot.rotation.y = direction * Math.PI / 4;
			for (let frame = 0; frame < FRAME_COUNT; frame++) {
				vrm.humanoid.resetNormalizedPose();
				vrm.humanoid.setNormalizedPose(createAtlasPose(frame));
				vrm.springBoneManager?.reset();
				vrm.update(1 / 60);
				avatarRoot.updateWorldMatrix(true, true);
				renderer.render(scene, camera);
				atlasContext.clearRect(direction * CELL_WIDTH, frame * CELL_HEIGHT, CELL_WIDTH, CELL_HEIGHT);
				atlasContext.drawImage(renderCanvas, direction * CELL_WIDTH, frame * CELL_HEIGHT);
				completed++;
				onProgress?.({ stage: 'rendering', completed, total });
				if (completed % 4 === 0) await nextFrame();
			}
		}

		onProgress?.({ stage: 'saving', completed: 0, total: 1 });
		const image = await canvasToBlob(atlasCanvas);
		const atlas: StoredAvatarWalkAtlas = {
			version: ATLAS_VERSION,
			image,
			cellWidth: CELL_WIDTH,
			cellHeight: CELL_HEIGHT,
			directionCount: DIRECTION_COUNT,
			idleFrameCount: IDLE_FRAME_COUNT,
			walkFrameCount: WALK_FRAME_COUNT,
			motionCount: AVATAR_WALK_ACTIONS.length,
			motionFrameCount: MOTION_FRAME_COUNT,
			createdAt: Date.now(),
			model: getModelMetadata(vrm.meta),
		};
		await set(STORAGE_KEY, atlas, ATLAS_STORE);
		window.dispatchEvent(new CustomEvent(AVATAR_WALK_ATLAS_UPDATED_EVENT));
		onProgress?.({ stage: 'saving', completed: 1, total: 1 });
		return atlas;
	} finally {
		if (vrm != null) VRMUtils.deepDispose(vrm.scene);
		renderer.dispose();
		renderer.forceContextLoss();
		renderCanvas.remove();
		atlasCanvas.remove();
	}
}

export class InvalidVrmError extends Error {
	constructor() {
		super('Invalid VRM file');
		this.name = 'InvalidVrmError';
	}
}

export class VrmFileTooLargeError extends Error {
	constructor() {
		super('VRM file is too large');
		this.name = 'VrmFileTooLargeError';
	}
}

function hasGlbSignature(buffer: ArrayBuffer): boolean {
	if (buffer.byteLength < 12) return false;
	const bytes = new Uint8Array(buffer, 0, 4);
	return bytes[0] === 0x67 && bytes[1] === 0x6c && bytes[2] === 0x54 && bytes[3] === 0x46;
}

function getModelMetadata(meta: VRMMeta): StoredAvatarWalkAtlas['model'] {
	if (meta.metaVersion === '1') {
		return {
			name: normalizeMetadataText(meta.name),
			authors: meta.authors.slice(0, 10).map(normalizeMetadataText).filter(value => value != null),
			licenseUrl: normalizeExternalUrl(meta.otherLicenseUrl ?? meta.licenseUrl),
		};
	}
	return {
		name: normalizeMetadataText(meta.title),
		authors: meta.author ? [normalizeMetadataText(meta.author)].filter(value => value != null) : [],
		licenseUrl: normalizeExternalUrl(meta.otherLicenseUrl ?? meta.otherPermissionUrl),
	};
}

function normalizeMetadataText(value: string | undefined): string | undefined {
	const normalized = value == null
		? undefined
		: [...value].map(character => {
			const codePoint = character.codePointAt(0) ?? 0;
			return codePoint <= 0x1f || codePoint === 0x7f ? ' ' : character;
		}).join('').trim();
	return normalized ? normalized.slice(0, 200) : undefined;
}

function normalizeExternalUrl(value: string | undefined): string | undefined {
	if (value == null || value.length > 2048) return undefined;
	try {
		const url = new URL(value);
		return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : undefined;
	} catch {
		return undefined;
	}
}

function createIdlePose(frame: number): VRMPose {
	const phase = frame / IDLE_FRAME_COUNT * Math.PI * 2;
	const breath = Math.sin(phase) * 0.015;
	return {
		hips: { position: [0, breath, 0] },
		spine: { rotation: quaternion(-0.03 + breath, 0, 0) },
		leftUpperArm: { rotation: quaternion(0.04, 0, -1.18) },
		rightUpperArm: { rotation: quaternion(-0.04, 0, 1.18) },
		leftLowerArm: { rotation: quaternion(0, 0.05, -0.18) },
		rightLowerArm: { rotation: quaternion(0, -0.05, 0.18) },
	};
}

function createAtlasPose(frame: number): VRMPose {
	if (frame < IDLE_FRAME_COUNT) return createIdlePose(frame);
	if (frame < IDLE_FRAME_COUNT + WALK_FRAME_COUNT) return createWalkPose(frame - IDLE_FRAME_COUNT);
	const motionFrame = frame - IDLE_FRAME_COUNT - WALK_FRAME_COUNT;
	const action = AVATAR_WALK_ACTIONS[Math.floor(motionFrame / MOTION_FRAME_COUNT)] ?? AVATAR_WALK_ACTIONS[0];
	return createActionPose(action, motionFrame % MOTION_FRAME_COUNT);
}

function createActionPose(action: typeof AVATAR_WALK_ACTIONS[number], frame: number): VRMPose {
	const phase = frame / MOTION_FRAME_COUNT * Math.PI * 2;
	if (action === 'sit') {
		const amount = easeOut(Math.min(1, frame / (MOTION_FRAME_COUNT - 1)));
		return {
			hips: { position: [0, -0.34 * amount, 0.04 * amount], rotation: quaternion(-0.08 * amount, 0, 0) },
			spine: { rotation: quaternion(0.12 * amount, 0, 0) },
			leftUpperLeg: { rotation: quaternion(-1.18 * amount, 0, 0) },
			rightUpperLeg: { rotation: quaternion(-1.18 * amount, 0, 0) },
			leftLowerLeg: { rotation: quaternion(1.42 * amount, 0, 0) },
			rightLowerLeg: { rotation: quaternion(1.42 * amount, 0, 0) },
			leftUpperArm: { rotation: quaternion(0.16, 0, -1.1) },
			rightUpperArm: { rotation: quaternion(0.16, 0, 1.1) },
		};
	}
	if (action === 'wave') {
		return {
			spine: { rotation: quaternion(-0.04, 0, -0.04) },
			leftUpperArm: { rotation: quaternion(0.04, 0, -1.18) },
			rightUpperArm: { rotation: quaternion(-0.18, 0, 2.35) },
			rightLowerArm: { rotation: quaternion(0, Math.sin(phase) * 0.35, 0.72 + Math.sin(phase) * 0.28) },
		};
	}
	if (action === 'bow') {
		const amount = [0, 0.65, 1, 0.35][frame] ?? 0;
		return {
			hips: { rotation: quaternion(0.22 * amount, 0, 0) },
			spine: { rotation: quaternion(0.72 * amount, 0, 0) },
			chest: { rotation: quaternion(0.28 * amount, 0, 0) },
			leftUpperArm: { rotation: quaternion(0.12, 0, -1.08) },
			rightUpperArm: { rotation: quaternion(0.12, 0, 1.08) },
		};
	}
	const bob = Math.abs(Math.sin(phase)) * 0.07;
	return {
		hips: { position: [0, bob, 0] },
		spine: { rotation: quaternion(-0.08, 0, Math.sin(phase) * 0.04) },
		leftUpperArm: { rotation: quaternion(-0.18, 0, -2.35) },
		rightUpperArm: { rotation: quaternion(-0.18, 0, 2.35) },
		leftLowerArm: { rotation: quaternion(0, 0, -0.35) },
		rightLowerArm: { rotation: quaternion(0, 0, 0.35) },
	};
}

function easeOut(value: number): number {
	return 1 - (1 - value) ** 3;
}

function createWalkPose(frame: number): VRMPose {
	const phase = frame / WALK_FRAME_COUNT * Math.PI * 2;
	const swing = Math.sin(phase);
	const oppositeSwing = Math.sin(phase + Math.PI);
	const bob = Math.abs(Math.sin(phase)) * 0.035;
	const leftKnee = Math.max(0, -swing) * 0.65 + 0.08;
	const rightKnee = Math.max(0, -oppositeSwing) * 0.65 + 0.08;
	return {
		hips: {
			position: [0, bob, 0],
			rotation: quaternion(0, Math.sin(phase * 2) * 0.035, -swing * 0.025),
		},
		spine: { rotation: quaternion(-0.08, -Math.sin(phase * 2) * 0.03, swing * 0.025) },
		leftUpperLeg: { rotation: quaternion(swing * 0.52, 0, 0) },
		rightUpperLeg: { rotation: quaternion(oppositeSwing * 0.52, 0, 0) },
		leftLowerLeg: { rotation: quaternion(leftKnee, 0, 0) },
		rightLowerLeg: { rotation: quaternion(rightKnee, 0, 0) },
		leftFoot: { rotation: quaternion(-leftKnee * 0.45, 0, 0) },
		rightFoot: { rotation: quaternion(-rightKnee * 0.45, 0, 0) },
		leftUpperArm: { rotation: quaternion(oppositeSwing * 0.42, 0, -1.14) },
		rightUpperArm: { rotation: quaternion(swing * 0.42, 0, 1.14) },
		leftLowerArm: { rotation: quaternion(-0.12, 0, -0.22) },
		rightLowerArm: { rotation: quaternion(-0.12, 0, 0.22) },
	};
}

function quaternion(x: number, y: number, z: number): [number, number, number, number] {
	const value = new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z, 'XYZ'));
	return [value.x, value.y, value.z, value.w];
}

function canvasToBlob(canvas: HTMLCanvasElement, type = 'image/png', quality?: number): Promise<Blob> {
	return new Promise((resolve, reject) => {
		canvas.toBlob((blob) => {
			if (blob == null) {
				reject(new Error('Failed to encode avatar atlas'));
			} else {
				resolve(blob);
			}
		}, type, quality);
	});
}

function nextFrame(): Promise<void> {
	return new Promise(resolve => window.requestAnimationFrame(() => resolve()));
}
