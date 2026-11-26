/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * タイマーのタイル。切れる時刻を共有し、残り時間は各自の画面で計算して出す。
 * 「切れた」と書くのは、まず担当の1人。全員の手元で同時に切れても、処理が人数分動かないようにする。
 * 担当がこのタイルを画面に出していない (ほかのページを見ている) こともあるので、少し待っても書かれなければ、ほかの人が書く。
 * 書くのは同じ値なので、重なっても害は無い。音は、切れた時刻ごとに1回だけ鳴らす。
 */
export default String.raw`
<style>
	#time { font-size: 32px; font-weight: bold; text-align: center; font-variant-numeric: tabular-nums; }
	#time.done { color: var(--accent); }
	.row { display: flex; align-items: center; justify-content: center; gap: 6px; margin-top: 6px; }
	#minutes { width: 72px; }
	#message { min-height: 1.5em; font-weight: bold; }
</style>
<div id="time" role="timer" aria-live="off">00:00</div>
<div id="message" class="row" role="status" aria-live="polite"></div>
<div class="row" id="setup"><input id="minutes" type="number" min="1" max="600" value="5"><span id="unit"></span><button id="start" class="primary"></button></div>
<div class="row" id="running" hidden><button id="stop"></button></div>
<script>
	var endsAt = space.shared('endsAt', null);
	var finished = space.shared('finished', false);
	var $ = function (id) { return document.getElementById(id); };
	$('unit').textContent = space.t('minutes');
	$('start').textContent = space.t('start');
	$('stop').textContent = space.t('stop');
	$('minutes').setAttribute('aria-label', space.t('minutes'));

	// 担当が書かなかったときに、自分が代わりに書くまでの待ち時間。人ごとにずらして、一斉に書かないようにする
	var GRACE = 3000 + Math.floor(Math.random() * 2000);
	// 音を鳴らし終えた「切れる時刻」。開いた時点で切れていたものは鳴らさない
	var rungFor = finished.get() === true ? endsAt.get() : null;

	function beep() {
		// ブラウザが止めることがある。鳴らなくても、表示で分かるようにしてある
		try {
			var context = new (window.AudioContext || window.webkitAudioContext)();
			var oscillator = context.createOscillator();
			var gain = context.createGain();
			oscillator.frequency.value = 880;
			gain.gain.value = 0.1;
			oscillator.connect(gain);
			gain.connect(context.destination);
			oscillator.start();
			oscillator.stop(context.currentTime + 0.6);
		} catch (err) { /* 鳴らせない環境 */ }
	}

	function render() {
		var end = endsAt.get();
		var running = typeof end === 'number' && isFinite(end);
		var done = running && finished.get() === true;
		var left = running ? end - Date.now() : 0;
		var remaining = Math.max(0, Math.ceil(left / 1000));
		var m = Math.floor(remaining / 60);
		var s = remaining % 60;
		$('time').textContent = (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
		$('time').className = done ? 'done' : '';
		var message = done ? space.t('finished') : '';
		if ($('message').textContent !== message) $('message').textContent = message;
		$('setup').hidden = running;
		$('running').hidden = !running;

		if (running && !done && left <= 0 && (space.isLeader || -left > GRACE)) finished.set(true);
		if (done && rungFor !== end) {
			rungFor = end;
			beep();
		}
	}

	$('start').addEventListener('click', function () {
		var minutes = Math.min(600, Math.max(1, Number($('minutes').value) || 1));
		finished.set(false);
		endsAt.set(Date.now() + minutes * 60000);
	});
	$('stop').addEventListener('click', function () {
		endsAt.set(null);
		finished.set(false);
	});

	space.onShared(render);
	space.onLeader(render);
	setInterval(render, 250);
	render();
</script>
`;
