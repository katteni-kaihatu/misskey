/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { MiUser } from '@/models/User.js';
import type { MiSpaceTileDef } from '@/models/SpaceTileDef.js';
import type { SpaceTileDefsRepository, SpaceTilesRepository } from '@/models/_.js';
import type { Packed } from '@/misc/json-schema.js';
import { DI } from '@/di-symbols.js';
import { bindThis } from '@/decorators.js';
import { IdService } from '@/core/IdService.js';
import { UserEntityService } from '@/core/entities/UserEntityService.js';
import { SpaceService } from './SpaceService.js';

/** コードの大きさの歯止め。共有する値の1回の書き込みと同じ */
export const SPACE_TILE_CODE_MAX_LENGTH = 256 * 1024;
export const SPACE_TILE_FETCH_HOSTS_MAX = 32;

const HOST_PATTERN = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

/**
 * 読みに行く先のドメインをそろえる。小文字にして、重なりと、ドメインの形でないものを落とす。
 * IP アドレスや `localhost` のような点の無い名前は、形が合わないので落ちる (数字だけの名前も落とす)。
 */
export function normalizeSpaceTileHosts(hosts: readonly string[]): string[] {
	const result: string[] = [];
	for (const raw of hosts) {
		const host = raw.trim().toLowerCase();
		if (host.length > 253 || !HOST_PATTERN.test(host)) continue;
		// 最後の区切りが数字だけなら IP アドレス
		if (/^[0-9]+$/.test(host.split('.').at(-1) ?? '')) continue;
		if (!result.includes(host)) result.push(host);
	}
	return result.slice(0, SPACE_TILE_FETCH_HOSTS_MAX);
}

@Injectable()
export class SpaceTileDefService {
	constructor(
		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		@Inject(DI.spaceTilesRepository)
		private spaceTilesRepository: SpaceTilesRepository,

		private idService: IdService,
		private userEntityService: UserEntityService,
		private spaceService: SpaceService,
	) {
	}

	@bindThis
	public async pack(def: MiSpaceTileDef, me: { id: MiUser['id'] } | null, options: { withCode?: boolean } = {}): Promise<Packed<'SpaceTileDef'>> {
		return {
			id: def.id,
			createdAt: this.idService.parse(def.id).date.toISOString(),
			updatedAt: def.updatedAt.toISOString(),
			userId: def.userId,
			user: await this.userEntityService.pack(def.userId, me),
			name: def.name,
			description: def.description,
			fetchHosts: def.fetchHosts,
			visibility: def.visibility,
			...(options.withCode ? { code: def.code } : {}),
		};
	}

	@bindThis
	public async packMany(defs: MiSpaceTileDef[], me: { id: MiUser['id'] } | null): Promise<Packed<'SpaceTileDef'>[]> {
		return await Promise.all(defs.map(def => this.pack(def, me)));
	}

	/**
	 * コードを読める人か。公開されているものは全員。
	 * 自分だけのものは、作者と、それが置いてあるスペースにいま入っている人 (`tileId` で示す)。
	 */
	@bindThis
	public async canRead(def: MiSpaceTileDef, me: { id: MiUser['id'] }, tileId?: string | null): Promise<boolean> {
		if (def.visibility === 'public' || def.userId === me.id) return true;
		if (tileId == null) return false;
		const tile = await this.spaceTilesRepository.findOneBy({ id: tileId, defId: def.id });
		if (tile == null) return false;
		return await this.spaceService.isMember(tile.spaceId, me.id);
	}

	/** 置ける人か。公開されているものは全員、自分だけのものは作者。 */
	@bindThis
	public canPlace(def: MiSpaceTileDef, me: { id: MiUser['id'] }): boolean {
		return def.visibility === 'public' || def.userId === me.id;
	}

	@bindThis
	public async create(user: { id: MiUser['id'] }, params: Pick<MiSpaceTileDef, 'name' | 'description' | 'code' | 'fetchHosts' | 'visibility'>): Promise<MiSpaceTileDef> {
		return await this.spaceTileDefsRepository.insertOne({
			id: this.idService.gen(),
			userId: user.id,
			name: params.name,
			description: params.description,
			code: params.code,
			fetchHosts: normalizeSpaceTileHosts(params.fetchHosts),
			visibility: params.visibility,
			updatedAt: new Date(),
		});
	}

	@bindThis
	public async update(def: MiSpaceTileDef, params: Partial<Pick<MiSpaceTileDef, 'name' | 'description' | 'code' | 'fetchHosts' | 'visibility'>>): Promise<MiSpaceTileDef> {
		await this.spaceTileDefsRepository.update(def.id, {
			...(params.name !== undefined ? { name: params.name } : {}),
			...(params.description !== undefined ? { description: params.description } : {}),
			...(params.code !== undefined ? { code: params.code } : {}),
			...(params.fetchHosts !== undefined ? { fetchHosts: normalizeSpaceTileHosts(params.fetchHosts) } : {}),
			...(params.visibility !== undefined ? { visibility: params.visibility } : {}),
			updatedAt: new Date(),
		});
		return await this.spaceTileDefsRepository.findOneByOrFail({ id: def.id });
	}
}
