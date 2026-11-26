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
			id: '90836769-dc47-4dfa-a27f-be8d76afd5a7',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '1c14e428-e783-4662-aea6-0369f5ba72e6',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: '0ac76e3a-973f-46b5-a187-68669b3fefef',
		},
		notInSpace: {
			message: 'Join the space first.',
			code: 'NOT_IN_SPACE',
			id: '50d22652-2297-4fe8-9b1d-144dd70b540a',
		},
		accessDenied: {
			message: 'You are not allowed to do this.',
			code: 'ACCESS_DENIED',
			id: '8ddcfaf0-17ea-45e8-ba2e-4cc9c1a22e2d',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		spaceId: { type: 'string', format: 'misskey:id' },
		tileIds: {
			type: 'array',
			items: { type: 'string', format: 'misskey:id' },
		},
	},
	required: ['spaceId', 'tileIds'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		private spaceService: SpaceService,
		private spaceTileService: SpaceTileService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			const space = await this.spacesRepository.findOneBy({ id: ps.spaceId });
			if (space == null) throw new ApiError(meta.errors.noSuchSpace);
			if (space.endedAt != null) throw new ApiError(meta.errors.ended);
			// タイルを触れるのは、スペースに入っている人だけ
			if (!(await this.spaceService.isMember(space.id, me.id))) throw new ApiError(meta.errors.notInSpace);
			if (!this.spaceTileService.canPlace(me, space)) throw new ApiError(meta.errors.accessDenied);

			await this.spaceTileService.move(space, ps.tileIds);
		});
	}
}
