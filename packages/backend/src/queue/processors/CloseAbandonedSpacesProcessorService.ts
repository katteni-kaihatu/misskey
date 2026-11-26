/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { Injectable } from '@nestjs/common';
import type Logger from '@/logger.js';
import { bindThis } from '@/decorators.js';
import { SpaceService } from '@/core/spaces/SpaceService.js';
import { QueueLoggerService } from '../QueueLoggerService.js';

/** だれもいないまま時間が過ぎたスペースを閉じる。 */
@Injectable()
export class CloseAbandonedSpacesProcessorService {
	private logger: Logger;

	constructor(
		private spaceService: SpaceService,
		private queueLoggerService: QueueLoggerService,
	) {
		this.logger = this.queueLoggerService.logger.createSubLogger('close-abandoned-spaces');
	}

	@bindThis
	public async process(): Promise<void> {
		if (!this.spaceService.isEnabled()) return;
		const closed = await this.spaceService.closeAbandoned();
		if (closed > 0) this.logger.succ(`Closed ${closed} abandoned space(s).`);
	}
}
