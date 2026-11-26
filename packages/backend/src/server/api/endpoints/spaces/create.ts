/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import ms from 'ms';
import type { SpacesRepository } from '@/models/_.js';
import { DI } from '@/di-symbols.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { spaceAccesses, spaceNoteScopes } from '@/models/Space.js';
import type { MiSpace } from '@/models/Space.js';
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
		noSuchSpaceToContinue: {
			message: 'No such space to continue.',
			code: 'NO_SUCH_SPACE_TO_CONTINUE',
			id: 'b47440d5-669c-4aef-8c2f-8d879784c01b',
		},
		cannotContinue: {
			message: 'You can only continue a closed space that you hosted.',
			code: 'CANNOT_CONTINUE',
			id: 'f447461e-ffe3-483e-9ae9-3d86722596e1',
		},
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
		// 「続きをひらく」の元のスペース。自分がホストだった、閉じたスペースだけ
		continueFromId: { type: 'string', format: 'misskey:id', nullable: true },
	},
	required: ['name'],
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

			// 1人が同時に開けるスペースは1つ
			if (await this.spaceService.findOpenByHost(me.id) != null) throw new ApiError(meta.errors.alreadyOpen);

			// 「続きをひらく」のときは、タイルを置ける人の設定も引き継ぐ
			let tilePlacement: MiSpace['tilePlacement'] | undefined;
			if (ps.continueFromId != null) {
				const source = await this.spacesRepository.findOneBy({ id: ps.continueFromId });
				if (source == null) throw new ApiError(meta.errors.noSuchSpaceToContinue);
				if (source.hostId !== me.id || source.endedAt == null) throw new ApiError(meta.errors.cannotContinue);
				tilePlacement = source.tilePlacement;
			}

			const space = await this.spaceService.create(me, {
				name: ps.name,
				access: ps.access,
				noteScope: ps.noteScope,
				continuedFromId: ps.continueFromId ?? null,
				tilePlacement,
			}).catch(err => {
				// 同時に2つ作ろうとした場合は、DB の一意制約がここに来る
				if (isDuplicateKeyValueError(err)) throw new ApiError(meta.errors.alreadyOpen);
				throw err;
			});
			return await this.spaceService.pack(space, me);
		});
	}
}
