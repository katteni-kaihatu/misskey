/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { beforeAll, describe, expect, test } from 'vitest';
import { api, signup } from '../utils.js';
import type { entities } from 'misskey-js';

describe('XRift settings over HTTP', () => {
	let admin: entities.SignupResponse;
	let member: entities.SignupResponse;
	beforeAll(async () => {
		admin = await signup({ username: 'admin' });
		member = await signup({ username: 'member' });
	});
	test('only an administrator can change the key, and responses never expose it', async () => {
		const key = 'xrift_sk_fixture_only';
		expect((await api('admin/update-meta', { xriftApiKey: key }, member)).status).toBe(403);
		expect((await api('admin/meta', {}, member)).status).toBe(403);
		expect((await api('admin/update-meta', { xriftApiKey: key }, admin)).status).toBe(204);
		const settings = await api('admin/meta', {}, admin);
		expect(settings.status).toBe(200);
		expect(settings.body.xriftApiKeyConfigured).toBe(true);
		expect(JSON.stringify(settings.body)).not.toContain(key);
		const publicMeta = await api('meta', {});
		expect(publicMeta.status).toBe(200);
		expect(JSON.stringify(publicMeta.body)).not.toContain(key);
		expect((await api('admin/update-meta', { xriftApiKey: null }, admin)).status).toBe(204);
		expect((await api('admin/meta', {}, admin)).body.xriftApiKeyConfigured).toBe(false);
	});
});
