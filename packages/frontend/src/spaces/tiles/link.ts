/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * リンクのタイル。URL をカードで出す。
 * タイトルと説明は本体に取ってきてもらう。開くときも本体に頼む (本体が確かめてから開く)。
 */
export default String.raw`
<style>
	.entry { display: flex; gap: 6px; }
	#card { display: block; width: 100%; text-align: left; padding: 8px 10px; }
	#title { font-weight: bold; overflow-wrap: anywhere; }
	#description { font-size: 12px; opacity: 0.8; overflow-wrap: anywhere; margin-top: 2px; }
	#host { font-size: 12px; opacity: 0.6; margin-top: 4px; overflow-wrap: anywhere; }
	.row { display: flex; justify-content: flex-end; margin-top: 6px; }
</style>
<div class="entry" id="form"><input id="input" type="url" maxlength="2000"><button id="set" class="primary"></button></div>
<div id="view" hidden>
	<button id="card"><div id="title"></div><div id="description"></div><div id="host"></div></button>
	<div class="row"><button id="change"></button></div>
</div>
<script>
	var url = space.shared('url', '');
	var preview = space.shared('preview', null);
	var $ = function (id) { return document.getElementById(id); };
	$('input').placeholder = 'https://';
	$('input').setAttribute('aria-label', space.t('url'));
	$('set').textContent = space.t('set');
	$('change').textContent = space.t('change');

	function render() {
		var current = url.get();
		var has = typeof current === 'string' && current !== '';
		$('form').hidden = has;
		$('view').hidden = !has;
		if (!has) return;
		// プレビューは、いまの URL のものだけを出す。2人が同時に別の URL を置いたときに、説明とリンク先が食い違わないようにする
		var stored = preview.get();
		var info = stored && stored.url === current ? stored : {};
		var text = function (value) { return typeof value === 'string' ? value : ''; };
		$('title').textContent = text(info.title) || current;
		$('description').textContent = text(info.description);
		$('host').textContent = text(info.sitename) || current;
	}

	$('input').addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); $('set').click(); } });
	$('set').addEventListener('click', function () {
		var value = $('input').value.trim();
		if (!/^https?:\/\//.test(value)) return;
		preview.set(null);
		url.set(value);
		space.preview(value).then(function (info) {
			// 取ってきている間に別の URL に変わっていたら、書かない
			if (info && url.get() === value) preview.set({ url: value, title: info.title || '', description: info.description || '', sitename: info.sitename || '' });
		}).catch(function () { /* 取れなくても URL だけ出す */ });
	});
	$('card').addEventListener('click', function () { space.open(url.get()); });
	$('change').addEventListener('click', function () {
		$('input').value = url.get();
		preview.set(null);
		url.set(null);
	});

	space.onShared(render);
	render();
</script>
`;
