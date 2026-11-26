/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { Config } from '@/config.js';
import type { MiSpace } from '@/models/Space.js';
import { buildSpaceSummaryText, pickSpaceLeader, SPACE_EMPTY_CLOSE_MS, SpaceService } from './SpaceService.js';

type Args = ConstructorParameters<typeof SpaceService>;

function space(patch: Partial<MiSpace> = {}): MiSpace {
	return { id: 'space', hostId: 'host', host: null, name: 'name', access: 'local', noteScope: 'local', tilePlacement: 'everyone', continuedFromId: null, announceNoteId: null, summaryNoteId: null, participantIds: [], peakCount: 0, endedAt: null, ...patch };
}

function fixture() {
	const kicked = new Set<string>();
	const strings = new Map<string, string>();
	const redis = {
		sismember: vi.fn(async (_key: string, id: string) => kicked.has(id) ? 1 : 0),
		zrangebyscore: vi.fn(async () => []),
		hlen: vi.fn(async () => 0),
		get: vi.fn(async (key: string) => strings.get(key) ?? null),
		set: vi.fn(async (key: string, value: string) => { strings.set(key, value); return 'OK'; }),
		del: vi.fn(async () => 1),
	};
	const spaces = {
		findBy: vi.fn(async () => [] as MiSpace[]),
		update: vi.fn(async () => ({ affected: 1 })),
		findOne: vi.fn(async () => null as MiSpace | null),
	};
	const followings = { exists: vi.fn(async () => false) };
	const blocking = { checkBlocked: vi.fn(async (_blocker: string, _blockee: string) => false) };
	const events = { publishSpaceStream: vi.fn() };
	const logger = { warn: vi.fn(), debug: vi.fn() };
	const notes = { create: vi.fn(async () => ({ id: 'summary' })) };
	const announces = { findOneBy: vi.fn(async () => ({ id: 'announce', localOnly: true, visibility: 'followers' }) as { id: string; localOnly: boolean; visibility: string } | null) };
	const ids = { parse: () => ({ date: new Date(1_800_000_000_000 - 90 * 60000) }) };
	const service = new SpaceService(
		{ url: 'https://g.example', spaces: undefined } as Config,
		redis as unknown as Args[1],
		spaces as unknown as Args[2],
		followings as unknown as Args[3],
		{} as Args[4],
		ids as unknown as Args[5],
		{} as Args[6],
		blocking as unknown as Args[7],
		notes as unknown as Args[8],
		events as unknown as Args[9],
		{ getLogger: () => logger } as unknown as Args[10],
		announces as unknown as Args[11],
		{ closeSpace: vi.fn(async () => undefined) } as unknown as Args[12],
	);
	return { service, kicked, strings, redis, spaces, followings, blocking, events, notes, announces };
}

describe('SpaceService.canJoin', () => {
	let f: ReturnType<typeof fixture>;
	beforeEach(() => {
		f = fixture();
	});

	test('nobody can join an ended space, not even the host', async () => {
		expect(await f.service.canJoin({ id: 'host' }, space({ endedAt: new Date() }))).toBe(false);
	});

	test('the host can always join an open space', async () => {
		f.kicked.add('host');
		expect(await f.service.canJoin({ id: 'host' }, space({ access: 'followers' }))).toBe(true);
	});

	test('anyone on the server can join a local space', async () => {
		expect(await f.service.canJoin({ id: 'guest' }, space())).toBe(true);
		expect(f.followings.exists).not.toHaveBeenCalled();
	});

	test('a kicked user cannot rejoin', async () => {
		f.kicked.add('guest');
		expect(await f.service.canJoin({ id: 'guest' }, space())).toBe(false);
	});

	test('a block in either direction keeps the user out', async () => {
		f.blocking.checkBlocked.mockImplementation(async (blocker, blockee) => blocker === 'host' && blockee === 'guest');
		expect(await f.service.canJoin({ id: 'guest' }, space())).toBe(false);
		f.blocking.checkBlocked.mockImplementation(async (blocker, blockee) => blocker === 'guest' && blockee === 'host');
		expect(await f.service.canJoin({ id: 'guest' }, space())).toBe(false);
	});

	test('a followers-only space admits only followers of the host', async () => {
		expect(await f.service.canJoin({ id: 'guest' }, space({ access: 'followers' }))).toBe(false);
		f.followings.exists.mockResolvedValue(true);
		expect(await f.service.canJoin({ id: 'guest' }, space({ access: 'followers' }))).toBe(true);
		expect(f.followings.exists).toHaveBeenLastCalledWith({ where: { followerId: 'guest', followeeId: 'host' } });
	});
});

describe('SpaceService.closeAbandoned', () => {
	const now = 1_800_000_000_000;

	test('keeps a space that has someone in it', async () => {
		const f = fixture();
		f.spaces.findBy.mockResolvedValue([space()]);
		f.redis.hlen.mockResolvedValue(1);
		expect(await f.service.closeAbandoned(now)).toBe(0);
		expect(f.spaces.update).not.toHaveBeenCalled();
	});

	test('starts counting when the empty mark is missing', async () => {
		const f = fixture();
		f.spaces.findBy.mockResolvedValue([space()]);
		expect(await f.service.closeAbandoned(now)).toBe(0);
		expect(f.strings.get('space:space:emptySince')).toBe(now.toString());
	});

	test('keeps an empty space until the limit, then closes it', async () => {
		const f = fixture();
		f.spaces.findBy.mockResolvedValue([space()]);
		f.strings.set('space:space:emptySince', (now - SPACE_EMPTY_CLOSE_MS + 1000).toString());
		expect(await f.service.closeAbandoned(now)).toBe(0);

		f.strings.set('space:space:emptySince', (now - SPACE_EMPTY_CLOSE_MS).toString());
		expect(await f.service.closeAbandoned(now)).toBe(1);
		expect(f.spaces.update).toHaveBeenCalledTimes(1);
		expect(f.events.publishSpaceStream).toHaveBeenCalledWith('space', 'ended', null);
		expect(f.redis.del).toHaveBeenCalled();
	});
});

describe('leader', () => {
	test('is the host when the host is in the space, otherwise the one who has been in longest', () => {
		expect(pickSpaceLeader(['a', 'host', 'b'], 'host')).toBe('host');
		expect(pickSpaceLeader(['a', 'b'], 'host')).toBe('a');
		expect(pickSpaceLeader([], 'host')).toBeNull();
	});
});

describe('summary note', () => {
	const host = { id: 'host', username: 'host', host: null };

	test('writes the name, the time open, the head count and the link, without names', () => {
		const text = buildSpaceSummaryText({ name: 'もくもく', startedAt: new Date(0), endedAt: new Date(95 * 60000), participantCount: 7, url: 'https://g.example/spaces/space' });
		expect(text).toBe('もくもく は終わりました\n開いていた時間 1時間35分 ・ 参加した人 7人\nhttps://g.example/spaces/space');
		expect(buildSpaceSummaryText({ name: 'n', startedAt: new Date(0), endedAt: new Date(5000), participantCount: 1, url: 'u' })).toContain('1分');
	});

	test('is posted on close with the scope of the announcement', async () => {
		const f = fixture();
		// ひらいたあとで「入れる人」を広げていても、範囲は実際に出たお知らせノートに合わせる
		const ended = space({ endedAt: new Date(1_800_000_000_000), participantIds: ['a', 'b', 'c'], access: 'local', noteScope: 'public', announceNoteId: 'announce', host: host as MiSpace['host'] });
		f.spaces.findOne.mockResolvedValue(ended);
		await f.service.end(space());
		expect(f.notes.create).toHaveBeenCalledWith(host, expect.objectContaining({ localOnly: true, visibility: 'followers', text: expect.stringContaining('参加した人 3人') }));
		expect(f.spaces.update).toHaveBeenLastCalledWith('space', { summaryNoteId: 'summary' });
	});

	test('is not posted when the host chose no notes, twice, or after the announcement was deleted', async () => {
		const f = fixture();
		f.spaces.findOne.mockResolvedValue(space({ endedAt: new Date(), noteScope: 'none', host: host as MiSpace['host'] }));
		await f.service.end(space());
		f.spaces.findOne.mockResolvedValue(space({ endedAt: new Date(), announceNoteId: 'announce', summaryNoteId: 'already', host: host as MiSpace['host'] }));
		await f.service.end(space());
		f.announces.findOneBy.mockResolvedValue(null);
		f.spaces.findOne.mockResolvedValue(space({ endedAt: new Date(), announceNoteId: 'announce', host: host as MiSpace['host'] }));
		await f.service.end(space());
		expect(f.notes.create).not.toHaveBeenCalled();
	});
});

describe('SpaceService.createToken', () => {
	test('refuses when spaces is not configured', async () => {
		const f = fixture();
		await expect(f.service.createToken(space(), { id: 'guest' } as Parameters<SpaceService['createToken']>[1])).rejects.toThrow('not enabled');
	});
});
