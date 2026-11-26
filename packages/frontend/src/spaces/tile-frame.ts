/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import type * as Misskey from 'misskey-js';

/**
 * タイルを動かす枠 (sandbox 付きの iframe) の中身を組み立てる。
 *
 * 枠は Misskey のページとは別の出どころとして扱われ、アクセストークンにも保存データにも触れない。
 * 外とのやり取りは、ここで用意する `space` という窓口だけを通る。窓口の先は本体 (MkSpaceTile) が受ける。
 */

/** 枠に最初に渡すもの */
export type TileInit = {
	/** 共有する値。キー → 値 */
	shared: Record<string, unknown>;
	/** 自分だけの値。キー → 値 */
	mine: Record<string, unknown>;
	me: TileUser;
	members: TileUser[];
	isHost: boolean;
	/** 自分が担当か */
	isLeader: boolean;
	/** ホストだけが操作できるタイルか */
	hostOnly: boolean;
	/** このサーバーの URL。ノートのページなどを開くのに使う */
	origin: string;
	/** タイルが出す文言。キー → 文言 */
	strings: Record<string, string>;
};

export type TileUser = {
	id: string;
	name: string;
	username: string;
	avatarUrl: string | null;
};

/** 枠から本体へ */
export type TileToHostMessage =
	| { t: 'setShared'; key: string; value: unknown }
	| { t: 'setMine'; key: string; value: unknown }
	| { t: 'signal'; type: string; body: unknown }
	| { t: 'open'; url: string }
	| { t: 'post'; text: string }
	| { t: 'call'; id: number; method: string; args: unknown }
	| { t: 'resize'; height: number };

/** 本体から枠へ */
export type HostToTileMessage =
	| { t: 'shared'; key: string; value: unknown; userId: string }
	| { t: 'signal'; type: string; body: unknown; userId: string }
	| { t: 'members'; members: TileUser[] }
	| { t: 'leader'; isLeader: boolean }
	| { t: 'hostOnly'; hostOnly: boolean }
	| { t: 'reply'; id: number; ok: boolean; value: unknown };

/** 枠に窓口の通信路を渡すときの合図 */
export const TILE_PORT_MESSAGE = 'space:port';

export function toTileUser(user: Misskey.entities.UserLite): TileUser {
	return { id: user.id, name: user.name ?? user.username, username: user.username, avatarUrl: user.avatarUrl ?? null };
}

/**
 * 枠の中で `space` を用意するスクリプト。タイルのコードより先に動く。
 * 枠の中は別の世界なので、ここは文字列として渡す。本体のコードは使えない。
 */
const BOOTSTRAP = String.raw`
(function () {
	// WebRTC は通信の制限の外にあり、外へデータを送る道になる。タイルのコードが動く前に、入口を消しておく
	['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCIceTransport', 'RTCSessionDescription', 'RTCIceCandidate'].forEach(function (name) {
		try { Object.defineProperty(window, name, { value: undefined, writable: false, configurable: false }); } catch (err) { /* 無いブラウザ */ }
	});

	var init = JSON.parse(document.getElementById('space-init').textContent);
	var port = null;
	var queue = [];
	function post(message) {
		if (port) port.postMessage(message); else queue.push(message);
	}

	var sharedListeners = {};
	var mineListeners = {};
	var signalListeners = {};
	var memberListeners = [];
	var leaderListeners = [];
	var anyListeners = [];
	var calls = {};
	var nextCall = 1;

	function fire(listeners, key, value, info) {
		(listeners[key] || []).slice().forEach(function (fn) {
			try { fn(value, info); } catch (err) { console.error(err); }
		});
	}

	function store(values, listeners, kind) {
		return function (key, initial) {
			return {
				get: function () { return Object.prototype.hasOwnProperty.call(values, key) ? values[key] : initial; },
				set: function (value) {
					if (value === undefined) value = null;
					if (value === null) delete values[key]; else values[key] = value;
					post({ t: kind, key: key, value: value });
					var info = { userId: init.me.id, self: true };
					fire(listeners, key, value, info);
					if (kind === 'setShared') fireAny(key, value, info);
				},
				on: function (fn) {
					(listeners[key] = listeners[key] || []).push(function (value, info) { fn(value === null ? initial : value, info); });
				},
			};
		};
	}

	function fireAny(key, value, info) {
		anyListeners.slice().forEach(function (fn) {
			try { fn(key, value, info); } catch (err) { console.error(err); }
		});
	}

	// 本体に頼んで、返事を待つ
	function call(method, args) {
		return new Promise(function (resolve, reject) {
			var id = nextCall++;
			calls[id] = { resolve: resolve, reject: reject };
			post({ t: 'call', id: id, method: method, args: args });
		});
	}

	window.space = {
		shared: store(init.shared, sharedListeners, 'setShared'),
		mine: store(init.mine, mineListeners, 'setMine'),
		send: function (type, body) { post({ t: 'signal', type: String(type), body: body === undefined ? null : body }); },
		on: function (type, fn) { (signalListeners[type] = signalListeners[type] || []).push(fn); },
		me: init.me,
		members: init.members,
		onMembers: function (fn) { memberListeners.push(fn); },
		isHost: init.isHost,
		isLeader: init.isLeader,
		onLeader: function (fn) { leaderListeners.push(fn); },
		hostOnly: !!init.hostOnly,
		origin: init.origin,
		keys: function (prefix) {
			return Object.keys(init.shared).filter(function (key) { return !prefix || key.indexOf(prefix) === 0; });
		},
		onShared: function (fn) { anyListeners.push(fn); },
		misskey: function (endpoint, params) { return call('misskey', { endpoint: String(endpoint), params: params || {} }); },
		pickFile: function () { return call('pickFile', null); },
		preview: function (url) { return call('preview', { url: String(url) }); },
		open: function (url) { post({ t: 'open', url: String(url) }); },
		// 外部の URL を読む。読みに行くのは本体のサーバーで、置いた人が許した先だけが読める
		fetch: function (url, options) {
			return call('fetch', { url: String(url) }).then(function (res) {
				if (options && options.json) {
					try { res.json = JSON.parse(res.text); } catch (err) { res.json = null; }
				}
				return res;
			});
		},
		// 投稿フォームを、本文を入れた状態で開く。投稿するかどうかは本人が決める
		post: function (text) { post({ t: 'post', text: String(text) }); },
		t: function (key) { return Object.prototype.hasOwnProperty.call(init.strings, key) ? init.strings[key] : key; },
	};

	function onMessage(ev) {
		var message = ev.data;
		if (!message) return;
		if (message.t === 'shared') {
			if (message.value === null) delete init.shared[message.key]; else init.shared[message.key] = message.value;
			var info = { userId: message.userId, self: false };
			fire(sharedListeners, message.key, message.value, info);
			fireAny(message.key, message.value, info);
		} else if (message.t === 'signal') {
			fire(signalListeners, message.type, message.body, { userId: message.userId });
		} else if (message.t === 'leader') {
			window.space.isLeader = !!message.isLeader;
			leaderListeners.slice().forEach(function (fn) {
				try { fn(window.space.isLeader); } catch (err) { console.error(err); }
			});
		} else if (message.t === 'hostOnly') {
			window.space.hostOnly = !!message.hostOnly;
		} else if (message.t === 'reply') {
			var pending = calls[message.id];
			if (!pending) return;
			delete calls[message.id];
			if (message.ok) pending.resolve(message.value); else pending.reject(new Error(String(message.value)));
		} else if (message.t === 'members') {
			window.space.members = message.members;
			memberListeners.slice().forEach(function (fn) {
				try { fn(message.members); } catch (err) { console.error(err); }
			});
		}
	}

	window.addEventListener('message', function (ev) {
		if (port || !ev.data || ev.data.type !== 'space:port' || !ev.ports || !ev.ports[0]) return;
		port = ev.ports[0];
		port.onmessage = onMessage;
		queue.forEach(function (message) { port.postMessage(message); });
		queue = [];
	});

	// 枠の高さを中身に合わせてもらう。中身の高さは body で測る (html は、枠そのものの高さに引きずられることがある)
	var lastHeight = -1;
	function reportHeight() {
		if (!document.body) return;
		var height = Math.ceil(document.body.getBoundingClientRect().height);
		if (height === lastHeight) return;
		lastHeight = height;
		post({ t: 'resize', height: height });
	}
	window.addEventListener('load', function () {
		reportHeight();
		if (window.ResizeObserver) new ResizeObserver(reportHeight).observe(document.body);
		// 画像の読み込みなどで、あとから高さが変わることがある
		setInterval(reportHeight, 1000);
	});
})();
`;

/** 枠の中の見た目の土台。本体のテーマの色を引き継ぐ。 */
const BASE_STYLE = String.raw`
* { box-sizing: border-box; }
[hidden] { display: none !important; }
/* 縦のスクロールバーの場所をいつも空けておく。出たり消えたりすると幅が変わり、枠の高さが定まらなくなる */
html { scrollbar-gutter: stable; }
html, body { margin: 0; padding: 0; background: transparent; color: var(--fg); font-family: sans-serif; font-size: 14px; line-height: 1.5; }
body { padding: 10px 12px; }
button, input, textarea, select { font: inherit; color: inherit; }
button { cursor: pointer; border: 1px solid var(--divider); border-radius: 6px; background: var(--buttonBg); padding: 4px 12px; white-space: nowrap; flex-shrink: 0; }
button.primary { background: var(--accent); color: var(--fgOnAccent); border-color: transparent; }
input, textarea { width: 100%; border: 1px solid var(--divider); border-radius: 6px; background: var(--panel); padding: 6px 8px; }
textarea { display: block; resize: vertical; }
input:focus, textarea:focus { outline: 2px solid var(--accent); outline-offset: -1px; }
`;

/** 本体のテーマから枠に渡す色。枠の中の名前 → 本体の CSS 変数 */
const THEME_VARS = {
	fg: '--MI_THEME-fg',
	bg: '--MI_THEME-bg',
	panel: '--MI_THEME-panel',
	accent: '--MI_THEME-accent',
	fgOnAccent: '--MI_THEME-fgOnAccent',
	divider: '--MI_THEME-divider',
	buttonBg: '--MI_THEME-buttonBg',
} as const;

/** `</script>` などでスクリプトの外へ出られないよう、JSON を埋め込む前に `<` を置き換える。 */
function embedJson(value: unknown): string {
	// 行の区切りとして扱われる2つの文字も、スクリプトの中では置き換えておく
	return JSON.stringify(value)
		.replaceAll('<', '\\u003c')
		.replaceAll(String.fromCharCode(0x2028), '\\u2028')
		.replaceAll(String.fromCharCode(0x2029), '\\u2029');
}

function themeStyle(): string {
	const computed = window.getComputedStyle(window.document.documentElement);
	const declarations = Object.entries(THEME_VARS)
		.map(([name, source]) => `--${name}: ${computed.getPropertyValue(source).trim() || 'inherit'};`)
		.join(' ');
	return `:root { ${declarations} }`;
}

/**
 * 枠の中の通信の制限。スクリプトとスタイルは枠に書いたものだけ、画像と音はこのサーバーのドライブのファイルだけを読める。
 * それ以外の通信 (fetch など) はできない。WebRTC は、この指定では止められないブラウザがあるので、枠の中の準備で入口を消している。
 * 画像の許可先をサーバー全体にしないのは、外部の URL を代わりに取りに行く経路 (/proxy/) を通して、データを外へ送れてしまうため。
 */
function contentSecurityPolicy(origin: string): string {
	return [
		'default-src \'none\'',
		'script-src \'unsafe-inline\'',
		'style-src \'unsafe-inline\'',
		`img-src ${origin}/files/ data: blob:`,
		`media-src ${origin}/files/ data: blob:`,
		'form-action \'none\'',
		'base-uri \'none\'',
	].join('; ');
}

/** 枠に入れる文書を組み立てる。`tileHtml` はタイルの HTML と JavaScript。 */
export function buildTileDocument(tileHtml: string, init: TileInit, origin: string): string {
	return [
		'<!DOCTYPE html><html><head><meta charset="utf-8">',
		`<meta http-equiv="Content-Security-Policy" content="${contentSecurityPolicy(origin)}">`,
		`<style>${themeStyle()}${BASE_STYLE}</style>`,
		`<script type="application/json" id="space-init">${embedJson(init)}</script>`,
		`<script>${BOOTSTRAP}</script>`,
		'</head><body>',
		tileHtml,
		'</body></html>',
	].join('\n');
}
