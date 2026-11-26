/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * やることのタイル。項目を足し、済んだものに印を付ける。
 * 項目は1つずつ別のキー (item:ID) に書くので、同時に足してもぶつからない。
 */
export default String.raw`
<style>
	.entry { display: flex; gap: 6px; }
	ul { list-style: none; margin: 8px 0 0; padding: 0; }
	li { display: flex; align-items: center; gap: 8px; padding: 4px 0; }
	li input { width: auto; flex-shrink: 0; }
	li span { flex: 1; overflow-wrap: anywhere; }
	li.done span { text-decoration: line-through; opacity: 0.6; }
	li button { border: none; background: none; padding: 0 6px; opacity: 0.6; }
	#empty { margin-top: 8px; opacity: 0.6; font-size: 12px; }
</style>
<div class="entry"><input id="text" maxlength="200"><button id="add" class="primary"></button></div>
<div id="empty"></div>
<ul id="list"></ul>
<script>
	var $ = function (id) { return document.getElementById(id); };
	$('text').placeholder = space.t('placeholder');
	$('text').setAttribute('aria-label', space.t('placeholder'));
	$('add').textContent = space.t('add');
	$('empty').textContent = space.t('empty');

	function render() {
		var items = space.keys('item:').map(function (key) {
			var item = space.shared(key, null).get();
			// ほかの人が変な値を書いていても止まらないよう、形の合うものだけを項目として扱う
			return item && typeof item.text === 'string' ? { key: key, text: item.text, done: item.done === true, at: typeof item.at === 'number' && isFinite(item.at) ? item.at : 0 } : null;
		}).filter(function (item) { return item !== null; }).sort(function (a, b) { return a.at - b.at; });
		$('empty').hidden = items.length > 0;
		var list = $('list');
		list.textContent = '';
		items.forEach(function (item) {
			var li = document.createElement('li');
			if (item.done) li.className = 'done';
			var check = document.createElement('input');
			check.type = 'checkbox';
			check.checked = item.done;
			check.setAttribute('aria-label', item.text);
			check.addEventListener('change', function () {
				space.shared(item.key, null).set({ text: item.text, done: check.checked, at: item.at });
			});
			var text = document.createElement('span');
			text.textContent = item.text;
			var remove = document.createElement('button');
			remove.textContent = '×';
			remove.setAttribute('aria-label', space.t('remove'));
			remove.addEventListener('click', function () { space.shared(item.key, null).set(null); });
			li.appendChild(check);
			li.appendChild(text);
			li.appendChild(remove);
			list.appendChild(li);
		});
	}

	$('add').addEventListener('click', function () {
		var text = $('text').value.trim();
		if (text === '') return;
		var id = Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
		space.shared('item:' + id, null).set({ text: text, done: false, at: Date.now() });
		$('text').value = '';
	});
	$('text').addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); $('add').click(); } });

	space.onShared(render);
	render();
</script>
`;
