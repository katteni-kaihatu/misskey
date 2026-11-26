/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
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
			id: 'f16c47e8-8d2d-481b-89ee-cc2682fd497a',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		name: { type: 'string', minLength: 1, maxLength: 100 },
		description: { type: 'string', maxLength: 1000 },
		code: { type: 'string', minLength: 1, maxLength: 262144 },
		fetchHosts: { type: 'array', maxItems: 32, items: { type: 'string', minLength: 1, maxLength: 253 } },
		visibility: { type: 'string', enum: ['public', 'private'] },
	},
	required: ['name', 'code'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		private spaceService: SpaceService,
		private spaceTileDefService: SpaceTileDefService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			const def = await this.spaceTileDefService.create(me, {
				name: ps.name,
				description: ps.description ?? '',
				code: ps.code,
				fetchHosts: ps.fetchHosts ?? [],
				visibility: ps.visibility ?? 'public',
			});
			return await this.spaceTileDefService.pack(def, me, { withCode: true });
		});
	}
}
