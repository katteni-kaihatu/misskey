/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test } from 'vitest';
import { resolveSpacesConfig } from './spaces-config.js';

const env = { SPACES_TEST_SECRET: 'not-a-real-secret' };
const source = { enabled: true, livekit: { url: 'wss://livekit.example', apiKey: 'key', apiSecretEnv: 'SPACES_TEST_SECRET' } };

describe('Spaces configuration', () => {
	test('does not enable a missing or disabled configuration', () => {
		expect(resolveSpacesConfig(undefined, {})).toBeNull();
		expect(resolveSpacesConfig({}, {})).toBeNull();
		expect(resolveSpacesConfig({ ...source, enabled: false }, {})).toBeNull();
	});

	test('resolves the browser URL, the server URL and the secret', () => {
		expect(resolveSpacesConfig(source, env)).toEqual({
			livekit: { url: 'wss://livekit.example', httpUrl: 'https://livekit.example', apiKey: 'key', apiSecret: 'not-a-real-secret' },
		});
	});

	test('maps a local ws:// URL to http://', () => {
		const resolved = resolveSpacesConfig({ ...source, livekit: { ...source.livekit, url: 'ws://localhost:7880/' } }, env);
		expect(resolved?.livekit).toMatchObject({ url: 'ws://localhost:7880', httpUrl: 'http://localhost:7880' });
	});

	test.each(['https://livekit.example', 'livekit.example', 'wss://livekit.example/rtc', 'wss://user:pass@livekit.example', 'wss://livekit.example?x=1', 'wss://livekit.example#x', undefined])('rejects invalid LiveKit URL %s', url => {
		expect(() => resolveSpacesConfig({ ...source, livekit: { ...source.livekit, url } }, env)).toThrow('livekit.url');
	});

	test('rejects a non-boolean enabled, a missing section and a missing key', () => {
		expect(() => resolveSpacesConfig({ ...source, enabled: 'yes' as unknown as boolean }, env)).toThrow('boolean');
		expect(() => resolveSpacesConfig({ enabled: true }, env)).toThrow('livekit section');
		expect(() => resolveSpacesConfig({ ...source, livekit: { ...source.livekit, apiKey: '' } }, env)).toThrow('apiKey');
	});

	test('rejects an absent secret without including a value in the error', () => {
		expect(() => resolveSpacesConfig(source, {})).toThrow('environment variable');
		expect(() => resolveSpacesConfig({ ...source, livekit: { ...source.livekit, apiSecretEnv: 'not-a-real-secret' } }, env)).toThrow('must name an environment variable');
	});
});
