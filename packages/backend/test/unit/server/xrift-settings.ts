/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test, vi } from 'vitest';
import UpdateMeta, { meta as updateMeta } from '@/server/api/endpoints/admin/update-meta.js';
import GetMeta, { meta as getMeta } from '@/server/api/endpoints/admin/meta.js';

vi.mock('@/core/MetaService.js', () => ({ MetaService: class {} }));
vi.mock('@/core/ModerationLogService.js', () => ({ ModerationLogService: class {} }));
vi.mock('@/core/SystemAccountService.js', () => ({ SystemAccountService: class {} }));

describe('XRift admin settings', () => {
	function setup() {
		const instance = { xriftApiKey: 'xrift_sk_old', policies: {} };
		const metaService = {
			fetch: vi.fn(async () => ({ ...instance })),
			update: vi.fn(async (settings) => Object.assign(instance, settings)),
		};
		const moderationLog = { log: vi.fn() };
		return {
			instance,
			metaService,
			moderationLog,
			update: new UpdateMeta(instance as never, metaService as never, moderationLog as never),
			get: new GetMeta({} as never, metaService as never, { fetch: vi.fn(async () => ({ id: 'proxy' })) } as never),
		};
	}

	test('requires administrator access for both endpoints', () => {
		expect(getMeta.requireAdmin).toBe(true);
		expect(updateMeta.requireAdmin).toBe(true);
	});

	test('returns only configured state, never the saved key', async () => {
		const { get } = setup();
		const response = await get.exec({}, null as never, null);
		expect(response.xriftApiKeyConfigured).toBe(true);
		expect(response).not.toHaveProperty('xriftApiKey');
		expect(JSON.stringify(response)).not.toContain('xrift_sk_old');
	});

	test('saves a new key and redacts before/after moderation logs', async () => {
		const { update, instance, moderationLog } = setup();
		await update.exec({ xriftApiKey: 'xrift_sk_new' }, { id: 'admin' } as never, null);
		expect(instance.xriftApiKey).toBe('xrift_sk_new');
		expect(JSON.stringify(moderationLog.log.mock.calls)).not.toContain('xrift_sk_');
		expect(moderationLog.log.mock.calls[0][2]).toMatchObject({ before: { xriftApiKey: '[redacted]' }, after: { xriftApiKey: '[redacted]' } });
	});

	test('keeps the key when updating unrelated settings', async () => {
		const { update, instance } = setup();
		await update.exec({ urlPreviewEnabled: true }, { id: 'admin' } as never, null);
		expect(instance.xriftApiKey).toBe('xrift_sk_old');
	});

	test('removes the key explicitly', async () => {
		const { update, get, instance } = setup();
		await update.exec({ xriftApiKey: null }, { id: 'admin' } as never, null);
		expect(instance.xriftApiKey).toBeNull();
		expect((await get.exec({}, null as never, null)).xriftApiKeyConfigured).toBe(false);
	});

	test.each(['xrf_cli_token', 'invalid', 'xrift_sk_bad\r\nheader', 'xrift_sk_' + 'a'.repeat(1024)])('rejects invalid key input', async xriftApiKey => {
		const { update, metaService } = setup();
		await expect(update.exec({ xriftApiKey }, { id: 'admin' } as never, null)).rejects.toMatchObject({ code: 'INVALID_PARAM' });
		expect(metaService.update).not.toHaveBeenCalled();
	});
});
