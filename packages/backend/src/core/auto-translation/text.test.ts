/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { describe, expect, test } from 'vitest';
import { detectJapaneseReply, detectTranslationLanguage, normalizeTranslationLanguage, protectTranslationText, selectTranslationLanguage } from './text.js';

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

	test('uses kana and a small reply lexicon without treating all Han text as Japanese', () => {
		for (const text of ['あ', '夜が更ける', '今日は晴れ', '草', '草草', '笑', '乙', '了解']) {
			expect(detectJapaneseReply(text)).toBe('ja');
			expect(selectTranslationLanguage(text, [{ language: 'zh', probability: 0.99 }])).toBe('ja');
		}
		for (const text of ['你好', '中文', '国語', 'Hello', 'This is a ペン', 'こんにちは Привет']) {
			expect(detectJapaneseReply(text)).toBeNull();
		}
	});

	test('accepts model-backed Japanese with product names, keeping foreign sentences and uncertain text separate', () => {
		expect(selectTranslationLanguage('Example Editorを使ったよ', [{ language: 'ja', probability: 0.67 }])).toBe('ja');
		expect(selectTranslationLanguage('試すか PRODUCTNAME 好きなんだよな PRODUCTNAME', [{ language: 'ja', probability: 0.31 }])).toBe('ja');
		expect(selectTranslationLanguage('This is a ペン', [{ language: 'en', probability: 0.98 }])).toBe('en');
		expect(selectTranslationLanguage('今日は雨です I will stay at home', [{ language: 'en', probability: 0.99 }])).toBe('en');
		expect(selectTranslationLanguage('This is a ペン', [{ language: 'ja', probability: 0.31 }])).toBeNull();
		expect(selectTranslationLanguage('API', [{ language: 'id', probability: 0.37 }])).toBeNull();
		expect(selectTranslationLanguage('Example Editorを使ったよ', [{ language: 'ja', probability: 0.20 }])).toBeNull();
		expect(selectTranslationLanguage('bonjour', [{ language: 'fr', probability: 0.90 }])).toBe('fr');
		expect(selectTranslationLanguage('test', [{ language: 'xx', probability: 0.99 }])).toBeNull();
		expect(selectTranslationLanguage('你好', [{ language: 'zh', probability: 0.99 }])).toBeNull();
		expect(selectTranslationLanguage('这是我们的书', [{ language: 'zh', probability: 0.99 }])).toBe('zh-hans');
		expect(selectTranslationLanguage('這是我們的書', [{ language: 'zh', probability: 0.99 }])).toBe('zh-hant');
		expect(selectTranslationLanguage('test', [])).toBeNull();
	});
});
