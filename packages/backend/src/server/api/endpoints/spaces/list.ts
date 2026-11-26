/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';

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
			ref: 'Space',
		},
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: 'bca25abe-e87b-4fb3-984c-d006c862d464',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
	},
	required: [],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		private spaceService: SpaceService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			return await this.spaceService.listJoinable(me);
		});
	}
}
