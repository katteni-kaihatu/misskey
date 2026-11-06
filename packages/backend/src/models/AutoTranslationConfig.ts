/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Column, Entity, PrimaryColumn } from 'typeorm';

@Entity('auto_translation_config')
export class MiAutoTranslationConfig {
	@PrimaryColumn('integer')
	public id: number;

	@Column('boolean', { default: false })
	public enabled: boolean;

	@Column('varchar', { length: 2048, default: '' })
	public baseUrl: string;

	@Column('varchar', { length: 256, default: '' })
	public model: string;

	@Column('varchar', { length: 4096, nullable: true, select: false })
	public apiKey: string | null;

	@Column('boolean', { default: false })
	public allowPrivateNetwork: boolean;

	@Column('integer', { default: 16 })
	public maxConcurrency: number;

	@Column('varchar', { length: 36, default: '' })
	public revision: string;
}
