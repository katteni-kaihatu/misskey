/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { reactive } from 'vue';
import type * as Misskey from 'misskey-js';
import type { Room, Track } from 'livekit-client';
import { $i } from '@/i.js';
import { useStream } from '@/stream.js';
import { misskeyApi } from '@/utility/misskey-api.js';

/**
 * 参加中のスペースを1つ持つ。ストリーミングと LiveKit の両方をここで握る。
 * ページを移っても参加が続くよう、画面のコンポーネントではなくこのモジュールが接続を持つ。
 */

const HEARTBEAT_INTERVAL_MS = 5000;
const JOIN_TIMEOUT_MS = 10000;
/** 共有する値の決まり。サーバーと同じ */
const SHARED_KEY_MAX_LENGTH = 64;
const SHARED_VALUE_MAX_BYTES = 256 * 1024;

export type SpaceEndReason = 'ended' | 'replaced' | 'kicked' | 'failed';
export type SpaceCallStatus = 'off' | 'connecting' | 'connected' | 'failed';

export const spaceSession = reactive({
	status: 'idle' as 'idle' | 'connecting' | 'joined',
	space: null as Misskey.entities.Space | null,
	members: [] as Misskey.SpaceMember[],
	messages: [] as Misskey.SpaceMessage[],
	mode: 'listen' as Misskey.SpaceMode,
	/** スピーカーを切っているとき true。通話にはつないだまま、自分の側で音を止める */
	speakerMuted: false,
	callStatus: 'off' as SpaceCallStatus,
	/** いま話している人 */
	speakingIds: [] as string[],
	/** マイクが入っている人 */
	micOnIds: [] as string[],
	/** ホストにマイクを切られた直後だけ true。画面が知らせを出したら false に戻す */
	mutedByHost: false,
	/** 直前のスペースから出された理由と、そのスペース */
	lastEnd: null as { spaceId: string; reason: SpaceEndReason } | null,
	/** 担当のユーザー ID。全員の手元で同時に起きる出来事を、1人だけで実行するための役 */
	leaderId: null as string | null,
	/** 置いてあるタイル。並び順どおり。値は getSpaceShared で読む */
	tiles: [] as Misskey.entities.SpaceTile[],
	/** いま出ている画面共有。映像そのものは attachSpaceScreen で画面の要素につなぐ */
	screenShares: [] as { id: string; userId: string }[],
	/** 自分が画面を共有しているとき true */
	sharingScreen: false,
	/** ブラウザが音を鳴らすのを止めているとき true。画面が「音声を再生」のボタンを出す */
	audioBlocked: false,
	/** いま開いているスペースのページの ID。参加中のスペース自身のページでだけ、小さな操作バーを隠す */
	pageSpaceId: null as string | null,
});

let connection: Misskey.IChannelConnection<Misskey.Channels['space']> | null = null;
let heartbeatTimerId: number | null = null;
let joinTimerId: number | null = null;
/** つなぎ直したあと、snapshot が来るまで true。その間は送っても届かないので送らない */
let awaitingSnapshot = false;
let room: Room | null = null;
/** 通話の接続をやり直すたびに増やす。古い接続の結果を捨てるのに使う */
let callGeneration = 0;
const audioElements = new Set<HTMLMediaElement>();

type TileListener = {
	shared: (key: string, value: unknown, userId: string) => void;
	signal: (type: string, body: unknown, userId: string) => void;
};
/** タイルが共有する値。タイルの ID → キー → 値。画面は直接見ず、タイルの枠が読む */
const sharedValues = new Map<string, Map<string, unknown>>();
/** 自分が書いて、まだサーバーから戻ってきていない書き込みの数。キーは「タイルの ID + 改行 + キー」 */
const pendingWrites = new Map<string, number>();
const tileListeners = new Map<string, Set<TileListener>>();
/** 画面共有の映像。キーは spaceSession.screenShares の id */
const screenTracks = new Map<string, Track>();

/** 画面を共有できるブラウザか。スマホのブラウザは見る側だけになる。 */
export const canShareSpaceScreen = typeof navigator.mediaDevices?.getDisplayMedia === 'function';

export function isInSpace(spaceId: string): boolean {
	return spaceSession.status !== 'idle' && spaceSession.space?.id === spaceId;
}

/** 入る。「入る」ボタンを押した操作の中で呼ぶこと (音を出す許可を取るため)。 */
export async function joinSpace(space: Misskey.entities.Space, mode: Misskey.SpaceMode): Promise<void> {
	if ($i == null) return;
	if (spaceSession.status !== 'idle') leaveSpace();

	spaceSession.status = 'connecting';
	spaceSession.space = space;
	spaceSession.members = [];
	spaceSession.messages = [];
	spaceSession.mode = mode;
	spaceSession.speakerMuted = false;
	spaceSession.lastEnd = null;
	spaceSession.mutedByHost = false;

	const stream = useStream();
	stream.on('_connected_', onStreamReconnected);
	stream.on('_disconnected_', onStreamDisconnected);
	connection = stream.useChannel('space', { spaceId: space.id, mode });
	connection.on('snapshot', onSnapshot);
	connection.on('joined', onJoined);
	connection.on('left', onLeft);
	connection.on('memberUpdated', onMemberUpdated);
	connection.on('message', onMessage);
	connection.on('updated', onUpdated);
	connection.on('leader', (payload) => {
		spaceSession.leaderId = payload.userId;
	});
	connection.on('tileAdded', onTileAdded);
	connection.on('tileUpdated', onTileUpdated);
	connection.on('tileRemoved', onTileRemoved);
	connection.on('tilesMoved', onTilesMoved);
	connection.on('shared', onShared);
	connection.on('signal', onSignal);
	connection.on('ended', () => close('ended'));
	connection.on('replaced', () => close('replaced'));
	connection.on('kicked', () => close('kicked'));
	connection.on('muted', onMuted);

	heartbeatTimerId = window.setInterval(() => {
		if (spaceSession.status === 'joined') connection?.send('heartbeat', {});
	}, HEARTBEAT_INTERVAL_MS);
	startJoinTimer();
}

export function leaveSpace(): void {
	close(null);
}

/** サーバーが接続を断ったときは何も返ってこないので、snapshot が来るまでの時間で見切る。 */
function startJoinTimer(): void {
	if (joinTimerId != null) window.clearTimeout(joinTimerId);
	joinTimerId = window.setTimeout(() => {
		joinTimerId = null;
		if (spaceSession.status !== 'idle') close('failed');
	}, JOIN_TIMEOUT_MS);
}

/** ストリーミングが切れたとき。つなぎ直して snapshot が来るまで、送っても届かないので送らない。 */
function onStreamDisconnected(): void {
	if (spaceSession.status !== 'idle') awaitingSnapshot = true;
}

/** ストリーミングがつなぎ直されたとき。チャンネルは入り直しになるので、snapshot が来るかを見張る。 */
function onStreamReconnected(): void {
	if (spaceSession.status === 'idle') return;
	awaitingSnapshot = true;
	startJoinTimer();
}

function close(reason: SpaceEndReason | null): void {
	const spaceId = spaceSession.space?.id ?? null;
	if (heartbeatTimerId != null) window.clearInterval(heartbeatTimerId);
	if (joinTimerId != null) window.clearTimeout(joinTimerId);
	heartbeatTimerId = null;
	joinTimerId = null;
	awaitingSnapshot = false;
	useStream().off('_connected_', onStreamReconnected);
	useStream().off('_disconnected_', onStreamDisconnected);
	connection?.dispose();
	connection = null;
	disconnectCall();
	spaceSession.status = 'idle';
	spaceSession.space = null;
	spaceSession.members = [];
	spaceSession.messages = [];
	spaceSession.tiles = [];
	spaceSession.leaderId = null;
	sharedValues.clear();
	pendingWrites.clear();
	spaceSession.mode = 'listen';
	spaceSession.speakerMuted = false;
	spaceSession.lastEnd = (reason != null && spaceId != null) ? { spaceId, reason } : null;
}

/** チャットに書く。送れたら true。 */
export function sayInSpace(text: string): boolean {
	if (spaceSession.status !== 'joined' || awaitingSnapshot || connection == null) return false;
	connection.send('say', { text });
	return true;
}

/** 入り方 (話す / 聞くだけ) を変える。通話につないでいる途中なら、つながった時点の入り方でマイクが決まる。 */
export async function setSpaceMode(mode: Misskey.SpaceMode): Promise<void> {
	if (spaceSession.space == null || spaceSession.status !== 'joined') return;
	if (mode === spaceSession.mode) return;
	spaceSession.mode = mode;
	connection?.send('setMode', { mode });
	if (room != null) await setMicrophone(room, mode === 'voice');
}

/** スピーカーを切る、入れる。通話にはつないだまま、この画面で鳴らす音だけを止める。 */
export function toggleSpaceSpeaker(): void {
	spaceSession.speakerMuted = !spaceSession.speakerMuted;
	for (const element of audioElements) element.muted = spaceSession.speakerMuted;
}

export async function toggleSpaceMicrophone(): Promise<void> {
	await setSpaceMode(spaceSession.mode === 'voice' ? 'listen' : 'voice');
}

// ---- ストリーミング ----

function onSnapshot(payload: { space: Misskey.entities.Space; members: Misskey.SpaceMember[]; messages: Misskey.SpaceMessage[]; tiles: Misskey.SpaceTileWithShared[]; leaderId: string | null }): void {
	if (joinTimerId != null) window.clearTimeout(joinTimerId);
	joinTimerId = null;
	awaitingSnapshot = false;
	spaceSession.space = payload.space;
	spaceSession.members = payload.members;
	spaceSession.messages = payload.messages;
	spaceSession.leaderId = payload.leaderId;
	applyTileSnapshot(payload.tiles);
	const reconnected = spaceSession.status === 'joined';
	spaceSession.status = 'joined';
	if (reconnected) {
		// つなぎ直しのときは、つないだ時点の入り方で入り直している。いまの入り方に合わせる
		connection?.send('setMode', { mode: spaceSession.mode });
	} else {
		// 通話には、スペースに入れたことが分かってからつなぐ
		void connectCall(payload.space.id);
	}
}

function onJoined(member: Misskey.SpaceMember): void {
	spaceSession.members = [...spaceSession.members.filter(m => m.user.id !== member.user.id), member];
}

function onLeft(payload: { userId: string }): void {
	spaceSession.members = spaceSession.members.filter(m => m.user.id !== payload.userId);
}

function onMemberUpdated(payload: { userId: string; mode: Misskey.SpaceMode }): void {
	spaceSession.members = spaceSession.members.map(m => m.user.id === payload.userId ? { ...m, mode: payload.mode } : m);
}

function onMessage(message: Misskey.SpaceMessage): void {
	// 入った直後は、snapshot に入っている発言がもう一度届くことがある
	if (spaceSession.messages.some(m => m.id === message.id)) return;
	spaceSession.messages = [...spaceSession.messages, message].slice(-200);
}

function onUpdated(payload: Pick<Misskey.entities.Space, 'name' | 'access' | 'tilePlacement'>): void {
	if (spaceSession.space != null) spaceSession.space = { ...spaceSession.space, ...payload };
}

function onMuted(): void {
	if (spaceSession.mode !== 'voice') return;
	spaceSession.mutedByHost = true;
	void setSpaceMode('listen');
}

// ---- タイル ----

function sameValue(a: unknown, b: unknown): boolean {
	return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
}

function applyTileSnapshot(tiles: Misskey.SpaceTileWithShared[]): void {
	pendingWrites.clear();
	const presentIds = new Set(tiles.map(tile => tile.id));
	for (const tileId of [...sharedValues.keys()]) {
		if (!presentIds.has(tileId)) sharedValues.delete(tileId);
	}
	for (const tile of tiles) {
		const previous = sharedValues.get(tile.id) ?? new Map<string, unknown>();
		const next = new Map(Object.entries(tile.shared).map(([key, entry]) => [key, entry.value]));
		sharedValues.set(tile.id, next);
		// つなぎ直しのときは、切れている間に変わった値をタイルに伝える
		for (const key of new Set([...previous.keys(), ...next.keys()])) {
			if (!sameValue(previous.get(key), next.get(key))) emitShared(tile.id, key, next.get(key) ?? null, '');
		}
	}
	spaceSession.tiles = tiles.map(({ shared: _, ...tile }) => tile);
}

function emitShared(tileId: string, key: string, value: unknown, userId: string): void {
	for (const listener of tileListeners.get(tileId) ?? []) listener.shared(key, value, userId);
}

function onTileAdded(tile: Misskey.entities.SpaceTile): void {
	if (!sharedValues.has(tile.id)) sharedValues.set(tile.id, new Map());
	spaceSession.tiles = [...spaceSession.tiles.filter(t => t.id !== tile.id), tile].sort((a, b) => a.position - b.position);
}

/** 許したドメインや「ホストだけが操作できる」が変わった。並びと値はそのまま。 */
function onTileUpdated(tile: Misskey.entities.SpaceTile): void {
	spaceSession.tiles = spaceSession.tiles.map(t => t.id === tile.id ? { ...tile, position: t.position } : t);
}

function onTileRemoved(payload: { tileId: string }): void {
	sharedValues.delete(payload.tileId);
	for (const pendingKey of [...pendingWrites.keys()]) {
		if (pendingKey.startsWith(`${payload.tileId}\n`)) pendingWrites.delete(pendingKey);
	}
	spaceSession.tiles = spaceSession.tiles.filter(tile => tile.id !== payload.tileId);
}

function onTilesMoved(payload: { tileIds: string[] }): void {
	const order = new Map(payload.tileIds.map((tileId, index) => [tileId, index]));
	spaceSession.tiles = spaceSession.tiles
		.map(tile => ({ ...tile, position: order.get(tile.id) ?? tile.position }))
		.sort((a, b) => a.position - b.position);
}

function onShared(payload: { tileId: string; key: string; value: unknown; userId: string }): void {
	const values = sharedValues.get(payload.tileId);
	if (values == null) return;
	if (payload.userId === $i?.id) {
		// 自分の書き込みが戻ってきた。あとから書いたものがまだ戻っていなければ、古い値で画面を巻き戻さない
		const pendingKey = `${payload.tileId}\n${payload.key}`;
		const pending = pendingWrites.get(pendingKey) ?? 0;
		if (pending > 1) {
			pendingWrites.set(pendingKey, pending - 1);
			return;
		}
		pendingWrites.delete(pendingKey);
	}
	if (sameValue(values.get(payload.key), payload.value)) return;
	if (payload.value == null) values.delete(payload.key); else values.set(payload.key, payload.value);
	emitShared(payload.tileId, payload.key, payload.value ?? null, payload.userId);
}

function onSignal(payload: { tileId: string; type: string; body: unknown; userId: string }): void {
	for (const listener of tileListeners.get(payload.tileId) ?? []) listener.signal(payload.type, payload.body, payload.userId);
}

/** タイルが共有する値の、いまの中身。 */
export function getSpaceShared(tileId: string): Record<string, unknown> {
	return Object.fromEntries(sharedValues.get(tileId) ?? []);
}

/** 共有する値を書く。手元にはすぐ反映し、サーバーへ送る。value が null ならキーを消す。 */
export function setSpaceShared(tileId: string, key: string, value: unknown): void {
	const values = sharedValues.get(tileId);
	if (values == null || spaceSession.status !== 'joined' || awaitingSnapshot || connection == null) return;
	// サーバーが受け付けない書き込みは、送らない。送ると、戻りを待つ数だけがずれて残る
	if (key.length < 1 || key.length > SHARED_KEY_MAX_LENGTH || key === '__proto__') return;
	if (new Blob([JSON.stringify(value ?? null)]).size > SHARED_VALUE_MAX_BYTES) return;
	if (value == null) values.delete(key); else values.set(key, value);
	const pendingKey = `${tileId}\n${key}`;
	pendingWrites.set(pendingKey, (pendingWrites.get(pendingKey) ?? 0) + 1);
	connection.send('setShared', { tileId, key, value: value ?? null });
}

/** 保存しない一時的な知らせを、その場にいる人に送る。 */
export function sendSpaceSignal(tileId: string, type: string, body: unknown): void {
	if (spaceSession.status !== 'joined' || awaitingSnapshot || connection == null) return;
	connection.send('signal', { tileId, type, body: body ?? null });
}

/** タイルの値の変化と知らせを受け取る。返す関数を呼ぶと受け取りをやめる。 */
export function onSpaceTileEvent(tileId: string, listener: TileListener): () => void {
	const listeners = tileListeners.get(tileId) ?? new Set<TileListener>();
	tileListeners.set(tileId, listeners);
	listeners.add(listener);
	return () => {
		listeners.delete(listener);
		if (listeners.size === 0) tileListeners.delete(tileId);
	};
}

// ---- 通話 (LiveKit) ----

async function connectCall(spaceId: string): Promise<void> {
	const generation = ++callGeneration;
	spaceSession.callStatus = 'connecting';
	try {
		// スペースに入るときだけ読み込む
		const { Room, RoomEvent, Track } = await import('livekit-client');
		const { url, token } = await misskeyApi('spaces/token', { spaceId });
		if (generation !== callGeneration) return;

		const newRoom = new Room({ adaptiveStream: true, dynacast: true });
		room = newRoom;

		newRoom.on(RoomEvent.TrackSubscribed, (track, publication, participant) => {
			if (track.kind === Track.Kind.Video) {
				if (room === newRoom && publication.source === Track.Source.ScreenShare) addScreenShare(publication.trackSid, participant.identity, track);
				return;
			}
			if (track.kind !== Track.Kind.Audio) return;
			const element = track.attach();
			element.style.display = 'none';
			element.muted = spaceSession.speakerMuted;
			window.document.body.appendChild(element);
			audioElements.add(element);
		});
		newRoom.on(RoomEvent.TrackUnsubscribed, (track, publication) => {
			if (track.kind === Track.Kind.Video) {
				if (room === newRoom) removeScreenShare(publication.trackSid);
				return;
			}
			for (const element of track.detach()) {
				element.remove();
				audioElements.delete(element);
			}
		});
		// 自分の画面共有。ブラウザの「共有を停止」で止めたときも、ここで片づく
		newRoom.on(RoomEvent.LocalTrackPublished, (publication) => {
			if (room !== newRoom || publication.source !== Track.Source.ScreenShare || publication.track == null) return;
			addScreenShare(publication.trackSid, newRoom.localParticipant.identity, publication.track);
			spaceSession.sharingScreen = true;
		});
		newRoom.on(RoomEvent.LocalTrackUnpublished, (publication) => {
			if (room !== newRoom || publication.source !== Track.Source.ScreenShare) return;
			removeScreenShare(publication.trackSid);
			spaceSession.sharingScreen = false;
		});
		newRoom.on(RoomEvent.AudioPlaybackStatusChanged, () => {
			if (room === newRoom) spaceSession.audioBlocked = !newRoom.canPlaybackAudio;
		});
		newRoom.on(RoomEvent.ActiveSpeakersChanged, (speakers) => {
			spaceSession.speakingIds = speakers.map(speaker => speaker.identity);
		});
		for (const event of [
			RoomEvent.TrackMuted, RoomEvent.TrackUnmuted, RoomEvent.TrackPublished, RoomEvent.TrackUnpublished,
			RoomEvent.LocalTrackPublished, RoomEvent.LocalTrackUnpublished, RoomEvent.ParticipantConnected, RoomEvent.ParticipantDisconnected,
		] as const) {
			newRoom.on(event, () => refreshMicrophones(newRoom));
		}
		newRoom.on(RoomEvent.Disconnected, () => {
			if (room !== newRoom) return;
			// 追い出しや終了ではストリーミングの知らせが先に来て、ここには来ない。来たら通話だけ切れたものとして扱う
			room = null;
			removeAudioElements();
			clearScreenShares();
			spaceSession.callStatus = 'failed';
			spaceSession.speakingIds = [];
			spaceSession.micOnIds = [];
			spaceSession.audioBlocked = false;
		});

		await newRoom.connect(url, token);
		if (generation !== callGeneration) {
			void newRoom.disconnect();
			return;
		}
		// 操作なしに音を鳴らすことをブラウザが止める場合がある。止められたら、画面に「音声を再生」を出す
		await newRoom.startAudio().catch(() => undefined);
		if (generation !== callGeneration || room !== newRoom) return;
		spaceSession.audioBlocked = !newRoom.canPlaybackAudio;
		spaceSession.callStatus = 'connected';
		// つないでいる間に入り方が変わった (ホストにマイクを切られた、など) 場合があるので、いまの入り方で決める
		if (spaceSession.mode === 'voice') await setMicrophone(newRoom, true);
		refreshMicrophones(newRoom);
	} catch (err) {
		if (generation !== callGeneration) return;
		console.error('failed to connect to the space call', err);
		disconnectCall();
		spaceSession.callStatus = 'failed';
	}
}

/** 通話につなぎ直す。「通話につながりません」の画面から呼ぶ。 */
export async function retrySpaceCall(): Promise<void> {
	const space = spaceSession.space;
	if (space == null) return;
	disconnectCall();
	await connectCall(space.id);
}

/** ブラウザに止められた音を鳴らす。ボタンを押した操作の中で呼ぶこと。 */
export async function resumeSpaceAudio(): Promise<void> {
	const target = room;
	if (target == null) return;
	await target.startAudio().catch(() => undefined);
	if (room === target) spaceSession.audioBlocked = !target.canPlaybackAudio;
}

async function setMicrophone(target: Room, enabled: boolean): Promise<void> {
	if (room !== target) return;
	try {
		await target.localParticipant.setMicrophoneEnabled(enabled);
	} catch (err) {
		// マイクの許可が下りなかった場合など。聞くだけに戻す
		console.error('failed to switch the microphone', err);
		if (room === target && enabled && spaceSession.mode === 'voice') {
			spaceSession.mode = 'listen';
			connection?.send('setMode', { mode: 'listen' });
		}
	}
	refreshMicrophones(target);
}

function refreshMicrophones(target: Room): void {
	if (room !== target) return;
	const ids: string[] = [];
	if (target.localParticipant.isMicrophoneEnabled) ids.push(target.localParticipant.identity);
	for (const participant of target.remoteParticipants.values()) {
		if (participant.isMicrophoneEnabled) ids.push(participant.identity);
	}
	spaceSession.micOnIds = ids;
}

function addScreenShare(id: string, userId: string, track: Track): void {
	screenTracks.set(id, track);
	spaceSession.screenShares = [...spaceSession.screenShares.filter(share => share.id !== id), { id, userId }];
}

function removeScreenShare(id: string): void {
	screenTracks.get(id)?.detach();
	screenTracks.delete(id);
	spaceSession.screenShares = spaceSession.screenShares.filter(share => share.id !== id);
}

function clearScreenShares(): void {
	for (const track of screenTracks.values()) track.detach();
	screenTracks.clear();
	spaceSession.screenShares = [];
	spaceSession.sharingScreen = false;
}

/** 画面共有の映像を、画面の video 要素につなぐ。 */
export function attachSpaceScreen(id: string, element: HTMLVideoElement): void {
	screenTracks.get(id)?.attach(element);
}

export function detachSpaceScreen(id: string, element: HTMLVideoElement): void {
	screenTracks.get(id)?.detach(element);
}

/** 画面の共有を始める、止める。PC の音も一緒に流せる (ブラウザが対応していれば、共有を選ぶ画面で選べる)。 */
export async function toggleSpaceScreenShare(): Promise<void> {
	const target = room;
	if (target == null || spaceSession.callStatus !== 'connected') return;
	try {
		const enable = !spaceSession.sharingScreen;
		await target.localParticipant.setScreenShareEnabled(enable, { audio: true });
		// 共有する画面を選んでいる間にスペースから出ていたら、取った画面をすぐ止める
		if (enable && room !== target) await target.localParticipant.setScreenShareEnabled(false).catch(() => undefined);
	} catch (err) {
		// 共有する画面を選ばずに閉じた場合もここに来る
		console.warn('failed to switch the screen share', err);
	}
}

function removeAudioElements(): void {
	for (const element of audioElements) element.remove();
	audioElements.clear();
}

function disconnectCall(): void {
	callGeneration++;
	const current = room;
	room = null;
	if (current != null) void current.disconnect();
	removeAudioElements();
	clearScreenShares();
	spaceSession.callStatus = 'off';
	spaceSession.speakingIds = [];
	spaceSession.micOnIds = [];
	spaceSession.audioBlocked = false;
}
