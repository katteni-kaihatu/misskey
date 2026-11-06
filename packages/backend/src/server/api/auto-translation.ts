/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { AutoTranslationError } from '@/core/auto-translation/AutoTranslationService.js';
import { ApiError } from './error.js';

export const configResponse = {
	type: 'object', optional: false, nullable: false,
	properties: {
		enabled: { type: 'boolean', optional: false, nullable: false },
		baseUrl: { type: 'string', optional: false, nullable: false },
		model: { type: 'string', optional: false, nullable: false },
		apiKeyConfigured: { type: 'boolean', optional: false, nullable: false },
		allowPrivateNetwork: { type: 'boolean', optional: false, nullable: false },
		maxConcurrency: { type: 'integer', optional: false, nullable: false },
	},
} as const;

export const translationErrors = {
	unavailable: { message: 'Automatic translation is unavailable.', code: 'UNAVAILABLE', id: '099b706b-092f-4ac4-9aaa-3fe304792cc1' },
	not_found: { message: 'No such note.', code: 'NO_SUCH_NOTE', id: '143dfdbd-7a42-4891-af50-57acb619368c' },
	not_visible: { message: 'Cannot translate invisible note.', code: 'CANNOT_TRANSLATE_INVISIBLE_NOTE', id: '583c9f51-3af2-47f2-85e3-589f1b8a0f57' },
	invalid_language: { message: 'Unsupported target language.', code: 'INVALID_LANGUAGE', id: 'b0296260-a989-4c65-8edc-dc6d8818d3d5' },
	invalid_config: { message: 'Invalid automatic translation configuration.', code: 'INVALID_CONFIG', id: '839bb130-4d24-4da0-a0c8-771e57bfcdd9' },
	busy: { message: 'Automatic translation is busy. Try again later.', code: 'TRANSLATION_BUSY', id: '16cb36b5-8ca7-44fa-9d6a-8321aa1e4319' },
	upstream: { message: 'Translation provider failed.', code: 'TRANSLATION_FAILED', id: 'ac5f901b-25ba-49cd-b7b9-527a1f0e76b1' },
} as const;

export function translationFailure(error: unknown): never {
	if (error instanceof AutoTranslationError) throw new ApiError(translationErrors[error.reason]);
	// Provider and persistence errors may contain authorization or SQL parameters.
	throw new ApiError(translationErrors.upstream);
}
