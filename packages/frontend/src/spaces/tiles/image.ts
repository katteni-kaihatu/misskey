/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * 画像のタイル。ドライブの画像を1枚出す。
 * ファイルを選ぶ画面は本体が出す。枠の中からドライブは見えない。
 */
export default String.raw`
<style>
	img { display: block; max-width: 100%; max-height: 480px; margin: 0 auto; border-radius: 6px; }
	.row { display: flex; align-items: center; gap: 8px; margin-top: 6px; }
	#name { flex: 1; font-size: 12px; opacity: 0.7; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	#empty { text-align: center; padding: 12px 0; }
</style>
<div id="empty"><button id="pick" class="primary"></button></div>
<div id="view" hidden>
	<img id="image" alt="">
	<div class="row"><span id="name"></span><button id="change"></button></div>
</div>
<script>
	var file = space.shared('file', null);
	var $ = function (id) { return document.getElementById(id); };
	$('pick').textContent = space.t('pick');
	$('change').textContent = space.t('change');

	function render() {
		var current = file.get();
		var has = current && typeof current.url === 'string';
		$('empty').hidden = !!has;
		$('view').hidden = !has;
		if (!has) return;
		if ($('image').getAttribute('src') !== current.url) $('image').src = current.url;
		$('image').alt = current.name || '';
		$('name').textContent = current.name || '';
	}

	function pick() {
		space.pickFile().then(function (picked) {
			if (picked && /^image\//.test(picked.type)) file.set({ url: picked.url, name: picked.name });
		}).catch(function () { /* 選ばずに閉じた */ });
	}
	$('pick').addEventListener('click', pick);
	$('change').addEventListener('click', pick);

	space.onShared(render);
	render();
</script>
`;
