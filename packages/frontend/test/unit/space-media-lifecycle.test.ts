/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { EventEmitter } from 'node:events';
import { afterEach, expect, it, vi } from 'vitest';
import type * as Misskey from 'misskey-js';
import { joinSpace, leaveSpace, setSpaceMode, spaceSession } from '@/utility/space-session.js';

const connection = Object.assign(new EventEmitter(), { send: vi.fn(), dispose: vi.fn() });
const rooms: TestRoom[] = [];

class TestRoom extends EventEmitter {
	localParticipant = {
		setMicrophoneEnabled: vi.fn(async (_enabled: boolean) => {}),
		audioTrackPublications: new Map(),
	};

	remoteParticipants = new Map();
	connect = vi.fn();
	startAudio = vi.fn(async () => {});
	disconnect = vi.fn();
	canPlaybackAudio = true;

	constructor() {
		super();
		rooms.push(this);
	}
}

vi.mock('@/i.js', () => ({ $i: { id: 'viewer' } }));
vi.mock('@/stream.js', () => ({
	useStream: () => ({ on: vi.fn(), off: vi.fn(), useChannel: () => connection }),
}));
vi.mock('@/utility/misskey-api.js', () => ({ misskeyApi: async () => ({ url: '', token: '' }) }));
vi.mock('livekit-client', () => ({
	Room: TestRoom,
	RoomEvent: new Proxy({}, { get: (_target, key) => key }),
	Track: { Kind: { Audio: 'audio', Video: 'video' }, Source: { ScreenShare: 'screen_share' } },
}));

async function enter(id: string) {
	const space = { id } as Misskey.entities.Space;
	await joinSpace(space, 'listen');
	connection.emit('snapshot', { space, members: [], messages: [], tiles: [], leaderId: null });
	await vi.waitFor(() => expect(spaceSession.callStatus).toBe('connected'));
	return rooms[rooms.length - 1];
}

afterEach(() => {
	leaveSpace();
	connection.removeAllListeners();
	connection.send.mockClear();
	rooms.length = 0;
	vi.restoreAllMocks();
});

it('honors a host mute while microphone permission is pending', async () => {
	const room = await enter('first');
	const permission = Promise.withResolvers<void>();
	const mic = room.localParticipant.setMicrophoneEnabled;
	mic.mockReturnValueOnce(permission.promise);
	const pending = setSpaceMode('voice');
	await vi.waitFor(() => expect(mic).toHaveBeenCalledWith(true));
	connection.emit('muted');
	permission.resolve();
	await pending;
	await vi.waitFor(() => expect(mic).toHaveBeenLastCalledWith(false));
	expect(connection.send).not.toHaveBeenCalledWith('setMode', { mode: 'voice' });
	expect(spaceSession.mode).toBe('listen');
});

it('stops a late microphone grant and ignores audio and speakers from the previous room', async () => {
	const oldRoom = await enter('first');
	const permission = Promise.withResolvers<void>();
	oldRoom.localParticipant.setMicrophoneEnabled.mockReturnValueOnce(permission.promise);
	const pending = setSpaceMode('voice');
	await vi.waitFor(() => expect(oldRoom.localParticipant.setMicrophoneEnabled).toHaveBeenCalledWith(true));
	leaveSpace();
	connection.removeAllListeners();
	const current = await enter('second');
	permission.resolve();
	await pending;
	const attach = vi.fn();
	oldRoom.emit('TrackSubscribed', { kind: 'audio', attach }, {}, {});
	oldRoom.emit('ActiveSpeakersChanged', [{ identity: 'old' }]);
	expect(attach).not.toHaveBeenCalled();
	expect(spaceSession.speakingIds).toEqual([]);
	expect(oldRoom.localParticipant.setMicrophoneEnabled).toHaveBeenLastCalledWith(false);
	expect(current.localParticipant.setMicrophoneEnabled).not.toHaveBeenCalled();
});

it('stops the track and disconnects before announcing listen mode when disabling fails', async () => {
	const room = await enter('first');
	await setSpaceMode('voice');
	const stop = vi.fn();
	room.localParticipant.audioTrackPublications.set('mic', { source: 'microphone', track: { stop } });
	const disabling = Promise.withResolvers<void>();
	room.localParticipant.setMicrophoneEnabled.mockReturnValueOnce(disabling.promise);
	vi.spyOn(console, 'error').mockImplementation(() => {});
	const pending = setSpaceMode('listen');
	await vi.waitFor(() => expect(room.localParticipant.setMicrophoneEnabled).toHaveBeenLastCalledWith(false));
	expect(spaceSession.mode).toBe('voice');
	disabling.reject(new Error('device unavailable'));
	await pending;
	expect(stop).toHaveBeenCalledOnce();
	expect(room.disconnect).toHaveBeenCalledOnce();
	expect(spaceSession.callStatus).toBe('failed');
	expect(spaceSession.mode).toBe('listen');
});

it('stays connected in listen mode when microphone permission is denied', async () => {
	const room = await enter('first');
	vi.spyOn(console, 'error').mockImplementation(() => {});
	room.localParticipant.setMicrophoneEnabled.mockRejectedValueOnce(new Error('permission denied'));
	await setSpaceMode('voice');
	expect(room.localParticipant.setMicrophoneEnabled.mock.calls).toEqual([[true], [false]]);
	expect(connection.send).not.toHaveBeenCalledWith('setMode', { mode: 'voice' });
	expect(spaceSession.mode).toBe('listen');
	expect(spaceSession.callStatus).toBe('connected');
});
