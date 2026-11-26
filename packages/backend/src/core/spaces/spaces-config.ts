/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/** 設定ファイルの `spaces` の節。 */
export type SpacesConfigSource = {
	enabled?: boolean;
	livekit?: {
		/** ブラウザがつなぐ先。`ws://` か `wss://` で始まる。 */
		url?: string;
		apiKey?: string;
		/** API の秘密を入れた環境変数の名前。秘密そのものは設定ファイルに書かない。 */
		apiSecretEnv?: string;
	};
};

export type SpacesConfig = {
	livekit: {
		/** ブラウザに渡す接続先 (`ws://` / `wss://`)。 */
		url: string;
		/** Misskey から LiveKit を操作するときの接続先 (`http://` / `https://`)。 */
		httpUrl: string;
		apiKey: string;
		apiSecret: string;
	};
};

function livekitOrigins(value: unknown): { url: string; httpUrl: string } {
	if (typeof value !== 'string') throw new Error('Spaces livekit.url must be a string.');
	let url: URL;
	try {
		url = new URL(value);
	} catch {
		throw new Error('Spaces livekit.url must be a valid URL.');
	}
	if (url.protocol !== 'ws:' && url.protocol !== 'wss:') throw new Error('Spaces livekit.url must start with ws:// or wss://.');
	if (url.username !== '' || url.password !== '' || url.pathname !== '/' || url.search !== '' || url.hash !== '') {
		throw new Error('Spaces livekit.url must not contain credentials, a path, a query or a fragment.');
	}
	const httpProtocol = url.protocol === 'wss:' ? 'https:' : 'http:';
	return { url: `${url.protocol}//${url.host}`, httpUrl: `${httpProtocol}//${url.host}` };
}

/**
 * `spaces` の節を検査して、使える形にする。
 * 節が無い、または無効なら null を返す。有効なのに中身が足りないときは例外を投げる。
 * 例外の文言に秘密の値は入れない。
 */
export function resolveSpacesConfig(source: SpacesConfigSource | undefined, env: NodeJS.ProcessEnv): SpacesConfig | null {
	if (source?.enabled == null || source.enabled === false) return null;
	if (source.enabled !== true) throw new Error('Spaces enabled must be a boolean.');
	const livekit = source.livekit;
	if (livekit == null || typeof livekit !== 'object') throw new Error('Spaces requires a livekit section.');
	const origins = livekitOrigins(livekit.url);
	if (typeof livekit.apiKey !== 'string' || livekit.apiKey.length === 0) throw new Error('Spaces livekit.apiKey must be a non-empty string.');
	if (typeof livekit.apiSecretEnv !== 'string' || !/^[A-Z][A-Z0-9_]*$/.test(livekit.apiSecretEnv)) {
		throw new Error('Spaces livekit.apiSecretEnv must name an environment variable.');
	}
	const apiSecret = env[livekit.apiSecretEnv];
	if (!apiSecret) throw new Error('Spaces requires the LiveKit API secret in the environment variable named by livekit.apiSecretEnv.');
	return { livekit: { ...origins, apiKey: livekit.apiKey, apiSecret } };
}
