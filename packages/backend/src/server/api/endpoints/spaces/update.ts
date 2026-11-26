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
import { spaceAccesses, spaceTilePlacements } from '@/models/Space.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	prohibitMoved: true,

	res: {
		type: 'object',
		optional: false, nullable: false,
		ref: 'Space',
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: 'eb5de782-6af4-443b-b42d-c300b1c0c9be',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '681c8f26-2d5b-4823-8a9e-008575d1a43d',
		},
		accessDenied: {
			message: 'Only the host can do this.',
			code: 'ACCESS_DENIED',
			id: '088238a8-c249-4186-bab0-98df8979d8f5',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: 'c9619c10-c768-49af-89fb-0d4920d45ebc',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		spaceId: { type: 'string', format: 'misskey:id' },
		name: { type: 'string', minLength: 1, maxLength: 128 },
		access: { type: 'string', enum: spaceAccesses },
		tilePlacement: { type: 'string', enum: spaceTilePlacements },
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

			const updated = await this.spaceService.update(space, { name: ps.name, access: ps.access, tilePlacement: ps.tilePlacement });
			return await this.spaceService.pack(updated, me);
		});
	}
}
