package render;

import h3d.col.Point;
import world.Island;
import world.Noise;

/**
	Turns an Island heightfield into the stylized scene: faceted terrain,
	depth-tinted animated water, scattered pines and rocks, and the apex flag.
**/
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

	function buildTerrain() {
		var b = new FlatMeshBuilder();
		var jitter = new Noise(island.seed + 101);
		for (j in 0...island.size)
			for (i in 0...island.size) {
				var p00 = vertex(i, j), p10 = vertex(i + 1, j);
				var p01 = vertex(i, j + 1), p11 = vertex(i + 1, j + 1);
				// Alternate the diagonal for a less grid-like faceting.
				var flip = ((i + j) & 1) == 0;
				var ta = flip ? [p00, p10, p11] : [p00, p10, p01];
				var tb = flip ? [p00, p11, p01] : [p10, p11, p01];
				for (t in [ta, tb]) {
					var h = (t[0].z + t[1].z + t[2].z) / 3;
					var shade = 0.94 + jitter.rand(i * 2 + (t == ta ? 0 : 1), j) * 0.1;
					b.tri(t[0], t[1], t[2], Palette.terrain(h), shade);
				}
			}
		b.build(this);
	}

	function buildWater() {
		// One smooth grid well past the island so the sea reaches the horizon.
		var segs = 80;
		var extent = island.halfExtent * 3.0;
		var pts = [], cols = [], nrm = [];
		var idx = new hxd.IndexBuffer();
		var up = new Point(0, 0, 1);
		for (j in 0...segs + 1)
			for (i in 0...segs + 1) {
				var x = i / segs * extent * 2 - extent;
				var y = j / segs * extent * 2 - extent;
				pts.push(new Point(x, y, Island.SEA_LEVEL));
				nrm.push(up);
				var depth = Island.SEA_LEVEL - island.heightAt(x, y);
				var c = Palette.water(depth);
				cols.push(new Point(Palette.r(c), Palette.g(c), Palette.b(c)));
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
		FlatMeshBuilder.setupMaterial(m.material, true);
		m.material.blendMode = Alpha;
		m.material.color.set(1, 1, 1, 0.82);
		m.material.mainPass.depthWrite = false;
		m.material.specularAmount = 0.25;
		m.material.mainPass.addShader(new WaterShader());
	}

	function buildProps() {
		var b = new FlatMeshBuilder();
		var density = new Noise(island.seed + 202);
		var rnd = new Noise(island.seed + 303);
		var he = island.halfExtent;
		// Scatter on a half-cell lattice with jitter.
		var step = island.cell * 0.9;
		var n = Std.int(island.size * island.cell / step);
		for (j in 0...n)
			for (i in 0...n) {
				var x = i * step - he + (rnd.rand(i, j) - 0.5) * step;
				var y = j * step - he + (rnd.rand(j + 991, i) - 0.5) * step;
				var h = island.heightAt(x, y);
				var d = density.fbm(x * 0.08 + 3, y * 0.08 + 3, 3);
				var r = rnd.rand(i + 5000, j);
				if (h > 1.2 && h < 4.4 && d > 0.5 && r < 0.7) {
					pine(b, x, y, h - 0.05, 0.75 + rnd.rand(i, j + 7000) * 0.6, r);
				} else if (h > 4.2 && r < 0.18) {
					rock(b, x, y, h - 0.1, 0.4 + r * 2.0, r);
				} else if (h > 0.4 && h < 1.1 && r < 0.03) {
					rock(b, x, y, h - 0.1, 0.25 + r * 4.0, r);
				}
			}
		b.build(this);
	}

	function pine(b:FlatMeshBuilder, x:Float, y:Float, z:Float, s:Float, r:Float) {
		var rot = r * Math.PI;
		b.prism(x, y, z, 0.09 * s, 0.45 * s, 5, Palette.TRUNK, rot);
		var c1 = r < 0.5 ? Palette.PINE_A : Palette.PINE_B;
		var c2 = r < 0.5 ? Palette.PINE_B : Palette.PINE_A;
		b.cone(x, y, z + 0.35 * s, 0.62 * s, 1.0 * s, 6, c1, 0, rot);
		b.cone(x, y, z + 0.85 * s, 0.45 * s, 0.85 * s, 6, c2, 0, rot + 0.4);
	}

	function rock(b:FlatMeshBuilder, x:Float, y:Float, z:Float, s:Float, r:Float) {
		b.cone(x, y, z, 0.6 * s, 0.35 * s, 5, Palette.STONE, 0.3 * s, r * 6);
	}

	function buildApexFlag() {
		var b = new FlatMeshBuilder();
		var x = island.apexX, y = island.apexY, z = island.apexH - 0.05;
		// Stone cairn + pole + neutral banner, waiting to be claimed.
		b.cone(x, y, z, 0.7, 0.45, 6, Palette.STONE, 0.45);
		b.prism(x, y, z + 0.4, 0.05, 2.6, 5, Palette.WOOD);
		var top = z + 2.9;
		b.tri(new Point(x, y, top), new Point(x + 1.1, y + 0.15, top - 0.35), new Point(x, y, top - 0.7), 0xEFE8D8);
		b.build(this);
	}
}
