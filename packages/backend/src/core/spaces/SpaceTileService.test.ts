/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test, vi } from 'vitest';
import type { MiSpace } from '@/models/Space.js';
import type { MiSpaceTile } from '@/models/SpaceTile.js';
import { SPACE_SHARED_VALUE_MAX_BYTES, SpaceTileService } from './SpaceTileService.js';

type Args = ConstructorParameters<typeof SpaceTileService>;

/** テストに要るぶんだけの、メモリの中の Redis。 */
function fakeRedis() {
	const strings = new Map<string, string>();
	const sets = new Map<string, Set<string>>();
	const hashes = new Map<string, Map<string, string>>();
	const set = (key: string) => sets.get(key) ?? sets.set(key, new Set()).get(key)!;
	const hash = (key: string) => hashes.get(key) ?? hashes.set(key, new Map()).get(key)!;
	return {
		strings, sets, hashes,
		get: vi.fn(async (key: string) => strings.get(key) ?? null),
		hsetnx: vi.fn(async (key: string, field: string, value: string) => {
			if (hash(key).has(field)) return 0;
			hash(key).set(field, value);
			return 1;
		}),
		set: vi.fn(async (key: string, value: string, ...modes: (string | number)[]) => {
			if (modes.includes('NX') && strings.has(key)) return null;
			strings.set(key, value);
			return 'OK';
		}),
		incr: vi.fn(async (key: string) => {
			const next = Number(strings.get(key) ?? '0') + 1;
			strings.set(key, next.toString());
			return next;
		}),
		sadd: vi.fn(async (key: string, ...members: string[]) => { for (const member of members) set(key).add(member); return members.length; }),
		srem: vi.fn(async (key: string, member: string) => set(key).delete(member) ? 1 : 0),
		sismember: vi.fn(async (key: string, member: string) => set(key).has(member) ? 1 : 0),
		smembers: vi.fn(async (key: string) => [...set(key)]),
		hset: vi.fn(async (key: string, field: string | Record<string, string>, value?: string) => {
			if (typeof field === 'string') hash(key).set(field, value!);
			else for (const [k, v] of Object.entries(field)) hash(key).set(k, v);
			return 1;
		}),
		hdel: vi.fn(async (key: string, field: string) => hash(key).delete(field) ? 1 : 0),
		hgetall: vi.fn(async (key: string) => Object.fromEntries(hash(key))),
		del: vi.fn(async (...keys: string[]) => {
			for (const key of keys) { strings.delete(key); sets.delete(key); hashes.delete(key); }
			return keys.length;
		}),
	};
}

function tile(patch: Partial<MiSpaceTile> = {}): MiSpaceTile {
	return { id: 't1', spaceId: 'space', space: null, kind: 'memo', creatorId: 'alice', position: 0, shared: {}, ...patch };
}

function fixture(stored: MiSpaceTile[] = [tile()]) {
	const redis = fakeRedis();
	const rows = new Map(stored.map(row => [row.id, { ...row }]));
	const sorted = () => [...rows.values()].sort((a, b) => a.position - b.position || a.id.localeCompare(b.id));
	const tiles = {
		findBy: vi.fn(async () => sorted()),
		find: vi.fn(async () => sorted()),
		findOne: vi.fn(async () => sorted().at(-1) ?? null),
		insertOne: vi.fn(async (row: MiSpaceTile) => { rows.set(row.id, row); return row; }),
		update: vi.fn(async (criteria: string | { id: string }, patch: Partial<MiSpaceTile>) => {
			const row = rows.get(typeof criteria === 'string' ? criteria : criteria.id);
			if (row == null) return { affected: 0 };
			Object.assign(row, patch);
			return { affected: 1 };
		}),
		delete: vi.fn(async (id: string) => { rows.delete(id); }),
	};
	const events = { publishSpaceStream: vi.fn() };
	let nextId = 2;
	const service = new SpaceTileService(
		redis as unknown as Args[0],
		{} as Args[1],
		tiles as unknown as Args[2],
		{ gen: () => `t${nextId++}` } as unknown as Args[3],
		events as unknown as Args[4],
	);
	return { service, redis, rows, tiles, events };
}

const space = { id: 'space', hostId: 'host', endedAt: null, tilePlacement: 'everyone' } as MiSpace;

describe('placing tiles', () => {
	test('anyone can place by default; only the host when the host says so; nobody after it ends', () => {
		const { service } = fixture();
		expect(service.canPlace({ id: 'guest' }, space)).toBe(true);
		expect(service.canPlace({ id: 'guest' }, { ...space, tilePlacement: 'host' })).toBe(false);
		expect(service.canPlace({ id: 'host' }, { ...space, tilePlacement: 'host' })).toBe(true);
		expect(service.canPlace({ id: 'host' }, { ...space, endedAt: new Date() })).toBe(false);
	});

	test('the creator and the host can remove a tile', () => {
		const { service } = fixture();
		expect(service.canRemove({ id: 'alice' }, space, tile())).toBe(true);
		expect(service.canRemove({ id: 'host' }, space, tile())).toBe(true);
		expect(service.canRemove({ id: 'guest' }, space, tile())).toBe(false);
	});

	test('a new tile goes last and is announced', async () => {
		const f = fixture();
		const added = await f.service.add(space, { id: 'bob' }, 'poll');
		expect(added).toMatchObject({ id: 't2', kind: 'poll', creatorId: 'bob', position: 1 });
		expect(f.events.publishSpaceStream).toHaveBeenCalledWith('space', 'tileAdded', expect.objectContaining({ id: 't2', position: 1 }));
	});

	test('moving ignores unknown ids and keeps unlisted tiles at the end', async () => {
		const f = fixture([tile({ id: 'a', position: 0 }), tile({ id: 'b', position: 1 }), tile({ id: 'c', position: 2 })]);
		await f.service.move(space, ['c', 'zzz', 'c', 'a']);
		expect(f.events.publishSpaceStream).toHaveBeenCalledWith('space', 'tilesMoved', { tileIds: ['c', 'a', 'b'] });
		expect(f.rows.get('c')?.position).toBe(0);
		expect(f.rows.get('b')?.position).toBe(2);
	});
});

describe('shared values', () => {
	test('a write gets the next number and is sent to everyone', async () => {
		const f = fixture();
		expect(await f.service.setShared('space', 'alice', 't1', 'text', 'hello')).toBe(true);
		expect(await f.service.setShared('space', 'bob', 't1', 'text', 'world')).toBe(true);
		expect(f.events.publishSpaceStream).toHaveBeenLastCalledWith('space', 'shared', { tileId: 't1', key: 'text', value: 'world', rev: 2, userId: 'bob' });
		const [packed] = await f.service.getTiles('space');
		// 後から届いたほうが残る
		expect(packed.shared).toEqual({ text: { value: 'world', rev: 2 } });
	});

	test('null removes the key', async () => {
		const f = fixture();
		await f.service.setShared('space', 'alice', 't1', 'text', 'hello');
		await f.service.setShared('space', 'alice', 't1', 'text', null);
		expect((await f.service.getTiles('space'))[0].shared).toEqual({});
	});

	test('rejects a tile of another space, a bad key and an oversized value', async () => {
		const f = fixture();
		expect(await f.service.setShared('space', 'alice', 'other', 'text', 'x')).toBe(false);
		expect(await f.service.setShared('space', 'alice', 't1', '', 'x')).toBe(false);
		expect(await f.service.setShared('space', 'alice', 't1', '__proto__', 'x')).toBe(false);
		expect(await f.service.setShared('space', 'alice', 't1', 'k'.repeat(65), 'x')).toBe(false);
		expect(await f.service.setShared('space', 'alice', 't1', 'text', undefined)).toBe(false);
		expect(await f.service.setShared('space', 'alice', 't1', 'text', 'x'.repeat(SPACE_SHARED_VALUE_MAX_BYTES))).toBe(false);
		expect(f.events.publishSpaceStream).not.toHaveBeenCalled();
	});

	test('a signal is sent but not stored', async () => {
		const f = fixture();
		expect(await f.service.signal('space', 'alice', 't1', 'ring', { n: 1 })).toBe(true);
		expect(f.events.publishSpaceStream).toHaveBeenCalledWith('space', 'signal', { tileId: 't1', type: 'ring', body: { n: 1 }, userId: 'alice' });
		expect((await f.service.getTiles('space'))[0].shared).toEqual({});
		expect(await f.service.signal('space', 'alice', 'other', 'ring', null)).toBe(false);
	});

	test('values saved in the DB come back after Redis loses them', async () => {
		const f = fixture([tile({ shared: { text: 'saved' } })]);
		expect((await f.service.getTiles('space'))[0].shared).toEqual({ text: { value: 'saved', rev: 0 } });
	});

	test('flush writes changed tiles to the DB once', async () => {
		const f = fixture();
		await f.service.setShared('space', 'alice', 't1', 'text', 'hello');
		expect(await f.service.flush('space')).toBe(1);
		expect(f.rows.get('t1')?.shared).toEqual({ text: 'hello' });
		expect(await f.service.flush('space')).toBe(0);
	});

	test('closing saves the values and clears Redis', async () => {
		const f = fixture();
		await f.service.setShared('space', 'alice', 't1', 'text', 'hello');
		await f.service.closeSpace('space');
		expect(f.rows.get('t1')?.shared).toEqual({ text: 'hello' });
		expect(f.redis.hashes.size).toBe(0);
		expect(f.redis.strings.size).toBe(0);
	});

	test('a failed save is retried on the next flush', async () => {
		const f = fixture();
		await f.service.setShared('space', 'alice', 't1', 'text', 'hello');
		f.tiles.update.mockRejectedValueOnce(new Error('db down'));
		await expect(f.service.flush('space')).rejects.toThrow('db down');
		expect(await f.service.flush('space')).toBe(1);
		expect(f.rows.get('t1')?.shared).toEqual({ text: 'hello' });
	});

	test('a flush that runs after the space was closed does not wipe the saved values', async () => {
		const f = fixture();
		await f.service.setShared('space', 'alice', 't1', 'text', 'hello');
		await f.service.closeSpace('space');
		f.redis.sets.set('space:space:dirty', new Set(['t1']));
		expect(await f.service.flush('space')).toBe(0);
		expect(f.rows.get('t1')?.shared).toEqual({ text: 'hello' });
	});

	test('restoring from the DB does not overwrite a newer value', async () => {
		const f = fixture([tile({ shared: { text: 'old', keep: 1 } })]);
		f.redis.hashes.set('space:space:tile:t1:shared', new Map([['text', JSON.stringify({ v: 'new', r: 5 })]]));
		expect((await f.service.getTiles('space'))[0].shared).toEqual({ text: { value: 'new', rev: 5 }, keep: { value: 1, rev: 0 } });
	});

	test('continuing copies the tiles, their order and their saved values', async () => {
		const f = fixture([tile({ id: 'a', position: 0, shared: { text: 'kept' } }), tile({ id: 'b', position: 1, kind: 'poll' })]);
		expect(await f.service.copyTiles('space', 'next')).toBe(2);
		const copies = [...f.rows.values()].filter(row => row.spaceId === 'next');
		expect(copies).toHaveLength(2);
		expect(copies[0]).toMatchObject({ kind: 'memo', position: 0, shared: { text: 'kept' }, creatorId: 'alice' });
		expect(copies[1]).toMatchObject({ kind: 'poll', position: 1 });
	});

	test('removing a tile drops its values', async () => {
		const f = fixture();
		await f.service.setShared('space', 'alice', 't1', 'text', 'hello');
		await f.service.remove(tile());
		expect(f.events.publishSpaceStream).toHaveBeenLastCalledWith('space', 'tileRemoved', { tileId: 't1' });
		expect(await f.service.setShared('space', 'alice', 't1', 'text', 'again')).toBe(false);
	});
});
