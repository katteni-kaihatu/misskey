/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { computed, reactive, ref, shallowReactive } from 'vue';
import type * as Misskey from 'misskey-js';
import { $i } from '@/i.js';
import { useStream } from '@/stream.js';

const SEND_INTERVAL_MS = 100;
const HEARTBEAT_INTERVAL_MS = 5000;

export type AvatarWalkConnectionStatus = 'unavailable' | 'connecting' | 'connected';

export const avatarWalkLocalPlayer = reactive({
	x: 800,
	y: 600,
	direction: 0,
	moving: false,
});

export const avatarWalkRemotePlayers = shallowReactive(new Map<string, Misskey.AvatarWalkPlayer>());
export const avatarWalkConnectionStatus = ref<AvatarWalkConnectionStatus>($i == null ? 'unavailable' : 'connecting');
export const avatarWalkOnlineCount = computed(() => avatarWalkConnectionStatus.value === 'connected'
	? avatarWalkRemotePlayers.size + 1
	: 0);

let consumers = 0;
let connection: Misskey.IChannelConnection<Misskey.Channels['avatarWalkRoom']> | null = null;
let sendTimerId: number | null = null;
let lastSentAt = 0;
let lastSentState = '';
let localSharedAtlas: Misskey.AvatarWalkSharedAtlasInput | null = null;

export function setAvatarWalkSharedAtlas(atlas: Misskey.AvatarWalkSharedAtlasInput | null): void {
	if (JSON.stringify(localSharedAtlas) === JSON.stringify(atlas)) return;
	localSharedAtlas = atlas;
	sendSharedAtlas();
}

export function acquireAvatarWalkMultiplayer(): () => void {
	consumers++;
	if (consumers === 1) connect();

	let released = false;
	return () => {
		if (released) return;
		released = true;
		consumers = Math.max(0, consumers - 1);
		if (consumers === 0) disconnect();
	};
}

function connect(): void {
	if ($i == null || connection != null) return;

	avatarWalkConnectionStatus.value = 'connecting';
	const stream = useStream();
	connection = stream.useChannel('avatarWalkRoom', { roomId: 'main' });
	connection.on('snapshot', onSnapshot);
	connection.on('joined', onJoined);
	connection.on('moved', onMoved);
	connection.on('atlasUpdated', onAtlasUpdated);
	connection.on('left', onLeft);
	stream.on('_disconnected_', onDisconnected);
	stream.on('_connected_', onStreamConnected);

	lastSentAt = 0;
	lastSentState = '';
	sendTimerId = window.setInterval(sendLocalState, SEND_INTERVAL_MS);
}

function disconnect(): void {
	if (sendTimerId != null) {
		window.clearInterval(sendTimerId);
		sendTimerId = null;
	}

	if (connection != null) {
		const stream = useStream();
		stream.off('_disconnected_', onDisconnected);
		stream.off('_connected_', onStreamConnected);
		connection.dispose();
	}
	connection = null;
	avatarWalkRemotePlayers.clear();
	avatarWalkConnectionStatus.value = $i == null ? 'unavailable' : 'connecting';
}

function onSnapshot(payload: { players: Misskey.AvatarWalkPlayer[] }): void {
	const presentUserIds = new Set<string>();
	for (const player of payload.players) {
		presentUserIds.add(player.user.id);
		if (player.user.id === $i?.id) {
			avatarWalkLocalPlayer.x = player.x;
			avatarWalkLocalPlayer.y = player.y;
			avatarWalkLocalPlayer.direction = player.direction;
			avatarWalkLocalPlayer.moving = false;
		} else {
			avatarWalkRemotePlayers.set(player.user.id, player);
		}
	}

	for (const userId of avatarWalkRemotePlayers.keys()) {
		if (!presentUserIds.has(userId)) avatarWalkRemotePlayers.delete(userId);
	}
	avatarWalkConnectionStatus.value = 'connected';
	sendLocalState();
	sendSharedAtlas();
}

function onJoined(player: Misskey.AvatarWalkPlayer): void {
	if (player.user.id === $i?.id) return;
	avatarWalkRemotePlayers.set(player.user.id, player);
}

function onMoved(movement: Misskey.AvatarWalkMovement): void {
	if (movement.userId === $i?.id) return;
	const player = avatarWalkRemotePlayers.get(movement.userId);
	if (player == null || movement.updatedAt < player.updatedAt) return;
	avatarWalkRemotePlayers.set(movement.userId, {
		...player,
		...movement,
	});
}

function onAtlasUpdated(payload: { userId: string; atlas: Misskey.AvatarWalkSharedAtlas | null }): void {
	if (payload.userId === $i?.id) return;
	const player = avatarWalkRemotePlayers.get(payload.userId);
	if (player == null) return;
	avatarWalkRemotePlayers.set(payload.userId, { ...player, atlas: payload.atlas });
}

function onLeft(payload: { userId: string }): void {
	if (payload.userId !== $i?.id) avatarWalkRemotePlayers.delete(payload.userId);
}

function onDisconnected(): void {
	avatarWalkConnectionStatus.value = 'connecting';
}

function onStreamConnected(): void {
	avatarWalkConnectionStatus.value = 'connecting';
}

function sendLocalState(): void {
	if (connection == null || avatarWalkConnectionStatus.value !== 'connected') return;
	const state = JSON.stringify(avatarWalkLocalPlayer);
	const now = Date.now();
	if (state === lastSentState && now - lastSentAt < HEARTBEAT_INTERVAL_MS) return;

	connection.send('move', {
		x: avatarWalkLocalPlayer.x,
		y: avatarWalkLocalPlayer.y,
		direction: avatarWalkLocalPlayer.direction,
		moving: avatarWalkLocalPlayer.moving,
	});
	lastSentState = state;
	lastSentAt = now;
}

function sendSharedAtlas(): void {
	if (connection == null || avatarWalkConnectionStatus.value !== 'connected') return;
	connection.send('setAtlas', localSharedAtlas);
}
