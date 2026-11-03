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
	- Peak: loose gravel, boulder clusters, a few stones

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
	/** The same trees as 3D procedural trees (EZ-Tree's generator; the default look). **/
	var proc:h3d.scene.Object;
	/** Sprite tree canopies and their trunks (inside `sprites`; hidden when 3D trees show). **/
	var canopies:h3d.scene.Object;
	/** Grass field map (R field, G clump, B dryness) for tinting the ground under fields. **/
	var fieldMask:Null<h3d.mat.Texture>;
	/** The grass (call setFocus each frame with the camera's look-at). **/
	var grass:Null<GrassField>;
	var trees:ProcTrees;
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
	/** Shared by both looks: palms, driftwood, stones. **/
	final solid = new FlatMeshBuilder();
	/** Shared: grass, flowers, shells (alpha pass, not inked). **/
	final grass = new FlatMeshBuilder();
	/** Low-poly trees, bushes, rocks. **/
	final low = new FlatMeshBuilder();
	/** Sprite trees, bushes, boulders, reeds. **/
	final spr = new SpriteProps();
	/** Sprite tree canopies only, so they can hide while bushes and reeds stay. **/
	final canopySpr = new SpriteProps();
	/** Real 3D boulders for the sprite look (sprites read as stickers for rocks). **/
	final rocks = new Rocks();
	final palms = new Palms();
	final procTrees = new ProcTrees();
	/** Wind-blown grass fields (real blades, bent in the shader). **/
	var fields:GrassField;
	var fieldN:Noise;
	/** Where boulders gather (clusters around the gravel high ground). **/
	var boulderN:Noise;
	var forestN:Noise;
	var tSand = 0.0;
	var tUp = 0.0;
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
		forestN = new Noise(island.seed + 202);
		var meadowN = new Noise(island.seed + 404);
		fieldN = new Noise(island.seed + 505);
		boulderN = new Noise(island.seed + 909);

		var he = island.halfExtent;
		tSand = Island.classicHeight(0.39);
		var tLow = Island.classicHeight(0.54);
		tUp = Island.classicHeight(0.70);

		var step = 1.1;
		var n = Std.int(island.size * island.cell / step);
		for (j in 0...n)
			for (i in 0...n) {
				salt = (j * n + i) * 37;
				var x = i * step - he + (r() - 0.5) * step;
				var y = j * step - he + (r() - 0.5) * step;
				var h = island.heightAt(x, y);
				// Rare rock outcrops along the coast, running out into the shallows.
				if (h > -0.9 && h < 0.45 && outcropSpot(x, y)) {
					outcrop(x, y, h);
					continue;
				}
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
				var forest = forestAt(x, y);
				var meadow = meadowN.fbm(x * 0.08 + 9, y * 0.08 + 9, 3);
				var roll = r();
				var z = h - 0.06;

				if (h < tSand) {
					// Beach
					if (roll < 0.03 && h > 0.35) palm(x, y, z, -gx, -gy);
					else if (roll < 0.033) stones(x, y, z, 1);
					else if (roll < 0.066 && h < 0.6) driftwood(x, y, z);
					else if (roll < 0.12) shells(x, y, z);
					else if (roll < 0.2 && h > 0.35) beachGrass(x, y, z);
				} else if (h < tUp + 1.0) {
					// Pastoral lowland and upland: broad open fields, divided by winding
					// tree lines (hedgerows), with a few small copses and lone trees.
					var line = treeLineAt(x, y);
					var copse = forest > 0.7;
					if (boulderSpot(x, y, h, roll)) rockCluster(x, y, z, 1 + Std.int(r() * 3));
					else if (line > 0.5) {
						if (roll < 0.8) {
							if (h > tLow && r() < 0.5) pine(x, y, z) else broadleaf(x, y, z);
						} else bush(x, y, z);
					} else if (copse && roll < 0.6) {
						if (h > tLow && r() < 0.6) pine(x, y, z) else broadleaf(x, y, z);
					} else if (forest > 0.62 && roll < 0.25) bush(x, y, z);
					else if (fieldWeight(x, y, h, forest, slope) > 0.02) {
						// Open field: the blades come from GrassField. Now and then a lone tree,
						// like parkland, and a few flowers.
						if (roll < 0.004) broadleaf(x, y, z);
						else if (roll < 0.004) stones(x, y, z, 1);
						else if (roll < 0.06) flowers(x, y, z);
					} else if (meadow > 0.48 && roll < 0.5) grassTuft(x, y, z);
				} else {
					// Peak
					// Sparse: a few boulder groups and loose stones (the owner found them too many).
					// The rocky high point: outcrops and scree around the summit.
					// The high point: loose gravel (terrain texture) strewn with stones, a few
					// boulders.
					if (boulderSpot(x, y, h, roll)) rockCluster(x, y, z, 1 + Std.int(r() * 3));
					else if (roll < 0.1) stones(x, y, z, 2);
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
		var proc = new h3d.scene.Object(parent);
		procTrees.build(proc);
		#if js
		js.Syntax.code("window.procTrees = {0}", procTrees.count);
		#end
		var sprites = new h3d.scene.Object(parent);
		var canopies = new h3d.scene.Object(sprites);
		trunks.build(canopies, true, true, true);
		canopySpr.build(canopies);
		spr.build(sprites);
		rocks.build(sprites);
		pebbles.build(parent);
		fields = new GrassField(island);
		fields.build(parent, fieldAt);
		#if js
		js.Syntax.code("window.grassBlades = {0}", fields.blades);
		#end
		palms.build(parent);
		return {lowPoly: lowPoly, sprites: sprites, proc: proc, canopies: canopies, fieldMask: fields.mask, grass: fields, trees: procTrees};
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
		canopySpr.add(SPRITES + name + ".png", x, y, z + trunkH, size, size * 0.28, r() * Math.PI * 2, 0.92 + r() * 0.16);
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
		procTrees.add(Pine, x, y, z, 0.75 + s * 0.3, r() * Math.PI * 2, Std.int(r() * 4), tint(pick(Palette.PINE), 0.2), tint(pick(Palette.BARK)));
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
		var roll = r();
		var species:ProcTrees.TreeSpecies = roll < 0.5 ? Oak : roll < 0.85 ? Ash : Aspen;
		procTrees.add(species, x, y, z, 0.75 + s * 0.3, r() * Math.PI * 2, Std.int(r() * 4), tint(leaf, 0.2), tint(pick(Palette.BARK)));
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

	/** Forest density (only the densest spots become copses now). **/
	function forestAt(x:Float, y:Float):Float {
		return forestN.fbm(x * 0.09 + 3, y * 0.09 + 3, 3);
	}

	/**
		Tree lines: thin winding bands along a noise isoline, like hedgerows
		dividing fields. 1 on the line, 0 off it. A second noise breaks them
		into runs with gaps (field gates), so they don't wall everything in.
	**/
	function treeLineAt(x:Float, y:Float):Float {
		var n = fieldN.fbm(x * 0.022 + 40, y * 0.022 + 40, 2);
		var gx = fieldN.fbm((x + 1) * 0.022 + 40, y * 0.022 + 40, 2) - n;
		var gy = fieldN.fbm(x * 0.022 + 40, (y + 1) * 0.022 + 40, 2) - n;
		// Distance to the 0.5 isoline in metres (value / gradient).
		var d = Math.abs(n - 0.5) / Math.max(1e-5, Math.sqrt(gx * gx + gy * gy));
		var runs = smoothstep(0.38, 0.46, forestN.fbm(x * 0.03 + 77, y * 0.03 + 77, 2));
		return (1 - smoothstep(1.6, 2.8, d)) * runs;
	}

	/**
		How much grass field grows here (0..1): nearly all open lowland and
		upland, stopping at copses, tree lines, the beach, bare heights and
		steep ground.
	**/
	function fieldWeight(x:Float, y:Float, h:Float, forest:Float, slope:Float):Float {
		return (1 - smoothstep(0.64, 0.72, forest)) * (1 - treeLineAt(x, y) * 0.85) * smoothstep(tSand + 0.05, tSand + 0.45, h)
			* (1 - smoothstep(tUp + 0.6, tUp + 1.4, h)) * (1 - smoothstep(0.7, 1.0, slope));
	}

	/** fieldWeight at any world point (for GrassField's map). **/
	function fieldAt(x:Float, y:Float):Float {
		var h = island.heightAt(x, y);
		var gx = island.heightAt(x + 0.5, y) - island.heightAt(x - 0.5, y);
		var gy = island.heightAt(x, y + 0.5) - island.heightAt(x, y - 0.5);
		return fieldWeight(x, y, h, forestAt(x, y), Math.sqrt(gx * gx + gy * gy));
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

	/** A few stretches of coast get outcrops (noise clumps, sparse). **/
	function outcropSpot(x:Float, y:Float):Bool {
		var n = boulderN.fbm(x * 0.07 + 51, y * 0.07 + 51, 3);
		return n > 0.7 && r() < 0.06;
	}

	/**
		A group of larger, chipped rocks at the waterline. Rocks in the water
		sit on a raised base, so they break the surface while their lower part
		stays hidden under water.
	**/
	function outcrop(x:Float, y:Float, h:Float) {
		var c = pick(Palette.ROCKS);
		for (k in 0...2 + Std.int(r() * 3)) {
			var a = r() * Math.PI * 2, d = k == 0 ? 0 : 0.5 + r() * 0.9;
			var rx = x + Math.cos(a) * d, ry = y + Math.sin(a) * d;
			var gh = island.heightAt(rx, ry);
			var size = (k == 0 ? 1.5 : 0.8) + r() * 0.9;
			// Sea rocks are dark: wet, weathered, darker still where they sit in the water.
			var dark = gh < 0.1 ? 0.42 : 0.55;
			rocks.add(rx, ry, Math.max(gh, -0.3), size, salt * 31 + 500 + k, tint(Palette.shade(c, dark), 0.12));
		}
	}

	/**
		Boulders gather around the gravel high ground: on it and in a band just
		below its rim, in irregular clusters (noise patches), with almost none
		out in the meadows.
	**/
	function boulderSpot(x:Float, y:Float, h:Float, roll:Float):Bool {
		var near = smoothstep(tUp + 0.1, tUp + 0.9, h); // 0 down in the meadows, 1 on the gravel
		if (near <= 0) return false;
		var clump = smoothstep(0.5, 0.68, boulderN.fbm(x * 0.11 + 13, y * 0.11 + 13, 3));
		return roll < near * (0.004 + 0.07 * clump);
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

}
