package world;

/**
	The summit is a quarried monolith, after the Yangshan Quarry near Nanjing
	(owner: "could we incorporate visual aspects of the quarry into the high
	point... something the characters could walk or climb to the top and
	plant a flag, like Northgard"). A huge block left standing in the cut
	bedrock: sheer, chisel-fluted walls, a flat top with the flag on it, and
	a cut-stone ramp up each long side, one facing each landing beach. Round
	it the hilltop is cut down to a level quarry floor.

	This is the simulation's half (no rendering here): it shapes the height
	map, so the top, the ramps and the floor are real ground, and it says
	where the walls are, which nobody can walk on (`isWall`), so the only
	way up is a ramp. `render/QuarryView` draws it over the same numbers.

	Local frame: `u` along the block's long axis, `v` across it. The layout is
	symmetric under a half turn ((u, v) -> (-u, -v)), so both sides get the
	same climb. All deterministic (plain arithmetic on the island's heights).
**/
class Quarry {
	/** Half length and half width of the block (m), and its corner radius. **/
	public static inline var L = 8.0;
	public static inline var W = 4.0;
	public static inline var CORNER = 1.6;
	/** How far the outline wanders in and out of a true rounded rectangle (m). **/
	public static inline var WOBBLE = 0.55;
	/** How high the walls stand above the quarry floor (m). **/
	public static inline var RISE = 6.5;
	/** A ramp's walkable width (m). **/
	public static inline var RAMP_W = 3.0;
	/** Where a ramp reaches the top (u): the last stretch is a landing at the top's height. **/
	public static inline var RAMP_TOP_U = L - 4.5;
	/**
		Wall bands. The height map steps from the top down to the floor over
		[-HEIGHT_IN, 0] past an edge; the drawn wall leans out to WALL_OUT, so
		the terrain's slope stays hidden inside the stone (the map's 0.75 m
		cells smear any step that wide). Nobody walks within BLOCK_IN inside
		or BLOCK_OUT outside an edge.
	**/
	public static inline var HEIGHT_IN = 0.75;
	public static inline var WALL_OUT = 0.85;
	public static inline var BLOCK_IN = 1.0;
	public static inline var BLOCK_OUT = 1.3;
	/** The ramp runs beside the block, beyond its wall band. **/
	public static inline var RAMP_V0 = W + BLOCK_OUT;
	public static inline var RAMP_V1 = RAMP_V0 + RAMP_W;
	/** Level floor round the structure, then a blend back to the hillside. **/
	public static inline var APRON = 2.0;
	public static inline var APRON_BLEND = 5.0;

	public final cx:Float;
	public final cy:Float;
	/** Direction of the long axis (radians). **/
	public final axis:Float;
	public final floor:Float;
	public final top:Float;
	final ca:Float;
	final sa:Float;
	final noise:Noise;

	/**
		`axis`: the long axis. On a single island the landing beaches lie at 45°
		and 225° (Sim.spawnTeam), so the long sides, and their ramps, face them
		with the axis on the other diagonal; on an atoll it runs along the reef.
	**/
	public function new(cx:Float, cy:Float, groundH:Float, axis:Float, seed:Int) {
		noise = new Noise(seed + 4242);
		this.cx = cx;
		this.cy = cy;
		this.axis = axis;
		ca = Math.cos(axis);
		sa = Math.sin(axis);
		floor = groundH - 0.6;
		top = floor + RISE;
	}

	/** Shape the island's height map (every vertex). **/
	public function carve(island:Island) {
		var w = island.size + 1, he = island.halfExtent;
		for (j in 0...w)
			for (i in 0...w) {
				var x = i * island.cell - he, y = j * island.cell - he;
				var k = j * w + i;
				island.heights[k] = heightOver(x, y, island.heights[k]);
			}
	}

	public inline function localU(x:Float, y:Float):Float
		return (x - cx) * ca + (y - cy) * sa;

	public inline function localV(x:Float, y:Float):Float
		return -(x - cx) * sa + (y - cy) * ca;

	/** Signed distance to the block's rounded outline (negative inside). **/
	public static function blockSdf(u:Float, v:Float):Float {
		var qx = Math.abs(u) - (L - CORNER), qy = Math.abs(v) - (W - CORNER);
		var ox = Math.max(qx, 0), oy = Math.max(qy, 0);
		return Math.sqrt(ox * ox + oy * oy) + Math.min(Math.max(qx, qy), 0) - CORNER;
	}

	/**
		The block isn't a perfect box (owner: "slightly more irregular"): its
		outline bulges and dips by up to WOBBLE, from smooth noise along the
		walls. Not mirrored between the two sides: a few tens of centimetres
		of wall don't change the fight, and the ramps stay exactly symmetric.
	**/
	public function wobble(u:Float, v:Float):Float
		return (noise.fbm(u * 0.16 + 5.3, v * 0.16 + 9.1, 3) - 0.5) * 2 * WOBBLE;

	/** Signed distance to the block's actual (irregular) outline, local coordinates. **/
	public function sdf(u:Float, v:Float):Float
		return blockSdf(u, v) - wobble(u, v);

	/** The ramp's height at u (floor at the low end, top at the landing). **/
	public function rampH(u:Float):Float {
		var f = (u + L) / (RAMP_TOP_U + L);
		f = f < 0 ? 0 : f > 1 ? 1 : f;
		return floor + (top - floor) * f;
	}

	/** Signed distance to the whole footprint (block and both ramps), as a box. **/
	static function footprintSdf(u:Float, v:Float):Float {
		var qx = Math.abs(u) - (L + WALL_OUT + WOBBLE), qy = Math.abs(v) - (RAMP_V1 + WALL_OUT);
		var ox = Math.max(qx, 0), oy = Math.max(qy, 0);
		return Math.sqrt(ox * ox + oy * oy) + Math.min(Math.max(qx, qy), 0);
	}

	/** Inside the footprint plus a margin (props and grass keep off). **/
	public function covers(x:Float, y:Float, margin:Float):Bool
		return footprintSdf(localU(x, y), localV(x, y)) < margin;

	/** Ground height under the ramp at (u, v >= 0), or the floor off it. **/
	function besideH(u:Float, v:Float):Float {
		// Off the long side (beyond the block's ends) it's just the floor.
		if (u < -L - 0.5 || u > L + HEIGHT_IN || v < W - CORNER) return floor;
		var h = rampH(u);
		// The landing's end face (u past L) and the outer side drop to the floor.
		if (u > L) h = lerp(h, floor, (u - L) / HEIGHT_IN);
		if (v > RAMP_V1) h = lerp(h, floor, Math.min(1, (v - RAMP_V1) / HEIGHT_IN));
		return h;
	}

	/** The ground's height at (x, y), given the hillside's own height there. **/
	public function heightOver(x:Float, y:Float, orig:Float):Float {
		var u = localU(x, y), v = localV(x, y);
		var fs = footprintSdf(u, v);
		if (fs > 0) {
			// The quarry floor round it, blending back to the hillside, its edge
			// ragged rather than a neat rounded pad.
			var t = (fs - APRON - (noise.fbm(x * 0.09 + 17, y * 0.09 + 3, 3) - 0.5) * 5) / APRON_BLEND;
			t = t < 0 ? 0 : t > 1 ? 1 : t;
			t = t * t * (3 - 2 * t);
			return lerp(floor, orig, t);
		}
		// The block's own (irregular) outline, read where the point really is.
		var d = sdf(u, v);
		if (v < 0) {
			// Half-turn symmetry for the ramps: the other side is the same, rotated.
			u = -u;
			v = -v;
		}
		var outside = besideH(u, v);
		if (d <= -HEIGHT_IN) return top;
		if (d >= 0) return outside;
		// The step from the top down to whatever is beside the block.
		return lerp(top, outside, (d + HEIGHT_IN) / HEIGHT_IN);
	}

	/** Where the ramp's landing opens onto the top (u range, on the long side). **/
	static inline function inOpening(u:Float):Bool
		return u > RAMP_TOP_U + 0.3 && u < L - CORNER - 0.3;

	/** A wall: nobody stands or walks here (the only ways up are the ramps). **/
	public function isWall(x:Float, y:Float):Bool {
		var u = localU(x, y), v = localV(x, y);
		if (footprintSdf(u, v) > BLOCK_OUT) return false;
		var d = sdf(u, v);
		if (v < 0) {
			u = -u;
			v = -v;
		}
		if (d > -BLOCK_IN && d < BLOCK_OUT) {
			// The landing joins the top through a gap in the long wall.
			var longSide = Math.abs(u) < L - CORNER && v > 0;
			if (!(longSide && inOpening(u))) return true;
		}
		// The ramp's outer side and its end face, wherever they're a drop.
		var onRampU = u > -L - 0.5 && u < L + BLOCK_OUT;
		if (onRampU && v > RAMP_V1 - 0.3 && v < RAMP_V1 + BLOCK_OUT && rampH(u) - floor > 0.8) return true;
		if (v > RAMP_V0 - 0.5 && v < RAMP_V1 + BLOCK_OUT && u > L - 0.3 && u < L + BLOCK_OUT) return true;
		return false;
	}

	/** On the block's top (where archers see further). **/
	public function onTop(x:Float, y:Float):Bool
		return sdf(localU(x, y), localV(x, y)) < -BLOCK_IN + 0.2;

	static inline function lerp(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;
}
