/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpacesRepository, SpaceTileDefsRepository, SpaceTilesRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { SpaceTileService } from '@/core/spaces/SpaceTileService.js';
import { normalizeSpaceTileHosts } from '@/core/spaces/SpaceTileDefService.js';

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
			id: 'd6aefdef-6390-4d04-b4c5-6ac3b6b6a45e',
		},
		noSuchTile: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE',
			id: 'a612f166-b7d2-4328-9d31-97fa3c43304f',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '9f911dc5-36e0-4e1f-a74a-337013cd4f3c',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: '3d8de1df-2c3b-43f3-a470-b5195cad1961',
		},
		notInSpace: {
			message: 'Join the space first.',
			code: 'NOT_IN_SPACE',
			id: '4624ba17-cebd-4814-9927-b50b0631998b',
		},
		accessDenied: {
			message: 'You are not allowed to do this.',
			code: 'ACCESS_DENIED',
			id: '2e09c02e-98c2-45b3-905c-b3948879c704',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		tileId: { type: 'string', format: 'misskey:id' },
		// space.fetch に許すドメイン。置いた本人とホストが変えられる
		allowedHosts: { type: 'array', maxItems: 32, items: { type: 'string', minLength: 1, maxLength: 253 } },
		// ホストだけが操作できるか。ホストが変えられる
		hostOnly: { type: 'boolean' },
	},
	required: ['tileId'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		@Inject(DI.spaceTilesRepository)
		private spaceTilesRepository: SpaceTilesRepository,

		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private spaceService: SpaceService,
		private spaceTileService: SpaceTileService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			const tile = await this.spaceTilesRepository.findOneBy({ id: ps.tileId });
			if (tile == null) throw new ApiError(meta.errors.noSuchTile);
			const space = await this.spacesRepository.findOneBy({ id: tile.spaceId });
			if (space == null) throw new ApiError(meta.errors.noSuchSpace);
			if (space.endedAt != null) throw new ApiError(meta.errors.ended);
			if (!(await this.spaceService.isMember(space.id, me.id))) throw new ApiError(meta.errors.notInSpace);
			if (ps.allowedHosts !== undefined && !this.spaceTileService.canAllowHosts(me, space, tile)) throw new ApiError(meta.errors.accessDenied);
			if (ps.hostOnly !== undefined && !this.spaceTileService.canSetHostOnly(me, space)) throw new ApiError(meta.errors.accessDenied);

			// 許せるのは、タイルの定義が宣言している先だけ。置くときと同じ
			let allowedHosts: string[] | undefined;
			if (ps.allowedHosts !== undefined) {
				const def = tile.defId == null ? null : await this.spaceTileDefsRepository.findOneBy({ id: tile.defId });
				allowedHosts = normalizeSpaceTileHosts(ps.allowedHosts).filter(host => def?.fetchHosts.includes(host) ?? false);
			}

			const updated = await this.spaceTileService.update(tile, {
				allowedHosts,
				hostOnly: ps.hostOnly,
			});
			return await this.spaceTileService.pack(updated);
		});
	}
}
