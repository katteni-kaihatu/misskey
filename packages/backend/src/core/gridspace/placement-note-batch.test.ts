/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, expect, test, vi } from 'vitest';
import Fastify from 'fastify';
import fastifyRawBody from 'fastify-raw-body';
import { registerGridspacePeer } from '@/server/gridspace/peer-server.js';
import type { MiLocalUser } from '@/models/User.js';
import { GridspacePrivateService } from './GridspacePrivateService.js';
import { GridspaceLinkError } from './GridspaceLinkService.js';
import * as peerClient from './peer-client.js';
import { createGridspaceHeaders, type GridspacePeerConfig } from './peer-protocol.js';
import { PLACEMENT_NOTE_BATCH_PATH, readPlacementNoteBatch } from './placement-note-batch.js';
import type { PrivateNote, PrivatePage } from './private-protocol.js';

const origin = 'https://local.example';
const other = 'https://peer.example';
const peer = { origin, peerOrigin: other, keyId: 'key', communityId: 'test', secret: Buffer.alloc(32, 1) } as GridspacePeerConfig;
const viewer = { id: 'viewer' } as MiLocalUser;
const targets = Array.from({ length: 20 }, (_, i) => ({ noteId: 'note' + i, conversationUri: `${other}/notes/note${i}` }));
const page = (noteId: string): PrivatePage => ({ notes: [{ id: noteId, uri: `${other}/notes/${noteId}`, origin: other,
	author: { uri: `${other}/users/author`, host: new URL(other).host }, filterActors: [] }], next: null, head: null, scannedThrough: null, observedAt: new Date().toISOString(), validForMs: 10000 }) as PrivatePage;

afterEach(() => { vi.restoreAllMocks(); });

function fixture() {
	const check = vi.fn().mockResolvedValue(undefined);
	const destination = vi.fn().mockResolvedValue({ credential: { placementActorId: 'actor' }, peerUserId: '', check });
	const localAllows = vi.fn().mockResolvedValue(true);
	const localActorChecker = vi.fn().mockResolvedValue(async () => true);
	const filterChannelRenote = vi.fn().mockImplementation(async (_viewer, note: PrivateNote) => note);
	const service: GridspacePrivateService = Object.assign(Object.create(GridspacePrivateService.prototype), { peer, placementActions: { destination }, localAllows, localActorChecker, filterChannelRenote });
	return { service, check, destination, localAllows, localActorChecker };
}

test('one signed request retains independent scopes, omissions and bounded source concurrency', async () => {
	const { service, check, localAllows, localActorChecker } = fixture();
	const receiver = { ...peer, origin: other, peerOrigin: origin };
	const app = Fastify();
	await app.register(fastifyRawBody, { global: false, encoding: null, runFirst: true });
	let active = 0; let maxActive = 0;
	const read = vi.fn(async (name, input) => {
		expect(name).toBe('notes');
		expect(input).toEqual({ placementActorId: 'actor', ...targets.find(target => target.noteId === input.noteId), mode: 'show', limit: 1 });
		active++; maxActive = Math.max(active, maxActive);
		try {
			await new Promise(resolve => setTimeout(resolve, 1));
			if (input.noteId === 'note3') throw new GridspaceLinkError('ACTION_REJECTED');
			return page(input.noteId);
		} finally { active--; }
	});
	await app.register(async child => registerGridspacePeer(child, receiver, async () => true, undefined, undefined, undefined, undefined, read), { prefix: '/gridspace/v1' });
	const request = vi.spyOn(peerClient, 'requestGridspacePeer').mockImplementation(async (_peer, url, input) => {
		const payload = Buffer.from(JSON.stringify(input));
		const response = await app.inject({ method: 'POST', url, payload, headers: createGridspaceHeaders(peer, 'POST', url, payload) });
		expect(response.statusCode).toBe(200);
		return response.json();
	});
	localAllows.mockImplementation(async (_viewer, note) => note.id !== 'note5');
	try {
		const result = await service.placementNotes(viewer, targets, Date.now() + 5000);
		expect(request).toHaveBeenCalledOnce();
		expect(read).toHaveBeenCalledTimes(20);
		expect(maxActive).toBe(4);
		expect(result.notes.map(note => note.id)).toEqual(targets.map(target => target.noteId).filter(id => !['note3', 'note5'].includes(id)));
		expect(result.notes.every(note => !('filterActors' in note))).toBe(true);
		expect(localActorChecker).toHaveBeenCalledOnce();
		expect(check).toHaveBeenCalledOnce();
		expect(result.validForMs).toBeGreaterThan(0);
	} finally { await app.close(); }
});

test('batch endpoint rejects unsigned, oversized and mixed credential requests before reading', async () => {
	const app = Fastify(); const read = vi.fn();
	await app.register(fastifyRawBody, { global: false, encoding: null, runFirst: true });
	await app.register(async child => registerGridspacePeer(child, { ...peer, origin: other, peerOrigin: origin }, async () => true, undefined, undefined, undefined, undefined, read), { prefix: '/gridspace/v1' });
	try {
		const valid = { placementActorId: 'actor', items: targets };
		expect((await app.inject({ method: 'POST', url: PLACEMENT_NOTE_BATCH_PATH, payload: valid })).statusCode).toBe(403);
		for (const input of [{ ...valid, accessToken: 'wrong' }, { ...valid, items: [...targets, { noteId: 'extra', conversationUri: other + '/notes/extra' }] }, { ...valid, items: [targets[0], targets[0]] }]) {
			const payload = Buffer.from(JSON.stringify(input));
			expect((await app.inject({ method: 'POST', url: PLACEMENT_NOTE_BATCH_PATH, payload, headers: createGridspaceHeaders(peer, 'POST', PLACEMENT_NOTE_BATCH_PATH, payload) })).statusCode).toBe(400);
		}
		expect(read).not.toHaveBeenCalled();
	} finally { await app.close(); }
});

test('unknown source failure fails the batch instead of reporting missing notes', async () => {
	await expect(readPlacementNoteBatch({ placementActorId: 'actor', items: targets }, async () => { throw new Error('database unavailable'); })).rejects.toThrow('database unavailable');
});

test.each(['503', '404'] as const)('rolling fallback is used only for a missing endpoint (%s)', async status => {
	const { service, check } = fixture();
	const request = vi.spyOn(peerClient, 'requestGridspacePeer').mockRejectedValue(status === '404' ? new peerClient.GridspaceEndpointUnavailable() : new Error('unavailable'));
	const single = vi.spyOn(service, 'notes').mockImplementation(async (_viewer, input) => ({ notes: page(input.noteId!).notes, validForMs: 10000 }) as never);
	if (status === '503') {
		await expect(service.placementNotes(viewer, targets, Date.now() + 5000)).rejects.toMatchObject({ code: 'PEER_UNAVAILABLE' });
		expect(single).not.toHaveBeenCalled();
	} else {
		expect((await service.placementNotes(viewer, targets, Date.now() + 5000)).notes).toHaveLength(20);
		expect(single).toHaveBeenCalledTimes(20);
		expect(check).toHaveBeenCalledOnce();
	}
	expect(request).toHaveBeenCalledOnce();
});

test('fresh destination revocation after retrieval prevents returning all bodies', async () => {
	const { service, check } = fixture();
	vi.spyOn(peerClient, 'requestGridspacePeer').mockResolvedValue({ items: targets.map(target => ({ noteId: target.noteId, page: page(target.noteId) })) });
	check.mockRejectedValue(new GridspaceLinkError('AUTHORIZATION_REVOKED'));
	await expect(service.placementNotes(viewer, targets, Date.now() + 5000)).rejects.toMatchObject({ code: 'AUTHORIZATION_REVOKED' });
});

test.each(['duplicate', 'foreign', 'wrong-note', 'wrong-origin', 'invalid-expiry'] as const)('rejects a malformed response: %s', async kind => {
	const { service } = fixture();
	const items = targets.map(target => ({ noteId: target.noteId, page: page(target.noteId) }));
	if (kind === 'duplicate') items[1] = items[0];
	if (kind === 'foreign') items[0].noteId = 'foreign';
	if (kind === 'wrong-note') items[0].page.notes[0].uri = other + '/notes/foreign';
	if (kind === 'wrong-origin') items[0].page.notes[0].origin = origin;
	if (kind === 'invalid-expiry') items[0].page.validForMs = -1;
	vi.spyOn(peerClient, 'requestGridspacePeer').mockResolvedValue({ items });
	await expect(service.placementNotes(viewer, targets, Date.now() + 5000)).rejects.toMatchObject({ code: 'PEER_UNAVAILABLE' });
});
