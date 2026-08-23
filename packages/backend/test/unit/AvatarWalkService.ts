/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test } from 'vitest';
import {
	AVATAR_WALK_WORLD_HEIGHT,
	AVATAR_WALK_WORLD_WIDTH,
	isAvatarWalkMoveInput,
	isAvatarWalkSharedAtlasInput,
	normalizeAvatarWalkMove,
} from '@/core/AvatarWalkService.js';
import type { AvatarWalkPlayer } from '@/core/AvatarWalkService.js';

const player = {
	user: { id: 'test-user' },
	x: 100,
	y: 100,
	direction: 0,
	moving: false,
	updatedAt: 1000,
	atlas: null,
} as AvatarWalkPlayer;

describe('AvatarWalkService', () => {
	test('validates movement payloads', () => {
		expect(isAvatarWalkMoveInput({ x: 120, y: 140, direction: 7, moving: true })).toBe(true);
		expect(isAvatarWalkMoveInput({ x: Number.NaN, y: 140, direction: 0, moving: true })).toBe(false);
		expect(isAvatarWalkMoveInput({ x: 120, y: 140, direction: 8, moving: true })).toBe(false);
		expect(isAvatarWalkMoveInput({ x: 120, y: 140, direction: 0, moving: 'yes' })).toBe(false);
	});

	test('validates shared atlas payloads', () => {
		const atlas = {
			fileId: 'test-drive-file',
			version: 4,
			cellWidth: 128,
			cellHeight: 192,
			directionCount: 8,
			idleFrameCount: 4,
			walkFrameCount: 6,
		};
		expect(isAvatarWalkSharedAtlasInput(atlas)).toBe(true);
		expect(isAvatarWalkSharedAtlasInput({ ...atlas, fileId: '' })).toBe(false);
		expect(isAvatarWalkSharedAtlasInput({ ...atlas, directionCount: 4 })).toBe(false);
		expect(isAvatarWalkSharedAtlasInput({ ...atlas, cellWidth: 4096 })).toBe(false);
	});

	test('limits movement speed', () => {
		const result = normalizeAvatarWalkMove(player, {
			x: 1100,
			y: 100,
			direction: 2,
			moving: true,
		}, 1050);

		expect(result.x).toBe(158);
		expect(result.y).toBe(100);
		expect(result.direction).toBe(2);
		expect(result.moving).toBe(true);
	});

	test('keeps players inside the world', () => {
		const nearEdge = { ...player, x: 20, y: AVATAR_WALK_WORLD_HEIGHT - 20 };
		const result = normalizeAvatarWalkMove(nearEdge, {
			x: -100,
			y: AVATAR_WALK_WORLD_HEIGHT + 100,
			direction: 5,
			moving: true,
		}, 2000);

		expect(result.x).toBe(18);
		expect(result.y).toBe(AVATAR_WALK_WORLD_HEIGHT - 18);
		expect(result.x).toBeLessThan(AVATAR_WALK_WORLD_WIDTH);
	});
});
