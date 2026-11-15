/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterAll, beforeAll, expect, test, vi } from 'vitest';
import { DataSource } from 'typeorm';
import { loadConfig } from '@/config.js';
import { GridspaceFollowExpansionService } from './GridspaceFollowExpansionService.js';

const config = loadConfig();
const db = new DataSource({ type: 'postgres', host: config.db.host, port: config.db.port, username: config.db.user, password: config.db.pass, database: config.db.db });
beforeAll(async () => { await db.initialize(); });
afterAll(async () => { await db.destroy(); });

test('candidate SQL preserves subscriptions, pending retries, link restrictions and pagination', async () => {
	const capture = vi.fn(async () => []);
	const service = Object.assign(Object.create(GridspaceFollowExpansionService.prototype), {
		peer: { peerOrigin: 'https://peer.example' }, working: false, sourceSide: false, cursor: null, db: { query: capture },
	}) as GridspaceFollowExpansionService;
	await service['work']();
	const sql = (capture.mock.calls[0] as unknown as [string])[0];
	const runner = db.createQueryRunner();
	await runner.startTransaction();
	try {
		await runner.query(`CREATE TEMP TABLE gridspace_link ("localUserId" text, "peerUserId" text, "peerOrigin" text, state text, initiator boolean);
			CREATE TEMP TABLE "user" (id text, uri text, host text);
			CREATE TEMP TABLE following ("followerId" text, "followeeId" text);
			CREATE TEMP TABLE follow_request ("followerId" text, "followeeId" text);
			CREATE TEMP TABLE gridspace_follow_expansion ("followerId" text, "targetId" text, state text, "retryAt" timestamptz);
			INSERT INTO gridspace_link SELECT 'v' || n, 'old-v' || n, 'https://peer.example', 'active', true FROM generate_series(1,3) n;
			INSERT INTO gridspace_link SELECT 't' || lpad(n::text,2,'0'), 'old-t' || n, 'https://peer.example', 'active', true FROM generate_series(1,30) n;
			INSERT INTO "user" SELECT 'r' || n, 'https://peer.example/users/old-t' || n, 'peer.example' FROM generate_series(1,30) n;
			INSERT INTO following SELECT 'v' || v, 'r' || n FROM generate_series(1,3) v, generate_series(1,30) n;
			INSERT INTO follow_request VALUES ('v1','r1'), ('v1','r2'), ('v1','r30');
			DELETE FROM following WHERE "followerId"='v1' AND "followeeId"='r30';
			INSERT INTO following VALUES ('t01','r1');
			UPDATE gridspace_link SET state='revoked' WHERE "localUserId"='t03';
			UPDATE gridspace_link SET initiator=false WHERE "localUserId"='t04';
			UPDATE gridspace_link SET "peerOrigin"='https://other.example' WHERE "localUserId"='t05';
			UPDATE "user" SET host='other.example' WHERE id='r6';
			INSERT INTO gridspace_follow_expansion VALUES ('v1','t01','done',now()), ('v1','t02','skipped',now()),
				('v1','t07','pending',now()-interval '1 minute'), ('v1','t08','pending',now()+interval '1 hour');`);
		const original = `SELECT DISTINCT viewer."localUserId" AS "followerId", target."localUserId" AS "targetId", source.id AS "sourceId"
			FROM gridspace_link viewer JOIN (SELECT * FROM following UNION ALL SELECT * FROM follow_request) subscription ON subscription."followerId"=viewer."localUserId"
			JOIN "user" source ON source.id=subscription."followeeId" AND source.host=$2
			JOIN gridspace_link target ON source.uri=$1||'/users/'||target."peerUserId"
			LEFT JOIN gridspace_follow_expansion receipt ON receipt."followerId"=viewer."localUserId" AND receipt."targetId"=target."localUserId"
			WHERE viewer.state='active' AND viewer.initiator=true AND viewer."peerOrigin"=$1
			AND target.state='active' AND target.initiator=true AND target."peerOrigin"=$1 AND viewer."localUserId"<>target."localUserId"
			AND (receipt."followerId" IS NULL OR (receipt.state='pending' AND receipt."retryAt"<=now()))
			AND ($3::varchar IS NULL OR (viewer."localUserId",target."localUserId")>($3,$4)) ORDER BY "followerId","targetId" LIMIT 20`;
		let cursor: { followerId: string; targetId: string } | undefined;
		const all: { followerId: string; targetId: string }[] = [];
		for (let page = 0; page < 6; page++) {
			const params = ['https://peer.example', 'peer.example', cursor?.followerId ?? null, cursor?.targetId ?? null];
			const actual = await runner.query(sql, params);
			expect(actual).toEqual(await runner.query(original, params));
			if (!actual.length) break;
			all.push(...actual); cursor = actual.at(-1);
		}
		expect(all).toContainEqual({ followerId: 'v1', targetId: 't30', sourceId: 'r30' });
		expect(all).toContainEqual({ followerId: 'v1', targetId: 't07', sourceId: 'r7' });
		for (const targetId of ['t01', 't02', 't08']) expect(all).not.toContainEqual(expect.objectContaining({ followerId: 'v1', targetId }));
		expect(all.length).toBeGreaterThan(40);
	} finally { await runner.rollbackTransaction(); await runner.release(); }
});
