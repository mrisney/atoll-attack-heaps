package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Marks left on the ground, starting with blast craters.

	A decal is a small grid draped over the terrain (each vertex sampled from
	the heightfield, nudged up a few centimetres), with an alpha-blended
	texture. The crater texture is painted in code: a scorched centre, a ring
	of thrown soil and flecks, and a soft edge. All craters share one batch per
	island, rebuilt when one is added (cheap at these counts).
**/
class Decals extends h3d.scene.Object {
	static var craterTex:Null<h3d.mat.Texture> = null;
	static inline var GRID = 10;

	final island:world.Island;
	final craters:Array<{x:Float, y:Float, r:Float, rot:Float}> = [];
	var mesh:Null<h3d.scene.Mesh> = null;

	final tone:Null<hxsl.Shader>;

	public function new(island:world.Island, ?parent:h3d.scene.Object, ?tone:hxsl.Shader) {
		super(parent);
		this.island = island;
		this.tone = tone;
	}

	public function crater(x:Float, y:Float, radius:Float) {
		craters.push({x: x, y: y, r: radius, rot: (craters.length * 2.399) % (Math.PI * 2)});
		// A long bombardment would pile them up: keep the latest.
		if (craters.length > 80) craters.shift();
		rebuild();
	}

	function rebuild() {
		if (mesh != null) mesh.remove();
		var pts:Array<Point> = [], uvs:Array<UV> = [], cols:Array<Point> = [];
		var idx = new hxd.IndexBuffer();
		var white = new Point(1, 1, 1);
		for (c in craters) {
			var base = pts.length;
			var cs = Math.cos(c.rot), sn = Math.sin(c.rot);
			for (j in 0...GRID + 1)
				for (i in 0...GRID + 1) {
					var u = i / GRID * 2 - 1, v = j / GRID * 2 - 1;
					var lx = u * c.r, ly = v * c.r;
					var wx = c.x + lx * cs - ly * sn, wy = c.y + lx * sn + ly * cs;
					// Drape over terrain, but never sink below the water surface.
					var z = Math.max(island.heightAt(wx, wy), 0.02) + 0.04;
					pts.push(new Point(wx, wy, z));
					uvs.push(new UV((u + 1) * 0.5, (v + 1) * 0.5));
					cols.push(white);
				}
			var w = GRID + 1;
			for (j in 0...GRID)
				for (i in 0...GRID) {
					var a = base + j * w + i, b = a + 1, d = a + w, e = d + 1;
					for (k in [a, b, e, a, e, d]) idx.push(k);
				}
		}
		if (pts.length == 0) return;
		var poly = new h3d.prim.Polygon(pts, idx);
		poly.uvs = uvs;
		poly.colors = cols;
		mesh = new h3d.scene.Mesh(poly, this);
		var mat = mesh.material;
		FlatMeshBuilder.setupMaterial(mat, false);
		mat.texture = texture();
		mat.blendMode = Alpha;
		mat.mainPass.depthWrite = false;
		mat.mainPass.culling = None;
		if (tone != null) mat.mainPass.addShader(tone);
		FlatMeshBuilder.shadows(mat, false, true);
	}

	/** Paint the crater texture once: scorch, thrown soil, flecks, soft edge. **/
	static function texture():h3d.mat.Texture {
		if (craterTex != null) return craterTex;
		var size = 128;
		var px = hxd.Pixels.alloc(size, size, RGBA);
		var n = new world.Noise(4141);
		for (y in 0...size)
			for (x in 0...size) {
				var u = (x + 0.5) / size * 2 - 1, v = (y + 0.5) / size * 2 - 1;
				var ang = Math.atan2(v, u);
				// Ragged outline: radius wobbles with angle.
				var wob = 1 + (n.fbm(Math.cos(ang) * 2 + 5, Math.sin(ang) * 2 + 5, 3) - 0.5) * 0.45;
				var d = Math.sqrt(u * u + v * v) / wob;
				var grain = n.fbm(u * 9 + 11, v * 9 + 11, 3);
				var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
				if (d < 0.38) {
					// Scorched pit.
					var k = 0.16 + grain * 0.12;
					r = k * 1.05;
					g = k;
					b = k * 0.9;
					a = 0.92;
				} else if (d < 0.78) {
					// Thrown soil, lighter toward the rim, streaked radially.
					var t = (d - 0.38) / 0.4;
					var streak = n.fbm(ang * 6 + 3, d * 3, 2);
					var k = 0.28 + t * 0.18 + streak * 0.12;
					r = k * 1.25;
					g = k;
					b = k * 0.72;
					a = 0.85 * (1 - t * 0.35);
				} else if (d < 1.0) {
					// Soft fade with scattered flecks.
					var t = (d - 0.78) / 0.22;
					var fleck = grain > 0.62 ? 0.6 : 0.0;
					r = 0.38;
					g = 0.3;
					b = 0.22;
					a = (1 - t) * 0.35 + fleck * (1 - t);
				}
				inline function c8(f:Float) return Std.int(Math.max(0, Math.min(1, f)) * 255);
				px.setPixel(x, y, (c8(a) << 24) | (c8(r) << 16) | (c8(g) << 8) | c8(b));
			}
		var t = new h3d.mat.Texture(size, size, [MipMapped]);
		t.uploadPixels(px);
		t.mipMap = Linear;
		t.filter = Linear;
		t.wrap = Clamp;
		craterTex = t;
		return t;
	}
}
