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
	connection = stream.useChannel('space', { spaceId: space.id, mode });
	connection.on('snapshot', onSnapshot);
	connection.on('joined', onJoined);
	connection.on('left', onLeft);
	connection.on('memberUpdated', onMemberUpdated);
	connection.on('message', onMessage);
	connection.on('updated', onUpdated);
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
	connection?.dispose();
	connection = null;
	disconnectCall();
	spaceSession.status = 'idle';
	spaceSession.space = null;
	spaceSession.members = [];
	spaceSession.messages = [];
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

function onSnapshot(payload: { space: Misskey.entities.Space; members: Misskey.SpaceMember[]; messages: Misskey.SpaceMessage[] }): void {
	if (joinTimerId != null) window.clearTimeout(joinTimerId);
	joinTimerId = null;
	awaitingSnapshot = false;
	spaceSession.space = payload.space;
	spaceSession.members = payload.members;
	spaceSession.messages = payload.messages;
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

function onUpdated(payload: Pick<Misskey.entities.Space, 'name' | 'access'>): void {
	if (spaceSession.space != null) spaceSession.space = { ...spaceSession.space, ...payload };
}

function onMuted(): void {
	if (spaceSession.mode !== 'voice') return;
	spaceSession.mutedByHost = true;
	void setSpaceMode('listen');
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
