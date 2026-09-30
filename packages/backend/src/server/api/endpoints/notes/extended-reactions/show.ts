/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { ExtendedReactionService } from '@/core/ExtendedReactionService.js';

export const meta = {
	description: 'Get merged ordinary and instance-local reaction counts for visible notes.',
	tags: ['reactions', 'notes'],
	requireCredential: false,
	res: {
		type: 'array', optional: false, nullable: false,
		items: {
			type: 'object', optional: false, nullable: false,
			properties: {
				noteId: { type: 'string', format: 'id', optional: false, nullable: false },
				reactions: { type: 'object', optional: false, nullable: false, additionalProperties: { type: 'number' } },
				reactionEmojis: { type: 'object', optional: false, nullable: false, additionalProperties: { type: 'string' } },
				myReaction: { type: 'string', optional: false, nullable: true },
				myReactions: { type: 'array', optional: false, nullable: false, items: { type: 'string', optional: false, nullable: false } },
			},
		},
	},
} as const;
export const paramDef = {
	type: 'object',
	properties: { noteIds: { type: 'array', items: { type: 'string', format: 'misskey:id' }, minItems: 1, maxItems: 100, uniqueItems: true } },
	required: ['noteIds'],
} as const;
@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(private extendedReactionService: ExtendedReactionService) {
		super(meta, paramDef, async (ps, me) => this.extendedReactionService.show(ps.noteIds, me));
	}
}
