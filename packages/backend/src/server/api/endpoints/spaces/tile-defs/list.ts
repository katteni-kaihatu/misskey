/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpaceTileDefsRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { DI } from '@/di-symbols.js';
import { QueryService } from '@/core/QueryService.js';
import { SpaceTileDefService } from '@/core/spaces/SpaceTileDefService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'read:spaces',

	res: {
		type: 'array',
		optional: false, nullable: false,
		items: {
			type: 'object',
			optional: false, nullable: false,
			ref: 'SpaceTileDef',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		limit: { type: 'integer', minimum: 1, maximum: 100, default: 30 },
		sinceId: { type: 'string', format: 'misskey:id' },
		untilId: { type: 'string', format: 'misskey:id' },
	},
	required: [],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private queryService: QueryService,
		private spaceTileDefService: SpaceTileDefService,
	) {
		super(meta, paramDef, async (ps, me) => {
			// 公開されているタイルの一覧。新しい順。コードは含めない
			const defs = await this.queryService.makePaginationQuery(this.spaceTileDefsRepository.createQueryBuilder('def'), ps.sinceId, ps.untilId)
				.andWhere('def.visibility = :visibility', { visibility: 'public' })
				.limit(ps.limit)
				.getMany();

			return await this.spaceTileDefService.packMany(defs, me);
		});
	}
}
