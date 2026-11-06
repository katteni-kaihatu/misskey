/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { AutoTranslationService } from '@/core/auto-translation/AutoTranslationService.js';
import { configResponse, translationErrors, translationFailure } from '@/server/api/auto-translation.js';

export const meta = {
	tags: ['admin'], requireCredential: true, requireAdmin: true, kind: 'write:admin:meta',
	limit: { duration: 60_000, max: 30 },
	res: configResponse, errors: translationErrors,
} as const;
export const paramDef = {
	type: 'object',
	properties: {
		enabled: { type: 'boolean' }, baseUrl: { type: 'string', maxLength: 2048 }, model: { type: 'string', maxLength: 256 },
		apiKey: { type: 'string', nullable: true, maxLength: 4096 },
		allowPrivateNetwork: { type: 'boolean' }, maxConcurrency: { type: 'integer', minimum: 1, maximum: 16 },
	}, required: [],
} as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(service: AutoTranslationService) {
		super(meta, paramDef, async ps => {
			const update = { ...ps };
			// ApiCallService logs the original params on unexpected errors.
			delete ps.apiKey;
			return service.updateConfig(update).catch(translationFailure);
		});
	}
}
