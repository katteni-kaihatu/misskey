/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
/* eslint-disable @typescript-eslint/explicit-function-return-type */
import type { StoryObj } from '@storybook/vue3';
import MkPanorama from './MkPanorama.vue';

const sample = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="512" viewBox="0 0 1024 512"><rect width="1024" height="512" fill="#8dc6dd"/><path d="M0 270L100 180L240 265L410 150L580 265L770 160L910 260L1024 190V512H0Z" fill="#537d70"/><path d="M0 330Q260 270 512 350T1024 320V512H0Z" fill="#c3b38a"/></svg>`;
export const Default = {
	render(args) { return { components: { MkPanorama }, setup: () => ({ args }), template: '<div style="width:320px;height:240px"><MkPanorama v-bind="args"/></div>' }; },
	args: { src: `data:image/svg+xml,${encodeURIComponent(sample)}`, alt: 'Panorama sample' },
} satisfies StoryObj<typeof MkPanorama>;
