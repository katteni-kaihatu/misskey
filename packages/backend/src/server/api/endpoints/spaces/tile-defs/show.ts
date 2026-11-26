/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpaceTileDefsRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceTileDefService } from '@/core/spaces/SpaceTileDefService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'read:spaces',

	res: {
		type: 'object',
		optional: false, nullable: false,
		ref: 'SpaceTileDef',
	},

	errors: {
		noSuchTileDef: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE_DEF',
			id: '7e647448-62be-426a-bfac-0ff9e8724e94',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		defId: { type: 'string', format: 'misskey:id' },
		// 自分だけのタイルを、それが置いてあるスペースにいる人が読むときに付ける
		tileId: { type: 'string', format: 'misskey:id', nullable: true },
	},
	required: ['defId'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private spaceTileDefService: SpaceTileDefService,
	) {
		super(meta, paramDef, async (ps, me) => {
			const def = await this.spaceTileDefsRepository.findOneBy({ id: ps.defId });
			// 読めないものは、無いものと同じに見せる
			if (def == null || !(await this.spaceTileDefService.canRead(def, me, ps.tileId))) throw new ApiError(meta.errors.noSuchTileDef);

			return await this.spaceTileDefService.pack(def, me, { withCode: true });
		});
	}
}
