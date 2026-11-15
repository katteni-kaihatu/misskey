/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import cluster from 'node:cluster';
import { envOption } from '@/env.js';

const timers = new Map<string, ReturnType<typeof setInterval>>();

/** The primary process owns background work, or one designated server-only worker. */
export function startGridspaceTimer(name: string, callback: () => void, interval: number): ReturnType<typeof setInterval> | undefined {
	if (envOption.noDaemons || (!cluster.isPrimary && process.env.MK_GRIDSPACE_DAEMONS !== '1') || timers.has(name)) return;
	const timer = setInterval(callback, interval);
	timer.unref();
	timers.set(name, timer);
	return timer;
}

export function stopGridspaceTimer(name: string, timer: ReturnType<typeof setInterval> | undefined): void {
	if (timer == null) return;
	clearInterval(timer);
	if (timers.get(name) === timer) timers.delete(name);
}
