/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * @typedef {import('typeorm').MigrationInterface} MigrationInterface
 * @typedef {import('typeorm').QueryRunner} QueryRunner
 */

/**
 * @class
 * @implements {MigrationInterface}
 */
export class AddSpaceTileDef1795676597727 {
    name = 'AddSpaceTileDef1795676597727'

    /**
     * @param {QueryRunner} queryRunner
     */
    async up(queryRunner) {
        await queryRunner.query(`CREATE TYPE "public"."space_tile_def_visibility_enum" AS ENUM('public', 'private')`);
        await queryRunner.query(`CREATE TABLE "space_tile_def" ("id" character varying(32) NOT NULL, "userId" character varying(32) NOT NULL, "name" character varying(100) NOT NULL, "description" character varying(1000) NOT NULL DEFAULT '', "code" text NOT NULL, "fetchHosts" character varying(253) array NOT NULL DEFAULT '{}', "visibility" "public"."space_tile_def_visibility_enum" NOT NULL DEFAULT 'public', "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL, CONSTRAINT "PK_9999e544e1e479ed3b759473898" PRIMARY KEY ("id")); COMMENT ON COLUMN "space_tile_def"."userId" IS '作者'; COMMENT ON COLUMN "space_tile_def"."code" IS '枠の中で動く HTML と JavaScript'; COMMENT ON COLUMN "space_tile_def"."fetchHosts" IS 'space.fetch で読みに行く先のドメイン'; COMMENT ON COLUMN "space_tile_def"."visibility" IS 'public なら一覧に出る'; COMMENT ON COLUMN "space_tile_def"."updatedAt" IS '最後に書き換えた時'`);
        await queryRunner.query(`CREATE INDEX "IDX_9faac55d42ebea380927748117" ON "space_tile_def"  ("userId") `);
        await queryRunner.query(`CREATE INDEX "IDX_333433714409ab73bd21de945d" ON "space_tile_def"  ("visibility") `);
        await queryRunner.query(`ALTER TABLE "space_tile" ADD "defId" character varying(32)`);
        await queryRunner.query(`COMMENT ON COLUMN "space_tile"."defId" IS '自作タイルの定義。きほんのタイルは null。定義が消されると null になる'`);
        await queryRunner.query(`ALTER TABLE "space_tile" ADD "allowedHosts" character varying(253) array NOT NULL DEFAULT '{}'`);
        await queryRunner.query(`COMMENT ON COLUMN "space_tile"."allowedHosts" IS '置いた人が space.fetch に許したドメイン'`);
        await queryRunner.query(`ALTER TABLE "space_tile" ADD "hostOnly" boolean NOT NULL DEFAULT false`);
        await queryRunner.query(`COMMENT ON COLUMN "space_tile"."hostOnly" IS 'ホストだけが操作できる'`);
        await queryRunner.query(`CREATE INDEX "IDX_f04240b4bc46ed268a840f55d2" ON "space_tile"  ("defId") `);
        await queryRunner.query(`ALTER TABLE "space_tile_def" ADD CONSTRAINT "FK_9faac55d42ebea3809277481178" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "space_tile" ADD CONSTRAINT "FK_f04240b4bc46ed268a840f55d22" FOREIGN KEY ("defId") REFERENCES "space_tile_def"("id") ON DELETE SET NULL ON UPDATE NO ACTION`);
    }

    /**
     * @param {QueryRunner} queryRunner
     */
    async down(queryRunner) {
        await queryRunner.query(`ALTER TABLE "space_tile" DROP CONSTRAINT "FK_f04240b4bc46ed268a840f55d22"`);
        await queryRunner.query(`ALTER TABLE "space_tile_def" DROP CONSTRAINT "FK_9faac55d42ebea3809277481178"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_f04240b4bc46ed268a840f55d2"`);
        await queryRunner.query(`COMMENT ON COLUMN "space_tile"."hostOnly" IS 'ホストだけが操作できる'`);
        await queryRunner.query(`ALTER TABLE "space_tile" DROP COLUMN "hostOnly"`);
        await queryRunner.query(`COMMENT ON COLUMN "space_tile"."allowedHosts" IS '置いた人が space.fetch に許したドメイン'`);
        await queryRunner.query(`ALTER TABLE "space_tile" DROP COLUMN "allowedHosts"`);
        await queryRunner.query(`COMMENT ON COLUMN "space_tile"."defId" IS '自作タイルの定義。きほんのタイルは null。定義が消されると null になる'`);
        await queryRunner.query(`ALTER TABLE "space_tile" DROP COLUMN "defId"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_333433714409ab73bd21de945d"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_9faac55d42ebea380927748117"`);
        await queryRunner.query(`DROP TABLE "space_tile_def"`);
        await queryRunner.query(`DROP TYPE "public"."space_tile_def_visibility_enum"`);
    }
}
