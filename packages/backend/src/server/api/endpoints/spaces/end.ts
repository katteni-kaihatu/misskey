/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import type { SpacesRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: '9de9c527-c80d-4cbc-9429-5695d7d6a88f',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '7e5508d1-ba0c-4dd8-8c6a-307922e43fd2',
		},
		accessDenied: {
			message: 'Only the host can do this.',
			code: 'ACCESS_DENIED',
			id: 'b999e2cf-942c-4e88-a7ed-60e2430f0530',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: '7092017c-ef40-439b-8a6c-ba011d5d53cc',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		spaceId: { type: 'string', format: 'misskey:id' },
	},
	required: ['spaceId'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		private spaceService: SpaceService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			const space = await this.spacesRepository.findOneBy({ id: ps.spaceId });
			if (space == null) throw new ApiError(meta.errors.noSuchSpace);
			if (space.hostId !== me.id) throw new ApiError(meta.errors.accessDenied);
			if (space.endedAt != null) throw new ApiError(meta.errors.ended);

			await this.spaceService.end(space);
		});
	}
}
