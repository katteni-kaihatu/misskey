/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import MkAvatarWalkGame from './MkAvatarWalkGame.vue';
import type { StoryObj } from '@storybook/vue3';

export const Default = {
	render(args) {
		return {
			components: {
				MkAvatarWalkGame,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkAvatarWalkGame v-bind="args" />',
		};
	},
	parameters: {
		layout: 'fullscreen',
	},
} satisfies StoryObj<typeof MkAvatarWalkGame>;

export const Compact = {
	...Default,
	args: {
		compact: true,
	},
} satisfies StoryObj<typeof MkAvatarWalkGame>;
