/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * ノートのタイル。ノートの URL か ID を入れると、そのノートを出す。
 * ノートは本体がログインなしの立場で読む。公開されていないノートは出せない。
 * 本文は文字として出す。絵文字や装飾は描かない。全文はノートのページを開いて見る。
 */
export default String.raw`
<style>
	.entry { display: flex; gap: 6px; }
	#author { font-weight: bold; overflow-wrap: anywhere; }
	#author small { font-weight: normal; opacity: 0.7; margin-left: 4px; }
	#body { white-space: pre-wrap; overflow-wrap: anywhere; margin-top: 4px; max-height: 240px; overflow-y: auto; }
	#status { opacity: 0.7; font-size: 12px; }
	.row { display: flex; justify-content: flex-end; gap: 6px; margin-top: 6px; }
</style>
<div class="entry" id="form"><input id="input" maxlength="500"><button id="set" class="primary"></button></div>
<div id="view" hidden>
	<div id="status"></div>
	<div id="author"></div>
	<div id="body"></div>
	<div class="row"><button id="open"></button><button id="change"></button></div>
</div>
<script>
	var noteId = space.shared('noteId', '');
	var $ = function (id) { return document.getElementById(id); };
	$('input').placeholder = space.t('placeholder');
	$('input').setAttribute('aria-label', space.t('placeholder'));
	$('set').textContent = space.t('set');
	$('open').textContent = space.t('open');
	$('change').textContent = space.t('change');
	var shown = null;

	function render() {
		var id = noteId.get();
		var has = typeof id === 'string' && id !== '';
		$('form').hidden = has;
		$('view').hidden = !has;
		if (!has || shown === id) return;
		shown = id;
		$('status').textContent = space.t('loading');
		$('author').textContent = '';
		$('body').textContent = '';
		space.misskey('notes/show', { noteId: id }).then(function (note) {
			if (noteId.get() !== id) return;
			$('status').textContent = '';
			$('author').textContent = (note.user && (note.user.name || note.user.username)) || '';
			var handle = document.createElement('small');
			handle.textContent = note.user ? '@' + note.user.username : '';
			$('author').appendChild(handle);
			// 注意書きつきのノートは、注意書きだけを出す
			$('body').textContent = note.cw != null ? note.cw + ' ' + space.t('hidden') : (note.text || '');
		}).catch(function () {
			if (noteId.get() === id) $('status').textContent = space.t('notFound');
		});
	}

	$('input').addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); $('set').click(); } });
	$('set').addEventListener('click', function () {
		// URL でも ID でも受ける。URL なら最後の /notes/ のあとを ID とする
		var value = $('input').value.trim();
		var matched = /\/notes\/([a-zA-Z0-9]+)/.exec(value);
		var id = matched ? matched[1] : value;
		if (/^[a-zA-Z0-9]{1,64}$/.test(id)) noteId.set(id);
	});
	$('open').addEventListener('click', function () { space.open(space.origin + '/notes/' + noteId.get()); });
	$('change').addEventListener('click', function () { shown = null; noteId.set(null); });

	space.onShared(render);
	render();
</script>
`;
