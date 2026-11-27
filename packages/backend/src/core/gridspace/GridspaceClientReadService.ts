/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Inject, Injectable } from '@nestjs/common';
import { DataSource, IsNull } from 'typeorm';
import { DI } from '@/di-symbols.js';
import type { Config } from '@/config.js';
import { MiAccessToken } from '@/models/AccessToken.js';
import { MiApp } from '@/models/App.js';
import { MiUser, type MiLocalUser } from '@/models/User.js';
import { GridspaceLinkError, GridspaceLinkService } from './GridspaceLinkService.js';
import { GridspaceNotificationService } from './GridspaceNotificationService.js';
import { GridspaceTimelineService } from './timeline/GridspaceTimelineService.js';
import { resolveGridspaceConfig } from './peer-protocol.js';
import { gridspaceHash, openGridspaceSecret, sealGridspaceSecret } from './link-crypto.js';
import { CLIENT_CURSOR_TTL_MS, CLIENT_NOTIFICATION_SCOPE, CLIENT_PRIVATE_SCOPE, CLIENT_REVALIDATE_MS, CLIENT_TIMELINE_SCOPE,
	GridspaceClientError, clientAuthor, clientNote } from './client-read-protocol.js';

type Source = 'local' | 'peer' | 'channel';
type Scope = 'read:account' | typeof CLIENT_TIMELINE_SCOPE | typeof CLIENT_NOTIFICATION_SCOPE;
type ReadOptions = { limit: number; cursor?: string; includePrivate: boolean };

@Injectable()
export class GridspaceClientReadService {
	private readonly peer;
	private readonly origin: string;
	constructor(
		@Inject(DI.db) private db: DataSource,
		@Inject(DI.config) config: Config,
		private links: GridspaceLinkService,
		private timeline: GridspaceTimelineService,
		private notifications: GridspaceNotificationService,
	) {
		this.peer = resolveGridspaceConfig(config.gridspace, config.url, process.env);
		this.origin = new URL(config.url).origin;
	}

	private async authorize(viewer: MiLocalUser, token: MiAccessToken | null, scope: Scope, includePrivate: boolean) {
		if (!token?.id) throw new GridspaceClientError('APP_TOKEN_REQUIRED');
		const live = await this.db.getRepository(MiAccessToken).findOneBy({ id: token.id, userId: viewer.id });
		if (!live || !await this.db.getRepository(MiUser).existsBy({ id: viewer.id, host: IsNull(), isSuspended: false, isDeleted: false })) throw new GridspaceClientError('AUTHORIZATION_REVOKED');
		const app = live.appId ? await this.db.getRepository(MiApp).findOneBy({ id: live.appId }) : null;
		if (live.appId && !app) throw new GridspaceClientError('AUTHORIZATION_REVOKED');
		const permissions = app?.permission ?? live.permission;
		if (!permissions.includes(scope) || (includePrivate && !permissions.includes(CLIENT_PRIVATE_SCOPE))) throw new GridspaceClientError('PERMISSION_DENIED');
		let grant: string | null = null;
		if (this.peer) {
			this.links.assertPrivateCaller(live);
			if (includePrivate) {
				try {
					const link = await this.links.privateLink(viewer.id);
					grant = JSON.stringify([link.id, link.generation, link.privateTokenHash, link.privateMutualGrantId, link.tokenCipher,
						link.privateTokenCipher, link.privateRevision, link.privateMutualReady]);
				} catch (error) {
					if (!(error instanceof GridspaceLinkError) || !['LINK_REVOKED', 'AUTHORIZATION_REVOKED'].includes(error.code)) throw error;
				}
			}
		}
		return { permissions, binding: gridspaceHash(JSON.stringify([viewer.id, live.id, live.token, [...permissions].sort(), scope, includePrivate, grant])) };
	}

	private async finish(viewer: MiLocalUser, token: MiAccessToken | null, scope: Scope, includePrivate: boolean, binding: string) {
		if ((await this.authorize(viewer, token, scope, includePrivate)).binding !== binding) throw new GridspaceClientError('AUTHORIZATION_REVOKED');
	}

	private cursor(value: string | null, binding: string, source: string): string | null {
		if (!value) return null;
		if (!this.peer) throw new GridspaceClientError('UNAVAILABLE');
		return sealGridspaceSecret(this.peer, JSON.stringify({ value, expires: Date.now() + CLIENT_CURSOR_TTL_MS }), `client-read:${source}:${binding}`);
	}

	private decode(value: string | undefined, binding: string, source: string): string | undefined {
		if (!value) return undefined;
		if (!this.peer) throw new GridspaceClientError('UNAVAILABLE');
		try {
			const decoded: unknown = JSON.parse(openGridspaceSecret(this.peer, value, `client-read:${source}:${binding}`));
			if (!decoded || typeof decoded !== 'object' || !('value' in decoded) || typeof decoded.value !== 'string' || !('expires' in decoded) || typeof decoded.expires !== 'number' || decoded.expires <= Date.now()) throw new Error();
			return decoded.value;
		} catch { throw new GridspaceClientError('INVALID_CURSOR'); }
	}

	public async status(viewer: MiLocalUser, token: MiAccessToken | null) {
		const auth = await this.authorize(viewer, token, 'read:account', false);
		const capability = await this.timeline.capability();
		const peerPrivate = auth.permissions.includes(CLIENT_PRIVATE_SCOPE);
		let peer: 'ok' | 'disabled' | 'unavailable' | 'unauthorized' = 'disabled';
		if (capability.enabled && peerPrivate) {
			const status = await this.links.privateStatus(viewer);
			peer = !status.available ? 'unavailable' : status.granted ? 'ok' : 'unauthorized';
		}
		await this.finish(viewer, token, 'read:account', false, auth.binding);
		return { version: 1, timeline: capability.enabled && auth.permissions.includes(CLIENT_TIMELINE_SCOPE),
			notifications: !!this.peer && auth.permissions.includes(CLIENT_NOTIFICATION_SCOPE), peerPrivate, peer };
	}

	public async home(viewer: MiLocalUser, token: MiAccessToken | null, input: ReadOptions) {
		const started = Date.now();
		const auth = await this.authorize(viewer, token, CLIENT_TIMELINE_SCOPE, input.includePrivate);
		if (!(await this.timeline.capability()).enabled) throw new GridspaceClientError('UNAVAILABLE');
		const cursor = this.decode(input.cursor, auth.binding, 'home');
		const page = await this.timeline.page(viewer, { kind: 'home', clientContext: auth.binding, clientLocalOnly: !input.includePrivate },
			input.limit, cursor, input.includePrivate ? 'unified' : 'local-fallback');
		await this.finish(viewer, token, CLIENT_TIMELINE_SCOPE, input.includePrivate, auth.binding);
		const elapsed = Date.now() - started;
		return { version: 1, items: page.items.flatMap(item => {
			const note = clientNote(item.payload, this.origin);
			const validForMs = item.validForMs == null ? null : Math.max(0, item.validForMs - elapsed);
			return note && validForMs !== 0 ? [{ key: item.key, note, validForMs, nextPolicyCheckAt: item.nextPolicyCheckAt }] : [];
		}), nextCursor: this.cursor(page.nextCursor, auth.binding, 'home'), complete: page.complete,
			sources: page.sources, revalidateAfterMs: page.revalidateAfterMs };
	}

	public async readNotifications(viewer: MiLocalUser, token: MiAccessToken | null, input: ReadOptions & { source: Source }) {
		const started = Date.now();
		const auth = await this.authorize(viewer, token, CLIENT_NOTIFICATION_SCOPE, input.includePrivate);
		if (!this.peer) throw new GridspaceClientError('UNAVAILABLE');
		if (input.source !== 'local' && !input.includePrivate) throw new GridspaceClientError('PERMISSION_DENIED');
		const before = this.decode(input.cursor, auth.binding, input.source);
		try {
			const page = input.source === 'local'
				? await this.notifications.local(viewer, { before, limit: input.limit })
				: await this.notifications.remote(viewer, { before, limit: input.limit }, 'query', input.source === 'channel');
			await this.finish(viewer, token, CLIENT_NOTIFICATION_SCOPE, input.includePrivate, auth.binding);
			const items = page.items.map(item => {
				const notification = 'notification' in item ? item.notification : item;
				const user = 'user' in notification ? notification.user : null;
				const note = 'note' in notification ? notification.note : null;
				return { key: `${page.origin}:${item.id}`, id: item.id, createdAt: item.createdAt, type: notification.type, isRead: item.isRead,
					user: user ? clientAuthor(user, page.origin) : null,
					note: note ? clientNote(note, this.origin) : null,
					body: 'body' in notification && typeof notification.body === 'string' ? notification.body : null,
					reaction: 'reaction' in notification && typeof notification.reaction === 'string' ? notification.reaction : null };
			});
			return { version: 1, items, nextCursor: this.cursor(page.next, auth.binding, input.source),
				source: { source: input.source, status: 'ok' as const, retryable: false }, unreadCount: page.unreadCount,
				validForMs: Math.max(0, 60_000 - (Date.now() - started)), revalidateAfterMs: CLIENT_REVALIDATE_MS };
		} catch (error) {
			if (!(error instanceof GridspaceLinkError) || !['LINK_REVOKED', 'AUTHORIZATION_REVOKED', 'PEER_UNAVAILABLE', 'UNAVAILABLE'].includes(error.code)) throw error;
			await this.finish(viewer, token, CLIENT_NOTIFICATION_SCOPE, input.includePrivate, auth.binding);
			const unauthorized = ['LINK_REVOKED', 'AUTHORIZATION_REVOKED'].includes(error.code);
			return { version: 1, items: [], nextCursor: null,
				source: { source: input.source, status: unauthorized ? 'unauthorized' as const : 'unavailable' as const, retryable: !unauthorized },
				unreadCount: null, validForMs: 0, revalidateAfterMs: CLIENT_REVALIDATE_MS };
		}
	}
}
