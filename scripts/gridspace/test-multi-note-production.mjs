/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { createRequire } from 'node:module';

process.env.GRIDSPACE_LAB_PROFILE = 'multi-note';
const { api, eventually, loadSite, savePrivateJson } = await import('./lab.mjs');
const root = fileURLToPath(new URL('../../', import.meta.url));
const dir = join(root, '.config');
const [g, r, e] = JSON.parse(readFileSync(join(dir, 'multi-note-repositories.json'), 'utf8')).map(loadSite);
const run = randomBytes(5).toString('hex');
const report = { run, completed: false, checks: [] };
const accounts = {};
const channels = new Map();
const unique = label => `mn_${label}_${run}`;
const reportPath = join(dir, `multi-note-production-${run}.json`);
const credentialsPath = join(dir, `multi-note-production-${run}-accounts.json`);
const publicAudience = 'https://www.w3.org/ns/activitystreams#Public';
const canonical = (site, note) => note.uri ?? `${site.origin}/notes/${note.id}`;
const call = (site, endpoint, data) => api(site, endpoint, data, accounts[site.role].token);

async function check(name, test) {
	try {
		await test();
		report.checks.push({ name, status: 'pass' });
		console.log(`PASS ${name}`);
	} catch (error) {
		report.checks.push({ name, status: 'fail', code: error.code ?? error.name });
		throw error;
	} finally {
		savePrivateJson(reportPath, report);
	}
}

async function setup(site) {
	// Never submit administrator credentials until the public origin matches the dedicated lab.
	assert.equal((await api(site, 'meta', { detail: false })).uri, site.origin);
	const admin = JSON.parse(readFileSync(site.accountsPath, 'utf8')).accounts.admin;
	const meta = await api(site, 'admin/meta', {}, admin.token);
	assert.equal(meta.federation, 'specified');
	assert.deepEqual(meta.federationHosts.toSorted(), [g, r, e].filter(other => other !== site).map(other => new URL(other.origin).host).toSorted());
	const username = unique(site.role.toLowerCase());
	const password = randomBytes(24).toString('base64url');
	accounts[site.role] = { username, password };
	savePrivateJson(credentialsPath, accounts);
	Object.assign(accounts[site.role], await api(site, 'admin/accounts/create', { username, password }, admin.token));
	savePrivateJson(credentialsPath, accounts);
	const role = await api(site, 'admin/roles/create', {
		name: unique('delivery'), description: 'Dedicated integration test users', target: 'manual', condFormula: {},
		isPublic: false, isModerator: false, isAdministrator: false, asBadge: false, canEditMembersByModerator: false,
		color: null, iconUrl: null, displayOrder: 0, policies: { rateLimitFactor: { useDefault: false, priority: 2, value: 0 } },
	}, admin.token);
	await api(site, 'admin/roles/assign', { roleId: role.id, userId: accounts[site.role].id }, admin.token);
}

async function delivery(site) {
	const acct = accounts[site.role];
	const actor = await call(e, 'users/show', { username: acct.username, host: new URL(site.origin).host });
	await call(e, 'following/create', { userId: actor.id });
	await eventually('E follow accepted', async () => (await call(e, 'users/show', { userId: actor.id })).isFollowing, 60000);
	await eventually('source registered E follower', async () => (await call(site, 'users/followers', { userId: acct.id, limit: 20 }))
		.some(row => row.follower.host === new URL(e.origin).host && row.follower.username === accounts.E.username), 60000);
	const channelId = channels.get(site).id;
	const notes = new Map();
	const modes = [
		{ name: 'ordinary', noRelay: false, localOnly: false },
		{ name: 'ordinary_no_relay', noRelay: true, localOnly: false },
		{ name: 'local', noRelay: false, localOnly: true },
		{ name: 'multi_no_relay', noRelay: true, localOnly: false, placed: true },
		{ name: 'multi_public', noRelay: false, localOnly: false, placed: true },
		{ name: 'multi_local', noRelay: false, localOnly: true, placed: true },
	];
	const { Client } = createRequire(join(site.repo, 'packages/backend/package.json'))('pg');
	const { host, port, user, pass, db } = site.config.db;
	const sql = new Client({ host, port, user, password: pass, database: db });
	await sql.connect();
	try {
		for (const mode of modes) {
			const params = { text: unique(mode.name), visibility: 'public', noRelay: mode.noRelay, localOnly: mode.localOnly };
			if (mode.placed) Object.assign(params, { includeDefault: true, channelIds: [channelId], clientRequestId: randomUUID() });
			const note = (await call(site, 'notes/create', params)).createdNote;
			notes.set(mode.name, note);
			await check(`${site.role} ${mode.name} persists delivery policy`, async () => {
				assert.equal(note.visibility, 'public');
				assert.equal(note.noRelay, mode.noRelay);
				assert.equal(note.localOnly, mode.localOnly);
				const result = await sql.query('SELECT "noRelay", "federateAsHome", "localOnly" FROM note WHERE id = $1', [note.id]);
				assert.deepEqual(result.rows, [{ noRelay: mode.noRelay, federateAsHome: mode.noRelay, localOnly: mode.localOnly }]);
				if (mode.placed) {
					assert.equal((await call(site, 'notes/create', params)).createdNote.id, note.id);
					assert.equal((await call(site, 'notes/create-status', { clientRequestId: params.clientRequestId })).status, 'created');
				}
			});
			await check(`${site.role} ${mode.name} ActivityPub addressing`, async () => {
				const response = await fetch(canonical(site, note), { headers: { accept: 'application/activity+json' }, redirect: 'error', signal: AbortSignal.timeout(15000) });
				if (mode.localOnly) {
					assert.equal(response.status, 404);
					await response.body?.cancel();
					return;
				}
				assert.equal(response.status, 200);
				const doc = await response.json();
				assert.equal(doc.id, canonical(site, note));
				const followers = `${site.origin}/users/${acct.id}/followers`;
				assert.deepEqual(doc.to, [mode.noRelay ? followers : publicAudience]);
				assert.ok(doc.cc.includes(mode.noRelay ? publicAudience : followers));
			});
		}
	} finally {
		await sql.end();
	}
	// E follows the author. Relay queue inclusion/exclusion and dispatch replay are exercised
	// separately in the isolated backend E2E test with two accepted relay inboxes.
	await check(`${site.role} real follower receives federated notes once, excluding local notes`, async () => {
		const ids = modes.filter(mode => !mode.localOnly).map(mode => canonical(site, notes.get(mode.name)));
		const timeline = () => call(e, 'notes/timeline', { limit: 100 });
		await eventually('all federated notes reach E', async () => {
			const rows = await timeline();
			return ids.every(id => rows.some(n => n.uri === id));
		}, 90000);
		const imported = await call(e, 'users/notes', { userId: actor.id, limit: 100 });
		for (const mode of modes) {
			const rows = imported.filter(note => note.uri === canonical(site, notes.get(mode.name)));
			assert.equal(rows.length, mode.localOnly ? 0 : 1);
			if (mode.noRelay) assert.equal(rows[0].visibility, 'home');
		}
	});
	return notes.get('ordinary');
}

async function quotesAndClips(site, peer, ordinary) {
	const newNote = async params => (await call(site, 'notes/create', params)).createdNote;
	const legacy = await newNote({ channelId: channels.get(site).id, text: unique('legacy') });
	for (const [label, note] of [['ordinary', ordinary], ['legacy', legacy]]) {
		await check(`${site.role} ${label} renote and quote`, async () => {
			const target = { renoteId: note.id, ...(note.channelId ? { channelId: note.channelId } : {}) };
			const rn = await newNote(target);
			const quote = await newNote({ ...target, text: unique('quote') });
			for (const result of [rn, quote]) assert.equal((await call(site, 'notes/show', { noteId: result.id })).renoteId, note.id);
			assert.equal(quote.text, unique('quote'));
		});
	}
	await check(`${site.role} public clip appears on a shared ordinary note from both origins`, async () => {
		const channelId = channels.get(peer).id;
		const note = await newNote({ text: unique('clips'), visibility: 'public', gridspaceShared: true, clientRequestId: randomUUID(),
			includeDefault: true, channelTargets: [{ origin: peer.origin, channelId }] });
		const clip = await call(site, 'clips/create', { name: unique('public_clip'), isPublic: true });
		await call(site, 'clips/add-note', { clipId: clip.id, noteId: note.id });
		assert.ok((await call(site, 'notes/clips', { noteId: note.id })).some(c => c.id === clip.id));
		await eventually('peer can list origin clip', async () => {
			const page = await call(peer, 'gridspace/timeline', { kind: 'channel', channelOrigin: peer.origin, channelId, limit: 20 });
			const mirror = page.items.find(item => item.key === canonical(site, note) && item.representation === 'normal');
			if (!mirror) return false;
			const result = await call(peer, 'gridspace/note-clips', { noteId: mirror.payload.id });
			return !result.partial && result.clips.some(c => c.name === clip.name);
		}, 60000);
	});
	const target = { origin: peer.origin, channelId: channels.get(peer).id };
	const root = await newNote({ text: unique('guest'), visibility: 'public', includeDefault: false, clientRequestId: randomUUID(), channelTargets: [target] });
	const conversationUri = canonical(site, root);
	await eventually('guest sees dedicated placement', async () => {
		const page = await call(peer, 'gridspace/timeline', { kind: 'channel', channelOrigin: target.origin, channelId: target.channelId, limit: 20 });
		return page.items.some(item => item.key === conversationUri);
	}, 60000);
	await check(`${peer.role} signed conversation can list the public clip of a ${site.role} root`, async () => {
		const clip = await call(site, 'clips/create', { name: unique('guest_clip'), isPublic: true });
		await call(site, 'clips/add-note', { clipId: clip.id, noteId: root.id });
		const result = await call(peer, 'gridspace/note-clips', { source: 'peer', conversationUri, noteId: root.id });
		assert.equal(result.partial, false);
		assert.ok(result.clips.some(c => c.name === clip.name));
	});
	const favorite = await call(peer, 'channels/create', { name: unique('favorite') });
	await call(peer, 'channels/favorite', { channelId: favorite.id });
	const other = await call(site, 'channels/create', { name: unique('remote_favorite') });
	assert.equal((await call(peer, 'gridspace/multi-note/channel-update', { channelId: other.id, action: 'favorite' })).isFavorited, true);
	const reference = new URL(conversationUri);
	reference.searchParams.set('gridspaceChannelOrigin', target.origin);
	reference.searchParams.set('gridspaceChannelId', target.channelId);
	const readLink = (viewer) => call(viewer, 'gridspace/note-link', { url: reference.href });
	async function verifyOriginal(viewer) {
		const result = await readLink(viewer);
		const original = viewer === site ? result.localNote : result.note;
		assert.equal(original?.id, root.id);
		assert.equal(original.text, root.text);
		if (viewer === peer) assert.equal(original.uri, conversationUri);
	}
	await check(`${site.role} placement link resolves on the origin and the guest server`, async () => {
		for (const viewer of [site, peer]) await verifyOriginal(viewer);
	});
	const actions = [
		{ label: 'outside renote' },
		{ label: 'outside quote', text: unique('outside_quote') },
		{ label: 'in-channel renote', channel: target.channelId },
		{ label: 'in-channel quote', channel: target.channelId, text: unique('placed_quote') },
		{ label: 'other favorite channel renote', channel: favorite.id },
		{ label: 'favorite on the opposite server renote', channel: other.id, remote: true },
	];
	for (const action of actions) {
		await check(`${peer.role} ${action.label} of a ${site.role} placement`, async () => {
			const params = { gridspaceQuote: reference.href, localOnly: true, visibility: 'public' };
			if (action.text) params.text = action.text;
			const destination = action.remote ? site : peer;
			if (action.channel) Object.assign(params, { includeDefault: false, clientRequestId: randomUUID(), channelTargets: [{ origin: destination.origin, channelId: action.channel }] });
			const posted = (await call(peer, 'notes/create', params)).createdNote;
			const note = await call(peer, 'notes/show', { noteId: posted.id });
			assert.equal(note.gridspaceQuote, reference.href);
			assert.equal(note.localOnly, true);
			assert.equal(note.text ?? null, action.text ?? null);
			if (action.channel) {
				assert.equal(note.includeDefault, false);
				assert.equal((await call(peer, 'notes/create', params)).createdNote.id, note.id);
				await eventually('origin reports the active target', async () => {
					const packed = await call(peer, 'notes/show', { noteId: note.id });
					return packed.channelPlacements.some(p => p.state === 'active' && p.channelId === action.channel && p.origin === destination.origin);
				}, 60000);
				if (action.remote) {
					await eventually('target server displays exactly one replayed placement', async () => {
						const page = await call(site, 'gridspace/timeline', { kind: 'channel', channelOrigin: site.origin, channelId: other.id, limit: 20 });
						const items = page.items.filter(item => item.key === canonical(peer, note));
						return items.length === 1 && items[0].payload?.gridspaceQuote === reference.href;
					}, 60000);
				}
			}
		});
	}
	await check(`${site.role} removed route preserves reading the original but stops new quotes`, async () => {
		await call(peer, 'gridspace/multi-note/remove', { canonicalUri: conversationUri, channelOrigin: target.origin, channelId: target.channelId });
		await eventually('origin records route removal', async () => {
			const note = await call(site, 'notes/show', { noteId: root.id });
			return !note.channelPlacements.some(p => p.channelId === target.channelId && p.origin === target.origin && p.state === 'active');
		}, 60000);
		for (const viewer of [site, peer]) await verifyOriginal(viewer);
		await assert.rejects(call(peer, 'notes/create', { text: unique('retired_quote'), localOnly: true, gridspaceQuote: reference.href }), err => err.code === 'CANNOT_RENOTE_OUTSIDE_OF_CHANNEL');
	});
	await check(`${site.role} viewer block denies the existing guest link while the author can still read it`, async () => {
		const guest = await call(site, 'users/show', { username: accounts[peer.role].username, host: new URL(peer.origin).host });
		const blocking = { userId: guest.id };
		await call(site, 'blocking/create', blocking);
		try {
			await verifyOriginal(site);
			await assert.rejects(readLink(peer), err => err.code === 'GRIDSPACE_NOTE_LINK_UNAVAILABLE');
		} finally {
			await call(site, 'blocking/delete', blocking);
		}
	});
	await check(`${site.role} deleted fixture no longer resolves from either viewer origin`, async () => {
		await call(site, 'notes/delete', { noteId: root.id });
		for (const viewer of [site, peer]) {
			await eventually('reference no longer readable', async () => {
				try {
					await readLink(viewer);
					return false;
				} catch (error) {
					if (error.code === 'GRIDSPACE_NOTE_LINK_UNAVAILABLE') return true;
					throw error;
				}
			}, 60000);
		}
	});
}

async function emojiSync(site, peer) {
	const admin = JSON.parse(readFileSync(site.accountsPath, 'utf8')).accounts.admin;
	const name = unique(`emoji_${site.role.toLowerCase()}`);
	const form = new FormData();
	form.set('i', admin.token);
	const image = readFileSync(join(root, 'packages/backend/test/resources', site === g ? '192.png' : 'with-alpha.png'));
	form.set('file', new Blob([image], { type: 'image/png' }), name + '.png');
	const upload = await fetch(site.origin + '/api/drive/files/create', { method: 'POST', body: form, redirect: 'error', signal: AbortSignal.timeout(20000) });
	assert.equal(upload.status, 200);
	const file = await upload.json();
	await api(site, 'admin/emoji/add', { fileId: file.id, name, aliases: [name + '_alias'] }, admin.token);
	await check(`${site.role} custom emoji becomes a local emoji at ${peer.role}`, async () => {
		await eventually('copied local emoji and alias', async () => {
			const { emojis } = await call(peer, 'emojis', {});
			if (!emojis.some(emoji => emoji.name === name)) {
				await new Promise(resolve => setTimeout(resolve, 2500));
				return false;
			}
			const emoji = await call(peer, 'emoji', { name });
			return emoji.name === name && emoji.aliases?.includes(name + '_alias');
		}, 150000);
	});
}

try {
	for (const site of [g, r, e]) await setup(site);
	await check('existing original and mirror retain source placements', async () => {
		const identifiers = [[g, 'attcxa5ey3sg006h'], [r, 'attcxa5eys17005v']];
		const placements = [];
		for (const [site, id] of identifiers) {
			const note = await call(site, 'notes/show', { noteId: id });
			assert.equal(note.id, id);
			placements.push(note.channelPlacements.filter(row => row.state === 'active').map(row => `${row.origin}/${row.channelId}`).toSorted());
		}
		assert.deepEqual(placements[0], placements[1]);
		assert.equal(placements[0].length, 2);
	});
	for (const site of [g, r]) channels.set(site, await call(site, 'channels/create', { name: unique(`ch_${site.role.toLowerCase()}`) }));
	for (const site of [g, r]) {
		const peer = site === g ? r : g;
		const ordinary = await delivery(site);
		await quotesAndClips(site, peer, ordinary);
		await emojiSync(site, peer);
	}
	report.completed = true;
	savePrivateJson(reportPath, report);
	console.log(`Production integration checks passed: ${report.checks.length} (${run})`);
} catch (error) {
	report.failure = { code: error.code ?? error.name };
	savePrivateJson(reportPath, report);
	throw error;
}
