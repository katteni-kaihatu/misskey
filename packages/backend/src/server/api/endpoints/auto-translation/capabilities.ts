/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { AutoTranslationService } from '@/core/auto-translation/AutoTranslationService.js';

export const meta = {
	tags: ['notes'], requireCredential: true, kind: 'read:account',
	res: {
		type: 'object', optional: false, nullable: false,
		properties: {
			available: { type: 'boolean', optional: false, nullable: false },
			languages: { type: 'array', optional: false, nullable: false, items: { type: 'string', optional: false, nullable: false } },
		},
	},
} as const;
export const paramDef = { type: 'object', properties: {}, required: [] } as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(service: AutoTranslationService) {
		super(meta, paramDef, async (_ps, me) => service.capabilities(me));
	}
}
