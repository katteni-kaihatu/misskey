/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

async function apGet(site, canonicalUri) {
	const url = new URL(canonicalUri);
	assert.equal(url.origin, site.origin);
	const origin = process.env.GRIDSPACE_LAB_LOOPBACK === '1' ? `http://127.0.0.1:${site.config.port}` : site.origin;
	return fetch(origin + url.pathname + url.search, {
		headers: { accept: 'application/activity+json' },
		redirect: 'error', signal: AbortSignal.timeout(15000),
	});
}

async function apDocument(site, canonicalUri) {
	const response = await apGet(site, canonicalUri);
	assert.equal(response.status, 200);
	assert.match(response.headers.get('content-type') ?? '', /application\/(activity\+json|ld\+json)/);
	return response.json();
}

export async function testExternalFederation({ g, r, e, users, localChannels, run, fixtures, remember, check, api, eventually, createNote, uri }) {
	const password = randomBytes(24).toString('base64url');
	const outside = await api(e, 'admin/accounts/create', { username: `mn_ext_${run}`, password }, e.accounts.admin.token);
	fixtures.users.E_external = { ...outside, password };
	remember();
	const role = await api(e, 'admin/roles/create', {
		name: `Multi Note external acceptance ${run}`, description: '', color: null, iconUrl: null, target: 'manual',
		condFormula: {}, isPublic: false, isModerator: false, isAdministrator: false, asBadge: false,
		canEditMembersByModerator: false, displayOrder: 0, policies: { rateLimitFactor: { useDefault: false, priority: 2, value: 0 } },
	}, e.accounts.admin.token);
	await api(e, 'admin/roles/assign', { roleId: role.id, userId: outside.id }, e.accounts.admin.token);

	for (const site of [g, r]) {
		const author = users.get(site).author;
		const actorUri = `${site.origin}/users/${author.id}`;
		const remote = await api(e, 'users/show', { username: author.username, host: new URL(site.origin).host }, outside.token);
		await check(`E follows the ${site.role} author through ActivityPub`, async () => {
			await api(e, 'following/create', { userId: remote.id }, outside.token);
			await eventually(`E follows ${site.role}`, async () => (await api(e, 'users/show', { userId: remote.id }, outside.token)).isFollowing, 60000);
			await eventually(`${site.role} accepted E follower`, async () => {
				const followers = await api(site, 'users/followers', { userId: author.id, limit: 100 }, author.token);
				return followers.some(row => row.follower?.username === outside.username && row.follower.host === new URL(e.origin).host);
			}, 60000);
		});

		const channelIds = localChannels.get(site).slice(0, 2).map(channel => channel.id);
		assert.equal(channelIds.length, 2);
		const dedicated = await createNote(site, author, 'external-dedicated', { includeDefault: false, channelIds });
		const child = (await api(site, 'notes/create', { text: `Multi Note external dedicated child ${run}`, visibility: 'public', replyId: dedicated.note.id }, author.token)).createdNote;
		assert.equal(child.multiNoteKind, 'conversation-reply');
		const childUri = uri(site, child);
		fixtures.notes[`${site.role}_external-dedicated-child`] = { ...child, canonicalUri: childUri };
		remember();
		const mixed = await createNote(site, author, 'external-mixed', { includeDefault: true, channelIds, localOnly: false });
		const ordinary = (await api(site, 'notes/create', { text: `Multi Note external control ${run}`, visibility: 'public', localOnly: false }, author.token)).createdNote;
		const ordinaryUri = uri(site, ordinary);
		const timeline = () => api(e, 'notes/timeline', { limit: 100 }, outside.token);
		let copy;

		await check(`${site.role} to E delivers one ordinary AP Note for two placements`, async () => {
			await eventually(`E receives ${site.role} ordinary control and placed note`, async () => {
				const rows = await timeline();
				return [mixed.canonicalUri, ordinaryUri].every(id => rows.some(row => row.uri === id));
			}, 90000);
			const byAuthor = await api(e, 'users/notes', { userId: remote.id, limit: 100 }, outside.token);
			const matches = byAuthor.filter(row => row.text === mixed.note.text);
			assert.equal(matches.length, 1);
			[copy] = matches;
			assert.equal(copy.uri, mixed.canonicalUri);
			assert.equal(copy.channelId ?? null, null);
			assert.equal(copy.userId, remote.id);
			const normal = await apDocument(site, ordinaryUri);
			const placed = await apDocument(site, mixed.canonicalUri);
			assert.deepEqual(Object.keys(placed).sort(), Object.keys(normal).sort());
			for (const field of ['@context', 'attributedTo', 'to', 'cc', 'tag', 'type']) assert.deepEqual(placed[field], normal[field], field);
			assert.equal(placed.id, mixed.canonicalUri);
			assert.equal(placed.type, 'Note');
			assert.equal(placed.attributedTo, actorUri);
		});

		await check(`E replies and reacts to the ${site.role} ordinary AP note`, async () => {
			const reply = (await api(e, 'notes/create', { text: `Multi Note E reply to ${site.role} ${run}`, replyId: copy.id, visibility: 'public', localOnly: false }, outside.token)).createdNote;
			const replyUri = uri(e, reply);
			await api(e, 'notes/reactions/create', { noteId: copy.id, reaction: '👍' }, outside.token);
			await eventually(`${site.role} receives E reply and reaction`, async () => {
				const replies = await api(site, 'notes/replies', { noteId: mixed.note.id, limit: 100 }, author.token);
				const reactions = await api(site, 'notes/reactions', { noteId: mixed.note.id, limit: 100 }, author.token);
				const remoteUser = user => user?.username === outside.username && user.host === new URL(e.origin).host;
				return replies.filter(note => note.uri === replyUri && note.replyId === mixed.note.id && remoteUser(note.user)).length === 1 &&
					reactions.filter(row => row.type === '👍' && remoteUser(row.user)).length === 1;
			}, 90000);
		});

		await check(`E votes on the ${site.role} placed ActivityPub Question`, async () => {
			const poll = await createNote(site, author, 'external-poll', {
				includeDefault: true, channelIds, localOnly: false, poll: { choices: ['a', 'b'], multiple: false },
			});
			const question = await apDocument(site, poll.canonicalUri);
			assert.equal(question.type, 'Question');
			assert.deepEqual(question.oneOf.map(choice => choice.name), ['a', 'b']);
			let imported;
			await eventually(`E receives ${site.role} poll`, async () => {
				imported = (await timeline()).find(row => row.uri === poll.canonicalUri);
				return !!imported;
			}, 90000);
			assert.deepEqual(imported.poll.choices.map(choice => choice.text), ['a', 'b']);
			await api(e, 'notes/polls/vote', { noteId: imported.id, choice: 0 }, outside.token);
			await eventually(`ordinary E vote reaches ${site.role} poll`, async () => {
				const original = await api(site, 'notes/show', { noteId: poll.note.id }, author.token);
				return original.poll.choices[0].votes === 1 && original.poll.choices[1].votes === 0;
			}, 60000);
		});

		await check(`${site.role} dedicated original and child stay out of AP and E timelines`, async () => {
			const outbox = await apDocument(site, actorUri + '/outbox?page=true');
			const objectIds = outbox.orderedItems.map(item => typeof item.object === 'string' ? item.object : item.object?.id);
			assert.equal(objectIds.filter(id => id === mixed.canonicalUri).length, 1);
			assert.ok(objectIds.includes(ordinaryUri));
			const views = await Promise.all([timeline(), api(e, 'users/notes', { userId: remote.id, withReplies: true, limit: 100 }, outside.token), api(e, 'notes/global-timeline', { limit: 100 }, outside.token)]);
			for (const hidden of [dedicated.canonicalUri, childUri]) {
				assert.ok(!objectIds.includes(hidden));
				assert.ok(views.every(rows => !rows.some(note => note.uri === hidden)));
				const response = await apGet(site, hidden);
				assert.equal(response.status, 404);
				await response.body?.cancel();
				await assert.rejects(api(e, 'ap/show', { uri: hidden }, outside.token), error => ['REQUEST_FAILED', 'NO_SUCH_OBJECT'].includes(error.code));
			}
		});
	}
}
