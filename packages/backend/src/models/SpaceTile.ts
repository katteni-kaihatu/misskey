/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { PrimaryColumn, Entity, Index, JoinColumn, Column, ManyToOne } from 'typeorm';
import { id } from './util/id.js';
import { MiSpace } from './Space.js';
import type { MiUser } from './User.js';
import { MiSpaceTileDef } from './SpaceTileDef.js';

/** きほんのタイルの種類 */
export const spaceTileKinds = ['note', 'image', 'poll', 'todo', 'draw', 'memo', 'link', 'play', 'timer'] as const;
export type SpaceTileKind = typeof spaceTileKinds[number];
/** 自作タイルの種類。コードは `defId` が指す定義にある */
export const SPACE_TILE_KIND_CUSTOM = 'custom';

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

	@Index()
	@Column({
		...id(),
		nullable: true,
		comment: '自作タイルの定義。きほんのタイルは null。定義が消されると null になる',
	})
	public defId: MiSpaceTileDef['id'] | null;

	@ManyToOne(() => MiSpaceTileDef, {
		onDelete: 'SET NULL',
	})
	@JoinColumn()
	public def: MiSpaceTileDef | null;

	@Column('varchar', {
		length: 253, array: true, default: '{}',
		comment: '置いた人が space.fetch に許したドメイン',
	})
	public allowedHosts: string[];

	@Column('boolean', {
		default: false,
		comment: 'ホストだけが操作できる',
	})
	public hostOnly: boolean;

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
