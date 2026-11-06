/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { randomBytes } from 'node:crypto';
import { francAll } from 'franc';

// Supported by PLaMo Translate; keep scripts distinct when comparing Chinese.
export const translationLanguages = ['ja', 'en', 'zh-hans', 'zh-hant', 'ko', 'fr', 'de', 'es', 'it', 'ar', 'az', 'be', 'bg', 'bn', 'ca', 'ceb', 'et', 'eu', 'fa', 'gu', 'he', 'hi', 'hr', 'hu', 'hy', 'id', 'jv', 'ka', 'kk', 'km', 'lt', 'lv', 'ml', 'mr', 'ms', 'my', 'ne', 'nl', 'pa', 'pl', 'ru', 'si', 'sk', 'sl', 'sr', 'sw', 'ta', 'te', 'th', 'tl', 'ur', 'uz', 'vi'] as const;

const iso3: Record<string, string> = {
	jpn: 'ja', eng: 'en', cmn: 'zh', kor: 'ko', fra: 'fr', deu: 'de', spa: 'es', ita: 'it', arb: 'ar', azj: 'az', bel: 'be', bul: 'bg', ben: 'bn', cat: 'ca', ceb: 'ceb', est: 'et', eus: 'eu', pes: 'fa', guj: 'gu', heb: 'he', hin: 'hi', hrv: 'hr', hun: 'hu', hye: 'hy', ind: 'id', jav: 'jv', kat: 'ka', kaz: 'kk', khm: 'km', lit: 'lt', lav: 'lv', mal: 'ml', mar: 'mr', zlm: 'ms', mya: 'my', npi: 'ne', nld: 'nl', pan: 'pa', pol: 'pl', rus: 'ru', sin: 'si', slk: 'sk', slv: 'sl', srp: 'sr', swh: 'sw', tam: 'ta', tel: 'te', tha: 'th', tgl: 'tl', urd: 'ur', uzn: 'uz', vie: 'vi',
};

export function normalizeTranslationLanguage(value: string): string {
	const code = value.toLowerCase().replaceAll('_', '-');
	if (['zh-cn', 'zh-sg', 'zh-hans'].includes(code)) return 'zh-hans';
	if (['zh-tw', 'zh-hk', 'zh-mo', 'zh-hant'].includes(code)) return 'zh-hant';
	return code.split('-')[0];
}

// Protect non-prose before passing it to the model. One pass avoids matching our own markers.
const protectedPattern = /```[\s\S]*?```|`[^`\n]+`|<\|plamo:[^>]*>|https?:\/\/[^\s<>]+|@[\w.-]+(?:@[\w.-]+)?|:[\w+-]+(?:@[\w.-]+)?:|#[\p{L}\p{N}_]+|\$\[[\w.,=+-]+\s|\*\*|__|~~|<\/?(?:center|small|plain)>|\\.|[\[\]()*<>]/gu;

export function protectTranslationText(text: string) {
	const values: string[] = [];
	const prefix = `MK${randomBytes(8).toString('hex')}X`;
	const protectedText = text.replace(protectedPattern, value => {
		values.push(value);
		return `[[${prefix}${values.length - 1}]]`;
	});
	return {
		text: protectedText,
		prose: text.replace(protectedPattern, ' ').replace(/[^\p{L}\p{M}\s]/gu, ' ').trim(),
		restore(translated: string): string {
			if (translated.includes('<|plamo:')) throw new Error('Translation returned unexpected control text');
			let previousPosition = -1;
			for (const index of values.keys()) {
				const position = translated.indexOf(`[[${prefix}${index}]]`);
				if (position <= previousPosition) throw new Error('Translation reordered protected syntax');
				previousPosition = position;
			}
			for (const [index, value] of values.entries()) {
				const marker = `[[${prefix}${index}]]`;
				if (translated.split(marker).length !== 2) throw new Error('Translation changed a protected marker');
				translated = translated.replace(marker, value);
			}
			if (translated.includes(prefix)) throw new Error('Translation returned unexpected control text');
			return translated;
		},
	};
}

export function detectTranslationLanguage(prose: string): string | null {
	const letters = prose.match(/\p{L}/gu) ?? [];
	if (letters.length === 0) return null;
	const kana = (prose.match(/[\p{Script=Hiragana}\p{Script=Katakana}]/gu) ?? []).length;
	const hangul = (prose.match(/\p{Script=Hangul}/gu) ?? []).length;
	const latin = (prose.match(/\p{Script=Latin}/gu) ?? []).length;
	const han = (prose.match(/\p{Script=Han}/gu) ?? []).length;
	// Mixed scripts are deliberately not considered a confident same-language result.
	if (kana >= 2 && letters.every(letter => /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}ー]/u.test(letter))) return 'ja';
	if (hangul >= 2 && hangul === letters.length) return 'ko';
	if (han > 0 && han === letters.length) {
		const simplified = /[这们说个让还]/u.test(prose);
		const traditional = /[這們說個讓還]/u.test(prose);
		return simplified !== traditional ? (simplified ? 'zh-hans' : 'zh-hant') : null;
	}
	if (letters.length < 30 || kana > 0 || hangul > 0 || han > 0) return null;
	if (latin > 0 && latin !== letters.length) return null;
	const guesses = francAll(prose, { minLength: 30, only: Object.keys(iso3) });
	const [first, second] = guesses;
	if (!first || first[0] === 'und' || (second && first[1] - second[1] < 0.08)) return null;
	return iso3[first[0]] ?? null;
}

// Bump this when detection rules change so old decisions/translations are not reused.
export const languageDetectionRevision = 'mediapipe-1.2.2-v1';

export type LanguagePrediction = { language: string; probability: number };

/** Small Japanese replies are commonly mistaken for Chinese by statistical models. */
export function detectJapaneseReply(prose: string): 'ja' | null {
	const letters = prose.match(/\p{L}/gu) ?? [];
	if (letters.length === 0) return null;
	if (/[\p{Script=Hiragana}\p{Script=Katakana}]/u.test(prose) &&
		letters.every(letter => /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}ー]/u.test(letter))) return 'ja';
	// Explicit conversational replies only: arbitrary Han-only text may be Chinese.
	if (/^(?:草+|笑+|乙|了解)$/u.test(prose.replace(/\s/gu, ''))) return 'ja';
	return null;
}

/** Select only sufficiently confident, supported languages from the server detector. */
export function selectTranslationLanguage(prose: string, predictions: LanguagePrediction[]): string | null {
	const japanese = detectJapaneseReply(prose);
	if (japanese) return japanese;
	const [first] = [...predictions].sort((a, b) => b.probability - a.probability);
	if (!first) return null;
	let language = normalizeTranslationLanguage(first.language);
	let threshold = 0.8;
	// Product names and acronyms can dominate character counts in short Japanese posts.
	// Require Google's top choice to agree, kana, and no foreign-script/English sentence.
	if (language === 'ja' && /[\p{Script=Hiragana}\p{Script=Katakana}]/u.test(prose) &&
		(prose.match(/\p{L}/gu) ?? []).every(letter => /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}\p{Script=Latin}ー]/u.test(letter)) &&
		!/(?:\p{Script=Latin}+\s+){2}\p{Script=Latin}+/u.test(prose)) threshold = 0.25;
	if (first.probability < threshold) return null;
	if (language === 'zh') {
		// An undifferentiated zh result cannot establish equality with either script.
		const simplified = /[这们说个让还]/u.test(prose);
		const traditional = /[這們說個讓還]/u.test(prose);
		if (simplified === traditional) return null;
		language = simplified ? 'zh-hans' : 'zh-hant';
	}
	return (translationLanguages as readonly string[]).includes(language) ? language : null;
}
