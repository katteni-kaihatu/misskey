/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export class XriftApiKey1794890440230 {
    name = 'XriftApiKey1794890440230';

    async up(queryRunner) {
        await queryRunner.query('ALTER TABLE "meta" ADD "xriftApiKey" character varying(1024)');
    }

    async down(queryRunner) {
        await queryRunner.query('ALTER TABLE "meta" DROP COLUMN "xriftApiKey"');
    }
}
