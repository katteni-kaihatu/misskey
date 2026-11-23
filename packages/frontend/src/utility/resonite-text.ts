/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

/** Preserve provider colors where readable against even the brightest backdrop. */
export function readableResoniteColor(color: string | undefined): string | undefined {
	if (!color || !/^#(?:[\da-f]{3,4}|[\da-f]{6}|[\da-f]{8})$/i.test(color)) return undefined;
	let hex = color.slice(1);
	if (hex.length < 5) hex = [...hex].map(value => value + value).join('');
	const rgb = [0, 2, 4].map(offset => parseInt(hex.slice(offset, offset + 2), 16));
	// A white image at the backdrop's 14% opacity over the #2b2f35 panel.
	const background = [73, 77, 82];
	const alpha = hex.length === 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1;
	const base = rgb.map((value, i) => value * alpha + background[i] * (1 - alpha));
	const luminance = (values: number[]): number => values.reduce((sum, value, i) => {
		const channel = value / 255;
		return sum + (channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4) * [0.2126, 0.7152, 0.0722][i];
	}, 0);
	const backdrop = luminance(background);
	for (let step = 0; step <= 20; step++) {
		const candidate = base.map(value => Math.round(value + (255 - value) * step / 20));
		if ((luminance(candidate) + 0.05) / (backdrop + 0.05) >= 4.5) return `#${candidate.map(value => value.toString(16).padStart(2, '0')).join('')}`;
	}
	return '#ffffff';
}
