/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpacesRepository, SpaceTilesRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { SpaceTileService } from '@/core/spaces/SpaceTileService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: 'bd871696-7e30-42de-b16b-2eb09b2820fd',
		},
		noSuchTile: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE',
			id: 'ecae7a89-75b8-4a85-b1bf-e5de2026b061',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '377cdc42-53c9-410a-b34a-63f7795b30c0',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: 'd4bd1f9c-2c5b-46a1-a451-f7a60d65a060',
		},
		notInSpace: {
			message: 'Join the space first.',
			code: 'NOT_IN_SPACE',
			id: '045b875a-bf08-4deb-9b33-fd6148b06746',
		},
		accessDenied: {
			message: 'You are not allowed to do this.',
			code: 'ACCESS_DENIED',
			id: '1c71a734-8249-4bd3-9c18-1f2bf99af5c0',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		tileId: { type: 'string', format: 'misskey:id' },
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
			// タイルを触れるのは、スペースに入っている人だけ
			if (!(await this.spaceService.isMember(space.id, me.id))) throw new ApiError(meta.errors.notInSpace);
			if (!this.spaceTileService.canRemove(me, space, tile)) throw new ApiError(meta.errors.accessDenied);

			await this.spaceTileService.remove(tile);
		});
	}
}
