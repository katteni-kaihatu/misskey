/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpaceTileDefsRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { SpaceTileDefService } from '@/core/spaces/SpaceTileDefService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	res: {
		type: 'object',
		optional: false, nullable: false,
		ref: 'SpaceTileDef',
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: '039186a1-ea8d-4cae-93ef-64a0c7c105c5',
		},
		noSuchTileDef: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE_DEF',
			id: '127864bb-50f5-46a3-b2ee-da50c19635b5',
		},
		accessDenied: {
			message: 'You are not allowed to do this.',
			code: 'ACCESS_DENIED',
			id: '05a9abb4-7d95-428b-b315-1ae374278a68',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		defId: { type: 'string', format: 'misskey:id' },
		name: { type: 'string', minLength: 1, maxLength: 100 },
		description: { type: 'string', maxLength: 1000 },
		code: { type: 'string', minLength: 1, maxLength: 262144 },
		fetchHosts: { type: 'array', maxItems: 32, items: { type: 'string', minLength: 1, maxLength: 253 } },
		visibility: { type: 'string', enum: ['public', 'private'] },
	},
	required: ['defId'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private spaceService: SpaceService,
		private spaceTileDefService: SpaceTileDefService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			const def = await this.spaceTileDefsRepository.findOneBy({ id: ps.defId });
			if (def == null) throw new ApiError(meta.errors.noSuchTileDef);
			// 書き換えられるのは作者だけ。モデレーターは消せるが、中身は変えられない
			if (def.userId !== me.id) throw new ApiError(meta.errors.accessDenied);

			const updated = await this.spaceTileDefService.update(def, {
				name: ps.name,
				description: ps.description,
				code: ps.code,
				fetchHosts: ps.fetchHosts,
				visibility: ps.visibility,
			});
			return await this.spaceTileDefService.pack(updated, me, { withCode: true });
		});
	}
}
