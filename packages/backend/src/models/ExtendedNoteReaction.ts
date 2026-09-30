/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Column, Entity, Index, JoinColumn, ManyToOne, PrimaryColumn } from 'typeorm';
import { id } from './util/id.js';
import { MiNote } from './Note.js';
import { MiUser } from './User.js';

/** Additional, instance-local reactions. Never rendered as ActivityPub Likes. */
@Entity('extended_note_reaction')
@Index('IDX_extended_reaction_user_note_emoji', ['userId', 'noteId', 'reaction'], { unique: true })
export class MiExtendedNoteReaction {
	@PrimaryColumn({ ...id(), primaryKeyConstraintName: 'PK_extended_reaction' })
	public id: string;

	@Index('IDX_extended_reaction_user')
	@Column(id())
	public userId: MiUser['id'];

	@ManyToOne(() => MiUser, { onDelete: 'CASCADE' })
	@JoinColumn({ foreignKeyConstraintName: 'FK_extended_reaction_user' })
	public user?: MiUser | null;

	@Index('IDX_extended_reaction_note')
	@Column(id())
	public noteId: MiNote['id'];

	@ManyToOne(() => MiNote, { onDelete: 'CASCADE' })
	@JoinColumn({ foreignKeyConstraintName: 'FK_extended_reaction_note' })
	public note?: MiNote | null;

	@Column('varchar', { length: 260 })
	public reaction: string;
}
