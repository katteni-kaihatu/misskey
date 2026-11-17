/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { createServer, Agent } from 'node:http';
import { once } from 'node:events';
import { expect, test } from 'vitest';
import { HttpRequestService } from './HttpRequestService.js';

test('authenticated API calls can refuse redirects while ordinary calls retain the default', async () => {
	let destinationRequests = 0;
	const server = createServer((request, response) => {
		if (request.url === '/redirect') { response.writeHead(302, { Location: '/destination' }); response.end(); return; }
		destinationRequests++;
		response.end('ok');
	});
	server.listen(0, '127.0.0.1');
	await once(server, 'listening');
	const address = server.address();
	if (address == null || typeof address === 'string') throw new Error('Missing test address');
	const agent = new Agent();
	const service = Object.assign(Object.create(HttpRequestService.prototype), { config: { userAgent: 'test' } }) as HttpRequestService;
	Object.defineProperty(service, 'getAgentByUrl', { value: () => agent });
	try {
		const url = `http://127.0.0.1:${address.port}/redirect`;
		await expect(service.send(url, { redirect: 'error', headers: { Authorization: 'Bearer test-only' } })).rejects.toThrow();
		expect(destinationRequests).toBe(0);
		const response = await service.send(url);
		expect(await response.text()).toBe('ok');
		expect(destinationRequests).toBe(1);
	} finally { agent.destroy(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
});
