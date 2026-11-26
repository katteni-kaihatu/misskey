/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import * as Redis from 'ioredis';
import { IsNull } from 'typeorm';
import { AccessToken, RoomServiceClient, TrackSource } from 'livekit-server-sdk';
import type { MiLocalUser, MiUser } from '@/models/User.js';
import { MiSpace } from '@/models/Space.js';
import type { FollowingsRepository, NotesRepository, SpacesRepository, UsersRepository } from '@/models/_.js';
import type { Packed } from '@/misc/json-schema.js';
import type { Config } from '@/config.js';
import { DI } from '@/di-symbols.js';
import { bindThis } from '@/decorators.js';
import { IdService } from '@/core/IdService.js';
import { UserEntityService } from '@/core/entities/UserEntityService.js';
import { UserBlockingService } from '@/core/UserBlockingService.js';
import { NoteCreateService } from '@/core/NoteCreateService.js';
import { GlobalEventService } from '@/core/GlobalEventService.js';
import { LoggerService } from '@/core/LoggerService.js';
import type Logger from '@/logger.js';
import { resolveSpacesConfig, type SpacesConfig } from './spaces-config.js';
import { SpaceTileService } from './SpaceTileService.js';

/** 入り方。voice はマイクを入れている、listen は聞くだけ。どちらも通話にはつないでいる */
export const spaceModes = ['voice', 'listen'] as const;
export type SpaceMode = typeof spaceModes[number];

export type SpaceMember = {
	user: Packed<'UserLite'>;
	mode: SpaceMode;
	joinedAt: number;
};

export type SpaceMessage = {
	id: string;
	user: Packed<'UserLite'>;
	text: string;
	createdAt: number;
};

type StoredMember = SpaceMember & { sessionId: string };

/** 生存確認がこの秒数来なければ、出たものとして扱う (仮の値) */
const PRESENCE_TTL_SECONDS = 90;
/** だれもいなくなってから自動で閉じるまで */
export const SPACE_EMPTY_CLOSE_MS = 30 * 60 * 1000;
const MAX_MESSAGES = 200;
export const SPACE_MESSAGE_MAX_LENGTH = 2000;
const TOKEN_TTL_SECONDS = 10 * 60;
/** 通話にいる人と「いる人」の一覧を突き合わせる間隔 */
const RECONCILE_INTERVAL_SECONDS = 20;

/** 接続の ID が一致するときだけ「いる人」から外す。確認と削除を1回で行い、入り直した新しい接続を消さないようにする */
const LEAVE_SCRIPT = `
local raw = redis.call('HGET', KEYS[1], ARGV[1])
if not raw then return 0 end
local ok, member = pcall(cjson.decode, raw)
if not ok or member.sessionId ~= ARGV[2] then return 0 end
redis.call('HDEL', KEYS[1], ARGV[1])
redis.call('ZREM', KEYS[2], ARGV[1])
return 1
`;

/** まとめノートの本文。開いていた時間は分で、1分に満たなくても1分と書く。 */
export function buildSpaceSummaryText(params: { name: string; startedAt: Date; endedAt: Date; participantCount: number; url: string }): string {
	const minutes = Math.max(1, Math.round((params.endedAt.getTime() - params.startedAt.getTime()) / 60000));
	const duration = minutes >= 60 ? `${Math.floor(minutes / 60)}時間${minutes % 60}分` : `${minutes}分`;
	return `${params.name} は終わりました\n開いていた時間 ${duration} ・ 参加した人 ${params.participantCount}人\n${params.url}`;
}

/** 担当を選ぶ。`memberIds` は長くいる順。ホストがいればホスト、いなければ先頭の人。 */
export function pickSpaceLeader(memberIds: string[], hostId: string | null): string | null {
	if (hostId != null && memberIds.includes(hostId)) return hostId;
	return memberIds[0] ?? null;
}

export function isSpaceMode(value: unknown): value is SpaceMode {
	return typeof value === 'string' && (spaceModes as readonly string[]).includes(value);
}

@Injectable()
export class SpaceService {
	private logger: Logger;
	private spacesConfig: SpacesConfig | null;
	private roomService: RoomServiceClient | null;

	constructor(
		@Inject(DI.config)
		private config: Config,

		@Inject(DI.redis)
		private redisClient: Redis.Redis,

		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		@Inject(DI.followingsRepository)
		private followingsRepository: FollowingsRepository,

		@Inject(DI.usersRepository)
		private usersRepository: UsersRepository,

		private idService: IdService,
		private userEntityService: UserEntityService,
		private userBlockingService: UserBlockingService,
		private noteCreateService: NoteCreateService,
		private globalEventService: GlobalEventService,
		private loggerService: LoggerService,

		@Inject(DI.notesRepository)
		private notesRepository: NotesRepository,

		private spaceTileService: SpaceTileService,
	) {
		this.logger = this.loggerService.getLogger('spaces');
		this.spacesConfig = resolveSpacesConfig(this.config.spaces, process.env);
		this.roomService = this.spacesConfig == null ? null : new RoomServiceClient(this.spacesConfig.livekit.httpUrl, this.spacesConfig.livekit.apiKey, this.spacesConfig.livekit.apiSecret);
	}

	@bindThis
	public isEnabled(): boolean {
		return this.spacesConfig != null;
	}

	private key(spaceId: MiSpace['id'], kind: 'members' | 'active' | 'messages' | 'emptySince' | 'kicked' | 'reconcileLock' | 'reconcileSuspects' | 'leader'): string {
		return `space:${spaceId}:${kind}`;
	}

	// ---- 作る、変える、閉じる ----

	@bindThis
	public async findOpenByHost(hostId: MiUser['id']): Promise<MiSpace | null> {
		return await this.spacesRepository.findOneBy({ hostId, endedAt: IsNull() });
	}

	@bindThis
	public async create(host: MiLocalUser, params: Pick<MiSpace, 'name' | 'access' | 'noteScope'> & { continuedFromId?: MiSpace['id'] | null; tilePlacement?: MiSpace['tilePlacement'] }): Promise<MiSpace> {
		const space = await this.spacesRepository.insertOne({
			id: this.idService.gen(),
			hostId: host.id,
			name: params.name,
			access: params.access,
			noteScope: params.noteScope,
			continuedFromId: params.continuedFromId ?? null,
			...(params.tilePlacement != null ? { tilePlacement: params.tilePlacement } : {}),
		});

		// 「続きをひらく」のときは、元のスペースのタイルと値を写す
		if (space.continuedFromId != null) await this.spaceTileService.copyTiles(space.continuedFromId, space.id);

		await this.redisClient.set(this.key(space.id, 'emptySince'), Date.now().toString());

		if (space.noteScope !== 'none') {
			try {
				const note = await this.noteCreateService.create(host, {
					text: `${space.name}\n${this.url(space.id)}`,
					localOnly: space.noteScope === 'local',
					visibility: space.access === 'followers' ? 'followers' : 'public',
				});
				await this.spacesRepository.update(space.id, { announceNoteId: note.id });
				space.announceNoteId = note.id;
			} catch (err) {
				// お知らせが出せなくても、スペースは開いたままにする
				this.logger.warn(`failed to create the announcement note for space ${space.id}`, { err });
			}
		}

		return space;
	}

	@bindThis
	public url(spaceId: MiSpace['id']): string {
		return `${this.config.url}/spaces/${spaceId}`;
	}

	@bindThis
	public async update(space: MiSpace, params: Partial<Pick<MiSpace, 'name' | 'access' | 'tilePlacement'>>): Promise<MiSpace> {
		const set: Partial<Pick<MiSpace, 'name' | 'access' | 'tilePlacement'>> = {};
		if (params.name !== undefined) set.name = params.name;
		if (params.access !== undefined) set.access = params.access;
		if (params.tilePlacement !== undefined) set.tilePlacement = params.tilePlacement;
		// 何も変えない呼び出しでは、知らせも配らない
		if (Object.keys(set).length === 0) return space;
		await this.spacesRepository.update(space.id, set);
		const updated = { ...space, ...set };
		this.globalEventService.publishSpaceStream(space.id, 'updated', { name: updated.name, access: updated.access, tilePlacement: updated.tilePlacement });
		return updated;
	}

	/** 閉じる。ホストの操作と定期ジョブの両方がこれを呼ぶ。 */
	@bindThis
	public async end(space: MiSpace): Promise<void> {
		if (space.endedAt != null) return;
		const endedAt = new Date();
		const result = await this.spacesRepository.update({ id: space.id, endedAt: IsNull() }, { endedAt });
		if (result.affected === 0) return;
		space.endedAt = endedAt;

		this.globalEventService.publishSpaceStream(space.id, 'ended', null);

		if (this.roomService != null) {
			try {
				await this.roomService.deleteRoom(space.id);
			} catch (err) {
				// 部屋がまだ無い (だれも入らないまま閉じた) 場合もここに来る
				this.logger.warn(`failed to delete the LiveKit room for space ${space.id}`, { err });
			}
		}

		// Redis の片づけに失敗しても、まとめノートは出す
		await this.redisClient.del(
			this.key(space.id, 'members'),
			this.key(space.id, 'active'),
			this.key(space.id, 'messages'),
			this.key(space.id, 'emptySince'),
			this.key(space.id, 'kicked'),
			this.key(space.id, 'reconcileLock'),
			this.key(space.id, 'reconcileSuspects'),
			this.key(space.id, 'leader'),
		).catch(err => {
			this.logger.warn(`failed to clean up Redis for space ${space.id}`, { err });
		});

		// タイルの値を DB に写して、Redis を片づける。失敗しても、まとめノートは出す
		await this.spaceTileService.closeSpace(space.id).catch(err => {
			this.logger.warn(`failed to save the tiles of space ${space.id}`, { err });
		});

		await this.postSummaryNote(space.id);
	}

	/**
	 * 閉じたスペースのまとめノートを出す。お知らせノートと同じ範囲で出し、お知らせを出さなかったスペースでは出さない。
	 * 範囲は、実際に出たお知らせノートのものを使う。ひらいたあとで「入れる人」を広げても、まとめがお知らせより広く出ないようにする。
	 * 参加した人の名前は載せない。
	 */
	private async postSummaryNote(spaceId: MiSpace['id']): Promise<void> {
		try {
			// 参加した人数は入るたびに DB で増えているので、読み直す
			const space = await this.spacesRepository.findOne({ where: { id: spaceId }, relations: { host: true } });
			if (space == null || space.host == null || space.endedAt == null) return;
			if (space.noteScope === 'none' || space.summaryNoteId != null || space.announceNoteId == null) return;
			const announce = await this.notesRepository.findOneBy({ id: space.announceNoteId });
			// お知らせノートが消されていたら、まとめも出さない
			if (announce == null) return;

			const note = await this.noteCreateService.create(space.host, {
				text: buildSpaceSummaryText({
					name: space.name,
					startedAt: this.idService.parse(space.id).date,
					endedAt: space.endedAt,
					participantCount: space.participantIds.length,
					url: this.url(space.id),
				}),
				localOnly: announce.localOnly,
				visibility: announce.visibility === 'followers' ? 'followers' : 'public',
			});
			await this.spacesRepository.update(space.id, { summaryNoteId: note.id });
		} catch (err) {
			// まとめが出せなくても、閉じる処理は終わったものとして扱う
			this.logger.warn(`failed to create the summary note for space ${spaceId}`, { err });
		}
	}

	// ---- 入れるかの判定 ----

	@bindThis
	public async canJoin(me: { id: MiUser['id'] }, space: MiSpace): Promise<boolean> {
		if (space.endedAt != null) return false;
		if (space.hostId === me.id) return true;
		if (await this.redisClient.sismember(this.key(space.id, 'kicked'), me.id) === 1) return false;
		if (await this.userBlockingService.checkBlocked(space.hostId, me.id)) return false;
		if (await this.userBlockingService.checkBlocked(me.id, space.hostId)) return false;
		if (space.access === 'local') return true;
		return await this.followingsRepository.exists({ where: { followerId: me.id, followeeId: space.hostId } });
	}

	// ---- 返す形 ----

	@bindThis
	public async pack(space: MiSpace, me: { id: MiUser['id'] }): Promise<Packed<'Space'>> {
		const host = space.host ?? await this.usersRepository.findOneByOrFail({ id: space.hostId });
		return {
			id: space.id,
			createdAt: this.idService.parse(space.id).date.toISOString(),
			endedAt: space.endedAt?.toISOString() ?? null,
			hostId: space.hostId,
			host: await this.userEntityService.pack(host, me),
			name: space.name,
			access: space.access,
			noteScope: space.noteScope,
			tilePlacement: space.tilePlacement,
			announceNoteId: space.announceNoteId,
			summaryNoteId: space.summaryNoteId,
			memberCount: space.endedAt == null ? await this.countMembers(space.id) : 0,
			participantCount: space.participantIds.length,
			peakCount: space.peakCount,
			canJoin: await this.canJoin(me, space),
		};
	}

	/** 開いていて、自分が入れるスペース。 */
	@bindThis
	public async listJoinable(me: { id: MiUser['id'] }): Promise<Packed<'Space'>[]> {
		const spaces = await this.spacesRepository.find({ where: { endedAt: IsNull() }, relations: { host: true }, order: { id: 'DESC' } });
		const packed = await Promise.all(spaces.map(space => this.pack(space, me)));
		return packed.filter(space => space.canJoin);
	}

	// ---- いる人 ----

	private parseMember(raw: string): StoredMember | null {
		try {
			return JSON.parse(raw) as StoredMember;
		} catch {
			return null;
		}
	}

	private async getStoredMember(spaceId: MiSpace['id'], userId: MiUser['id']): Promise<StoredMember | null> {
		const raw = await this.redisClient.hget(this.key(spaceId, 'members'), userId);
		return raw == null ? null : this.parseMember(raw);
	}

	private async removeMember(spaceId: MiSpace['id'], userId: MiUser['id']): Promise<void> {
		const removed = await this.redisClient.hdel(this.key(spaceId, 'members'), userId);
		await this.redisClient.zrem(this.key(spaceId, 'active'), userId);
		await this.afterRemoved(spaceId, userId, removed > 0);
	}

	private async afterRemoved(spaceId: MiSpace['id'], userId: MiUser['id'], removed: boolean): Promise<void> {
		if (removed) {
			this.globalEventService.publishSpaceStream(spaceId, 'left', { userId });
			await this.refreshLeader(spaceId);
		}
		if (await this.redisClient.hlen(this.key(spaceId, 'members')) === 0) {
			await this.redisClient.set(this.key(spaceId, 'emptySince'), Date.now().toString(), 'NX');
		}
	}

	/**
	 * 担当を決め直す。担当は、全員の手元で同時に起きる出来事 (タイマーが切れた、など) を1人だけで実行するための役。
	 * ホストがいればホスト、いなければいちばん長くいる人。替わったら全員に知らせる。
	 */
	@bindThis
	public async refreshLeader(spaceId: MiSpace['id'], hostId?: MiUser['id']): Promise<MiUser['id'] | null> {
		const host = hostId ?? (await this.spacesRepository.findOne({ where: { id: spaceId }, select: { id: true, hostId: true } }))?.hostId;
		const members = (await this.redisClient.hvals(this.key(spaceId, 'members')))
			.map(raw => this.parseMember(raw))
			.filter(member => member != null)
			.sort((a, b) => a.joinedAt - b.joinedAt || a.user.id.localeCompare(b.user.id));
		const next = pickSpaceLeader(members.map(member => member.user.id), host ?? null);
		const previous = await this.redisClient.get(this.key(spaceId, 'leader'));
		if ((previous ?? null) === next) return next;
		if (next == null) await this.redisClient.del(this.key(spaceId, 'leader'));
		else await this.redisClient.set(this.key(spaceId, 'leader'), next);
		this.globalEventService.publishSpaceStream(spaceId, 'leader', { userId: next });
		return next;
	}

	@bindThis
	public async getLeader(spaceId: MiSpace['id']): Promise<MiUser['id'] | null> {
		return await this.redisClient.get(this.key(spaceId, 'leader'));
	}

	/** 生存確認が途絶えた人を外す。 */
	@bindThis
	public async prune(spaceId: MiSpace['id']): Promise<void> {
		const stale = await this.redisClient.zrangebyscore(this.key(spaceId, 'active'), '-inf', Date.now() - (PRESENCE_TTL_SECONDS * 1000));
		for (const userId of stale) {
			await this.removeMember(spaceId, userId);
		}
	}

	@bindThis
	public async getMembers(spaceId: MiSpace['id']): Promise<SpaceMember[]> {
		await this.prune(spaceId);
		const raws = await this.redisClient.hvals(this.key(spaceId, 'members'));
		return raws
			.map(raw => this.parseMember(raw))
			.filter(member => member != null)
			.map(({ user, mode, joinedAt }) => ({ user, mode, joinedAt }))
			.sort((a, b) => a.joinedAt - b.joinedAt);
	}

	@bindThis
	public async countMembers(spaceId: MiSpace['id']): Promise<number> {
		await this.prune(spaceId);
		return await this.redisClient.hlen(this.key(spaceId, 'members'));
	}

	@bindThis
	public async getMessages(spaceId: MiSpace['id']): Promise<SpaceMessage[]> {
		const raws = await this.redisClient.lrange(this.key(spaceId, 'messages'), 0, -1);
		const messages: SpaceMessage[] = [];
		for (const raw of raws) {
			try {
				messages.push(JSON.parse(raw) as SpaceMessage);
			} catch {
				// 壊れた行は飛ばす
			}
		}
		return messages;
	}

	/**
	 * 入る。同じ人がすでに別の接続で入っていれば、そちらに `replaced` を送って置き換える。
	 * 入れるかの判定 (canJoin) は呼ぶ側が先に済ませる。
	 */
	@bindThis
	public async join(space: MiSpace, sessionId: string, user: MiUser, mode: SpaceMode): Promise<{ members: SpaceMember[]; messages: SpaceMessage[] }> {
		const previous = await this.getStoredMember(space.id, user.id);
		if (previous != null && previous.sessionId !== sessionId) {
			this.globalEventService.publishSpaceStream(space.id, 'replaced', { userId: user.id, sessionId: previous.sessionId });
		}

		const member: StoredMember = {
			user: await this.userEntityService.pack(user, user),
			mode,
			joinedAt: previous?.joinedAt ?? Date.now(),
			sessionId,
		};
		await this.redisClient.hset(this.key(space.id, 'members'), user.id, JSON.stringify(member));
		await this.redisClient.zadd(this.key(space.id, 'active'), Date.now(), user.id);
		await this.redisClient.del(this.key(space.id, 'emptySince'));

		const members = await this.getMembers(space.id);
		await this.spacesRepository.createQueryBuilder().update()
			.set({
				participantIds: () => 'CASE WHEN :userId = ANY("participantIds") THEN "participantIds" ELSE array_append("participantIds", :userId) END',
				peakCount: () => 'GREATEST("peakCount", :count)',
			})
			.where('id = :id', { id: space.id })
			.setParameters({ userId: user.id, count: members.length })
			.execute();

		const { sessionId: _, ...publicMember } = member;
		if (previous == null) {
			this.globalEventService.publishSpaceStream(space.id, 'joined', publicMember);
		} else if (previous.mode !== member.mode) {
			this.globalEventService.publishSpaceStream(space.id, 'memberUpdated', { userId: user.id, mode: member.mode });
		}

		await this.refreshLeader(space.id, space.hostId);

		return { members, messages: await this.getMessages(space.id) };
	}

	@bindThis
	public async leave(spaceId: MiSpace['id'], sessionId: string, userId: MiUser['id']): Promise<void> {
		// 別の接続に置き換えられたあとなら、何もしない
		const removed = await this.redisClient.eval(LEAVE_SCRIPT, 2, this.key(spaceId, 'members'), this.key(spaceId, 'active'), userId, sessionId);
		if (removed === 1) await this.afterRemoved(spaceId, userId, true);
	}

	@bindThis
	public async heartbeat(space: MiSpace, sessionId: string, userId: MiUser['id']): Promise<void> {
		const member = await this.getStoredMember(space.id, userId);
		if (member == null || member.sessionId !== sessionId) return;
		await this.redisClient.zadd(this.key(space.id, 'active'), Date.now(), userId);
		await this.reconcileCall(space);
	}

	/**
	 * 通話 (LiveKit) にいるのに「いる人」に入っていない人を外す。
	 * LiveKit は発行済みのトークンを取り消せない。追い出された人が手元のトークンでつなぎ直した場合や、
	 * トークンだけ取って一覧に載らずに聞いている場合を、ここで止める。
	 * だれかの生存確認のたびに呼ばれるが、実際に調べるのは一定の間隔に1回だけ。
	 */
	@bindThis
	public async reconcileCall(space: MiSpace): Promise<void> {
		if (this.roomService == null) return;
		const locked = await this.redisClient.set(this.key(space.id, 'reconcileLock'), '1', 'EX', RECONCILE_INTERVAL_SECONDS, 'NX');
		if (locked !== 'OK') return;
		try {
			const participants = await this.roomService.listParticipants(space.id);
			if (participants.length === 0) return;
			const memberIds = new Set(await this.redisClient.hkeys(this.key(space.id, 'members')));
			const kickedIds = new Set(await this.redisClient.smembers(this.key(space.id, 'kicked')));
			const suspectsKey = this.key(space.id, 'reconcileSuspects');
			const previousSuspects = new Set(await this.redisClient.smembers(suspectsKey));
			const suspects: string[] = [];
			for (const participant of participants) {
				const identity = participant.identity;
				if (memberIds.has(identity) && !kickedIds.has(identity)) continue;
				// 入っている途中や、ストリーミングのつなぎ直しの途中の人を外さないよう、追い出された人以外は2回続けて見つけてから外す
				if (kickedIds.has(identity) || previousSuspects.has(identity)) {
					await this.roomService.removeParticipant(space.id, identity);
				} else {
					suspects.push(identity);
				}
			}
			await this.redisClient.del(suspectsKey);
			if (suspects.length > 0) {
				await this.redisClient.sadd(suspectsKey, ...suspects);
				await this.redisClient.expire(suspectsKey, RECONCILE_INTERVAL_SECONDS * 4);
			}
		} catch (err) {
			// 部屋がまだ無い場合や、LiveKit が止まっている場合。いる人とチャットは動かし続ける
			this.logger.debug(`failed to reconcile the LiveKit room for space ${space.id}`, { err });
		}
	}

	@bindThis
	public async setMode(space: MiSpace, sessionId: string, userId: MiUser['id'], mode: SpaceMode): Promise<void> {
		const member = await this.getStoredMember(space.id, userId);
		if (member == null || member.sessionId !== sessionId || member.mode === mode) return;
		member.mode = mode;
		await this.redisClient.hset(this.key(space.id, 'members'), userId, JSON.stringify(member));
		this.globalEventService.publishSpaceStream(space.id, 'memberUpdated', { userId, mode });
	}

	@bindThis
	public async say(spaceId: MiSpace['id'], sessionId: string, userId: MiUser['id'], text: string): Promise<void> {
		const trimmed = text.trim();
		if (trimmed.length === 0 || trimmed.length > SPACE_MESSAGE_MAX_LENGTH) return;
		const member = await this.getStoredMember(spaceId, userId);
		if (member == null || member.sessionId !== sessionId) return;
		const message: SpaceMessage = { id: this.idService.gen(), user: member.user, text: trimmed, createdAt: Date.now() };
		await this.redisClient.rpush(this.key(spaceId, 'messages'), JSON.stringify(message));
		await this.redisClient.ltrim(this.key(spaceId, 'messages'), -MAX_MESSAGES, -1);
		this.globalEventService.publishSpaceStream(spaceId, 'message', message);
	}

	/** その接続が、いまもスペースに入っているものか。生存確認が途絶えて外された接続や、置き換えられた接続では false。 */
	@bindThis
	public async isCurrentSession(spaceId: MiSpace['id'], sessionId: string, userId: MiUser['id']): Promise<boolean> {
		const member = await this.getStoredMember(spaceId, userId);
		return member != null && member.sessionId === sessionId;
	}

	// ---- ホストの操作 ----

	@bindThis
	public async isMember(spaceId: MiSpace['id'], userId: MiUser['id']): Promise<boolean> {
		return await this.redisClient.hexists(this.key(spaceId, 'members'), userId) === 1;
	}

	/** 相手のブラウザにマイクを切らせる。本人はもう一度入れられる (仮)。 */
	@bindThis
	public mute(space: MiSpace, userId: MiUser['id']): void {
		this.globalEventService.publishSpaceStream(space.id, 'muted', { userId });
	}

	@bindThis
	public async kick(space: MiSpace, userId: MiUser['id']): Promise<void> {
		await this.redisClient.sadd(this.key(space.id, 'kicked'), userId);
		this.globalEventService.publishSpaceStream(space.id, 'kicked', { userId });
		await this.removeMember(space.id, userId);
		if (this.roomService != null) {
			try {
				await this.roomService.removeParticipant(space.id, userId);
			} catch (err) {
				// 通話につながっていなかった場合はここに来る。つなぎ直してきた場合は reconcileCall が外す
				this.logger.debug(`failed to remove ${userId} from the LiveKit room for space ${space.id}`, { err });
			}
		}
	}

	// ---- 通話 ----

	/** LiveKit のトークンを作る。入れるかの判定は呼ぶ側が先に済ませる。 */
	@bindThis
	public async createToken(space: MiSpace, user: MiUser): Promise<{ url: string; token: string }> {
		if (this.spacesConfig == null) throw new Error('Spaces is not enabled.');
		const { url, apiKey, apiSecret } = this.spacesConfig.livekit;
		const token = new AccessToken(apiKey, apiSecret, {
			identity: user.id,
			name: user.name ?? user.username,
			ttl: TOKEN_TTL_SECONDS,
		});
		// LiveKit は書かなかった権限を「許可」として扱う。禁止するものは false と書く。
		token.addGrant({
			room: space.id,
			roomJoin: true,
			roomCreate: false,
			roomList: false,
			roomRecord: false,
			roomAdmin: false,
			ingressAdmin: false,
			canPublish: true,
			canSubscribe: true,
			// 位置などをあとで LiveKit のデータ通信に移すため、最初から許可しておく
			canPublishData: true,
			canUpdateOwnMetadata: false,
			hidden: false,
			recorder: false,
			// カメラは入れない
			canPublishSources: [TrackSource.MICROPHONE, TrackSource.SCREEN_SHARE, TrackSource.SCREEN_SHARE_AUDIO],
		});
		return { url, token: await token.toJwt() };
	}

	// ---- 定期ジョブ ----

	/** だれもいないまま時間が過ぎたスペースを閉じる。閉じた数を返す。 */
	@bindThis
	public async closeAbandoned(now = Date.now()): Promise<number> {
		const spaces = await this.spacesRepository.findBy({ endedAt: IsNull() });
		let closed = 0;
		for (const space of spaces) {
			if (await this.countMembers(space.id) > 0) continue;
			const raw = await this.redisClient.get(this.key(space.id, 'emptySince'));
			if (raw == null) {
				// Redis の中身が消えた場合など。ここから数え直す
				await this.redisClient.set(this.key(space.id, 'emptySince'), now.toString(), 'NX');
				continue;
			}
			if (now - Number(raw) < SPACE_EMPTY_CLOSE_MS) continue;
			// 調べている間にだれかが入っていたら、閉じない
			if (await this.redisClient.hlen(this.key(space.id, 'members')) > 0) continue;
			await this.end(space);
			closed++;
		}
		return closed;
	}
}
