/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import assert from 'node:assert/strict';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { isIP } from 'node:net';
import { timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';

export async function parityTransport(environment = process.env) {
	const file = environment.GRIDSPACE_PARITY_TRANSPORT_FILE;
	if (!file) {
		assert.equal(environment.GRIDSPACE_PARITY_ADDRESS ?? '127.0.0.1', '127.0.0.1', 'Use live USB metadata or loopback');
		assert.ok(!environment.GRIDSPACE_PARITY_PEER, 'Use live USB metadata or loopback');
		return { address: '127.0.0.1', peer: null };
	}
	assert.ok(!environment.GRIDSPACE_PARITY_ADDRESS && !environment.GRIDSPACE_PARITY_PEER, 'Do not mix USB metadata and addresses');
	const value = JSON.parse(await readFile(file, 'utf8'));
	const age = Date.now() / 1000 - value.updatedAt;
	assert.ok(value.version === 1 && value.transport === 'wired' && Number.isSafeInteger(value.pid) && value.pid > 1
		&& Number.isFinite(age) && age >= 0 && age <= 20, 'USB metadata is stale or invalid');
	assert.ok([value.address, value.peer].every(address => typeof address === 'string' && isIP(address) === 6 && /^f[cd]/i.test(address))
		&& value.address !== value.peer, 'USB addresses must be distinct IPv6 ULA addresses');
	process.kill(value.pid, 0); // Check only; never stop an owner from metadata.
	return { address: value.address, peer: value.peer, pid: value.pid, updatedAt: value.updatedAt };
}

export function parityOrigins(transport) {
	return transport.peer ? ['https://g.ios-parity.test:61813', 'https://r.ios-parity.test:61815']
		: ['https://127.0.0.1:61813', 'https://127.0.0.1:61815'];
}

/** Private fixture DNS for its Node workers only; no API or TLS verification changes. */
export function parityWorkerDNS(transport) {
	if (!transport.peer) return () => {};
	const original = https.Agent.prototype.createConnection;
	https.Agent.prototype.createConnection = function (options, callback) {
		const hostname = options.host ?? options.hostname;
		if (!['g.ios-parity.test', 'r.ios-parity.test'].includes(hostname)) return original.call(this, options, callback);
		return original.call(this, { ...options, lookup: (host, settings, done) => {
			if (host !== hostname) { done(new Error('Unexpected fixture DNS name')); return; }
			if (settings?.all) done(null, [{ address: '127.0.0.1', family: 4 }]);
			else done(null, '127.0.0.1', 4);
		} }, callback);
	};
	return () => { https.Agent.prototype.createConnection = original; };
}

/** App-scoped CONNECT transport, without TLS termination or system proxy changes.
 * Only the paired phone may connect, only two fixed loopback destinations are
 * reachable, and proxy authentication is separate from all Misskey credentials.
 */
export function parityConnectProxy(transport, password, isLive) {
	assert.ok(transport.peer && /^[0-9a-f]{64}$/.test(password));
	const expected = Buffer.from('Basic ' + Buffer.from('paired-parity:' + password).toString('base64'));
	const sockets = new Set();
	const audit = [];
	const server = http.createServer({ maxHeaderSize: 8192 }, (_request, response) => { response.writeHead(403); response.end(); });
	server.on('connection', socket => {
		sockets.add(socket);
		// CONNECT detaches the HTTP parser, including on rejected tunnels.
		// A client reset must close this socket rather than kill the fixture.
		socket.on('error', () => socket.destroy());
		socket.once('close', () => sockets.delete(socket));
	});
	server.on('connect', (request, socket, head) => {
		const ports = { 'g.ios-parity.test:61813': 61813, 'r.ios-parity.test:61815': 61815 };
		if (!isLive() || request.socket.remoteAddress !== transport.peer || !Object.hasOwn(ports, request.url)) {
			audit.push({ status: 403, target: Object.hasOwn(ports, request.url) ? request.url : 'other' });
			socket.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'); return;
		}
		const actual = Buffer.from(request.headers['proxy-authorization'] ?? '');
		if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
			audit.push({ status: 407, target: request.url });
			socket.end('HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="Private paired parity"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'); return;
		}
		// Preserve early TLS bytes while the upstream socket is connecting.
		socket.pause();
		const upstream = net.connect({ host: '127.0.0.1', port: ports[request.url] }, () => {
			const transfer = { status: 200, target: request.url, headBytes: head.length, sentBytes: head.length, receivedBytes: 0 };
			audit.push(transfer);
			socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
			if (head.length) upstream.write(head);
			upstream.pipe(socket); socket.pipe(upstream);
			socket.on('data', bytes => { transfer.sentBytes += bytes.length; });
			upstream.on('data', bytes => { transfer.receivedBytes += bytes.length; });
		});
		sockets.add(upstream); upstream.once('close', () => sockets.delete(upstream));
		upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy());
		socket.once('close', () => upstream.destroy());
	});
	return { server, audit, close: async () => { for (const socket of sockets) socket.destroy(); await new Promise(done => server.close(done)); } };
}
