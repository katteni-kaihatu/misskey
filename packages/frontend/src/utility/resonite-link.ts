/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

export function getResoniteLink(input: string): { type: 'world' | 'session'; url: string; launchUrl: string } | null {
	try {
		const url = new URL(input);
		if (url.username || url.password) return null;
		const path = url.origin === 'https://go.resonite.com' ? url.pathname : url.origin === 'https://api.resonite.com' && url.pathname.startsWith('/open/') ? url.pathname.slice(5) : null;
		if (!path) return null;
		const parts = path.replace(/\/$/, '').split('/').slice(1).map(decodeURIComponent);
		if ((parts[0] === 'world' || parts[0] === 'record') && parts.length === 3 && /^(U|G)-[a-zA-Z0-9._-]{1,128}$/.test(parts[1]) && /^R-[a-zA-Z0-9_-]{1,128}$/.test(parts[2])) {
			return { type: 'world', url: `https://go.resonite.com/world/${encodeURIComponent(parts[1])}/${encodeURIComponent(parts[2])}`, launchUrl: `resrec:///${parts[1]}/${parts[2]}` };
		}
		if (parts[0] === 'session' && parts.length === 2 && /^S-[a-zA-Z0-9_:-]{1,190}$/.test(parts[1])) {
			return { type: 'session', url: `https://go.resonite.com/session/${encodeURIComponent(parts[1])}`, launchUrl: `ressession:///${parts[1]}` };
		}
	} catch { /* Ordinary URL previews handle other links. */ }
	return null;
}
