package render;

/**
	Granite for the summit's dome (render/QuarryView). The owner found the
	dome too patterned with the shared rock texture: its painted crack
	network repeats every couple of metres and read "like a peanut shell".

	Granite is grain, not cracks: a fine speckle of crystals (dark biotite,
	white quartz, a few warm feldspars) over grey, and a slow mottle of
	lighter and darker patches. Two textures painted in code, both tileable
	(speckles wrap round the edges), sampled triplanar at two unrelated
	scales (`GraniteShader`) so neither repeat lines up with the other. The
	big cracks are real geometry (QuarryView's fissures), not texture.
**/
class Granite {
	static var cached:Null<Granite> = null;

	public final grain:h3d.mat.Texture;
	public final mottle:h3d.mat.Texture;

	public static function get():Granite {
		if (cached == null) cached = new Granite();
		return cached;
	}

	function new() {
		grain = paintGrain(256);
		mottle = paintMottle(128);
	}

	/** A little LCG: repeatable, render-side only (never used by the sim). **/
	static var state = 1;

	static inline function rnd():Float {
		state = (state * 1103515 + 12345) & 0x7fffffff;
		return state / 0x7fffffff;
	}

	static function toTexture(n:Int, buf:Array<Float>):h3d.mat.Texture {
		var px = hxd.Pixels.alloc(n, n, RGBA);
		inline function b(v:Float)
			return v < 0 ? 0 : (v > 1 ? 255 : Std.int(v * 255));
		for (y in 0...n)
			for (x in 0...n) {
				var i = (y * n + x) * 3;
				px.setPixel(x, y, (255 << 24) | (b(buf[i]) << 16) | (b(buf[i + 1]) << 8) | b(buf[i + 2]));
			}
		var t = new h3d.mat.Texture(n, n, [MipMapped]);
		t.uploadPixels(px);
		t.wrap = Repeat;
		t.filter = Linear;
		t.mipMap = Linear;
		return t;
	}

	/** Stamp a soft disc of colour, wrapping round the edges (so the tile repeats seamlessly). **/
	static function stamp(buf:Array<Float>, n:Int, cx:Float, cy:Float, r:Float, c:Array<Float>, a:Float) {
		var ri = Std.int(Math.ceil(r + 1));
		for (dy in -ri...ri + 1)
			for (dx in -ri...ri + 1) {
				var d = Math.sqrt(dx * dx + dy * dy) / r;
				if (d > 1) continue;
				var w = a * (1 - d * d);
				var x = ((Std.int(cx) + dx) % n + n) % n, y = ((Std.int(cy) + dy) % n + n) % n;
				var i = (y * n + x) * 3;
				for (k in 0...3) buf[i + k] += (c[k] - buf[i + k]) * w;
			}
	}

	static function paintGrain(n:Int):h3d.mat.Texture {
		state = 9157;
		var buf = [];
		// Grey ground mass with a per-pixel grain.
		for (_ in 0...n * n) {
			var g = 0.6 + (rnd() - 0.5) * 0.08;
			buf.push(g);
			buf.push(g * 0.995);
			buf.push(g * 0.985);
		}
		// Crystals: many small dark flecks, fewer white and warm ones, some clustered.
		for (_ in 0...2600) stamp(buf, n, rnd() * n, rnd() * n, 0.7 + rnd() * 1.3, [0.2, 0.2, 0.21], 0.85);
		for (_ in 0...1500) stamp(buf, n, rnd() * n, rnd() * n, 0.8 + rnd() * 1.8, [0.86, 0.85, 0.82], 0.7);
		for (_ in 0...260) stamp(buf, n, rnd() * n, rnd() * n, 1.0 + rnd() * 2.0, [0.74, 0.64, 0.58], 0.55);
		return toTexture(n, buf);
	}

	/**
		The dome's weathering and fine relief, baked once per island over its
		footprint in world xy (`GraniteShader.weather`).

		The owner pointed at a mountain viewer that looks real because it drapes
		satellite photos over real elevation data: the light and the dirt in the
		picture come from the ground itself. We can't use those photos (and the
		viewer has no licence), so this bakes the same kind of picture from the
		dome's own shape:

		- fine relief: the rock's height plus eroded, ridged micro-relief, with
		  drainage channels carved where water collects (D8 flow accumulation);
		- shading from that relief under the game's fixed sun, relative to the
		  mesh's own (so the mesh lights the big shape and this adds the small),
		  and cavity darkening in hollows: stored in alpha;
		- the stain, in RGB: dark streaks along the real drainage lines (Stone
		  Mountain's streaks follow the water), lichen crust where it's damp,
		  paler fresh sheets, weathering pits on the crown.

		On the sheer face the xy projection smears each texel straight down: fine
		for the stains (streaks), so the shader fades the relief shading out on
		steep surfaces instead.
	**/
	public static function paintWeather(q:world.Quarry, seed:Int, n:Int, half:Float):h3d.mat.Texture {
		var nz = new world.Noise(seed + 909);
		state = 7001 + seed % 1000;
		var d = half * 2 / n;
		var count = n * n;
		inline function smooth(e0:Float, e1:Float, x:Float):Float {
			var t = (x - e0) / (e1 - e0);
			t = t < 0 ? 0 : t > 1 ? 1 : t;
			return t * t * (3 - 2 * t);
		}
		inline function ridge(f:Float):Float
			return 1 - Math.abs(f * 2 - 1);
		// The rock is read 0.8 m grown, where the drawn sheet stands.
		var grow = 1 + 0.8 / world.Quarry.W;
		var base = new haxe.ds.Vector<Float>(count);
		var h = new haxe.ds.Vector<Float>(count);
		var rock = new haxe.ds.Vector<Bool>(count);
		var wx = new haxe.ds.Vector<Float>(count), wy = new haxe.ds.Vector<Float>(count);
		for (j in 0...n)
			for (i in 0...n) {
				var k = j * n + i;
				var x = q.cx - half + (i + 0.5) * d, y = q.cy - half + (j + 0.5) * d;
				wx[k] = x;
				wy[k] = y;
				// Read the rock where the drawn sheet is (it stands a little proud of
				// the sim's outline), so the map's edge meets the mesh's foot.
				var u = q.localU(x, y) / grow, v = q.localV(x, y) / grow;
				var rh = q.rockH(u, v);
				rock[k] = !Math.isNaN(rh);
				var b = rock[k] ? rh : q.floor;
				base[k] = b;
				if (!rock[k]) {
					h[k] = b;
					continue;
				}
				// Eroded micro-relief: ridged noise over a warped domain (so the ridges
				// meander like weathered rock, not a regular texture), fading at the foot.
				var ox = (nz.fbm(x * 0.2 + 71, y * 0.2 + 3, 2) - 0.5) * 3, oy = (nz.fbm(x * 0.2 + 9, y * 0.2 + 55, 2) - 0.5) * 3;
				var m = (ridge(nz.fbm((x + ox) * 0.33, (y + oy) * 0.33, 3)) - 0.5) * 0.22
					+ (ridge(nz.fbm((x + ox) * 1.05 + 9, (y + oy) * 1.05, 2)) - 0.5) * 0.12
					+ (nz.value(x * 3.1 + 2, y * 3.1) - 0.5) * 0.04;
				var r = q.radius(u, v);
				h[k] = b + m * (1 - Math.pow(Math.min(r, 1), 8));
			}

		// Joints: a few long, wandering grooves cut into the relief (not drawn
		// lines: drawn ribbons looked "very artificial"). The baked light shades
		// their sides and the drainage runs along them, so they read softly.
		var groove = new haxe.ds.Vector<Float>(count);
		for (k in 0...count) groove[k] = 0;
		inline function carveAt(fx:Float, fy:Float, depth:Float, width:Float) {
			var rr = Std.int(Math.ceil(width * 2 / d));
			var ci = Std.int(fx / d), cj = Std.int(fy / d);
			for (dj in -rr...rr + 1)
				for (di in -rr...rr + 1) {
					var ii = ci + di, jj = cj + dj;
					if (ii < 0 || jj < 0 || ii >= n || jj >= n) continue;
					var kk = jj * n + ii;
					if (!rock[kk]) continue;
					var dx = (ii + 0.5) * d - fx, dy = (jj + 0.5) * d - fy;
					var e = Math.sqrt(dx * dx + dy * dy) / width;
					// The deepest cut wins (the walk overlaps itself step to step).
					if (e < 2) groove[kk] = Math.max(groove[kk], depth * Math.exp(-e * e * 1.5));
				}
		}
		for (jn in 0...9) {
			var u = (rnd() - 0.6) * world.Quarry.L * 1.3, v = (rnd() - 0.5) * world.Quarry.W * 1.4;
			var dir = rnd() * Math.PI * 2, len = 3 + rnd() * 7, t = 0.0;
			var depth = 0.05 + rnd() * 0.06;
			while (t < len) {
				var x = q.worldX(u * grow, v * grow), y = q.worldY(u * grow, v * grow);
				if (Math.isNaN(q.rockH(u, v))) break;
				// Deep in the middle, closing at the ends.
				var f = Math.sin(Math.PI * t / len);
				carveAt(x - (q.cx - half), y - (q.cy - half), depth * f, 0.05 + 0.05 * f);
				dir += (rnd() - 0.5) * 0.3;
				u += Math.cos(dir) * d * 0.8;
				v += Math.sin(dir) * d * 0.8;
				t += d * 0.8;
			}
		}

		for (k in 0...count) h[k] -= groove[k];

		// Where water goes: each cell drains to its lowest neighbour, highest first.
		var order = [for (k in 0...count) if (rock[k]) k];
		order.sort((a, b) -> h[b] > h[a] ? 1 : (h[b] < h[a] ? -1 : 0));
		var acc = new haxe.ds.Vector<Float>(count);
		for (k in 0...count) acc[k] = 1;
		// Shared between all the lower neighbours by how steeply each one drops
		// (multiple flow directions): one-way (D8) drainage made ruler-straight,
		// zigzagging lines that read as scratches.
		var nbr = [-1, -1, 0, -1, 1, -1, -1, 0, 1, 0, -1, 1, 0, 1, 1, 1];
		var wts = [for (_ in 0...8) 0.0];
		for (k in order) {
			var i = k % n, j = Std.int(k / n);
			var sum = 0.0;
			for (m in 0...8) {
				wts[m] = 0;
				var ii = i + nbr[m * 2], jj = j + nbr[m * 2 + 1];
				if (ii < 0 || jj < 0 || ii >= n || jj >= n) continue;
				var drop = (h[k] - h[jj * n + ii]) / ((nbr[m * 2] != 0 && nbr[m * 2 + 1] != 0) ? 1.414 : 1);
				if (drop <= 0) continue;
				wts[m] = Math.pow(drop, 1.6);
				sum += wts[m];
			}
			if (sum <= 0) continue;
			for (m in 0...8)
				if (wts[m] > 0) acc[(j + nbr[m * 2 + 1]) * n + i + nbr[m * 2]] += acc[k] * wts[m] / sum;
		}
		// Carve the channels a little.
		for (k in order) h[k] -= Math.min(0.06, 0.006 * Math.sqrt(acc[k] - 1));

		// Hollows: height against a blurred copy (two box blurs, ~0.6 m).
		var blur = new haxe.ds.Vector<Float>(count), tmp = new haxe.ds.Vector<Float>(count);
		for (k in 0...count) blur[k] = h[k];
		var rad = Std.int(Math.max(2, 0.6 / d));
		for (pass in 0...2) {
			for (j in 0...n) {
				var sum = 0.0;
				for (i in -rad...rad + 1) sum += blur[j * n + (i < 0 ? 0 : i >= n ? n - 1 : i)];
				for (i in 0...n) {
					tmp[j * n + i] = sum / (rad * 2 + 1);
					var a = i - rad, b = i + rad + 1;
					sum += blur[j * n + (b >= n ? n - 1 : b)] - blur[j * n + (a < 0 ? 0 : a)];
				}
			}
			for (i in 0...n) {
				var sum = 0.0;
				for (j in -rad...rad + 1) sum += tmp[(j < 0 ? 0 : j >= n ? n - 1 : j) * n + i];
				for (j in 0...n) {
					blur[j * n + i] = sum / (rad * 2 + 1);
					var a = j - rad, b = j + rad + 1;
					sum += tmp[(b >= n ? n - 1 : b) * n + i] - tmp[(a < 0 ? 0 : a) * n + i];
				}
			}
		}

		var sun = render.TerrainStyle.SUN;
		var sl = Math.sqrt(sun.x * sun.x + sun.y * sun.y + sun.z * sun.z);
		var sx = sun.x / sl, sy = sun.y / sl, sz = sun.z / sl;
		var rgb = [for (_ in 0...count * 3) 1.0];
		var shade = new haxe.ds.Vector<Float>(count);
		var accLog = Math.log(1 + 900);
		for (j in 0...n)
			for (i in 0...n) {
				var k = j * n + i;
				shade[k] = 1;
				if (!rock[k]) continue;
				var x = wx[k], y = wy[k];
				var il = i > 0 ? k - 1 : k, ir = i < n - 1 ? k + 1 : k, jd = j > 0 ? k - n : k, ju = j < n - 1 ? k + n : k;
				var span = d * 2;
				// Fine and coarse normals.
				var fx = -(h[ir] - h[il]) / span, fy = -(h[ju] - h[jd]) / span;
				var fl = Math.sqrt(fx * fx + fy * fy + 1);
				var cx = -(base[ir] - base[il]) / span, cy = -(base[ju] - base[jd]) / span;
				var cl = Math.sqrt(cx * cx + cy * cy + 1);
				var lf = Math.max(0.05, (fx * sx + fy * sy + sz) / fl) * 0.8 + 0.2;
				var lc = Math.max(0.05, (cx * sx + cy * sy + sz) / cl) * 0.8 + 0.2;
				var cavity = (h[k] - blur[k]) * 2.2;
				cavity = cavity < -0.45 ? -0.45 : cavity > 0.25 ? 0.25 : cavity;
				// Soft shadows the fine relief casts in this sun (march toward it over
				// the baked heights), and how much sky each spot sees (horizon angles
				// in eight directions): the baked light that makes webgl-mountains'
				// scenery look real, done here from the rock's own heights.
				var lit = 1.0;
				var t = d * 1.5;
				var hx = sx / Math.sqrt(sx * sx + sy * sy), hy = sy / Math.sqrt(sx * sx + sy * sy);
				var tanSun = sz / Math.sqrt(sx * sx + sy * sy);
				while (t < 5) {
					var ii = Std.int(i + hx * t / d), jj = Std.int(j + hy * t / d);
					if (ii < 0 || jj < 0 || ii >= n || jj >= n) break;
					var over = h[jj * n + ii] - (h[k] + t * tanSun);
					if (over > 0) lit = Math.min(lit, 1 - Math.min(1, over / 0.15));
					t += d * 1.5;
				}
				var sky = 0.0;
				for (m in 0...8) {
					var ddx = nbr[m * 2], ddy = nbr[m * 2 + 1];
					var dl = Math.sqrt(ddx * ddx + ddy * ddy);
					var maxTan = 0.0;
					for (dist in [0.3, 0.9, 2.2]) {
						var ii = Std.int(i + ddx / dl * dist / d), jj = Std.int(j + ddy / dl * dist / d);
						if (ii < 0 || jj < 0 || ii >= n || jj >= n) continue;
						// Relative to the smooth surface, so the dome's own curve doesn't count.
						var rise = (h[jj * n + ii] - base[jj * n + ii]) - (h[k] - base[k]);
						maxTan = Math.max(maxTan, rise / dist);
					}
					sky += 1 - Math.min(1, maxTan * 1.5);
				}
				sky /= 8;
				var direct = lf / lc * (0.35 + 0.65 * lit);
				var s = (direct * 0.75 + sky * 0.25 + 0.0) * (1 + cavity);
				shade[k] = s < 0.3 ? 0.3 : s > 1.7 ? 1.7 : s;

				var steep = 1 - 1 / cl;
				var wet = Math.min(1, Math.log(acc[k]) / accLog);
				var c = 1.0, cr = 1.0, cb = 1.0;
				// Streaks along the drainage, darker where it runs steeply.
				var streak = smooth(0.35, 0.85, wet) * (0.3 + 0.7 * smooth(0.1, 0.6, steep));
				c *= 1 - streak * 0.42;
				cb *= 1 - streak * 0.06;
				// Lichen crust: big ragged patches, mostly where it stays damp.
				var crust = smooth(0.49, 0.53, nz.fbm(x * 0.075 + 3, y * 0.075 + 7, 4) + (nz.fbm(x * 0.9, y * 0.9, 2) - 0.5) * 0.12);
				crust *= 0.45 + 0.55 * smooth(0.05, 0.35, wet);
				c *= 1 - crust * 0.36;
				cr *= 1 + crust * 0.03;
				cb *= 1 - crust * 0.1;
				// Freshly peeled sheets: paler, clean, on the dry ribs.
				var fresh = smooth(0.6, 0.66, nz.fbm(x * 0.21 + 50, y * 0.21 + 20, 3)) * (1 - crust) * (1 - wet);
				c *= 1 + fresh * 0.18;
				rgb[k * 3] = c * cr;
				rgb[k * 3 + 1] = c;
				rgb[k * 3 + 2] = c * cb;
			}
		// Weathering pits on the crown: shallow pale hollows with a dark rim.
		var px = n / (half * 2);
		for (_ in 0...26) {
			var u = (rnd() - 0.6) * world.Quarry.L * 1.1, v = (rnd() - 0.5) * world.Quarry.W * 1.1;
			if (q.radius(u, v) > 0.6) continue;
			var cx = (q.worldX(u, v) - q.cx + half) * px, cy = (q.worldY(u, v) - q.cy + half) * px;
			var rd = (0.25 + rnd() * 0.6) * px;
			stamp(rgb, n, cx, cy, rd * 1.25, [0.62, 0.6, 0.57], 0.6);
			stamp(rgb, n, cx, cy, rd, [1.12, 1.12, 1.1], 0.8);
		}
		var pxs = hxd.Pixels.alloc(n, n, RGBA);
		inline function b(v:Float)
			return v < 0 ? 0 : (v > 1 ? 255 : Std.int(v * 255));
		// Stored halved, so the paler-than-plain parts fit (the shader doubles it).
		for (j in 0...n)
			for (i in 0...n) {
				var k = j * n + i, p = k * 3;
				pxs.setPixel(i, j, (b(shade[k] * 0.5) << 24) | (b(rgb[p] * 0.5) << 16) | (b(rgb[p + 1] * 0.5) << 8) | b(rgb[p + 2] * 0.5));
			}
		var t = new h3d.mat.Texture(n, n, [MipMapped]);
		t.uploadPixels(pxs);
		t.wrap = Clamp;
		t.filter = Linear;
		t.mipMap = Linear;
		return t;
	}

	static function paintMottle(n:Int):h3d.mat.Texture {
		state = 3301;
		var buf = [for (_ in 0...n * n * 3) 0.6];
		// Big soft patches, a little lighter or darker, a little warmer or cooler.
		for (_ in 0...140) {
			var v = 0.6 + (rnd() - 0.5) * 0.34;
			var warm = (rnd() - 0.5) * 0.03;
			stamp(buf, n, rnd() * n, rnd() * n, 6 + rnd() * 16, [v + warm, v, v - warm], 0.35);
		}
		return toTexture(n, buf);
	}
}

/**
	Triplanar granite: fine crystal grain times a slow mottle, multiplied
	into the vertex colour (which carries the streaks, lichen and shading).
**/
class GraniteShader extends hxsl.Shader {
	static var SRC = {
		@param var grain:Sampler2D;
		@param var mottle:Sampler2D;
		/** Metres per tile of grain and of mottle (unrelated, so they never line up). **/
		@param var grainScale:Float;
		@param var mottleScale:Float;
		@param var strength:Float;
		/** The dome's weathering (paintWeather), over world xy: origin and size. **/
		@param var weather:Sampler2D;
		@param var weatherOrigin:Vec2;
		@param var weatherSize:Float;
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;

		function fragment() {
			var n = abs(normalize(transformedNormal));
			var w = n * n * n * n;
			w /= (w.x + w.y + w.z);
			var p = transformedPosition / grainScale;
			var g = grain.get(p.yz).rgb * w.x + grain.get(p.xz).rgb * w.y + grain.get(p.xy).rgb * w.z;
			var q = transformedPosition / mottleScale;
			var m = mottle.get(q.yz).rgb * w.x + mottle.get(q.xz).rgb * w.y + mottle.get(q.xy).rgb * w.z;
			// Both average about 0.6: normalise so the vertex tint stays the tint.
			pixelColor.rgb *= mix(vec3(1.0), g * m * 2.78, strength);
			var wt = weather.get((transformedPosition.xy - weatherOrigin) / weatherSize);
			pixelColor.rgb *= wt.rgb * 2.0;
			// The baked fine-relief shading, only where the surface faces up (on the
			// sheer face the top-down map smears).
			var up = smoothstep(0.35, 0.75, normalize(transformedNormal).z);
			// Light through a colour ramp, as webgl-mountains does with its lightmaps:
			// shade cools toward sky blue, sunlit ribs warm a touch.
			var sh = wt.a * 2.0;
			var tint = mix(vec3(0.8, 0.86, 1.0), vec3(1.04, 1.0, 0.93), smoothstep(0.55, 1.15, sh));
			pixelColor.rgb *= mix(vec3(1.0), tint * sh, up);
		}
	};

	public function new() {
		super();
		grainScale = 1.37;
		mottleScale = 11.3;
		strength = 0.9;
	}
}
