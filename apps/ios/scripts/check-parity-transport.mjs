/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

// Exercise the restricted proxy with real TLS to the owned paired backend.
import assert from 'node:assert/strict';
import { readFile, realpath } from 'node:fs/promises';
import { basename, join } from 'node:path';
import net from 'node:net';
import tls from 'node:tls';
import { createHash } from 'node:crypto';
import { parityConnectProxy } from './parity-transport.mjs';

const directory = await realpath(process.argv[2]);
assert.ok(basename(directory).startsWith('gridspace-ios-parity-pair-'));
const run = JSON.parse(await readFile(join(directory, 'run.json'), 'utf8'));
assert.equal(run.pair.client.origin, 'https://g.ios-parity.test:61813');
const ca = await readFile(join(directory, 'root-cert.pem'));
const password = '9'.repeat(64); // Only this temporary proxy, never an account credential.
let live = true;
const proxy = parityConnectProxy({ peer: '127.0.0.1' }, password, () => live);
await new Promise((done, reject) => proxy.server.once('error', reject).listen(0, '127.0.0.1', done));
const port = proxy.server.address().port;
const credential = 'Basic ' + Buffer.from('paired-parity:' + password).toString('base64');
async function connect(authority, auth = credential) {
	const socket = net.connect({ host: '127.0.0.1', port });
	socket.setTimeout(5000, () => socket.destroy(new Error('Fixture CONNECT deadline')));
	return new Promise((done, reject) => {
		let bytes = Buffer.alloc(0);
		socket.once('error', reject);
		socket.once('connect', () => socket.write(`CONNECT ${authority} HTTP/1.1\r\nHost: ${authority}\r\n${auth ? 'Proxy-Authorization: ' + auth + '\r\n' : ''}\r\n`));
		const receive = chunk => {
			bytes = Buffer.concat([bytes, chunk]);
			if (!bytes.includes('\r\n\r\n')) return;
			socket.off('data', receive);
			const status = Number(bytes.toString('ascii').match(/^HTTP\/1\.1 ([0-9]+)/)?.[1]);
			if (status !== 200) socket.destroy();
			done({ status, socket });
		};
		socket.on('data', receive);
	});
}
async function resetRejectedTunnel(authority, expectedStatus, auth = credential) {
	const socket = net.connect({ host: '127.0.0.1', port });
	await new Promise((done, reject) => {
		let response = '';
		socket.setTimeout(5000, () => socket.destroy(new Error('Fixture reset deadline')));
		socket.once('error', reject);
		socket.once('connect', () => socket.write(`CONNECT ${authority} HTTP/1.1\r\nHost: ${authority}\r\nProxy-Authorization: ${auth}\r\n\r\n`));
		socket.on('data', chunk => {
			response += chunk.toString('ascii');
			if (!response.includes('\r\n\r\n')) return;
			try { assert.match(response, new RegExp(`^HTTP/1.1 ${expectedStatus} `)); }
			catch (error) { socket.destroy(); reject(error); return; }
			socket.resetAndDestroy();
		});
		socket.once('close', () => { try { assert.ok(response.includes('\r\n\r\n')); done(); } catch (error) { reject(error); } });
	});
}
try {
	await resetRejectedTunnel('example.com:443', 403);
	await resetRejectedTunnel('g.ios-parity.test:61813', 407, 'Basic invalid');
	for (const authority of ['example.com:443', 'g.ios-parity.test:61815', 'g.ios-parity.test:443', '127.0.0.1:61813', 'g.ios-parity.test:61813@evil.test']) {
		assert.equal((await connect(authority)).status, 403);
	}
	assert.equal((await connect('g.ios-parity.test:61813', '')).status, 407);
	assert.equal((await connect('g.ios-parity.test:61813', 'Basic invalid')).status, 407);
	live = false;
	assert.equal((await connect('g.ios-parity.test:61813')).status, 403);
	live = true;
	for (const [host, targetPort, pin] of [['g.ios-parity.test', 61813, run.environment.GRIDSPACE_PARITY_CERT_SHA256], ['r.ios-parity.test', 61815, run.environment.GRIDSPACE_PARITY_PEER_CERT_SHA256]]) {
		const { status, socket } = await connect(host + ':' + targetPort);
		assert.equal(status, 200);
		await new Promise((done, reject) => {
			const secure = tls.connect({ socket, servername: host, ca, rejectUnauthorized: true }, () => {
				assert.equal(secure.authorized, true);
				assert.equal(createHash('sha256').update(secure.getPeerCertificate().raw).digest('hex'), pin, 'CONNECT must leave the actual backend certificate untouched');
				secure.write(`GET / HTTP/1.1\r\nHost: ${host}:${targetPort}\r\nConnection: close\r\n\r\n`);
			});
			let response = '';
			secure.on('data', chunk => { response += chunk; if (response.length > 4 * 1024 * 1024) secure.destroy(new Error('Fixture response limit')); });
			secure.once('error', reject);
			secure.once('end', () => { try { assert.match(response, /^HTTP\/1\.1 200 /); done(); } catch (error) { reject(error); } });
		});
	}
	console.log('PASS: rejected CONNECT resets, authentication, destination allowlist, expiry and end-to-end TLS for both actual backends');
} finally { await proxy.close(); }
