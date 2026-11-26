/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpacesRepository, SpaceTileDefsRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { SpaceTileService } from '@/core/spaces/SpaceTileService.js';
import { SPACE_TILE_KIND_CUSTOM, spaceTileKinds } from '@/models/SpaceTile.js';
import { normalizeSpaceTileHosts, SpaceTileDefService } from '@/core/spaces/SpaceTileDefService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	res: {
		type: 'object',
		optional: false, nullable: false,
		ref: 'SpaceTile',
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: 'dc8b28da-98af-42f9-8393-a61ac3548fc3',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '4443e2d9-a9d7-4852-8fb7-1f6d63b83d60',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: 'b3ce7526-d9d8-460a-89a0-8e5c5dd03926',
		},
		notInSpace: {
			message: 'Join the space first.',
			code: 'NOT_IN_SPACE',
			id: 'a21dbe9e-5788-44b1-8ad0-b2b78d76c931',
		},
		accessDenied: {
			message: 'You are not allowed to do this.',
			code: 'ACCESS_DENIED',
			id: '34fda655-58ff-493e-8055-cfa58300f1e1',
		},
		noSuchTileDef: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE_DEF',
			id: 'a2780d7f-1ecf-4616-bd03-9719ce2bb901',
		},
		kindOrDefRequired: {
			message: 'Specify either kind or defId.',
			code: 'KIND_OR_DEF_REQUIRED',
			id: '7d9c6617-3599-48cf-b135-9d13020cd121',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		spaceId: { type: 'string', format: 'misskey:id' },
		// きほんのタイルは kind、自作タイルは defId のどちらかで示す
		kind: { type: 'string', enum: spaceTileKinds },
		defId: { type: 'string', format: 'misskey:id' },
		// 自作タイルの space.fetch に許すドメイン。定義が宣言している先だけが残る
		allowedHosts: { type: 'array', maxItems: 32, items: { type: 'string', minLength: 1, maxLength: 253 } },
		// ホストだけが操作できるタイルにするか。ホストだけが選べる
		hostOnly: { type: 'boolean' },
	},
	required: ['spaceId'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private spaceService: SpaceService,
		private spaceTileService: SpaceTileService,
		private spaceTileDefService: SpaceTileDefService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			const space = await this.spacesRepository.findOneBy({ id: ps.spaceId });
			if (space == null) throw new ApiError(meta.errors.noSuchSpace);
			if (space.endedAt != null) throw new ApiError(meta.errors.ended);
			// タイルを触れるのは、スペースに入っている人だけ
			if (!(await this.spaceService.isMember(space.id, me.id))) throw new ApiError(meta.errors.notInSpace);
			if (!this.spaceTileService.canPlace(me, space)) throw new ApiError(meta.errors.accessDenied);

			if (ps.hostOnly === true && !this.spaceTileService.canSetHostOnly(me, space)) throw new ApiError(meta.errors.accessDenied);
			if ((ps.kind == null) === (ps.defId == null)) throw new ApiError(meta.errors.kindOrDefRequired);

			if (ps.defId != null) {
				const def = await this.spaceTileDefsRepository.findOneBy({ id: ps.defId });
				// 置けないものは、無いものと同じに見せる
				if (def == null || !this.spaceTileDefService.canPlace(def, me)) throw new ApiError(meta.errors.noSuchTileDef);
				const allowedHosts = normalizeSpaceTileHosts(ps.allowedHosts ?? []).filter(host => def.fetchHosts.includes(host));
				const tile = await this.spaceTileService.add(space, me, SPACE_TILE_KIND_CUSTOM, { def, allowedHosts, hostOnly: ps.hostOnly });
				return await this.spaceTileService.pack(tile);
			}

			const tile = await this.spaceTileService.add(space, me, ps.kind!, { hostOnly: ps.hostOnly });
			return await this.spaceTileService.pack(tile);
		});
	}
}
