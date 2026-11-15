/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import cluster, { type Worker } from 'node:cluster';

const backgroundWorkers = new WeakSet<Worker>();

export function forkWorker(background = false): Worker {
	const worker = cluster.fork({ MK_GRIDSPACE_DAEMONS: background ? '1' : '' });
	if (background) backgroundWorkers.add(worker);
	return worker;
}

export function replaceWorker(worker: Worker): Worker {
	return forkWorker(backgroundWorkers.has(worker));
}
