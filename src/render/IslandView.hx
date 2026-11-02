package render;

import h3d.col.Point;
import world.Island;
import world.Noise;

/**
	Turns an Island heightfield into the stylized scene: terrain, banded
	animated water, scattered pines and rocks, and the apex flag.
**/
enum VisualStyle {
	/** The atoll-attack (Flutter) look: posterised bands, bright palette. **/
	Classic;
	/** Hand-drawn map: soft colours, contours, hatching, ink outlines. **/
	InkMap;
	/** Painted ground textures (grass/dirt/sand/rock), soft water, tilt-shift. **/
	Painted;
	/**
		Architectural presentation drawing: graphite on paper, only timber in
		colour, ruled water, drafting annotations, edges dissolving to the page.
	**/
	Sketch;
}

class IslandView extends h3d.scene.Object {
	final island:Island;

	public function new(island:Island, ?parent:h3d.scene.Object) {
		super(parent);
		this.island = island;
		buildTerrain();
		buildProps();
		buildApexFlag();
		buildWater();
		surf = Surf.build(island, this);
		// Everything built so far is "nature" and goes grey in the Sketch style.
		// Things added later (docks, the flag pole) are timber and keep their colour.
		for (m in getMaterials()) m.mainPass.addShader(m == terrainMat || m == waterMat ? sketchTone : sketchProps);
		decals = new Decals(island, this, sketchTone);
		buildFlagPole();
	}

	/** Greys everything for the Sketch style (amount 0 in the others). **/
	public final sketchTone = new SketchTone();
	/** Props go darker than the ground, so trees read as graphite on the page. **/
	public final sketchProps = new SketchTone(1.0, 1.3);
	var terrainMat:h3d.mat.Material;
	var waterMat:h3d.mat.Material;

	function vertex(i:Int, j:Int):Point {
		var he = island.halfExtent;
		return new Point(i * island.cell - he, j * island.cell - he, island.heightAtVertex(i, j));
	}

	/**
		Smooth-shaded terrain: shared vertices, normals from the height
		gradient, and colors blended per vertex. A low-frequency "paint"
		noise varies the tint so it reads hand-painted rather than banded.
	**/
	function buildTerrain() {
		var size = island.size;
		var c = island.cell;
		var paint = new Noise(island.seed + 101);
		var pts = [], nrm = [], cols = [];
		for (j in 0...size + 1)
			for (i in 0...size + 1) {
				var p = vertex(i, j);
				pts.push(p);
				// Central differences → smooth normal.
				var dx = island.heightAtVertex(i + 1, j) - island.heightAtVertex(i - 1, j);
				var dy = island.heightAtVertex(i, j + 1) - island.heightAtVertex(i, j - 1);
				var n = new Point(-dx, -dy, 2 * c);
				n.normalize();
				nrm.push(n);

				var col = Palette.terrain(p.z);
				// Steep slopes pick up a rocky tint, like painted cliffs.
				var steep = 1 - n.z;
				if (p.z > 0.5 && steep > 0.2) col = Palette.mix(col, Palette.ROCK, (steep - 0.2) * 1.6);
				var tint = 0.93 + paint.fbm(p.x * 0.12 + 7, p.y * 0.12 + 7, 3) * 0.14;
				cols.push(new Point(Palette.r(col) * tint, Palette.g(col) * tint, Palette.b(col) * tint));
			}
		var idx = new hxd.IndexBuffer();
		var w = size + 1;
		for (j in 0...size)
			for (i in 0...size) {
				var a = j * w + i, b = a + 1, d = a + w, e = d + 1;
				for (k in [a, b, e, a, e, d]) idx.push(k);
			}
		var poly = new h3d.prim.Polygon(pts, idx);
		poly.normals = nrm;
		poly.colors = cols;
		var m = new h3d.scene.Mesh(poly, this);
		terrainMat = m.material;
		// Shaded by TerrainStyle rather than the scene lights, so the look is fully ours.
		FlatMeshBuilder.setupMaterial(m.material, false);
		terrainStyle.bakeRelief(island);
		m.material.mainPass.addShader(terrainStyle);
		m.material.mainPass.addShader(terrainInk);
		// Hills cast shadows too; receive must be enabled last (see FlatMeshBuilder.shadows).
		FlatMeshBuilder.shadows(m.material, true, true);
	}

	/** Band colours and relief (Classic) or soft vertex colours (Ink). **/
	public final terrainStyle = new TerrainStyle();
	/** Contours, coastline and slope hatching — tweak live via this shader's params. **/
	public final terrainInk = new render.ink.TerrainInk();
	public final waterShader = new WaterShader();

	public function setStyle(style:VisualStyle) {
		terrainStyle.painted = style == Painted ? 1 : 0;
		sketchTone.amount = style == Sketch ? 1 : 0;
		sketchProps.amount = sketchTone.amount;
		waterShader.ruled = style == Sketch ? 0.55 : 0;
		// Surf body: a deeper shade of each style's shallow water.
		if (surf != null) {
			var c = switch style {
				case Classic: 0x3D8FC4;
				case Painted: 0x2F8C9C;
				case InkMap: 0x86AFBC;
				case Sketch: 0xC9CAC7;
			};
			TerrainStyle.setColor(surf.body, c);
			// On paper the grey wave backs read as heavy brush strokes; keep them faint.
			surf.opacity = style == Sketch ? 0.35 : 0.9;
		}
		waterShader.softness = 0;
		switch style {
			case Painted:
				terrainStyle.bands = 0;
				waterShader.setPaintedColors();
				waterShader.softness = 0.45;
				terrainInk.minorAlpha = 0;
				terrainInk.majorAlpha = 0;
				terrainInk.hatchAlpha = 0;
				terrainInk.coastWidth = 0;
				terrainInk.coastLevel = -999;
			case Classic:
				terrainStyle.bands = 1;
				waterShader.setClassicColors();
				terrainInk.minorAlpha = 0;
				terrainInk.majorAlpha = 0;
				terrainInk.hatchAlpha = 0;
				terrainInk.coastWidth = 0;
				terrainInk.coastLevel = -999; // no inked coastline in this style
			case InkMap:
				terrainStyle.bands = 0;
				waterShader.setChartColors();
				terrainInk.minorAlpha = 0.28;
				terrainInk.majorAlpha = 0.55;
				terrainInk.hatchAlpha = 0.3;
				terrainInk.coastWidth = 2.2;
				terrainInk.coastLevel = 0.1;
			case Sketch:
				terrainStyle.bands = 0;
				waterShader.setSketchColors();
				terrainInk.minorAlpha = 0.1;
				terrainInk.majorAlpha = 0.28;
				terrainInk.hatchAlpha = 0.38;
				terrainInk.coastWidth = 1.6;
				terrainInk.coastLevel = 0.1;
		}
	}

	function buildWater() {
		// One smooth grid well past the island so the sea reaches the horizon.
		var segs = 110;
		var extent = island.halfExtent * 6.0;
		var pts = [], cols = [], nrm = [];
		var idx = new hxd.IndexBuffer();
		var up = new Point(0, 0, 1);
		for (j in 0...segs + 1)
			for (i in 0...segs + 1) {
				var x = i / segs * extent * 2 - extent;
				var y = j / segs * extent * 2 - extent;
				pts.push(new Point(x, y, Island.SEA_LEVEL));
				nrm.push(up);
				cols.push(new Point(1, 1, 1));
			}
		for (j in 0...segs)
			for (i in 0...segs) {
				var a = j * (segs + 1) + i;
				var b = a + 1, c = a + segs + 1, d = c + 1;
				for (k in [a, b, d, a, d, c]) idx.push(k);
			}
		var poly = new h3d.prim.Polygon(pts, idx);
		poly.colors = cols;
		poly.normals = nrm;
		var m = new h3d.scene.Mesh(poly, this);
		waterMat = m.material;
		// Opaque, unlit: colour comes entirely from the banded water shader.
		FlatMeshBuilder.setupMaterial(m.material, false);
		waterShader.setIsland(island);
		m.material.mainPass.addShader(waterShader);
		// Trees and cliffs shade the shallows; the sea itself casts nothing.
		FlatMeshBuilder.shadows(m.material, false, true);
	}

	var props:Props.PropGroups;

	var surf:Null<Surf.SurfShader>;

	/** Ground marks (blast craters). **/
	public var decals(default, null):Decals;

	public function update(dt:Float) {}

	/**
		A wooden dock at each landing beach, pointing from the beach out to sea.
		`points` are on land near the shore (the squads' spawn spots).
	**/
	public function addLandings(points:Array<{x:Float, y:Float}>):Array<{x:Float, y:Float}> {
		var ends = [];
		var sp = new SpriteProps();
		var posts = new FlatMeshBuilder();
		for (p in points) {
			// The shortest way to deep water is the dock's direction.
			var best = -1.0, bdx = 1.0, bdy = 0.0;
			for (k in 0...32) {
				var a = k / 32 * Math.PI * 2;
				var dx = Math.cos(a), dy = Math.sin(a);
				var t = 0.0;
				while (t < 30 && island.heightAt(p.x + dx * t, p.y + dy * t) > -0.9) t += 0.25;
				if (t < 30 && (best < 0 || t < best)) {
					best = t;
					bdx = dx;
					bdy = dy;
				}
			}
			if (best < 0) continue;
			// Find the waterline along that direction; the dock starts just above it.
			var t = 0.0;
			while (t < best && island.heightAt(p.x + bdx * t, p.y + bdy * t) > 0.25) t += 0.1;
			var len = 7.5;
			var sx = p.x + bdx * (t - 1.2), sy = p.y + bdy * (t - 1.2);
			var cx = sx + bdx * len / 2, cy = sy + bdy * len / 2;
			var deck = 0.45;
			ends.push({x: sx + bdx * len * 0.7, y: sy + bdy * len * 0.7});
			// Image-up (the shore end) points back toward land.
			sp.add("structures/dock.png", cx, cy, deck, len, 0, Math.atan2(bdx, -bdy), 1.0);
			// Pilings along both sides, down into the water.
			var sideX = -bdy, sideY = bdx;
			var k = 0.0;
			while (k <= len) {
				for (side in [-1.25, 1.25]) {
					var px = sx + bdx * k + sideX * side, py = sy + bdy * k + sideY * side;
					var ground = island.heightAt(px, py);
					posts.prism(px, py, Math.min(ground, -0.2) - 0.3, 0.09, deck - Math.min(ground, -0.2) + 0.25, 6, Palette.shade(Palette.TRUNK, 0.8));
				}
				k += 2.4;
			}
		}
		var docks = new h3d.scene.Object(this);
		sp.build(docks, true);
		posts.build(docks, true, true, true);
		return ends;
	}

	function buildProps() {
		props = Props.build(island, this);
	}

	/** Painted sprite trees/bushes/boulders, or the low-poly versions. **/
	public function setSpriteProps(on:Bool) {
		props.sprites.visible = on;
		props.lowPoly.visible = !on;
	}

	/** The flag pole is timber: built after the Sketch tone is applied, so it keeps its colour. **/
	function buildFlagPole() {
		var b = new FlatMeshBuilder();
		b.prism(island.apexX, island.apexY, island.apexH - 0.05 + 0.4, 0.05, 2.6, 5, Palette.WOOD);
		b.build(this, true, true, true);
	}

	function buildApexFlag() {
		var b = new FlatMeshBuilder();
		var x = island.apexX, y = island.apexY, z = island.apexH - 0.05;
		// Stone cairn + pole + neutral banner, waiting to be claimed.
		b.cone(x, y, z, 0.7, 0.45, 6, Palette.STONE, 0.45);
		var top = z + 2.9;
		var f0 = new Point(x, y, top), f1 = new Point(x + 1.1, y + 0.15, top - 0.35), f2 = new Point(x, y, top - 0.7);
		b.tri(f0, f1, f2, 0xEFE8D8);
		b.tri(f0, f2, f1, 0xEFE8D8); // two-sided cloth
		b.build(this, true, true, true);
	}
}
