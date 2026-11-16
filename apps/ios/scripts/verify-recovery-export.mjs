// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

// Run through frontend's tsx to decode the actual native saved files.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { decodeLocalDataArchive } from '../../../packages/frontend/src/utility/local-data-archive.ts';
import { localDataFingerprint, readLocalDataSnapshot, transferLocationID } from '../../../packages/frontend/src/utility/local-data-transfer.ts';

const [directory, snapshotFile, recoveryFile] = process.argv.slice(2);
if (!directory || !snapshotFile || !recoveryFile) throw new Error('Specify the private fixture directory, snapshot and recovery export');
let stage = 'fixture decode';
async function decoded(file) { return decodeLocalDataArchive(new Blob([await readFile(file)])); }
async function comparable(value) {
	if (value instanceof Blob) {
		return { blob: true, size: value.size, mime: value.type,
			sha256: createHash('sha256').update(new Uint8Array(await value.arrayBuffer())).digest('hex'),
			...(typeof value.name === 'string' ? { name: value.name, lastModified: value.lastModified } : {}) };
	}
	if (Array.isArray(value)) return Promise.all(value.map(comparable));
	if (value !== null && typeof value === 'object') {
		return Object.fromEntries(await Promise.all(Object.entries(value).map(async ([key, child]) => [key, await comparable(child)])));
	}
	return value;
}
try {
	const expected = await decoded(join(directory, 'parity-recovery-expected.gridspace-localdata'));
	assert.equal(expected.format, 'gridspace-ios-recovery-fixture');
	assert.equal(expected.version, 1);
	assert.equal(expected.original.writes.length, 2);
	stage = 'recovery decode';
	const backup = await decoded(recoveryFile);
	assert.equal(backup.format, 'gridspace-local-recovery');
	assert.equal(backup.version, 1);
	assert.match(backup.info.id, /^[0-9a-f-]{36}$/i);
	assert.ok(Number.isFinite(Date.parse(backup.info.savedAt)));
	assert.deepEqual(backup.info.source, expected.original.source);
	stage = 'original binary journal';
	assert.deepEqual(await comparable(backup.original), await comparable(expected.original));
	assert.equal(backup.reviewed.phase, 'recovering');
	assert.equal(backup.reviewed.id, expected.original.id);
	assert.deepEqual(backup.reviewed.source, expected.original.source);
	assert.equal(backup.reviewed.writes.length, 2);
	stage = 'reviewed binary journal';
	for (const [index, write] of backup.reviewed.writes.entries()) {
		const original = expected.original.writes[index];
		assert.deepEqual(write.location, original.location);
		assert.deepEqual(await comparable(write.before), await comparable(original.before));
		assert.deepEqual(await comparable(write.after), await comparable(expected.current[index]));
		assert.equal(write.beforeHash, await localDataFingerprint(write.before));
		assert.equal(write.afterHash, await localDataFingerprint(write.after));
	}
	stage = 'normal snapshot';
	const snapshot = await readLocalDataSnapshot(new Blob([await readFile(snapshotFile)]));
	assert.notEqual(snapshot.id, expected.original.id);
	assert.equal(snapshot.source.origin, expected.original.source.origin);
	assert.equal(snapshot.source.userId, expected.original.source.userId);
	for (const write of expected.original.writes) {
		const record = snapshot.records.find(value => transferLocationID(value) === transferLocationID(write.location));
		assert.ok(record);
		assert.deepEqual(await comparable(record.value), await comparable(write.before.value));
	}
	for (const record of snapshot.records.filter(value => value.storage === 'idb' && value.key.startsWith('pizzax::'))) {
		for (const key of ['accountTokens', 'pluginTokens', 'accountInfos']) assert.equal(Object.hasOwn(record.value, key), false);
	}
	console.log('PASS: restored snapshot and recovery export preserve identity, original/imported/concurrent 2 MiB Blob bytes, MIME, unknown metadata and reviewed hashes');
} catch {
	// Assertions must not print credentials or archive bodies.
	console.error('FAIL: native recovery export mismatch (' + stage + ')');
	process.exitCode = 1;
}
