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
	}

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
		// Opaque, unlit: colour comes entirely from the banded water shader.
		FlatMeshBuilder.setupMaterial(m.material, false);
		waterShader.setIsland(island);
		m.material.mainPass.addShader(waterShader);
		// Trees and cliffs shade the shallows; the sea itself casts nothing.
		FlatMeshBuilder.shadows(m.material, false, true);
	}

	var props:Props.PropGroups;

	function buildProps() {
		props = Props.build(island, this);
	}

	/** Painted sprite trees/bushes/boulders, or the low-poly versions. **/
	public function setSpriteProps(on:Bool) {
		props.sprites.visible = on;
		props.lowPoly.visible = !on;
	}

	function buildApexFlag() {
		var b = new FlatMeshBuilder();
		var x = island.apexX, y = island.apexY, z = island.apexH - 0.05;
		// Stone cairn + pole + neutral banner, waiting to be claimed.
		b.cone(x, y, z, 0.7, 0.45, 6, Palette.STONE, 0.45);
		b.prism(x, y, z + 0.4, 0.05, 2.6, 5, Palette.WOOD);
		var top = z + 2.9;
		var f0 = new Point(x, y, top), f1 = new Point(x + 1.1, y + 0.15, top - 0.35), f2 = new Point(x, y, top - 0.7);
		b.tri(f0, f1, f2, 0xEFE8D8);
		b.tri(f0, f2, f1, 0xEFE8D8); // two-sided cloth
		b.build(this, true, true, true);
	}
}
