/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// Opt-in pair of actual e2e servers over loopback or one paired wired transport. No production configuration,
// test-misskey database, system trust store, or pre-existing process is changed.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID, createHash, timingSafeEqual } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { open, mkdir, readdir, readFile, writeFile, realpath, chmod, rename, rm } from 'node:fs/promises';
import https from 'node:https';
import http from 'node:http';
import net from 'node:net';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { parityTransport, parityConnectProxy, parityOrigins, parityWorkerDNS } from './parity-transport.mjs';

process.umask(0o077);
const root = fileURLToPath(new URL('../../../', import.meta.url));
const requireBackend = createRequire(join(root, 'packages/backend/package.json'));
const { Client } = requireBackend('pg');
const Redis = requireBackend('ioredis').default;
const yaml = requireBackend('js-yaml');
const signal = new AbortController();
for (const name of ['SIGINT', 'SIGTERM']) process.on(name, () => signal.abort());

async function privateDirectory(value) {
	assert.equal(typeof value, 'string', 'A private fixture directory is required');
	await mkdir(resolve(value), { recursive: true, mode: 0o700 });
	const directory = await realpath(resolve(value));
	const distance = relative(root, directory);
	assert.ok(distance.startsWith('../'), 'Keep the fixture outside the checkout');
	assert.ok(basename(directory).startsWith('gridspace-ios-parity-pair-'), 'Use a dedicated paired fixture directory');
	await chmod(directory, 0o700);
	return directory;
}

async function worker() {
	assert.equal(process.env.GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET, '1');
	const directory = await privateDirectory(dirname(process.env.MISSKEY_CONFIG_YML));
	const config = yaml.load(await readFile(process.env.MISSKEY_CONFIG_YML, 'utf8'));
	const transport = await parityTransport();
	const origins = parityOrigins(transport);
	parityWorkerDNS(transport);
	const role = config.gridspace?.channelRole === 'client' ? 'client' : 'source';
	assert.match(config.db.db, new RegExp(`^test_misskey_ios_${role}_[0-9a-f]{12}$`));
	assert.deepEqual([config.db.host, config.db.port, config.db.user, config.db.pass], ['127.0.0.1', 54312, 'postgres', '']);
	assert.deepEqual([config.redis.host, config.redis.port, config.redis.db], ['127.0.0.1', 56312, role === 'client' ? 14 : 15]);
	assert.match(config.redis.prefix, /^ios-pair-[0-9a-f]{12}-(client|source)$/);
	assert.equal(config.port, role === 'client' ? 61812 : 61814);
	assert.equal(config.socket, join(directory, role + '.sock'));
	assert.equal(config.url, origins[role === 'client' ? 0 : 1]);
	assert.equal(config.gridspace.peerUrl, origins[role === 'client' ? 1 : 0]);
	assert.equal(config.gridspace.peerTlsCaFile, join(directory, 'root-cert.pem'));
	process.env.NODE_ENV = 'test';
	// Standalone fixtures bypass the normal boot entrypoint, which initializes
	// slacc's signing thread pool. Use the real signer for peer actor requests.
	requireBackend('slacc').init(1);
	const backend = await import(new URL('../../../packages/backend/built-test/entry.js', import.meta.url));
	await backend.setupIsolated({ vitest: { createCoverageProvider: async () => null } });
	process.send?.({ ready: true });
	await new Promise(resolveStop => {
		if (signal.signal.aborted) resolveStop();
		else signal.signal.addEventListener('abort', resolveStop, { once: true });
	});
	await backend.teardownIsolated();
	process.disconnect?.();
}

async function main() {
	assert.equal(process.env.GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET, '1', 'Explicit opt-in is required');
	const directory = await privateDirectory(process.env.GRIDSPACE_PARITY_DIRECTORY);
	const transport = await parityTransport();
	const origins = parityOrigins(transport);
	const restoreDNS = parityWorkerDNS(transport);
	for (const port of [61812, 61813, 61814, 61815]) {
		const probe = net.createServer();
		await new Promise((ready, reject) => probe.once('error', reject).listen(port, '127.0.0.1', ready));
		await new Promise(done => probe.close(done));
	}
	assert.equal((await readdir(directory)).length, 0, 'Use a fresh empty fixture directory');
	const suffix = randomBytes(6).toString('hex');
	const secret = randomBytes(32).toString('base64');
	const rootCertificate = join(directory, 'root-cert.pem');
	const rootKey = join(directory, 'root-key.pem');
	const openssl = args => execFileSync('openssl', args, { stdio: 'ignore' });
	openssl(['req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes', '-days', '7', '-keyout', rootKey, '-out', rootCertificate,
		'-subj', '/CN=GridSpace isolated parity root', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign']);
	const ca = await readFile(rootCertificate);
	const adminDB = new Client({ host: '127.0.0.1', port: 54312, user: 'postgres', password: '', database: 'postgres', connectionTimeoutMillis: 10000 });
	const sites = [];
	const requestAudit = [];
	const controlSecret = randomBytes(32).toString('hex');
	const proxySecret = randomBytes(32).toString('hex');
	let connectProxy;
	let localConnectProxy;
	let control;
	let liveUntil = transport.updatedAt == null ? Infinity : transport.updatedAt * 1000 + 20000;
	await adminDB.connect();
	const transportTimer = transport.peer ? setInterval(async () => {
		try {
			const current = await parityTransport();
			assert.ok(current.address === transport.address && current.peer === transport.peer && current.pid === transport.pid);
			liveUntil = current.updatedAt * 1000 + 20000;
			await writeFile(join(directory, 'proxy-audit.json'), JSON.stringify({ wired: connectProxy?.audit ?? [], local: localConnectProxy?.audit ?? [] }), { mode: 0o600 });
		} catch { signal.abort(); }
	}, 5000) : undefined;
	const allowed = request => Date.now() < liveUntil && request.socket.remoteAddress === '127.0.0.1';
	try {
		if (transport.peer) {
			connectProxy = parityConnectProxy(transport, proxySecret, () => Date.now() < liveUntil);
			await new Promise((ready, reject) => connectProxy.server.once('error', reject).listen(61816, transport.address, ready));
			localConnectProxy = parityConnectProxy({ peer: '127.0.0.1' }, proxySecret, () => Date.now() < liveUntil);
			await new Promise((ready, reject) => localConnectProxy.server.once('error', reject).listen(61816, '127.0.0.1', ready));
		}
		for (const [index, role] of ['client', 'source'].entries()) {
			const config = yaml.load(await readFile(join(root, '.github/misskey/test.yml'), 'utf8'));
			config.url = origins[index];
			config.port = 61812 + index * 2;
			config.socket = join(directory, role + '.sock'); config.chmodSocket = '600';
			// The upstream is a private UNIX socket, with no remote IP to match a
			// CIDR. Only this loopback-filtered proxy reaches it and sets the IP.
			config.trustProxy = true;
			config.setupPassword = randomBytes(24).toString('hex');
			config.db.db = `test_misskey_ios_${role}_${suffix}`;
			config.redis.db = 14 + index; config.redis.prefix = `ios-pair-${suffix}-${role}`;
			config.allowedPrivateNetworks = ['127.0.0.1/32'];
			config.fulltextSearch = { provider: 'sqlLike' };
			config.gridspace = { enabled: true, communityId: 'ios-private-parity', keyId: 'fixture-v1', secretEnv: 'GRIDSPACE_PARITY_PAIR_KEY',
				channelRole: role, peerUrl: origins[1 - index], peerTransportUrl: `https://127.0.0.1:${index === 0 ? 61815 : 61813}`, peerTlsCaFile: rootCertificate };
			const site = { role, config, origin: config.url };
			sites.push(site);
			// An occupied config.port must survive isolated startup and shutdown.
			site.guard = net.createServer(socket => socket.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
			await new Promise((ready, reject) => site.guard.once('error', reject).listen(config.port, '127.0.0.1', ready));
			await adminDB.query(`CREATE DATABASE "${config.db.db}"`);
			site.created = true;
			const key = join(directory, role + '-key.pem'); const cert = join(directory, role + '-cert.pem');
			const csr = join(directory, role + '.csr'); const extensions = join(directory, role + '-extensions.txt');
			await writeFile(extensions, `subjectAltName=IP:127.0.0.1${transport.peer ? ',DNS:' + new URL(config.url).hostname : ''}\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n`);
			openssl(['req', '-new', '-newkey', 'rsa:2048', '-sha256', '-nodes', '-keyout', key, '-out', csr, '-subj', '/CN=GridSpace isolated parity']);
			openssl(['x509', '-req', '-in', csr, '-CA', rootCertificate, '-CAkey', rootKey, '-set_serial', String(index + 1), '-days', '7', '-sha256', '-extfile', extensions, '-out', cert]);
			site.pin = createHash('sha256').update(execFileSync('openssl', ['x509', '-in', cert, '-outform', 'DER'])).digest('hex');
			const server = https.createServer({ key: await readFile(key), cert: await readFile(cert), minVersion: 'TLSv1.2' }, (request, response) => {
				if (!allowed(request) || request.headers.host !== new URL(config.url).host) { response.writeHead(403); response.end(); return; }
				if (new URL(request.url, config.url).pathname.startsWith('/__ios-private-parity/control/')) {
					const actual = Buffer.from(request.headers['x-gridspace-parity-control'] ?? '');
					const expected = Buffer.from(controlSecret);
					if (role !== 'client' || request.method !== 'POST' || actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
						response.writeHead(403); response.end(); return;
					}
					if (!control) { response.writeHead(503); response.end(); return; }
					void control(new URL(request.url, config.url).pathname.split('/').at(-1)).then(result => {
						response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' }); response.end(JSON.stringify(result));
					}, error => {
						// Only structured, sanitized diagnostics; never a raw API body.
						console.error('Private fixture control failed', error.fixtureFailure ?? error.code ?? 'FIXTURE_ERROR');
						response.writeHead(500); response.end();
					});
					return;
				}
				const upstream = http.request({ socketPath: config.socket, method: request.method, path: request.url,
					headers: { ...request.headers, host: new URL(config.url).host, 'x-forwarded-for': '127.0.0.1', 'x-forwarded-proto': 'https' } }, incoming => {
					requestAudit.push({ role, path: new URL(request.url, config.url).pathname, status: incoming.statusCode });
					response.writeHead(incoming.statusCode, incoming.headers); incoming.pipe(response);
				});
				upstream.on('error', () => { if (!response.headersSent) response.writeHead(502); response.end(); });
				request.on('aborted', () => upstream.destroy());
				request.pipe(upstream);
			});
			server.on('tlsClientError', error => requestAudit.push({ role, tls: /^[A-Z0-9_]+$/.test(error.code) ? error.code : 'TLS_ERROR' }));
			const sockets = new Set();
			server.on('connection', socket => {
				sockets.add(socket); socket.on('error', () => socket.destroy());
				socket.once('close', () => sockets.delete(socket));
			});
			server.on('secureConnection', socket => socket.on('error', () => socket.destroy()));
			site.sockets = sockets;
			server.on('upgrade', (request, socket, head) => {
				if (!allowed(request) || request.headers.host !== new URL(config.url).host) { socket.destroy(); return; }
				const upstream = net.connect(config.socket, () => {
					upstream.write(`${request.method} ${request.url} HTTP/${request.httpVersion}\r\n`);
					for (const [name, value] of Object.entries({ ...request.headers, host: new URL(config.url).host, 'x-forwarded-for': '127.0.0.1', 'x-forwarded-proto': 'https' })) {
						for (const item of Array.isArray(value) ? value : [value]) if (item !== undefined) upstream.write(`${name}: ${item}\r\n`);
					}
					upstream.write('\r\n'); if (head.length) upstream.write(head);
					upstream.pipe(socket); socket.pipe(upstream);
				});
				upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy()); socket.on('close', () => upstream.destroy());
			});
			site.server = server;
			await new Promise((ready, reject) => server.once('error', reject).listen(61813 + index * 2, '127.0.0.1', ready));
			const file = join(directory, role + '.yml');
			await writeFile(file, yaml.dump(config), { mode: 0o600 });
			const log = await open(join(directory, role + '.log'), 'wx', 0o600);
			const child = spawn(process.execPath, [fileURLToPath(import.meta.url), '--worker'], {
				cwd: root, stdio: ['ignore', log.fd, log.fd, 'ipc'],
				env: { ...process.env, NODE_ENV: 'test', MISSKEY_CONFIG_YML: file, NODE_EXTRA_CA_CERTS: rootCertificate, GRIDSPACE_PARITY_PAIR_KEY: secret },
			});
			site.child = child;
			await log.close();
			await new Promise((ready, reject) => {
				const timer = setTimeout(() => reject(new Error(role + ' startup deadline')), 120000);
				const fail = () => { clearTimeout(timer); reject(new Error(role + ' startup failed')); };
				child.once('exit', fail); child.once('error', fail);
				child.once('message', message => {
					clearTimeout(timer); child.removeListener('exit', fail); child.removeListener('error', fail);
					message?.ready === true ? ready() : reject(new Error('Unexpected startup acknowledgment'));
				});
			});
			signal.signal.throwIfAborted();
		}
		const request = (site, path, body, options = {}) => new Promise((resolveResponse, reject) => {
			const request = https.request(new URL(path, site.origin), { ca, method: options.method ?? 'POST',
				signal: AbortSignal.any([signal.signal, AbortSignal.timeout(30000)]),
				headers: { 'content-type': options.contentType ?? (options.form ? 'application/x-www-form-urlencoded' : 'application/json'), ...options.headers } }, response => {
				let text = '';
				response.setEncoding('utf8');
				response.on('data', chunk => { text += chunk; if (text.length > 4 * 1024 * 1024) response.destroy(new Error('Fixture response too large')); });
				response.on('error', reject);
				response.on('end', () => resolveResponse({ status: response.statusCode, headers: response.headers, text }));
			});
			request.on('error', reject);
			request.end(body == null ? undefined : options.raw ? body : options.form ? String(body) : JSON.stringify(body));
		});
		const api = async (site, endpoint, body = {}, token) => {
			const response = await request(site, '/api/' + endpoint, { ...body, ...(token ? { i: token } : {}) });
			const result = response.status === 204 ? undefined : JSON.parse(response.text);
			if (response.status < 200 || response.status >= 300) {
				const code = /^[A-Z_]+$/.test(result?.error?.code) ? result.error.code : 'HTTP_ERROR';
				const reason = /^[A-Z_]{1,64}$/.test(result?.error?.info?.reason) ? result.error.info.reason : 'UNSPECIFIED';
				throw Object.assign(new Error(`${site.role} ${endpoint} ${body.action ?? ''}: ${response.status} ${code} ${reason}`), {
					fixtureFailure: { role: site.role, endpoint, status: response.status, code, reason },
				});
			}
			return result;
		};
		const account = async (site, username, admin = false) => {
			const password = randomBytes(24).toString('hex');
			return { ...await api(site, 'admin/accounts/create', { username, password, ...(admin ? { setupPassword: site.config.setupPassword } : {}) }, site.admin?.token), password };
		};
		for (const site of sites) {
			site.admin = await account(site, 'paired_admin', true);
			// Channel guests resolve their actual ActivityPub actor. Fresh instances
			// default to federation=none; authorize only the other isolated peer.
			await api(site, 'admin/update-meta', { federation: 'specified', federationHosts: [new URL(site.config.gridspace.peerUrl).host] }, site.admin.token);
		}
		const [client, source] = sites;
		await api(client, 'admin/roles/update-default-policies', { policies: { canSearchNotes: true } }, client.admin.token);
		const user = await account(client, 'paired_user'); const other = await account(client, 'paired_other');
		await api(client, 'notes/create', { text: 'Synthetic native timeline seed', visibility: 'public', localOnly: true }, other.token);
		await api(client, 'notes/create', {
			text: '**Synthetic MFM bold** [外部リンク](https://example.test/native-mfm)\n$[blur Synthetic hidden MFM]\n\\(x^2\\)',
			visibility: 'public', localOnly: true,
		}, other.token);
		const searched = await api(client, 'notes/search', { query: 'Synthetic native timeline seed' }, user.token);
		assert.ok(searched.some(note => note.text === 'Synthetic native timeline seed'), 'Synthetic native search is not enabled');
		const old = await account(source, 'paired_old'); const author = await account(source, 'paired_author');
		await api(source, 'following/create', { userId: author.id }, old.token);
		const started = await api(client, 'gridspace/link', { action: 'start' }, user.token);
		const authorization = await request(source, started.authorizationUrl, null, { method: 'GET' });
		assert.equal(authorization.status, 200, 'OAuth authorization page failed');
		const transaction = authorization.text.match(/name="misskey:oauth:transaction-id" content="([^"]+)"/)?.[1];
		assert.ok(transaction, 'OAuth transaction missing');
		const decision = await request(source, '/oauth/decision', new URLSearchParams({ transaction_id: transaction, login_token: old.token }), { form: true });
		assert.equal(decision.status, 302, 'OAuth consent failed');
		const callback = new URL(decision.headers.location);
		assert.equal(callback.origin, client.origin);
		await api(client, 'gridspace/link', { action: 'finish', code: callback.searchParams.get('code'), state: callback.searchParams.get('state'), issuer: callback.searchParams.get('iss'), clientKey: started.clientKey }, user.token);
		const grant = await api(client, 'gridspace/private-grant', {}, user.token);
		assert.equal(grant.granted, true, 'Actual private grant missing');
		const follower = (await api(source, 'notes/create', { text: 'Synthetic paired private follower body', cw: 'Synthetic paired private CW', visibility: 'followers', localOnly: true }, author.token)).createdNote;
		const channel = await api(source, 'channels/create', { name: 'Synthetic paired channel', allowRenoteToExternal: false }, author.token);
		const channelNote = (await api(source, 'notes/create', { text: 'Synthetic paired channel target', channelId: channel.id, localOnly: true }, author.token)).createdNote;
		for (const [note, channelId] of [[follower, undefined], [channelNote, channel.id]]) {
			const read = await api(client, 'gridspace/private-notes', { mode: 'show', noteId: note.id, channelId }, user.token);
			assert.equal(read.notes[0]?.text, note.text, 'Real private read mismatch');
			const refused = await request(client, '/api/gridspace/private-notes', { mode: 'show', noteId: follower.id, i: other.token });
			assert.ok(refused.status >= 400, 'Unlinked reader received private data');
		}
		const prepared = await api(client, 'gridspace/channel-post', { action: 'prepare', channelId: channel.id, renoteId: channelNote.id }, user.token);
		assert.equal(prepared.canReply, true, 'Real channel guest preparation failed');
		const prompt = await api(client, 'signin-flow', { username: user.username });
		assert.equal(prompt.finished, false, 'Normal sign-in flow failed');
		assert.equal(prompt.next, 'captcha');
		async function authorizePrivate() {
			const started = await api(client, 'gridspace/private-grant', { action: 'start' }, user.token);
			assert.equal(new URL(started.authorizationUrl).origin, source.origin);
			const authorization = await request(source, started.authorizationUrl, null, { method: 'GET' });
			assert.equal(authorization.status, 200);
			const transaction = authorization.text.match(/name="misskey:oauth:transaction-id" content="([^"]+)"/)?.[1];
			assert.ok(transaction);
			const decision = await request(source, '/oauth/decision', new URLSearchParams({ transaction_id: transaction, login_token: old.token }), { form: true });
			assert.equal(decision.status, 302);
			const callback = new URL(decision.headers.location);
			assert.equal(callback.origin, client.origin);
			await api(client, 'gridspace/private-grant', { action: 'finish', code: callback.searchParams.get('code'), state: callback.searchParams.get('state'), issuer: callback.searchParams.get('iss'), clientKey: started.clientKey }, user.token);
		}
		let socialThread;
		let socialPolls;
		let profileFixtures;
		let actionFixtures;
		let notificationFixtures;
		let emojiFixtures;
		let emojiCatalog;
		control = async action => {
			if (action === 'native-emoji-prepare') {
				if (!emojiCatalog) {
					const boundary = 'Fixture-' + randomUUID();
					const bytes = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAABJUlEQVR4nO3X0Q3CMAxF0Q7BAMzACIzPUuUPRVVL09TOtZNnKb/B9yBQuywajcZ71s97bT307s1zJzothkd0Goye8aEQiPAwEHQ4hkDHohB0IIpAh6EIdBCKQIfgCHQECkAHoAj04jgCvTQKQC+MItCL4gj0kgIgAegFcQSLD3g8X78T8T5XgHJZi6Wt7/sLYP1tRQU4RBCAwcXbpSPe5w6Q4QhAAAIQgAAEIAABdAHYe5ytPekBagIJhC4ArTE9EHYBLBEsArwQDuOtADxfh9MBRAM9BbBA8PrjsgA4jReA0c8g6qkCGBWhOn5EhMvxAhgIoTl+BITb8QJIjGAWnxHBPD4Tglt8BgT3+KgQXcOjIWDx5UwbXs7U8duZMvpopozWJJkv4yiia0UneHgAAAAASUVORK5CYII=', 'base64');
					const body = Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="synthetic-emoji.png"\r\nContent-Type: image/png\r\n\r\n`), bytes, Buffer.from(`\r\n--${boundary}--\r\n`)]);
					const uploaded = await request(client, '/api/drive/files/create', body, { raw: true, contentType: 'multipart/form-data; boundary=' + boundary, headers: { authorization: 'Bearer ' + client.admin.token } });
					assert.equal(uploaded.status, 200, 'Synthetic emoji attachment failed');
					const fileId = JSON.parse(uploaded.text).id;
					const role = await api(client, 'admin/roles/create', { name: 'Synthetic emoji restricted role', description: '', color: null, iconUrl: null, target: 'manual', condFormula: {}, isPublic: true, isModerator: false, isAdministrator: false, asBadge: false, canEditMembersByModerator: false, displayOrder: 0, policies: {} }, client.admin.token);
					for (const [name, extra] of [['native_wave', {}], ['native_sensitive', { isSensitive: true }], ['native_locked', { roleIdsThatCanBeUsedThisEmojiAsReaction: [role.id] }]]) {
						await api(client, 'admin/emoji/add', { name, fileId, aliases: ['拍手', 'synthetic cheer'], category: 'Synthetic emoji', ...extra }, client.admin.token);
					}
					emojiCatalog = true;
				}
				const tag = randomBytes(4).toString('hex');
				const target = (await api(client, 'notes/create', { text: 'Synthetic emoji picker target ' + tag, visibility: 'home', localOnly: true }, other.token)).createdNote;
				emojiFixtures = { tag, target: target.id, writes: requestAudit.filter(item => item.role === 'client' && item.path === '/api/notes/reactions/create' && item.status === 204).length };
				return { emojiNoteID: target.id, emojiTag: tag };
			}
			if (action === 'native-emoji-status') {
				assert.ok(emojiFixtures);
				const note = await api(client, 'notes/show', { noteId: emojiFixtures.target }, user.token);
				const notes = await api(client, 'users/notes', { userId: user.id, limit: 100 }, user.token);
				return { emojiReaction: note.myReaction ?? null, emojiReactionCount: Object.values(note.reactions).reduce((a, b) => a + b, 0),
					emojiWrites: requestAudit.filter(item => item.role === 'client' && item.path === '/api/notes/reactions/create' && item.status === 204).length - emojiFixtures.writes,
					emojiComposedTexts: notes.filter(item => item.text?.startsWith('Synthetic native emoji ')).map(item => item.text) };
			}

			if (action === 'native-notifications-prepare') {
				if (!notificationFixtures) {
					const tag = randomBytes(4).toString('hex');
					let firstFollower;
					for (let index = 0; index < 31; index++) {
						const fan = await account(client, 'nf_' + tag.slice(0, 4) + '_' + String(index).padStart(2, '0'));
						await api(client, 'following/create', { userId: user.id }, fan.token);
						if (index === 0) firstFollower = fan;
					}
					const root = (await api(client, 'notes/create', { text: 'Synthetic native notification root ' + tag, visibility: 'home', localOnly: true }, user.token)).createdNote;
					await api(client, 'notes/create', { text: 'Synthetic native notification reply ' + tag, replyId: root.id, visibility: 'home', localOnly: true }, firstFollower.token);
					await api(client, 'notes/reactions/create', { noteId: root.id, reaction: '👍' }, firstFollower.token);
					notificationFixtures = { tag, firstFollower: firstFollower.id };
				}
				await api(client, 'notifications/create', { header: 'Synthetic native notice header ' + notificationFixtures.tag, body: '**Synthetic native notification body**' }, user.token);
				for (let attempt = 0; attempt < 50; attempt++) {
					const follows = await api(client, 'i/notifications', { markAsRead: false, includeTypes: ['follow'], limit: 100 }, user.token);
					const apps = await api(client, 'i/notifications', { markAsRead: false, includeTypes: ['app'], limit: 100 }, user.token);
					if (follows.length >= 31 && apps.some(item => item.header === 'Synthetic native notice header ' + notificationFixtures.tag)) break;
					assert.ok(attempt < 49, 'Synthetic notification delivery deadline');
					await new Promise(done => setTimeout(done, 100));
				}
				return { notificationTag: notificationFixtures.tag, notificationFirstFollowerID: notificationFixtures.firstFollower };
			}
			if (action === 'native-notifications-status') {
				const account = await api(client, 'i', {}, user.token);
				return { notificationUnreadCount: account.unreadNotificationsCount,
					notificationReadAttempts: requestAudit.filter(item => item.role === 'client' && item.path === '/api/notifications/mark-all-as-read').length,
					notificationReadWrites: requestAudit.filter(item => item.role === 'client' && item.path === '/api/notifications/mark-all-as-read' && item.status === 204).length };
			}
			if (action === 'native-actions-prepare') {
				const tag = randomBytes(4).toString('hex');
				const author = await account(client, 'na_' + tag);
				const target = (await api(client, 'notes/create', { text: 'Synthetic native reshare target ' + tag, visibility: 'home', localOnly: true }, author.token)).createdNote;
				actionFixtures = { tag, author, target: target.id };
				return { actionTag: tag, actionTargetID: target.id };
			}
			if (action === 'native-actions-restrict') {
				assert.ok(actionFixtures);
				await api(client, 'i/update', { makeNotesFollowersOnlyBefore: Math.floor(Date.now() / 1000) + 3600 }, actionFixtures.author.token);
				const target = await api(client, 'notes/show', { noteId: actionFixtures.target }, user.token);
				assert.equal(target.isHidden, true, 'Actual server must hide the restricted target');
				return { restricted: true };
			}
			if (action === 'native-actions-status') {
				assert.ok(actionFixtures);
				const notes = await api(client, 'users/notes', { userId: user.id, withRenotes: true, limit: 100 }, user.token);
				const own = notes.filter(note => note.renoteId === actionFixtures.target);
				const target = await api(client, 'notes/show', { noteId: actionFixtures.target }, actionFixtures.author.token);
				return { actionReshareIDs: own.filter(note => note.text === null && note.cw === null && note.files.length === 0 && !note.poll).map(note => note.id),
					actionQuoteIDs: own.filter(note => note.text !== null || note.cw !== null || note.files.length > 0 || note.poll).map(note => note.id),
					actionTexts: own.map(note => note.text), actionVisibilities: own.map(note => note.visibility), actionLocalOnly: own.map(note => note.localOnly), actionTargetExists: target.id === actionFixtures.target };
			}
			if (action === 'native-auth' || action === 'native-auth-notifications-read-only') {
				const session = randomUUID();
				const permission = ['read:account', 'write:notes', 'read:notifications', 'write:reactions', 'read:drive', 'write:drive', 'write:votes', 'write:following', 'write:notifications'];
				await api(client, 'miauth/gen-token', { session, name: 'Synthetic native parity', permission: action === 'native-auth' ? permission : permission.filter(value => value !== 'write:notifications') }, user.token);
				return { session };
			}
			if (action === 'native-status') {
				const notes = await api(client, 'users/notes', { userId: user.id, limit: 100 }, user.token);
				const own = notes.filter(note => note.text === 'Synthetic native device draft');
				return { nativeNoteCount: own.length, nativeNoteVisibility: own[0]?.visibility, nativeNoteCW: own[0]?.cw };
			}
			if (action === 'native-attachment-status') {
				const notes = await api(client, 'users/notes', { userId: user.id, limit: 100 }, user.token);
				const own = notes.filter(note => note.text === null && note.files?.length === 2);
				const files = await api(client, 'drive/stream', { limit: 100 }, user.token);
				return { attachmentNoteCount: own.length, attachmentNames: own[0]?.files.map(file => file.name),
					attachmentSensitive: own[0]?.files.map(file => file.isSensitive), attachmentComments: own[0]?.files.map(file => file.comment),
					attachmentDriveCount: files.length, attachmentHashes: own[0]?.files.map(file => files.find(item => item.id === file.id)?.md5) };
			}
			if (action === 'native-profile-prepare') {
				if (!profileFixtures) {
					const publicUser = await account(client, 'np_public');
					const locked = await account(client, 'np_locked');
					const privateUser = await account(client, 'np_private');
					await api(client, 'i/update', { description: 'Synthetic native profile description', fields: [{ name: 'Synthetic profile field', value: 'Synthetic field value' }] }, publicUser.token);
					await api(client, 'i/update', { isLocked: true }, locked.token);
					await api(client, 'i/update', { followersVisibility: 'private', followingVisibility: 'private' }, privateUser.token);
					const tag = randomBytes(4).toString('hex');
					const create = async (actor, text, extra = {}) => (await api(client, 'notes/create', { text, visibility: 'home', localOnly: true, ...extra }, actor.token)).createdNote;
					for (let index = 0; index < 31; index++) await create(publicUser, 'Synthetic profile post ' + String(index).padStart(2, '0'));
					const marker = await create(publicUser, 'Synthetic public profile marker ' + tag);
					await create(publicUser, 'Synthetic profile reply item', { replyId: marker.id });
					await create(locked, 'Synthetic locked profile marker ' + tag);
					await create(privateUser, 'Synthetic private profile marker ' + tag);
					const boundary = 'Fixture-' + randomUUID();
					const bytes = Buffer.from('Synthetic native profile attachment\n');
					const body = Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="synthetic-profile.txt"\r\nContent-Type: application/octet-stream\r\n\r\n`), bytes, Buffer.from(`\r\n--${boundary}--\r\n`)]);
					const uploaded = await request(client, '/api/drive/files/create', body, { raw: true, contentType: 'multipart/form-data; boundary=' + boundary, headers: { authorization: 'Bearer ' + publicUser.token } });
					assert.equal(uploaded.status, 200, 'Synthetic profile attachment failed');
					await create(publicUser, 'Synthetic profile media item', { fileIds: [JSON.parse(uploaded.text).id] });
					let firstFan;
					for (let index = 0; index < 31; index++) {
						const fan = await account(client, 'np_fan_' + String(index).padStart(2, '0'));
						await api(client, 'following/create', { userId: publicUser.id }, fan.token);
						if (index === 0) { firstFan = fan.id; await api(client, 'following/create', { userId: fan.id }, publicUser.token); }
					}
					profileFixtures = { publicID: publicUser.id, lockedID: locked.id, privateID: privateUser.id, firstFan, tag };
				}
				for (const id of [profileFixtures.publicID, profileFixtures.lockedID]) {
					const current = await api(client, 'users/show', { userId: id }, user.token);
					if (current.isFollowing) await api(client, 'following/delete', { userId: id }, user.token);
					else if (current.hasPendingFollowRequestFromYou) await api(client, 'following/requests/cancel', { userId: id }, user.token);
				}
				return { profilePublicID: profileFixtures.publicID, profileLockedID: profileFixtures.lockedID, profilePrivateID: profileFixtures.privateID, profileFirstFanID: profileFixtures.firstFan, profileTag: profileFixtures.tag };
			}
			if (action === 'native-profile-status') {
				assert.ok(profileFixtures);
				const publicUser = await api(client, 'users/show', { userId: profileFixtures.publicID }, user.token);
				const locked = await api(client, 'users/show', { userId: profileFixtures.lockedID }, user.token);
				return { profileFollowing: publicUser.isFollowing, profilePending: publicUser.hasPendingFollowRequestFromYou, lockedFollowing: locked.isFollowing, lockedPending: locked.hasPendingFollowRequestFromYou };
			}
			if (action === 'native-social-prepare') {
				if (!socialThread) {
					const privateAuthor = await account(client, 'social_private');
					const hidden = (await api(client, 'notes/create', { text: 'Synthetic hidden conversation ancestor', visibility: 'public', localOnly: true }, privateAuthor.token)).createdNote;
					const createReply = async (text, replyId) => (await api(client, 'notes/create', { text, replyId, visibility: 'followers', localOnly: true }, user.token)).createdNote;
					const root = await createReply('Synthetic visible conversation ancestor', hidden.id);
					const parent = await createReply('Synthetic conversation parent', root.id);
					const target = await createReply('Synthetic conversation target', parent.id);
					for (let index = 0; index < 31; index++) await createReply('Synthetic conversation reply ' + String(index).padStart(2, '0'), target.id);
					await api(client, 'i/update', { makeNotesFollowersOnlyBefore: Math.floor(Date.now() / 1000) + 3600 }, privateAuthor.token);
					const ancestors = await api(client, 'notes/conversation', { noteId: target.id }, user.token);
					assert.ok(ancestors.some(note => note.id === hidden.id && note.isHidden === true), 'Private ancestor must be hidden by the actual packer');
					socialThread = { target: target.id };
				}
				const tag = randomBytes(4).toString('hex');
				const createPoll = async (name, multiple, expiresAt) => (await api(client, 'notes/create', {
					text: `Synthetic native ${name} poll ${tag}`, visibility: 'followers', localOnly: true,
					poll: { choices: ['Native choice A', 'Native choice B'], multiple, expiresAt },
				}, user.token)).createdNote;
				const single = await createPoll('single', false, Date.now() + 3600000);
				const multiple = await createPoll('multiple', true, Date.now() + 3600000);
				const expiry = Date.now() + 2000;
				const expired = await createPoll('expired', false, expiry);
				await new Promise(done => setTimeout(done, Math.max(0, expiry - Date.now() + 20)));
				const rejected = await request(client, '/api/notes/polls/vote', { i: user.token, noteId: expired.id, choice: 0 });
				assert.equal(rejected.status, 400); assert.equal(JSON.parse(rejected.text).error.code, 'ALREADY_EXPIRED');
				socialPolls = { single: single.id, multiple: multiple.id, expired: expired.id };
				return { socialTag: tag, socialTargetID: socialThread.target };
			}
			if (action === 'native-social-status') {
				assert.ok(socialThread && socialPolls, 'Prepare the synthetic social fixtures first');
				const single = await api(client, 'notes/show', { noteId: socialPolls.single }, user.token);
				const multiple = await api(client, 'notes/show', { noteId: socialPolls.multiple }, user.token);
				const expired = await api(client, 'notes/show', { noteId: socialPolls.expired }, user.token);
				const replies = await api(client, 'notes/replies', { noteId: socialThread.target, limit: 100 }, user.token);
				return { singleVotes: single.poll.choices.map(choice => choice.votes), multipleVotes: multiple.poll.choices.map(choice => choice.votes),
					expiredVotes: expired.poll.choices.map(choice => choice.votes), deviceReplies: replies.filter(note => note.text === 'Synthetic native conversation device reply').length };
			}
			if (action === 'rename') {
				const name = 'Updated paired author native';
				await api(source, 'i/update', { name }, author.token);
				return { name };
			}
			if (action === 'revoke') await api(client, 'gridspace/private-grant', { action: 'revoke' }, user.token);
			else if (action === 'authorize') await authorizePrivate();
			else if (action !== 'status') throw new Error('Unknown isolated fixture control');
			const state = await api(client, 'gridspace/private-grant', {}, user.token);
			const post = await api(client, 'gridspace/channel-post', { action: 'prepare', channelId: channel.id }, user.token);
			return { granted: state.granted, canPostChannel: post.canReply };
		};
		assert.equal((await request(client, '/__ios-private-parity/control/revoke', {})).status, 403, 'Fixture controls must require their private secret');
		const snapshotID = randomUUID();
		const run = { snapshotID, fixtureDirectory: 'ParityFixtures-' + snapshotID, environment: {
			GRIDSPACE_PARITY_ORIGIN: client.origin, GRIDSPACE_PARITY_CERT_SHA256: client.pin,
			GRIDSPACE_PARITY_HTTP_USER: 'private-paired-fixture', GRIDSPACE_PARITY_HTTP_PASSWORD: controlSecret, GRIDSPACE_PARITY_PAIR_CONTROL: 'v1',
			GRIDSPACE_PARITY_PEER_ORIGIN: source.origin, GRIDSPACE_PARITY_PEER_CERT_SHA256: source.pin,
			...(transport.peer ? { GRIDSPACE_PARITY_PROXY_ADDRESS: transport.address, GRIDSPACE_PARITY_PROXY_PASSWORD: proxySecret } : {}),
			GRIDSPACE_PARITY_STORE: randomUUID(), GRIDSPACE_PARITY_USERNAME: user.username, GRIDSPACE_PARITY_PASSWORD: user.password,
			GRIDSPACE_PARITY_USER_ID: user.id, GRIDSPACE_PARITY_SECOND_USERNAME: other.username, GRIDSPACE_PARITY_SECOND_PASSWORD: other.password, GRIDSPACE_PARITY_SECOND_USER_ID: other.id,
			GRIDSPACE_PARITY_PRIVATE_NOTE_ID: follower.id, GRIDSPACE_PARITY_CHANNEL_ID: channel.id, GRIDSPACE_PARITY_CHANNEL_NOTE_ID: channelNote.id,
		}, pair: { client: { origin: client.origin, user, other }, source: { origin: source.origin, old, author }, follower, channel, channelNote, rootCertificate } };
		await writeFile(join(directory, 'run.json.tmp'), JSON.stringify(run), { mode: 0o600 });
		await rename(join(directory, 'run.json.tmp'), join(directory, 'run.json'));
		console.log('PRIVATE_PARITY_READY — private run.json contains synthetic paired credentials; do not print or commit it.');
		await new Promise(resolveStop => {
			if (signal.signal.aborted) resolveStop();
			else signal.signal.addEventListener('abort', resolveStop, { once: true });
		});
	} finally {
		clearInterval(transportTimer);
		await connectProxy?.close();
		await localConnectProxy?.close();
		for (const site of sites) { site.server?.closeAllConnections(); for (const socket of site.sockets ?? []) socket.destroy(); }
		await Promise.all(sites.map(async site => {
			if (site.server) await new Promise(done => site.server.close(done));
			const child = site.child;
			if (child && child.exitCode == null && child.signalCode == null) {
				child.kill('SIGTERM');
				await new Promise(done => { const timer = setTimeout(done, 15000); child.once('exit', () => { clearTimeout(timer); done(); }); });
				if (child.exitCode == null && child.signalCode == null) { child.kill('SIGKILL'); await new Promise(done => child.once('exit', done)); }
			}
			if (site.guard) {
				assert.equal(site.guard.listening, true, 'Isolated teardown closed an unrelated listener');
				await new Promise(done => site.guard.close(done));
			}
			const redis = new Redis({ host: '127.0.0.1', port: 56312, db: site.config.redis.db, lazyConnect: true, connectTimeout: 5000, maxRetriesPerRequest: 1 });
			try {
				await redis.connect();
				let cursor = '0';
				do {
					const [next, keys] = await redis.scan(cursor, 'MATCH', site.config.redis.prefix + ':*', 'COUNT', 500);
					if (keys.length) await redis.unlink(...keys);
					cursor = next;
				} while (cursor !== '0');
			} finally { redis.disconnect(); }
			if (site.created) {
				// Local storage uses repository/files even for an isolated DB. Only
				// delete exact storage keys read from this run's owned database.
				const storageDB = new Client({ host: '127.0.0.1', port: 54312, user: 'postgres', database: site.config.db.db });
				try {
					await storageDB.connect();
					const table = await storageDB.query("SELECT to_regclass('public.drive_file') AS name");
					if (table.rows[0].name) {
						const files = await storageDB.query('SELECT "accessKey", "thumbnailAccessKey", "webpublicAccessKey" FROM drive_file WHERE "storedInternal" = true');
						let removed = 0;
						for (const file of files.rows) for (const key of Object.values(file)) {
							if (key === null) continue;
							assert.match(key, /^(?:thumbnail-|webpublic-)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
							await rm(join(root, 'files', key), { force: true }); removed++;
						}
						await writeFile(join(directory, site.role + '-storage-cleanup.json'), JSON.stringify({ removed }), { mode: 0o600 });
					}
				} finally { await storageDB.end(); }
				await adminDB.query(`DROP DATABASE "${site.config.db.db}" WITH (FORCE)`);
			}
		}));
		await writeFile(join(directory, 'request-audit.json'), JSON.stringify(requestAudit), { mode: 0o600 });
		await adminDB.end();
		await rm(join(directory, 'run.json'), { force: true });
		restoreDNS();
	}
}

try { if (process.argv.includes('--worker')) await worker(); else await main(); }
catch (error) {
	if (!(signal.signal.aborted && error instanceof Error && error.name === 'AbortError')) {
		// A requested shutdown must still report failures in its cleanup.
		console.error(error instanceof Error ? error.message : 'Private pair fixture failed');
		process.exitCode = 1;
	}
}
