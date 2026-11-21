/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

export async function testRetirement({ g, r, users, run, fixtures, remember, check, api, eventually, createNote, channelContains, uri }) {
	const { loadSite } = await import('./lab.mjs');
	assert.equal(process.env.GRIDSPACE_LAB_PROFILE, 'multi-note');
	for (const [index, site] of [g, r].entries()) {
		const expected = loadSite(site.repo, index);
		assert.equal(site.origin, expected.origin);
		assert.equal(site.config.port, expected.config.port);
	}
	const timeout = 120_000;
	const results = fixtures.retirement ??= {};

	async function showMissing(site, noteId, viewer) {
		try {
			await api(site, 'notes/show', { noteId }, viewer.token);
			return false;
		} catch (error) {
			if (error.code === 'NO_SUCH_NOTE') return true;
			throw error;
		}
	}

	async function publicOriginal(site, posted) {
		const note = await api(site, 'notes/show', { noteId: posted.note.id });
		assert.equal(note.id, posted.note.id);
		assert.equal(note.text, posted.request.text);
		assert.equal(uri(site, note), posted.canonicalUri);
		const canonical = new URL(posted.canonicalUri);
		assert.equal(canonical.origin, site.origin);
		assert.equal(canonical.pathname, '/notes/' + posted.note.id);
		const url = process.env.GRIDSPACE_LAB_LOOPBACK === '1' ? new URL(canonical.pathname, 'http://127.0.0.1:' + site.config.port) : canonical;
		const response = await fetch(url, { headers: { accept: 'text/html', 'cache-control': 'no-cache' }, redirect: 'error', signal: AbortSignal.timeout(15000) });
		assert.equal(response.status, 200);
		assert.match(response.headers.get('content-type') ?? '', /text\/html/);
		// A generic SPA shell can also return 200. Check the server-rendered original.
		assert.ok((await response.text()).includes(posted.request.text), 'the public HTML contains the original text');
	}

	for (const [source, target] of [[g, r], [r, g]]) {
		const { author, reader } = users.get(source);
		const { author: owner, reader: observer } = users.get(target);
		const direction = source.role + '-' + target.role;
		const summary = results[direction] = {};
		// Separate channels make exact counts observable even when deleted authors are hidden by hydration.
		const channels = [];
		for (const label of ['one', 'two']) {
			const channel = await api(target, 'channels/create', { name: 'Retirement ' + direction + ' ' + label + ' ' + run }, owner.token);
			channels.push(channel);
			fixtures.channels[target.role + '_retirement_' + label] = { ...channel, origin: target.origin };
		}
		remember();
		const targets = channels.map(channel => ({ origin: target.origin, channelId: channel.id }));
		const remove = (site, actor, posted, channel) => api(site, 'gridspace/multi-note/remove', {
			canonicalUri: posted.canonicalUri, channelOrigin: target.origin, channelId: channel.id,
		}, actor.token);
		const retry = (posted, actor = author) => api(source, 'gridspace/multi-note/retry', { canonicalUri: posted.canonicalUri }, actor.token);
		const readRoutes = async (posted, actor) => (await api(source, 'notes/show', { noteId: posted.note.id }, actor.token)).channelPlacements ?? [];
		function hasState(routes, channel, state) {
			return routes.some(p => p.origin === target.origin && p.channelId === channel.id && p.state === state);
		}
		async function waitIndex(posted, channel, listed, count) {
			await eventually(direction + ' index/count ' + channel.id, async () => {
				const metadata = await api(target, 'channels/show', { channelId: channel.id }, observer.token);
				return metadata.notesCount === count && await channelContains(target, observer, target.origin, channel.id, posted.canonicalUri) === listed;
			}, timeout);
		}
		async function waitActive(posted, actor) {
			await eventually(direction + ' delivery acknowledgement', async () => {
				const routes = await readRoutes(posted, actor);
				return channels.every(channel => hasState(routes, channel, 'active'));
			}, timeout);
			for (const channel of channels) await waitIndex(posted, channel, true, 1);
		}
		let removed;
		await check(direction + ': source and destination removals converge and preserve the public original', async () => {
			removed = await createNote(source, author, 'retirement_remove', { includeDefault: false, channelTargets: targets });
			const initial = removed.note.channelPlacements ?? [];
			for (const channel of channels) assert.ok(['pending', 'active'].some(state => hasState(initial, channel, state)), 'committed delivery intent is observable');
			summary.createStates = initial.map(p => p.state);
			await retry(removed);
			await waitActive(removed, author);
			await remove(source, author, removed, channels[0]);
			await waitIndex(removed, channels[0], false, 0);
			await waitIndex(removed, channels[1], true, 1);
			await remove(target, owner, removed, channels[1]);
			await remove(target, owner, removed, channels[1]);
			await eventually(direction + ' source receives target removal', async () => {
				const routes = await readRoutes(removed, author);
				return channels.every(channel => hasState(routes, channel, 'removed'));
			}, timeout);
			await waitIndex(removed, channels[1], false, 0);
			assert.equal((await readRoutes(removed, reader)).some(p => p.state === 'active'), false);
			await publicOriginal(source, removed);
			remember();
		});

		await check(direction + ': manual retries do not restore removed placements and original deletion reaches all targets', async () => {
			await retry(removed);
			await retry(removed, source.accounts.admin);
			const replay = await api(source, 'notes/create', removed.request, author.token);
			assert.equal(replay.createdNote.id, removed.note.id);

			// Delete immediately after commit, before waiting for the asynchronous placement acknowledgement.
			const early = await createNote(source, author, 'retirement_early_delete', { includeDefault: false, channelTargets: targets });
			summary.earlyDeleteStates = early.note.channelPlacements.map(p => p.state);
			await api(source, 'notes/delete', { noteId: early.note.id }, author.token);
			assert.equal((await api(source, 'notes/create-status', { clientRequestId: early.request.clientRequestId }, author.token)).status, 'deleted');
			remember();

			// A later note makes another delivery pass observable before testing non-resurrection.
			const posted = await createNote(source, author, 'retirement_delete', { includeDefault: false, channelTargets: targets });
			await waitActive(posted, author);
			for (const channel of channels) {
				await waitIndex(removed, channel, false, 1);
				await waitIndex(early, channel, false, 1);
			}
			await api(source, 'notes/delete', { noteId: posted.note.id }, author.token);
			await eventually(direction + ' deleted receipt', async () => (await api(source, 'notes/create-status', { clientRequestId: posted.request.clientRequestId }, author.token)).status === 'deleted', timeout);
			await eventually(direction + ' deleted original', () => showMissing(source, posted.note.id, reader), timeout);
			for (const channel of channels) await waitIndex(posted, channel, false, 0);
			const routes = await readRoutes(removed, author);
			assert.ok(channels.every(channel => hasState(routes, channel, 'removed')));
			await publicOriginal(source, removed);
		});

		await check(direction + ': retiring a newly created account removes every peer placement', async () => {
			const username = 'mn_del_' + randomBytes(6).toString('hex');
			const password = randomBytes(32).toString('base64url');
			const account = await api(source, 'admin/accounts/create', { username, password }, source.accounts.admin.token);
			assert.equal(account.username, username);
			assert.ok(account.id && account.token);
			const self = await api(source, 'i', {}, account.token);
			assert.equal(self.id, account.id);
			assert.equal(self.username, username);
			assert.ok(![source.accounts.admin.id, author.id, reader.id].includes(self.id));

			const posted = await createNote(source, account, 'retirement_account', { includeDefault: false, channelTargets: targets });
			await waitActive(posted, account);
			summary.deletedAccount = { id: self.id, username, original: posted.canonicalUri };
			remember();
			// Self-service retirement uses only the newly returned account token and its generated password.
			await api(source, 'i/delete-account', { password }, account.token);
			await eventually(direction + ' account-deletion worker removes original', () => showMissing(source, posted.note.id, reader), timeout);
			for (const channel of channels) await waitIndex(posted, channel, false, 0);
		});
	}
}
