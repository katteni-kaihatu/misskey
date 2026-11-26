/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render } from '@testing-library/vue';
import WebClientIconPicker from '@/pages/settings/web-client-icon-picker.vue';

vi.mock('@/i18n.js', () => ({ i18n: {
	ts: { random: 'Random', _webClientIcon: { title: 'Web icon', description: 'Random changes every five minutes.' } },
	tsx: { _webClientIcon: { artworkBy: ({ name }: { name: string }) => `${name} artwork` } },
} }));

afterEach(cleanup);

test('shows six labeled radio choices with artwork previews and emits fixed/random selections', async () => {
	const view = render(WebClientIconPicker, {
		props: { modelValue: 'random' },
		global: { stubs: { SearchLabel: { template: '<span><slot/></span>' }, SearchText: { template: '<span><slot/></span>' } } },
	});
	expect(view.getAllByRole('radio')).toHaveLength(6);
	expect(view.getByRole('radio', { name: 'Random' })).toHaveProperty('checked', true);
	expect(view.container.querySelectorAll('img')).toHaveLength(5);
	await fireEvent.click(view.getByRole('radio', { name: '@tekerets artwork' }));
	expect(view.emitted()['update:modelValue']).toEqual([['tekerets']]);
	await view.rerender({ modelValue: 'tekerets' });
	expect(view.getByRole('radio', { name: '@tekerets artwork' })).toHaveProperty('checked', true);
	await fireEvent.click(view.getByRole('radio', { name: 'Random' }));
	expect(view.emitted()['update:modelValue']).toEqual([['tekerets'], ['random']]);
});
