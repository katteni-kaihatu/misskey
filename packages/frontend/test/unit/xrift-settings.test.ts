/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, waitFor } from '@testing-library/vue';
import Settings from '@/components/MkXriftSettings.vue';

const { save } = vi.hoisted(() => ({ save: vi.fn() }));
vi.mock('@/os.js', () => ({ apiWithDialog: save }));
vi.mock('@/i18n.js', () => ({ i18n: { ts: { _urlPreviewSetting: { xriftApiKey: 'XRift API key', xriftKeyConfigured: 'Key configured', xriftRemoveKey: 'Remove saved key' }, notSet: 'Not configured' } } }));
vi.mock('@/components/MkInput.vue', () => ({ default: { props: ['modelValue', 'type', 'ariaLabel', 'disabled'], emits: ['update:modelValue'], template: '<input :type="type" :aria-label="ariaLabel" :disabled="disabled" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)"/>' } }));
vi.mock('@/components/MkFolder.vue', () => ({ default: { template: '<section><slot name="label"/><slot/><slot name="footer"/></section>' } }));
vi.mock('@/components/MkFormFooter.vue', () => ({ default: { props: ['form'], template: '<button @click="form.save">Save</button>' } }));
vi.mock('@/components/MkInfo.vue', () => ({ default: { template: '<div><slot/></div>' } }));

beforeEach(() => {
	save.mockReset().mockResolvedValue(undefined);
});
afterEach(cleanup);

async function mountSettings() {
	const view = render(Settings, { props: { configured: true } });
	await waitFor(() => expect(view.getByLabelText('XRift API key')).toBeTruthy());
	return view;
}

test('shows configured state without exposing a saved key', async () => {
	const view = await mountSettings();
	expect(view.getByText('Key configured')).toBeTruthy();
	expect((view.getByLabelText('XRift API key') as HTMLInputElement).value).toBe('');
	expect(view.getByLabelText('XRift API key').getAttribute('type')).toBe('password');
});

test('saves a replacement key and clears the input and dirty state', async () => {
	const view = await mountSettings();
	await fireEvent.update(view.getByLabelText('XRift API key'), '  xrift_sk_new  ');
	await fireEvent.click(view.getByRole('button', { name: 'Save' }));
	await waitFor(() => expect(save).toHaveBeenCalledWith('admin/update-meta', { xriftApiKey: 'xrift_sk_new' }));
	await waitFor(() => expect((view.getByLabelText('XRift API key') as HTMLInputElement).value).toBe(''));
	expect(view.queryByRole('button', { name: 'Save' })).toBeNull();
});

test('deletes a saved key explicitly and updates configured state', async () => {
	const view = await mountSettings();
	await fireEvent.click(view.getByLabelText('Remove saved key'));
	expect((view.getByLabelText('XRift API key') as HTMLInputElement).disabled).toBe(true);
	await fireEvent.click(view.getByRole('button', { name: 'Save' }));
	await waitFor(() => expect(save).toHaveBeenCalledWith('admin/update-meta', { xriftApiKey: null }));
	await waitFor(() => expect(view.getByText('Not configured')).toBeTruthy());
});
