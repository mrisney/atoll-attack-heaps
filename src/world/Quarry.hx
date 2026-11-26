package world;

/**
	The summit: a granite dome sheared off on one side, like Yosemite's Half
	Dome, with the sheer face cut and fluted like the walls of the Yangshan
	Quarry (owner: "a more Yosemite Half Dome look, more irregular, but
	obviously very influenced by the visuals of Yangshan quarry"; a first,
	block-shaped version "looked like a structure").

	- The dome rises `RISE` metres over a cut-down floor, on an irregular,
	  roughly elliptical base, its flanks steepening to cliffs near the foot.
	- At the +u end it's sheared off: a vertical face, the dome's high side.
	- Each long flank (one facing each landing beach) has a gully climbing
	  diagonally into the rock from the back of the dome to the crown: the
	  only ways up. The flag stands on the crown, near the edge of the face.

	This is the simulation's half: it shapes the height map (the dome, the
	face, the gullies and a ragged floor round it), and anything too steep to
	stand on is a wall nobody can walk (`isWall`, by the slope of the height
	map itself), so NavGrid paths go up the gullies. `render/QuarryView`
	draws the rock over the same numbers. Local frame: `u` along the long
	axis, `v` across; the gullies are mirror images (v -> -v), so both sides
	climb the same way. Deterministic: plain arithmetic and seeded Noise.
**/
class Quarry {
	/** Semi-axes of the dome's base (m): along the long axis and across it. **/
	public static inline var L = 12.0;
	/** The front semi-axis (toward the face) is shorter: little is left beyond the cut. **/
	public static inline var L_FRONT = 7.5;
	public static inline var W = 9.0;
	/** Height of the crown above the floor (m). **/
	public static inline var RISE = 8.0;
	/** Where the dome is sheared off (u, before its wander). **/
	public static inline var CUT_U = 5.2;
	/** Gullies: half width (m), and where they start (outside the foot) and reach the crown, in (u, |v|). **/
	public static inline var GULLY_HALF = 2.0;
	public static inline var GULLY_AU = -9.5;
	public static inline var GULLY_AV = 9.6;
	public static inline var GULLY_BU = -1.0;
	public static inline var GULLY_BV = 3.6;
	/** Steeper than this (rise over run) is a wall. **/
	public static inline var MAX_SLOPE = 1.05;
	/** Level floor round the foot, then a ragged blend back to the hillside. **/
	public static inline var APRON = 2.0;
	public static inline var APRON_BLEND = 5.0;

	public final cx:Float;
	public final cy:Float;
	/** Direction of the long axis (radians). **/
	public final axis:Float;
	public final floor:Float;
	/** The crown: the highest ground, a few metres back from the face's edge (the flag goes here). **/
	public var top(default, null):Float;
	public var peakX(default, null):Float;
	public var peakY(default, null):Float;
	final ca:Float;
	final sa:Float;
	final noise:Noise;
	var island:Null<Island> = null;
	/** Height where each gully reaches the crown. **/
	final gullyTop:Float;

	/**
		`axis`: the long axis. On a single island the landing beaches lie at 45°
		and 225° (Sim.spawnTeam), so the flanks with their gullies face them,
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
		gullyTop = domeH(GULLY_BU, GULLY_BV);
		// Find the crown (sampled every half metre), keeping back from the face.
		top = -1e9;
		var u = -L;
		while (u < CUT_U) {
			var v = -W;
			while (v < W) {
				if (u < cutAt(v) - 3.0) {
					var h = rockH(u, v);
					if (!Math.isNaN(h) && h > top) {
						top = h;
						peakX = worldX(u, v);
						peakY = worldY(u, v);
					}
				}
				v += 0.5;
			}
			u += 0.5;
		}
	}

	/** Shape the island's height map (every vertex). **/
	public function carve(island:Island) {
		this.island = island;
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

	/** World position of local (u, v). **/
	public inline function worldX(u:Float, v:Float):Float
		return cx + u * ca - v * sa;

	public inline function worldY(u:Float, v:Float):Float
		return cy + u * sa + v * ca;

	/** How far the base's outline wanders, as a factor on its radius, by direction. **/
	/**
		The base outline (1 = the plain ellipse): a polygon, straight runs
		between irregular corners, plus a little noise. Smooth noise alone
		made round lobes that bulged at the foot like a gourd's (owner: "more
		jagged"); straight runs turn the flanks into broad faces meeting at
		ridges. Corners stay near 1 so few are concave (a deep concave
		corner pinched the flank into two round cheeks).
	**/
	public function outlineAt(theta:Float):Float {
		var k = CORNERS;
		inline function ang(j:Int):Float
			return (j + (noise.value(((j % k) + k) % k * 7.31 + 0.5, 1.9) - 0.5) * 0.7) / k * Math.PI * 2;
		inline function rad(j:Int):Float
			return 0.9 + noise.value(((j % k) + k) % k * 5.17 + 0.5, 3.7) * 0.22;
		var a = theta / (Math.PI * 2);
		a -= Math.floor(a);
		var t = a * Math.PI * 2;
		// The segment whose corners straddle t.
		var i = Math.floor(a * k) - 1;
		while (ang(i + 1) <= t) i++;
		while (ang(i) > t) i--;
		var a0 = ang(i), a1 = ang(i + 1), r0 = rad(i), r1 = rad(i + 1);
		var p0x = Math.cos(a0) * r0, p0y = Math.sin(a0) * r0;
		var ex = Math.cos(a1) * r1 - p0x, ey = Math.sin(a1) * r1 - p0y;
		var dx = Math.cos(t), dy = Math.sin(t);
		var den = dx * ey - dy * ex;
		var r = Math.abs(den) < 1e-9 ? r0 : (p0x * ey - p0y * ex) / den;
		return r + (noise.fbm(Math.cos(theta) * 3.1 + 5, Math.sin(theta) * 3.1 + 9, 2) - 0.5) * 0.06;
	}

	static inline var CORNERS = 9;

	/** Normalised distance from the centre (1 = the foot), irregular outline. **/
	public function radius(u:Float, v:Float):Float {
		var nu = u / (u > 0 ? L_FRONT : L), nv = v / W;
		return Math.sqrt(nu * nu + nv * nv) / outlineAt(Math.atan2(nv, nu));
	}

	/** The dome's profile: flat-ish crown, steepening to a cliff at the foot. **/
	public function profile(r:Float):Float {
		if (r >= 1) return floor;
		var r4 = r * r * r * r;
		return floor + RISE * Math.sqrt(1 - r4);
	}

	/**
		The dome's height at (u, v): the profile, leaning up toward the face
		(Half Dome is highest at its sheer edge and rolls down behind), with
		broad swells and hollows so it isn't a smooth bun.
	**/
	public function shapeH(u:Float, v:Float):Float {
		var r = radius(u, v);
		if (r >= 1) return floor;
		var lean = 0.72 + 0.28 * Math.max(0, Math.min(1, (u / L + 1) / 1.45));
		var swell = (noise.fbm(u * 0.11 + 21, v * 0.11 + 13, 3) - 0.5) * 2.4 * (1 - r * r);
		return floor + (profile(r) - floor) * lean + swell;
	}

	/** Where the sheer face stands (u), wandering a little across it. **/
	public function cutAt(v:Float):Float
		return CUT_U + (noise.fbm(v * 0.17 + 3, 1.7, 2) - 0.5) * 1.6;

	/** The dome alone (with the face cut), ignoring the gullies. **/
	public function domeH(u:Float, v:Float):Float {
		if (u > cutAt(v)) return floor;
		return shapeH(u, v);
	}

	/** The gully nearest (u, v): along-ness t (0 at the foot, 1 at the crown) and distance across. **/
	public function gully(u:Float, v:Float):{t:Float, across:Float, half:Float} {
		var av = Math.abs(v);
		var dx = GULLY_BU - GULLY_AU, dy = GULLY_BV - GULLY_AV;
		var len2 = dx * dx + dy * dy;
		var t = ((u - GULLY_AU) * dx + (av - GULLY_AV) * dy) / len2;
		var px = GULLY_AU + dx * t, py = GULLY_AV + dy * t;
		var across = Math.sqrt((u - px) * (u - px) + (av - py) * (av - py));
		// It widens and narrows a little along its length.
		var half = GULLY_HALF + (noise.value(t * 4 + (v < 0 ? 30 : 0), 7) - 0.5) * 0.7;
		return {t: t, across: across, half: half};
	}

	public function gullyH(t:Float):Float
		return floor + (gullyTop - floor) * (t < 0 ? 0 : t > 1 ? 1 : t);

	/** The rock's height at local (u, v), or NaN off it (then it's floor and apron). **/
	public function rockH(u:Float, v:Float):Float {
		var g = gully(u, v);
		if (g.t > -0.05 && g.t < 1 && g.across < g.half) return gullyH(g.t);
		var r = radius(u, v);
		if (r >= 1 || u > cutAt(v)) return Math.NaN;
		return shapeH(u, v);
	}

	/** Metres outside the foot (roughly; negative inside). **/
	function outside(u:Float, v:Float):Float
		return (radius(u, v) - 1) * W;

	/** The ground's height at (x, y), given the hillside's own height there. **/
	public function heightOver(x:Float, y:Float, orig:Float):Float {
		var u = localU(x, y), v = localV(x, y);
		var h = rockH(u, v);
		if (!Math.isNaN(h)) return h;
		// The floor round the foot (and under the face), blending back to the
		// hillside with a ragged edge rather than a neat pad.
		var e = Math.max(0, outside(u, v));
		var t = (e - APRON - (noise.fbm(x * 0.09 + 17, y * 0.09 + 3, 3) - 0.5) * 5) / APRON_BLEND;
		t = t < 0 ? 0 : t > 1 ? 1 : t;
		t = t * t * (3 - 2 * t);
		return floor + (orig - floor) * t;
	}

	/** Near the rock or its floor, plus a margin (props and grass keep off). **/
	public function covers(x:Float, y:Float, margin:Float):Bool {
		var u = localU(x, y), v = localV(x, y);
		if (outside(u, v) < margin) return true;
		var g = gully(u, v);
		return g.t > -0.2 && g.t < 1.1 && g.across < g.half + margin;
	}

	/** Loose rock fallen from the dome: how likely a boulder is here (0 = none). **/
	public function talus(x:Float, y:Float):Float {
		var u = localU(x, y), v = localV(x, y);
		var e = outside(u, v);
		if (e < 0.6 || e > 4.0) return 0;
		var g = gully(u, v);
		if (g.t > -0.5 && g.t < 1.1 && g.across < g.half + 2.0) return 0; // keep the way up clear
		return noise.fbm(x * 0.3 + 61, y * 0.3 + 23, 2) * (1 - e / 4.0);
	}

	/**
		Too steep to stand on: the face, the dome's lower flanks, the gullies'
		sides. Read from the height map's own slope, so the sim's walls are
		exactly where the ground is steep. The floor's gentle blend never is.
	**/
	public function isWall(x:Float, y:Float):Bool {
		if (island == null) return false;
		var u = localU(x, y), v = localV(x, y);
		if (outside(u, v) > 2.0) return false;
		var h = island.heightAt(x, y);
		if (h < floor + 0.4) return false;
		var s = 0.5;
		var hx0 = island.heightAt(x - s, y), hx1 = island.heightAt(x + s, y);
		var hy0 = island.heightAt(x, y - s), hy1 = island.heightAt(x, y + s);
		var gx = (hx1 - hx0) / (2 * s), gy = (hy1 - hy0) / (2 * s);
		if (gx * gx + gy * gy <= MAX_SLOPE * MAX_SLOPE) return false;
		// Only a real drop: a knee-high step at a gully's mouth is just a step
		// (thin pockets of "wall" there trapped units walking between them).
		var hi = Math.max(Math.max(hx0, hx1), Math.max(hy0, hy1)), lo = Math.min(Math.min(hx0, hx1), Math.min(hy0, hy1));
		return hi - lo > 0.9;
	}

	/** On the dome's upper part (where archers see further). **/
	public function onTop(x:Float, y:Float):Bool
		return island != null && island.heightAt(x, y) > floor + RISE * 0.6;
}
