/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
/* eslint-disable import/no-default-export */
import type { StoryObj } from '@storybook/vue3';
import MkSpaceTile from './MkSpaceTile.vue';

export const Default = {
	render(args) {
		return {
			components: {
				MkSpaceTile,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkSpaceTile v-bind="args"/>',
		};
	},
	args: {
		tile: {
			id: 'sometileid',
			spaceId: 'somespaceid',
			kind: 'memo',
			creatorId: 'someuserid',
			position: 0,
			def: null,
			allowedHosts: [],
			hostOnly: false,
		},
		removable: true,
	},
	parameters: {
		layout: 'centered',
	},
} satisfies StoryObj<typeof MkSpaceTile>;
