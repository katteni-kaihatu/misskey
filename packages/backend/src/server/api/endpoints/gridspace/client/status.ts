/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { GridspaceClientReadService } from '@/core/gridspace/GridspaceClientReadService.js';
import { clientStatusSchema } from '@/core/gridspace/client-read-protocol.js';
import { clientApiError, clientErrors } from './errors.js';

export const meta = {
	tags: ['account'], requireCredential: true, kind: 'read:account',
	description: 'Read GridSpace external-client capabilities using an application token.',
	limit: { duration: 60_000, max: 60 }, errors: clientErrors, res: clientStatusSchema,
} as const;
export const paramDef = { type: 'object', properties: {}, required: [] } as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(private reader: GridspaceClientReadService) {
		super(meta, paramDef, async (_ps, me, token) => {
			try { return await this.reader.status(me, token); } catch (error) { return clientApiError(error); }
		});
	}
}
