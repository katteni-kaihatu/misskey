/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import cluster, { type Worker } from 'node:cluster';
import { afterEach, expect, test, vi } from 'vitest';
import { envOption } from '@/env.js';
import { forkWorker, replaceWorker } from '@/boot/cluster-worker.js';
import { startGridspaceTimer, stopGridspaceTimer } from './background-timer.js';

const primary = cluster.isPrimary;
const noDaemons = envOption.noDaemons;
afterEach(() => {
	Object.assign(cluster, { isPrimary: primary }); envOption.noDaemons = noDaemons;
	vi.useRealTimers(); vi.unstubAllEnvs(); vi.restoreAllMocks();
});

test('only the background owner starts a timer, including server-only workers', () => {
	vi.useFakeTimers();
	envOption.noDaemons = false;
	Object.assign(cluster, { isPrimary: false });
	vi.stubEnv('MK_GRIDSPACE_DAEMONS', '');
	const callback = vi.fn();
	expect(startGridspaceTimer('test', callback, 3000)).toBeUndefined();
	vi.stubEnv('MK_GRIDSPACE_DAEMONS', '1');
	const timer = startGridspaceTimer('test', callback, 3000);
	try {
		expect(timer).toBeDefined();
		expect(startGridspaceTimer('test', callback, 3000)).toBeUndefined();
		vi.advanceTimersByTime(6000);
		expect(callback).toHaveBeenCalledTimes(2);
	} finally { stopGridspaceTimer('test', timer); }
	vi.advanceTimersByTime(3000);
	expect(callback).toHaveBeenCalledTimes(2);
});

test('primary contexts share one timer, and shutdown permits a later owner', () => {
	vi.useFakeTimers();
	envOption.noDaemons = false;
	Object.assign(cluster, { isPrimary: true });
	const callback = vi.fn();
	const timer = startGridspaceTimer('test', callback, 3000);
	try {
		expect(startGridspaceTimer('test', callback, 3000)).toBeUndefined();
		stopGridspaceTimer('test', undefined);
		vi.advanceTimersByTime(3000);
		expect(callback).toHaveBeenCalledOnce();
	} finally { stopGridspaceTimer('test', timer); }
	const replacement = startGridspaceTimer('test', callback, 3000);
	try { expect(replacement).toBeDefined(); } finally { stopGridspaceTimer('test', replacement); }
});

test('no-daemons mode disables background timers', () => {
	envOption.noDaemons = true;
	Object.assign(cluster, { isPrimary: true });
	expect(startGridspaceTimer('test', vi.fn(), 3000)).toBeUndefined();
});

test('replacement workers retain their background role without inheriting another worker role', () => {
	const spawn = vi.spyOn(cluster, 'fork').mockImplementation(() => ({} as Worker));
	const background = forkWorker(true);
	const regular = forkWorker();
	const replacement = replaceWorker(background);
	replaceWorker(replacement);
	replaceWorker(regular);
	expect(spawn.mock.calls).toEqual([
		[{ MK_GRIDSPACE_DAEMONS: '1' }], [{ MK_GRIDSPACE_DAEMONS: '' }],
		[{ MK_GRIDSPACE_DAEMONS: '1' }], [{ MK_GRIDSPACE_DAEMONS: '1' }], [{ MK_GRIDSPACE_DAEMONS: '' }],
	]);
});
