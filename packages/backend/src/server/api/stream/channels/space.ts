/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { randomUUID } from 'node:crypto';
import { Inject, Injectable, Scope } from '@nestjs/common';
import { REQUEST } from '@nestjs/core';
import type { SpacesRepository } from '@/models/_.js';
import type { MiSpace } from '@/models/Space.js';
import { DI } from '@/di-symbols.js';
import { bindThis } from '@/decorators.js';
import { isSpaceMode, SpaceService } from '@/core/spaces/SpaceService.js';
import { SpaceTileService } from '@/core/spaces/SpaceTileService.js';
import type { GlobalEvents } from '@/core/GlobalEventService.js';
import { isJsonObject } from '@/misc/json-value.js';
import type { JsonObject, JsonValue } from '@/misc/json-value.js';
import Channel, { type ChannelRequest } from '../channel.js';

/**
 * このチャンネルにつないでいる間が「スペースにいる」。つなぐと入り、切ると出る。
 */
@Injectable({ scope: Scope.TRANSIENT })
export class SpaceChannel extends Channel {
	public readonly chName = 'space';
	public static shouldShare = false;
	public static requireCredential = true as const;
	public static kind = 'read:spaces';
	private readonly sessionId = randomUUID();
	private space: MiSpace | null = null;
	/** 入っている間だけ true。置き換え・追い出し・終了のあとは false */
	private active = false;
	/** 置き換え・追い出し・終了を受けたら true。入る処理の途中で受けた場合に、入った状態へ戻さないために使う */
	private terminated = false;
	/** 入る処理の途中で届いた知らせ。snapshot を送ったあとに流す */
	private pending: GlobalEvents['space']['payload'][] | null = [];

	constructor(
		@Inject(REQUEST)
		request: ChannelRequest,

		@Inject(DI.spacesRepository)
		private spacesRepository: SpacesRepository,

		private spaceService: SpaceService,
		private spaceTileService: SpaceTileService,
	) {
		super(request);
	}

	@bindThis
	public async init(params: JsonObject): Promise<boolean> {
		if (this.user == null) return false;
		if (typeof params.spaceId !== 'string') return false;
		const mode = isSpaceMode(params.mode) ? params.mode : 'listen';
		if (!this.spaceService.isEnabled()) return false;

		// 先に知らせを受け取り始めてから、スペースを読む。読んだあとに閉じられても、知らせで気づける
		const spaceId = params.spaceId;
		this.subscriber.on(`spaceStream:${spaceId}`, this.onEvent);
		const space = await this.spacesRepository.findOneBy({ id: spaceId });
		if (space == null || !(await this.spaceService.canJoin(this.user, space))) {
			this.subscriber.off(`spaceStream:${spaceId}`, this.onEvent);
			return false;
		}

		this.space = space;
		const { members, messages } = await this.spaceService.join(space, this.sessionId, this.user, mode);
		// 入る処理の途中で追い出されたり閉じられたりした場合は、入らなかったことにする
		if (this.terminated || !(await this.spaceService.canJoin(this.user, space))) {
			await this.spaceService.leave(space.id, this.sessionId, this.user.id);
			this.subscriber.off(`spaceStream:${space.id}`, this.onEvent);
			this.space = null;
			return false;
		}
		this.active = true;
		this.send('snapshot', {
			space: await this.spaceService.pack(space, this.user),
			members,
			messages,
			tiles: await this.spaceTileService.getTiles(space.id),
			leaderId: await this.spaceService.getLeader(space.id),
		});
		// snapshot を作っている間に届いた知らせを、順番どおりに流す。同じ知らせが snapshot と重なっても、受け取る側は上書きで扱う
		const pending = this.pending ?? [];
		this.pending = null;
		for (const data of pending) this.onEvent(data);
		return true;
	}

	@bindThis
	private onEvent(data: GlobalEvents['space']['payload']): void {
		if (this.user == null) return;
		// 入る処理の途中で届いた知らせは、snapshot のあとに流す。出される知らせ (置き換え・追い出し・終了) だけは、すぐに扱う
		if (this.pending != null && data.type !== 'replaced' && data.type !== 'kicked' && data.type !== 'ended') {
			this.pending.push(data);
			return;
		}
		switch (data.type) {
			case 'replaced':
				if (data.body.userId !== this.user.id || data.body.sessionId !== this.sessionId) return;
				this.terminated = true;
				this.active = false;
				this.send('replaced', null);
				return;
			case 'muted':
				if (data.body.userId !== this.user.id || !this.active) return;
				this.send('muted', null);
				return;
			case 'kicked':
				if (data.body.userId !== this.user.id) return;
				this.terminated = true;
				this.active = false;
				this.send('kicked', null);
				return;
			case 'ended':
				this.terminated = true;
				this.active = false;
				this.send('ended', null);
				return;
			case 'updated':
				if (!this.active) return;
				if (this.space != null) Object.assign(this.space, data.body);
				this.send(data.type, data.body);
				return;
			default:
				if (!this.active) return;
				this.send(data.type, data.body);
		}
	}

	@bindThis
	public onMessage(type: string, body: JsonValue): void {
		if (!this.active || this.user == null || this.space == null) return;
		switch (type) {
			case 'heartbeat':
				void this.spaceService.heartbeat(this.space, this.sessionId, this.user.id);
				break;
			case 'setMode':
				if (isJsonObject(body) && isSpaceMode(body.mode)) {
					void this.spaceService.setMode(this.space, this.sessionId, this.user.id, body.mode);
				}
				break;
			case 'setShared':
				if (!this.canWrite()) break;
				if (isJsonObject(body)) void this.writeTile(this.space.id, this.user.id, () => this.spaceTileService.setShared(this.space!.id, this.user!.id, body.tileId, body.key, body.value));
				break;
			case 'signal':
				if (!this.canWrite()) break;
				if (isJsonObject(body)) void this.writeTile(this.space.id, this.user.id, () => this.spaceTileService.signal(this.space!.id, this.user!.id, body.tileId, body.type, body.body));
				break;
			case 'say':
				if (!this.canWrite()) break;
				if (isJsonObject(body) && typeof body.text === 'string') {
					void this.spaceService.say(this.space.id, this.sessionId, this.user.id, body.text);
				}
				break;
		}
	}

	/** タイルへの書き込み。生存確認が途絶えて外された接続からは書かせない。 */
	private async writeTile(spaceId: MiSpace['id'], userId: string, write: () => Promise<boolean>): Promise<void> {
		if (!(await this.spaceService.isCurrentSession(spaceId, this.sessionId, userId))) return;
		await write();
	}

	/** 見るだけの権限のアプリには書かせない。 */
	private canWrite(): boolean {
		return this.connection.token == null || this.connection.token.permission.includes('write:spaces');
	}

	@bindThis
	public dispose(): void {
		if (this.space == null) return;
		this.subscriber.off(`spaceStream:${this.space.id}`, this.onEvent);
		if (this.active && this.user != null) {
			void this.spaceService.leave(this.space.id, this.sessionId, this.user.id);
		}
	}
}
