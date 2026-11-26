/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
/* eslint-disable import/no-default-export */
import type { StoryObj } from '@storybook/vue3';
import MkSpaceTileFrame from './MkSpaceTileFrame.vue';
import sample from '@/spaces/sample-tile.js';

export const Default = {
	render(args) {
		return {
			components: {
				MkSpaceTileFrame,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkSpaceTileFrame v-bind="args"/>',
		};
	},
	args: {
		html: sample,
		title: 'Counter',
		init: {
			shared: {},
			mine: {},
			me: { id: 'someuserid', name: 'Someone', username: 'someone', avatarUrl: null },
			members: [],
			isHost: true,
			isLeader: true,
			hostOnly: false,
			origin: 'https://example.com',
			strings: {},
		},
		call: async () => undefined,
	},
	parameters: {
		layout: 'centered',
	},
} satisfies StoryObj<typeof MkSpaceTileFrame>;
