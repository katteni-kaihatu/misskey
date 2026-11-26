/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { PrimaryColumn, Entity, Index, JoinColumn, Column, ManyToOne } from 'typeorm';
import { id } from './util/id.js';
import { MiUser } from './User.js';
import type { MiNote } from './Note.js';

export const spaceAccesses = ['local', 'followers'] as const;
export const spaceNoteScopes = ['local', 'public', 'none'] as const;
export const spaceTilePlacements = ['everyone', 'host'] as const;

@Entity('space')
// 1人が同時に開けるスペースは1つ。同時に作ろうとしたときも DB で止める
@Index(['hostId'], { unique: true, where: '"endedAt" IS NULL' })
export class MiSpace {
	@PrimaryColumn(id())
	public id: string;

	@Index()
	@Column(id())
	public hostId: MiUser['id'];

	@ManyToOne(() => MiUser, {
		onDelete: 'CASCADE',
	})
	@JoinColumn()
	public host: MiUser | null;

	@Column('varchar', {
		length: 128,
	})
	public name: string;

	@Column('enum', {
		enum: spaceAccesses,
		default: 'local',
	})
	public access: typeof spaceAccesses[number];

	@Column('enum', {
		enum: spaceNoteScopes,
		default: 'local',
	})
	public noteScope: typeof spaceNoteScopes[number];

	@Column('enum', {
		enum: spaceTilePlacements,
		default: 'everyone',
		comment: 'タイルを置ける人',
	})
	public tilePlacement: typeof spaceTilePlacements[number];

	@Column({
		...id(),
		nullable: true,
		comment: '「続きをひらく」の元のスペース',
	})
	public continuedFromId: MiSpace['id'] | null;

	@Column({
		...id(),
		nullable: true,
	})
	public announceNoteId: MiNote['id'] | null;

	@Column({
		...id(),
		nullable: true,
	})
	public summaryNoteId: MiNote['id'] | null;

	@Column({
		...id(),
		array: true, default: '{}',
		comment: '一度でも入った人',
	})
	public participantIds: MiUser['id'][];

	@Column('integer', {
		default: 0,
	})
	public peakCount: number;

	@Index()
	@Column('timestamp with time zone', {
		nullable: true,
		comment: 'null なら開いている',
	})
	public endedAt: Date | null;
}
