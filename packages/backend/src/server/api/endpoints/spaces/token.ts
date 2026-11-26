/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import ms from 'ms';
import type { SpacesRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	// マイクや画面共有を出せるトークンなので、書き込みの権限を求める
	kind: 'write:spaces',

	prohibitMoved: true,

	limit: {
		duration: ms('1hour'),
		max: 120,
	},

	res: {
		type: 'object',
		optional: false, nullable: false,
		properties: {
			url: { type: 'string', optional: false, nullable: false },
			token: { type: 'string', optional: false, nullable: false },
		},
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: '7518ba5b-b33b-455d-a5e9-093b27bed62f',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '58e16628-9c9e-46ef-b3e9-1df54dd939bb',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: '49c8ff06-9c19-4348-8a91-a67468e972d4',
		},
		notInSpace: {
			message: 'Join the space before connecting to the call.',
			code: 'NOT_IN_SPACE',
			id: 'f5dbc96f-c4b7-4a8f-89d4-46fd2242b2f7',
		},
		cannotJoin: {
			message: 'You cannot join this space.',
			code: 'CANNOT_JOIN',
			id: '315d1aff-67e6-43bd-8aff-16560b9f1c44',
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
			if (space.endedAt != null) throw new ApiError(meta.errors.ended);
			if (!(await this.spaceService.canJoin(me, space))) throw new ApiError(meta.errors.cannotJoin);
			// 通話のトークンは、スペースに入っている人にだけ出す。入らずに聞くことを防ぐ
			if (!(await this.spaceService.isMember(space.id, me.id))) throw new ApiError(meta.errors.notInSpace);

			return await this.spaceService.createToken(space, me);
		});
	}
}
