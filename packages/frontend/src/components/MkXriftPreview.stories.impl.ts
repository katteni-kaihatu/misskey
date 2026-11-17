/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
/* eslint-disable @typescript-eslint/explicit-function-return-type */
import type { StoryObj } from '@storybook/vue3';
import type { SummalyResult } from '@misskey-dev/summaly';
import type { XriftPreview } from 'misskey-js';
import MkXriftPreview from './MkXriftPreview.vue';

const url = 'https://app.xrift.net/world/4b84ca2a-06cc-4351-a2df-adc904eec8e4';
const summary: SummalyResult & { xrift: XriftPreview } = {
	url, title: 'Cozy Workspace Cafe', description: '雨の街並みを眺める、中庭のある作業カフェ。静かなBGMで、自分のペースで過ごせます。', thumbnail: null, thumbnailStyle: 'summary_large_image', icon: null, sitename: 'XRift',
	player: { url: null, width: null, height: null, allow: [] }, activityPub: null, fediverseCreator: null,
	xrift: { type: 'world', state: 'available', creator: 'ワールド作者', totalVisits: 12345, visitsLast7Days: 234, publicInstances: 2 },
};
export const World = {
	render(args) {
		return { components: { MkXriftPreview }, setup: () => ({ args }), template: '<div style="width:640px;max-width:100%"><MkXriftPreview v-bind="args"/></div>' };
	},
	args: { url, type: 'world', summary, loading: false, failed: false },
	parameters: { layout: 'padded' },
} satisfies StoryObj<typeof MkXriftPreview>;
export const Mobile = { ...World, render(args) { return { components: { MkXriftPreview }, setup: () => ({ args }), template: '<div style="width:340px;max-width:100%"><MkXriftPreview v-bind="args"/></div>' }; } } satisfies StoryObj<typeof MkXriftPreview>;
export const Empty = { ...World, args: { ...World.args, summary: { ...summary, xrift: { ...summary.xrift, publicInstances: 0 } } } } satisfies StoryObj<typeof MkXriftPreview>;
export const Room = { ...World, args: { ...World.args, type: 'instance', url: url.replace('/world/', '/instance/'), summary: { ...summary, xrift: { ...summary.xrift, type: 'instance', worldUrl: url, createdAt: new Date(Date.now() - 84 * 60_000).toISOString() } } } } satisfies StoryObj<typeof MkXriftPreview>;
export const Profile = { ...World, args: { ...World.args, type: 'user', summary: { ...summary, title: 'ワールド作者', xrift: { type: 'user', state: 'available', creator: null, totalWorlds: 12, createdAt: '2026-01-01T00:00:00Z', worlds: [{ url, title: summary.title!, thumbnail: null }] } } } } satisfies StoryObj<typeof MkXriftPreview>;
export const Unavailable = { ...World, args: { ...World.args, summary: { ...summary, xrift: { type: 'world', state: 'unavailable', creator: null } } } } satisfies StoryObj<typeof MkXriftPreview>;
export const Loading = { ...World, args: { ...World.args, summary: null, loading: true } } satisfies StoryObj<typeof MkXriftPreview>;
export const Error = { ...World, args: { ...World.args, summary: null, failed: true } } satisfies StoryObj<typeof MkXriftPreview>;
