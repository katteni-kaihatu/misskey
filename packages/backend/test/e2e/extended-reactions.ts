/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

process.env.NODE_ENV = 'test';

import { beforeAll, describe, expect, test } from 'vitest';
import type * as Misskey from 'misskey-js';
import { api, post, signup } from '../utils.js';

describe('Instance-local extended reactions', () => {
	let alice: Misskey.entities.SignupResponse;
	let bob: Misskey.entities.SignupResponse;
	beforeAll(async () => {
		alice = await signup({ username: 'alice' });
		bob = await signup({ username: 'bob' });
	});

	const add = (noteId: string, reaction: string) => api('notes/extended-reactions/create', { noteId, reaction }, bob);
	const remove = (noteId: string, reaction: string) => api('notes/extended-reactions/delete', { noteId, reaction }, bob);
	const state = async (noteId: string) => (await api('notes/extended-reactions/show', { noteIds: [noteId] }, bob)).body[0];

	test('first reaction remains compatible; extra counts and users are separate', async () => {
		const note = await post(alice, { text: 'Multiple reactions' });
		expect((await add(note.id, '👍')).status).toBe(204);
		expect((await add(note.id, '🎉')).status).toBe(204);
		const legacy = await api('notes/show', { noteId: note.id }, bob);
		expect(legacy.body.reactions).toEqual({ '👍': 1 });
		expect((await api('notes/reactions', { noteId: note.id }, bob)).body).toHaveLength(1);
		expect((await state(note.id)).reactions).toEqual({ '👍': 1, '🎉': 1 });
		expect((await state(note.id)).myReactions).toEqual(expect.arrayContaining(['👍', '🎉']));
		const users = await api('notes/extended-reactions/list', { noteId: note.id, type: '🎉' }, bob);
		expect(users.body.map(r => r.user.id)).toEqual([bob.id]);
	});

	test('removing the first reaction never promotes extras; clearing resets the first slot', async () => {
		const note = await post(alice, { text: 'No promotion' });
		await add(note.id, '👍');
		await add(note.id, '🎉');
		expect((await remove(note.id, '👍')).status).toBe(204);
		await add(note.id, '🚀');
		expect((await api('notes/reactions', { noteId: note.id }, bob)).body).toHaveLength(0);
		expect((await state(note.id)).reactions).toEqual({ '🎉': 1, '🚀': 1 });
		await remove(note.id, '🎉');
		await remove(note.id, '🚀');
		await add(note.id, '❤️');
		expect((await api('notes/reactions', { noteId: note.id }, bob)).body[0].type).toBe('❤');
	});

	test('legacy replacement/deletion leaves extras untouched and merged icons deduplicate overlaps', async () => {
		const note = await post(alice, { text: 'Legacy client' });
		await add(note.id, '👍');
		await add(note.id, '🎉');
		expect((await api('notes/reactions/create', { noteId: note.id, reaction: '🎉' }, bob)).status).toBe(204);
		expect((await state(note.id)).reactions).toEqual({ '🎉': 1 });
		expect((await api('notes/extended-reactions/list', { noteId: note.id, type: '🎉' }, bob)).body).toHaveLength(1);
		await api('notes/reactions/delete', { noteId: note.id }, bob);
		expect((await state(note.id)).myReactions).toEqual(['🎉']);
		await remove(note.id, '🎉');
		expect((await state(note.id)).myReactions).toEqual([]);
	});

	test('simultaneous additions create only one legacy reaction and reject duplicate emojis', async () => {
		const note = await post(alice, { text: 'Concurrency' });
		const results = await Promise.all([add(note.id, '👍'), add(note.id, '🎉'), add(note.id, '🚀')]);
		expect(results.map(r => r.status)).toEqual([204, 204, 204]);
		expect((await api('notes/reactions', { noteId: note.id }, bob)).body).toHaveLength(1);
		expect((await state(note.id)).myReactions).toHaveLength(3);
		expect((await add(note.id, '👍')).status).toBe(400);
	});

	test('private-note reads and writes preserve visibility checks', async () => {
		const note = await post(alice, { text: 'Private', visibility: 'specified', visibleUserIds: [] });
		expect((await api('notes/extended-reactions/show', { noteIds: [note.id] }, bob)).body).toEqual([]);
		expect((await add(note.id, '👍')).status).toBe(400);
		expect((await api('notes/extended-reactions/list', { noteId: note.id }, bob)).status).toBe(400);
	});

	test('like-only acceptance and Unicode normalization prevent extra equivalent reactions', async () => {
		const note = await post(alice, { text: 'Likes only', reactionAcceptance: 'likeOnly' });
		await add(note.id, '👍');
		expect((await add(note.id, '🎉')).status).toBe(400);
		expect((await state(note.id)).myReactions).toEqual(['❤']);
		expect((await remove(note.id, '❤️')).status).toBe(204);
	});

	test('merged list pagination includes extras without repeating a user/emoji', async () => {
		const note = await post(alice, { text: 'Pagination' });
		await add(note.id, '👍');
		await add(note.id, '🎉');
		await add(note.id, '🚀');
		const first = (await api('notes/extended-reactions/list', { noteId: note.id, limit: 2 }, bob)).body;
		const second = (await api('notes/extended-reactions/list', { noteId: note.id, limit: 2, untilId: first[1].id }, bob)).body;
		expect(first).toHaveLength(2);
		expect(second).toHaveLength(1);
		expect(new Set([...first, ...second].map(r => r.id)).size).toBe(3);
	});
});
