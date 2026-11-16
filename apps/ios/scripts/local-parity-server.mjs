/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// Run via frontend's tsx. Uses ONLY the built e2e server and its test DB/Redis.
import { randomBytes, randomUUID, timingSafeEqual, createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile, chmod, realpath, rm, rename } from 'node:fs/promises';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { basename, join, relative, resolve } from 'node:path';
import { createLocalDataSnapshot, localDataFingerprint } from '../../../packages/frontend/src/utility/local-data-transfer.ts';
import { encodeLocalDataArchive } from '../../../packages/frontend/src/utility/local-data-archive.ts';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const requireBackend = createRequire(join(root, 'packages/backend/package.json'));
const yaml = requireBackend('js-yaml');
const OTPAuth = requireBackend('otpauth');
let address = process.env.GRIDSPACE_PARITY_ADDRESS ?? '';
let peer = process.env.GRIDSPACE_PARITY_PEER ?? '';
if (process.env.GRIDSPACE_PARITY_TRANSPORT_FILE) {
	if (address || peer) throw new Error('Use either live USB transport metadata or explicit addresses');
	const transport = JSON.parse(await readFile(process.env.GRIDSPACE_PARITY_TRANSPORT_FILE, 'utf8'));
	const age = Date.now() / 1000 - transport.updatedAt;
	if (transport.version !== 1 || transport.transport !== 'wired' || !Number.isSafeInteger(transport.pid) || transport.pid <= 1
		|| !Number.isFinite(age) || age < 0 || age > 20) throw new Error('USB transport metadata is stale or invalid');
	process.kill(transport.pid, 0); // Check the owner; never signal or replace it.
	address = transport.address;
	peer = transport.peer;
}
const octets = address.split('.');
const bytes = octets.map(Number);
const privateV4 = net.isIP(address) === 4 && octets.length === 4 && bytes.every(part => part <= 255)
	&& (address === '127.0.0.1' || bytes[0] === 10 || (bytes[0] === 172 && bytes[1] >= 16 && bytes[1] <= 31) || (bytes[0] === 192 && bytes[1] === 168));
const privateV6 = net.isIP(address) === 6 && /^f[cd]/i.test(address);
if (!privateV4 && !privateV6) {
	throw new Error('GRIDSPACE_PARITY_ADDRESS must be a Mac private IP address');
}
const peerBytes = peer.split('.').map(Number);
const privatePeerV4 = net.isIP(peer) === 4 && (peerBytes[0] === 10 || (peerBytes[0] === 172 && peerBytes[1] >= 16 && peerBytes[1] <= 31) || (peerBytes[0] === 192 && peerBytes[1] === 168));
if (peer && !privatePeerV4 && !(net.isIP(peer) === 6 && /^f[cd]/i.test(peer))) throw new Error('Invalid explicit test device address');
if (address !== '127.0.0.1' && !peer) throw new Error('LAN PWA tests require an explicit private GRIDSPACE_PARITY_PEER');
if (process.env.GRIDSPACE_PARITY_ALLOW_TEST_DB_RESET !== '1') throw new Error('Explicit test DB reset flag required');
if (!process.env.GRIDSPACE_PARITY_DIRECTORY) throw new Error('A private temporary directory is required');
const directory = resolve(process.env.GRIDSPACE_PARITY_DIRECTORY);
await mkdir(directory, { recursive: true, mode: 0o700 });
const canonical = await realpath(directory);
if (!basename(canonical).startsWith('gridspace-ios-parity-')) throw new Error('Use a dedicated gridspace-ios-parity-* temporary directory');
const distance = relative(root, canonical);
if (distance !== '..' && !distance.startsWith('../')) throw new Error('Keep test credentials outside the checkout');
await chmod(canonical, 0o700);

// Refuse to kill/replace another listener. The test harness uses port 61812.
for (const [host, port] of [['127.0.0.1', 61812], [address, 61813]]) {
	const probe = net.createServer();
	await new Promise((resolve, reject) => probe.once('error', reject).listen(port, host, resolve));
	await new Promise(resolve => probe.close(resolve));
}
// A new process must not publish an old certificate/account configuration.
await rm(join(canonical, 'run.json'), { force: true });
const authority = `${privateV6 ? '[' + address + ']' : address}:61813`;
const origin = `https://${authority}`;
const config = yaml.load(await readFile(join(root, '.github/misskey/test.yml'), 'utf8'));
if (config.db.db !== 'test-misskey' || config.db.host !== '127.0.0.1' || config.db.port !== 54312 || config.redis.port !== 56312) {
	throw new Error('Unexpected e2e database configuration');
}
config.url = origin;
config.port = 61812;
config.socket = join(canonical, 'backend.sock');
config.chmodSocket = 0o600;
config.trustProxy = true;
if (process.env.GRIDSPACE_PARITY_ASSOCIATION_IDS) config.iosAppIdentifiers = JSON.parse(process.env.GRIDSPACE_PARITY_ASSOCIATION_IDS);
const configFile = join(canonical, 'test.yml');
await writeFile(configFile, yaml.dump(config), { mode: 0o600 });
const key = join(canonical, 'server-key.pem');
const certificate = join(canonical, 'server-cert.pem');
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes', '-days', '7',
	'-keyout', key, '-out', certificate, '-subj', '/CN=GridSpace local parity', '-addext', `subjectAltName=IP:${address}`,
	'-addext', 'extendedKeyUsage=serverAuth', '-addext', 'keyUsage=critical,digitalSignature,keyEncipherment',
	'-addext', 'basicConstraints=critical,CA:FALSE'], { stdio: 'ignore' });
await chmod(key, 0o600);
const der = execFileSync('openssl', ['x509', '-in', certificate, '-outform', 'DER']);
const httpUser = 'local-parity';
const httpPassword = randomBytes(32).toString('hex');
const expectedAuthorization = Buffer.from('Basic ' + Buffer.from(httpUser + ':' + httpPassword).toString('base64'));
function authorized(request) {
	const remote = request.socket.remoteAddress;
	// Product API requests deliberately use credentials: 'omit'. Keep that
	// behavior: local simulation stays on loopback; LAN tests require an exact,
	// explicit peer. This is fixture transport filtering, never Misskey auth.
	if (address === '127.0.0.1' && remote === '127.0.0.1') return true;
	if (remote === address) return true; // The Mac itself, including its simulator.
	if (peer && remote === peer) return true;
	const actual = Buffer.from(request.headers.authorization ?? '');
	return actual.length === expectedAuthorization.length && timingSafeEqual(actual, expectedAuthorization);
}
function headers(request) {
	const clean = { ...request.headers, 'x-forwarded-for': '127.0.0.1' };
	if (/^Basic /i.test(clean.authorization ?? '')) delete clean.authorization; // Keep product Bearer auth intact.
	return clean;
}

process.env.NODE_ENV = 'test';
// The backend's test mode otherwise accepts arbitrary TOTP codes. Exercise
// production verification and replay protection for this parity environment.
process.env.MISSKEY_TEST_CHECK_DUPLICATED_TOTP = '1';
process.env.MISSKEY_CONFIG_YML = configFile;
const backend = await import(new URL('../../../packages/backend/built-test/entry.js', import.meta.url));
await backend.setup({ vitest: { createCoverageProvider: async () => null } });
const recoveryPages = new Map();
const server = https.createServer({ key: await readFile(key), cert: await readFile(certificate), minVersion: 'TLSv1.2' }, (request, response) => {
	if (!authorized(request)) {
		response.writeHead(401, { 'WWW-Authenticate': 'Basic realm="GridSpace local parity"' });
		response.end();
		return;
	}
	// Private synthetic navigation fixtures; no production endpoint or account
	// is involved. The external destination contains only a synthetic marker.
	const navigationPath = new URL(request.url, origin).pathname;
	if (request.method === 'GET' && navigationPath.startsWith('/__ios-recovery/')) {
		const page = recoveryPages.get(navigationPath);
		response.writeHead(page ? 200 : 404, { 'Content-Type': 'text/html; charset=utf-8',
			'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
		response.end(page ?? 'Unknown synthetic recovery fixture');
		return;
	}
	if (request.method === 'GET' && navigationPath.startsWith('/__ios-navigation/')) {
		response.setHeader('Cache-Control', 'no-store');
		if (navigationPath === '/__ios-navigation/internal') {
			response.writeHead(302, { Location: '/__ios-navigation/result?tag=one%2Btwo&tag=two#section%202' });
			response.end(); return;
		}
		if (navigationPath === '/__ios-navigation/external') {
			response.writeHead(302, { Location: 'https://example.com/?code=synthetic-private-navigation' });
			response.end(); return;
		}
		if (['/__ios-navigation/start', '/__ios-navigation/result'].includes(navigationPath)) {
			response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'X-Content-Type-Options': 'nosniff' });
			response.end(`<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><title>Native navigation fixture</title>
				<h1>${navigationPath.endsWith('/result') ? 'Internal redirect result' : 'Native navigation fixture'}</h1>
				<p id="location"></p><p><a href="/__ios-navigation/internal">Open internal redirect</a></p>
				<p><a href="/__ios-navigation/external">Open external redirect</a></p>
				<script>document.getElementById('location').textContent = location.search + '|' + location.hash;</script>`);
			return;
		}
		response.writeHead(404); response.end(); return;
	}
	const upstream = http.request({ socketPath: config.socket, path: request.url, method: request.method, headers: headers(request) }, incoming => {
		response.writeHead(incoming.statusCode, incoming.headers);
		incoming.pipe(response);
	});
	upstream.on('error', () => { response.writeHead(502); response.end(); });
	request.pipe(upstream);
});
server.on('upgrade', (request, socket, head) => {
	if (!authorized(request)) { socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n'); return; }
	const upstream = net.connect(config.socket, () => {
		upstream.write(`${request.method} ${request.url} HTTP/${request.httpVersion}\r\n`);
		for (const [name, value] of Object.entries(headers(request))) {
			for (const item of Array.isArray(value) ? value : [value]) if (item !== undefined) upstream.write(`${name}: ${item}\r\n`);
		}
		upstream.write('\r\n');
		if (head.length) upstream.write(head);
		upstream.pipe(socket); socket.pipe(upstream);
	});
	upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy());
});
await new Promise(resolve => server.listen(61813, address, resolve));

async function api(endpoint, body, expectedErrorID) {
	return new Promise((resolve, reject) => {
		const request = http.request({ socketPath: config.socket, path: '/api/' + endpoint, method: 'POST',
			headers: { 'content-type': 'application/json', 'x-forwarded-for': '127.0.0.1', host: authority } }, response => {
			let data = '';
			response.setEncoding('utf8');
			response.on('data', chunk => { data += chunk; });
			response.on('end', () => {
				const parsed = JSON.parse(data);
				if (response.statusCode < 200 || response.statusCode >= 300) {
					if (expectedErrorID && parsed.error?.id === expectedErrorID) { resolve(parsed.error); return; }
					reject(new Error('Synthetic account setup failed (' + endpoint + '): ' + response.statusCode)); return;
				}
				if (expectedErrorID) { reject(new Error('Expected synthetic authentication refusal')); return; }
				resolve(parsed);
			});
		});
		request.on('error', () => reject(new Error('Synthetic account setup unavailable')));
		request.end(JSON.stringify(body));
	});
}
// The first account is an admin solely to permit ordinary synthetic signup.
await api('admin/accounts/create', { username: 'parity_admin', password: randomBytes(24).toString('hex'), setupPassword: config.setupPassword });
const password = randomBytes(24).toString('hex');
const user = await api('signup', { username: 'parity_user', password });
const secondPassword = randomBytes(24).toString('hex');
const secondUser = await api('signup', { username: 'parity_second', password: secondPassword });
// Simulate a persisted interrupted transaction in the isolated named Web
// store. No product endpoint, boot flag or real account is changed.
const recoveryBefore = { exists: true, value: '// Synthetic recovery before <b>literal</b>' };
const recoveryAfter = { exists: true, value: '// Synthetic recovery imported' };
const beforeHash = await localDataFingerprint(recoveryBefore);
const afterHash = await localDataFingerprint(recoveryAfter);
const scriptJSON = value => JSON.stringify(value).replaceAll('<', '\\u003c');
function recoveryBinary(seed, stage) {
	const bytes = new Uint8Array(2 * 1024 * 1024);
	for (let index = 0; index < bytes.length; index++) bytes[index] = (index * 31 + seed) & 255;
	return { binary: new Blob([bytes], { type: 'application/octet-stream' }), futureMeta: { stage, unknown: ['synthetic', null, seed] } };
}
for (const mode of ['interrupted', 'conflict', 'different-account', 'conflict-blob', 'corrupt']) {
	const journal = { id: randomUUID(), source: { origin, userId: mode === 'different-account' ? secondUser.id : user.id },
		phase: 'applying', writes: [{ location: { storage: 'local', key: 'scratchpad' },
			before: recoveryBefore, after: recoveryAfter, beforeHash, afterHash }] };
	const current = ['interrupted', 'corrupt'].includes(mode) ? recoveryAfter.value : '// Synthetic recovery current';
	if (mode === 'corrupt') {
		const repaired = structuredClone(journal);
		journal.writes[0].beforeHash = '0'.repeat(64);
		for (const complete of [false, true]) {
			recoveryPages.set('/__ios-recovery/corrupt-' + (complete ? 'complete' : 'audit'), `<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
				<title>Synthetic recovery inspection</title><p id="status">Inspecting synthetic recovery evidence</p>
				${complete ? '' : '<button id="repair" disabled>Repair synthetic journal</button>'}<script>
				(async () => {
					if (JSON.parse(localStorage.getItem('account') ?? 'null')?.id !== ${scriptJSON(user.id)}) throw new Error('Synthetic identity mismatch');
					const db = await new Promise((resolve, reject) => {
						const request = indexedDB.open('GridSpaceLocalTransfer');
						request.onupgradeneeded = () => request.transaction.abort();
						request.onsuccess = () => resolve(request.result);
						request.onerror = () => reject(new Error('Synthetic evidence unavailable'));
					});
					const transaction = db.transaction('journal', 'readonly');
					const store = transaction.objectStore('journal');
					const active = store.get('active');
					const keys = store.getAllKeys();
					await new Promise((resolve, reject) => {
						transaction.oncomplete = resolve; transaction.onabort = reject;
					});
					db.close();
					const expected = ${scriptJSON(complete ? null : journal)};
					if (JSON.stringify(active.result ?? null) !== JSON.stringify(expected)
						|| JSON.stringify(keys.result) !== JSON.stringify(${scriptJSON(complete ? [] : ['active'])})
						|| localStorage.getItem('gridspace-local-data-transfer-pending') !== ${scriptJSON(complete ? null : journal.id)}
						|| localStorage.getItem('scratchpad') !== ${scriptJSON(complete ? recoveryBefore.value : current)}) throw new Error('Synthetic evidence changed');
					document.getElementById('status').textContent = ${scriptJSON(complete ? 'Synthetic recovery completed without leftover journal' : 'Synthetic damaged recovery journal retained')};
					${complete ? '' : `
					const button = document.getElementById('repair'); button.disabled = false;
					button.addEventListener('click', async () => {
						const request = indexedDB.open('GridSpaceLocalTransfer');
						request.onsuccess = () => {
							const db = request.result;
							const transaction = db.transaction('journal', 'readwrite');
							transaction.objectStore('journal').put(${scriptJSON(repaired)}, 'active');
							transaction.oncomplete = () => { db.close(); location.replace('/scratchpad'); };
							transaction.onabort = () => { db.close(); document.getElementById('status').textContent = 'Synthetic repair failed'; };
						};
					}, { once: true });`}
				})().catch(() => { document.getElementById('status').textContent = 'Synthetic recovery evidence mismatch'; });
				</script>`);
		}
	}
	let binarySetup = '';
	if (mode === 'conflict-blob') {
		const before = { exists: true, value: recoveryBinary(7, 'before') };
		const after = { exists: true, value: recoveryBinary(19, 'imported') };
		const binaryCurrent = { exists: true, value: recoveryBinary(43, 'concurrent') };
		journal.writes.push({ location: { storage: 'idb', database: 'MisskeyAvatarWalk', store: 'atlas', key: 'avatarWalkGame::parity-recovery' },
			before, after, beforeHash: await localDataFingerprint(before), afterHash: await localDataFingerprint(after) });
		await writeFile(join(canonical, 'parity-recovery-expected.gridspace-localdata'), new Uint8Array(await encodeLocalDataArchive({
			format: 'gridspace-ios-recovery-fixture', version: 1, original: journal,
			current: [{ exists: true, value: current }, binaryCurrent],
		}).arrayBuffer()), { mode: 0o600 });
		binarySetup = `
			const makeBinary = seed => {
				const bytes = new Uint8Array(2 * 1024 * 1024);
				for (let index = 0; index < bytes.length; index++) bytes[index] = (index * 31 + seed) & 255;
				return new Blob([bytes], {type: 'application/octet-stream'});
			};
			journal.writes[1].before.value.binary = makeBinary(7);
			journal.writes[1].after.value.binary = makeBinary(19);
			const currentBinary = ${scriptJSON(binaryCurrent.value)};
			currentBinary.binary = makeBinary(43);
			await new Promise((resolve, reject) => {
				const request = indexedDB.open('MisskeyAvatarWalk');
				request.onupgradeneeded = () => request.result.createObjectStore('atlas');
				request.onerror = () => reject(new Error('Synthetic atlas unavailable'));
				request.onsuccess = () => {
					const db = request.result;
					const transaction = db.transaction('atlas', 'readwrite');
					transaction.objectStore('atlas').put(currentBinary, 'avatarWalkGame::parity-recovery');
					transaction.oncomplete = () => { db.close(); resolve(); };
					transaction.onabort = () => { db.close(); reject(new Error('Synthetic atlas aborted')); };
				};
			});`;
	}
	recoveryPages.set('/__ios-recovery/' + mode, `<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
		<title>Synthetic recovery fixture</title><p id="status">Preparing synthetic recovery fixture</p><script>
		(async () => {
			if (JSON.parse(localStorage.getItem('account') ?? 'null')?.id !== ${scriptJSON(user.id)}) throw new Error('Synthetic identity mismatch');
			const journal = ${scriptJSON(journal)};
			await navigator.locks.request('gridspace-local-data-transfer', async () => {
				${binarySetup}
				await new Promise((resolve, reject) => {
					const request = indexedDB.open('GridSpaceLocalTransfer');
					request.onupgradeneeded = () => {
						request.result.createObjectStore('journal'); request.result.createObjectStore('used');
					};
					request.onerror = () => reject(new Error('Synthetic journal unavailable'));
					request.onsuccess = () => {
						const db = request.result;
						const transaction = db.transaction('journal', 'readwrite');
						transaction.objectStore('journal').put(journal, 'active');
						transaction.oncomplete = () => { db.close(); resolve(); };
						transaction.onabort = () => { db.close(); reject(new Error('Synthetic journal aborted')); };
					};
				});
				localStorage.setItem('scratchpad', ${scriptJSON(current)});
				localStorage.setItem('gridspace-local-data-transfer-pending', journal.id);
			});
			location.replace('/scratchpad');
		})().catch(() => { document.getElementById('status').textContent = 'Synthetic recovery fixture failed'; });
		</script>`);
}
const revocationPassword = randomBytes(24).toString('hex');
const revocationUser = await api('signup', { username: 'parity_revocation', password: revocationPassword });
const revocationNote = await api('notes/create', { i: revocationUser.token, visibility: 'specified', visibleUserIds: [],
	localOnly: true, text: 'Synthetic revocable note\n[Open security settings](' + origin + '/settings/security)' });
// A self-only local note supplies a real authorization boundary for history
// tests. The synthetic body links to Settings through the ordinary Web router.
const privateText = 'Synthetic account-isolated note';
const privateNote = await api('notes/create', { i: user.token, visibility: 'specified', visibleUserIds: [],
	localOnly: true, text: privateText + '\n[Open synthetic settings](' + origin + '/settings)' });
const noteId = privateNote.createdNote.id;
const ownNote = await api('notes/show', { i: user.token, noteId });
if (!ownNote.text?.startsWith(privateText)) throw new Error('Synthetic private note must be visible to its owner');
for (const token of [undefined, secondUser.token]) {
	const hidden = await api('notes/show', { i: token, noteId });
	if (hidden.text != null || (hidden.files?.length ?? 0) !== 0) throw new Error('Synthetic private note authorization mismatch');
}
const applicationName = 'Synthetic iOS parity application';
const application = await api('miauth/gen-token', {
	i: user.token, session: randomUUID(), name: applicationName,
	description: 'Synthetic fixture for secure API parity', permission: ['read:account'],
});
// Keep the server's secure:true rule intact: a limited third-party token is
// refused, while the ordinary first-party Web session can list its own apps.
await api('i/apps', { i: application.token }, '56f35758-7dd5-468b-8439-5d6fb8ec9b8e');
const firstPartyApps = await api('i/apps', { i: user.token });
if (!firstPartyApps.some(app => app.name === applicationName)) throw new Error('Synthetic first-party app list mismatch');
// A separate synthetic identity exercises the ordinary secure 2FA endpoints.
// Its first-party token stays only in this process, never in run.json or logs.
const totpPassword = randomBytes(24).toString('hex');
const totpUser = await api('signup', { username: 'parity_totp', password: totpPassword });
if (typeof totpUser.token !== 'string') throw new Error('Synthetic signup must return a first-party token');
const totpRegistration = await api('i/2fa/register', { i: totpUser.token, password: totpPassword });
const totp = new OTPAuth.TOTP({ secret: OTPAuth.Secret.fromBase32(totpRegistration.secret), digits: 6, period: 30 });
const enrollmentCode = totp.generate();
const { backupCodes } = await api('i/2fa/done', { i: totpUser.token, token: enrollmentCode });
const possibleCodes = new Set([-30_000, 0, 30_000].map(offset => totp.generate({ timestamp: Date.now() + offset })));
let invalidCode = '000000';
while (possibleCodes.has(invalidCode)) invalidCode = String(Number(invalidCode) + 1).padStart(6, '0');
for (const code of [invalidCode, enrollmentCode]) {
	await api('signin-flow', { username: 'parity_totp', password: totpPassword, token: code }, 'cdf1235b-ac71-46d4-a3a6-84ccce48df6f');
}
const snapshot = createLocalDataSnapshot({ origin, userId: user.id, webVersion: 'local-parity-test' }, [
	{ storage: 'local', key: 'drafts', value: JSON.stringify({ [user.id + ':parity']: { text: 'Synthetic iPhone migration draft', futureField: 'keep' } }) },
	{ storage: 'local', key: 'scratchpad', value: 'Synthetic iPhone migration scratchpad' },
	{ storage: 'local', key: 'aiscript:widget:parity', value: '{"futureValue":"keep"}' },
	{ storage: 'idb', database: 'MisskeyAvatarWalk', store: 'atlas', key: 'avatarWalkGame::parity-fixture',
		value: { binary: new Blob([new Uint8Array(2 * 1024 * 1024).fill(73)], { type: 'application/octet-stream' }), futureMeta: 'keep' } },
]);
await writeFile(join(canonical, 'parity-import.gridspace-localdata'), new Uint8Array(await encodeLocalDataArchive(snapshot).arrayBuffer()), { mode: 0o600 });
const run = { environment: {
	GRIDSPACE_PARITY_ORIGIN: origin,
	GRIDSPACE_PARITY_STORE: randomUUID(),
	GRIDSPACE_PARITY_CERT_SHA256: createHash('sha256').update(der).digest('hex'),
	GRIDSPACE_PARITY_HTTP_USER: httpUser,
	GRIDSPACE_PARITY_HTTP_PASSWORD: httpPassword,
	GRIDSPACE_PARITY_USERNAME: 'parity_user',
	GRIDSPACE_PARITY_USER_ID: user.id,
	GRIDSPACE_PARITY_SECOND_USERNAME: 'parity_second',
	GRIDSPACE_PARITY_SECOND_PASSWORD: secondPassword,
	GRIDSPACE_PARITY_SECOND_USER_ID: secondUser.id,
	GRIDSPACE_PARITY_REVOCATION_USERNAME: 'parity_revocation',
	GRIDSPACE_PARITY_REVOCATION_PASSWORD: revocationPassword,
	GRIDSPACE_PARITY_REVOCATION_USER_ID: revocationUser.id,
	GRIDSPACE_PARITY_REVOCATION_NOTE_ID: revocationNote.createdNote.id,
	GRIDSPACE_PARITY_PASSWORD: password,
	GRIDSPACE_PARITY_APP_NAME: applicationName,
	GRIDSPACE_PARITY_PRIVATE_NOTE_ID: noteId,
	GRIDSPACE_PARITY_TOTP_USERNAME: 'parity_totp',
	GRIDSPACE_PARITY_TOTP_USER_ID: totpUser.id,
	GRIDSPACE_PARITY_TOTP_PASSWORD: totpPassword,
	GRIDSPACE_PARITY_TOTP_SECRET: totpRegistration.secret,
	GRIDSPACE_PARITY_BACKUP_CODE: backupCodes[0],
}, userId: user.id, snapshotID: snapshot.id, fixtureDirectory: 'ParityFixtures-' + snapshot.id };
run.environment.GRIDSPACE_PARITY_FIXTURE_FOLDER = run.fixtureDirectory;
await writeFile(join(canonical, 'run.json.tmp'), JSON.stringify(run), { mode: 0o600 });
await rename(join(canonical, 'run.json.tmp'), join(canonical, 'run.json'));
console.log('LOCAL_PARITY_READY — private run.json contains test parameters; do not print or commit it.');
let stopping = false;
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
	if (stopping) return;
	stopping = true;
	server.closeAllConnections();
	await new Promise(resolve => server.close(resolve));
	await backend.teardown();
	process.exit(0);
});
