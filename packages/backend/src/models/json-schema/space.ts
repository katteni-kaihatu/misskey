/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export const packedSpaceSchema = {
	type: 'object',
	properties: {
		id: {
			type: 'string',
			optional: false, nullable: false,
			format: 'id',
		},
		createdAt: {
			type: 'string',
			optional: false, nullable: false,
			format: 'date-time',
		},
		endedAt: {
			type: 'string',
			optional: false, nullable: true,
			format: 'date-time',
		},
		hostId: {
			type: 'string',
			optional: false, nullable: false,
			format: 'id',
		},
		host: {
			type: 'object',
			optional: false, nullable: false,
			ref: 'UserLite',
		},
		name: {
			type: 'string',
			optional: false, nullable: false,
		},
		access: {
			type: 'string',
			optional: false, nullable: false,
			enum: ['local', 'followers'],
		},
		noteScope: {
			type: 'string',
			optional: false, nullable: false,
			enum: ['local', 'public', 'none'],
		},
		announceNoteId: {
			type: 'string',
			optional: false, nullable: true,
			format: 'id',
		},
		memberCount: {
			type: 'integer',
			optional: false, nullable: false,
		},
		participantCount: {
			type: 'integer',
			optional: false, nullable: false,
		},
		peakCount: {
			type: 'integer',
			optional: false, nullable: false,
		},
		canJoin: {
			type: 'boolean',
			optional: false, nullable: false,
		},
	},
} as const;
