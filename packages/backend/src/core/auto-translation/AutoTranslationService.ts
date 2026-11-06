/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { createHash, randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { Inject, Injectable } from '@nestjs/common';
import type { DataSource } from 'typeorm';
import type * as Redis from 'ioredis';
import fetch from 'node-fetch';
import { DI } from '@/di-symbols.js';
import type { NotesRepository } from '@/models/_.js';
import type { MiLocalUser } from '@/models/User.js';
import { MiAutoTranslationConfig } from '@/models/AutoTranslationConfig.js';
import { NoteEntityService } from '@/core/entities/NoteEntityService.js';
import { HttpRequestService } from '@/core/HttpRequestService.js';
import { RoleService } from '@/core/RoleService.js';
import { detectJapaneseReply, detectTranslationLanguage, languageDetectionRevision, normalizeTranslationLanguage, protectTranslationText, selectTranslationLanguage, translationLanguages } from './text.js';
import type { LanguagePrediction } from './text.js';

export class AutoTranslationError extends Error {
	constructor(public readonly reason: 'unavailable' | 'not_found' | 'not_visible' | 'invalid_language' | 'invalid_config' | 'busy' | 'upstream') {
		super(reason);
	}
}

export type AutoTranslationResult = {
	status: 'translated' | 'sameLanguage' | 'skipped';
	sourceLang: string | null;
	targetLang: string;
	text: string | null;
	cw: string | null;
};

type ConfigUpdate = Partial<Pick<MiAutoTranslationConfig, 'enabled' | 'baseUrl' | 'model' | 'apiKey' | 'allowPrivateNetwork' | 'maxConcurrency'>>;
const WAIT_LIMIT_MS = 30_000;
const LEASE_MS = WAIT_LIMIT_MS + 10_000;
const releaseLock = "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end";

@Injectable()
export class AutoTranslationService {
	private readonly languageRequests = new Map<string, Promise<string | null>>();
	private detectorBackoff: { revision: string; until: number } | null = null;

	constructor(
		@Inject(DI.db) private db: DataSource,
		@Inject(DI.redis) private redis: Redis.Redis,
		@Inject(DI.notesRepository) private notes: NotesRepository,
		private noteEntityService: NoteEntityService,
		private roleService: RoleService,
		private httpRequestService: HttpRequestService,
	) {}

	public async getConfig(): Promise<MiAutoTranslationConfig> {
		return await this.db.getRepository(MiAutoTranslationConfig).createQueryBuilder('config')
			.addSelect('config.apiKey').where('config.id = :id', { id: 1 }).getOne() ?? Object.assign(new MiAutoTranslationConfig(), {
			id: 1, enabled: false, baseUrl: '', model: '', apiKey: null, allowPrivateNetwork: false, maxConcurrency: 16, revision: '',
		});
	}

	public async getAdminConfig() {
		const config = await this.getConfig();
		return this.publicConfig(config);
	}

	private publicConfig(config: MiAutoTranslationConfig) {
		return {
			enabled: config.enabled, baseUrl: config.baseUrl, model: config.model,
			apiKeyConfigured: Boolean(config.apiKey), allowPrivateNetwork: config.allowPrivateNetwork,
			maxConcurrency: config.maxConcurrency,
		};
	}

	public async updateConfig(update: ConfigUpdate) {
		const config = await this.getConfig();
		const fields = ['enabled', 'baseUrl', 'model', 'apiKey', 'allowPrivateNetwork', 'maxConcurrency'] as const;
		for (const field of fields) {
			if (Object.hasOwn(update, field)) Object.assign(config, { [field]: update[field] });
		}
		config.baseUrl = config.baseUrl.trim().replace(/\/+$/, '');
		config.model = config.model.trim();
		if (!Number.isInteger(config.maxConcurrency) || config.maxConcurrency < 1 || config.maxConcurrency > 16) throw new AutoTranslationError('invalid_config');
		if (config.apiKey != null) config.apiKey = config.apiKey.trim() || null;
		if (config.baseUrl) this.validateUrl(config);
		if (config.enabled && (!config.baseUrl || !config.model || !config.apiKey)) throw new AutoTranslationError('invalid_config');
		config.revision = randomUUID();
		await this.db.getRepository(MiAutoTranslationConfig).save(config);
		return this.publicConfig(config);
	}

	private validateUrl(config: MiAutoTranslationConfig): URL {
		try {
			const url = new URL(config.baseUrl);
			if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('Invalid URL');
			if (url.protocol !== 'https:' && !config.allowPrivateNetwork) throw new Error('HTTP requires explicit private network access');
			return url;
		} catch {
			throw new AutoTranslationError('invalid_config');
		}
	}

	public async capabilities(me: MiLocalUser) {
		const config = await this.getConfig();
		const policies = await this.roleService.getUserPolicies(me.id);
		return { available: config.enabled && Boolean(config.baseUrl && config.model && config.apiKey) && policies.canUseTranslator,
			languages: [...translationLanguages] };
	}

	private async request(config: MiAutoTranslationConfig, path: string, body?: unknown, timeout = WAIT_LIMIT_MS): Promise<unknown> {
		this.validateUrl(config);
		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), timeout);
		try {
			const response = await fetch(`${config.baseUrl}/${path}`, {
				method: body === undefined ? 'GET' : 'POST',
				headers: { Authorization: `Bearer ${config.apiKey ?? ''}`, 'Content-Type': 'application/json' },
				body: body === undefined ? undefined : JSON.stringify(body),
				redirect: 'error', size: 1024 * 1024, signal: controller.signal,
				agent: url => this.httpRequestService.getAgentByUrl(url, true, config.allowPrivateNetwork),
			});
			if (!response.ok) throw new AutoTranslationError('upstream');
			return await response.json();
		} catch {
			// Do not return URLs, authorization headers, or upstream bodies to clients/logs.
			throw new AutoTranslationError('upstream');
		} finally {
			clearTimeout(timer);
		}
	}

	public async testConnection(): Promise<void> {
		const config = await this.getConfig();
		if (!config.baseUrl || !config.model || !config.apiKey) throw new AutoTranslationError('invalid_config');
		const result = await this.request(config, 'models') as { data?: { id?: string }[] };
		if (!Array.isArray(result.data) || !result.data.some(item => item.id === config.model)) throw new AutoTranslationError('upstream');
	}

	private async detectLanguage(config: MiAutoTranslationConfig, prose: string): Promise<string | null> {
		if (!prose) return null;
		const digest = createHash('sha256').update(JSON.stringify([languageDetectionRevision, config.revision, prose])).digest('hex');
		const key = `auto-translation:language:${digest}`;
		const cached = await this.redis.get(key);
		if (cached !== null) return JSON.parse(cached) as string | null;
		const pending = this.languageRequests.get(key);
		if (pending) return pending;
		const request = (async () => {
			const fallback = () => detectJapaneseReply(prose) ?? detectTranslationLanguage(prose);
			if (this.detectorBackoff?.revision === config.revision && this.detectorBackoff.until > Date.now()) return fallback();
			try {
				const result = await this.request(config, 'language-detection', { text: prose }, 1500) as { predictions?: LanguagePrediction[] } | null;
				if (!result || !Array.isArray(result.predictions) || result.predictions.length > 10 ||
					!result.predictions.every(item => item && typeof item.language === 'string' &&
						typeof item.probability === 'number' && Number.isFinite(item.probability) && item.probability >= 0 && item.probability <= 1)) throw new AutoTranslationError('upstream');
				const language = selectTranslationLanguage(prose, result.predictions);
				// Cache unknown as well; transport failures must be retried after backoff.
				await this.redis.set(key, JSON.stringify(language), 'EX', 86400);
				return language;
			} catch {
				this.detectorBackoff = { revision: config.revision, until: Date.now() + 30_000 };
				return fallback();
			}
		})();
		this.languageRequests.set(key, request);
		try {
			return await request;
		} finally {
			this.languageRequests.delete(key);
		}
	}

	private async withCapacity<T>(limit: number, deadline: number, run: () => Promise<T>): Promise<T> {
		const token = randomUUID();
		const waiting = 'auto-translation:waiting';
		const running = 'auto-translation:running';
		const registered = await this.redis.eval("redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1]); if redis.call('ZCARD', KEYS[1]) >= 64 then return 0 end; redis.call('ZADD', KEYS[1], ARGV[2], ARGV[3]); return 1", 1, waiting, Date.now(), Date.now() + LEASE_MS, token);
		if (Number(registered) !== 1) throw new AutoTranslationError('busy');
		try {
			while (Date.now() < deadline) {
				const acquired = await this.redis.eval("redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1]); if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[2]) then return 0 end; redis.call('ZADD', KEYS[1], ARGV[3], ARGV[4]); return 1", 1, running, Date.now(), limit, Date.now() + LEASE_MS, token);
				if (Number(acquired) === 1) {
					await this.redis.zrem(waiting, token);
					return await run();
				}
				await delay(50);
			}
			throw new AutoTranslationError('busy');
		} finally {
			await Promise.all([this.redis.zrem(waiting, token), this.redis.zrem(running, token)]);
		}
	}

	private async translateText(config: MiAutoTranslationConfig, text: string | null, targetLang: string, sourceLang: string | null, deadline: number): Promise<string | null> {
		if (!text?.trim()) return text;
		const protectedText = protectTranslationText(text);
		if (!protectedText.prose) return text;
		if (Date.now() >= deadline) throw new AutoTranslationError('busy');
		const result = await this.request(config, 'chat/completions', {
			model: config.model, messages: [{ role: 'user', content: protectedText.text }],
			chat_template_kwargs: { target_lang: targetLang, ...(sourceLang ? { source_lang: sourceLang } : {}),
				context: 'Preserve every marker beginning with [[MK exactly, including brackets, letters, and numbers.' },
			temperature: 0, max_tokens: 2048, stream: false, stop: ['<|plamo:tag|>', '<|plamo:bos|>'],
		}, Math.max(1, deadline - Date.now())) as { choices?: { message?: { content?: unknown }; finish_reason?: string }[] };
		const choice = result.choices?.[0];
		if (typeof choice?.message?.content !== 'string' || !choice.message.content.trim() || choice.finish_reason !== 'stop') throw new AutoTranslationError('upstream');
		try {
			return protectedText.restore(choice.message.content);
		} catch {
			throw new AutoTranslationError('upstream');
		}
	}

	public async translateNote(noteId: string, language: string, me: MiLocalUser): Promise<AutoTranslationResult> {
		const targetLang = normalizeTranslationLanguage(language);
		if (!(translationLanguages as readonly string[]).includes(targetLang)) throw new AutoTranslationError('invalid_language');
		const policies = await this.roleService.getUserPolicies(me.id);
		if (!policies.canUseTranslator) throw new AutoTranslationError('unavailable');
		const note = await this.notes.findOneBy({ id: noteId });
		if (!note) throw new AutoTranslationError('not_found');
		if (!await this.noteEntityService.isVisibleForMe(note, me.id) || (await this.noteEntityService.pack(note, me)).isHidden) throw new AutoTranslationError('not_visible');
		const config = await this.getConfig();
		if (!config.enabled || !config.baseUrl || !config.apiKey || !config.model) throw new AutoTranslationError('unavailable');
		const prose = protectTranslationText([note.cw, note.text].filter(Boolean).join('\n')).prose;
		const sourceLang = await this.detectLanguage(config, prose);
		const base = { sourceLang, targetLang, text: null, cw: null };
		if (!prose) return { ...base, status: 'skipped' };
		if (sourceLang === targetLang) return { ...base, status: 'sameLanguage' };
		const digest = createHash('sha256').update(JSON.stringify([note.id, note.text, note.cw, targetLang, config.revision, languageDetectionRevision])).digest('hex');
		const cacheKey = `auto-translation:result:${digest}`;
		const lockKey = `auto-translation:lock:${digest}`;
		const token = randomUUID();
		const deadline = Date.now() + WAIT_LIMIT_MS;
		while (Date.now() < deadline) {
			const cached = await this.redis.get(cacheKey);
			if (cached) return JSON.parse(cached) as AutoTranslationResult;
			const acquired = await this.redis.set(lockKey, token, 'PX', LEASE_MS, 'NX');
			if (acquired) {
				try {
					// The previous owner may have filled the cache between GET and SET NX.
					const completed = await this.redis.get(cacheKey);
					if (completed) return JSON.parse(completed) as AutoTranslationResult;
					return await this.withCapacity(config.maxConcurrency, deadline, async () => {
						const result: AutoTranslationResult = { status: 'translated', sourceLang, targetLang,
							text: await this.translateText(config, note.text, targetLang, sourceLang, deadline),
							cw: await this.translateText(config, note.cw, targetLang, sourceLang, deadline) };
						await this.redis.set(cacheKey, JSON.stringify(result), 'EX', 3600);
						return result;
					});
				} finally {
					await this.redis.eval(releaseLock, 1, lockKey, token);
				}
			}
			await delay(50);
		}
		throw new AutoTranslationError('busy');
	}
}
