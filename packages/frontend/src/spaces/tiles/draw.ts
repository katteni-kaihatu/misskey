/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/**
 * らくがきのタイル。みんなで1枚に描く。
 * 描き終わった線は1本ずつ共有する値 (stroke:ID) に書く。描いている途中の線は、保存しない知らせで流す。
 * 線の点は、キャンバスの大きさに対する割合 (0〜1) で持つ。画面の幅が違う人どうしでも同じ絵になる。
 */
export default String.raw`
<style>
	canvas { display: block; width: 100%; aspect-ratio: 5 / 3; background: var(--panel); border: 1px solid var(--divider); border-radius: 6px; touch-action: none; cursor: crosshair; }
	.row { display: flex; align-items: center; gap: 6px; margin-top: 6px; }
	.color { width: 24px; height: 24px; padding: 0; border-radius: 50%; }
	.color[aria-pressed="true"] { outline: 2px solid var(--accent); outline-offset: 2px; }
	.space { flex: 1; }
</style>
<canvas id="canvas" width="1000" height="600"></canvas>
<div class="row" id="tools"><span class="space"></span><button id="clear"></button></div>
<script>
	var $ = function (id) { return document.getElementById(id); };
	var canvas = $('canvas');
	var context = canvas.getContext('2d');
	var COLORS = ['#222222', '#e5484d', '#2f9e44', '#1c7ed6', '#f08c00', '#ffffff'];
	var color = COLORS[0];
	var current = null;
	var lastSent = 0;
	// ほかの人が描いている途中の線。送った人ごとに1本
	var live = {};
	canvas.setAttribute('aria-label', space.t('name'));
	$('clear').textContent = space.t('clear');

	COLORS.forEach(function (value) {
		var button = document.createElement('button');
		button.className = 'color';
		button.style.background = value;
		button.setAttribute('aria-label', value);
		button.setAttribute('aria-pressed', value === color ? 'true' : 'false');
		button.addEventListener('click', function () {
			color = value;
			Array.prototype.forEach.call(document.querySelectorAll('.color'), function (other) {
				other.setAttribute('aria-pressed', other === button ? 'true' : 'false');
			});
		});
		$('tools').insertBefore(button, $('tools').firstChild);
	});

	// 1本の線に入れる数の上限 (x と y で2つずつ)。これを超えたら線を分ける。1回の書き込みの大きさに収めるため
	var MAX_VALUES = 4000;
	// 途中の線は、この時間更新が無ければ消す。描いている途中で出ていった人の線が残らないようにする
	var LIVE_TTL = 5000;

	function drawStroke(stroke) {
		if (!stroke || !Array.isArray(stroke.p) || stroke.p.length < 2) return;
		// ほかの人が変な値を書いていても止まらないよう、数だけでできた線だけを描く
		if (!stroke.p.every(function (n) { return typeof n === 'number' && isFinite(n); })) return;
		context.strokeStyle = typeof stroke.c === 'string' ? stroke.c : COLORS[0];
		context.lineWidth = 4;
		context.lineCap = 'round';
		context.lineJoin = 'round';
		context.beginPath();
		context.moveTo(stroke.p[0] * canvas.width, stroke.p[1] * canvas.height);
		for (var i = 2; i + 1 < stroke.p.length; i += 2) context.lineTo(stroke.p[i] * canvas.width, stroke.p[i + 1] * canvas.height);
		if (stroke.p.length === 2) context.lineTo(stroke.p[0] * canvas.width + 0.1, stroke.p[1] * canvas.height);
		context.stroke();
	}

	function render() {
		context.clearRect(0, 0, canvas.width, canvas.height);
		space.keys('stroke:').sort().forEach(function (key) { drawStroke(space.shared(key, null).get()); });
		Object.keys(live).forEach(function (userId) {
			if (Date.now() - live[userId].at > LIVE_TTL) delete live[userId]; else drawStroke(live[userId].stroke);
		});
		drawStroke(current);
	}

	function point(ev) {
		var rect = canvas.getBoundingClientRect();
		var round = function (n) { return Math.round(Math.min(1, Math.max(0, n)) * 1000) / 1000; };
		return [round((ev.clientX - rect.left) / rect.width), round((ev.clientY - rect.top) / rect.height)];
	}

	canvas.addEventListener('pointerdown', function (ev) {
		canvas.setPointerCapture(ev.pointerId);
		var p = point(ev);
		// ID は時刻で始めるので、並べると描いた順になる
		current = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), c: color, p: [p[0], p[1], p[0], p[1]] };
		render();
	});
	canvas.addEventListener('pointermove', function (ev) {
		if (!current) return;
		var p = point(ev);
		current.p.push(p[0], p[1]);
		if (current.p.length >= MAX_VALUES) {
			// 長くなったら、ここまでを1本として置き、続きを新しい線として描く
			var done = current;
			space.shared('stroke:' + done.id, null).set({ c: done.c, p: done.p });
			current = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), c: done.c, p: [p[0], p[1], p[0], p[1]] };
		}
		render();
		// 描いている途中の線は、間を空けて送る
		if (Date.now() - lastSent > 80) {
			lastSent = Date.now();
			space.send('drawing', { c: current.c, p: current.p });
		}
	});
	function finish() {
		if (!current) return;
		var stroke = current;
		current = null;
		space.shared('stroke:' + stroke.id, null).set({ c: stroke.c, p: stroke.p });
		space.send('drawing', null);
		render();
	}
	canvas.addEventListener('pointerup', finish);
	canvas.addEventListener('pointercancel', finish);

	$('clear').addEventListener('click', function () {
		space.keys('stroke:').forEach(function (key) { space.shared(key, null).set(null); });
		live = {};
		render();
	});
	// 途中の線の片づけのために、ときどき描き直す
	setInterval(function () { if (Object.keys(live).length > 0) render(); }, 1000);

	space.on('drawing', function (body, info) {
		if (info.userId === space.me.id) return;
		if (body && Array.isArray(body.p)) live[info.userId] = { stroke: body, at: Date.now() }; else delete live[info.userId];
		render();
	});
	space.onShared(render);
	render();
</script>
`;
