/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
/* eslint-disable import/no-default-export */
import type { StoryObj } from '@storybook/vue3';
import MkFlashPlayer from './MkFlashPlayer.vue';

export const Default = {
	render(args) {
		return {
			components: {
				MkFlashPlayer,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkFlashPlayer v-bind="args"/>',
		};
	},
	args: {
		flashId: 'someflashid',
	},
	parameters: {
		layout: 'centered',
	},
} satisfies StoryObj<typeof MkFlashPlayer>;
