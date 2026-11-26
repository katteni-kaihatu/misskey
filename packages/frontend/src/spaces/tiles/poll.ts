/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * 投票のタイル。選択肢を作り、1人1票で選ぶ。
 * 票は人ごとのキー (vote:投票のID:ユーザーID) に書くので、同時に投票してもぶつからない。
 * 投票の ID を挟むのは、作り直しと投票が重なったときに、前の投票の票が次の投票に混ざらないようにするため。
 */
export default String.raw`
<style>
	.row { display: flex; gap: 6px; margin-top: 6px; }
	.choice { display: flex; align-items: center; gap: 8px; width: 100%; margin-top: 6px; text-align: left; position: relative; overflow: hidden; }
	.choice.mine { border-color: var(--accent); }
	.bar { position: absolute; left: 0; top: 0; bottom: 0; background: var(--accent); opacity: 0.18; }
	.label { flex: 1; position: relative; overflow-wrap: anywhere; }
	.count { position: relative; opacity: 0.8; }
	#question { font-weight: bold; overflow-wrap: anywhere; }
	.foot { display: flex; align-items: center; gap: 8px; margin-top: 8px; font-size: 12px; opacity: 0.8; }
	.foot span { flex: 1; }
</style>
<div id="setup">
	<input id="q" maxlength="200">
	<textarea id="c" rows="3" style="margin-top: 6px"></textarea>
	<div class="row"><button id="start" class="primary"></button></div>
</div>
<div id="vote" hidden>
	<div id="question"></div>
	<div id="choices"></div>
	<div class="foot"><span id="total"></span><button id="reset"></button></div>
</div>
<script>
	var question = space.shared('question', '');
	var choices = space.shared('choices', []);
	var pollId = space.shared('pollId', '');
	var $ = function (id) { return document.getElementById(id); };
	$('q').placeholder = space.t('question');
	$('c').placeholder = space.t('choices');
	$('start').textContent = space.t('start');
	$('reset').textContent = space.t('reset');

	function prefix() { return 'vote:' + String(pollId.get() || '') + ':'; }

	// ほかの人が変な値を書いていても止まらないよう、文字のものだけを選択肢として扱う
	function list() {
		var value = choices.get();
		return Array.isArray(value) ? value.filter(function (text) { return typeof text === 'string'; }) : [];
	}

	function votes() {
		var counts = {};
		space.keys(prefix()).forEach(function (key) {
			var index = space.shared(key, null).get();
			if (typeof index === 'number') counts[index] = (counts[index] || 0) + 1;
		});
		return counts;
	}

	function render() {
		var items = list();
		var open = items.length > 0;
		$('setup').hidden = open;
		$('vote').hidden = !open;
		if (!open) return;
		$('question').textContent = typeof question.get() === 'string' ? question.get() : '';
		var counts = votes();
		var total = 0;
		Object.keys(counts).forEach(function (key) { total += counts[key]; });
		var mine = space.shared(prefix() + space.me.id, null).get();
		var box = $('choices');
		box.textContent = '';
		items.forEach(function (text, index) {
			var button = document.createElement('button');
			button.className = 'choice' + (mine === index ? ' mine' : '');
			var bar = document.createElement('span');
			bar.className = 'bar';
			bar.style.width = (total === 0 ? 0 : Math.round((counts[index] || 0) * 100 / total)) + '%';
			var label = document.createElement('span');
			label.className = 'label';
			label.textContent = text;
			var count = document.createElement('span');
			count.className = 'count';
			count.textContent = String(counts[index] || 0);
			button.appendChild(bar);
			button.appendChild(label);
			button.appendChild(count);
			button.setAttribute('aria-pressed', mine === index ? 'true' : 'false');
			button.addEventListener('click', function () {
				// もう一度押すと票を取り消す
				space.shared(prefix() + space.me.id, null).set(mine === index ? null : index);
			});
			box.appendChild(button);
		});
		$('total').textContent = space.t('total').replace('{n}', String(total));
	}

	$('start').addEventListener('click', function () {
		var entered = $('c').value.split('\n').map(function (line) { return line.trim(); }).filter(function (line) { return line !== ''; });
		if (entered.length < 2) return;
		pollId.set(Date.now().toString(36) + Math.random().toString(36).slice(2, 8));
		question.set($('q').value.trim());
		choices.set(entered.slice(0, 20));
	});

	$('reset').addEventListener('click', function () {
		space.keys('vote:').forEach(function (key) { space.shared(key, null).set(null); });
		choices.set(null);
		question.set(null);
	});

	space.onShared(render);
	render();
</script>
`;
