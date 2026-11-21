/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterAll, beforeAll, expect, test } from 'vitest';
import { DataSource, EntitySchema } from 'typeorm';
import { loadConfig } from '@/config.js';
import { GridspaceSearchService } from './GridspaceSearchService.js';

const config = loadConfig();
const db = new DataSource({ type: 'postgres', host: config.db.host, port: config.db.port, username: config.db.user, password: config.db.pass, database: config.db.db,
	entities: [new EntitySchema({ name: 'SearchUser', tableName: 'search_user', columns: {
		id: { type: String, primary: true }, host: { type: String, nullable: true }, isDeleted: { type: Boolean }, isSuspended: { type: Boolean },
	} })],
});
beforeAll(async () => { await db.initialize(); });
afterAll(async () => { await db.destroy(); });

test('user host filtering matches the previous predicate, including wildcard and case rules', async () => {
	const runner = db.createQueryRunner(); await runner.startTransaction();
	try {
		await runner.query('CREATE TEMP TABLE search_user (id text PRIMARY KEY, host text, "isDeleted" boolean, "isSuspended" boolean)');
		const hosts = [null, 'good.example', 'bad.example', 'sub.bad.example', 'UPPER.example', 'sub.upper.example', 'bad.example.evil', 'blocked90.example', 'wildX.example'];
		for (const [n, host] of hosts.entries()) await runner.query('INSERT INTO search_user VALUES ($1,$2,false,false)', [String(n), host]);
		await runner.query("INSERT INTO search_user VALUES ('deleted',NULL,true,false),('suspended',NULL,false,true)");
		const blockedHosts = ['bad.example', 'upper.example', 'wild_.example', ...Array.from({ length: 91 }, (_, n) => `blocked${n}.example`)];
		const service = Object.assign(Object.create(GridspaceSearchService.prototype), {
			db: { getRepository: () => ({ createQueryBuilder: () => db.createQueryBuilder('SearchUser', 'user', runner) }) }, meta: { blockedHosts },
		}) as GridspaceSearchService;
		const query = service.userQuery(null);
		const [sql, params] = query.getQueryAndParameters();
		const patterns = blockedHosts.flatMap(host => [host, `%.${host}`]);
		expect(params).toEqual(patterns);
		const actual = await runner.query(sql, params);
		const old = await runner.query('SELECT id FROM search_user WHERE "isDeleted"=false AND "isSuspended"=false AND (host IS NULL OR host NOT ILIKE ALL($1::text[])) ORDER BY id DESC', [patterns]);
		expect(actual.map((row: { user_id: string }) => row.user_id)).toEqual(old.map((row: { id: string }) => row.id));
		expect(actual.map((row: { user_id: string }) => row.user_id).sort()).toEqual(['0', '1', '6']);
	} finally { await runner.rollbackTransaction(); await runner.release(); }
});
