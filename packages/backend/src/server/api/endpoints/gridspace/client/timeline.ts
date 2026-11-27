/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import { Endpoint } from '@/server/api/endpoint-base.js';
import { GridspaceClientReadService } from '@/core/gridspace/GridspaceClientReadService.js';
import { CLIENT_TIMELINE_SCOPE, clientTimelineSchema } from '@/core/gridspace/client-read-protocol.js';
import { clientApiError, clientErrors } from './errors.js';

export const meta = {
	tags: ['notes'], requireCredential: true, kind: CLIENT_TIMELINE_SCOPE,
	description: 'Read the home timeline. Peer data requires includePrivate and read:gridspace-client-private. Cursors are bound to the application token and its current permissions.',
	limit: { duration: 60_000, max: 60 }, errors: clientErrors, res: clientTimelineSchema,
} as const;
export const paramDef = { type: 'object', properties: {
	limit: { type: 'integer', minimum: 1, maximum: 40, default: 20 },
	cursor: { type: 'string', minLength: 1, maxLength: 4096 },
	includePrivate: { type: 'boolean', default: false },
}, required: [] } as const;

@Injectable()
export default class extends Endpoint<typeof meta, typeof paramDef> { // eslint-disable-line import/no-default-export
	constructor(private reader: GridspaceClientReadService) {
		super(meta, paramDef, async (ps, me, token) => {
			try { return await this.reader.home(me, token, { limit: ps.limit, cursor: ps.cursor, includePrivate: ps.includePrivate }); } catch (error) { return clientApiError(error); }
		});
	}
}
