/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
/* eslint-disable import/no-default-export */
import type { StoryObj } from '@storybook/vue3';
import MkSpaceBar from './MkSpaceBar.vue';

// 参加中のスペースが無いときは何も描かない
export const Default = {
	render(args) {
		return {
			components: {
				MkSpaceBar,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkSpaceBar v-bind="args"/>',
		};
	},
	args: {},
	parameters: {
		layout: 'centered',
	},
} satisfies StoryObj<typeof MkSpaceBar>;
