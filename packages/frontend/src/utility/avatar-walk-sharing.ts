/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type * as Misskey from 'misskey-js';
import { $i } from '@/i.js';
import { uploadFile } from '@/utility/drive.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import type { StoredAvatarWalkAtlas, StoredSharedAvatarWalkAtlas, StoredSharedAvatarWalkAtlasActive } from '@/utility/avatar-walk-atlas.js';
import {
	createSharedAvatarWalkAtlasImage,
	loadLegacySharedAvatarWalkAtlas,
	loadSharedAvatarWalkAtlas,
	removeLegacySharedAvatarWalkAtlas,
	removeSharedAvatarWalkAtlas,
	saveSharedAvatarWalkAtlas,
} from '@/utility/avatar-walk-atlas.js';
import { setAvatarWalkSharedAtlas } from '@/utility/avatar-walk-multiplayer.js';

let sharePromise: Promise<void> | null = null;
let removalPromise: Promise<boolean> | null = null;
let pendingCleanupPromise: Promise<void> | null = null;
let desiredShareKey: string | null = null;
let shareGeneration = 0;
let failedShareKey: string | null = null;
let retryAttemptedShareKey: string | null = null;
let retryTimer: number | null = null;

export async function syncAvatarWalkSharing(atlas: StoredAvatarWalkAtlas): Promise<void> {
	if (removalPromise != null) return;
	if (pendingCleanupPromise != null) {
		await pendingCleanupPromise;
		await syncAvatarWalkSharing(atlas);
		return;
	}
	const ownerUserId = $i?.id;
	if (ownerUserId == null) {
		invalidateDesiredShare(null);
		setAvatarWalkSharedAtlas(null);
		return;
	}

	const shareKey = `${ownerUserId}:${atlas.createdAt}`;
	if (desiredShareKey !== shareKey) invalidateDesiredShare(shareKey);
	const generation = shareGeneration;
	if (failedShareKey === shareKey) return;
	if (sharePromise != null) {
		await sharePromise;
		if (isCurrentShare(generation, shareKey)) await syncAvatarWalkSharing(atlas);
		return;
	}

	sharePromise = syncSharedAvatar(atlas, ownerUserId, generation, shareKey);
	try {
		await sharePromise;
	} catch {
		if (isCurrentShare(generation, shareKey)) {
			failedShareKey = shareKey;
			scheduleShareRetry(atlas, shareKey);
		}
	} finally {
		sharePromise = null;
	}
}

export async function removeAvatarWalkSharing(): Promise<boolean> {
	if (removalPromise != null) return removalPromise;
	if (pendingCleanupPromise != null) await pendingCleanupPromise;
	invalidateDesiredShare(null);
	setAvatarWalkSharedAtlas(null);
	removalPromise = removeCurrentSharedAvatar();
	try {
		return await removalPromise;
	} finally {
		removalPromise = null;
	}
}

export async function retryAvatarWalkPendingDeletes(): Promise<void> {
	if (pendingCleanupPromise != null) return pendingCleanupPromise;
	pendingCleanupPromise = cleanupPendingDeletes();
	try {
		await pendingCleanupPromise;
	} finally {
		pendingCleanupPromise = null;
	}
}

async function cleanupPendingDeletes(): Promise<void> {
	if (removalPromise != null) await removalPromise;
	if (sharePromise != null) await sharePromise.catch(() => undefined);
	const ownerUserId = $i?.id;
	if (ownerUserId == null) return;
	const stored = await loadSharedAvatarWalkAtlas(ownerUserId);
	if (stored != null && stored.pendingDeleteFileIds.length > 0) await retryPendingDeletes(stored);
}

async function removeCurrentSharedAvatar(): Promise<boolean> {
	if (sharePromise != null) {
		try {
			await sharePromise;
		} catch {
			// Continue removing any previous shared atlas.
		}
	}
	const ownerUserId = $i?.id;
	if (ownerUserId == null) return true;
	const stored = await loadSharedAvatarWalkAtlas(ownerUserId);
	if (stored == null) {
		await removeSharedAvatarWalkAtlas(ownerUserId);
		return true;
	}

	const failedDeletes: string[] = [];
	const fileIds = stored.active == null
		? stored.pendingDeleteFileIds
		: [stored.active.fileId, ...stored.pendingDeleteFileIds];
	for (const fileId of new Set(fileIds)) {
		if (!await deleteSharedDriveFile(fileId)) failedDeletes.push(fileId);
	}
	if (failedDeletes.length === 0) {
		await removeSharedAvatarWalkAtlas(ownerUserId);
	} else {
		await saveSharedAvatarWalkAtlas({
			ownerUserId,
			active: null,
			pendingDeleteFileIds: failedDeletes,
		});
	}
	return failedDeletes.length === 0;
}

async function syncSharedAvatar(atlas: StoredAvatarWalkAtlas, ownerUserId: string, generation: number, shareKey: string): Promise<void> {
	let stored = await loadSharedAvatarWalkAtlas(ownerUserId) ?? await migrateLegacySharedAvatar(ownerUserId);
	if (!isCurrentShare(generation, shareKey)) return;
	if (stored?.active?.sourceCreatedAt === atlas.createdAt) {
		const driveFile = await getSharedDriveFile(stored.active.fileId, ownerUserId);
		if (!isCurrentShare(generation, shareKey)) return;
		if (driveFile != null && isUsableSharedDriveFile(driveFile)) {
			setAvatarWalkSharedAtlas(toSharedAtlasInput(stored.active));
			await retryPendingDeletes(stored);
			return;
		}
		stored = {
			...stored,
			active: null,
			pendingDeleteFileIds: driveFile == null
				? stored.pendingDeleteFileIds
				: [...stored.pendingDeleteFileIds, stored.active.fileId],
		};
		await saveSharedAvatarWalkAtlas(stored);
	} else if (stored?.active != null) {
		stored = {
			...stored,
			active: null,
			pendingDeleteFileIds: [...stored.pendingDeleteFileIds, stored.active.fileId],
		};
		await saveSharedAvatarWalkAtlas(stored);
	}
	if (!isCurrentShare(generation, shareKey)) return;
	setAvatarWalkSharedAtlas(null);
	await publishSharedAvatar(atlas, ownerUserId, stored, generation, shareKey);
}

async function publishSharedAvatar(atlas: StoredAvatarWalkAtlas, ownerUserId: string, previous: StoredSharedAvatarWalkAtlas | null, generation: number, shareKey: string): Promise<void> {
	const sharedImage = await createSharedAvatarWalkAtlasImage(atlas);
	if (!isCurrentShare(generation, shareKey)) return;
	const extension = sharedImage.image.type === 'image/webp' ? 'webp' : 'png';
	const driveFile = await uploadFile(sharedImage.image, {
		name: `avatar-walk-atlas-${Date.now()}.${extension}`,
		isSensitive: false,
	}).filePromise;
	const active: StoredSharedAvatarWalkAtlasActive = {
		fileId: driveFile.id,
		sourceCreatedAt: atlas.createdAt,
		version: sharedImage.version,
		cellWidth: sharedImage.cellWidth,
		cellHeight: sharedImage.cellHeight,
		directionCount: sharedImage.directionCount,
		idleFrameCount: sharedImage.idleFrameCount,
		walkFrameCount: sharedImage.walkFrameCount,
	};
	if (!isCurrentShare(generation, shareKey)) {
		await deleteOrRememberCanceledUpload(ownerUserId, driveFile.id);
		return;
	}
	const next: StoredSharedAvatarWalkAtlas = {
		ownerUserId,
		active,
		pendingDeleteFileIds: previous?.pendingDeleteFileIds ?? [],
	};
	await saveSharedAvatarWalkAtlas(next);
	if (!isCurrentShare(generation, shareKey)) {
		await cancelSavedUpload(next);
		return;
	}
	failedShareKey = null;
	setAvatarWalkSharedAtlas(toSharedAtlasInput(active));
	await retryPendingDeletes(next);
}

async function retryPendingDeletes(shared: StoredSharedAvatarWalkAtlas): Promise<void> {
	const remaining: string[] = [];
	for (const fileId of new Set(shared.pendingDeleteFileIds)) {
		if (!await deleteSharedDriveFile(fileId)) remaining.push(fileId);
	}
	if (remaining.length !== shared.pendingDeleteFileIds.length) {
		await saveSharedAvatarWalkAtlas({ ...shared, pendingDeleteFileIds: remaining });
	}
}

async function migrateLegacySharedAvatar(ownerUserId: string): Promise<StoredSharedAvatarWalkAtlas | null> {
	const legacy = await loadLegacySharedAvatarWalkAtlas();
	if (legacy == null) return null;
	const driveFile = await getSharedDriveFile(legacy.fileId, ownerUserId);
	if (driveFile == null || !isUsableSharedDriveFile(driveFile)) return null;
	const migrated: StoredSharedAvatarWalkAtlas = {
		ownerUserId,
		active: legacy,
		pendingDeleteFileIds: [],
	};
	await saveSharedAvatarWalkAtlas(migrated);
	await removeLegacySharedAvatarWalkAtlas();
	return migrated;
}

async function getSharedDriveFile(fileId: string, ownerUserId: string): Promise<Misskey.entities.DriveFile | null> {
	try {
		const file = await misskeyApi('drive/files/show', { fileId });
		return file.id === fileId && file.userId === ownerUserId ? file : null;
	} catch (error) {
		if (hasMisskeyErrorCode(error, 'NO_SUCH_FILE')) return null;
		throw error;
	}
}

function isUsableSharedDriveFile(file: Misskey.entities.DriveFile): boolean {
	return file.type.startsWith('image/') && !file.isSensitive && file.size <= 20 * 1024 * 1024;
}

async function deleteSharedDriveFile(fileId: string): Promise<boolean> {
	try {
		await misskeyApi('drive/files/delete', { fileId });
		return true;
	} catch (error) {
		return hasMisskeyErrorCode(error, 'NO_SUCH_FILE');
	}
}

async function deleteOrRememberCanceledUpload(ownerUserId: string, fileId: string): Promise<void> {
	if (await deleteSharedDriveFile(fileId)) return;
	const stored = await loadSharedAvatarWalkAtlas(ownerUserId);
	await saveSharedAvatarWalkAtlas({
		ownerUserId,
		active: stored?.active ?? null,
		pendingDeleteFileIds: [...stored?.pendingDeleteFileIds ?? [], fileId],
	});
}

async function cancelSavedUpload(shared: StoredSharedAvatarWalkAtlas): Promise<void> {
	const fileId = shared.active?.fileId;
	if (fileId == null) return;
	const deleted = await deleteSharedDriveFile(fileId);
	const canceled: StoredSharedAvatarWalkAtlas = {
		...shared,
		active: null,
		pendingDeleteFileIds: deleted ? shared.pendingDeleteFileIds : [...shared.pendingDeleteFileIds, fileId],
	};
	if (canceled.pendingDeleteFileIds.length === 0) {
		await removeSharedAvatarWalkAtlas(shared.ownerUserId);
	} else {
		await saveSharedAvatarWalkAtlas(canceled);
	}
}

function hasMisskeyErrorCode(error: unknown, code: string): boolean {
	return typeof error === 'object' && error != null && 'code' in error && error.code === code;
}

function invalidateDesiredShare(nextShareKey: string | null): void {
	if (retryTimer != null) {
		window.clearTimeout(retryTimer);
		retryTimer = null;
	}
	desiredShareKey = nextShareKey;
	shareGeneration++;
	failedShareKey = null;
	retryAttemptedShareKey = null;
}

function scheduleShareRetry(atlas: StoredAvatarWalkAtlas, shareKey: string): void {
	if (retryAttemptedShareKey === shareKey) return;
	retryAttemptedShareKey = shareKey;
	if (retryTimer != null) window.clearTimeout(retryTimer);
	retryTimer = window.setTimeout(() => {
		retryTimer = null;
		if (desiredShareKey !== shareKey || removalPromise != null) return;
		failedShareKey = null;
		void syncAvatarWalkSharing(atlas);
	}, 5000);
}

function isCurrentShare(generation: number, shareKey: string): boolean {
	return shareGeneration === generation && desiredShareKey === shareKey;
}

function toSharedAtlasInput(shared: StoredSharedAvatarWalkAtlasActive): Misskey.AvatarWalkSharedAtlasInput {
	return {
		fileId: shared.fileId,
		version: shared.version,
		cellWidth: shared.cellWidth,
		cellHeight: shared.cellHeight,
		directionCount: shared.directionCount,
		idleFrameCount: shared.idleFrameCount,
		walkFrameCount: shared.walkFrameCount,
	};
}
