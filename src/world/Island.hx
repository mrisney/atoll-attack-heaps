package world;

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

	public var apexX(default, null) = 0.0;
	public var apexY(default, null) = 0.0;
	public var apexH(default, null) = -999.0;

	public var halfExtent(get, never):Float;

	inline function get_halfExtent()
		return size * cell * 0.5;

	public function new(seed:Int, size = 96, cell = 1.25) {
		this.seed = seed;
		this.size = size;
		this.cell = cell;
		heights = [for (_ in 0...(size + 1) * (size + 1)) 0.0];
		generate();
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
	public function findLandNear(angle:Float):{x:Float, y:Float} {
		var dx = Math.cos(angle), dy = Math.sin(angle);
		var best = {x: 0.0, y: 0.0};
		var bestH = -999.0;
		var steps = 200;
		for (k in 0...steps) {
			var t = k / steps * halfExtent;
			var x = dx * t, y = dy * t;
			var h = heightAt(x, y);
			// Prefer low beaches (good landing zones) over peaks.
			if (h > WALKABLE_MIN + 0.3 && h < 2.5 && h > bestH) {
				bestH = h;
				best = {x: x, y: y};
			}
		}
		if (bestH < -100) {
			// Fall back to the highest point along that bearing.
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

	public static inline function lerp(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;

	public static function smoothstep(e0:Float, e1:Float, x:Float):Float {
		var t = (x - e0) / (e1 - e0);
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		return t * t * (3 - 2 * t);
	}
}
