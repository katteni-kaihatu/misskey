/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

process.env.GRIDSPACE_LAB_PROFILE = 'multi-note';
const { api, eventually, loadSite, savePrivateJson } = await import('./lab.mjs');
const [phase, offRole = 'R'] = process.argv.slice(2);
assert.ok(['G', 'R'].includes(offRole));
assert.ok(['prepare', 'during', 'after'].includes(phase));
const fixturePath = `.config/multi-note-flag-${offRole}.json`;
const sites = JSON.parse(readFileSync('.config/multi-note-repositories.json', 'utf8')).slice(0, 2).map(loadSite);
for (const site of sites) site.accounts = JSON.parse(readFileSync(site.accountsPath, 'utf8')).accounts;
const state = phase === 'prepare' ? { run: randomUUID().slice(0, 8), channels: {}, roots: {}, results: [] } : JSON.parse(readFileSync(fixturePath, 'utf8'));
const save = () => savePrivateJson(fixturePath, state);
const failures = [];
async function check(name, body) {
	try {
		await body();
		state.results.push({ phase, name, status: 'pass' });
		console.log(`PASS ${name}`);
	} catch (error) {
		state.results.push({ phase, name, status: 'fail', code: error.code ?? error.name });
		failures.push(name);
		console.error(`FAIL ${name} (${error.code ?? error.name})`);
		if (phase === 'prepare') throw error;
	} finally {
		save();
	}
}
function post(site, params) {
	return api(site, 'notes/create', { text: `Multi Note flag test ${state.run}`, clientRequestId: randomUUID(), includeDefault: false, ...params }, site.accounts.author.token);
}
async function includes(viewer, host, canonicalUri, pinnedOnly = false) {
	const page = await api(viewer, 'gridspace/timeline', { kind: 'channel', channelOrigin: host.origin, channelId: state.channels[host.role], pinnedOnly, limit: 10 }, viewer.accounts.reader.token);
	return page.items.some(item => item.key === canonicalUri);
}

if (phase === 'prepare') {
	for (const site of sites) {
		const channel = await api(site, 'channels/create', { name: `Flag ${offRole} ${state.run}` }, site.accounts.author.token);
		state.channels[site.role] = channel.id;
		save();
	}
	for (const origin of sites) {
		const response = await post(origin, { channelTargets: sites.map(site => ({ origin: site.origin, channelId: state.channels[site.role] })) });
		state.roots[origin.role] = { id: response.createdNote.id, uri: `${origin.origin}/notes/${response.createdNote.id}` };
		save();
	}
	for (const site of sites) {
		const uris = Object.values(state.roots).map(note => note.uri);
		for (const uri of uris) await eventually('placement active', () => includes(site, site, uri), 60000);
		await api(site, 'channels/update', { channelId: state.channels[site.role], pinnedNoteUris: uris }, site.accounts.author.token);
		await check(`${site.role} pins exist before toggle`, async () => {
			for (const uri of uris) assert.ok(await includes(site, site, uri, true));
		});
	}
} else if (phase === 'during') {
	const off = sites.find(site => site.role === offRole);
	const on = sites.find(site => site !== off);
	for (const site of sites) await eventually('feature propagation', async () => {
		const { features } = await api(site, 'meta', { detail: true });
		return features.multiNote === (site === on) && features.multiNotePeer === false;
	}, 60000);
	for (const origin of sites) {
		const peer = sites.find(site => site !== origin);
		const root = state.roots[origin.role];
		await check(`${origin.role} retains placement chips, reads, pins and original`, async () => {
			const packed = await api(origin, 'notes/show', { noteId: root.id }, origin.accounts.author.token);
			assert.equal(packed.channelPlacements.filter(placement => placement.state === 'active').length, 2);
			for (const viewer of [origin, peer]) {
				for (const host of [origin, peer]) {
					assert.ok(await includes(viewer, host, root.uri));
					assert.ok(await includes(viewer, host, root.uri, true));
				}
			}
			const detail = await api(peer, 'gridspace/private-notes', { mode: 'show', conversationUri: root.uri, noteId: root.id }, peer.accounts.reader.token);
			assert.equal(detail.notes[0]?.multiNoteKind, 'root');
		});
	}
	for (const origin of sites) {
		await check(`${origin.role} rejects new placements in disabled ${off.role}`, async () => {
			await assert.rejects(post(origin, { channelTargets: [{ origin: off.origin, channelId: state.channels[off.role] }] }), err => err.code === 'INVALID_NOTE_PLACEMENT');
		});
	}
	for (const origin of sites) {
		const peer = sites.find(site => site !== origin);
		const root = state.roots[origin.role];
		await check(`${origin.role} deletion removes remote placement and pin in ${peer.role}`, async () => {
			await api(origin, 'notes/delete', { noteId: root.id }, origin.accounts.author.token);
			await eventually('deleted remote placement', async () => !await includes(peer, peer, root.uri), 60000);
			assert.equal(await includes(peer, peer, root.uri, true), false);
		});
	}
} else {
	for (const site of sites) await check(`${site.role} restored both capabilities`, async () => {
		await eventually('feature restored', async () => {
			const { features } = await api(site, 'meta', { detail: true });
			return features.multiNote && features.multiNotePeer;
		}, 60000);
	});
}
if (failures.length) throw new Error(`${failures.length} feature-flag checks failed: ${failures.join(', ')}`);
