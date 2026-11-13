/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/** Only the bundled game runtime may be framed by its own instance. */
export function clientFrameOptions(url: string): 'SAMEORIGIN' | 'DENY' {
	return url.split('?', 1)[0] === '/client-assets/doom/index.html' ? 'SAMEORIGIN' : 'DENY';
}
