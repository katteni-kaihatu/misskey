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
const run = randomBytes(4).toString('hex');
const fixtures = { run, users: {}, channels: {}, notes: {} };
const results = [];
const save = () => savePrivateJson('.config/multi-note-mirror-placements-fixtures.json', fixtures);
const record = completed => savePrivateJson('.config/multi-note-mirror-placements-results.json', { run, completed, results });
async function check(name, test) {
	await test();
	results.push({ name, status: 'pass' });
	record(false);
	console.log(`PASS ${name}`);
}
const canonical = (site, note) => note.uri ?? `${site.origin}/notes/${note.id}`;
const active = note => (note.channelPlacements ?? []).filter(placement => placement.state === 'active');
function assertPlacements(note, expected) {
	assert.equal(note.multiNoteKind, 'root');
	assert.equal(note.includeDefault, true);
	assert.deepEqual(active(note).map(p => `${p.origin}/${p.channelId}`).sort(), expected.map(p => `${p.origin}/${p.id}`).sort());
}
async function original(site, label, params = {}) {
	const request = { text: `Mirror placements ${label} ${run}`, cw: `Original CW ${run}`, visibility: 'public', gridspaceShared: true,
		includeDefault: true, clientRequestId: randomUUID(), channelIds: site.channels.map(channel => channel.id), ...params };
	const { createdNote } = await api(site, 'notes/create', request, site.author.token);
	const result = { note: createdNote, canonicalUri: canonical(site, createdNote), request };
	fixtures.notes[`${site.role}_${label}`] = result;
	save();
	return result;
}
async function mirror(home, source, post) {
	const actor = await api(home, 'users/show', { username: source.author.username, host: new URL(source.origin).host }, home.reader.token);
	let found;
	await eventually('ordinary shared mirror', async () => {
		found = (await api(home, 'users/notes', { userId: actor.id, limit: 100 }, home.reader.token)).find(note => note.uri === post.canonicalUri);
		return found?.gridspaceShared === true;
	}, 60000);
	return found;
}
async function homeStream(site) {
	const socket = new WebSocket(`${site.origin.replace('https:', 'wss:')}/streaming?i=${encodeURIComponent(site.reader.token)}`);
	const messages = [];
	let failed = false;
	socket.addEventListener('error', () => { failed = true; });
	socket.addEventListener('message', event => { messages.push(JSON.parse(event.data)); });
	try {
		await eventually('authenticated home stream open', () => {
			assert.equal(failed, false, 'WebSocket connection failed');
			return socket.readyState === WebSocket.OPEN;
		});
		socket.send(JSON.stringify({ type: 'connect', body: { channel: 'homeTimeline', id: run, pong: true } }));
		await eventually('home stream subscribed', () => messages.some(message => message.type === 'connected' && message.body.id === run));
		return { messages, close: () => socket.close() };
	} catch (error) { socket.close(); throw error; }
}

try {
	for (const site of sites) {
		site.admin = JSON.parse(readFileSync(site.accountsPath, 'utf8')).accounts.admin;
		for (const label of ['author', 'owner', 'reader']) {
			const password = randomBytes(24).toString('base64url');
			site[label] = { ...await api(site, 'admin/accounts/create', { username: `mn_mp_${label[0]}_${run}`, password }, site.admin.token), password };
			fixtures.users[`${site.role}_${label}`] = site[label];
			save();
		}
		const role = await api(site, 'admin/roles/create', {
			name: `Mirror placement acceptance ${run}`, description: '', color: null, iconUrl: null, target: 'manual', condFormula: {},
			isPublic: false, isModerator: false, isAdministrator: false, asBadge: false, canEditMembersByModerator: false, displayOrder: 0,
			policies: { rateLimitFactor: { useDefault: false, priority: 2, value: 0 } },
		}, site.admin.token);
		for (const user of [site.author, site.owner, site.reader]) await api(site, 'admin/roles/assign', { roleId: role.id, userId: user.id }, site.admin.token);
		site.channels = [];
		for (const sensitive of [false, true]) {
			const channel = await api(site, 'channels/create', { name: `Origin ${sensitive ? 'sensitive' : 'ordinary'} ${run}`, isSensitive: sensitive, allowRenoteToExternal: true }, site.owner.token);
			site.channels.push({ ...channel, origin: site.origin });
		}
		fixtures.channels[site.role] = site.channels;
		save();
	}
	for (const source of sites) {
		const home = sites.find(site => site !== source);
		const actor = await api(home, 'users/show', { username: source.author.username, host: new URL(source.origin).host }, home.reader.token);
		await api(home, 'following/create', { userId: actor.id }, home.reader.token);
		await eventually('remote follow accepted before opening home stream', async () =>
			(await api(home, 'users/show', { userId: actor.id }, home.reader.token)).isFollowing === true, 60000);
		let post, copy;
		const shown = () => api(home, 'notes/show', { noteId: copy.id }, home.reader.token);
		await check(`${source.role} to ${home.role}: ordinary mirror exposes source-only placements in show, home and global timelines`, async () => {
			const stream = await homeStream(home);
			try {
				post = await original(source, 'source-only');
				copy = await mirror(home, source, post);
				assertPlacements(await shown(), source.channels);
				for (const endpoint of ['notes/timeline', 'notes/global-timeline']) {
					await eventually(endpoint + ' ordinary timeline', async () => {
						const item = (await api(home, endpoint, { limit: 100 }, home.reader.token)).find(note => note.uri === post.canonicalUri);
						if (!item) return false;
						assertPlacements(item, source.channels);
						assert.equal(item.cw, post.note.cw);
						return true;
					}, 60000);
				}
				try { await eventually('live ordinary home note contains source chips', () => stream.messages.some(message => {
					const note = message.type === 'channel' && message.body?.type === 'note' ? message.body.body : null;
					return note?.uri === post.canonicalUri && note.multiNoteKind === 'root' && active(note).length === 2;
				}), 60000); } catch (error) {
					console.log('Home stream diagnostic', JSON.stringify(stream.messages.map(message => {
						const note = message.type === 'channel' && message.body?.type === 'note' ? message.body.body : null;
						return { type: message.type, channelType: message.body?.type, id: note?.id, uri: note?.uri, gridspaceShared: note?.gridspaceShared, multiNoteKind: note?.multiNoteKind, placements: active(note ?? {}).length };
					})));
					throw error;
				}
			} finally { stream.close(); }
		});
		await check(`${source.role} to ${home.role}: source chips and destination chips form one deduplicated set outside channel context`, async () => {
			const mixed = await original(source, 'both-origins', { channelTargets: [{ origin: home.origin, channelId: home.channels[0].id }] });
			const other = await mirror(home, source, mixed);
			await eventually('destination active metadata', async () => {
				const note = await api(home, 'notes/show', { noteId: other.id }, home.reader.token);
				if (active(note).length !== 3) return false;
				assertPlacements(note, [...source.channels, home.channels[0]]);
				return true;
			}, 60000);
		});
		await check(`${source.role} to ${home.role}: ordinary posts without placements retain ordinary classification`, async () => {
			const { createdNote } = await api(source, 'notes/create', { text: `Ordinary control ${run}`, visibility: 'public', gridspaceShared: true }, source.author.token);
			const control = await mirror(home, source, { canonicalUri: canonical(source, createdNote) });
			assert.notEqual(control.multiNoteKind, 'root');
			assert.equal(active(control).length, 0);
		});
		await check(`${source.role} to ${home.role}: nested Renote also retains source chips`, async () => {
			const { createdNote } = await api(home, 'notes/create', { renoteId: copy.id, visibility: 'public' }, home.reader.token);
			const nested = (await api(home, 'notes/show', { noteId: createdNote.id }, home.reader.token)).renote;
			assert.equal(nested.uri, post.canonicalUri);
			assertPlacements(nested, source.channels);
		});
		await check(`${source.role} to ${home.role}: renamed and removed source placements update existing mirrors without reposting`, async () => {
			const renamed = `Renamed source channel ${run}`;
			await api(source, 'channels/update', { channelId: source.channels[1].id, name: renamed, color: '#cc4499' }, source.owner.token);
			await api(source, 'gridspace/multi-note/remove', { canonicalUri: post.canonicalUri, channelOrigin: source.origin, channelId: source.channels[0].id }, source.author.token);
			const current = await shown();
			assertPlacements(current, [source.channels[1]]);
			assert.equal(active(current)[0].name, renamed);
			assert.equal(active(current)[0].color, '#cc4499');
			assert.equal(current.id, copy.id);
			assert.equal(current.text, post.note.text);
		});
		await check(`${source.role} to ${home.role}: home viewer block and mute hide source-owner chips without hiding public body`, async () => {
			const owner = await api(home, 'users/show', { username: source.owner.username, host: new URL(source.origin).host }, home.reader.token);
			for (const kind of ['blocking', 'mute']) {
				const create = kind === 'mute' ? 'mute/create' : 'blocking/create';
				const remove = kind === 'mute' ? 'mute/delete' : 'blocking/delete';
				await api(home, create, { userId: owner.id }, home.reader.token);
				try {
					const current = await shown();
					assert.equal(active(current).length, 0);
					assert.equal(current.text, post.note.text);
					assert.equal(current.cw, post.note.cw);
				} finally { await api(home, remove, { userId: owner.id }, home.reader.token); }
			}
			assertPlacements(await shown(), [source.channels[1]]);
		});
		await check(`${source.role} to ${home.role}: a block recorded at the channel origin is applied to mirror metadata`, async () => {
			const viewer = await api(source, 'users/show', { username: home.reader.username, host: new URL(home.origin).host }, source.owner.token);
			await api(source, 'blocking/create', { userId: viewer.id }, source.owner.token);
			try {
				assert.equal(active(await shown()).length, 0);
			} finally { await api(source, 'blocking/delete', { userId: viewer.id }, source.owner.token); }
			assertPlacements(await shown(), [source.channels[1]]);
		});
		await check(`${source.role} to ${home.role}: a root with no remaining source placements stays a default original`, async () => {
			await api(source, 'gridspace/multi-note/remove', { canonicalUri: post.canonicalUri, channelOrigin: source.origin, channelId: source.channels[1].id }, source.author.token);
			const current = await shown();
			assertPlacements(current, []);
			assert.equal(current.id, copy.id);
			assert.equal(current.text, post.note.text);
		});
	}
	record(true);
	console.log(`Mirror placement acceptance passed: ${results.length} checks.`);
} catch (error) {
	record(false);
	throw error;
}
