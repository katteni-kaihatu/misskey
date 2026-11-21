/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

async function upload(site, user, target, name, content) {
	const form = new FormData();
	for (const [key, value] of Object.entries({ ...target, i: user.token, name })) form.set(key, value);
	form.set('file', new Blob([content], { type: 'text/plain' }), name);
	const base = process.env.GRIDSPACE_LAB_LOOPBACK === '1' ? `http://127.0.0.1:${site.config.port}` : site.origin;
	const response = await fetch(`${base}/api/gridspace/private-upload`, { method: 'POST', body: form, redirect: 'error', signal: AbortSignal.timeout(30000) });
	assert.equal(response.status, 200, `${site.role} guest attachment upload`);
	const file = await response.json();
	assert.ok(file.id);
	assert.equal(file.name, name);
	return file;
}

export async function testGuestOperations({ g, r, users, localChannels, run, fixtures, remember, check, api, eventually, createNote, channelContains, uri }) {
	for (const origin of [g, r]) {
		const home = origin === g ? r : g;
		const actor = users.get(home).reader;
		const author = users.get(origin).author;
		const channel = localChannels.get(home)[0];
		const actorUri = `${home.origin}/users/${actor.id}`;
		const atHome = (endpoint, params) => api(home, endpoint, params, actor.token);
		const atOrigin = (endpoint, params) => api(origin, endpoint, params, author.token);
		const lookup = target => atHome('gridspace/private-notes', { ...target, mode: 'show' });
		const notifications = options => atHome('gridspace/notifications', { source: 'channel', ...options });
		const reply = params => atHome('gridspace/private-reply', { expectedActorUri: actorUri, ...params });
		const direction = `${home.role} guest on ${origin.role}`;
		let target, child, grandchild;

		await check(`${direction}: remote-only poll and current actor`, async () => {
			const post = await createNote(origin, author, 'guest-operations', {
				includeDefault: false, channelTargets: [{ origin: home.origin, channelId: channel.id }],
				poll: { choices: ['first', 'second'], multiple: false },
			});
			target = { conversationUri: post.canonicalUri, noteId: post.note.id };
			await eventually(direction + ' active placement', () => channelContains(home, actor, home.origin, channel.id, post.canonicalUri), 60000);
			const prepared = await reply({ ...target, action: 'prepare' });
			assert.equal(prepared.account.uri, actorUri);
			assert.equal(prepared.canReply, true);
			assert.equal(prepared.canAttach, true);
			assert.equal(prepared.localOnly, true);
			assert.equal((await lookup(target)).notes[0]?.multiNoteKind, 'root');
		});

		await check(`${direction}: reaction membership and canonical poll vote`, async () => {
			const action = params => atHome('gridspace/private-action', { ...target, expectedActorUri: actorUri, ...params });
			for (const reaction of ['👍', '🎉', '🎉']) await action({ action: 'add-reaction', reaction });
			const reacted = (await action({ action: 'prepare' })).note;
			assert.deepEqual(new Set(reacted.myReactions), new Set(['👍', '🎉']));
			assert.equal(reacted.reactions['🎉'], 1);
			for (let i = 0; i < 2; i++) await action({ action: 'remove-reaction', reaction: '🎉' });
			const removed = (await lookup(target)).notes[0];
			assert.deepEqual(removed.myReactions, ['👍']);
			assert.equal(removed.reactions['🎉'] ?? 0, 0);
			for (let i = 0; i < 2; i++) {
				const voted = (await action({ action: 'vote', choice: 1 })).note;
				assert.equal(voted.poll.choices[1].isVoted, true);
				assert.equal(voted.poll.choices[1].votes, 1);
			}
			const native = await atOrigin('notes/show', { noteId: target.noteId });
			assert.equal(native.poll.choices[1].votes, 1);
			assert.equal(native.poll.choices[1].isVoted, false);
		});

		await check(`${direction}: attachment and idempotent origin-hosted reply`, async () => {
			const name = `guest-${home.role}-${run}.txt`;
			const content = `Multi Note attachment ${run}`;
			const file = await upload(home, actor, { ...target, expectedActorUri: actorUri }, name, content);
			const sent = { ...target, action: 'send', requestId: randomUUID(), text: `Guest reply ${run}`, fileIds: [file.id] };
			const id = (await reply(sent)).createdNoteId;
			assert.ok(id);
			assert.equal((await reply(sent)).createdNoteId, id);
			const note = await atOrigin('notes/show', { noteId: id });
			child = { noteId: id, conversationUri: uri(origin, note) };
			assert.equal(note.replyId, target.noteId);
			assert.equal(note.multiNoteKind, 'conversation-reply');
			assert.equal(note.includeDefault, false);
			assert.equal(note.localOnly, true);
			assert.equal(note.channelId ?? null, null);
			const body = (await lookup(child)).notes[0];
			assert.equal(body.author.uri, actorUri);
			assert.equal(body.canDelete, true);
			assert.equal(body.files[0]?.name, name);
			const fileUrl = new URL(body.files[0].url);
			const servingSite = [origin, home].find(site => site.origin === fileUrl.origin);
			assert.ok(servingSite, 'guest file belongs to the test pair');
			const downloadUrl = process.env.GRIDSPACE_LAB_LOOPBACK === '1' ? `http://127.0.0.1:${servingSite.config.port}${fileUrl.pathname}${fileUrl.search}` : fileUrl;
			const download = await fetch(downloadUrl, { signal: AbortSignal.timeout(15000) });
			assert.equal(download.status, 200);
			assert.equal(await download.text(), content);
			assert.ok((await atHome('drive/files', { limit: 100 })).some(original => original.name === name && original.size > 0));
			fixtures.notes[origin.role + '_guest_reply'] = { id, canonicalUri: child.conversationUri, fileId: file.id };
			remember();
		});

		await check(`${direction}: limited reply and reaction notifications and per-ID read`, async () => {
			const native = (await atOrigin('notes/create', { text: `Response for guest ${run}`, replyId: child.noteId, visibility: 'public' })).createdNote;
			grandchild = { noteId: native.id, conversationUri: uri(origin, native) };
			assert.equal(native.replyId, child.noteId);
			assert.equal(native.multiNoteKind, 'conversation-reply');
			await atOrigin('notes/extended-reactions/create', { noteId: child.noteId, reaction: '⭐' });
			let page, matching;
			await eventually(direction + ' two guest notifications', async () => {
				page = await notifications({ limit: 40 });
				matching = page.remote.filter(item => (item.type === 'reply' && item.note?.id === grandchild.noteId) || (item.type === 'reaction' && item.note?.id === child.noteId));
				return matching.some(item => item.type === 'reply') && matching.some(item => item.type === 'reaction');
			}, 60000);
			assert.equal(matching.length, 2);
			assert.equal(new Set(matching.map(item => item.id)).size, 2);
			assert.ok(page.remote.every(item => item.type === 'reply' || item.type === 'reaction'));
			await assert.rejects(atHome('gridspace/notifications', { source: 'peer', limit: 1 }),
				error => error.code === 'GRIDSPACE_NOTIFICATIONS_UNAVAILABLE');
			const initial = (await notifications({ countOnly: true })).unreadCount;
			assert.ok(initial >= 2);
			const notice = matching.find(item => item.type === 'reply');
			const read = { source: 'channel', ids: [notice.id], recipientId: page.recipientId, origin: page.origin };
			for (let i = 0; i < 2; i++) assert.equal((await atHome('gridspace/notifications/read', read)).unreadCount, initial - 1);
			const selected = (await notifications({ ids: matching.map(item => item.id) })).remote;
			assert.equal(selected.find(item => item.id === notice.id)?.isRead, true);
			assert.equal(selected.find(item => item.type === 'reaction')?.isRead, false);
		});

		await check(`${direction}: public thread after removal and author deletion`, async () => {
			const originals = [target, child, grandchild];
			const visitorStatus = async original => {
				try { return (await api(origin, 'notes/show', { noteId: original.noteId })).id; } catch (error) {
					if (error.code === 'CONTENT_RESTRICTED_BY_SERVER') return error.code;
					throw error;
				}
			};
			const before = await Promise.all(originals.map(visitorStatus));
			await atOrigin('gridspace/multi-note/remove', { canonicalUri: target.conversationUri, channelOrigin: home.origin, channelId: channel.id });
			await eventually(direction + ' placement removed', async () => !await channelContains(home, actor, home.origin, channel.id, target.conversationUri), 60000);
			await eventually(direction + ' reply permission revoked', async () => !(await reply({ ...target, action: 'prepare' })).canReply);
			assert.deepEqual(await Promise.all(originals.map(visitorStatus)), before);
			for (const original of originals) {
				assert.equal((await api(origin, 'notes/show', { noteId: original.noteId }, users.get(origin).reader.token)).id, original.noteId);
				assert.equal((await lookup(original)).notes[0]?.id, original.noteId);
			}
			const thread = (await atHome('gridspace/private-notes', { ...target, mode: 'context', order: 'oldest' })).notes;
			assert.deepEqual(thread.map(note => note.id), [target.noteId, child.noteId, grandchild.noteId]);
			await assert.rejects(atHome('gridspace/delete-reply', { canonicalUri: grandchild.conversationUri, requestId: randomUUID() }), error => error.code === 'GRIDSPACE_DELETE_REPLY_UNAVAILABLE');
			const deletion = { canonicalUri: child.conversationUri, requestId: randomUUID() };
			for (let i = 0; i < 2; i++) assert.equal((await atHome('gridspace/delete-reply', deletion)).deleted, true);
			await assert.rejects(atOrigin('notes/show', { noteId: child.noteId }), error => error.code === 'NO_SUCH_NOTE');
			assert.equal((await atOrigin('notes/show', { noteId: target.noteId })).id, target.noteId);
		});

		await check(`${direction}: standard vote on a paired localOnly mirror`, async () => {
			const post = await createNote(origin, author, 'mirror-vote', {
				includeDefault: true, localOnly: true, channelIds: [localChannels.get(origin)[0].id],
				poll: { choices: ['left', 'right'], multiple: false },
			});
			let mirror;
			await eventually(direction + ' regular peer mirror', async () => {
				try {
					mirror = (await atHome('ap/show', { uri: post.canonicalUri })).object;
					return mirror.uri === post.canonicalUri;
				} catch (error) {
					if (['REQUEST_FAILED', 'NO_SUCH_OBJECT'].includes(error.code)) return false;
					throw error;
				}
			}, 60000);
			assert.equal(mirror.localOnly, true);
			await atHome('notes/polls/vote', { noteId: mirror.id, choice: 0 });
			const ownCopy = await atHome('notes/show', { noteId: mirror.id });
			assert.equal(ownCopy.poll.choices[0].votes, 1);
			assert.equal(ownCopy.poll.choices[0].isVoted, true);
			assert.equal((await atOrigin('notes/show', { noteId: post.note.id })).poll.choices[0].votes, 1);
			await atOrigin('notes/polls/vote', { noteId: post.note.id, choice: 1 });
			await eventually(direction + ' aggregate reaches passive mirror', async () => {
				const refreshed = await atHome('notes/show', { noteId: mirror.id });
				return refreshed.poll.choices[1].votes === 1 && !refreshed.poll.choices[1].isVoted && refreshed.poll.choices[0].isVoted;
			}, 60000);
		});
	}
}
