/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, realpathSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Keep all operations on the three checked-in test origins and loopback ports.
process.env.GRIDSPACE_LAB_PROFILE = 'multi-note';
process.env.GRIDSPACE_LAB_LOOPBACK = '1';
const { api, loadSite, sites } = await import('./lab.mjs');
const root = fileURLToPath(new URL('../../', import.meta.url));
const configDir = join(root, '.config');
const composePath = join(configDir, 'multi-note-compose.json');
const pathsFile = join(configDir, 'multi-note-repositories.json');
const [command, ...args] = process.argv.slice(2);

function setup() {
	if (args.length !== 2) throw new Error('Usage: multi-note-lab.mjs setup <R repository> <E repository>');
	const repos = [root, ...args].map(path => realpathSync(path));
	if (new Set(repos.map(path => process.platform === 'win32' ? path.toLowerCase() : path)).size !== 3) throw new Error('Use a fresh checkout for each lab site.');
	const files = new Map();
	const compose = { name: 'gridspace-multi-note', services: {}, volumes: {} };
	const dbPasswords = [];
	const peerKey = randomBytes(32).toString('base64');
	for (const [index, repo] of repos.entries()) {
		assert.equal(JSON.parse(readFileSync(join(repo, 'package.json'), 'utf8')).name, 'misskey');
		const site = sites[index];
		const role = site.role.toLowerCase();
		const database = site.dbName ?? 'misskey';
		const db = `db-${role}`;
		const redis = `redis-${role}`;
		const password = randomBytes(32).toString('hex');
		const variable = `MULTI_NOTE_DB_${site.role}_PASSWORD`;
		dbPasswords.push(`${variable}=${password}`);
		compose.services[db] = {
			image: 'postgres:18-alpine',
			environment: { POSTGRES_DB: database, POSTGRES_USER: 'gridspace', POSTGRES_PASSWORD: '${' + variable + ':?Missing test database password}' },
			ports: [`127.0.0.1:${site.dbPort}:5432`], volumes: [`${db}:/var/lib/postgresql`],
			healthcheck: { test: ['CMD', 'pg_isready', '-U', 'gridspace', '-d', database], interval: '3s', timeout: '3s', retries: 20 },
		};
		compose.services[redis] = {
			image: 'redis:7-alpine', ports: [`127.0.0.1:${site.redisPort}:6379`], volumes: [`${redis}:/data`],
			healthcheck: { test: ['CMD', 'redis-cli', 'ping'], interval: '3s', timeout: '3s', retries: 20 },
		};
		compose.volumes[db] = {};
		compose.volumes[redis] = {};
		const config = {
			url: site.origin, port: site.port, setupPassword: randomBytes(32).toString('hex'),
			db: { host: '127.0.0.1', port: site.dbPort, db: database, user: 'gridspace', pass: password },
			redis: { host: '127.0.0.1', port: site.redisPort }, id: 'aidx', clusterLimit: 1,
			fulltextSearch: { provider: 'sqlLike' }, proxyRemoteFiles: true, trustProxy: ['127.0.0.1/32', '::1/128'],
		};
		if (role !== 'e') {
			config.multiNote = { enabled: true };
			config.gridspace = {
				enabled: true, timelineEnabled: true, communityId: 'gridspace-multi-note', peerUrl: sites[1 - index].origin,
				keyId: 'multi-note-v1', secretEnv: 'GRIDSPACE_LAB_PEER_KEY', channelRole: role === 'g' ? 'client' : 'source',
			};
		}
		files.set(join(repo, '.config/gridspace-lab.yml'), JSON.stringify(config, null, 2));
		files.set(join(repo, '.config/gridspace-lab.env'), role === 'e' ? '' : `GRIDSPACE_LAB_PEER_KEY=${peerKey}`);
	}
	files.set(composePath, JSON.stringify(compose, null, 2));
	files.set(join(configDir, 'multi-note-compose.env'), dbPasswords.join('\n'));
	files.set(pathsFile, JSON.stringify(repos, null, 2));
	for (const path of files.keys()) {
		if (existsSync(path)) throw new Error(`Refusing to replace an existing lab file: ${path}`);
	}
	const created = [];
	try {
		for (const [path, data] of files) {
			writeFileSync(path, data + '\n', { flag: 'wx', mode: 0o600 });
			created.push(path);
		}
	} catch (err) {
		for (const path of created) unlinkSync(path);
		throw err;
	}
	console.log('Created isolated lab configuration for G, R and E.');
}

function run(program, argv) {
	const result = spawnSync(program, argv, { stdio: 'inherit' });
	if (result.error) throw result.error;
	if (result.status !== 0) throw new Error(`${program} exited with status ${result.status}.`);
}

if (command === 'setup') {
	setup();
} else if (command === 'seed') {
	const repos = JSON.parse(readFileSync(pathsFile, 'utf8'));
	const role = args[0]?.toUpperCase();
	if (role && !sites.some(site => site.role === role)) throw new Error('Usage: multi-note-lab.mjs seed [G|R|E]');
	for (const [index, repo] of repos.entries()) {
		const site = loadSite(repo, index);
		if (role && site.role !== role) continue;
		assert.equal((await api(site, 'meta', { detail: false })).uri, site.origin, 'Unexpected local listener.');
	}
	run(process.execPath, [fileURLToPath(new URL('./seed-lab.mjs', import.meta.url)), ...repos.slice(1), ...(role ? [role] : [])]);
} else if (command === 'tunnel') {
	const index = sites.findIndex(site => site.role === args[0]?.toUpperCase());
	if (index < 0) throw new Error('Usage: multi-note-lab.mjs tunnel G|R|E');
	const repos = JSON.parse(readFileSync(pathsFile, 'utf8'));
	const site = loadSite(repos[index], index);
	assert.equal((await api(site, 'meta', { detail: false })).uri, site.origin, 'Unexpected local listener.');
	const accounts = JSON.parse(readFileSync(site.accountsPath, 'utf8'));
	assert.equal(accounts.origin, site.origin);
	const meta = await api(site, 'admin/meta', {}, accounts.accounts.admin.token);
	assert.equal(meta.uri, site.origin);
	assert.equal(meta.disableRegistration, true);
	assert.equal(meta.federation, 'specified');
	assert.deepEqual(meta.federationHosts.toSorted(), sites.filter(other => other !== sites[index]).map(other => new URL(other.origin).host).toSorted());
	const host = new URL(site.origin).hostname.split('.')[0];
	run('ssh', ['-T', '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3', '-R', `${host}:80:127.0.0.1:${site.port}`, 'kokopi.me']);
} else {
	throw new Error('Choose setup <R repository> <E repository>, seed, or tunnel G|R|E.');
}
