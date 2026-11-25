package render;

import h3d.col.Point;
import world.Quarry;

/**
	Draws the quarried monolith on the summit (world/Quarry holds its shape
	and the sim's walls; this only draws it). After the photos of the
	Yangshan Quarry the owner shared:

	- sheer walls with a slight batter, covered in vertical chisel flutes,
	  lumpy where the stone resisted, with dark weathering streaks running
	  down from the top;
	- a weathered, rounded top edge and a flat top (the flag stands on it);
	- the foot of the walls undercut into dark slots between square stone
	  posts, as where the masons began cutting the block free;
	- a cut ramp up each long side, scored across for footing, with the same
	  fluted outer face.

	The walls stand a little outside where the height map steps down, so the
	terrain's smeared slope stays hidden inside the stone. Lit, shadowed,
	inked and toned like the rest of the island (built before IslandView
	applies the Sketch tone: it's stone, not timber).
**/
class QuarryView {
	static inline var MAX_VERTS = 60000;

	final q:Quarry;
	final noise:world.Noise;
	final pts:Array<Point> = [];
	final nrm:Array<Point> = [];
	final col:Array<Point> = [];
	final idx:Array<Int> = [];
	final chunks:Array<h3d.prim.Polygon> = [];

	public function new(q:Quarry, seed:Int) {
		this.q = q;
		noise = new world.Noise(seed + 717);
	}

	public static function build(island:world.Island, parent:h3d.scene.Object):Array<h3d.mat.Material> {
		if (island.quarry == null) return [];
		var v = new QuarryView(island.quarry, island.seed);
		v.block();
		for (side in [1.0, -1.0]) v.ramp(side);
		return v.finish(parent);
	}

	// --- the block ---------------------------------------------------------------

	/** Columns round the outline: where they sit at offset 0, their outward normal, and arc length. **/
	function outline():Array<{u:Float, v:Float, nu:Float, nv:Float, s:Float, arcCentre:Bool}> {
		var a = Quarry.L - Quarry.CORNER, b = Quarry.W - Quarry.CORNER, c = Quarry.CORNER;
		var cols = [];
		var s = 0.0;
		inline function straight(u0:Float, v0:Float, u1:Float, v1:Float, nu:Float, nv:Float) {
			var len = Math.sqrt((u1 - u0) * (u1 - u0) + (v1 - v0) * (v1 - v0));
			var n = Std.int(Math.ceil(len / 0.3));
			for (k in 0...n) {
				var t = k / n;
				cols.push({u: u0 + (u1 - u0) * t, v: v0 + (v1 - v0) * t, nu: nu, nv: nv, s: s + len * t, arcCentre: false});
			}
			s += len;
		}
		inline function arc(cu:Float, cv:Float, a0:Float) {
			var n = 8;
			for (k in 0...n) {
				var ang = a0 + Math.PI / 2 * k / n;
				// Stored at the corner's centre; the offset adds CORNER + o along the normal.
				cols.push({u: cu, v: cv, nu: Math.cos(ang), nv: Math.sin(ang), s: s + c * Math.PI / 2 * k / n, arcCentre: true});
			}
			s += c * Math.PI / 2;
		}
		// Counter-clockwise from the +u end.
		straight(a + c, -b, a + c, b, 1, 0);
		arc(a, b, 0);
		straight(a, b + c, -a, b + c, 0, 1);
		arc(-a, b, Math.PI / 2);
		straight(-a - c, b, -a - c, -b, -1, 0);
		arc(-a, -b, Math.PI);
		straight(-a, -b - c, a, -b - c, 0, -1);
		arc(a, -b, Math.PI * 1.5);
		return cols;
	}

	/** World position of a local (u, v) point. **/
	inline function world(u:Float, v:Float, z:Float):Point {
		var ca = Math.cos(q.axis), sa = Math.sin(q.axis);
		return new Point(q.cx + u * ca - v * sa, q.cy + u * sa + v * ca, z);
	}

	/** Chisel flutes and lumps on a wall, metres outward, by (along, up). **/
	function relief(s:Float, z:Float):Float {
		var flute = Math.sin(s * Math.PI * 2 / 0.42 + noise.value(s * 0.6, z * 0.3) * 4) * 0.07;
		var lumps = (noise.fbm(s * 0.35 + 11, z * 0.35 + 7, 3) - 0.5) * 0.32;
		return flute + lumps;
	}

	/** Stone colour on a wall: weathering streaks from the top, damp near the foot. **/
	function wallColor(s:Float, z:Float, slot:Bool):Point {
		if (slot) return colour(Palette.QUARRY_SLOT, 1.0);
		var up = (z - q.floor) / Quarry.RISE;
		// Dark streaks run down from the top where water has run (narrow, uneven).
		var streak = smooth(0.52, 0.7, noise.fbm(s * 0.75 + 31, 0.5, 3)) * (0.45 + 0.55 * up);
		var shade = 1.02 + (noise.fbm(s * 0.9 + 3, z * 0.9 + 5, 2) - 0.5) * 0.3;
		var damp = 1 - 0.22 * (1 - smooth(0.0, 0.3, up));
		var c = mixColor(Palette.QUARRY, Palette.QUARRY_STAIN, streak * 0.85);
		return colour(c, shade * damp);
	}

	function block() {
		var cols = outline();
		var top = q.top, fl = q.floor;
		var ncol = cols.length;
		var grid:Array<Array<Point>> = [];
		var colours:Array<Array<Point>> = [];
		for (ci in 0...ncol) {
			var c = cols[ci];
			// The outline's own wander (the sim's walls follow the same number).
			var bu = c.u + (c.arcCentre ? c.nu * Quarry.CORNER : 0), bv = c.v + (c.arcCentre ? c.nv * Quarry.CORNER : 0);
			var wob = q.wobble(bu, bv);
			// Weathering varies along the wall: how much it leans, how round and how
			// far down the top edge has worn.
			var lean = 0.06 + noise.fbm(c.s * 0.12 + 50, 3, 2) * 0.22;
			var round = 0.3 + noise.fbm(c.s * 0.2 + 60, 7, 2) * 0.7;
			// Square posts every 2.8 m along the foot; between them, dark slots.
			var post = (c.s % 2.8) < 0.9;
			// Where a ramp's landing joins the top, the edge is flat (you step across it).
			var lu = c.u, side = c.nv;
			var opening = !c.arcCentre && Math.abs(side) > 0.5 && (side > 0 ? lu : -lu) > Quarry.RAMP_TOP_U + 0.1 && (side > 0 ? lu : -lu) < Quarry.L - Quarry.CORNER - 0.1;
			// The profile, bottom to top: (offset from the outline, height, slot?).
			var prof:Array<{o:Float, z:Float, slot:Bool}> = [];
			var o0 = Quarry.WALL_OUT + 0.04;
			prof.push({o: o0 + 0.06, z: fl - 0.4, slot: false});
			prof.push({o: o0, z: fl - 0.02, slot: true});
			prof.push({o: o0, z: fl + 1.05, slot: true});
			prof.push({o: o0, z: fl + 1.25, slot: false});
			var bodyTop = top - round;
			var bodyRows = 12;
			for (k in 1...bodyRows + 1) {
				var t = k / bodyRows;
				prof.push({o: o0 - lean * t, z: fl + 1.25 + (bodyTop - fl - 1.25) * t, slot: false});
			}
			for (k in 1...5) {
				var a = Math.PI / 2 * k / 4;
				prof.push({o: o0 - lean - round + Math.cos(a) * round, z: bodyTop + Math.sin(a) * round, slot: false});
			}
			var rows = prof.length;
			var colPts = [], colCols = [];
			for (ri in 0...rows) {
				var p = prof[ri];
				var o = p.o;
				var slot = p.slot && !post;
				if (slot) o -= 0.55;
				var z = p.z;
				if (opening && ri >= rows - 4) z = top + 0.02;
				var r = (ri == 0 || ri >= rows - 4) ? relief(c.s, z) * 0.3 : relief(c.s, z);
				var off = (c.arcCentre ? Quarry.CORNER : 0) + o + r + wob;
				colPts.push(world(c.u + c.nu * off, c.v + c.nv * off, z));
				colCols.push(wallColor(c.s, z, slot));
			}
			grid.push(colPts);
			colours.push(colCols);
		}
		sheet(grid, colours, true);
		cap(cols);
	}

	/** The flat top: rings stepping in from the rounded edge, fanned to the middle. **/
	function cap(cols:Array<{u:Float, v:Float, nu:Float, nv:Float, s:Float, arcCentre:Bool}>) {
		var top = q.top + 0.02;
		var offsets = [99.0, 0.0, -0.8, -1.8, -2.8, -3.6]; // 99: meet the wall's rounded edge
		var rings:Array<Array<Point>> = [];
		var rcols:Array<Array<Point>> = [];
		for (o in offsets) {
			var ring = [], rc = [];
			for (c in cols) {
				var bu = c.u + (c.arcCentre ? c.nu * Quarry.CORNER : 0), bv = c.v + (c.arcCentre ? c.nv * Quarry.CORNER : 0);
				var wob = q.wobble(bu, bv);
				var oo = o;
				if (o == 99.0) {
					// Same numbers as block(): where this column's rounded edge ends.
					var lean = 0.06 + noise.fbm(c.s * 0.12 + 50, 3, 2) * 0.22;
					var round = 0.3 + noise.fbm(c.s * 0.2 + 60, 7, 2) * 0.7;
					oo = Quarry.WALL_OUT + 0.04 - lean - round + relief(c.s, q.top) * 0.3 + wob;
				} else if (o == 0.0) oo = o + wob * 0.6;
				// Offset the outline; inside the corner radius the ring turns into a plain
				// rectangle, so clamp to it (keeps every ring convex).
				var off = c.arcCentre ? Math.max(0, Quarry.CORNER + oo) : oo;
				var hu = Math.max(0.05, Quarry.L + oo + Quarry.WOBBLE), hv = Math.max(0.05, Quarry.W + oo + Quarry.WOBBLE);
				var u = Math.max(-hu, Math.min(hu, c.u + c.nu * off));
				var v = Math.max(-hv, Math.min(hv, c.v + c.nv * off));
				// A gently uneven top: worn hollows and humps (never below the ground the sim stands on).
				var z = top + Math.abs(noise.fbm(u * 0.3 + 41, v * 0.3 + 9, 3) - 0.5) * 0.3;
				ring.push(world(u, v, z));
				var worn = noise.fbm(u * 0.25 + 70, v * 0.25 + 70, 3);
				rc.push(colour(mixColor(Palette.QUARRY_TOP, Palette.QUARRY_STAIN, smooth(0.55, 0.8, worn) * 0.5), 0.95 + (worn - 0.5) * 0.2));
			}
			rings.push(ring);
			rcols.push(rc);
		}
		// Rings as a sheet (columns = ring positions), wrapped round, facing up.
		var grid = [for (ci in 0...cols.length) [for (ri in 0...rings.length) rings[ri][ci]]];
		var gcol = [for (ci in 0...cols.length) [for (ri in 0...rings.length) rcols[ri][ci]]];
		sheet(grid, gcol, true);
		// It's a flat top: light it as one (the inner rings' clamped corners have no
		// usable slope to take a normal from).
		var k = pts.length - grid.length * rings.length;
		for (i in k...pts.length) nrm[i] = new Point(0, 0, 1);
		// The middle: a fan from the centre to the innermost ring.
		var last = rings[rings.length - 1];
		var lastC = rcols[rcols.length - 1];
		var centre = world(0, 0, top);
		var base = pts.length;
		pts.push(centre);
		nrm.push(new Point(0, 0, 1));
		col.push(lastC[0]);
		for (k in 0...last.length) {
			pts.push(last[k]);
			nrm.push(new Point(0, 0, 1));
			col.push(lastC[k]);
		}
		for (k in 0...last.length) {
			var a = base + 1 + k, b = base + 1 + (k + 1) % last.length;
			idx.push(base);
			idx.push(a);
			idx.push(b);
		}
	}

	// --- the ramps ---------------------------------------------------------------

	function ramp(side:Float) {
		var fl = q.floor;
		var u0 = -Quarry.L - 0.5, u1 = Quarry.L + Quarry.WALL_OUT;
		var v0 = Quarry.W + 0.55, v1 = Quarry.RAMP_V1 + Quarry.WALL_OUT;
		var nu = Std.int(Math.ceil((u1 - u0) / 0.35)), nv = 8;
		inline function at(u:Float, v:Float, z:Float):Point
			return world(u * side, v * side, z);
		inline function surfaceZ(u:Float):Float
			return q.rampH(Math.min(u, Quarry.L)) + 0.03;

		// The outer edge wanders (outward only: the height map's own edge must stay inside).
		inline function edgeOut(u:Float):Float
			return noise.fbm(u * 0.22 + 300 * side, 4, 3) * 0.6;
		// The walking surface, scored across every 0.6 m on the slope.
		var grid = [], cols = [];
		for (i in 0...nu + 1) {
			var u = u0 + (u1 - u0) * i / nu;
			var z = surfaceZ(u);
			var onSlope = u < Quarry.RAMP_TOP_U;
			var groove = onSlope && ((u + 20) % 0.6) < 0.12;
			var c = [], cc = [];
			for (j in 0...nv + 1) {
				var v = v0 + (v1 + edgeOut(u) - v0) * j / nv;
				// The outer edge rounds over, unevenly (chipped).
				var edge = smooth(v1 - 0.5, v1 + 0.5, v) * (0.08 + noise.value(u * 0.9 + 7, 2) * 0.25);
				c.push(at(u, v, z - edge + (noise.value(u * 1.3 + 5, v * 1.3) - 0.5) * 0.04));
				var shade = 0.9 + (noise.fbm(u * 0.8 + 13, v * 0.8, 2) - 0.5) * 0.2;
				cc.push(colour(Palette.QUARRY_TOP, groove ? shade * 0.72 : shade));
			}
			grid.push(c);
			cols.push(cc);
		}
		// Rows run outward (v), so the sheet faces up whichever side it's on.
		sheet(grid, cols, false);

		// The outer face: fluted like the block, from below the floor up to the surface.
		var face = [], fcols = [];
		for (i in 0...nu + 1) {
			var u = u0 + (u1 - u0) * i / nu;
			var zt = surfaceZ(u) - 0.1 - noise.value(u * 0.9 + 7, 2) * 0.25;
			var c = [], cc = [];
			var rows = 6;
			for (k in 0...rows + 1) {
				var z = fl - 0.4 + (Math.max(zt, fl - 0.2) - (fl - 0.4)) * k / rows;
				var r = relief(u * 1.0 + 100 * side, z) * (k == rows ? 0.2 : 0.8);
				c.push(at(u, v1 + edgeOut(u) + Math.abs(r), z));
				cc.push(wallColor(u + 100 * side, z, false));
			}
			face.push(c);
			fcols.push(cc);
		}
		sheet(face, fcols, false, true);

		// The end face, under the landing.
		var end = [], ecols = [];
		var ne = 10;
		for (j in 0...ne + 1) {
			var v = v0 + (v1 - v0) * j / ne;
			var c = [], cc = [];
			for (k in 0...7) {
				var z = fl - 0.4 + (q.top - 0.1 - (fl - 0.4)) * k / 6;
				var r = relief(v + 200 * side, z) * 0.8;
				c.push(at(u1 + Math.abs(r) + noise.fbm(v * 0.4 + 500 * side, 2, 2) * 0.4, v, z));
				cc.push(wallColor(v + 200 * side, z, false));
			}
			end.push(c);
			ecols.push(cc);
		}
		sheet(end, ecols, false);
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
				// A degenerate spot (clamped corners of the top's inner rings): face up.
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
		var tex = GroundTextures.get().rock;
		var mats = [];
		for (p in chunks) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			m.material.mainPass.culling = None;
			var sh = new Rocks.RockShader();
			sh.tex = tex;
			sh.scale = 2.6;
			sh.strength = 0.55;
			m.material.mainPass.addShader(sh);
			FlatMeshBuilder.shadows(m.material, true, true);
			mats.push(m.material);
		}
		return mats;
	}

	static inline function colour(c:Int, shade:Float):Point
		return new Point(Palette.r(c) * shade, Palette.g(c) * shade, Palette.b(c) * shade);

	static function mixColor(a:Int, b:Int, t:Float):Int {
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
