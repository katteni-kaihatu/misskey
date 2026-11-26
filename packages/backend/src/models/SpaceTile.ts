/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { PrimaryColumn, Entity, Index, JoinColumn, Column, ManyToOne } from 'typeorm';
import { id } from './util/id.js';
import { MiSpace } from './Space.js';
import type { MiUser } from './User.js';

/** きほんのタイルの種類。段階4で自作タイルを足すときは、コードを指す列を別に足す */
export const spaceTileKinds = ['note', 'image', 'poll', 'todo', 'draw', 'memo', 'link', 'play', 'timer'] as const;
export type SpaceTileKind = typeof spaceTileKinds[number];

@Entity('space_tile')
export class MiSpaceTile {
	@PrimaryColumn(id())
	public id: string;

	@Index()
	@Column(id())
	public spaceId: MiSpace['id'];

	@ManyToOne(() => MiSpace, {
		onDelete: 'CASCADE',
	})
	@JoinColumn()
	public space: MiSpace | null;

	@Column('varchar', {
		length: 64,
	})
	public kind: string;

	@Column({
		...id(),
		comment: '置いた人',
	})
	public creatorId: MiUser['id'];

	@Column('integer', {
		default: 0,
		comment: '並び順',
	})
	public position: number;

	@Column('jsonb', {
		default: {},
		comment: '共有する値の保存。開いている間の正は Redis にある',
	})
	public shared: Record<string, unknown>;
}
