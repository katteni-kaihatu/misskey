/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
/* eslint-disable import/no-default-export */
import type { StoryObj } from '@storybook/vue3';
import MkSpaceTilePreview from './MkSpaceTilePreview.vue';
import sample from '@/spaces/sample-tile.js';

export const Default = {
	render(args) {
		return {
			components: {
				MkSpaceTilePreview,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkSpaceTilePreview v-bind="args"/>',
		};
	},
	args: {
		code: sample,
		twoPeople: true,
	},
	parameters: {
		layout: 'centered',
	},
} satisfies StoryObj<typeof MkSpaceTilePreview>;
