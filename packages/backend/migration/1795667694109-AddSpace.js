/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export class AddSpace1795667694109 {
    name = 'AddSpace1795667694109'

    /**
     * @param {QueryRunner} queryRunner
     */
    async up(queryRunner) {
        await queryRunner.query(`CREATE TYPE "public"."space_access_enum" AS ENUM('local', 'followers')`);
        await queryRunner.query(`CREATE TYPE "public"."space_notescope_enum" AS ENUM('local', 'public', 'none')`);
        await queryRunner.query(`CREATE TYPE "public"."space_tileplacement_enum" AS ENUM('everyone', 'host')`);
        await queryRunner.query(`CREATE TABLE "space" ("id" character varying(32) NOT NULL, "hostId" character varying(32) NOT NULL, "name" character varying(128) NOT NULL, "access" "public"."space_access_enum" NOT NULL DEFAULT 'local', "noteScope" "public"."space_notescope_enum" NOT NULL DEFAULT 'local', "tilePlacement" "public"."space_tileplacement_enum" NOT NULL DEFAULT 'everyone', "continuedFromId" character varying(32), "announceNoteId" character varying(32), "summaryNoteId" character varying(32), "participantIds" character varying(32) array NOT NULL DEFAULT '{}', "peakCount" integer NOT NULL DEFAULT '0', "endedAt" TIMESTAMP WITH TIME ZONE, CONSTRAINT "PK_094f5ec727fe052956a11623640" PRIMARY KEY ("id")); COMMENT ON COLUMN "space"."tilePlacement" IS 'タイルを置ける人'; COMMENT ON COLUMN "space"."continuedFromId" IS '「続きをひらく」の元のスペース'; COMMENT ON COLUMN "space"."participantIds" IS '一度でも入った人'; COMMENT ON COLUMN "space"."endedAt" IS 'null なら開いている'`);
        await queryRunner.query(`CREATE INDEX "IDX_8562a454774cdf1cb4f899472b" ON "space"  ("hostId") `);
        await queryRunner.query(`CREATE INDEX "IDX_ec4c20ba6dae176f9f547aa1db" ON "space"  ("endedAt") `);
        await queryRunner.query(`CREATE UNIQUE INDEX "IDX_11ab9f8771337fb1f4c769ef3e" ON "space"  ("hostId") WHERE "endedAt" IS NULL`);
        await queryRunner.query(`CREATE TABLE "space_tile" ("id" character varying(32) NOT NULL, "spaceId" character varying(32) NOT NULL, "kind" character varying(64) NOT NULL, "creatorId" character varying(32) NOT NULL, "position" integer NOT NULL DEFAULT '0', "shared" jsonb NOT NULL DEFAULT '{}', CONSTRAINT "PK_a7da823bcff35b422860492a625" PRIMARY KEY ("id")); COMMENT ON COLUMN "space_tile"."creatorId" IS '置いた人'; COMMENT ON COLUMN "space_tile"."position" IS '並び順'; COMMENT ON COLUMN "space_tile"."shared" IS '共有する値の保存。開いている間の正は Redis にある'`);
        await queryRunner.query(`CREATE INDEX "IDX_ac306c664c4937707d169b2774" ON "space_tile"  ("spaceId") `);
        await queryRunner.query(`ALTER TABLE "space" ADD CONSTRAINT "FK_8562a454774cdf1cb4f899472ba" FOREIGN KEY ("hostId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "space_tile" ADD CONSTRAINT "FK_ac306c664c4937707d169b27743" FOREIGN KEY ("spaceId") REFERENCES "space"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
    }

    /**
     * @param {QueryRunner} queryRunner
     */
    async down(queryRunner) {
        await queryRunner.query(`ALTER TABLE "space_tile" DROP CONSTRAINT "FK_ac306c664c4937707d169b27743"`);
        await queryRunner.query(`ALTER TABLE "space" DROP CONSTRAINT "FK_8562a454774cdf1cb4f899472ba"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_ac306c664c4937707d169b2774"`);
        await queryRunner.query(`DROP TABLE "space_tile"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_11ab9f8771337fb1f4c769ef3e"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_ec4c20ba6dae176f9f547aa1db"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_8562a454774cdf1cb4f899472b"`);
        await queryRunner.query(`DROP TABLE "space"`);
        await queryRunner.query(`DROP TYPE "public"."space_tileplacement_enum"`);
        await queryRunner.query(`DROP TYPE "public"."space_notescope_enum"`);
        await queryRunner.query(`DROP TYPE "public"."space_access_enum"`);
    }
}
