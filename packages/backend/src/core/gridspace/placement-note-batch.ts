/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { GridspaceLinkError } from './GridspaceLinkService.js';
import { conversationUriSchema, placementActorIdSchema } from './conversation-protocol.js';
import type { PrivatePage, PrivatePeerRequest } from './private-protocol.js';

export const PLACEMENT_NOTE_BATCH_PATH = '/gridspace/v1/private/placement-notes';
export const PLACEMENT_NOTE_BATCH_LIMIT = 20;
export type PlacementNoteTarget = { noteId: string; conversationUri: string };
export type PlacementNoteBatch = { placementActorId: string; items: PlacementNoteTarget[] };
export type PlacementNoteBatchResult = { items: { noteId: string; page: PrivatePage | null }[] };
export const placementNoteBatchSchema = {
	type: 'object', additionalProperties: false, required: ['placementActorId', 'items'],
	properties: {
		placementActorId: placementActorIdSchema,
		items: { type: 'array', minItems: 1, maxItems: PLACEMENT_NOTE_BATCH_LIMIT, uniqueItems: true, items: {
			type: 'object', additionalProperties: false, required: ['noteId', 'conversationUri'],
			properties: { noteId: placementActorIdSchema, conversationUri: conversationUriSchema },
		} },
	},
} as const;

/** Share transport only. Every conversation keeps its fresh before/after authorization. */
export async function readPlacementNoteBatch(input: PlacementNoteBatch, read: (request: PrivatePeerRequest) => Promise<PrivatePage>): Promise<PlacementNoteBatchResult> {
	if (new Set(input.items.map(item => item.noteId)).size !== input.items.length) throw new GridspaceLinkError('INVALID_REQUEST');
	const items: PlacementNoteBatchResult['items'] = [];
	for (let offset = 0; offset < input.items.length; offset += 4) {
		items.push(...await Promise.all(input.items.slice(offset, offset + 4).map(async target => {
			try {
				const page = await read({ placementActorId: input.placementActorId, ...target, mode: 'show', limit: 1 });
				return { noteId: target.noteId, page };
			} catch (error) {
				if (!(error instanceof GridspaceLinkError) || !['ACTION_REJECTED', 'AUTHORIZATION_REVOKED', 'LINK_REVOKED'].includes(error.code)) throw error;
				return { noteId: target.noteId, page: null };
			}
		})));
	}
	return { items };
}
