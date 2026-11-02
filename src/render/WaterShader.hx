package render;

/**
	Water: the atoll-attack look — three depth bands (shallows, mid, deep)
	read from a heightmap of the island — lit by real wind waves.

	The waves come from `OceanWaves` (an FFT ocean baked into a looping
	texture). They're sampled at two scales and rotations so the tiling never
	shows, then used for:
	- light and shade from the wave slopes (sun on the faces, darker troughs);
	- sun glints (specular reflection toward the camera);
	- slightly lighter crests;
	- froth from the wave simulation's own foam (where crests fold over):
	  sparse whitecaps at sea, and in the shallows the swell breaks into
	  white water that rolls in and runs up the beach (with TerrainStyle's swash).
	Waves fade out over the reef and in the lagoon (they need depth), and
	toward the horizon where the texture would shimmer.
**/
class WaterShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
			@perObject var modelView:Mat4;
		};
		@global var camera:{
			var position:Vec3;
		};

		@param var waveTex:Sampler2D;
		/** Overall wave lighting strength (0 = flat water). **/
		@param var waves:Float;
		@param var glint:Float;
		@param var whitecap:Float;
		@param var sunDir:Vec3;
		/** Breaking waves in the shallows, rolling onto the beach (0 = off). **/
		@param var breakers:Float;

		@param var amplitude:Float;
		@param var shimmer:Float;

		@param var heightMap:Sampler2D;
		@param var mapOrigin:Vec2;
		@param var mapSize:Float;
		@param var heightRange:Float;

		@param var shallow:Vec3;
		@param var mid:Vec3;
		@param var deep:Vec3;
		@param var tShallow:Float;
		@param var tMid:Float;
		/** Extra blur on band edges (0 = hard Classic bands). **/
		@param var softness:Float;
		/** Sketch style: ruled pen strokes along the shore (0 = off). **/
		@param var ruled:Float;
		@param var ruleInk:Vec3;

		var relativePosition:Vec3;
		var transformedPosition:Vec3;
		var pixelColor:Vec4;

		/** One sample of the baked wave atlas: (slope x, slope y, height, foam), each 0..1. **/
		function waveAt4(p:Vec2, frame:Float):Vec4 {
			var t = fract(p);
			var col = mod(frame, 8.0);
			var row = floor(frame / 8.0);
			var uv = (vec2(col, row) * 66.0 + 1.0 + t * 64.0) / vec2(528.0, 264.0);
			return waveTex.get(uv);
		}

		/**
			Where this stretch of coast is in its breaking cycle (0..1).
			Shared with TerrainStyle (same formula) so the swash on the sand follows
			the breaker in the water. Each stretch of shore has its own timing.
		**/
		function shoreCycle(p:Vec2, time:Float):Float {
			var ph = waveTex.get((1.0 + fract(p / 70.0) * 64.0) / vec2(528.0, 264.0)).b;
			return fract(time / 6.5 + ph * 2.5);
		}

		function vertex() {
			var p = relativePosition * global.modelView.mat3x4();
			var t = global.time;
			p.z += (sin(p.x * 0.35 + t * 1.1) + cos(p.y * 0.28 + t * 0.9)) * amplitude;
			transformedPosition = p;
		}

		function fragment() {
			// Beyond the map, keep the edge's depth (the map edge is open sea). A hard switch
			// to a constant depth there left a thin bright seam along the map border.
			var uv = clamp((transformedPosition.xy - mapOrigin) / mapSize, vec2(0.0), vec2(1.0));
			var h = (heightMap.get(uv).r * 2.0 - 1.0) * heightRange;
			var depth = -h;

			var aa = max(fwidth(depth), 0.0001) + softness;
			var c = mix(shallow, mid, smoothstep(tShallow - aa, tShallow + aa, depth));
			c = mix(c, deep, smoothstep(tMid - aa, tMid + aa, depth));

			var t = global.time;
			var s = sin(transformedPosition.x * 0.9 + t * 1.7) * sin(transformedPosition.y * 0.8 - t * 1.3);
			c += vec3(shimmer * s * (1.0 - waves));

			if (waves > 0.0 && depth > -0.05) {
				var q = transformedPosition.xy;
				var fr = fract(t / 9.0) * 32.0;
				var f0 = floor(fr);
				var f1 = mod(f0 + 1.0, 32.0);
				var ft = fr - f0;
				var p1 = q / 34.0;
				var p2 = vec2(q.x * 0.8 - q.y * 0.6, q.x * 0.6 + q.y * 0.8) / 13.0 + vec2(0.37, 0.71);
				var w1 = mix(waveAt4(p1, f0), waveAt4(p1, f1), ft);
				var w2 = mix(waveAt4(p2, f0), waveAt4(p2, f1), ft);
				// Fade detail where a pixel spans several texels (far away), so it doesn't shimmer.
				var near = 1.0 - smoothstep(0.03, 0.09, fwidth(p2.x));
				// Waves need depth: full swell at sea, calm over the reef and in the lagoon.
				var amp = smoothstep(0.3, 4.0, depth) * waves * near;
				var sl = (w1.xy * 2.0 - 1.0) + (w2.xy * 2.0 - 1.0) * 0.55;
				var hh = w1.z * 0.65 + w2.z * 0.35;
				var n = normalize(vec3(-sl * 0.55 * amp, 1.0));
				var view = normalize(camera.position - transformedPosition);
				// Light and shade relative to flat water, so the band colours stay the base tone.
				var lit = dot(n, sunDir) - sunDir.z;
				c *= 1.0 + lit * 1.1;
				c *= 1.0 + (hh - 0.5) * 0.35 * amp;
				var r = reflect(-view, n);
				var spec = pow(max(dot(r, sunDir), 0.0), 48.0) * glint * amp;

				// Froth: foam from the wave simulation (where crests fold over), with a
				// finer sample for the lacy breakup.
				var p3 = vec2(q.x * 0.6 + q.y * 0.8, -q.x * 0.8 + q.y * 0.6) / 4.5 + vec2(0.11, 0.53);
				var fine = mix(waveAt4(p3, f0), waveAt4(p3, f1), ft).a;
				var fo = w1.a * 0.7 + w2.a * 0.6;
				var lace = smoothstep(0.15, 0.55, fine + fo * 0.5);
				// Open sea: whitecaps only on the strongest folds.
				var froth = smoothstep(0.2, 0.65, fo) * lace * min(1.0, whitecap * 3.0) * amp;
				// Shoaling: as the water gets shallow the swell trips and breaks, so foam forms
				// far more easily, and rolls in toward the beach.
				var exposed = heightMap.get(uv).g;
				var shoal = (1.0 - smoothstep(0.1, 1.8, depth)) * step(0.0, depth) * breakers * near * exposed;
				var sc = shoreCycle(q, t);
				// Two sets of breakers, half a cycle apart, each a frothy front with a fading
				// trail, rolling in along the depth contours to reach the shore as the cycle wraps.
				var ddA = depth - (1.0 - sc) * 1.5;
				var ddB = depth - (1.0 - fract(sc + 0.5)) * 1.5;
				var frontA = smoothstep(-0.08, 0.0, ddA) * (1.0 - smoothstep(0.0, 0.6, ddA)) * smoothstep(0.05, 0.4, sc);
				var frontB = smoothstep(-0.08, 0.0, ddB) * (1.0 - smoothstep(0.0, 0.6, ddB)) * smoothstep(0.05, 0.4, fract(sc + 0.5)) * 0.7;
				var front = max(frontA, frontB);
				// The surf zone: churned white water hugging the shore.
				var zone = 1.0 - smoothstep(0.15, 1.1, depth);
				var foamy = fine * 0.8 + fo * 0.5;
				var surf = smoothstep(0.35, 0.62, foamy + front * 0.45 + zone * 0.25) * (0.45 + 0.55 * max(front, zone));
				froth = max(froth, surf * shoal);
				// Foam clings to the waterline.
				var edge = (1.0 - smoothstep(0.0, 0.04, depth)) * step(0.0, depth) * smoothstep(0.35, 0.65, fine + 0.2) * breakers;
				froth = clamp(max(froth, edge * (0.25 + 0.5 * exposed)), 0.0, 1.0);
				c = mix(c, vec3(0.95, 0.97, 1.0), froth);
				c += vec3(spec * (1.0 - froth));
			}
			if (ruled > 0.0) {
				// Short horizontal pen strokes, dense near the shore and fading out to sea,
				// like water drawn in an architect's site plan.
				var q = transformedPosition.xy;
				var yy = q.y / 0.5;
				var fw = max(fwidth(yy), 0.0001);
				var dl = abs(fract(yy) - 0.5);
				var line = 1.0 - smoothstep(fw * 0.5, fw * 1.4, dl);
				line *= 1.0 - smoothstep(0.18, 0.4, fw); // fade out before the strokes alias
				var row = floor(yy);
				var seg = floor(q.x / (1.6 + fract(row * 0.618) * 1.8) + row * 0.37);
				var dash = step(0.42, fract(sin(row * 12.9898 + seg * 78.233) * 43758.5453));
				var near = (1.0 - smoothstep(0.2, 4.5, depth)) * step(0.05, depth);
				c = mix(c, ruleInk, line * dash * near * ruled);
			}
			pixelColor.rgb = c;
			pixelColor.a = 1.0;
		}
	};

	public function new(amplitude = 0.04, shimmer = 0.018) {
		super();
		this.amplitude = amplitude;
		this.shimmer = shimmer;
		heightRange = 10.0;
		softness = 0;
		ruled = 0;
		waveTex = OceanWaves.texture();
		waves = 0.8;
		glint = 0.6;
		whitecap = 0.3;
		breakers = 1.0;
		sunDir.set(0.55, 0.35, 0.76);
		sunDir.normalize();
		TerrainStyle.setColor(ruleInk, Palette.SKETCH_LINE);
		setClassicColors();
		// Same elevation thresholds as the original shader (0.25 and 0.18).
		tShallow = -world.Island.classicHeight(0.25);
		tMid = -world.Island.classicHeight(0.18);
	}

	public function setClassicColors() {
		TerrainStyle.setColor(shallow, 0x87D1FA);
		TerrainStyle.setColor(mid, 0x4AABE8);
		TerrainStyle.setColor(deep, 0x2185C4);
	}

	/** Natural turquoise shallows to deep blue, with soft transitions. **/
	public function setPaintedColors() {
		TerrainStyle.setColor(shallow, 0x8FD3C6);
		TerrainStyle.setColor(mid, 0x3E9DB0);
		TerrainStyle.setColor(deep, 0x235F86);
	}

	/** Muted, nautical-chart tones for the ink style. **/
	public function setChartColors() {
		TerrainStyle.setColor(shallow, 0xC9E3E2);
		TerrainStyle.setColor(mid, 0x9CC6CF);
		TerrainStyle.setColor(deep, 0x6E9FB5);
	}

	/** Sketch: muted slate water, with ruled strokes along the shore. **/
	public function setSketchColors() {
		// Muted slate-green, deepening gently; the tone shader keeps a little of the hue.
		TerrainStyle.setColor(shallow, 0xC8CFC2);
		TerrainStyle.setColor(mid, 0xA3B2AC);
		TerrainStyle.setColor(deep, 0x84979A);
	}

	/**
		Bake the island into a texture the water (and the terrain's swash) can sample:
		R = height. G = exposure to the open-ocean swell: 1 for open water (deep
		water connected to the map edge), fading to 0 over ~14 m of shallows.
		That keeps breakers and swash on exposed shores and leaves lagoons and
		sheltered sandbars calm.
	**/
	public function setIsland(island:world.Island) {
		var w = island.size + 1;
		var hs = [for (j in 0...w) for (i in 0...w) island.heightAtVertex(i, j)];
		// Open ocean: deep water reachable from the map edge.
		var dist = [for (_ in 0...w * w) -1];
		var queue:Array<Int> = [];
		for (k in 0...w * w) {
			var i = k % w, j = Std.int(k / w);
			if ((i == 0 || j == 0 || i == w - 1 || j == w - 1) && hs[k] < -1.0) {
				dist[k] = 0;
				queue.push(k);
			}
		}
		var head = 0;
		while (head < queue.length) {
			var k = queue[head++];
			var i = k % w, j = Std.int(k / w);
			for (d in [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
				var ni = i + d[0], nj = j + d[1];
				if (ni < 0 || nj < 0 || ni >= w || nj >= w) continue;
				var nk = nj * w + ni;
				if (dist[nk] >= 0) continue;
				if (hs[nk] < -1.0) {
					dist[nk] = 0; // still open ocean
					queue.push(nk);
				} else if (hs[nk] < 0.4 && dist[k] < 40) {
					dist[nk] = dist[k] + 1; // shallows and beach, counting steps in from open water
					queue.push(nk);
				}
			}
		}
		var reach = 14.0 / island.cell;
		var px = hxd.Pixels.alloc(w, w, RGBA);
		for (j in 0...w)
			for (i in 0...w) {
				var k = j * w + i;
				var h = hs[k] / heightRange;
				if (h < -1) h = -1;
				if (h > 1) h = 1;
				var v = Std.int((h * 0.5 + 0.5) * 255 + 0.5);
				var e = dist[k] < 0 ? 0.0 : Math.max(0, 1 - dist[k] / reach);
				var ev = Std.int(e * 255 + 0.5);
				px.setPixel(i, j, 0xFF000000 | (v << 16) | (ev << 8) | v);
			}
		if (heightMap != null) heightMap.dispose();
		heightMap = h3d.mat.Texture.fromPixels(px);
		heightMap.filter = Linear;
		heightMap.wrap = Clamp;
		mapOrigin.set(-island.halfExtent, -island.halfExtent);
		mapSize = island.size * island.cell;
	}
}
