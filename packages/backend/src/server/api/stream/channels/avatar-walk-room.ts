/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { randomUUID } from 'node:crypto';
import { Inject, Injectable, Scope } from '@nestjs/common';
import { REQUEST } from '@nestjs/core';
import { bindThis } from '@/decorators.js';
import { AvatarWalkService, isAvatarWalkMoveInput, isAvatarWalkSharedAtlasInput } from '@/core/AvatarWalkService.js';
import { isJsonObject } from '@/misc/json-value.js';
import type { JsonObject, JsonValue } from '@/misc/json-value.js';
import Channel, { type ChannelRequest } from '../channel.js';

const ROOM_ID = 'main';

@Injectable({ scope: Scope.TRANSIENT })
export class AvatarWalkRoomChannel extends Channel {
	public readonly chName = 'avatarWalkRoom';
	public static shouldShare = true;
	public static requireCredential = true as const;
	public static kind = 'read:account';
	private readonly sessionId = randomUUID();
	private initialized = false;

	constructor(
		@Inject(REQUEST)
		request: ChannelRequest,

		private avatarWalkService: AvatarWalkService,
	) {
		super(request);
	}

	@bindThis
	public async init(params: JsonObject): Promise<boolean> {
		if (this.user == null || params.roomId !== ROOM_ID) return false;

		this.subscriber.on(`avatarWalkRoomStream:${ROOM_ID}`, this.send);
		const players = await this.avatarWalkService.join(ROOM_ID, this.sessionId, this.user);
		this.initialized = true;
		this.send('snapshot', { players });
		return true;
	}

	@bindThis
	public onMessage(type: string, body: JsonValue): void {
		if (!this.initialized || this.user == null) return;
		if (type === 'move' && isJsonObject(body) && isAvatarWalkMoveInput(body)) {
			void this.avatarWalkService.move(ROOM_ID, this.sessionId, this.user.id, body);
		} else if (type === 'setAtlas' && (body === null || (isJsonObject(body) && isAvatarWalkSharedAtlasInput(body)))) {
			void this.avatarWalkService.setAtlas(ROOM_ID, this.sessionId, this.user.id, body);
		}
	}

	@bindThis
	public dispose(): void {
		this.subscriber.off(`avatarWalkRoomStream:${ROOM_ID}`, this.send);
		if (this.initialized && this.user != null) {
			void this.avatarWalkService.leave(ROOM_ID, this.sessionId, this.user.id);
		}
	}
}
