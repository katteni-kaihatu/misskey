/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import ms from 'ms';
import type { SpacesRepository, SpaceTileDefsRepository, SpaceTilesRepository } from '@/models/_.js';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ApiError } from '@/server/api/error.js';
import { DI } from '@/di-symbols.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { SpaceTileFetchService } from '@/core/spaces/SpaceTileFetchService.js';

export const meta = {
	tags: ['spaces'],

	requireCredential: true,

	kind: 'write:spaces',

	// 自作タイルが続けて読むことはあるので、ゆるめにしておく。同じ URL はサーバーが少しの間覚えている
	limit: {
		duration: ms('1min'),
		max: 300,
	},

	res: {
		type: 'object',
		optional: false, nullable: false,
		properties: {
			status: { type: 'integer', optional: false, nullable: false },
			contentType: { type: 'string', optional: false, nullable: true },
			text: { type: 'string', optional: false, nullable: false },
		},
	},

	errors: {
		spacesDisabled: {
			message: 'Spaces is not enabled on this server.',
			code: 'SPACES_DISABLED',
			id: '62ebdee2-1e76-4e92-82e9-dc7a82faa8c4',
		},
		noSuchTile: {
			message: 'No such tile.',
			code: 'NO_SUCH_TILE',
			id: 'd6d8e822-0fec-4dc7-9aad-4c7d1de18a19',
		},
		noSuchSpace: {
			message: 'No such space.',
			code: 'NO_SUCH_SPACE',
			id: '97de2dc1-1100-4754-9841-6be5e74906c9',
		},
		ended: {
			message: 'This space has ended.',
			code: 'SPACE_ENDED',
			id: '2cf69559-dff3-4c19-97fc-775e146eeb60',
		},
		notInSpace: {
			message: 'Join the space first.',
			code: 'NOT_IN_SPACE',
			id: 'd761dc2c-5f10-402e-b16b-edc3ebca9030',
		},
		notAllowed: {
			message: 'This tile is not allowed to read that URL.',
			code: 'URL_NOT_ALLOWED',
			id: '7fc68d47-d7bf-4f0d-9f0c-dc84fa467df3',
		},
		fetchFailed: {
			message: 'Failed to read the URL.',
			code: 'FETCH_FAILED',
			id: '082b03d8-d9cb-48e9-a9f2-e7098e8cd9bc',
		},
	},
} as const;

export const paramDef = {
	type: 'object',
	properties: {
		// スペースに置いてあるタイルから読むとき
		tileId: { type: 'string', format: 'misskey:id' },
		// 作者が、作成画面の試しの枠から読むとき
		defId: { type: 'string', format: 'misskey:id' },
		url: { type: 'string', minLength: 1, maxLength: 2048 },
	},
	required: ['url'],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(
		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		@Inject(DI.spaceTilesRepository)
		private spaceTilesRepository: SpaceTilesRepository,

		@Inject(DI.spaceTileDefsRepository)
		private spaceTileDefsRepository: SpaceTileDefsRepository,

		private spaceService: SpaceService,
		private spaceTileFetchService: SpaceTileFetchService,
	) {
		super(meta, paramDef, async (ps, me) => {
			if (!this.spaceService.isEnabled()) throw new ApiError(meta.errors.spacesDisabled);

			let hosts: string[];
			if (ps.tileId == null) {
				// 試しの枠。作者本人だけが、自分の宣言した先を読める
				const own = ps.defId == null ? null : await this.spaceTileDefsRepository.findOneBy({ id: ps.defId });
				if (own == null || own.userId !== me.id) throw new ApiError(meta.errors.notAllowed);
				hosts = own.fetchHosts;
			} else {
				hosts = await this.hostsOfTile(ps.tileId, me.id);
			}

			let result;
			try {
				result = await this.spaceTileFetchService.fetch(ps.url, hosts);
			} catch {
				throw new ApiError(meta.errors.fetchFailed);
			}
			if (result == null) throw new ApiError(meta.errors.notAllowed);
			return result;
		});
	}

	/** 置いてあるタイルが読める先。呼んだ人がそのスペースにいることも確かめる。 */
	private async hostsOfTile(tileId: string, meId: string): Promise<string[]> {
		const tile = await this.spaceTilesRepository.findOneBy({ id: tileId });
		if (tile == null) throw new ApiError(meta.errors.noSuchTile);
		const space = await this.spacesRepository.findOneBy({ id: tile.spaceId });
		if (space == null) throw new ApiError(meta.errors.noSuchSpace);
		if (space.endedAt != null) throw new ApiError(meta.errors.ended);
		if (!(await this.spaceService.isMember(space.id, meId))) throw new ApiError(meta.errors.notInSpace);

		// 読めるのは、タイルの定義が宣言していて、かつ置いた人が許した先だけ。
		// 作者があとから宣言を足しても、許し直されるまでは読めない。宣言から外した先も読めない
		const def = tile.defId == null ? null : await this.spaceTileDefsRepository.findOneBy({ id: tile.defId });
		if (def == null) throw new ApiError(meta.errors.notAllowed);
		return tile.allowedHosts.filter(host => def.fetchHosts.includes(host));
	}
}
