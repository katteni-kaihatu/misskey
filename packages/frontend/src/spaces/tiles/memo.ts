/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * メモのタイル。みんなで1枚の文章を書く。
 * 枠の中で動く HTML と JavaScript。使えるのは `space` だけ。
 */
export default String.raw`
<textarea id="text" rows="6"></textarea>
<script>
	var text = space.shared('text', '');
	var area = document.getElementById('text');
	area.placeholder = space.t('placeholder');
	area.setAttribute('aria-label', space.t('name'));
	area.value = text.get();

	var timer = null;
	area.addEventListener('input', function () {
		// 1文字ごとに送らず、少し待ってまとめて送る
		clearTimeout(timer);
		timer = setTimeout(function () { text.set(area.value); }, 200);
	});

	text.on(function (value, info) {
		if (info.self || value === area.value) return;
		// ほかの人が書いたものを出す。書いている途中なら、カーソルの位置をなるべく保つ
		var start = area.selectionStart;
		var end = area.selectionEnd;
		area.value = value;
		if (document.activeElement === area) area.setSelectionRange(Math.min(start, value.length), Math.min(end, value.length));
	});
</script>
`;
