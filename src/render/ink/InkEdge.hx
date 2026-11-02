package render.ink;

import render.Palette;

/**
	Screen-space ink: finds edges in the geometry buffer and draws them as
	semi-opaque ink over the frame.

	- Normal creases: neighbouring pixels whose normals disagree.
	- Depth breaks: a Laplacian on *inverse* depth, which is linear across any
	  flat surface in screen space, so slopes seen at a grazing angle don't
	  produce false lines — only real silhouettes do.
	- A low-frequency noise nudges line weight so it reads hand-inked.
**/
class InkEdge extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var geo:Sampler2D;
		@param var texel:Vec2;
		@param var ink:Vec3;
		@param var strength:Float;
		@param var width:Float;
		@param var normalThreshold:Float;
		@param var depthThreshold:Float;
		/** Sketch style: the drawing dissolves into the page toward the top and edges. **/
		@param var fade:Float;
		@param var paper:Vec3;

		function decodeN(c:Vec4):Vec3 {
			return c.rgb * 2.0 - 1.0;
		}

		function hash(p:Vec2):Float {
			return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
		}

		function fragment() {
			var uv = calculatedUV;
			// Wobble the stroke width a little, in screen-space blotches.
			var cell = floor(uv / (texel * 18.0));
			var w = width * (0.75 + 0.5 * hash(cell));
			var dx = vec2(texel.x * w, 0.0);
			var dy = vec2(0.0, texel.y * w);

			var c0 = geo.get(uv);
			var cl = geo.get(uv - dx);
			var cr = geo.get(uv + dx);
			var cu = geo.get(uv - dy);
			var cd = geo.get(uv + dy);

			var edge = 0.0;
			// Ignore anything touching empty background.
			if (c0.a < 0.999 && cl.a < 0.999 && cr.a < 0.999 && cu.a < 0.999 && cd.a < 0.999) {
				var n0 = decodeN(c0);
				var nd = max(max(1.0 - dot(n0, decodeN(cl)), 1.0 - dot(n0, decodeN(cr))),
					max(1.0 - dot(n0, decodeN(cu)), 1.0 - dot(n0, decodeN(cd))));

				var i0 = 1.0 / c0.a;
				var lapX = abs(1.0 / cl.a + 1.0 / cr.a - 2.0 * i0);
				var lapY = abs(1.0 / cu.a + 1.0 / cd.a - 2.0 * i0);
				var dd = max(lapX, lapY) / i0;

				edge = max(smoothstep(normalThreshold, normalThreshold * 1.8, nd), smoothstep(depthThreshold, depthThreshold * 2.5, dd));
			}
			var inkA = edge * strength;
			if (fade > 0.0) {
				// Upper part of the frame (far away) and the margins fade to paper.
				var top = 1.0 - smoothstep(0.02, 0.45, uv.y);
				var side = 1.0 - smoothstep(0.0, 0.14, min(uv.x, 1.0 - uv.x));
				var bottom = 1.0 - smoothstep(0.0, 0.1, 1.0 - uv.y);
				var f = fade * clamp(max(top * 0.92, max(side, bottom) * 0.75), 0.0, 1.0);
				inkA *= 1.0 - f * 0.85;
				var a = 1.0 - (1.0 - f) * (1.0 - inkA);
				var col = (paper * f * (1.0 - inkA) + ink * inkA) / max(a, 0.0001);
				pixelColor = vec4(col, a);
			} else
				pixelColor = vec4(ink, inkA);
		}
	};

	public function new() {
		super();
		ink.set(Palette.r(Palette.INK), Palette.g(Palette.INK), Palette.b(Palette.INK));
		strength = 0.85;
		width = 1.3;
		normalThreshold = 0.35;
		depthThreshold = 0.03;
		fade = 0;
		paper.set(Palette.r(Palette.SKETCH_BG), Palette.g(Palette.SKETCH_BG), Palette.b(Palette.SKETCH_BG));
	}
}
