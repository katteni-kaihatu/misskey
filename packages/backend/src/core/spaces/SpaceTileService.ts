/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import * as Redis from 'ioredis';
import { IsNull } from 'typeorm';
import type { MiUser } from '@/models/User.js';
import type { MiSpace } from '@/models/Space.js';
import { MiSpaceTile, spaceTileKinds, type SpaceTileKind } from '@/models/SpaceTile.js';
import type { SpacesRepository, SpaceTilesRepository } from '@/models/_.js';
import type { Packed } from '@/misc/json-schema.js';
import type { JsonValue } from '@/misc/json-value.js';
import { DI } from '@/di-symbols.js';
import { bindThis } from '@/decorators.js';
import { IdService } from '@/core/IdService.js';
import { GlobalEventService } from '@/core/GlobalEventService.js';

/** 共有する値。キー → 値と、その書き込みの通し番号 */
export type SpaceSharedValues = Record<string, { value: unknown; rev: number }>;

export type SpaceTileWithShared = Packed<'SpaceTile'> & { shared: SpaceSharedValues };

export const SPACE_SHARED_KEY_MAX_LENGTH = 64;
/** 1回の書き込みの大きさ。ストリーミングが詰まらないための歯止めで、個数や合計の上限は設けない */
export const SPACE_SHARED_VALUE_MAX_BYTES = 256 * 1024;
export const SPACE_SIGNAL_TYPE_MAX_LENGTH = 64;

export function isSpaceTileKind(value: unknown): value is SpaceTileKind {
	return typeof value === 'string' && (spaceTileKinds as readonly string[]).includes(value);
}

/** 共有する値のキーとして使えるか。 */
export function isSpaceSharedKey(value: unknown): value is string {
	// `__proto__` は、値を入れ物に詰めるときに落ちるので使わせない
	return typeof value === 'string' && value.length >= 1 && value.length <= SPACE_SHARED_KEY_MAX_LENGTH && value !== '__proto__';
}

type StoredValue = { v: unknown; r: number };

const LOAD_LOCK_SECONDS = 30;
const LOAD_WAIT_MS = 100;
const LOAD_WAIT_TRIES = 50;

/**
 * タイルと、タイルが全員で共有する値を扱う。
 * サーバーは覚えて配るだけで、計算はしない。開いている間の値の正は Redis に置き、DB へは定期的に写す。
 */
@Injectable()
export class SpaceTileService {
	constructor(
		@Inject(DI.redis)
		private redisClient: Redis.Redis,

		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		@Inject(DI.spaceTilesRepository)
		private spaceTilesRepository: SpaceTilesRepository,

		private idService: IdService,
		private globalEventService: GlobalEventService,
	) {
	}

	private sharedKey(spaceId: MiSpace['id'], tileId: MiSpaceTile['id']): string {
		return `space:${spaceId}:tile:${tileId}:shared`;
	}

	private key(spaceId: MiSpace['id'], kind: 'tiles' | 'tilesLoaded' | 'tilesLoading' | 'rev' | 'dirty'): string {
		return `space:${spaceId}:${kind}`;
	}

	@bindThis
	public pack(tile: MiSpaceTile): Packed<'SpaceTile'> {
		return {
			id: tile.id,
			spaceId: tile.spaceId,
			kind: tile.kind,
			creatorId: tile.creatorId,
			position: tile.position,
		};
	}

	/**
	 * DB にある値を Redis に戻す。スペースごとに1回だけ動く。
	 * Redis の中身が消えたあとや、サーバーを入れ替えたあとに、最後に保存したところから続けるため。
	 */
	private async ensureLoaded(spaceId: MiSpace['id']): Promise<void> {
		if (await this.redisClient.get(this.key(spaceId, 'tilesLoaded')) != null) return;
		// 戻すのは1か所だけ。ほかは、戻し終わるまで待つ。戻している途中で落ちても、鍵は時間で外れる
		const locked = await this.redisClient.set(this.key(spaceId, 'tilesLoading'), '1', 'EX', LOAD_LOCK_SECONDS, 'NX');
		if (locked !== 'OK') {
			for (let i = 0; i < LOAD_WAIT_TRIES; i++) {
				await new Promise(resolve => setTimeout(resolve, LOAD_WAIT_MS));
				if (await this.redisClient.get(this.key(spaceId, 'tilesLoaded')) != null) return;
			}
			return;
		}
		const tiles = await this.spaceTilesRepository.findBy({ spaceId });
		for (const tile of tiles) {
			await this.redisClient.sadd(this.key(spaceId, 'tiles'), tile.id);
			for (const [key, value] of Object.entries(tile.shared)) {
				// すでに Redis にある値 (より新しい) は上書きしない
				await this.redisClient.hsetnx(this.sharedKey(spaceId, tile.id), key, JSON.stringify({ v: value, r: 0 } satisfies StoredValue));
			}
		}
		await this.redisClient.set(this.key(spaceId, 'tilesLoaded'), '1');
		await this.redisClient.del(this.key(spaceId, 'tilesLoading'));
	}

	private async readShared(spaceId: MiSpace['id'], tileId: MiSpaceTile['id']): Promise<SpaceSharedValues> {
		const raw = await this.redisClient.hgetall(this.sharedKey(spaceId, tileId));
		const shared: SpaceSharedValues = Object.create(null) as SpaceSharedValues;
		for (const [key, json] of Object.entries(raw)) {
			try {
				const stored = JSON.parse(json) as StoredValue;
				shared[key] = { value: stored.v, rev: stored.r };
			} catch {
				// 壊れた値は飛ばす
			}
		}
		return shared;
	}

	/** タイルの一覧と、それぞれのいまの値。入った人に渡す。 */
	@bindThis
	public async getTiles(spaceId: MiSpace['id']): Promise<SpaceTileWithShared[]> {
		await this.ensureLoaded(spaceId);
		const tiles = await this.spaceTilesRepository.find({ where: { spaceId }, order: { position: 'ASC', id: 'ASC' } });
		return await Promise.all(tiles.map(async tile => ({ ...this.pack(tile), shared: await this.readShared(spaceId, tile.id) })));
	}

	/** タイルを置ける人か。スペースに入っているかは、呼ぶ側が先に確かめる。 */
	@bindThis
	public canPlace(me: { id: MiUser['id'] }, space: MiSpace): boolean {
		if (space.endedAt != null) return false;
		return space.tilePlacement === 'everyone' || space.hostId === me.id;
	}

	/** 片づけられる人か。置いた本人とホスト。 */
	@bindThis
	public canRemove(me: { id: MiUser['id'] }, space: MiSpace, tile: MiSpaceTile): boolean {
		if (space.endedAt != null) return false;
		return tile.creatorId === me.id || space.hostId === me.id;
	}

	@bindThis
	public async add(space: MiSpace, creator: { id: MiUser['id'] }, kind: SpaceTileKind): Promise<MiSpaceTile> {
		await this.ensureLoaded(space.id);
		const last = await this.spaceTilesRepository.findOne({ where: { spaceId: space.id }, order: { position: 'DESC' } });
		const tile = await this.spaceTilesRepository.insertOne({
			id: this.idService.gen(),
			spaceId: space.id,
			kind,
			creatorId: creator.id,
			position: (last?.position ?? -1) + 1,
			shared: {},
		});
		await this.redisClient.sadd(this.key(space.id, 'tiles'), tile.id);
		this.globalEventService.publishSpaceStream(space.id, 'tileAdded', this.pack(tile));
		return tile;
	}

	@bindThis
	public async remove(tile: MiSpaceTile): Promise<void> {
		await this.spaceTilesRepository.delete(tile.id);
		await this.redisClient.srem(this.key(tile.spaceId, 'tiles'), tile.id);
		await this.redisClient.srem(this.key(tile.spaceId, 'dirty'), tile.id);
		await this.redisClient.del(this.sharedKey(tile.spaceId, tile.id));
		this.globalEventService.publishSpaceStream(tile.spaceId, 'tileRemoved', { tileId: tile.id });
	}

	/** 並び順を変える。渡された ID の並びのうち、このスペースにあるものだけを使う。渡されなかったタイルは後ろに回る。 */
	@bindThis
	public async move(space: MiSpace, tileIds: MiSpaceTile['id'][]): Promise<void> {
		const tiles = await this.spaceTilesRepository.find({ where: { spaceId: space.id }, order: { position: 'ASC', id: 'ASC' } });
		const known = new Set(tiles.map(tile => tile.id));
		const ordered = [...new Set(tileIds)].filter(tileId => known.has(tileId));
		const rest = tiles.map(tile => tile.id).filter(tileId => !ordered.includes(tileId));
		const next = [...ordered, ...rest];
		await Promise.all(next.map((tileId, position) => this.spaceTilesRepository.update(tileId, { position })));
		this.globalEventService.publishSpaceStream(space.id, 'tilesMoved', { tileIds: next });
	}

	/**
	 * 共有する値を書く。届いた順に通し番号を振るので、同じキーに同時に書いたら後から届いたほうが残る。
	 * 値が null ならキーを消す。書けたら true。
	 * スペースに入っているかは、呼ぶ側 (ストリーミングのチャンネル) が先に確かめる。
	 */
	@bindThis
	public async setShared(spaceId: MiSpace['id'], userId: MiUser['id'], tileId: unknown, key: unknown, value: unknown): Promise<boolean> {
		if (typeof tileId !== 'string' || !isSpaceSharedKey(key) || value === undefined) return false;
		const json = JSON.stringify(value);
		if (Buffer.byteLength(json) > SPACE_SHARED_VALUE_MAX_BYTES) return false;
		await this.ensureLoaded(spaceId);
		if (await this.redisClient.sismember(this.key(spaceId, 'tiles'), tileId) !== 1) return false;

		const rev = await this.redisClient.incr(this.key(spaceId, 'rev'));
		if (value === null) {
			await this.redisClient.hdel(this.sharedKey(spaceId, tileId), key);
		} else {
			await this.redisClient.hset(this.sharedKey(spaceId, tileId), key, JSON.stringify({ v: value, r: rev } satisfies StoredValue));
		}
		await this.redisClient.sadd(this.key(spaceId, 'dirty'), tileId);
		this.globalEventService.publishSpaceStream(spaceId, 'shared', { tileId, key, value: value as JsonValue, rev, userId });
		return true;
	}

	/** 保存しない一時的な知らせを配る。配れたら true。 */
	@bindThis
	public async signal(spaceId: MiSpace['id'], userId: MiUser['id'], tileId: unknown, type: unknown, body: unknown): Promise<boolean> {
		if (typeof tileId !== 'string' || typeof type !== 'string' || type.length < 1 || type.length > SPACE_SIGNAL_TYPE_MAX_LENGTH) return false;
		if (Buffer.byteLength(JSON.stringify(body ?? null)) > SPACE_SHARED_VALUE_MAX_BYTES) return false;
		await this.ensureLoaded(spaceId);
		if (await this.redisClient.sismember(this.key(spaceId, 'tiles'), tileId) !== 1) return false;
		this.globalEventService.publishSpaceStream(spaceId, 'signal', { tileId, type, body: (body ?? null) as JsonValue, userId });
		return true;
	}

	/** まだ DB に写していない値を写す。写したタイルの数を返す。 */
	@bindThis
	public async flush(spaceId: MiSpace['id']): Promise<number> {
		const dirty = await this.redisClient.smembers(this.key(spaceId, 'dirty'));
		let flushed = 0;
		for (const tileId of dirty) {
			// 閉じる処理が先に Redis を片づけていたら、空の値で DB を上書きしないようにやめる
			if (await this.redisClient.get(this.key(spaceId, 'tilesLoaded')) == null) break;
			// 先に印を外す。写している間に書かれた値は、次の回にもう一度写る
			await this.redisClient.srem(this.key(spaceId, 'dirty'), tileId);
			try {
				const shared = await this.readShared(spaceId, tileId);
				const plain: Record<string, unknown> = {};
				for (const [key, entry] of Object.entries(shared)) plain[key] = entry.value;
				const result = await this.spaceTilesRepository.update({ id: tileId, spaceId }, { shared: plain } as never);
				if (result.affected != null && result.affected > 0) flushed++;
			} catch (err) {
				// 写せなかったら印を戻して、次の回にやり直す
				await this.redisClient.sadd(this.key(spaceId, 'dirty'), tileId);
				throw err;
			}
		}
		return flushed;
	}

	/** 開いているスペースすべてについて、値を DB に写す。定期ジョブが呼ぶ。 */
	@bindThis
	public async flushAll(): Promise<number> {
		const spaces = await this.spacesRepository.find({ where: { endedAt: IsNull() }, select: { id: true } });
		let flushed = 0;
		for (const space of spaces) flushed += await this.flush(space.id);
		return flushed;
	}

	/** 「続きをひらく」のとき。元のスペースのタイル、並び順、保存してある値を、新しいスペースに写す。 */
	@bindThis
	public async copyTiles(fromSpaceId: MiSpace['id'], toSpaceId: MiSpace['id']): Promise<number> {
		// 元のスペースを閉じた直後で、最後の値がまだ DB に写っていないことがある。先に写す
		await this.flush(fromSpaceId);
		const tiles = await this.spaceTilesRepository.find({ where: { spaceId: fromSpaceId }, order: { position: 'ASC', id: 'ASC' } });
		for (const tile of tiles) {
			await this.spaceTilesRepository.insertOne({
				id: this.idService.gen(),
				spaceId: toSpaceId,
				kind: tile.kind,
				creatorId: tile.creatorId,
				position: tile.position,
				shared: tile.shared as never,
			});
		}
		return tiles.length;
	}

	/** 閉じるとき。値を DB に写してから、Redis の中身を片づける。タイルと値は「続きをひらく」のために DB に残る。 */
	@bindThis
	public async closeSpace(spaceId: MiSpace['id']): Promise<void> {
		await this.flush(spaceId);
		const tileIds = await this.redisClient.smembers(this.key(spaceId, 'tiles'));
		const keys = [
			...tileIds.map(tileId => this.sharedKey(spaceId, tileId)),
			this.key(spaceId, 'tiles'),
			this.key(spaceId, 'tilesLoaded'),
			this.key(spaceId, 'tilesLoading'),
			this.key(spaceId, 'rev'),
			this.key(spaceId, 'dirty'),
		];
		await this.redisClient.del(...keys);
	}
}
