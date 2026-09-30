/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export class ExtendedNoteReactions1790758122262 {
	name = 'ExtendedNoteReactions1790758122262';

	async up(queryRunner) {
		await queryRunner.query(`CREATE TABLE "extended_note_reaction" ("id" varchar(32) NOT NULL, "userId" varchar(32) NOT NULL, "noteId" varchar(32) NOT NULL, "reaction" varchar(260) NOT NULL, CONSTRAINT "PK_extended_reaction" PRIMARY KEY ("id"))`);
		await queryRunner.query(`CREATE UNIQUE INDEX "IDX_extended_reaction_user_note_emoji" ON "extended_note_reaction" ("userId", "noteId", "reaction")`);
		await queryRunner.query(`CREATE INDEX "IDX_extended_reaction_user" ON "extended_note_reaction" ("userId")`);
		await queryRunner.query(`CREATE INDEX "IDX_extended_reaction_note" ON "extended_note_reaction" ("noteId")`);
		await queryRunner.query(`ALTER TABLE "extended_note_reaction" ADD CONSTRAINT "FK_extended_reaction_user" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE`);
		await queryRunner.query(`ALTER TABLE "extended_note_reaction" ADD CONSTRAINT "FK_extended_reaction_note" FOREIGN KEY ("noteId") REFERENCES "note"("id") ON DELETE CASCADE`);
	}

	async down(queryRunner) {
		await queryRunner.query(`DROP TABLE "extended_note_reaction"`);
	}
}
