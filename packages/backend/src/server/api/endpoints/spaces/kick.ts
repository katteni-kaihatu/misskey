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
			id: 'c0145961-1095-46ac-9424-2f17aeba0ee8',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '3b7eb1d9-1697-4f5b-9532-f53d2841093d',
		},
		accessDenied: {
			message: 'Only the host can do this.',
			code: 'ACCESS_DENIED',
			id: 'b3bfc70f-cf1a-4408-9437-4ba5d9e44e4d',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: 'e77361ef-9cda-49ce-a1ce-2bdf5cd2cc6a',
		},
		cannotTargetYourself: {
			message: 'You cannot do this to yourself.',
			code: 'CANNOT_TARGET_YOURSELF',
			id: '27a368c4-4d3e-478f-a2de-b991615ecace',
		},
		noSuchMember: {
			message: 'That user is not in this space.',
			code: 'NO_SUCH_MEMBER',
			id: '7768e684-288c-4308-9a3b-3209b5db2e99',
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

			if (ps.userId === me.id) throw new ApiError(meta.errors.cannotTargetYourself);
			if (!(await this.spaceService.isMember(space.id, ps.userId))) throw new ApiError(meta.errors.noSuchMember);

			await this.spaceService.kick(space, ps.userId);
		});
	}
}
