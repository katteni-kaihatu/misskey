/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export const CLIENT_TIMELINE_SCOPE = 'read:gridspace-client-timeline';
export const CLIENT_NOTIFICATION_SCOPE = 'read:gridspace-client-notifications';
export const CLIENT_PRIVATE_SCOPE = 'read:gridspace-client-private';
export const CLIENT_REVALIDATE_MS = 30_000;
export const CLIENT_CURSOR_TTL_MS = 10 * 60_000;

export class GridspaceClientError extends Error {
	constructor(public readonly code: 'APP_TOKEN_REQUIRED' | 'PERMISSION_DENIED' | 'AUTHORIZATION_REVOKED' | 'INVALID_CURSOR' | 'UNAVAILABLE') { super(code); }
}

const text = { type: 'string', optional: false, nullable: false } as const;
const nullableText = { ...text, nullable: true } as const;
const flag = { type: 'boolean', optional: false, nullable: false } as const;
export const clientAuthorSchema = { type: 'object', optional: false, nullable: false, properties: {
	username: text, name: nullableText, host: nullableText, uri: text,
} } as const;
export const clientNoteSummarySchema = { type: 'object', optional: false, nullable: false, properties: {
	id: text, uri: text, origin: text, createdAt: text, text: nullableText, cw: nullableText,
	visibility: text, author: clientAuthorSchema, fileCount: { type: 'integer', optional: false, nullable: false },
} } as const;
export const clientNoteSchema = { ...clientNoteSummarySchema, properties: {
	...clientNoteSummarySchema.properties, renote: { ...clientNoteSummarySchema, nullable: true },
} } as const;
export const clientSourceSchema = { type: 'object', optional: false, nullable: false, properties: {
	source: { ...text, enum: ['local', 'peer', 'channel'] },
	status: { ...text, enum: ['ok', 'disabled', 'unavailable', 'unauthorized'] }, retryable: flag,
} } as const;
export const clientTimelineSchema = { type: 'object', optional: false, nullable: false, properties: {
	version: { type: 'integer', optional: false, nullable: false },
	items: { type: 'array', optional: false, nullable: false, items: { type: 'object', optional: false, nullable: false, properties: {
		key: text, note: clientNoteSchema, validForMs: { type: 'integer', optional: false, nullable: true }, nextPolicyCheckAt: nullableText,
	} } },
	nextCursor: nullableText, complete: flag,
	sources: { type: 'array', optional: false, nullable: false, items: clientSourceSchema },
	revalidateAfterMs: { type: 'integer', optional: false, nullable: false },
} } as const;
export const clientNotificationsSchema = { type: 'object', optional: false, nullable: false, properties: {
	version: { type: 'integer', optional: false, nullable: false },
	items: { type: 'array', optional: false, nullable: false, items: { type: 'object', optional: false, nullable: false, properties: {
		key: text, id: text, createdAt: text, type: text, isRead: flag,
		user: { ...clientAuthorSchema, nullable: true }, note: { ...clientNoteSchema, nullable: true },
		body: nullableText, reaction: nullableText,
	} } },
	nextCursor: nullableText, source: clientSourceSchema,
	unreadCount: { type: 'integer', optional: false, nullable: true },
	validForMs: { type: 'integer', optional: false, nullable: false },
	revalidateAfterMs: { type: 'integer', optional: false, nullable: false },
} } as const;
export const clientStatusSchema = { type: 'object', optional: false, nullable: false, properties: {
	version: { type: 'integer', optional: false, nullable: false }, timeline: flag, notifications: flag, peerPrivate: flag,
	peer: { ...text, enum: ['ok', 'disabled', 'unavailable', 'unauthorized'] },
} } as const;

export interface ClientAuthorInput { id?: string; username: string; name?: string | null; host?: string | null; uri?: string | null; }
export interface ClientNoteInput {
	id: string; uri?: string | null; origin?: string; createdAt: string; text?: string | null; cw?: string | null; visibility: string;
	user?: ClientAuthorInput; author?: ClientAuthorInput; files?: unknown[]; renote?: ClientNoteInput | null;
}
export function clientAuthor(value: ClientAuthorInput, origin: string) {
	return { username: value.username, name: value.name ?? null, host: value.host ?? null,
		uri: value.uri ?? new URL(`/users/${value.id ?? value.username}`, origin).href };
}
/** Project only already-authorized content; origin does not identify the access route. */
export function clientNote(value: ClientNoteInput, localOrigin: string) {
	const summary = (note: ClientNoteInput) => {
		const uri = note.uri ?? new URL(`/notes/${note.id}`, note.origin ?? localOrigin).href;
		const origin = note.origin ?? new URL(uri).origin;
		const author = note.author ?? note.user;
		if (!author) return null;
		return { id: note.id, uri, origin, createdAt: note.createdAt, text: note.text ?? null, cw: note.cw ?? null,
			visibility: note.visibility, author: clientAuthor(author, origin), fileCount: note.files?.length ?? 0 };
	};
	const note = summary(value);
	return note ? { ...note, renote: value.renote ? summary(value.renote) : null } : null;
}
