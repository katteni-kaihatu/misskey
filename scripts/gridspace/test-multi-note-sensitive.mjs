/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

process.env.GRIDSPACE_LAB_PROFILE = 'multi-note';
const { api, eventually, loadSite, savePrivateJson } = await import('./lab.mjs');
const sites = JSON.parse(readFileSync('.config/multi-note-repositories.json', 'utf8')).slice(0, 2).map(loadSite);
const run = randomBytes(5).toString('hex');
const fixtures = { run, users: {}, channels: {}, notes: {} };
const results = [];
const save = () => savePrivateJson('.config/multi-note-sensitive-fixtures.json', fixtures);
const record = completed => savePrivateJson('.config/multi-note-sensitive-results.json', { run, completed, results });
async function check(name, test) {
	await test();
	results.push({ name, status: 'pass' });
	record(false);
	console.log(`PASS ${name}`);
}
const uri = (site, note) => note.uri ?? `${site.origin}/notes/${note.id}`;
async function page(viewer, host, channel, canonicalUri, pinnedOnly = false) {
	const response = await api(viewer, 'gridspace/timeline', { kind: 'channel', channelOrigin: host.origin, channelId: channel.id, pinnedOnly, limit: 50 }, viewer.reader.token);
	return response.items.filter(item => item.key === canonicalUri);
}
async function present(viewer, host, channel, post, cw, pinnedOnly = false, representation) {
	await eventually(`${viewer.role} reads ${host.role} ${channel.name}`, async () => {
		const rows = await page(viewer, host, channel, post.canonicalUri, pinnedOnly);
		return rows.length === 1 && rows[0].payload.cw === cw && rows[0].payload.text === post.note.text && (!representation || rows[0].representation === representation);
	}, 60000);
}
async function post(site, label, params) {
	const request = { text: `Sensitive channel acceptance ${label} ${run}`, visibility: 'public', clientRequestId: randomUUID(), ...params };
	const { createdNote } = await api(site, 'notes/create', request, site.author.token);
	assert.ok(createdNote?.id);
	const result = { note: createdNote, request, canonicalUri: uri(site, createdNote) };
	fixtures.notes[`${site.role}_${label}`] = result;
	save();
	return result;
}
async function rejectedPlacement(site, params) {
	const clientRequestId = randomUUID();
	await assert.rejects(api(site, 'notes/create', { text: `Rejected sensitivity fixture ${run}`, visibility: 'public', clientRequestId, ...params }, site.author.token), error => error.code === 'INVALID_NOTE_PLACEMENT');
	assert.equal((await api(site, 'notes/create-status', { clientRequestId }, site.author.token)).status, 'missing');
}

try {
	for (const site of sites) {
		const accounts = JSON.parse(readFileSync(site.accountsPath, 'utf8')).accounts;
		site.admin = accounts.admin;
		for (const label of ['author', 'reader']) {
			const password = randomBytes(24).toString('base64url');
			const account = { ...await api(site, 'admin/accounts/create', { username: `mn_s_${label[0]}_${run}`, password }, site.admin.token), password };
			site[label] = account;
			fixtures.users[`${site.role}_${label}`] = account;
			save();
		}
		const role = await api(site, 'admin/roles/create', {
			name: `Sensitive channel acceptance ${run}`, description: '', color: null, iconUrl: null, target: 'manual', condFormula: {},
			isPublic: false, isModerator: false, isAdministrator: false, asBadge: false, canEditMembersByModerator: false, displayOrder: 0,
			policies: { rateLimitFactor: { useDefault: false, priority: 2, value: 0 } },
		}, site.admin.token);
		for (const user of [site.author, site.reader]) await api(site, 'admin/roles/assign', { roleId: role.id, userId: user.id }, site.admin.token);
		for (const sensitive of [false, true]) {
			const label = sensitive ? 'sensitive' : 'ordinary';
			const channel = await api(site, 'channels/create', { name: `CW ${label} ${run}`, description: 'Disposable public channel CW test', isSensitive: sensitive, allowRenoteToExternal: true }, site.author.token);
			site[label] = channel;
			fixtures.channels[`${site.role}_${label}`] = { ...channel, origin: site.origin };
			save();
		}
	}

	for (const source of sites) {
		const peer = sites.find(site => site !== source);
		const cw = `Author supplied CW ${source.role} ${run}`;
		const both = site => [site.ordinary, site.sensitive];
		let dedicated;
		let localMixed;

		await check(`${source.role}: local and peer sensitive destinations remain discoverable`, async () => {
			const local = await api(source, 'channels/search', { query: run, limit: 20 }, source.reader.token);
			assert.ok(local.some(channel => channel.id === source.sensitive.id && channel.isSensitive));
			const remote = await api(source, 'gridspace/multi-note/channels', { list: 'search', query: run, limit: 20 }, source.reader.token);
			assert.equal(remote.enabled, true);
			assert.ok(remote.channels.some(channel => channel.id === peer.sensitive.id && channel.isSensitive));
		});

		await check(`${source.role}: default plus ordinary and sensitive channels share one original CW`, async () => {
			const mixed = await post(source, 'local-mixed', { includeDefault: true, channelIds: both(source).map(channel => channel.id), cw });
			localMixed = mixed;
			assert.equal(mixed.note.cw, cw);
			assert.equal(mixed.note.channelPlacements.filter(p => p.state === 'active').length, 2);
			for (const channel of both(source)) {
				await present(source, source, channel, mixed, cw);
				const legacy = await api(source, 'channels/timeline', { channelId: channel.id, limit: 100 }, source.reader.token);
				assert.equal(legacy.filter(note => note.id === mixed.note.id && note.cw === cw).length, 1);
			}
			assert.equal((await api(source, 'notes/local-timeline', { limit: 100 }, source.reader.token)).filter(note => note.id === mixed.note.id).length, 1);
		});

		await check(`${source.role} to ${peer.role}: all four placements, both viewers and pins preserve author CW`, async () => {
			dedicated = await post(source, 'four-placements', {
				includeDefault: false, cw, poll: { choices: ['one', 'two'], multiple: false },
				channelTargets: sites.flatMap(site => both(site).map(channel => ({ origin: site.origin, channelId: channel.id }))),
			});
			assert.equal(dedicated.note.localOnly, true);
			for (const host of sites) for (const channel of both(host)) {
				for (const viewer of sites) await present(viewer, host, channel, dedicated, cw);
				await api(host, 'channels/update', { channelId: channel.id, pinnedNoteUris: [dedicated.canonicalUri] }, host.author.token);
				for (const viewer of sites) await present(viewer, host, channel, dedicated, cw, true);
			}
			const detail = await api(peer, 'gridspace/private-notes', { mode: 'show', conversationUri: dedicated.canonicalUri, noteId: dedicated.note.id }, peer.reader.token);
			assert.equal(detail.notes[0].cw, cw);
			assert.equal(detail.notes[0].text, dedicated.note.text);
		});

		await check(`${source.role} to ${peer.role}: sensitive-channel conversation accepts guest reply, reaction and vote`, async () => {
			const target = { noteId: dedicated.note.id, conversationUri: dedicated.canonicalUri, expectedActorUri: `${peer.origin}/users/${peer.reader.id}` };
			const reply = await api(peer, 'gridspace/private-reply', { ...target, action: 'prepare' }, peer.reader.token);
			assert.equal(reply.canReply, true);
			const request = { ...target, action: 'send', requestId: randomUUID(), text: `Sensitive-channel guest reply ${run}` };
			const sent = await api(peer, 'gridspace/private-reply', request, peer.reader.token);
			assert.ok(sent.createdNoteId);
			assert.equal((await api(peer, 'gridspace/private-reply', request, peer.reader.token)).createdNoteId, sent.createdNoteId);
			const reaction = await api(peer, 'gridspace/private-action', { ...target, action: 'add-reaction', reaction: '👍' }, peer.reader.token);
			assert.equal(reaction.note.reactions['👍'], 1);
			for (let i = 0; i < 2; i++) {
				const voted = await api(peer, 'gridspace/private-action', { ...target, action: 'vote', choice: 0 }, peer.reader.token);
				assert.equal(voted.note.poll.choices[0].votes, 1);
				assert.equal(voted.note.poll.choices[0].isVoted, true);
				assert.equal(voted.note.cw, cw);
			}
		});

		await check(`${source.role} to ${peer.role}: normal shared mirrors retain both sensitive and ordinary placement chips`, async () => {
			const mixed = await post(source, 'peer-normal-mirror', { includeDefault: true, gridspaceShared: true, cw,
				channelTargets: both(peer).map(channel => ({ origin: peer.origin, channelId: channel.id })),
			});
			for (const channel of both(peer)) {
				await present(peer, peer, channel, mixed, cw, false, 'normal');
				await eventually('legacy API sees the actual shared mirror', async () => (await api(peer, 'channels/timeline', { channelId: channel.id, limit: 100 }, peer.reader.token)).some(note => note.uri === mixed.canonicalUri && note.cw === cw), 60000);
			}
		});

		await check(`${source.role} to ${peer.role}: CW is neither required nor automatically added`, async () => {
			const bare = await post(source, 'without-cw', { includeDefault: false, channelTargets: [{ origin: peer.origin, channelId: peer.sensitive.id }] });
			assert.equal(bare.note.cw, null);
			await present(peer, peer, peer.sensitive, bare, null);
		});

		await check(`${source.role}: existing profile discovery still hides another author's sensitive-only channel note`, async () => {
			const only = await post(source, 'profile-sensitive-only', { includeDefault: false, channelIds: [source.sensitive.id], cw });
			assert.ok((await api(source, 'users/notes', { userId: source.author.id, withChannelNotes: true, limit: 100 }, source.author.token)).some(note => note.id === only.note.id));
			assert.equal((await api(source, 'users/notes', { userId: source.author.id, withChannelNotes: true, limit: 100 }, source.reader.token)).some(note => note.id === only.note.id), false);
			await present(source, source, source.sensitive, only, cw);
			for (const viewer of [source.author, source.reader]) for (const withChannelNotes of [false, true]) {
				const unified = await api(source, 'gridspace/timeline', { kind: 'profile', userId: source.author.id, withChannelNotes, limit: 50 }, viewer.token);
				assert.equal(unified.items.some(item => item.key === only.canonicalUri), withChannelNotes && viewer.id === source.author.id);
				assert.equal(unified.items.some(item => item.key === dedicated.canonicalUri), withChannelNotes);
				assert.ok(unified.items.some(item => item.key === localMixed.canonicalUri));
			}
		});

		await check(`${source.role}: blocking a peer channel owner filters chips without changing the public original CW`, async () => {
			const owner = await api(source, 'users/show', { username: peer.author.username, host: new URL(peer.origin).host }, source.reader.token);
			await api(source, 'blocking/create', { userId: owner.id }, source.reader.token);
			try {
				const shown = await api(source, 'notes/show', { noteId: dedicated.note.id }, source.reader.token);
				assert.equal(shown.cw, cw);
				assert.equal(shown.text, dedicated.note.text);
				assert.ok(shown.channelPlacements.some(p => p.origin === source.origin));
				assert.equal(shown.channelPlacements.some(p => p.origin === peer.origin && p.state === 'active'), false);
			} finally { await api(source, 'blocking/delete', { userId: owner.id }, source.reader.token); }
		});

		await check(`${source.role}: archived sensitive destinations reject the whole request without a receipt`, async () => {
			await api(source, 'channels/update', { channelId: source.sensitive.id, isArchived: true }, source.author.token);
			try { await rejectedPlacement(source, { includeDefault: false, channelIds: both(source).map(channel => channel.id), cw }); }
			finally { await api(source, 'channels/update', { channelId: source.sensitive.id, isArchived: false }, source.author.token); }
		});

		await check(`${source.role}: original deletion clears all sensitive/ordinary placements and pins`, async () => {
			await api(source, 'notes/delete', { noteId: dedicated.note.id }, source.author.token);
			for (const host of sites) for (const channel of both(host)) {
				for (const viewer of sites) await eventually('deleted original and pin are absent', async () => (await page(viewer, host, channel, dedicated.canonicalUri)).length === 0 && (await page(viewer, host, channel, dedicated.canonicalUri, true)).length === 0, 60000);
			}
			assert.equal((await api(source, 'notes/create-status', { clientRequestId: dedicated.request.clientRequestId }, source.author.token)).status, 'deleted');
		});
	}
	record(true);
	console.log(`Sensitive channel acceptance passed: ${results.length} checks.`);
} catch (error) {
	record(false);
	throw error;
}
