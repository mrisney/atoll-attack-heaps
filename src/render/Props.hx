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
	thousand props cost only a handful of draw calls. Trees, bushes and rocks
	are built twice at the same spots: low-poly geometry, and painted sprites
	from res/props (see SpriteProps). The view shows one set. Grass goes in its own
	mesh in the alpha pass, so the ink outline pass skips it (otherwise every
	blade would get an outline).

	Layout is seeded from the island, so the same seed always looks the same.
	It's purely visual and doesn't affect the sim.
**/
typedef PropGroups = {
	/** Trees, bushes and rocks as low-poly geometry. **/
	var lowPoly:h3d.scene.Object;
	/** The same trees, bushes and rocks as painted sprites, plus waterline reeds. **/
	var sprites:h3d.scene.Object;
}

class Props {
	static inline var SPRITES = "props/";
	static final CANOPIES = ["tree-canopy-01", "tree-canopy-02", "tree-canopy-03", "tree-canopy-04"];
	/** Weeping, vine-draped canopies: mixed in, more often near water. **/
	static final VINE_CANOPIES = ["tree-canopy-vine-01", "tree-canopy-vine-02", "tree-canopy-vine-03"];
	static final VINE_MATS = ["vine-mat-01", "vine-mat-02"];
	static final TALL_GRASS = ["waterline-grass-tall-01", "waterline-grass-tall-02", "waterline-grass-tall-03"];
	static final BUSHES = ["bush-clump-01", "bush-clump-02", "bush-clump-03"];
	static final BOULDERS = ["landmark-boulder-01", "landmark-boulder-02", "landmark-boulder-03"];
	static final REEDS = [
		"waterline-grass-01", "waterline-grass-03", "waterline-reeds-02", "waterline-cattails-sparse-01", "waterline-cattails-sparse-02",
		"waterline-cattails-sparse-03"
	];

	final island:Island;
	/** Shared by both looks: palms, driftwood, stones, snags. **/
	final solid = new FlatMeshBuilder();
	/** Shared: grass, flowers, shells (alpha pass, not inked). **/
	final grass = new FlatMeshBuilder();
	/** Low-poly trees, bushes, rocks. **/
	final low = new FlatMeshBuilder();
	/** Sprite trees, bushes, boulders, reeds. **/
	final spr = new SpriteProps();
	/** Real 3D boulders for the sprite look (sprites read as stickers for rocks). **/
	final rocks = new Rocks();
	final palms = new Palms();
	/** Wind-blown grass fields (real blades, bent in the shader). **/
	final fields = new GrassField();
	var fieldN:Noise;
	var clumpN:Noise;
	/** Small loose stones, shared by both looks. **/
	final pebbles = new Rocks();
	/** Sprite trunks (mostly hidden under the canopy, they ground the tree). **/
	final trunks = new FlatMeshBuilder();
	final rnd:Noise;
	var salt = 0;

	/**
		Builds all props under `parent`. Trees, bushes and rocks exist in two
		forms at identical positions; show one group or the other.
	**/
	public static function build(island:Island, parent:h3d.scene.Object):PropGroups {
		return new Props(island).scatter(parent);
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

	function scatter(parent:h3d.scene.Object):PropGroups {
		var forestN = new Noise(island.seed + 202);
		var meadowN = new Noise(island.seed + 404);
		fieldN = new Noise(island.seed + 505);
		clumpN = new Noise(island.seed + 606);
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
				if (h < -0.15) continue;
				if (h < 0.18) {
					// Waterline: reeds and cattails standing in the shallows (sprite look only).
					if (r() < 0.07) reeds(x, y);
					continue;
				}

				var gx = island.heightAt(x + 0.5, y) - island.heightAt(x - 0.5, y);
				var gy = island.heightAt(x, y + 0.5) - island.heightAt(x, y - 0.5);
				var slope = Math.sqrt(gx * gx + gy * gy);
				var steep = slope > 0.9;
				var forest = forestN.fbm(x * 0.055 + 3, y * 0.055 + 3, 3);
				// Grassland clearings: where a field patch is strong, the woods give way to it.
				forest -= smoothstep(0.42, 0.55, fieldN.fbm(x * 0.035 + 21, y * 0.035 + 21, 3)) * 0.12;
				var meadow = meadowN.fbm(x * 0.08 + 9, y * 0.08 + 9, 3);
				var roll = r();
				var z = h - 0.06;

				if (h < tSand) {
					// Beach
					if (roll < 0.03 && h > 0.35) palm(x, y, z, -gx, -gy);
					else if (roll < 0.04) stones(x, y, z, 2);
					else if (roll < 0.066 && h < 0.6) driftwood(x, y, z);
					else if (roll < 0.12) shells(x, y, z);
					else if (roll < 0.2 && h > 0.35) beachGrass(x, y, z);
				} else if (h < tLow) {
					// Lowland
					if (steep && roll < 0.1) rockCluster(x, y, z, 2);
					else if (forest > 0.56 && roll < 0.55) {
						if (r() < 0.75) broadleaf(x, y, z) else pine(x, y, z);
					} else if (forest > 0.5 && roll < 0.2) bush(x, y, z);
					else if (forest > 0.47 && roll < 0.42) vineMat(x, y, z);
					else {
						// Open ground: fields of tall grass in the wind, meadow tufts elsewhere.
						var f = fieldWeight(x, y, h, forest, slope, tSand, tUp);
						if (f > 0.02) {
							grassField(x, y, step, f);
							if (r() < 0.1) flowers(x, y, z);
						} else if (meadow > 0.48 && roll < 0.75) {
							grassTuft(x, y, z);
							if (r() < 0.35) flowers(x, y, z);
						}
					}
				} else if (h < tUp) {
					// Upland
					if (steep && roll < 0.15) rockCluster(x, y, z, 2);
					else if (forest > 0.48 && roll < 0.65) {
						if (r() < 0.8) pine(x, y, z) else broadleaf(x, y, z);
					} else if (roll < 0.1) bush(x, y, z);
					else {
						var f = fieldWeight(x, y, h, forest, slope, tSand, tUp);
						if (f > 0.02) grassField(x, y, step, f);
						else if (roll < 0.3) grassTuft(x, y, z);
						else if (roll < 0.315) stones(x, y, z, 2);
					}
				} else {
					// Peak
					// Sparse: a few boulder groups and loose stones (the owner found them too many).
					if (roll < 0.022) rockCluster(x, y, z, 1 + Std.int(r() * 3));
					else if (roll < 0.05) stones(x, y, z, 2);
					else if (roll < 0.08) snag(x, y, z);
				}
			}

		solid.build(parent, true, true, true);
		for (m in grass.build(parent, true, false, true)) {
			// Alpha pass (fully opaque) keeps grass out of the ink edge buffer.
			m.material.blendMode = Alpha;
			m.material.mainPass.culling = None;
		}
		var lowPoly = new h3d.scene.Object(parent);
		low.build(lowPoly, true, true, true);
		var sprites = new h3d.scene.Object(parent);
		trunks.build(sprites, true, true, true);
		spr.build(sprites);
		rocks.build(sprites);
		pebbles.build(parent);
		fields.build(parent);
		#if js
		js.Syntax.code("window.grassBlades = {0}", fields.count);
		#end
		palms.build(parent);
		return {lowPoly: lowPoly, sprites: sprites};
	}

	inline function pickName(list:Array<String>):String
		return list[Std.int(r() * list.length) % list.length];

	/** A sprite canopy on a short trunk. `s` scales the whole tree. **/
	function spriteTree(x:Float, y:Float, z:Float, s:Float) {
		var trunkH = (0.9 + r() * 0.45) * s;
		trunks.prism(x, y, z, 0.1 * s, trunkH + 0.2, 5, tint(pick(Palette.BARK)), r() * 3);
		var size = (2.0 + r() * 0.9) * s;
		// Weeping vine trees like the low ground near water; elsewhere they're occasional.
		var vineChance = z < Island.classicHeight(0.47) ? 0.45 : 0.15;
		var name = r() < vineChance ? pickName(VINE_CANOPIES) : pickName(CANOPIES);
		spr.add(SPRITES + name + ".png", x, y, z + trunkH, size, size * 0.28, r() * Math.PI * 2, 0.92 + r() * 0.16);
	}

	/** Creepers spilling out of the forest edge onto the open ground. **/
	function vineMat(x:Float, y:Float, z:Float) {
		spr.add(SPRITES + pickName(VINE_MATS) + ".png", x, y, z + 0.04, 1.4 + r() * 1.0, 0.08, r() * Math.PI * 2, 0.9 + r() * 0.2);
	}

	/** Dune grass clumps on the sand. **/
	function beachGrass(x:Float, y:Float, z:Float) {
		for (k in 0...1 + Std.int(r() * 3)) {
			var a = r() * Math.PI * 2, d = r() * 0.7;
			spr.add(SPRITES + pickName(TALL_GRASS) + ".png", x + Math.cos(a) * d, y + Math.sin(a) * d, z + 0.05, 0.8 + r() * 0.5, 0.12,
				r() * Math.PI * 2, 0.95 + r() * 0.1);
		}
	}

	function reeds(x:Float, y:Float) {
		spr.add(SPRITES + pickName(REEDS) + ".png", x, y, 0.06, 0.9 + r() * 0.6, 0.1, r() * Math.PI * 2);
	}

	// --- species ------------------------------------------------------------

	function pine(x:Float, y:Float, z:Float) {
		var s = 0.75 + r() * 0.65;
		var rot = r() * Math.PI;
		var c1 = tint(pick(Palette.PINE)), c2 = tint(pick(Palette.PINE));
		low.prism(x, y, z, 0.08 * s, 0.5 * s, 5, tint(pick(Palette.BARK)), rot);
		low.cone(x, y, z + 0.35 * s, 0.68 * s, 1.0 * s, 7, c1, 0, rot);
		low.cone(x, y, z + 0.85 * s, 0.52 * s, 0.85 * s, 7, c2, 0, rot + 0.4);
		if (s > 1.1) low.cone(x, y, z + 1.35 * s, 0.34 * s, 0.7 * s, 6, c1, 0, rot + 0.8);
		spriteTree(x, y, z, 0.75 + s * 0.3);
	}

	function broadleaf(x:Float, y:Float, z:Float) {
		var s = 0.7 + r() * 0.6;
		var trunkH = 0.7 * s;
		low.prism(x, y, z, 0.09 * s, trunkH + 0.3 * s, 5, tint(pick(Palette.BARK)), r() * 3);
		// Mostly green, the odd turning tree, like Northgard's mixed woods.
		var leaf = r() < 0.06 ? pick(Palette.LEAF_AUTUMN) : pick(Palette.LEAF);
		var top = z + trunkH + 0.45 * s;
		var blobs = 2 + Std.int(r() * 3);
		for (k in 0...blobs) {
			var a = r() * Math.PI * 2;
			var d = (k == 0 ? 0 : 0.35 + r() * 0.25) * s;
			var br = (0.55 + r() * 0.3) * s * (k == 0 ? 1.15 : 0.9);
			low.ball(x + Math.cos(a) * d, y + Math.sin(a) * d, top + (r() - 0.3) * 0.35 * s, br, tint(leaf), 7, 4, 0.85, r() * 3);
		}
		spriteTree(x, y, z, 0.8 + s * 0.35);
	}

	/** Coconut palm (see Palms): smooth curved trunk, arched leafy fronds, a few coconuts. **/
	function palm(x:Float, y:Float, z:Float, towardX:Float, towardY:Float) {
		var s = 0.85 + r() * 0.45;
		var len = Math.sqrt(towardX * towardX + towardY * towardY);
		var a = len > 1e-4 ? Math.atan2(towardY, towardX) : r() * Math.PI * 2;
		a += (r() - 0.5) * 0.9;
		var lx = Math.cos(a), ly = Math.sin(a);
		palms.add(x, y, z, lx, ly, s, tint(pick(Palette.PALM_BARK)), tint(pick(Palette.PALM), 0.1), r);
	}

	function bush(x:Float, y:Float, z:Float) {
		var s = 0.5 + r() * 0.45;
		var c = pick(Palette.LEAF);
		for (k in 0...2 + Std.int(r() * 2)) {
			var a = r() * Math.PI * 2, d = r() * 0.3 * s;
			low.ball(x + Math.cos(a) * d, y + Math.sin(a) * d, z + 0.18 * s, (0.3 + r() * 0.15) * s, tint(c, 0.18), 6, 3, 0.75, r() * 3);
		}
		spr.add(SPRITES + pickName(BUSHES) + ".png", x, y, z, (1.0 + r() * 0.5) * (0.6 + s), 0.35 * s, r() * Math.PI * 2, 0.9 + r() * 0.2);
	}

	/**
		How much grass field grows here (0..1): large open patches away from
		forest, off the beach and below the bare heights, on gentle ground.
	**/
	function fieldWeight(x:Float, y:Float, h:Float, forest:Float, slope:Float, tSand:Float, tUp:Float):Float {
		if (slope > 0.75) return 0;
		var field = fieldN.fbm(x * 0.035 + 21, y * 0.035 + 21, 3);
		return smoothstep(0.34, 0.44, field) * (1 - smoothstep(0.5, 0.6, forest)) * smoothstep(tSand + 0.05, tSand + 0.45, h)
			* (1 - smoothstep(tUp - 0.3, tUp + 0.5, h));
	}

	/** Fill one placement cell with grass blades; `w` thins them out toward a field's edge. **/
	function grassField(x:Float, y:Float, cell:Float, w:Float) {
		var n = Std.int(w * 38 + r());
		for (k in 0...n) {
			var bx = x + (r() - 0.5) * cell, by = y + (r() - 0.5) * cell;
			// Clumpy heights (as in Terra): taller tussocks and shorter patches.
			var clump = clumpN.fbm(bx * 0.45 + 3, by * 0.45 + 3, 2);
			var height = (0.3 + 0.5 * clump) * (0.75 + r() * 0.5) * (0.6 + 0.4 * w);
			var dry = r() < 0.15 ? r() : r() * 0.25;
			fields.blade(bx, by, island.heightAt(bx, by) - 0.02, r() * Math.PI * 2, 0.08 + r() * 0.06, height, (r() - 0.5) * 0.5,
				0.15 + r() * 0.45, dry);
		}
	}

	static inline function smoothstep(a:Float, b:Float, x:Float):Float {
		var t = Math.max(0, Math.min(1, (x - a) / (b - a)));
		return t * t * (3 - 2 * t);
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
			low.ball(rx, ry, rz, rs, tint(c, 0.15), 5 + Std.int(r() * 2), 3, 0.55 + r() * 0.25, r() * 3);
			rocks.add(rx, ry, island.heightAt(rx, ry), rs * 2.4, salt * 31 + k, tint(c, 0.14));
		}
	}

	function stones(x:Float, y:Float, z:Float, count:Int) {
		for (k in 0...count) {
			var a = r() * Math.PI * 2, d = r() * 0.6;
			var sx = x + Math.cos(a) * d, sy = y + Math.sin(a) * d;
			pebbles.add(sx, sy, island.heightAt(sx, sy), 0.18 + r() * 0.22, salt * 31 + 100 + k, tint(pick(Palette.ROCKS), 0.2));
		}
	}

	function driftwood(x:Float, y:Float, z:Float) {
		var a = r() * Math.PI;
		var len = 0.9 + r() * 0.8;
		low.place(0, Math.PI / 2, a, x, y, z + 0.06);
		low.prism(0, 0, -len / 2, 0.07, len, 5, Palette.DRIFTWOOD);
		low.unplace();
		spr.add(SPRITES + "floating-log.png", x, y, z + 0.05, len * 1.25, 0.06, a + Math.PI / 2, 1.0);
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
