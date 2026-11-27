/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, describe, expect, test, vi } from 'vitest';
import { mockDeep } from 'vitest-mock-extended';
import type { DataSource, Repository } from 'typeorm';
import type { Config } from '@/config.js';
import { MiAccessToken } from '@/models/AccessToken.js';
import { MiUser, type MiLocalUser } from '@/models/User.js';
import { MiApp } from '@/models/App.js';
import { GridspaceClientReadService } from './GridspaceClientReadService.js';
import { GridspaceLinkError, type GridspaceLinkService } from './GridspaceLinkService.js';
import type { GridspaceNotificationService } from './GridspaceNotificationService.js';
import type { GridspaceTimelineService } from './timeline/GridspaceTimelineService.js';
import { CLIENT_NOTIFICATION_SCOPE, CLIENT_PRIVATE_SCOPE, CLIENT_TIMELINE_SCOPE, clientNote } from './client-read-protocol.js';

afterEach(() => { vi.unstubAllEnvs(); vi.restoreAllMocks(); });

const viewer = { id: 'viewer' } as MiLocalUser;
const note = { id: 'note', uri: 'https://local.example/notes/note', createdAt: '2026-11-27T00:00:00.000Z', text: 'hello', cw: null,
	visibility: 'followers', user: { id: 'author', username: 'author', name: null, host: null }, files: [] };

function fixture(permissions = [CLIENT_TIMELINE_SCOPE, CLIENT_NOTIFICATION_SCOPE, 'read:account']) {
	vi.stubEnv('GRIDSPACE_CLIENT_TEST_SECRET', Buffer.alloc(32, 5).toString('base64'));
	const config = { url: 'https://local.example', gridspace: { enabled: true, timelineEnabled: true, communityId: 'test', peerUrl: 'https://peer.example', keyId: 'test', secretEnv: 'GRIDSPACE_CLIENT_TEST_SECRET' } } as Config;
	const db = mockDeep<DataSource>();
	const tokens = mockDeep<Repository<MiAccessToken>>();
	const users = mockDeep<Repository<MiUser>>();
	const apps = mockDeep<Repository<MiApp>>();
	db.getRepository.mockImplementation(((entity: unknown) => entity === MiAccessToken ? tokens : entity === MiUser ? users : apps) as never);
	let live: MiAccessToken | null = { id: 'token', userId: viewer.id, token: 'test-token', appId: null, permission: permissions, name: 'reader' } as MiAccessToken;
	const token = { ...live };
	tokens.findOneBy.mockImplementation(async (where) => live && (where as { id: string }).id === live.id ? { ...live } : null);
	users.existsBy.mockResolvedValue(true);
	const links = mockDeep<GridspaceLinkService>();
	links.privateLink.mockRejectedValue(new GridspaceLinkError('LINK_REVOKED'));
	links.privateStatus.mockResolvedValue({ available: true, granted: true, mutual: true } as never);
	const timeline = mockDeep<GridspaceTimelineService>();
	timeline.capability.mockResolvedValue({ version: 1, enabled: true, kinds: ['home'] });
	timeline.page.mockResolvedValue({ version: 1, session: 'private-session', revision: '1', items: [{ key: note.uri, payload: note, validForMs: null, nextPolicyCheckAt: null }],
		nextCursor: 'internal-cursor', complete: true, sources: [{ source: 'local', status: 'ok', retryable: false }], revalidateAfterMs: 30000 } as never);
	const notifications = mockDeep<GridspaceNotificationService>();
	notifications.local.mockResolvedValue({ origin: config.url, recipientId: viewer.id, items: [{ id: 'notification', createdAt: note.createdAt, isRead: false,
		notification: { id: 'notification', type: 'reply', user: note.user, note } }], next: 'older', newest: null, boundary: null, unreadCount: 1 } as never);
	const reader = new GridspaceClientReadService(db, config, links, timeline, notifications);
	return { reader, token, tokens, users, apps, links, timeline, notifications, setToken: (value: MiAccessToken | null) => { live = value; }, getToken: () => live! };
}

describe('external GridSpace read authorization', () => {
	test('requires an application token, including for status', async () => {
		const f = fixture();
		await expect(f.reader.status(viewer, null)).rejects.toThrow('APP_TOKEN_REQUIRED');
		expect(f.timeline.page).not.toHaveBeenCalled();
	});

	test('checks the live scope before querying content', async () => {
		const f = fixture(['read:account']);
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false })).rejects.toThrow('PERMISSION_DENIED');
		expect(f.timeline.page).not.toHaveBeenCalled();
	});

	test('uses local-only source selection and does not expose internal sessions', async () => {
		const f = fixture();
		const page = await f.reader.home(viewer, f.token, { limit: 20, includePrivate: false });
		expect(f.timeline.page).toHaveBeenCalledWith(viewer, expect.objectContaining({ kind: 'home', clientLocalOnly: true }), 20, undefined, 'local-fallback');
		expect(page.items[0].note.text).toBe('hello');
		expect(JSON.stringify(page)).not.toContain('private-session');
		expect(page.nextCursor).not.toContain('internal-cursor');
	});

	test('requires explicit private scope before enabling peer reads', async () => {
		const f = fixture();
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: true })).rejects.toThrow('PERMISSION_DENIED');
		expect(f.timeline.page).not.toHaveBeenCalled();
	});

	test('rejects a token revoked during a content read', async () => {
		const f = fixture();
		f.timeline.page.mockImplementationOnce(async () => { f.setToken(null); return { items: [] } as never; });
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false })).rejects.toThrow('AUTHORIZATION_REVOKED');
	});

	test('rejects a user suspended during a content read', async () => {
		const f = fixture();
		f.timeline.page.mockImplementationOnce(async () => { f.users.existsBy.mockResolvedValue(false); return { items: [] } as never; });
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false })).rejects.toThrow('AUTHORIZATION_REVOKED');
	});

	test('binds cursors to the token and the complete current permission set', async () => {
		const f = fixture();
		const first = await f.reader.home(viewer, f.token, { limit: 20, includePrivate: false });
		await f.reader.home(viewer, f.token, { limit: 20, includePrivate: false, cursor: first.nextCursor! });
		expect(f.timeline.page).toHaveBeenLastCalledWith(viewer, expect.anything(), 20, 'internal-cursor', 'local-fallback');
		f.setToken({ ...f.getToken(), permission: [...f.getToken().permission, CLIENT_PRIVATE_SCOPE] });
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false, cursor: first.nextCursor! })).rejects.toThrow('INVALID_CURSOR');
	});

	test('rejects another application token belonging to the same user', async () => {
		const f = fixture();
		const first = await f.reader.home(viewer, f.token, { limit: 20, includePrivate: false });
		const other = { ...f.getToken(), id: 'other', token: 'other-token' };
		f.setToken(other);
		await expect(f.reader.home(viewer, other, { limit: 20, includePrivate: false, cursor: first.nextCursor! })).rejects.toThrow('INVALID_CURSOR');
	});

	test('expires cursors and rejects tampering', async () => {
		const f = fixture();
		const first = await f.reader.home(viewer, f.token, { limit: 20, includePrivate: false });
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false, cursor: first.nextCursor! + 'x' })).rejects.toThrow('INVALID_CURSOR');
		vi.spyOn(Date, 'now').mockReturnValue(Date.now() + 11 * 60_000);
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false, cursor: first.nextCursor! })).rejects.toThrow('INVALID_CURSOR');
	});

	test('rechecks the linked grant before returning private content', async () => {
		const f = fixture([CLIENT_TIMELINE_SCOPE, CLIENT_PRIVATE_SCOPE]);
		f.links.privateLink.mockResolvedValueOnce({ id: 'link', generation: 1, tokenCipher: 'grant' } as never);
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: true })).rejects.toThrow('AUTHORIZATION_REVOKED');
	});

	test('preserves the existing peer-credential guard', async () => {
		const f = fixture();
		f.links.assertPrivateCaller.mockImplementation(() => { throw new GridspaceLinkError('AUTHORIZATION_REVOKED'); });
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false })).rejects.toThrow('AUTHORIZATION_REVOKED');
		expect(f.timeline.page).not.toHaveBeenCalled();
	});

	test('detects revocation of a one-way private grant during a read', async () => {
		const f = fixture([CLIENT_TIMELINE_SCOPE, CLIENT_PRIVATE_SCOPE]);
		const link = { id: 'link', generation: 1, tokenCipher: 'normal-link', privateTokenCipher: 'private-grant', privateRevision: 1 };
		f.links.privateLink.mockResolvedValue(link as never);
		f.timeline.page.mockImplementationOnce(async () => {
			link.privateTokenCipher = '';
			link.privateRevision++;
			return { items: [] } as never;
		});
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: true })).rejects.toThrow('AUTHORIZATION_REVOKED');
	});

	test('reports a valid one-way private grant as usable', async () => {
		const f = fixture(['read:account', CLIENT_PRIVATE_SCOPE]);
		f.links.privateStatus.mockResolvedValue({ available: true, granted: true, mutual: false } as never);
		expect((await f.reader.status(viewer, f.token)).peer).toBe('ok');
	});

	test('uses live legacy application permissions, not cached caller permissions', async () => {
		const f = fixture();
		f.setToken({ ...f.getToken(), appId: 'legacy' });
		f.apps.findOneBy.mockResolvedValue({ id: 'legacy', permission: ['read:account'] } as MiApp);
		await expect(f.reader.home(viewer, f.token, { limit: 20, includePrivate: false })).rejects.toThrow('PERMISSION_DENIED');
	});
});

describe('external notification reads', () => {
	test('reads local notifications without marking them read or exposing presentation internals', async () => {
		const f = fixture();
		const page = await f.reader.readNotifications(viewer, f.token, { source: 'local', limit: 20, includePrivate: false });
		expect(page.items[0]).toMatchObject({ isRead: false, type: 'reply' });
		expect(f.notifications.local).toHaveBeenCalledWith(viewer, { before: undefined, limit: 20 });
		expect(f.notifications.remote).not.toHaveBeenCalled();
		expect(page.nextCursor).not.toBe('older');
	});

	test.each(['peer', 'channel'] as const)('does not contact %s without private permission', async source => {
		const f = fixture();
		await expect(f.reader.readNotifications(viewer, f.token, { source, limit: 20, includePrivate: false })).rejects.toThrow('PERMISSION_DENIED');
		expect(f.notifications.remote).not.toHaveBeenCalled();
	});

	test('reports peer failure without stale items or an unread count', async () => {
		const f = fixture([CLIENT_NOTIFICATION_SCOPE, CLIENT_PRIVATE_SCOPE]);
		f.notifications.remote.mockRejectedValue(new GridspaceLinkError('PEER_UNAVAILABLE'));
		const page = await f.reader.readNotifications(viewer, f.token, { source: 'peer', limit: 20, includePrivate: true });
		expect(page).toMatchObject({ items: [], nextCursor: null, unreadCount: null, source: { status: 'unavailable', retryable: true } });
		expect(f.notifications.remote).toHaveBeenCalledWith(viewer, expect.anything(), 'query', false);
	});

	test('does not convert unexpected server errors to an empty successful page', async () => {
		const f = fixture();
		f.notifications.local.mockRejectedValue(new Error('database error'));
		await expect(f.reader.readNotifications(viewer, f.token, { source: 'local', limit: 20, includePrivate: false })).rejects.toThrow('database error');
	});

	test('status returns only capabilities and requires a live token', async () => {
		const f = fixture();
		expect(await f.reader.status(viewer, f.token)).toEqual({ version: 1, timeline: true, notifications: true, peerPrivate: false, peer: 'disabled' });
		f.setToken(null);
		await expect(f.reader.status(viewer, f.token)).rejects.toThrow('AUTHORIZATION_REVOKED');
	});
});

test('the reader projection preserves authorized ActivityPub followers posts without copying arbitrary fields', () => {
	const payload = { ...note, token: 'secret', renote: { ...note, uri: 'https://peer.example/notes/private', origin: 'https://peer.example', text: 'private' } };
	const result = clientNote(payload, 'https://local.example');
	expect(result?.renote?.visibility).toBe('followers');
	expect(result?.renote?.text).toBe('private');
	expect(JSON.stringify(result)).not.toContain('secret');
});
