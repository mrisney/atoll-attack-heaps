package render;

import h3d.col.Point;
import world.Quarry;

/**
	Draws the summit's half dome (world/Quarry holds its shape and the sim's
	walls; this only draws the rock). Half Dome's form, Yangshan's surfaces:

	- the dome: a polar sheet from the crown to the foot over the same
	  irregular outline as the sim, its flanks fluted with vertical chisel
	  marks and streaked dark where water runs, faint curved exfoliation
	  shells on its shoulders, the crown pale and weathered with lichen;
	- the face: wherever the sheet runs past the cut it's folded down onto it,
	  which makes a sheer wall from the rock's own heights; fluted and lumpy
	  like the Yangshan walls, with long dark stains;
	- the gullies: cut into the flanks, floored with rough stone;
	- granite grain (render/Granite: crystal speckle and a slow mottle at
	  unrelated scales; the shared rock texture's crack network repeated
	  "like a peanut shell"), real fissures as thin dark ribbons laid on the
	  surface (branching cracks on the crown, curved sheeting joints on the
	  shoulders), and a few tufts of grass rooted in the cracks.

	The sheet sits a little outside the sim's outline (and the face a little
	in front of the cut), so the height map's smeared steps (0.75 m cells)
	stay hidden inside the stone. Lit, shadowed, inked and toned like the
	rest of the island (built before IslandView applies the Sketch tone).
**/
class QuarryView {
	static inline var MAX_VERTS = 60000;
	/** The drawn rock stands this much proud of the sim's (m). **/
	static inline var PROUD = 0.8;

	final q:Quarry;
	final noise:world.Noise;
	final pts:Array<Point> = [];
	final nrm:Array<Point> = [];
	final col:Array<Point> = [];
	final idx:Array<Int> = [];
	final chunks:Array<h3d.prim.Polygon> = [];

	final seed:Int;

	public function new(q:Quarry, seed:Int) {
		this.q = q;
		this.seed = seed;
		noise = new world.Noise(seed + 717);
	}

	public static function build(island:world.Island, parent:h3d.scene.Object):Array<h3d.mat.Material> {
		if (island.quarry == null) return [];
		var v = new QuarryView(island.quarry, island.seed);
		v.dome();
		v.fissures();
		var mats = v.finish(parent);
		v.tufts(parent);
		return mats;
	}

	/** Chisel flutes and lumps on a steep face, metres outward, by (along, up). **/
	function relief(s:Float, z:Float):Float {
		var flute = Math.sin(s * Math.PI * 2 / 0.45 + noise.value(s * 0.5, z * 0.25) * 5) * 0.06;
		var lumps = (noise.fbm(s * 0.3 + 11, z * 0.3 + 7, 3) - 0.5) * 0.45;
		return flute + lumps;
	}

	/**
		Stone colour: pale and weathered on the crown, streaked where it's steep
		(dark runs from above, uneven), curved exfoliation shells on the
		shoulders, damp near the foot, rough in the gullies.
	**/
	function stone(u:Float, v:Float, z:Float, steep:Float, s:Float, inGully:Bool):Point {
		var up = (z - q.floor) / Quarry.RISE;
		var base = mixColor(Palette.QUARRY_TOP, Palette.QUARRY, smooth(0.2, 0.8, steep));
		var streak = smooth(0.5, 0.72, noise.fbm(s * 0.6 + 31, 0.5, 3)) * smooth(0.3, 0.9, steep) * (0.4 + 0.6 * up);
		var c = mixColor(base, Palette.QUARRY_STAIN, streak * 0.85);
		// Exfoliation: thin darker shells following the dome's shape.
		var shell = Math.abs(Math.sin((up * 9 + noise.value(u * 0.15, v * 0.15) * 2.5) * Math.PI));
		var shellLine = (1 - smooth(0.0, 0.12, shell)) * smooth(0.1, 0.5, steep) * (1 - smooth(0.85, 1.0, steep)) * 0.22;
		var lichen = smooth(0.6, 0.8, noise.fbm(u * 0.4 + 70, v * 0.4 + 70, 3)) * (1 - steep) * 0.35;
		c = mixColor(c, Palette.QUARRY_LICHEN, lichen);
		var shade = 0.96 + (noise.fbm(u * 0.9 + 3, v * 0.9 + z * 0.5 + 5, 2) - 0.5) * 0.3;
		// Broad weathering: some sheets fresher and paler, some older and darker.
		shade *= 1 + (noise.fbm(u * 0.18 + 90, v * 0.18 + z * 0.1 + 40, 3) - 0.5) * 0.4;
		var damp = 1 - 0.22 * (1 - smooth(0.0, 0.25, up));
		// The gullies are the way up: worn paler by feet, so they read as paths.
		if (inGully) c = mixColor(c, Palette.TRACK_DUST, 0.45);
		return colour(c, shade * damp * (1 - shellLine));
	}

	function dome() {
		var nTheta = 220;
		// Rings: dense near the foot, where the flank turns to cliff.
		var rings:Array<Float> = [];
		var k = 0.0;
		while (k <= 1.0001) {
			rings.push(1 - Math.pow(1 - k, 1.8));
			k += 1 / 34;
		}
		rings.push(1.0); // the foot
		rings.push(1.0); // tucked below the floor (skirt)
		var nr = rings.length;
		var grid:Array<Array<Point>> = [];
		var colours:Array<Array<Point>> = [];
		for (ti in 0...nTheta) {
			var th = ti / nTheta * Math.PI * 2;
			var wob = q.outlineAt(Math.atan2(Math.sin(th), Math.cos(th)));
			var c = [], cc = [];
			for (ri in 0...nr) {
				var r = rings[ri];
				var skirt = ri == nr - 1;
				// Local position over the irregular outline, a little proud of the sim's.
				var grow = 1 + PROUD / Quarry.W;
				var u = Math.cos(th) * r * wob * (Math.cos(th) > 0 ? Quarry.L_FRONT : Quarry.L) * grow;
				var v = Math.sin(th) * r * wob * Quarry.W * grow;
				// Height from the sim's own rock (at the matching, un-grown spot).
				var su = u / grow, sv = v / grow;
				var z = r >= 0.9999 ? q.floor : q.shapeH(su, sv);
				var g = q.gully(su, sv);
				var inGully = g.t > -0.05 && g.t < 1 && g.across < g.half + 0.3;
				if (inGully) z = Math.min(z, q.gullyH(g.t) + 0.04);
				if (ri >= nr - 2) z = q.floor - (skirt ? 0.4 : 0.0);
				// The face: run past the cut and you're folded down onto it.
				var cut = q.cutAt(sv) + PROUD;
				var onFace = u > cut;
				if (onFace) u = cut;
				// Steepness here (0 flat .. 1 sheer): the profile's slope, or the face.
				var slope = onFace ? 1.0 : Math.min(1, Math.abs(q.profile(Math.min(r + 0.02, 0.9999)) - q.profile(Math.max(r - 0.02, 0))) / (0.04 * Quarry.W) / 2.5);
				// Chisel flutes belong to the cut face; the dome's flanks are smoother
				// (sheeted granite), just lumpy.
				var fluted = onFace ? 1.0 : 0.25;
				if (inGully && !onFace) slope = 0.15;
				// Flutes and lumps where it's steep: pushed outward (along u on the face).
				var s = onFace ? sv : th * Quarry.W * 1.2;
				var rel = (relief(s, z) - Math.sin(s * Math.PI * 2 / 0.45 + noise.value(s * 0.5, z * 0.25) * 5) * 0.06 * (1 - fluted)) * slope;
				if (!onFace) {
					// Exfoliation sheets: the flanks step out in shells, ledge over ledge,
					// rather than hanging in soft folds (half the lumps, plus the steps).
					var sh = (z - q.floor) / 1.3 + noise.fbm(th * 1.7 + 5, z * 0.08, 2) * 1.6;
					var step = sh - Math.floor(sh);
					rel = rel * 0.5 + (step * step) * 0.28 * smooth(0.15, 0.6, slope);
				}
				if (onFace) u += rel + 0.05;
				else if (!skirt) {
					var nx = Math.cos(th), ny = Math.sin(th) * Quarry.L / Quarry.W;
					var nl = Math.sqrt(nx * nx + ny * ny);
					u += nx / nl * rel;
					v += ny / nl * rel;
				}
				// Bumps on the crown (only upward: the sim's ground is the floor of it).
				if (!onFace && slope < 0.5) z += Math.abs(noise.fbm(u * 0.3 + 41, v * 0.3 + 9, 3) - 0.5) * 0.35 * (1 - slope * 2);
				c.push(new Point(q.worldX(u, v), q.worldY(u, v), z));
				cc.push(stone(u, v, z, slope, s, inGully));
			}
			grid.push(c);
			colours.push(cc);
		}
		sheet(grid, colours, true, true);
	}

	// --- fissures and tufts -------------------------------------------------------

	static var rngState = 1;

	static inline function rnd():Float {
		rngState = (rngState * 1103515 + 12345) & 0x7fffffff;
		return rngState / 0x7fffffff;
	}

	/**
		The drawn surface at local (u, v) (the grown frame dome() uses): its
		height and steepness, or null off the open rock (face, gullies, foot).
	**/
	function surfaceAt(u:Float, v:Float):Null<{z:Float, slope:Float}> {
		var grow = 1 + PROUD / Quarry.W;
		var su = u / grow, sv = v / grow;
		var r = q.radius(su, sv);
		if (r >= 0.95 || u > q.cutAt(sv) + PROUD - 0.4) return null;
		var g = q.gully(su, sv);
		if (g.t > -0.1 && g.t < 1.05 && g.across < g.half + 0.6) return null;
		var slope = Math.min(1, Math.abs(q.profile(Math.min(r + 0.02, 0.9999)) - q.profile(Math.max(r - 0.02, 0))) / (0.04 * Quarry.W) / 2.5);
		var z = q.shapeH(su, sv);
		if (slope < 0.5) z += Math.abs(noise.fbm(u * 0.3 + 41, v * 0.3 + 9, 3) - 0.5) * 0.35 * (1 - slope * 2);
		return {z: z, slope: slope};
	}

	final crackPts:Array<{u:Float, v:Float}> = [];

	/** One crack: a wandering line from (u, v), heading `dir`, laid on the rock as a thin dark ribbon. **/
	function crack(u:Float, v:Float, dir:Float, len:Float, width:Float, maxSlope:Float, turn:Float, depth:Int) {
		var path:Array<{u:Float, v:Float, z:Float}> = [];
		var step = 0.2, d = 0.0;
		while (d < len) {
			var s = surfaceAt(u, v);
			if (s == null || s.slope > maxSlope) break;
			path.push({u: u, v: v, z: s.z});
			if (rnd() < 0.15) crackPts.push({u: u, v: v});
			// Branches: shorter, finer, splaying off.
			if (depth < 2 && rnd() < 0.05) crack(u, v, dir + (rnd() < 0.5 ? 1 : -1) * (0.5 + rnd() * 0.7), len * 0.45, width * 0.65, maxSlope, turn, depth + 1);
			dir += (rnd() - 0.5) * turn;
			u += Math.cos(dir) * step;
			v += Math.sin(dir) * step;
			d += step;
		}
		if (path.length < 3) return;
		var n = path.length;
		var grid = [], cols = [];
		for (i in 0...n) {
			var a = path[i == 0 ? 0 : i - 1], b = path[i == n - 1 ? n - 1 : i + 1];
			var du = b.u - a.u, dv = b.v - a.v;
			var l = Math.max(Math.sqrt(du * du + dv * dv), 1e-4);
			// Widest in the middle, closing to a hairline at the ends, a little uneven.
			var t = i / (n - 1);
			var w = width * Math.sin(Math.PI * t) * (0.7 + 0.6 * noise.value(i * 0.4 + depth * 9, 3)) * 0.5 + 0.004;
			var p = path[i];
			var su = -dv / l * w, sv = du / l * w;
			grid.push([
				new Point(q.worldX(p.u + su, p.v + sv), q.worldY(p.u + su, p.v + sv), p.z + 0.035),
				new Point(q.worldX(p.u, p.v), q.worldY(p.u, p.v), p.z + 0.025),
				new Point(q.worldX(p.u - su, p.v - sv), q.worldY(p.u - su, p.v - sv), p.z + 0.035)
			]);
			cols.push([colour(Palette.QUARRY_CRACK, 1.25), colour(Palette.QUARRY_CRACK, 0.8), colour(Palette.QUARRY_CRACK, 1.25)]);
		}
		sheet(grid, cols, false, true);
	}

	function fissures() {
		rngState = q.cx < 0 ? 4711 : 4713;
		var lf = Quarry.L_FRONT, lb = Quarry.L, w = Quarry.W;
		// Joints across the crown: long, gently wandering, branching.
		for (k in 0...9) {
			var u = -lb * 0.55 + rnd() * (lb * 0.55 + lf * 0.5), v = (rnd() - 0.5) * w * 1.1;
			crack(u, v, rnd() * Math.PI * 2, 3 + rnd() * 5, 0.06 + rnd() * 0.05, 0.55, 0.35, 0);
		}
		// Sheeting joints on the shoulders: curving round the dome, roughly level.
		for (k in 0...8) {
			var th = rnd() * Math.PI * 2;
			var r = 0.62 + rnd() * 0.18;
			var u = Math.cos(th) * r * (Math.cos(th) > 0 ? lf : lb), v = Math.sin(th) * r * w;
			crack(u, v, th + Math.PI / 2, 2 + rnd() * 4, 0.05 + rnd() * 0.04, 0.85, 0.15, 1);
		}
		// Short hairline cracks scattered about.
		for (k in 0...22) {
			var u = -lb * 0.7 + rnd() * (lb * 0.7 + lf * 0.6), v = (rnd() - 0.5) * w * 1.4;
			crack(u, v, rnd() * Math.PI * 2, 0.6 + rnd() * 1.4, 0.03 + rnd() * 0.02, 0.7, 0.6, 2);
		}
	}

	/** A few tufts of grass rooted in the cracks: not many (owner: "a few grass shoots"). **/
	function tufts(parent:h3d.scene.Object) {
		var tp:Array<Point> = [], tn:Array<Point> = [], tc:Array<Point> = [];
		var count = 0;
		var k = 0;
		while (count < 11 && k < crackPts.length) {
			var c = crackPts[(k * 7) % crackPts.length];
			k++;
			if (rnd() > 0.5) continue;
			var s = surfaceAt(c.u, c.v);
			if (s == null || s.slope > 0.5) continue;
			count++;
			var blades = 5 + Std.int(rnd() * 5);
			var dry = rnd() < 0.4;
			for (b in 0...blades) {
				var a = rnd() * Math.PI * 2;
				var bu = c.u + Math.cos(a) * 0.05, bv = c.v + Math.sin(a) * 0.05;
				var h = 0.14 + rnd() * 0.26;
				// Lean outward from the clump and a little downwind.
				var lu = Math.cos(a) * h * 0.4 + 0.05, lv = Math.sin(a) * h * 0.4;
				var wu = -Math.sin(a) * 0.012, wv = Math.cos(a) * 0.012;
				var z = s.z + 0.02;
				tp.push(new Point(q.worldX(bu + wu, bv + wv), q.worldY(bu + wu, bv + wv), z));
				tp.push(new Point(q.worldX(bu - wu, bv - wv), q.worldY(bu - wu, bv - wv), z));
				tp.push(new Point(q.worldX(bu + lu, bv + lv), q.worldY(bu + lu, bv + lv), z + h));
				for (_ in 0...3) tn.push(new Point(0, 0, 1));
				var base = colour(Palette.GRASS_BLADE_BASE, 1.0), tip = colour(dry ? Palette.GRASS_BLADE_DRY : Palette.GRASS_BLADE_TIP, 1.0);
				tc.push(base);
				tc.push(base);
				tc.push(tip);
			}
		}
		if (tp.length == 0) return;
		var ib = new hxd.IndexBuffer();
		for (i in 0...tp.length) ib.push(i);
		var p = new h3d.prim.Polygon(tp, ib);
		p.normals = tn;
		p.colors = tc;
		var m = new h3d.scene.Mesh(p, parent);
		FlatMeshBuilder.setupMaterial(m.material, true);
		m.material.mainPass.culling = None;
	}

	// --- mesh plumbing -----------------------------------------------------------

	/**
		A grid of points (columns × rows) as triangles with smooth normals.
		`wrap` joins the last column to the first. `flip` turns the faces round.
	**/
	function sheet(grid:Array<Array<Point>>, colours:Array<Array<Point>>, wrap:Bool, flip = false) {
		var nc = grid.length, nr = grid[0].length;
		if (pts.length + nc * nr > MAX_VERTS) flush();
		var base = pts.length;
		for (ci in 0...nc)
			for (ri in 0...nr) {
				var p = grid[ci][ri];
				var cn = wrap ? (ci + 1) % nc : Std.int(Math.min(ci + 1, nc - 1));
				var cp = wrap ? (ci + nc - 1) % nc : Std.int(Math.max(ci - 1, 0));
				var rn = Std.int(Math.min(ri + 1, nr - 1)), rp = Std.int(Math.max(ri - 1, 0));
				var du = grid[cn][ri].sub(grid[cp][ri]);
				var dv = grid[ci][rn].sub(grid[ci][rp]);
				var n = du.cross(dv);
				if (flip) n = new Point(-n.x, -n.y, -n.z);
				// A degenerate spot (the crown's centre, folded face): face up.
				if (n.lengthSq() < 1e-10) n = new Point(0, 0, 1);
				n.normalize();
				pts.push(p);
				nrm.push(n);
				col.push(colours[ci][ri]);
			}
		var last = wrap ? nc : nc - 1;
		for (ci in 0...last)
			for (ri in 0...nr - 1) {
				var a = base + ci * nr + ri, b = base + ((ci + 1) % nc) * nr + ri;
				var c = a + 1, d = b + 1;
				if (flip) {
					idx.push(a); idx.push(c); idx.push(b);
					idx.push(b); idx.push(c); idx.push(d);
				} else {
					idx.push(a); idx.push(b); idx.push(c);
					idx.push(b); idx.push(d); idx.push(c);
				}
			}
	}

	function flush() {
		if (pts.length == 0) return;
		var ib = new hxd.IndexBuffer();
		for (k in idx) ib.push(k);
		var p = new h3d.prim.Polygon(pts.copy(), ib);
		p.normals = nrm.copy();
		p.colors = col.copy();
		chunks.push(p);
		pts.resize(0);
		nrm.resize(0);
		col.resize(0);
		idx.resize(0);
	}

	function finish(parent:h3d.scene.Object):Array<h3d.mat.Material> {
		flush();
		var granite = Granite.get();
		var half = Quarry.L * 1.45 + PROUD;
		var weather = Granite.paintWeather(q, seed, 448, half);
		var mats = [];
		for (p in chunks) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			m.material.mainPass.culling = None;
			var sh = new Granite.GraniteShader();
			sh.grain = granite.grain;
			sh.mottle = granite.mottle;
			sh.weather = weather;
			sh.weatherOrigin.set(q.cx - half, q.cy - half);
			sh.weatherSize = half * 2;
			m.material.mainPass.addShader(sh);
			FlatMeshBuilder.shadows(m.material, true, true);
			mats.push(m.material);
		}
		return mats;
	}

	static inline function colour(c:Int, shade:Float):Point
		return new Point(Palette.r(c) * shade, Palette.g(c) * shade, Palette.b(c) * shade);

	static function mixColor(a:Int, b:Int, t:Float):Int {
		t = t < 0 ? 0 : t > 1 ? 1 : t;
		inline function ch(x:Int, y:Int)
			return Std.int(x + (y - x) * t);
		return (ch(a >> 16 & 255, b >> 16 & 255) << 16) | (ch(a >> 8 & 255, b >> 8 & 255) << 8) | ch(a & 255, b & 255);
	}

	static inline function smooth(e0:Float, e1:Float, x:Float):Float {
		var t = (x - e0) / (e1 - e0);
		t = t < 0 ? 0 : t > 1 ? 1 : t;
		return t * t * (3 - 2 * t);
	}
}
