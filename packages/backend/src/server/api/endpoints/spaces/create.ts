/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import ms from 'ms';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { spaceAccesses, spaceNoteScopes } from '@/models/Space.js';
import { isDuplicateKeyValueError } from '@/misc/is-duplicate-key-value-error.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	limit: {
		duration: ms('1hour'),
		max: 10,
	},

	res: {
		type: 'object',
		optional: false, nullable: false,
		ref: 'Space',
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: '7b1d54fa-b087-466b-8180-ad661346faae',
		},
		alreadyOpen: {
			message: 'You already have an open space.',
			code: 'ALREADY_OPEN',
			id: '6da03960-fb53-4838-834b-251c227e5b2c',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		name: { type: 'string', minLength: 1, maxLength: 128 },
		access: { type: 'string', enum: spaceAccesses, default: 'local' },
		noteScope: { type: 'string', enum: spaceNoteScopes, default: 'local' },
	},
	required: ['name'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		private spaceService: SpaceService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			// 1人が同時に開けるスペースは1つ
			if (await this.spaceService.findOpenByHost(me.id) != null) throw new ApiError(meta.errors.alreadyOpen);

			const space = await this.spaceService.create(me, {
				name: ps.name,
				access: ps.access,
				noteScope: ps.noteScope,
			}).catch(err => {
				// 同時に2つ作ろうとした場合は、DB の一意制約がここに来る
				if (isDuplicateKeyValueError(err)) throw new ApiError(meta.errors.alreadyOpen);
				throw err;
			});
			return await this.spaceService.pack(space, me);
		});
	}
}
