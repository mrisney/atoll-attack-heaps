package world;

enum IslandShape {
	/** One island, ported from the Flutter atoll-attack shader: fbm + 3 peaks + radial falloff. **/
	Single;
	/** Reef ring with islets around a lagoon. **/
	Atoll;
}

/**
	Procedural atoll heightfield. Pure data: no rendering here, so the same
	class can run in a headless server or a lockstep simulation.

	World units: Z is up, sea level is 0, the island is centered on the origin.
**/
class Island {
	public static inline var SEA_LEVEL = 0.0;
	/** Below this height a tile counts as water for movement. **/
	public static inline var WALKABLE_MIN = 0.12;

	public final seed:Int;
	/** Number of cells per side (vertices = size + 1). **/
	public final size:Int;
	public final cell:Float;
	public final heights:Array<Float>;
	public final shape:IslandShape;

	public var apexX(default, null) = 0.0;
	public var apexY(default, null) = 0.0;
	public var apexH(default, null) = -999.0;

	public var halfExtent(get, never):Float;

	inline function get_halfExtent()
		return size * cell * 0.5;

	public function new(seed:Int, shape:IslandShape = Single, size = 160, cell = 0.75) {
		this.seed = seed;
		this.shape = shape;
		this.size = size;
		this.cell = cell;
		heights = [for (_ in 0...(size + 1) * (size + 1)) 0.0];
		switch shape {
			case Single:
				generateClassic();
				smooth(1);
			case Atoll:
				generate();
				smooth(2);
		}
		roughenCoast();
	}

	/**
		Make the shoreline irregular. The generators give smooth, round coasts
		(the owner found them "a little too simple"). Domain-warped noise at
		two scales (coves and points ~10 m across, ragged bits ~3 m) is added
		only near sea level, so the hills and the deep sea don't change. Some
		low spots become tide pools and some shallows become sandbars or
		skerries. Deterministic (seeded Noise), so the sim stays lockstep-safe.
	**/
	function roughenCoast() {
		var w = size + 1;
		var big = new Noise(seed * 31 + 7), fine = new Noise(seed * 17 + 3), wn = new Noise(seed * 5 + 19);
		for (j in 0...w)
			for (i in 0...w) {
				var k = j * w + i;
				var h = heights[k];
				var near = Math.exp(-(h * h) / (1.4 * 1.4));
				if (near < 0.01) continue;
				var x = i * cell, y = j * cell;
				// Warp the lookup a little, so coves curl instead of looking like blobs.
				var ox = (wn.fbm(x / 14 + 3.1, y / 14 + 7.7, 2) - 0.5) * 9;
				var oy = (wn.fbm(x / 14 + 9.4, y / 14 + 1.3, 2) - 0.5) * 9;
				var d = (big.fbm((x + ox) / 10, (y + oy) / 10, 3) - 0.5) * 2.2
					+ (fine.fbm((x + ox) / 3.5, (y + oy) / 3.5, 2) - 0.5) * 1.0;
				heights[k] = h + d * near;
			}
	}

	// --- Classic: a port of atoll-attack's island_water.frag getElevation() ---------

	/** Height scale: elevation 0.32 (the shader's shoreline) maps to sea level. **/
	public static inline var CLASSIC_SHORE = 0.32;
	public static inline var CLASSIC_SCALE = 12.0;

	// Same defaults as the Flutter game (constants/game_config.dart).
	public var amplitude = 1.9;
	public var wavelength = 0.22;
	public var bias = -0.56;
	public var islandRadius = 1.11;

	function classicFbm(n:Noise, x:Float, y:Float):Float {
		// 5 octaves, each rotated 0.5 rad and shifted — exactly like the GLSL.
		var v = 0.0, a = 0.5;
		var c = Math.cos(0.5), s = Math.sin(0.5);
		for (_ in 0...5) {
			v += a * n.value(x, y);
			var nx = (c * x - s * y) * 2.0 + 100.0;
			var ny = (s * x + c * y) * 2.0 + 100.0;
			x = nx;
			y = ny;
			a *= 0.5;
		}
		return v;
	}

	static inline function peak(x:Float, y:Float, cx:Float, cy:Float, radius:Float, intensity:Float):Float {
		var dx = x - cx, dy = y - cy;
		var d = Math.sqrt(dx * dx + dy * dy) / radius;
		return intensity * Math.exp(-d * d);
	}

	/** The shader's 0..1 elevation at a normalized position (-1..1). **/
	public function classicElevation(nx:Float, ny:Float, n:Noise):{e:Float, raw:Float} {
		var sf = (seed % 1000) * 1.0;
		var so = sf * 0.01;
		var v = classicFbm(n, nx / wavelength + so, ny / wavelength + so);
		v = (v + 1.0) * 0.5;
		v = v * amplitude + bias;
		v += peak(nx, ny, 0.3 * Math.sin(sf + 1.3), 0.25 * Math.cos(sf + 2.7), 0.13, 0.12);
		v += peak(nx, ny, -0.26 * Math.cos(sf + 3.4), 0.12 * Math.sin(sf + 5.8), 0.10, 0.08);
		v += peak(nx, ny, 0.15 * Math.sin(sf + 4.1), -0.20 * Math.cos(sf + 2.3), 0.09, 0.06);
		var raw = v;
		if (v < 0) v = 0;
		if (v > 1) v = 1;
		var dist = Math.sqrt(nx * nx + ny * ny);
		var falloff = 1.0 - dist / islandRadius;
		if (falloff < 0) falloff = 0;
		if (falloff > 1) falloff = 1;
		return {e: v * falloff, raw: raw * falloff};
	}

	function generateClassic() {
		var n = new Noise(seed);
		var w = size + 1;
		for (j in 0...w)
			for (i in 0...w) {
				var nx = i / size * 2 - 1;
				var ny = j / size * 2 - 1;
				var el = classicElevation(nx, ny, n);
				// The 2D shader clamps elevation at 1, which would make a smooth cone in 3D.
				// Let a little of the unclamped noise through so the highlands have relief.
				var bulge = Math.max(0, el.raw - el.e) * 0.18;
				var h = (el.e + bulge - CLASSIC_SHORE) * CLASSIC_SCALE;
				heights[j * w + i] = h;
			}
	}

	/** Classic band thresholds converted from shader elevation to world height. **/
	public static inline function classicHeight(e:Float):Float
		return (e - CLASSIC_SHORE) * CLASSIC_SCALE;

	/** Box-blur passes to round off ridges (deterministic, Int-indexed). **/
	function smooth(passes:Int) {
		var w = size + 1;
		for (_ in 0...passes) {
			var src = heights.copy();
			for (j in 1...size)
				for (i in 1...size) {
					var sum = 0.0;
					for (dj in -1...2)
						for (di in -1...2)
							sum += src[(j + dj) * w + i + di];
					heights[j * w + i] = sum / 9;
				}
		}
		// Recompute the apex after smoothing.
		apexH = -999.0;
		for (j in 0...w)
			for (i in 0...w) {
				var h = heights[j * w + i];
				if (h > apexH) {
					apexH = h;
					apexX = i * cell - halfExtent;
					apexY = j * cell - halfExtent;
				}
			}
	}

	function generate() {
		var n = new Noise(seed);
		var warp = new Noise(seed * 7 + 13);

		var ringR = 0.56; // reef radius (normalized)
		var ringW = 0.14; // reef width
		// One raised peak on the ring: the "apex" you plant your flag on.
		var hillAng = n.rand(911, 37) * Math.PI * 2;
		var hillX = Math.cos(hillAng) * ringR, hillY = Math.sin(hillAng) * ringR;

		for (j in 0...size + 1)
			for (i in 0...size + 1) {
				var nx = i / size * 2 - 1;
				var ny = j / size * 2 - 1;
				var r = Math.sqrt(nx * nx + ny * ny);
				var ang = Math.atan2(ny, nx);
				var ca = Math.cos(ang), sa = Math.sin(ang);

				// Wobble the ring so it isn't a perfect circle.
				var rr = r
					+ (n.fbm(ca * 1.5 + 5, sa * 1.5 + 5, 3) - 0.5) * 0.24
					+ (warp.fbm(nx * 3, ny * 3, 2) - 0.5) * 0.08;

				var ring = Math.exp(-((rr - ringR) * (rr - ringR)) / (ringW * ringW));
				// Break the ring into islets and sandbars.
				var islets = smoothstep(0.38, 0.62, n.fbm(ca * 2.2 + 11, sa * 2.2 + 11, 3));
				var land = ring * (0.3 + 0.7 * islets);

				var dhx = nx - hillX, dhy = ny - hillY;
				var hill = Math.exp(-(dhx * dhx + dhy * dhy) / 0.01) * 3.2;

				var detail = n.fbm(nx * 4 + 20, ny * 4 + 20, 4);
				// Ocean floor outside, shallow lagoon inside.
				var base = lerp(-7.0, -1.4, smoothstep(ringR + 0.25, ringR - 0.08, rr));
				var h = base + land * (3.6 + detail * 2.6) + hill * ring;

				// Always open ocean at the map edge.
				h = lerp(h, -8.0, smoothstep(0.86, 1.0, r));

				heights[j * (size + 1) + i] = h;
				if (h > apexH) {
					apexH = h;
					apexX = i * cell - halfExtent;
					apexY = j * cell - halfExtent;
				}
			}
	}

	public inline function heightAtVertex(i:Int, j:Int):Float {
		if (i < 0) i = 0;
		if (j < 0) j = 0;
		if (i > size) i = size;
		if (j > size) j = size;
		return heights[j * (size + 1) + i];
	}

	/** Bilinear height at a world position. Outside the map returns deep water. **/
	public function heightAt(wx:Float, wy:Float):Float {
		var gx = (wx + halfExtent) / cell;
		var gy = (wy + halfExtent) / cell;
		if (gx < 0 || gy < 0 || gx > size || gy > size)
			return -8.0;
		var i = Std.int(gx), j = Std.int(gy);
		var fx = gx - i, fy = gy - j;
		var a = heightAtVertex(i, j), b = heightAtVertex(i + 1, j);
		var c = heightAtVertex(i, j + 1), d = heightAtVertex(i + 1, j + 1);
		return lerp(lerp(a, b, fx), lerp(c, d, fx), fy);
	}

	public inline function isWalkable(wx:Float, wy:Float):Bool {
		return heightAt(wx, wy) > WALKABLE_MIN;
	}

	/** Find a walkable spot near a preferred angle on the ring (for spawning). **/
	public function findLandNear(angle:Float, sweep = 0):{x:Float, y:Float} {
		var dx = Math.cos(angle), dy = Math.sin(angle);
		var best = {x: 0.0, y: 0.0};
		var bestH = -999.0;
		var steps = 200;
		for (k in 0...steps) {
			var t = k / steps * halfExtent;
			var x = dx * t, y = dy * t;
			var h = heightAt(x, y);
			// Prefer low beaches (good landing zones) on a real landmass, not a sandbar.
			if (h > 0.6 && h < 2.5 && h > bestH && landAround(x, y, 3.0) >= 7) {
				bestH = h;
				best = {x: x, y: y};
			}
		}
		if (bestH < -100) {
			// Nothing suitable on this bearing: sweep outward to neighbouring bearings,
			// and only as a last resort settle for the highest point.
			if (sweep < 12) return findLandNear(angle + (sweep % 2 == 0 ? 1 : -1) * (sweep + 1) * 0.12, sweep + 1);
			for (k in 0...steps) {
				var t = k / steps * halfExtent;
				var h = heightAt(dx * t, dy * t);
				if (h > bestH) {
					bestH = h;
					best = {x: dx * t, y: dy * t};
				}
			}
		}
		return best;
	}

	/** How many of 8 points on a circle around (x,y) are walkable. **/
	function landAround(x:Float, y:Float, radius:Float):Int {
		var n = 0;
		for (k in 0...8) {
			var a = k / 8 * Math.PI * 2;
			if (heightAt(x + Math.cos(a) * radius, y + Math.sin(a) * radius) > 0.3) n++;
		}
		return n;
	}

	public static inline function lerp(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;

	public static function smoothstep(e0:Float, e1:Float, x:Float):Float {
		var t = (x - e0) / (e1 - e0);
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		return t * t * (3 - 2 * t);
	}
}
