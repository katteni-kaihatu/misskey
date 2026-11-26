/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpaceTileDefsRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { RoleService } from '@/core/RoleService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	errors: {
		noSuchTileDef: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE_DEF',
			id: '6dae9d76-ede3-41a7-b53d-1425007a2f27',
		},
		accessDenied: {
			message: 'You are not allowed to do this.',
			code: 'ACCESS_DENIED',
			id: '63f5b082-f9e3-4e4e-96f6-35803e5e14d8',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		defId: { type: 'string', format: 'misskey:id' },
	},
	required: ['defId'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private roleService: RoleService,
	) {
		super(meta, paramDef, async (ps, me) => {
			const def = await this.spaceTileDefsRepository.findOneBy({ id: ps.defId });
			if (def == null) throw new ApiError(meta.errors.noSuchTileDef);
			// 消せるのは作者とモデレーター
			if (def.userId !== me.id && !(await this.roleService.isModerator(me))) throw new ApiError(meta.errors.accessDenied);

			// 置いてあるタイルは残る。定義を指す列が空になり、画面は「消されました」を出す
			await this.spaceTileDefsRepository.delete(def.id);
		});
	}
}
