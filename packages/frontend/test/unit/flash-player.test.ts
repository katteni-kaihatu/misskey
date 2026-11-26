/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render } from '@testing-library/vue';
import { values } from '@syuilo/aiscript';
import Player from '@/components/MkFlashPlayer.vue';

const mocks = vi.hoisted(() => ({ api: vi.fn(), alert: vi.fn(), environment: vi.fn(), instances: [] as { abort: () => void }[] }));
vi.mock('@syuilo/aiscript', async importOriginal => {
	const actual = await importOriginal<typeof import('@syuilo/aiscript')>();
	return { ...actual, Interpreter: class extends actual.Interpreter {
		constructor(...args: ConstructorParameters<typeof actual.Interpreter>) {
			super(...args);
			this.abort = vi.fn(this.abort);
			mocks.instances.push(this);
		}
	} };
});
vi.mock('@syuilo/aiscript-0-19-0', async importOriginal => {
	const actual = await importOriginal<typeof import('@syuilo/aiscript-0-19-0')>();
	return { ...actual, Interpreter: class extends actual.Interpreter {
		constructor(...args: ConstructorParameters<typeof actual.Interpreter>) {
			super(...args);
			this.abort = vi.fn(this.abort);
			mocks.instances.push(this);
		}
	} };
});
vi.mock('@/utility/misskey-api.js', () => ({ misskeyApi: mocks.api }));
vi.mock('@/os.js', () => ({ alert: mocks.alert }));
vi.mock('@/aiscript/api.js', () => ({ createAiScriptEnv: mocks.environment, aiScriptReadline: vi.fn() }));
vi.mock('@/i18n.js', () => ({ i18n: { ts: { reload: 'Reload', _spaces: { _tiles: { _play: { start: 'Start', notFound: 'Not found' } } } } } }));
vi.mock('@/components/MkButton.vue', () => ({ default: { template: '<button @click="$emit(\'click\')"><slot/></button>' } }));
vi.mock('@/components/MkPostForm.vue', () => ({ default: { template: '<div/>' } }));

beforeEach(() => {
	vi.clearAllMocks();
	mocks.instances.length = 0;
	let run = 0;
	mocks.environment.mockImplementation(() => ({ 'Test:next': values.FN_NATIVE(() => values.STR(`Run ${++run}`)) }));
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

test.each(['1.0.0', '0.19.0'])('renders real AiScript UI and replaces its root on restart (%s)', async version => {
	mocks.api.mockResolvedValue({
		id: 'play', title: 'Test play', summary: 'Summary',
		script: `/// @ ${version}\nUi:render([Ui:C:text({ text: Test:next() })])`,
	});
	const view = render(Player, { props: { flashId: 'play' }, global: { stubs: { MkLoading: true, Mfm: true } } });
	await vi.waitFor(() => expect(view.getByRole('button', { name: 'Start' })).toBeTruthy());
	expect(view.queryByText('Run 1')).toBeNull();
	await fireEvent.click(view.getByRole('button', { name: 'Start' }));
	await vi.waitFor(() => expect(view.getByText('Run 1')).toBeTruthy());
	const first = mocks.instances[0];
	expect(mocks.alert).not.toHaveBeenCalled();

	await fireEvent.click(view.getByRole('button', { name: 'Reload' }));
	await vi.waitFor(() => expect(view.getByText('Run 2')).toBeTruthy());
	expect(view.queryByText('Run 1')).toBeNull();
	expect(first.abort).toHaveBeenCalledOnce();
	expect(mocks.alert).not.toHaveBeenCalled();

	view.unmount();
	expect(mocks.instances[1].abort).toHaveBeenCalledOnce();
});
