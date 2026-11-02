package render;

import h3d.col.Point;
import world.Island;
import world.Noise;

/**
	Vegetation and rocks: what makes the island feel lived-in.

	Variety comes from several species, a colour picked per instance plus a
	small tint, random size and lean, and clustering driven by low-frequency
	noise (forests, meadows) rather than uniform scatter. Placement follows
	the elevation bands:

	- Beach: palms leaning toward the sea, driftwood, small stones
	- Lowland: broadleaf groves with a few pines, bushes, grass meadows
	- Upland: pine forest, bushes, rock outcrops on steep ground
	- Peak: boulder clusters, loose stones, the odd dead snag

	Everything is merged into a few large meshes (FlatMeshBuilder), so a few
	thousand props cost only a handful of draw calls. Grass goes in its own
	mesh in the alpha pass, so the ink outline pass skips it (otherwise every
	blade would get an outline).

	Layout is seeded from the island, so the same seed always looks the same.
	It's purely visual and doesn't affect the sim.
**/
class Props {
	final island:Island;
	final solid = new FlatMeshBuilder();
	final grass = new FlatMeshBuilder();
	final rnd:Noise;
	var salt = 0;

	public static function build(island:Island, parent:h3d.scene.Object) {
		new Props(island).scatter(parent);
	}

	function new(island:Island) {
		this.island = island;
		rnd = new Noise(island.seed + 303);
	}

	/** Deterministic random in [0, 1) for this island. **/
	inline function r():Float
		return rnd.rand(salt++, 7919);

	inline function pick(list:Array<Int>):Int
		return list[Std.int(r() * list.length) % list.length];

	/** A palette colour with a little per-instance brightness variation. **/
	inline function tint(c:Int, amount = 0.12):Int
		return Palette.shade(c, 1 - amount * 0.5 + r() * amount);

	function scatter(parent:h3d.scene.Object) {
		var forestN = new Noise(island.seed + 202);
		var meadowN = new Noise(island.seed + 404);
		var he = island.halfExtent;
		var tSand = Island.classicHeight(0.39);
		var tLow = Island.classicHeight(0.54);
		var tUp = Island.classicHeight(0.70);

		var step = 1.1;
		var n = Std.int(island.size * island.cell / step);
		for (j in 0...n)
			for (i in 0...n) {
				salt = (j * n + i) * 37;
				var x = i * step - he + (r() - 0.5) * step;
				var y = j * step - he + (r() - 0.5) * step;
				var h = island.heightAt(x, y);
				if (h < 0.18) continue;

				var gx = island.heightAt(x + 0.5, y) - island.heightAt(x - 0.5, y);
				var gy = island.heightAt(x, y + 0.5) - island.heightAt(x, y - 0.5);
				var slope = Math.sqrt(gx * gx + gy * gy);
				var steep = slope > 0.9;
				var forest = forestN.fbm(x * 0.055 + 3, y * 0.055 + 3, 3);
				var meadow = meadowN.fbm(x * 0.08 + 9, y * 0.08 + 9, 3);
				var roll = r();
				var z = h - 0.06;

				if (h < tSand) {
					// Beach
					if (roll < 0.03 && h > 0.35) palm(x, y, z, -gx, -gy);
					else if (roll < 0.05) stones(x, y, z, 2);
					else if (roll < 0.056 && h < 0.6) driftwood(x, y, z);
					else if (roll < 0.12) shells(x, y, z);
				} else if (h < tLow) {
					// Lowland
					if (steep && roll < 0.25) rockCluster(x, y, z, 2);
					else if (forest > 0.56 && roll < 0.55) {
						if (r() < 0.75) broadleaf(x, y, z) else pine(x, y, z);
					} else if (forest > 0.5 && roll < 0.2) bush(x, y, z);
					else if (meadow > 0.48 && roll < 0.75) {
						grassTuft(x, y, z);
						if (r() < 0.35) flowers(x, y, z);
					}
					else if (roll < 0.015) rockCluster(x, y, z, 1);
				} else if (h < tUp) {
					// Upland
					if (steep && roll < 0.35) rockCluster(x, y, z, 3);
					else if (forest > 0.48 && roll < 0.65) {
						if (r() < 0.8) pine(x, y, z) else broadleaf(x, y, z);
					} else if (roll < 0.12) bush(x, y, z);
					else if (roll < 0.3) grassTuft(x, y, z);
					else if (roll < 0.36) stones(x, y, z, 2);
				} else {
					// Peak
					if (roll < 0.1) rockCluster(x, y, z, 4);
					else if (roll < 0.18) stones(x, y, z, 3);
					else if (roll < 0.21) snag(x, y, z);
				}
			}

		solid.build(parent, true, true, true);
		for (m in grass.build(parent, true, false, true)) {
			// Alpha pass (fully opaque) keeps grass out of the ink edge buffer.
			m.material.blendMode = Alpha;
			m.material.mainPass.culling = None;
		}
	}

	// --- species ------------------------------------------------------------

	function pine(x:Float, y:Float, z:Float) {
		var s = 0.75 + r() * 0.65;
		var rot = r() * Math.PI;
		var c1 = tint(pick(Palette.PINE)), c2 = tint(pick(Palette.PINE));
		solid.prism(x, y, z, 0.08 * s, 0.5 * s, 5, tint(pick(Palette.BARK)), rot);
		solid.cone(x, y, z + 0.35 * s, 0.68 * s, 1.0 * s, 7, c1, 0, rot);
		solid.cone(x, y, z + 0.85 * s, 0.52 * s, 0.85 * s, 7, c2, 0, rot + 0.4);
		if (s > 1.1) solid.cone(x, y, z + 1.35 * s, 0.34 * s, 0.7 * s, 6, c1, 0, rot + 0.8);
	}

	function broadleaf(x:Float, y:Float, z:Float) {
		var s = 0.7 + r() * 0.6;
		var trunkH = 0.7 * s;
		solid.prism(x, y, z, 0.09 * s, trunkH + 0.3 * s, 5, tint(pick(Palette.BARK)), r() * 3);
		// Mostly green, the odd turning tree, like Northgard's mixed woods.
		var leaf = r() < 0.06 ? pick(Palette.LEAF_AUTUMN) : pick(Palette.LEAF);
		var top = z + trunkH + 0.45 * s;
		var blobs = 2 + Std.int(r() * 3);
		for (k in 0...blobs) {
			var a = r() * Math.PI * 2;
			var d = (k == 0 ? 0 : 0.35 + r() * 0.25) * s;
			var br = (0.55 + r() * 0.3) * s * (k == 0 ? 1.15 : 0.9);
			solid.ball(x + Math.cos(a) * d, y + Math.sin(a) * d, top + (r() - 0.3) * 0.35 * s, br, tint(leaf), 7, 4, 0.85, r() * 3);
		}
	}

	/** Leaning palm: a curved trunk of short segments, drooping fronds, coconuts. **/
	function palm(x:Float, y:Float, z:Float, towardX:Float, towardY:Float) {
		var s = 0.85 + r() * 0.5;
		var len = Math.sqrt(towardX * towardX + towardY * towardY);
		var a = len > 1e-4 ? Math.atan2(towardY, towardX) : r() * Math.PI * 2;
		a += (r() - 0.5) * 0.9;
		var lx = Math.cos(a), ly = Math.sin(a);
		var lean = 0.25 + r() * 0.3;
		var bark = tint(pick(Palette.PALM_BARK));
		var segs = 6;
		var cx = x, cy = y, cz = z;
		for (k in 0...segs) {
			var t = (k + 1) / segs;
			var seg = 0.42 * s;
			solid.prism(cx, cy, cz, (0.11 - 0.035 * t) * s, seg, 5, k % 2 == 0 ? bark : Palette.shade(bark, 0.9), k * 0.4);
			// The trunk curves more toward the top.
			cx += lx * lean * t * seg;
			cy += ly * lean * t * seg;
			cz += seg * 0.95;
		}
		var top = new Point(cx, cy, cz);
		var leaf = pick(Palette.PALM);
		var fronds = 7;
		for (k in 0...fronds) {
			var fa = k / fronds * Math.PI * 2 + r() * 0.4;
			var fx = Math.cos(fa), fy = Math.sin(fa);
			var L = (1.1 + r() * 0.35) * s;
			var w = 0.22 * s;
			var mid = new Point(cx + fx * L * 0.5, cy + fy * L * 0.5, cz + 0.18 * s);
			var tip = new Point(cx + fx * L, cy + fy * L, cz - (0.35 + r() * 0.2) * s);
			var side = new Point(-fy * w, fx * w, 0);
			var c = tint(leaf);
			solid.twoSided(top, mid.add(side), tip, c);
			solid.twoSided(top, tip, mid.sub(side), Palette.shade(c, 0.9));
		}
		for (k in 0...3) {
			var ca = k * 2.1 + r();
			solid.ball(cx + Math.cos(ca) * 0.12 * s, cy + Math.sin(ca) * 0.12 * s, cz - 0.1 * s, 0.09 * s, Palette.COCONUT, 5, 3);
		}
	}

	function bush(x:Float, y:Float, z:Float) {
		var s = 0.5 + r() * 0.45;
		var c = pick(Palette.LEAF);
		for (k in 0...2 + Std.int(r() * 2)) {
			var a = r() * Math.PI * 2, d = r() * 0.3 * s;
			solid.ball(x + Math.cos(a) * d, y + Math.sin(a) * d, z + 0.18 * s, (0.3 + r() * 0.15) * s, tint(c, 0.18), 6, 3, 0.75, r() * 3);
		}
	}

	function grassTuft(x:Float, y:Float, z:Float) {
		var c = pick(Palette.GRASS_TUFT);
		var blades = 5 + Std.int(r() * 4);
		for (k in 0...blades) {
			var a = r() * Math.PI * 2;
			var ox = x + Math.cos(a) * r() * 0.25, oy = y + Math.sin(a) * r() * 0.25;
			var bh = 0.22 + r() * 0.2;
			var lean = 0.08 + r() * 0.12;
			var ba = r() * Math.PI * 2;
			var w = 0.035;
			grass.twoSided(new Point(ox - Math.sin(ba) * w, oy + Math.cos(ba) * w, z), new Point(ox + Math.sin(ba) * w, oy - Math.cos(ba) * w, z),
				new Point(ox + Math.cos(ba) * lean, oy + Math.sin(ba) * lean, z + bh), tint(c, 0.2));
		}
	}

	/** A small cluster of wildflowers: flat star-shaped heads on short stems. **/
	function flowers(x:Float, y:Float, z:Float) {
		var c = pick(Palette.FLOWERS);
		for (k in 0...3 + Std.int(r() * 5)) {
			var a = r() * Math.PI * 2, d = r() * 0.55;
			var fx = x + Math.cos(a) * d, fy = y + Math.sin(a) * d;
			var fz = island.heightAt(fx, fy) + 0.07 + r() * 0.08;
			var petals = 5;
			var rad = 0.05 + r() * 0.03;
			var rot = r() * Math.PI;
			var centre = new Point(fx, fy, fz);
			for (p in 0...petals) {
				var a0 = rot + p / petals * Math.PI * 2;
				var a1 = a0 + Math.PI * 2 / petals * 0.55;
				grass.twoSided(centre, new Point(fx + Math.cos(a0) * rad, fy + Math.sin(a0) * rad, fz),
					new Point(fx + Math.cos(a1) * rad, fy + Math.sin(a1) * rad, fz), c);
			}
		}
	}

	/** Pale shells scattered on the sand. **/
	function shells(x:Float, y:Float, z:Float) {
		for (k in 0...1 + Std.int(r() * 3)) {
			var a = r() * Math.PI * 2, d = r() * 0.5;
			var sx = x + Math.cos(a) * d, sy = y + Math.sin(a) * d;
			grass.ball(sx, sy, island.heightAt(sx, sy) + 0.01, 0.04 + r() * 0.03, pick(Palette.SHELLS), 5, 2, 0.5, r() * 3);
		}
	}

	function rockCluster(x:Float, y:Float, z:Float, count:Int) {
		var c = pick(Palette.ROCKS);
		for (k in 0...count) {
			var a = r() * Math.PI * 2, d = k == 0 ? 0 : 0.4 + r() * 0.5;
			var rs = (k == 0 ? 0.45 : 0.25) + r() * 0.35;
			var rx = x + Math.cos(a) * d, ry = y + Math.sin(a) * d;
			var rz = island.heightAt(rx, ry) - 0.08;
			solid.ball(rx, ry, rz, rs, tint(c, 0.15), 5 + Std.int(r() * 2), 3, 0.55 + r() * 0.25, r() * 3);
		}
	}

	function stones(x:Float, y:Float, z:Float, count:Int) {
		for (k in 0...count) {
			var a = r() * Math.PI * 2, d = r() * 0.6;
			var sx = x + Math.cos(a) * d, sy = y + Math.sin(a) * d;
			solid.ball(sx, sy, island.heightAt(sx, sy) - 0.03, 0.08 + r() * 0.1, tint(pick(Palette.ROCKS), 0.2), 5, 3, 0.6, r() * 3);
		}
	}

	function driftwood(x:Float, y:Float, z:Float) {
		var a = r() * Math.PI;
		var len = 0.9 + r() * 0.8;
		solid.place(0, Math.PI / 2, a, x, y, z + 0.06);
		solid.prism(0, 0, -len / 2, 0.07, len, 5, Palette.DRIFTWOOD);
		solid.unplace();
	}

	/** A bare dead tree on the heights. **/
	function snag(x:Float, y:Float, z:Float) {
		var s = 0.7 + r() * 0.5;
		var c = Palette.shade(pick(Palette.BARK), 1.1);
		solid.prism(x, y, z, 0.07 * s, 1.5 * s, 5, c, r() * 3);
		for (k in 0...2) {
			var a = r() * Math.PI * 2;
			solid.place(0, 0.7 + r() * 0.3, a, x, y, z + (0.8 + k * 0.4) * s);
			solid.prism(0, 0, 0, 0.035 * s, 0.6 * s, 4, c);
			solid.unplace();
		}
	}
}
