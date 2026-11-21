/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { testGuestOperations } from './test-multi-note-guest.mjs';
import { testExternalFederation } from './test-multi-note-external.mjs';
import { testRetirement } from './test-multi-note-retirement.mjs';

process.env.GRIDSPACE_LAB_PROFILE = 'multi-note';
const { api, eventually, loadSite, savePrivateJson } = await import('./lab.mjs');
const repositories = JSON.parse(readFileSync(resolve('.config/multi-note-repositories.json'), 'utf8'));
const [g, r, e] = repositories.map((repository, index) => loadSite(repository, index));
const run = randomBytes(5).toString('hex');
const results = [];
const fixtures = { run, origins: [g.origin, r.origin, e.origin], users: {}, channels: {}, notes: {} };
const fixturePath = resolve('.config/multi-note-acceptance.json');
const resultPath = resolve('.config/multi-note-acceptance-results.json');

for (const site of [g, r, e]) site.accounts = JSON.parse(readFileSync(site.accountsPath, 'utf8')).accounts;
function remember() { savePrivateJson(fixturePath, fixtures); }
async function check(name, test) {
	await test();
	results.push({ name, status: 'pass' });
	savePrivateJson(resultPath, { run, results, completed: false });
	console.log(`PASS ${name}`);
}
function uri(site, note) { return note.uri ?? `${site.origin}/notes/${note.id}`; }
function itemUri(item) { return item.key ?? item.payload?.uri; }
async function channelItems(viewerSite, user, origin, channelId) {
	const page = await api(viewerSite, 'gridspace/timeline', { kind: 'channel', channelOrigin: origin, channelId, limit: 50 }, user.token);
	assert.ok(Array.isArray(page.items));
	return page.items;
}
async function channelContains(viewerSite, user, origin, channelId, noteUri) {
	return (await channelItems(viewerSite, user, origin, channelId)).some(item => itemUri(item) === noteUri);
}
async function createAccount(site, label) {
	const password = randomBytes(24).toString('base64url');
	const account = { ...await api(site, 'admin/accounts/create', { username: `mn_${label}_${run}`, password }, site.accounts.admin.token), password };
	fixtures.users[`${site.role}_${label}`] = account;
	remember();
	return account;
}
async function createChannel(site, user, label, extra = {}) {
	const channel = await api(site, 'channels/create', { name: `Multi Note ${label} ${run}`, description: 'Isolated Multi Note acceptance fixture', ...extra }, user.token);
	fixtures.channels[`${site.role}_${label}`] = { ...channel, origin: site.origin };
	remember();
	return channel;
}
async function createNote(site, user, label, params) {
	const request = { text: `Multi Note ${label} ${run}`, visibility: 'public', clientRequestId: randomUUID(), ...params };
	const response = await api(site, 'notes/create', request, user.token);
	const note = response.createdNote;
	assert.ok(note?.id);
	fixtures.notes[`${site.role}_${label}`] = { ...note, canonicalUri: uri(site, note), request };
	remember();
	return { note, request, canonicalUri: uri(site, note) };
}
async function rejected(request) {
	await assert.rejects(request, error => typeof error.code === 'string' && /MULTI_NOTE|GRIDSPACE_|INVALID_PARAM|INVALID_NOTE_PLACEMENT|CANNOT_|NO_SUCH_|PERMISSION|ACCESS_DENIED/.test(error.code));
}

try {
	const authorG = await createAccount(g, 'author');
	const authorR = await createAccount(r, 'author');
	const readerG = await createAccount(g, 'reader');
	const readerR = await createAccount(r, 'reader');
	const users = new Map([[g, { author: authorG, reader: readerG }], [r, { author: authorR, reader: readerR }]]);
	for (const site of [g, r]) {
		const role = await api(site, 'admin/roles/create', {
			name: `Multi Note acceptance ${run}`, description: 'Isolated acceptance fixtures', color: null, iconUrl: null,
			target: 'manual', condFormula: {}, isPublic: false, isModerator: false, isAdministrator: false,
			asBadge: false, canEditMembersByModerator: false, displayOrder: 0,
			policies: { rateLimitFactor: { useDefault: false, priority: 2, value: 0 }, canSearchNotes: { useDefault: false, priority: 2, value: true } },
		}, site.accounts.admin.token);
		for (const user of Object.values(users.get(site))) await api(site, 'admin/roles/assign', { roleId: role.id, userId: user.id }, site.accounts.admin.token);
		await api(site, 'following/create', { userId: users.get(site).author.id }, users.get(site).reader.token);
	}
	const localChannels = new Map();
	for (const site of [g, r]) {
		const author = users.get(site).author;
		localChannels.set(site, [await createChannel(site, author, 'one'), await createChannel(site, author, 'two')]);
	}

	await check('local and peer capabilities are advertised in both directions', async () => {
		for (const site of [g, r]) {
			assert.equal((await api(site, 'meta', { detail: true })).features?.multiNote, true);
			await eventually(`${site.role} peer capability`, async () => (await api(site, 'meta', { detail: true })).features?.multiNotePeer === true, 60000);
		}
	});

	for (const site of [g, r]) {
		const peer = site === g ? r : g;
		const { author, reader } = users.get(site);
		const peerUser = users.get(peer).reader;
		const [first, second] = localChannels.get(site);
		const [remote] = localChannels.get(peer);
		let mixed;
		let dedicated;

		await check(`${site.role}: one original in normal and two local channels`, async () => {
			mixed = await createNote(site, author, 'mixed', { includeDefault: true, channelIds: [first.id, second.id] });
			assert.equal(mixed.note.includeDefault, true);
			assert.equal(mixed.note.channelId ?? null, null);
			for (const channel of [first, second]) {
				await eventually(`${site.role} local channel placement`, () => channelContains(site, reader, site.origin, channel.id, mixed.canonicalUri));
			}
			assert.equal((await api(site, 'notes/local-timeline', { limit: 100 }, reader.token)).filter(note => note.id === mixed.note.id).length, 1);
			await eventually('one default home delivery', async () => (await api(site, 'notes/timeline', { limit: 100 }, reader.token)).filter(note => note.id === mixed.note.id).length === 1);
		});

		await check(`${site.role}: channels-only is public by URL but absent from ordinary timelines`, async () => {
			dedicated = await createNote(site, author, 'dedicated', { includeDefault: false, channelIds: [first.id, second.id] });
			assert.equal(dedicated.note.includeDefault, false);
			assert.equal(dedicated.note.localOnly, true);
			assert.equal(dedicated.note.gridspaceShared, false);
			assert.equal((await api(site, 'notes/show', { noteId: dedicated.note.id })).id, dedicated.note.id);
			for (const endpoint of ['notes/local-timeline', 'notes/global-timeline', 'notes/hybrid-timeline']) {
				assert.equal((await api(site, endpoint, { limit: 100 }, reader.token)).some(note => note.id === dedicated.note.id), false, endpoint);
			}
			for (const channel of [first, second]) await eventually(`${site.role} dedicated channel`, () => channelContains(site, reader, site.origin, channel.id, dedicated.canonicalUri));
		});

		await check(`${site.role}: response recovery and idempotent creation`, async () => {
			const status = await api(site, 'notes/create-status', { clientRequestId: dedicated.request.clientRequestId }, author.token);
			assert.equal(status.status, 'created');
			assert.equal(status.createdNote.id, dedicated.note.id);
			const replay = await api(site, 'notes/create', dedicated.request, author.token);
			assert.equal(replay.createdNote.id, dedicated.note.id);
			await rejected(api(site, 'notes/create', { ...dedicated.request, text: `${dedicated.request.text} changed` }, author.token));
			assert.equal((await api(site, 'notes/create-status', { clientRequestId: dedicated.request.clientRequestId }, reader.token)).status, 'missing');
		});

		await check(`${site.role}: invalid destination combinations are rejected`, async () => {
			const base = { text: `Multi Note invalid ${run}`, clientRequestId: randomUUID(), includeDefault: false };
			await rejected(api(site, 'notes/create', { ...base, channelIds: [] }, author.token));
			await rejected(api(site, 'notes/create', { ...base, clientRequestId: randomUUID(), channelIds: [first.id, first.id] }, author.token));
			await rejected(api(site, 'notes/create', { ...base, clientRequestId: randomUUID(), channelId: first.id, channelIds: [second.id] }, author.token));
			await rejected(api(site, 'notes/create', { ...base, clientRequestId: randomUUID(), visibility: 'followers', channelIds: [first.id] }, author.token));
		});

		await check(`${site.role}: dedicated replies share the original conversation`, async () => {
			const reply = (await api(site, 'notes/create', { text: `Multi Note reply ${run}`, replyId: dedicated.note.id, visibility: 'public' }, reader.token)).createdNote;
			assert.equal(reply.replyId, dedicated.note.id);
			assert.equal(reply.includeDefault, false);
			assert.equal(reply.localOnly, true);
			assert.equal(reply.multiNoteKind, 'conversation-reply');
			assert.equal((await channelItems(site, reader, site.origin, first.id)).some(item => item.payload?.id === reply.id), false);
			fixtures.notes[`${site.role}_local_reply`] = { ...reply, canonicalUri: uri(site, reply) };
			remember();
		});

		await check(`${site.role} to ${peer.role}: a remote-only placement is the same original`, async () => {
			const posted = await createNote(site, author, 'remote', {
				includeDefault: false, channelTargets: [{ origin: peer.origin, channelId: remote.id }],
				poll: { choices: ['one', 'two'], multiple: false },
			});
			await eventually('remote channel shows canonical original', () => channelContains(peer, peerUser, peer.origin, remote.id, posted.canonicalUri), 60000);
			await eventually('home site opens peer channel without a hydration loop', () => channelContains(site, reader, peer.origin, remote.id, posted.canonicalUri), 60000);
			assert.equal((await api(site, 'notes/show', { noteId: posted.note.id }, reader.token)).id, posted.note.id);
		});

		await check(`${site.role} to ${peer.role}: default and channel routes share one normal mirror`, async () => {
			const posted = await createNote(site, author, 'shared-mixed', {
				includeDefault: true, gridspaceShared: true,
				channelTargets: [{ origin: site.origin, channelId: first.id }, { origin: peer.origin, channelId: remote.id }],
			});
			await eventually('normal mirror is used by the peer channel', async () => {
				const matches = (await channelItems(peer, peerUser, peer.origin, remote.id)).filter(item => itemUri(item) === posted.canonicalUri);
				return matches.length === 1 && matches[0].representation === 'normal' && matches[0].readOnly !== true;
			}, 60000);
			await eventually('legacy channel API includes the real normal mirror', async () => (await api(peer, 'channels/timeline', { channelId: remote.id, limit: 100 }, peerUser.token)).filter(note => uri(peer, note) === posted.canonicalUri).length === 1, 60000);
			assert.equal((await channelItems(site, reader, peer.origin, remote.id)).filter(item => itemUri(item) === posted.canonicalUri).length, 1);
		});

		await check(`${site.role}: removing one placement preserves another and the public original`, async () => {
			await api(site, 'gridspace/multi-note/remove', { canonicalUri: dedicated.canonicalUri, channelOrigin: site.origin, channelId: first.id }, author.token);
			await eventually('removed channel no longer lists original', async () => !await channelContains(site, reader, site.origin, first.id, dedicated.canonicalUri));
			assert.equal(await channelContains(site, reader, site.origin, second.id, dedicated.canonicalUri), true);
			assert.equal((await api(site, 'notes/show', { noteId: dedicated.note.id })).id, dedicated.note.id);
		});

		await check(`${site.role}: deletion remains terminal for the creation receipt`, async () => {
			await api(site, 'notes/delete', { noteId: dedicated.note.id }, author.token);
			assert.equal((await api(site, 'notes/create-status', { clientRequestId: dedicated.request.clientRequestId }, author.token)).status, 'deleted');
			await rejected(api(site, 'notes/create', dedicated.request, author.token));
			await eventually('deleted original disappears from remaining channel', async () => !await channelContains(site, reader, site.origin, second.id, dedicated.canonicalUri));
		});
	}

	await check('six local channels have no fixed five-channel product limit', async () => {
		const channels = [...localChannels.get(g)];
		while (channels.length < 6) channels.push(await createChannel(g, authorG, `many-${channels.length + 1}`));
		const posted = await createNote(g, authorG, 'six-channels', { includeDefault: false, channelIds: channels.map(channel => channel.id) });
		assert.equal(posted.note.channelPlacements.filter(placement => placement.state === 'active').length, 6);
	});

	const context = { g, r, e, users, localChannels, run, fixtures, remember, check, api, eventually, createNote, channelContains, uri };
	await testGuestOperations(context);
	await testExternalFederation(context);
	await testRetirement(context);
	savePrivateJson(resultPath, { run, results, completed: true });
	console.log(`Multi Note acceptance passed: ${results.length} checks. Fixtures and results are stored in ignored .config files.`);
} catch (error) {
	savePrivateJson(resultPath, { run, results, completed: false, failed: { code: error.code ?? null, name: error.name } });
	throw error;
}
