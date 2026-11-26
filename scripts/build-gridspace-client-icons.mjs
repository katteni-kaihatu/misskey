/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(new URL('../packages/backend/package.json', import.meta.url));
const sharp = require('sharp');
const input = new URL('../assets/gridspace/web-client-icons/', import.meta.url);
const output = new URL('../packages/frontend/assets/gridspace/client-icons/', import.meta.url);
await mkdir(output, { recursive: true });

for (const [name, extension] of [['sakami', 'webp'], ['tekerets', 'png'], ['sharuya', 'webp'], ['machiyoh', 'webp'], ['ningen', 'webp']]) {
	for (const [size, suffix] of [[128, ''], [64, '-favicon']]) {
		await sharp(fileURLToPath(new URL(`${name}.${extension}`, input)))
			.resize(size, size, { fit: 'contain' })
			.png()
			.toFile(fileURLToPath(new URL(`${name}${suffix}.png`, output)));
	}
}
