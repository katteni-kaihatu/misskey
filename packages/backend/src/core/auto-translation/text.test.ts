/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test } from 'vitest';
import { detectTranslationLanguage, normalizeTranslationLanguage, protectTranslationText } from './text.js';

describe('automatic translation text handling', () => {
	test('normalizes region and Chinese script variants', () => {
		expect(normalizeTranslationLanguage('EN_us')).toBe('en');
		expect(normalizeTranslationLanguage('zh-TW')).toBe('zh-hant');
		expect(normalizeTranslationLanguage('zh-CN')).toBe('zh-hans');
	});
	test('skips confident same-language text without guessing ambiguous short text', () => {
		expect(detectTranslationLanguage('今日はとてもいい天気ですね')).toBe('ja');
		expect(detectTranslationLanguage('This is a normal English sentence that should not need translation into the same language.')).toBe('en');
		expect(detectTranslationLanguage('Bonjour, je voudrais traduire cette phrase en japonais pour mes amis.')).toBe('fr');
		expect(detectTranslationLanguage('Hello')).toBeNull();
		expect(detectTranslationLanguage('今日は Hello world')).toBeNull();
		expect(detectTranslationLanguage('こんにちは Привет')).toBeNull();
		expect(detectTranslationLanguage('国語')).toBeNull();
		expect(detectTranslationLanguage('这 Привет')).toBeNull();
		expect(detectTranslationLanguage('中文')).toBeNull();
		expect(detectTranslationLanguage('这是我们的书')).toBe('zh-hans');
		expect(detectTranslationLanguage('這是我們的書')).toBe('zh-hant');
	});
	test('preserves URLs, mentions, emoji, code, tags, and model control strings exactly', () => {
		const source = 'こんにちは @alice@example.com :blobcat: #Misskey https://example.com/a `x = 1`\n```js\n42\n``` <|plamo:bos|>';
		const protectedText = protectTranslationText(source);
		expect(protectedText.prose).toBe('こんにちは');
		expect(protectedText.restore(protectedText.text.replace('こんにちは', 'Hello'))).toBe(source.replace('こんにちは', 'Hello'));
		expect(() => protectedText.restore('Hello')).toThrow();
		expect(() => protectedText.restore(protectedText.text + protectedText.text)).toThrow();
		expect(() => protectedText.restore(protectedText.text + '<|plamo:tag|>')).toThrow();
		const mfm = protectTranslationText('Hello $[spin world]');
		expect(() => mfm.restore(mfm.text.replace(/\[\[MK[^\]]+1\]\]/, ''))).toThrow();
	});
});
