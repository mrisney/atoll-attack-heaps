package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Breaking surf along the coast, from WildCurrent's animated swell sheet
	(res/effects/surf-sheet.png: 3×2 frames, played at 7 fps).

	Waves sit just offshore, rotated to run along the coastline with the crest
	facing land, in a couple of rows. Each wave has its own phase so the coast
	doesn't pulse in unison. All waves are one mesh with one draw call. The
	frame is chosen per pixel in `SurfShader` from time + the wave's phase, which
	is stored in the vertex colour.
**/
class Surf {
	/** Returns the surf shader so the view can recolour it per style. **/
	public static function build(island:world.Island, parent:h3d.scene.Object):Null<SurfShader> {
		var pts:Array<Point> = [], uvs:Array<UV> = [], cols:Array<Point> = [];
		var idx = new hxd.IndexBuffer();
		var n = new world.Noise(island.seed + 909);
		var he = island.halfExtent;

		// March inward along rays from the map edge; the first time we reach
		// shallow water, we're just off a coast that faces open sea.
		var rays = 170;
		for (k in 0...rays) {
			var a = k / rays * Math.PI * 2 + n.rand(k, 1) * 0.02;
			var dx = Math.cos(a), dy = Math.sin(a);
			var t = he * 1.05;
			var hit = -1.0;
			while (t > 2) {
				var h = island.heightAt(dx * t, dy * t);
				if (h > -0.45) {
					hit = t;
					break;
				}
				t -= 0.4;
			}
			if (hit < 0) continue;

			// Coast tangent from the height gradient (more accurate than the ray).
			var x = dx * hit, y = dy * hit;
			var gx = island.heightAt(x + 0.6, y) - island.heightAt(x - 0.6, y);
			var gy = island.heightAt(x, y + 0.6) - island.heightAt(x, y - 0.6);
			var gl = Math.sqrt(gx * gx + gy * gy);
			var ux = gl > 1e-5 ? gx / gl : -dx, uy = gl > 1e-5 ? gy / gl : -dy; // uphill = toward land

			for (row in 0...2) {
				if (n.rand(k, 10 + row) < 0.35) continue; // gaps, so it isn't a wall of foam
				var off = 0.6 + row * 1.7 + n.rand(k, 20 + row) * 0.6;
				var cx = x - ux * off, cy = y - uy * off;
				var len = 4.5 + n.rand(k, 30 + row) * 2.5;
				var depth = len * 0.75 * 0.55; // sprite is 4:3; the crest band is the middle
				var phase = n.rand(k, 40 + row);
				addQuad(pts, uvs, cols, idx, cx, cy, 0.13 + row * 0.01, ux, uy, len, depth, phase);
			}
		}
		if (pts.length == 0) return null;

		var poly = new h3d.prim.Polygon(pts, idx);
		poly.uvs = uvs;
		poly.colors = cols;
		var m = new h3d.scene.Mesh(poly, parent);
		var mat = m.material;
		mat.castShadows = false;
		mat.receiveShadows = false;
		mat.blendMode = Alpha;
		mat.mainPass.depthWrite = false;
		mat.mainPass.culling = None;
		mat.mainPass.enableLights = false;
		var sh = new SurfShader();
		sh.sheet = SpriteProps.texture("effects/surf-sheet.png");
		mat.mainPass.addShader(sh);
		return sh;
	}

	/** A quad whose image-up points toward land (`ux`, `uy`), so the crest faces shore. **/
	static function addQuad(pts:Array<Point>, uvs:Array<UV>, cols:Array<Point>, idx:hxd.IndexBuffer, cx:Float, cy:Float, z:Float, ux:Float,
			uy:Float, len:Float, depth:Float, phase:Float) {
		var tx = -uy, ty = ux; // along the coast
		var base = pts.length;
		for (c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
			var px = cx + tx * c[0] * len * 0.5 + ux * c[1] * depth * 0.5;
			var py = cy + ty * c[0] * len * 0.5 + uy * c[1] * depth * 0.5;
			pts.push(new Point(px, py, z));
			uvs.push(new UV((c[0] + 1) * 0.5, 1 - (c[1] + 1) * 0.5));
			cols.push(new Point(phase, 0, 0));
		}
		for (k in [0, 1, 2, 0, 2, 3]) idx.push(base + k);
	}
}

/** Plays the 3×2 surf sheet; each wave's phase comes from its vertex colour. **/
class SurfShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
		};
		@input var input:{
			var uv:Vec2;
			var color:Vec3;
		};
		@param var sheet:Sampler2D;
		@param var fps:Float;
		@param var opacity:Float;
		/** The wave's back is recoloured to this (a deeper shade of the local water). **/
		@param var body:Vec3;
		@param var bodyAlpha:Float;
		var pixelColor:Vec4;
		var calculatedUV:Vec2;
		var wavePhase:Float;

		function vertex() {
			calculatedUV = input.uv;
			wavePhase = input.color.r;
		}

		function fragment() {
			var frame = floor(fract(global.time * fps / 6.0 + wavePhase) * 6.0);
			var col = mod(frame, 3.0);
			var row = floor(frame / 3.0);
			// Inset slightly so neighbouring frames don't bleed in through filtering.
			var uv = clamp(calculatedUV, vec2(0.004), vec2(0.996));
			var c = sheet.get((vec2(col, row) + uv) / vec2(3.0, 2.0));
			// Fade the ends of each wave so the strips don't show hard edges.
			var edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
			// Keep the white foam; recolour the dark back of the wave to suit our water.
			var lum = dot(c.rgb, vec3(0.333));
			var foam = smoothstep(0.42, 0.78, lum);
			var rgb = mix(body, vec3(0.97, 0.99, 1.0), foam);
			var a = c.a * mix(bodyAlpha, 1.0, foam);
			pixelColor = vec4(rgb, a * opacity * edge);
		}
	};

	public function new() {
		super();
		fps = 7;
		opacity = 0.9;
		bodyAlpha = 0.45;
		body.set(0.2, 0.5, 0.62);
	}
}
