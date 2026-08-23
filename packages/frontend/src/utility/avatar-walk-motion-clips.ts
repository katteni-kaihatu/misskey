/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import * as THREE from 'three';
import { BVHLoader } from 'three/addons/loaders/BVHLoader.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import type { VRM, VRMHumanBoneName } from '@pixiv/three-vrm';

const MOTION_ASSET_VERSION = 1;
const KAYKIT_MOTIONS_URL = `/static-assets/avatar-walk/kaykit-medium-simulation.glb?v=${MOTION_ASSET_VERSION}`;
const CMU_BOW_MOTION_URL = `/static-assets/avatar-walk/cmu-113-02-bow.bvh?v=${MOTION_ASSET_VERSION}`;

const KAYKIT_CLIP_NAMES = {
	sit: 'Rig_Medium|Sit_Chair_Down',
	wave: 'Rig_Medium|Waving',
	cheer: 'Rig_Medium|Cheering',
} as const;

const KAYKIT_RIG_MAP: Readonly<Record<string, VRMHumanBoneName>> = {
	hips: 'hips',
	spine: 'spine',
	chest: 'chest',
	head: 'head',
	upperarml: 'leftUpperArm',
	lowerarml: 'leftLowerArm',
	wristl: 'leftHand',
	upperarmr: 'rightUpperArm',
	lowerarmr: 'rightLowerArm',
	wristr: 'rightHand',
	upperlegl: 'leftUpperLeg',
	lowerlegl: 'leftLowerLeg',
	footl: 'leftFoot',
	toesl: 'leftToes',
	upperlegr: 'rightUpperLeg',
	lowerlegr: 'rightLowerLeg',
	footr: 'rightFoot',
	toesr: 'rightToes',
};

const CMU_RIG_MAP: Readonly<Record<string, VRMHumanBoneName>> = {
	Hips: 'hips',
	Spine: 'spine',
	Spine1: 'chest',
	Neck1: 'neck',
	Head: 'head',
	LeftShoulder: 'leftShoulder',
	LeftArm: 'leftUpperArm',
	LeftForeArm: 'leftLowerArm',
	LeftHand: 'leftHand',
	RightShoulder: 'rightShoulder',
	RightArm: 'rightUpperArm',
	RightForeArm: 'rightLowerArm',
	RightHand: 'rightHand',
	LeftUpLeg: 'leftUpperLeg',
	LeftLeg: 'leftLowerLeg',
	LeftFoot: 'leftFoot',
	LeftToeBase: 'leftToes',
	RightUpLeg: 'rightUpperLeg',
	RightLeg: 'rightLowerLeg',
	RightFoot: 'rightFoot',
	RightToeBase: 'rightToes',
};

export type AvatarWalkMotionType = 'sit' | 'wave' | 'bow' | 'cheer';

export type AvatarWalkMotionClips = Record<AvatarWalkMotionType, THREE.AnimationClip>;

export async function loadAvatarWalkMotionClips(vrm: VRM): Promise<AvatarWalkMotionClips> {
	const [kayKit, bowText] = await Promise.all([
		new GLTFLoader().loadAsync(KAYKIT_MOTIONS_URL),
		fetchMotionText(CMU_BOW_MOTION_URL),
	]);
	const bow = new BVHLoader().parse(bowText);
	const bowRoot = bow.skeleton.bones[0];
	if (bowRoot == null) throw new Error('CMU bow motion has no skeleton');
	const bowRestMixer = new THREE.AnimationMixer(bowRoot);
	try {
		bowRestMixer.clipAction(bow.clip).play();
		bowRestMixer.setTime(0);
		bowRoot.updateWorldMatrix(true, true);

		return {
			sit: retargetClip(kayKit.scene, findClip(kayKit.animations, KAYKIT_CLIP_NAMES.sit), KAYKIT_RIG_MAP, vrm),
			wave: retargetClip(kayKit.scene, findClip(kayKit.animations, KAYKIT_CLIP_NAMES.wave), KAYKIT_RIG_MAP, vrm),
			bow: retargetClip(bowRoot, bow.clip, CMU_RIG_MAP, vrm),
			cheer: retargetClip(kayKit.scene, findClip(kayKit.animations, KAYKIT_CLIP_NAMES.cheer), KAYKIT_RIG_MAP, vrm),
		};
	} finally {
		bowRestMixer.stopAllAction();
		bowRestMixer.uncacheRoot(bowRoot);
	}
}

function findClip(clips: THREE.AnimationClip[], name: string): THREE.AnimationClip {
	const clip = THREE.AnimationClip.findByName(clips, name);
	if (clip == null) throw new Error(`Avatar walk motion clip is missing: ${name}`);
	return clip;
}

async function fetchMotionText(url: string): Promise<string> {
	const response = await window.fetch(url, { credentials: 'same-origin' });
	if (!response.ok) throw new Error(`Failed to load avatar walk motion: ${response.status}`);
	return await response.text();
}

function retargetClip(
	sourceRoot: THREE.Object3D,
	sourceClip: THREE.AnimationClip,
	rigMap: Readonly<Record<string, VRMHumanBoneName>>,
	vrm: VRM,
): THREE.AnimationClip {
	sourceRoot.updateWorldMatrix(true, true);
	const tracks: THREE.KeyframeTrack[] = [];
	const targetHipsHeight = vrm.humanoid.normalizedRestPose.hips.position?.[1] ?? 1;

	for (const sourceTrack of sourceClip.tracks) {
		const dotIndex = sourceTrack.name.lastIndexOf('.');
		if (dotIndex < 1) continue;
		const sourceBoneName = sourceTrack.name.slice(0, dotIndex);
		const propertyName = sourceTrack.name.slice(dotIndex + 1);
		const targetBoneName = rigMap[sourceBoneName];
		if (targetBoneName == null) continue;
		const targetNode = vrm.humanoid.getNormalizedBoneNode(targetBoneName);
		const sourceNode = sourceRoot.getObjectByName(sourceBoneName);
		if (targetNode == null || sourceNode == null) continue;

		if (sourceTrack instanceof THREE.QuaternionKeyframeTrack && propertyName === 'quaternion') {
			tracks.push(retargetQuaternionTrack(sourceTrack, sourceNode, targetNode.name, vrm.meta.metaVersion === '0'));
		} else if (
			targetBoneName === 'hips' &&
			sourceTrack instanceof THREE.VectorKeyframeTrack &&
			propertyName === 'position'
		) {
			tracks.push(retargetHipsPositionTrack(sourceTrack, targetNode.name, targetHipsHeight));
		}
	}

	return new THREE.AnimationClip(sourceClip.name, sourceClip.duration, tracks);
}

function retargetQuaternionTrack(
	sourceTrack: THREE.QuaternionKeyframeTrack,
	sourceNode: THREE.Object3D,
	targetNodeName: string,
	isVrm0: boolean,
): THREE.QuaternionKeyframeTrack {
	const restRotationInverse = sourceNode.getWorldQuaternion(new THREE.Quaternion()).invert();
	const parentRestWorldRotation = sourceNode.parent?.getWorldQuaternion(new THREE.Quaternion()) ?? new THREE.Quaternion();
	const quaternionValue = new THREE.Quaternion();
	const values = Float32Array.from(sourceTrack.values);

	for (let index = 0; index < values.length; index += 4) {
		quaternionValue.fromArray(values, index)
			.premultiply(parentRestWorldRotation)
			.multiply(restRotationInverse)
			.normalize();
		quaternionValue.toArray(values, index);
		if (isVrm0) {
			values[index] *= -1;
			values[index + 2] *= -1;
		}
	}

	return new THREE.QuaternionKeyframeTrack(`${targetNodeName}.quaternion`, sourceTrack.times, values);
}

function retargetHipsPositionTrack(
	sourceTrack: THREE.VectorKeyframeTrack,
	targetNodeName: string,
	targetHipsHeight: number,
): THREE.VectorKeyframeTrack {
	const sourceHipsHeight = Math.max(Math.abs(sourceTrack.values[1] ?? 1), 0.0001);
	const scale = targetHipsHeight / sourceHipsHeight;
	const values = new Float32Array(sourceTrack.values.length);

	for (let index = 0; index < values.length; index += 3) {
		values[index] = 0;
		values[index + 1] = (sourceTrack.values[index + 1] ?? sourceHipsHeight) * scale;
		values[index + 2] = 0;
	}

	return new THREE.VectorKeyframeTrack(`${targetNodeName}.position`, sourceTrack.times, values);
}
