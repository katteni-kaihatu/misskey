/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { beforeAll, describe, expect, test } from 'vitest';
import { api, createAppToken, initTestDb, post, signup } from '../utils.js';
import type { UserToken } from '../utils.js';
import type * as misskey from 'misskey-js';

describe('GridSpace external read API', () => {
	let alice: misskey.entities.SignupResponse;
	let bob: misskey.entities.SignupResponse;
	let reader: UserToken;
	let accountOnly: UserToken;
	beforeAll(async () => {
		// synchronize() creates tables but does not run the migration's seed insert.
		const db = await initTestDb(true);
		try { await db.query("INSERT INTO gridspace_timeline_state (key) VALUES ('changes') ON CONFLICT DO NOTHING"); } finally { await db.destroy(); }
		alice = await signup({ username: 'g2alice' });
		bob = await signup({ username: 'g2bob' });
		reader = { token: await createAppToken(alice, ['read:account', 'read:gridspace-client-timeline', 'read:gridspace-client-notifications']) };
		accountOnly = { token: await createAppToken(alice, ['read:account']) };
	});

	test('requires authentication and an application token', async () => {
		expect((await api('gridspace/client/status', {})).status).toBe(401);
		const native = await api('gridspace/client/status', {}, alice);
		expect(native.status).toBe(403);
	});

	test('returns only the application capabilities', async () => {
		const res = await api('gridspace/client/status', {}, reader);
		expect(res.status, JSON.stringify(res.body)).toBe(200);
		expect(res.body).toMatchObject({ version: 1, notifications: true, peerPrivate: false, peer: 'disabled' });
		expect(Object.keys(res.body).sort()).toEqual(['notifications', 'peer', 'peerPrivate', 'timeline', 'version']);
		expect(res.headers.get('cache-control')).toBe('private, no-store');
	});

	test('requires each endpoint scope separately', async () => {
		expect((await api('gridspace/client/timeline', {}, accountOnly)).status).toBe(403);
		expect((await api('gridspace/client/notifications', {}, accountOnly)).status).toBe(403);
		expect((await api('gridspace/client/timeline', { includePrivate: true }, reader)).status).toBe(403);
		expect((await api('gridspace/client/notifications', { source: 'peer' }, reader)).status).toBe(403);
	});

	test('validates limits and cursor authentication', async () => {
		expect((await api('gridspace/client/timeline', { limit: 41 }, reader)).status).toBe(400);
		expect((await api('gridspace/client/timeline', { cursor: 'forged' }, reader)).status).toBe(400);
	});

	test('reads a home post using an application token', async () => {
		const own = await post(alice, { text: 'external reader home post' });
		const res = await api('gridspace/client/timeline', { limit: 20 }, reader);
		expect(res.status, JSON.stringify(res.body)).toBe(200);
		expect(res.body.items.some(item => item.note.id === own.id && item.note.text === 'external reader home post')).toBe(true);
		expect(res.body.sources).toContainEqual({ source: 'peer', status: 'disabled', retryable: false });
		expect(res.headers.get('cache-control')).toBe('private, no-store');
	});

	test('notification reads do not mark a reply as read', async () => {
		const root = await post(alice, { text: 'notification root' });
		await post(bob, { text: 'notification reply', replyId: root.id });
		let found = false;
		for (let attempt = 0; attempt < 30; attempt++) {
			const res = await api('gridspace/client/notifications', {}, reader);
			expect(res.status).toBe(200);
			const item = res.body.items.find(value => value.type === 'reply');
			if (item) { expect(item.isRead).toBe(false); found = true; break; }
			await new Promise(resolve => setTimeout(resolve, 100));
		}
		expect(found).toBe(true);
		const again = await api('gridspace/client/notifications', {}, reader);
		expect(again.body.items.find(value => value.type === 'reply')?.isRead).toBe(false);
	});
});
