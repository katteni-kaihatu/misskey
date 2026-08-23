/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import * as Redis from 'ioredis';
import type { MiUser } from '@/models/User.js';
import type { Packed } from '@/misc/json-schema.js';
import { DI } from '@/di-symbols.js';
import { bindThis } from '@/decorators.js';
import { UserEntityService } from '@/core/entities/UserEntityService.js';
import { DriveFileEntityService } from '@/core/entities/DriveFileEntityService.js';
import { GlobalEventService } from '@/core/GlobalEventService.js';
import type { DriveFilesRepository } from '@/models/_.js';

export const AVATAR_WALK_WORLD_WIDTH = 1600;
export const AVATAR_WALK_WORLD_HEIGHT = 1200;

const PLAYER_RADIUS = 18;
const MAX_PLAYER_SPEED = 260;
const MOVEMENT_TOLERANCE = 45;
const PRESENCE_TTL_SECONDS = 90;
const MAX_SHARED_ATLAS_SIZE = 20 * 1024 * 1024;

export type AvatarWalkSharedAtlas = {
	url: string;
	version: number;
	cellWidth: number;
	cellHeight: number;
	directionCount: number;
	idleFrameCount: number;
	walkFrameCount: number;
};

export type AvatarWalkSharedAtlasInput = Omit<AvatarWalkSharedAtlas, 'url'> & {
	fileId: string;
};

export type AvatarWalkPlayer = {
	user: Packed<'UserLite'>;
	x: number;
	y: number;
	direction: number;
	moving: boolean;
	updatedAt: number;
	atlas: AvatarWalkSharedAtlas | null;
};

export type AvatarWalkMovement = Pick<AvatarWalkPlayer, 'x' | 'y' | 'direction' | 'moving' | 'updatedAt'> & {
	userId: MiUser['id'];
};

export type AvatarWalkMoveInput = Pick<AvatarWalkPlayer, 'x' | 'y' | 'direction' | 'moving'>;

const SPAWN_POINTS = [
	{ x: 800, y: 600 },
	{ x: 760, y: 460 },
	{ x: 940, y: 450 },
	{ x: 640, y: 790 },
	{ x: 960, y: 790 },
	{ x: 1160, y: 760 },
];

@Injectable()
export class AvatarWalkService {
	constructor(
		@Inject(DI.redis)
		private redisClient: Redis.Redis,

		@Inject(DI.driveFilesRepository)
		private driveFilesRepository: DriveFilesRepository,

		private userEntityService: UserEntityService,
		private driveFileEntityService: DriveFileEntityService,
		private globalEventService: GlobalEventService,
	) {
	}

	@bindThis
	public async join(roomId: string, sessionId: string, user: MiUser): Promise<AvatarWalkPlayer[]> {
		await this.cleanup(roomId);

		const now = Date.now();
		const previous = this.parsePlayer(await this.redisClient.hget(this.playersKey(roomId), user.id));
		const spawn = SPAWN_POINTS[this.hashUserId(user.id) % SPAWN_POINTS.length];
		const player: AvatarWalkPlayer = {
			user: await this.userEntityService.pack(user, user),
			x: previous?.x ?? spawn.x,
			y: previous?.y ?? spawn.y,
			direction: previous?.direction ?? 0,
			moving: false,
			updatedAt: now,
			atlas: previous?.atlas ?? null,
		};

		await this.redisClient.pipeline()
			.hset(this.playersKey(roomId), user.id, JSON.stringify(player))
			.hset(this.sessionsKey(roomId), user.id, sessionId)
			.zadd(this.activeKey(roomId), now, user.id)
			.expire(this.playersKey(roomId), PRESENCE_TTL_SECONDS * 2)
			.expire(this.sessionsKey(roomId), PRESENCE_TTL_SECONDS * 2)
			.expire(this.activeKey(roomId), PRESENCE_TTL_SECONDS * 2)
			.exec();

		this.globalEventService.publishAvatarWalkRoomStream(roomId, 'joined', player);

		const players = await this.redisClient.hvals(this.playersKey(roomId));
		return players.map(value => this.parsePlayer(value)).filter((value): value is AvatarWalkPlayer => value != null);
	}

	@bindThis
	public async move(roomId: string, sessionId: string, userId: MiUser['id'], input: AvatarWalkMoveInput): Promise<void> {
		const [activeSessionId, storedPlayer] = await Promise.all([
			this.redisClient.hget(this.sessionsKey(roomId), userId),
			this.redisClient.hget(this.playersKey(roomId), userId),
		]);
		if (activeSessionId !== sessionId) return;

		const previous = this.parsePlayer(storedPlayer);
		if (previous == null) return;

		const now = Date.now();
		const normalized = normalizeAvatarWalkMove(previous, input, now);
		const player: AvatarWalkPlayer = {
			...previous,
			...normalized,
		};

		const updated = await this.redisClient.eval(`
			if redis.call('HGET', KEYS[2], ARGV[1]) ~= ARGV[2] then
				return 0
			end
			redis.call('HSET', KEYS[1], ARGV[1], ARGV[3])
			redis.call('ZADD', KEYS[3], ARGV[4], ARGV[1])
			redis.call('EXPIRE', KEYS[1], ARGV[5])
			redis.call('EXPIRE', KEYS[2], ARGV[5])
			redis.call('EXPIRE', KEYS[3], ARGV[5])
			return 1
		`, 3, this.playersKey(roomId), this.sessionsKey(roomId), this.activeKey(roomId), userId, sessionId, JSON.stringify(player), now, PRESENCE_TTL_SECONDS * 2);
		if (updated !== 1) return;

		const movement: AvatarWalkMovement = {
			userId,
			x: player.x,
			y: player.y,
			direction: player.direction,
			moving: player.moving,
			updatedAt: player.updatedAt,
		};
		this.globalEventService.publishAvatarWalkRoomStream(roomId, 'moved', movement);
		await this.cleanup(roomId);
	}

	@bindThis
	public async setAtlas(roomId: string, sessionId: string, userId: MiUser['id'], input: AvatarWalkSharedAtlasInput | null): Promise<void> {
		const [activeSessionId, storedPlayer] = await Promise.all([
			this.redisClient.hget(this.sessionsKey(roomId), userId),
			this.redisClient.hget(this.playersKey(roomId), userId),
		]);
		if (activeSessionId !== sessionId) return;

		const previous = this.parsePlayer(storedPlayer);
		if (previous == null) return;

		let atlas: AvatarWalkSharedAtlas | null = null;
		if (input != null) {
			const file = await this.driveFilesRepository.findOneBy({ id: input.fileId, userId });
			if (file == null || !file.type.startsWith('image/') || file.size > MAX_SHARED_ATLAS_SIZE || file.isSensitive) return;
			const packedFile = await this.driveFileEntityService.pack(file);
			atlas = {
				url: packedFile.url,
				version: input.version,
				cellWidth: input.cellWidth,
				cellHeight: input.cellHeight,
				directionCount: input.directionCount,
				idleFrameCount: input.idleFrameCount,
				walkFrameCount: input.walkFrameCount,
			};
		}

		const player: AvatarWalkPlayer = { ...previous, atlas };
		const updated = await this.redisClient.eval(`
			if redis.call('HGET', KEYS[2], ARGV[1]) ~= ARGV[2] then
				return 0
			end
			redis.call('HSET', KEYS[1], ARGV[1], ARGV[3])
			redis.call('ZADD', KEYS[3], ARGV[4], ARGV[1])
			redis.call('EXPIRE', KEYS[1], ARGV[5])
			redis.call('EXPIRE', KEYS[2], ARGV[5])
			redis.call('EXPIRE', KEYS[3], ARGV[5])
			return 1
		`, 3, this.playersKey(roomId), this.sessionsKey(roomId), this.activeKey(roomId), userId, sessionId, JSON.stringify(player), Date.now(), PRESENCE_TTL_SECONDS * 2);
		if (updated !== 1) return;

		this.globalEventService.publishAvatarWalkRoomStream(roomId, 'atlasUpdated', { userId, atlas });
	}

	@bindThis
	public async leave(roomId: string, sessionId: string, userId: MiUser['id']): Promise<void> {
		const removed = await this.redisClient.eval(`
			if redis.call('HGET', KEYS[2], ARGV[1]) ~= ARGV[2] then
				return 0
			end
			redis.call('HDEL', KEYS[1], ARGV[1])
			redis.call('HDEL', KEYS[2], ARGV[1])
			redis.call('ZREM', KEYS[3], ARGV[1])
			return 1
		`, 3, this.playersKey(roomId), this.sessionsKey(roomId), this.activeKey(roomId), userId, sessionId);
		if (removed !== 1) return;

		this.globalEventService.publishAvatarWalkRoomStream(roomId, 'left', { userId });
	}

	private async cleanup(roomId: string): Promise<void> {
		const cutoff = Date.now() - PRESENCE_TTL_SECONDS * 1000;
		const removed = await this.redisClient.eval(`
			local stale = redis.call('ZRANGEBYSCORE', KEYS[3], 0, ARGV[1])
			local removed = {}
			for _, userId in ipairs(stale) do
				local score = redis.call('ZSCORE', KEYS[3], userId)
				if score and tonumber(score) <= tonumber(ARGV[1]) then
					redis.call('HDEL', KEYS[1], userId)
					redis.call('HDEL', KEYS[2], userId)
					redis.call('ZREM', KEYS[3], userId)
					table.insert(removed, userId)
				end
			end
			return removed
		`, 3, this.playersKey(roomId), this.sessionsKey(roomId), this.activeKey(roomId), cutoff);

		if (!Array.isArray(removed)) return;
		for (const userId of removed) {
			if (typeof userId === 'string') {
				this.globalEventService.publishAvatarWalkRoomStream(roomId, 'left', { userId });
			}
		}
	}

	private parsePlayer(value: string | null): AvatarWalkPlayer | null {
		if (value == null) return null;
		try {
			const player = JSON.parse(value) as AvatarWalkPlayer;
			if (!isFiniteNumber(player.x) || !isFiniteNumber(player.y) || !Number.isInteger(player.direction) || typeof player.moving !== 'boolean') return null;
			if (typeof player.user.id !== 'string') return null;
			if (player.atlas !== undefined && player.atlas !== null && !isAvatarWalkSharedAtlas(player.atlas)) return null;
			player.atlas ??= null;
			return player;
		} catch {
			return null;
		}
	}

	private hashUserId(userId: string): number {
		let hash = 0;
		for (const character of userId) hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
		return hash;
	}

	private playersKey(roomId: string): string {
		return `avatarWalk:room:${roomId}:players`;
	}

	private sessionsKey(roomId: string): string {
		return `avatarWalk:room:${roomId}:sessions`;
	}

	private activeKey(roomId: string): string {
		return `avatarWalk:room:${roomId}:active`;
	}
}

export function isAvatarWalkMoveInput(value: unknown): value is AvatarWalkMoveInput {
	if (value == null || typeof value !== 'object') return false;
	const input = value as Partial<AvatarWalkMoveInput>;
	const direction = input.direction;
	return isFiniteNumber(input.x) && isFiniteNumber(input.y) &&
		isFiniteNumber(direction) && Number.isInteger(direction) && direction >= 0 && direction <= 7 &&
		typeof input.moving === 'boolean';
}

export function isAvatarWalkSharedAtlasInput(value: unknown): value is AvatarWalkSharedAtlasInput {
	if (value == null || typeof value !== 'object') return false;
	const input = value as Partial<AvatarWalkSharedAtlasInput>;
	return typeof input.fileId === 'string' && input.fileId.length > 0 && input.fileId.length <= 32 &&
		isAvatarWalkAtlasMetadata(input);
}

export function normalizeAvatarWalkMove(previous: AvatarWalkPlayer, input: AvatarWalkMoveInput, now: number): Omit<AvatarWalkMovement, 'userId'> {
	const requestedX = clamp(input.x, PLAYER_RADIUS, AVATAR_WALK_WORLD_WIDTH - PLAYER_RADIUS);
	const requestedY = clamp(input.y, PLAYER_RADIUS, AVATAR_WALK_WORLD_HEIGHT - PLAYER_RADIUS);
	const distance = Math.hypot(requestedX - previous.x, requestedY - previous.y);
	const elapsedSeconds = clamp((now - previous.updatedAt) / 1000, 0.05, 1);
	const allowedDistance = MAX_PLAYER_SPEED * elapsedSeconds + MOVEMENT_TOLERANCE;
	const ratio = distance > allowedDistance ? allowedDistance / distance : 1;

	return {
		x: previous.x + (requestedX - previous.x) * ratio,
		y: previous.y + (requestedY - previous.y) * ratio,
		direction: input.direction,
		moving: input.moving && distance > 0,
		updatedAt: now,
	};
}

function isFiniteNumber(value: unknown): value is number {
	return typeof value === 'number' && Number.isFinite(value);
}

function isAvatarWalkSharedAtlas(value: unknown): value is AvatarWalkSharedAtlas {
	if (value == null || typeof value !== 'object') return false;
	const atlas = value as Partial<AvatarWalkSharedAtlas>;
	if (typeof atlas.url !== 'string' || atlas.url.length === 0 || atlas.url.length > 2048) return false;
	try {
		const url = new URL(atlas.url);
		if (url.protocol !== 'https:' && url.protocol !== 'http:') return false;
	} catch {
		return false;
	}
	return isAvatarWalkAtlasMetadata(atlas);
}

function isAvatarWalkAtlasMetadata(value: Partial<AvatarWalkSharedAtlasInput | AvatarWalkSharedAtlas>): boolean {
	return Number.isInteger(value.version) && (value.version ?? 0) >= 1 && (value.version ?? 0) <= 10 &&
		Number.isInteger(value.cellWidth) && (value.cellWidth ?? 0) >= 32 && (value.cellWidth ?? 0) <= 512 &&
		Number.isInteger(value.cellHeight) && (value.cellHeight ?? 0) >= 48 && (value.cellHeight ?? 0) <= 768 &&
		value.directionCount === 8 &&
		Number.isInteger(value.idleFrameCount) && (value.idleFrameCount ?? 0) >= 1 && (value.idleFrameCount ?? 0) <= 16 &&
		Number.isInteger(value.walkFrameCount) && (value.walkFrameCount ?? 0) >= 1 && (value.walkFrameCount ?? 0) <= 16;
}

function clamp(value: number, min: number, max: number): number {
	return Math.min(max, Math.max(min, value));
}
