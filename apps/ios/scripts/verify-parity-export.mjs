// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

// Run via `pnpm --filter frontend exec tsx` so the product codec is used.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { readLocalDataSnapshot, transferLocationID } from '../../../packages/frontend/src/utility/local-data-transfer.ts';

const [directory, file] = process.argv.slice(2);
if (!directory || !file) throw new Error('Specify the private parity directory and exported archive');
let stage = 'fixture decode';
try {
	const expected = await readLocalDataSnapshot(new Blob([await readFile(join(directory, 'parity-import.gridspace-localdata'))]));
	stage = 'export decode';
	const actual = await readLocalDataSnapshot(new Blob([await readFile(file)]));
	stage = 'identity';
	assert.equal(actual.source.origin, expected.source.origin);
	assert.equal(actual.source.userId, expected.source.userId);
	assert.notEqual(actual.id, expected.id, 'Verify a new export, not the original import file');
	for (const record of expected.records) {
		stage = record.storage === 'idb' ? 'blob' : 'local data';
		const result = actual.records.find(value => transferLocationID(value) === transferLocationID(record));
		assert.ok(result);
		if (record.storage === 'idb') {
			assert.ok(record.value.binary instanceof Blob && result.value.binary instanceof Blob);
			assert.equal(result.value.binary.type, record.value.binary.type);
			assert.deepEqual(new Uint8Array(await result.value.binary.arrayBuffer()), new Uint8Array(await record.value.binary.arrayBuffer()));
			assert.deepEqual({ ...result.value, binary: null }, { ...record.value, binary: null });
		} else {
			assert.deepEqual(result.value, record.value);
		}
	}
	console.log('PASS: native export preserves synthetic identity, drafts, script values, unknown fields and 2 MiB Blob bytes');
} catch (error) {
	// Never print record contents or a caller's archive in assertion diagnostics.
	console.error('FAIL: the exported archive does not preserve the synthetic fixture (' + stage + ')');
	if (typeof error?.code === 'string' && /^[a-z-]{1,32}$/.test(error.code)) console.error('Validation code: ' + error.code);
	process.exitCode = 1;
}
