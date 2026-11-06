/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type { StoryObj } from '@storybook/vue3';
import MkAutoTranslatedNote from './MkAutoTranslatedNote.vue';
import { note } from '../../.storybook/fakes.js';

export const Default = {
	render(args) {
		return {
			components: { MkAutoTranslatedNote },
			setup() { return { args }; },
			template: '<MkAutoTranslatedNote v-bind="args" v-slot="{ text }">{{ text }}</MkAutoTranslatedNote>',
		};
	},
	args: { note: note(), active: false },
	parameters: { layout: 'centered' },
} satisfies StoryObj<typeof MkAutoTranslatedNote>;
