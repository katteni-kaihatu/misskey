/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
import type { StoryObj } from '@storybook/vue3';
import MkXriftSettings from './MkXriftSettings.vue';

export const Default = {
	render(args) {
		return { components: { MkXriftSettings }, setup: () => ({ args }), template: '<MkXriftSettings v-bind="args"/>' };
	},
	args: { configured: false },
	parameters: { layout: 'padded' },
} satisfies StoryObj<typeof MkXriftSettings>;

export const Configured = {
	...Default,
	args: { configured: true },
} satisfies StoryObj<typeof MkXriftSettings>;
