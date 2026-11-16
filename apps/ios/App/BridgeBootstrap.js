/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

(() => {
	'use strict';
	if (window !== window.top || Object.hasOwn(window, 'gridspaceNative')) return;
	const protocolVersion = 1;
	const handler = window.webkit?.messageHandlers?.gridspaceBridge;
	if (!handler) return;
	// Native owns this per-WebView control key. It is not an account credential,
	// is never sent to Web listeners, and grants no authenticated operation.
	const lifecycleKey = '__GRIDSPACE_RENDERER_LIFECYCLE_KEY__';
	let rendererHidden = true;
	const rendererListeners = Object.create(null);
	let nextRendererListener = 0;
	const resolve = Promise.resolve.bind(Promise);
	const all = Promise.all.bind(Promise);
	const rendererLifecycle = Object.freeze({
		version: 1,
		get hidden() { return rendererHidden; },
		subscribe(listener) {
			if (typeof listener !== 'function') throw new TypeError('Invalid renderer listener');
			const id = nextRendererListener++;
			rendererListeners[id] = listener;
			return () => { delete rendererListeners[id]; };
		},
		async apply(hidden, key) {
			if (typeof hidden !== 'boolean' || typeof key !== 'string' || key.length !== 64) throw new TypeError('Renderer lifecycle request refused');
			let mismatch = 0;
			for (let index = 0; index < 64; index++) mismatch |= key[index] === lifecycleKey[index] ? 0 : 1;
			if (mismatch) throw new TypeError('Renderer lifecycle request refused');
			rendererHidden = hidden;
			let count = 0, failed = false;
			const pending = [];
			for (let id = 0; id < nextRendererListener; id++) {
				const listener = rendererListeners[id];
				if (!listener) continue;
				count++;
				try { pending[pending.length] = resolve(listener(hidden)).then(() => {}, () => { failed = true; }); } catch { failed = true; }
			}
			await all(pending);
			if (failed) throw new TypeError('Renderer lifecycle invalidation failed');
			return { version: 1, supported: count > 0, hidden };
		},
	});
	const request = async (operation, payload, accountEpoch = null) => {
		const requestId = crypto.randomUUID();
		const reply = await handler.postMessage({ protocolVersion, requestId, accountEpoch, operation, payload });
		if (!reply || typeof reply.requestId !== 'string' || reply.requestId.toLowerCase() !== requestId.toLowerCase() || reply.operation !== operation
			|| typeof reply.accountEpoch !== 'string' || !reply.payload
			|| !Array.isArray(reply.payload.operations)) throw new TypeError('Invalid bridge response');
		return reply;
	};
	let sessionQueue = Promise.resolve();
	const enqueue = (action) => {
		const result = sessionQueue.then(action);
		sessionQueue = result.then(() => undefined, () => undefined);
		return result;
	};
	Object.defineProperty(window, 'gridspaceNative', {
		value: Object.freeze({
			protocolVersion,
			rendererLifecycle,
			capabilities: () => request('capabilities', {}),
			handshake: (webVersion) => enqueue(async () => {
				if (typeof webVersion !== 'string' || !webVersion || new TextEncoder().encode(webVersion).length > 128) {
					throw new TypeError('Invalid Web version');
				}
				const caps = await request('capabilities', {});
				if (caps.protocolVersion !== protocolVersion || caps.status !== 'success') return caps;
				return request('ready', { schemaVersion: 1, webVersion }, caps.accountEpoch);
			}),
			sessionChanged: (change) => enqueue(async () => {
				if (!change || Object.keys(change).sort().join(',') !== 'host,reason,userId') {
					throw new TypeError('Invalid session change');
				}
				const caps = await request('capabilities', {});
				if (caps.protocolVersion !== protocolVersion || caps.status !== 'success'
					|| !caps.payload.operations.includes('session.changed')) return caps;
				return request('session.changed', change, caps.accountEpoch);
			}),
		}),
		writable: false,
		configurable: false,
	});
})();
