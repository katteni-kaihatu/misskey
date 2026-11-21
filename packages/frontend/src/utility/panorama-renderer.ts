/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */
import * as THREE from 'three';

export type PanoramaRenderer = {
	resize: (width: number, height: number) => void;
	render: (yaw: number) => void;
	dispose: () => void;
};

/** Loaded only for a visible equirectangular image; no renderer owns an animation loop. */
export function createPanoramaRenderer(canvas: HTMLCanvasElement, image: HTMLImageElement): PanoramaRenderer {
	// Keep full-size proxy URLs, but bound the GPU texture even for 8K panoramas.
	let source: HTMLImageElement | HTMLCanvasElement = image;
	if (image.naturalWidth > 2048) {
		const scaled = window.document.createElement('canvas');
		scaled.width = 2048;
		scaled.height = Math.max(1, Math.round(image.naturalHeight * 2048 / image.naturalWidth));
		const context = scaled.getContext('2d');
		if (!context) throw new Error('Panorama image scaling is unavailable');
		context.drawImage(image, 0, 0, scaled.width, scaled.height);
		source = scaled;
	}
	const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'low-power' });
	const texture = new THREE.Texture(source);
	const geometry = new THREE.SphereGeometry(10, 48, 24);
	const material = new THREE.MeshBasicMaterial({ map: texture, side: THREE.BackSide });
	const scene = new THREE.Scene();
	const camera = new THREE.PerspectiveCamera(65, 1, 0.1, 20);
	let disposed = false;
	texture.colorSpace = THREE.SRGBColorSpace;
	texture.minFilter = THREE.LinearFilter;
	texture.generateMipmaps = false;
	texture.needsUpdate = true;
	// Viewing the inside of a sphere reverses the usual texture orientation.
	texture.repeat.x = -1;
	texture.wrapS = THREE.RepeatWrapping;
	renderer.outputColorSpace = THREE.SRGBColorSpace;
	scene.add(new THREE.Mesh(geometry, material));
	return {
		resize(width, height) {
			if (disposed) return;
			const safeWidth = Math.max(1, width);
			const safeHeight = Math.max(1, height);
			renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5, 768 / Math.max(safeWidth, safeHeight)));
			renderer.setSize(safeWidth, safeHeight, false);
			camera.aspect = safeWidth / safeHeight;
			camera.updateProjectionMatrix();
		},
		render(yaw) {
			if (disposed) return;
			camera.lookAt(Math.sin(yaw), 0, -Math.cos(yaw));
			renderer.render(scene, camera);
		},
		dispose() {
			if (disposed) return;
			disposed = true;
			texture.dispose();
			geometry.dispose();
			material.dispose();
			renderer.dispose();
			renderer.forceContextLoss();
		},
	};
}
