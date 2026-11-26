/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export const packedSpaceTileSchema = {
	type: 'object',
	properties: {
		id: {
			type: 'string',
			optional: false, nullable: false,
			format: 'id',
		},
		spaceId: {
			type: 'string',
			optional: false, nullable: false,
			format: 'id',
		},
		kind: {
			type: 'string',
			optional: false, nullable: false,
		},
		creatorId: {
			type: 'string',
			optional: false, nullable: false,
			format: 'id',
		},
		position: {
			type: 'integer',
			optional: false, nullable: false,
		},
	},
} as const;
