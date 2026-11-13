/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import Fastify from 'fastify';
import { describe, test, expect } from 'vitest';
import { clientFrameOptions } from './client-frame-options.js';

describe('game frame policy', () => {
	test('allows the bundled runtime only from the same origin, including cache-busting queries', async () => {
		const app = Fastify();
		app.addHook('onRequest', (request, reply, done) => { reply.header('X-Frame-Options', clientFrameOptions(request.url)); done(); });
		app.get('/*', () => 'runtime');
		try {
			for (const url of ['/client-assets/doom/index.html', '/client-assets/doom/index.html?v=release']) {
				const response = await app.inject({ url });
				expect(response.headers['x-frame-options']).toBe('SAMEORIGIN');
			}
			for (const url of ['/play/doom', '/', '/client-assets/doom/player.js', '/client-assets/doom/index.html/other', '/client-assets/doom/%69ndex.html']) {
				const response = await app.inject({ url });
				expect(response.headers['x-frame-options']).toBe('DENY');
			}
		} finally { await app.close(); }
	});
});
