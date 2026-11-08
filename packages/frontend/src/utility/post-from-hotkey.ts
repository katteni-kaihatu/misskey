/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { $i } from '@/i.js';
import { apiWithDialog, post } from '@/os.js';
import { mainRouter } from '@/router.js';

export async function postFromHotkey(): Promise<void> {
	if ($i == null) return;

	const current = mainRouter.current;
	if (current.route.path !== '/channels/:channelId') {
		await post();
		return;
	}

	const channelId = current.props.get('channelId');
	if (typeof channelId !== 'string') return;

	const channel = await apiWithDialog('channels/show', { channelId }).catch(() => null);
	if (channel == null || mainRouter.current !== current) return;

	await post({ channel });
}
