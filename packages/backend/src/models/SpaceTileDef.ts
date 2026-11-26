/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { PrimaryColumn, Entity, Index, JoinColumn, Column, ManyToOne } from 'typeorm';
import { id } from './util/id.js';
import { MiUser } from './User.js';

export const spaceTileDefVisibilities = ['public', 'private'] as const;
export type SpaceTileDefVisibility = typeof spaceTileDefVisibilities[number];

/** 自作タイルの定義。スペースに置いたタイル (space_tile) がこれを指す。 */
@Entity('space_tile_def')
export class MiSpaceTileDef {
	@PrimaryColumn(id())
	public id: string;

	@Index()
	@Column({
		...id(),
		comment: '作者',
	})
	public userId: MiUser['id'];

	@ManyToOne(() => MiUser, {
		onDelete: 'CASCADE',
	})
	@JoinColumn()
	public user: MiUser | null;

	@Column('varchar', {
		length: 100,
	})
	public name: string;

	@Column('varchar', {
		length: 1000, default: '',
	})
	public description: string;

	@Column('text', {
		comment: '枠の中で動く HTML と JavaScript',
	})
	public code: string;

	@Column('varchar', {
		length: 253, array: true, default: '{}',
		comment: 'space.fetch で読みに行く先のドメイン',
	})
	public fetchHosts: string[];

	@Index()
	@Column('enum', {
		enum: spaceTileDefVisibilities,
		default: 'public',
		comment: 'public なら一覧に出る',
	})
	public visibility: SpaceTileDefVisibility;

	@Column('timestamp with time zone', {
		comment: '最後に書き換えた時',
	})
	public updatedAt: Date;
}
