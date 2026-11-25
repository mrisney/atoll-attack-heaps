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
	- the gullies: cut into the flanks, floored with rough stone.

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

	public function new(q:Quarry, seed:Int) {
		this.q = q;
		noise = new world.Noise(seed + 717);
	}

	public static function build(island:world.Island, parent:h3d.scene.Object):Array<h3d.mat.Material> {
		if (island.quarry == null) return [];
		var v = new QuarryView(island.quarry, island.seed);
		v.dome();
		return v.finish(parent);
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
		var tex = GroundTextures.get().rock;
		var mats = [];
		for (p in chunks) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			m.material.mainPass.culling = None;
			var sh = new Rocks.RockShader();
			sh.tex = tex;
			sh.scale = 2.2;
			sh.strength = 0.6;
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
