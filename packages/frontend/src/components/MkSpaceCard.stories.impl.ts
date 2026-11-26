/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/* eslint-disable @typescript-eslint/explicit-function-return-type */
/* eslint-disable import/no-default-export */
import type { StoryObj } from '@storybook/vue3';
import { userLite } from '../../.storybook/fakes.js';
import MkSpaceCard from './MkSpaceCard.vue';

export const Default = {
	render(args) {
		return {
			components: {
				MkSpaceCard,
			},
			setup() {
				return {
					args,
				};
			},
			template: '<MkSpaceCard v-bind="args"/>',
		};
	},
	args: {
		spaceId: 'somespaceid',
		initialSpace: {
			id: 'somespaceid',
			createdAt: '2026-11-26T12:00:00.000Z',
			endedAt: null,
			hostId: 'someuserid',
			host: userLite(),
			name: 'ざつだんスペース',
			access: 'local',
			noteScope: 'local',
			announceNoteId: null,
			memberCount: 4,
			participantCount: 6,
			peakCount: 5,
			canJoin: true,
		},
	},
	parameters: {
		layout: 'centered',
	},
} satisfies StoryObj<typeof MkSpaceCard>;

export const Ended = {
	...Default,
	args: {
		...Default.args,
		initialSpace: {
			...Default.args.initialSpace,
			endedAt: '2026-11-26T13:00:00.000Z',
			memberCount: 0,
			canJoin: false,
		},
	},
} satisfies StoryObj<typeof MkSpaceCard>;
