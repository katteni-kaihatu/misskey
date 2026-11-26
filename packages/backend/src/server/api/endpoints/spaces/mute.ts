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
			id: '9e2f8515-1348-48d3-8d40-2e31dff845c1',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '204ddc98-5f5f-4c30-aaf3-cffc5c43fe6c',
		},
		accessDenied: {
			message: 'Only the host can do this.',
			code: 'ACCESS_DENIED',
			id: 'bebd8ac2-d429-49ea-9f45-5ac6905c565d',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: 'fe66c40e-feb5-4010-a425-c3fe743b464c',
		},
		noSuchMember: {
			message: 'That user is not in this space.',
			code: 'NO_SUCH_MEMBER',
			id: '5a9813e3-6571-467a-a1b0-c3d8ca1f4552',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		spaceId: { type: 'string', format: 'misskey:id' },
		userId: { type: 'string', format: 'misskey:id' },
	},
	required: ['spaceId', 'userId'],
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

			if (!(await this.spaceService.isMember(space.id, ps.userId))) throw new ApiError(meta.errors.noSuchMember);

			this.spaceService.mute(space, ps.userId);
		});
	}
}
