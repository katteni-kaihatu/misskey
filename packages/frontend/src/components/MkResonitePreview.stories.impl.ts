/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
/* eslint-disable @typescript-eslint/explicit-function-return-type */
import type { StoryObj } from '@storybook/vue3';
import type { SummalyResult } from '@misskey-dev/summaly';
import type { ResonitePreview } from 'misskey-js';
import MkResonitePreview from './MkResonitePreview.vue';

const url = 'https://go.resonite.com/world/U-Example/R-12345678-1234-1234-1234-123456789abc';
const summary: SummalyResult & { resonite: ResonitePreview } = {
	url, title: 'Cozy Cave', description: 'A pile of blankets by a fire', thumbnail: null, icon: null, sitename: 'Resonite', thumbnailStyle: 'summary_large_image',
	player: { url: null, width: null, height: null, allow: [] }, activityPub: null, fediverseCreator: null,
	resonite: { type: 'world', state: 'available', creator: 'Example creator', visits: 24, updatedAt: '2026-11-19T00:00:00Z', titleParts: [{ text: 'Cozy ', color: '#61d1fa' }, { text: 'Cave', color: '#ba64f2' }] },
};
export const World = {
	render(args) { return { components: { MkResonitePreview }, setup: () => ({ args }), template: '<div style="width:640px;max-width:100%"><MkResonitePreview v-bind="args"/></div>' }; },
	args: { url, type: 'world', summary, loading: false, failed: false },
	parameters: { layout: 'padded' },
} satisfies StoryObj<typeof MkResonitePreview>;
export const Session = { ...World, args: { ...World.args, type: 'session', url: 'https://go.resonite.com/session/S-Example', summary: { ...summary, title: 'Islands of Resonite: Convention', resonite: { type: 'session', state: 'available', creator: 'Example host', currentUsers: 5, maxUsers: 32, worldUrl: url, createdAt: new Date(Date.now() - 84 * 60_000).toISOString() } } } } satisfies StoryObj<typeof MkResonitePreview>;
export const Mobile = { ...Session, render(args) { return { components: { MkResonitePreview }, setup: () => ({ args }), template: '<div style="width:340px;max-width:100%"><MkResonitePreview v-bind="args"/></div>' }; } } satisfies StoryObj<typeof MkResonitePreview>;
export const Full = { ...Session, args: { ...Session.args, summary: { ...Session.args.summary, resonite: { ...Session.args.summary.resonite, currentUsers: 32 } } } } satisfies StoryObj<typeof MkResonitePreview>;
export const Featured = { ...World, args: { ...World.args, summary: { ...summary, resonite: { ...summary.resonite, featured: true } } } } satisfies StoryObj<typeof MkResonitePreview>;
export const Ended = { ...Session, args: { ...Session.args, summary: { ...Session.args.summary, resonite: { ...Session.args.summary.resonite, state: 'ended' } } } } satisfies StoryObj<typeof MkResonitePreview>;
export const Unavailable = { ...World, args: { ...World.args, summary: { ...summary, resonite: { type: 'world', state: 'unavailable' } } } } satisfies StoryObj<typeof MkResonitePreview>;
export const Loading = { ...World, args: { ...World.args, summary: null, loading: true } } satisfies StoryObj<typeof MkResonitePreview>;
export const Error = { ...World, args: { ...World.args, summary: null, failed: true } } satisfies StoryObj<typeof MkResonitePreview>;
