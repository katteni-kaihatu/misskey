/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { AutoTranslationService } from '@/core/auto-translation/AutoTranslationService.js';
import { configResponse } from '@/server/api/auto-translation.js';

export const meta = { tags: ['admin'], requireCredential: true, requireAdmin: true, kind: 'read:admin:meta', res: configResponse } as const;
export const paramDef = { type: 'object', properties: {}, required: [] } as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(service: AutoTranslationService) {
		super(meta, paramDef, async () => service.getAdminConfig());
	}
}
