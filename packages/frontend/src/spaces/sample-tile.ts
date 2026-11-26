/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/** 新しくタイルをつくるときに、最初に入れておく見本。みんなで数えるカウンター。 */
export default String.raw`<style>
	#count { font-size: 32px; font-weight: bold; text-align: center; }
	.row { display: flex; justify-content: center; gap: 8px; }
</style>
<div id="count">0</div>
<div class="row">
	<button id="minus">-1</button>
	<button id="plus" class="primary">+1</button>
</div>
<script>
	// space.shared(キー, 最初の値) は、スペースの全員で同じになる値
	var count = space.shared('count', 0);

	function render() {
		document.getElementById('count').textContent = count.get();
	}

	document.getElementById('plus').addEventListener('click', function () { count.set(count.get() + 1); });
	document.getElementById('minus').addEventListener('click', function () { count.set(count.get() - 1); });

	// だれかが値を変えたら (自分が変えたときも) 描き直す
	count.on(render);
	render();
</script>
`;
