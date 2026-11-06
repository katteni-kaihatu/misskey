/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export class AutoTranslation1793987312305 {
	name = 'AutoTranslation1793987312305';

	async up(queryRunner) {
		await queryRunner.query(`CREATE TABLE "auto_translation_config" ("id" integer NOT NULL, "enabled" boolean NOT NULL DEFAULT false, "baseUrl" character varying(2048) NOT NULL DEFAULT '', "model" character varying(256) NOT NULL DEFAULT '', "apiKey" character varying(4096), "allowPrivateNetwork" boolean NOT NULL DEFAULT false, "maxConcurrency" integer NOT NULL DEFAULT 16, "revision" character varying(36) NOT NULL DEFAULT '', CONSTRAINT "PK_auto_translation_config" PRIMARY KEY ("id"))`);
	}

	async down(queryRunner) {
		await queryRunner.query('DROP TABLE "auto_translation_config"');
	}
}
