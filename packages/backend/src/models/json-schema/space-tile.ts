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
		def: {
			type: 'object',
			optional: false, nullable: true,
			properties: {
				id: { type: 'string', optional: false, nullable: false, format: 'id' },
				name: { type: 'string', optional: false, nullable: false },
				userId: { type: 'string', optional: false, nullable: false, format: 'id' },
				updatedAt: { type: 'string', optional: false, nullable: false, format: 'date-time' },
				fetchHosts: { type: 'array', optional: false, nullable: false, items: { type: 'string', optional: false, nullable: false } },
			},
		},
		allowedHosts: {
			type: 'array',
			optional: false, nullable: false,
			items: { type: 'string', optional: false, nullable: false },
		},
		hostOnly: {
			type: 'boolean',
			optional: false, nullable: false,
		},
	},
} as const;
