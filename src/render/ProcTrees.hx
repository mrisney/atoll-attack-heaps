package render;

import h3d.col.Point;
import h3d.prim.UV;
import render.TreeGen.TreeOptions;
import render.TreeGen.TreeMesh;

enum TreeSpecies {
	Oak;
	Ash;
	Aspen;
	Pine;
}

/**
	3D procedural trees for the island (EZ-Tree's generator, see TreeGen).

	A few templates per species are grown once (cached across islands). Each
	tree on the island picks a template, a heading, a size and a tint, and is
	merged into a handful of big meshes: bark (lit, bark texture) and leaves
	(alpha-cut sprig texture, rounded normals so the crown shades like a
	volume, darker inside, gentle sway). Both cast and receive shadows.

	The presets come from EZ-Tree's oak/ash/aspen/pine "medium" presets, with
	fewer, larger leaf cards so a whole island stays cheap from the RTS camera.
**/
class ProcTrees {
	static inline var MAX_VERTS = 60000;
	static inline var TEMPLATES = 4;
	static var templates:Array<Null<Array<TreeMesh>>> = [null, null, null, null];
	static var leafTex:Array<Null<h3d.mat.Texture>> = [null, null];
	static var barkTex:Null<h3d.mat.Texture> = null;

	final bark = new Batch();
	final leaves = new Batch();
	final needles = new Batch();
	public var count(default, null) = 0;

	public function new() {}

	/**
		Plant a tree with its base at (x, y, z).
		@param scale  1 = the species' normal height
		@param leaf   leaf colour; @param barkCol bark colour
	**/
	public function add(species:TreeSpecies, x:Float, y:Float, z:Float, scale:Float, yaw:Float, variant:Int, leaf:Int, barkCol:Int) {
		var list = template(species);
		var t = list[variant % list.length];
		var c = Math.cos(yaw) * scale, s = Math.sin(yaw) * scale;
		var cr = Math.cos(yaw), sr = Math.sin(yaw);
		inline function tx(px:Float, py:Float) return x + px * c - py * s;
		inline function ty(px:Float, py:Float) return y + px * s + py * c;

		// Bark.
		var b = bark;
		if (b.pts.length + Std.int(t.barkPos.length / 3) > MAX_VERTS) b.flush();
		var base = b.pts.length;
		var br = Palette.r(barkCol), bg = Palette.g(barkCol), bb = Palette.b(barkCol);
		var i = 0;
		while (i < t.barkPos.length) {
			var vx = t.barkPos[i], vy = t.barkPos[i + 1], vz = t.barkPos[i + 2];
			b.pts.push(new Point(tx(vx, vy), ty(vx, vy), z - 0.08 + vz * scale));
			var nx = t.barkNrm[i], ny = t.barkNrm[i + 1];
			b.nrm.push(new Point(nx * cr - ny * sr, nx * sr + ny * cr, t.barkNrm[i + 2]));
			var j = Std.int(i / 3) * 2;
			b.uvs.push(new UV(t.barkUv[j], t.barkUv[j + 1] * scale * 0.9));
			// Darker toward the ground (cheap occlusion).
			var ao = 0.65 + 0.35 * Math.min(1, vz * scale / 1.2);
			b.col.push(new Point(br * ao, bg * ao, bb * ao));
			i += 3;
		}
		for (k in t.barkIdx) b.idx.push(base + k);

		// Leaves.
		var L = species == Pine ? needles : leaves;
		if (L.pts.length + Std.int(t.leafPos.length / 3) > MAX_VERTS) L.flush();
		base = L.pts.length;
		var lr = Palette.r(leaf), lg = Palette.g(leaf), lb = Palette.b(leaf);
		i = 0;
		while (i < t.leafPos.length) {
			var vx = t.leafPos[i], vy = t.leafPos[i + 1], vz = t.leafPos[i + 2];
			L.pts.push(new Point(tx(vx, vy), ty(vx, vy), z - 0.08 + vz * scale));
			var nx = t.leafNrm[i], ny = t.leafNrm[i + 1];
			L.nrm.push(new Point(nx * cr - ny * sr, nx * sr + ny * cr, t.leafNrm[i + 2]));
			var j = Std.int(i / 3);
			L.uvs.push(new UV(t.leafUv[j * 2], t.leafUv[j * 2 + 1]));
			var sh = 0.5 + 0.5 * t.leafShade[j];
			L.col.push(new Point(lr * sh, lg * sh, lb * sh));
			i += 3;
		}
		for (k in t.leafIdx) L.idx.push(base + k);
		count++;
	}

	public function build(parent:h3d.scene.Object) {
		for (p in bark.done()) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			m.material.texture = barkTexture();
			FlatMeshBuilder.shadows(m.material, true, true);
		}
		for (pair in [{b: leaves, pine: false}, {b: needles, pine: true}])
			for (p in pair.b.done()) {
				var m = new h3d.scene.Mesh(p, parent);
				var mat = m.material;
				FlatMeshBuilder.setupMaterial(mat, true);
				mat.texture = leafTexture(pair.pine);
				mat.textureShader.killAlpha = true;
				mat.textureShader.killAlphaThreshold = 0.5;
				mat.mainPass.culling = None;
				mat.mainPass.addShader(new SwayShader(0.04, 0.9));
				FlatMeshBuilder.shadows(mat, true, true);
			}
	}

	// --- species --------------------------------------------------------------

	static function template(sp:TreeSpecies):Array<TreeMesh> {
		var t = templates[sp.getIndex()];
		if (t != null) return t;
		t = [];
		for (v in 0...TEMPLATES) {
			var o = options(sp, 1000 + v * 7919 + sp.getIndex() * 31);
			var h = switch sp {
				case Oak: 3.8;
				case Ash: 4.3;
				case Aspen: 4.8;
				case Pine: 5.0;
			};
			t.push(new TreeGen(o).mesh(h * (0.9 + 0.2 * (v / (TEMPLATES - 1)))));
		}
		templates[sp.getIndex()] = t;
		return t;
	}

	/** EZ-Tree's medium presets, with fewer and larger leaf cards (`count` down, `size` up). **/
	static function options(sp:TreeSpecies, seed:Int):TreeOptions {
		return switch sp {
			case Oak: {
					seed: seed, evergreen: false, levels: 3,
					angle: [0, 54, 58, 32], children: [5, 3, 2], forceStrength: 0.02,
					gnarliness: [0, -0.1, -0.15, 0.09], length: [37.24, 11.08, 12.39, 7.16],
					radius: [1.41, 0.9, 0.69, 1.19], sections: [6, 4, 2, 1], segments: [6, 4, 3, 3],
					start: [0, 0.49, 0.06, 0.12], taper: [0.73, 0.42, 0.69, 0.75], twist: [-0.23, 0.42, 0, 0],
					leafAngle: 42, leafCount: 7, leafStart: 0.16, leafSize: 7.4, leafSizeVariance: 0.5
				};
			case Ash: {
					seed: seed, evergreen: false, levels: 3,
					angle: [0, 48, 75, 60], children: [6, 3, 2], forceStrength: 0.01,
					gnarliness: [0.03, 0.25, 0.2, 0.09], length: [43.47, 27.14, 9.51, 4.6],
					radius: [2, 0.63, 0.76, 0.7], sections: [7, 4, 2, 1], segments: [6, 4, 3, 3],
					start: [0, 0.23, 0.33, 0], taper: [0.7, 0.7, 0.7, 0.7], twist: [0.09, -0.07, 0, 0],
					leafAngle: 55, leafCount: 7, leafStart: 0, leafSize: 7.6, leafSizeVariance: 0.5
				};
			case Aspen: {
					seed: seed, evergreen: false, levels: 2,
					angle: [0, 75, 32, 7], children: [10, 3, 3], forceStrength: 0.0148,
					gnarliness: [0.05, 0.12, 0.12, 0.02], length: [50, 6.07, 11.19, 1],
					radius: [0.72, 0.41, 0.7, 0.7], sections: [8, 4, 3, 2], segments: [6, 4, 3, 3],
					start: [0, 0.59, 0.35, 0], taper: [0.37, 0.13, 0.7, 0.7], twist: [0, 0, 0, 0],
					leafAngle: 30, leafCount: 8, leafStart: 0.124, leafSize: 5.2, leafSizeVariance: 0.5
				};
			case Pine: {
					seed: seed, evergreen: true, levels: 1,
					angle: [0, 110, 16, 60], children: [34, 3, 5], forceStrength: -0.003,
					gnarliness: [0.05, 0.08, 0, 0], length: [50, 23.87, 14.08, 1],
					radius: [1.05, 0.36, 0.7, 0.7], sections: [8, 3, 4, 3], segments: [6, 3, 3, 3],
					start: [0, 0.27, 0.14, 0.3], taper: [0.7, 0.7, 0.7, 0.7], twist: [0, 0, 0, 0],
					leafAngle: 39, leafCount: 9, leafStart: 0.09, leafSize: 3.6, leafSizeVariance: 0.2
				};
		};
	}

	// --- textures (painted in code) ---------------------------------------------

	/**
		A leaf card: a sprig of leaves on a twig (broadleaf), or a fan of needles
		(pine). White-ish green, so the vertex colour sets the tree's tint.
		Transparent texels carry the leaf colour too, so mipmaps don't halo.
	**/
	static function leafTexture(pine:Bool):h3d.mat.Texture {
		var t = leafTex[pine ? 1 : 0];
		if (t != null) return t;
		var S = 128;
		var px = hxd.Pixels.alloc(S, S, RGBA);
		var n = new world.Noise(pine ? 515 : 313);
		inline function c8(v:Float) return Std.int(Math.max(0, Math.min(1, v)) * 255 + 0.5);
		for (y in 0...S)
			for (x in 0...S) {
				var u = (x + 0.5) / S, v = (y + 0.5) / S; // v = 0 at the tip, 1 at the stem
				var a = 0.0, shade = 0.85;
				var cxv = u - 0.5;
				if (pine) {
					// Needles fan out from a central twig, longer in the middle.
					var along = 1 - v;
					var twig = Math.abs(cxv) < 0.018 + 0.01 * v;
					var ang = Math.atan2(cxv, along + 0.05);
					var k = Math.abs(Math.sin(ang * 26 + along * 4));
					var reach = 0.48 * Math.sin(Math.PI * Math.min(1, along * 1.05 + 0.02));
					if (twig && along > 0.02) {
						a = 1;
						shade = 0.55;
					} else if (Math.abs(cxv) < reach && k > 0.72) {
						a = 1;
						shade = 0.7 + 0.3 * k;
					}
				} else {
					// A twig up the middle with paired leaves (ellipses angled toward the tip).
					var twig = Math.abs(cxv) < 0.012 && v > 0.08;
					if (twig) {
						a = 1;
						shade = 0.5;
					}
					for (i in 0...7) {
						var lv = 0.12 + i * 0.12; // attachment along the twig
						var side = i % 2 == 0 ? -1.0 : 1.0;
						var len = 0.26 - Math.abs(lv - 0.45) * 0.18 + n.rand(i, 3) * 0.06;
						var wid = len * 0.42;
						var ang = side * (0.75 + n.rand(i, 7) * 0.3);
						// leaf frame: origin at the twig, pointing out and up (toward v = 0)
						var dx = cxv, dy = lv - v;
						var ca = Math.cos(ang), sa = Math.sin(ang);
						var lx = dx * ca + dy * sa; // across the leaf
						var ly = -dx * sa + dy * ca; // along the leaf
						var e = (lx * lx) / (wid * wid * 0.25) + Math.pow((ly - len * 0.5) / (len * 0.5), 2);
						if (e < 1 && ly > 0) {
							a = 1;
							var vein = Math.abs(lx) < 0.006 ? 0.85 : 1.0;
							shade = (0.78 + 0.22 * (1 - e) + 0.06 * (n.rand(i, 11) - 0.5)) * vein;
						}
					}
					// The tip leaf.
					var e = (cxv * cxv) / (0.05 * 0.05) + Math.pow((v - 0.12) / 0.12, 2);
					if (e < 1) {
						a = 1;
						shade = 0.8 + 0.2 * (1 - e);
					}
				}
				var r = 0.86 * shade, g = 0.96 * shade, b = 0.78 * shade;
				px.setPixel(x, y, (c8(a) << 24) | (c8(r) << 16) | (c8(g) << 8) | c8(b));
			}
		t = new h3d.mat.Texture(S, S, [MipMapped]);
		t.uploadPixels(px);
		t.mipMap = Linear;
		t.filter = Linear;
		t.wrap = Clamp;
		leafTex[pine ? 1 : 0] = t;
		return t;
	}

	/** Bark: vertical fissures with plates between, tileable, white-ish (tinted per tree). **/
	static function barkTexture():h3d.mat.Texture {
		if (barkTex != null) return barkTex;
		var W = 64, H = 128;
		var px = hxd.Pixels.alloc(W, H, RGBA);
		var n = new world.Noise(808);
		inline function c8(v:Float) return Std.int(Math.max(0, Math.min(1, v)) * 255 + 0.5);
		for (y in 0...H)
			for (x in 0...W) {
				var u = x / W, v = y / H;
				// Wavy vertical furrows (8 around the trunk), tileable in both directions.
				var wob = (n.fbm(Math.cos(v * Math.PI * 2) * 2 + 9, Math.sin(v * Math.PI * 2) * 2 + 9, 3) - 0.5) * 0.35;
				var f = Math.abs(Math.sin((u * 8 + wob) * Math.PI));
				var furrow = Math.pow(f, 0.6);
				var grain = n.fbm(Math.cos(u * Math.PI * 2) * 3 + v * 6, Math.sin(u * Math.PI * 2) * 3, 3);
				var s = 0.55 + 0.35 * furrow + 0.2 * (grain - 0.5);
				px.setPixel(x, y, 0xFF000000 | (c8(s) << 16) | (c8(s * 0.97) << 8) | c8(s * 0.92));
			}
		var t = new h3d.mat.Texture(W, H, [MipMapped]);
		t.uploadPixels(px);
		t.mipMap = Linear;
		t.filter = Linear;
		t.wrap = Repeat;
		barkTex = t;
		return t;
	}
}

private class Batch {
	public var pts:Array<Point> = [];
	public var nrm:Array<Point> = [];
	public var col:Array<Point> = [];
	public var uvs:Array<UV> = [];
	public var idx:Array<Int> = [];
	final chunks:Array<h3d.prim.Polygon> = [];

	public function new() {}

	public function flush() {
		if (pts.length == 0) return;
		var ib = new hxd.IndexBuffer();
		for (k in idx) ib.push(k);
		var p = new h3d.prim.Polygon(pts, ib);
		p.normals = nrm;
		p.colors = col;
		p.uvs = uvs;
		chunks.push(p);
		pts = [];
		nrm = [];
		col = [];
		uvs = [];
		idx = [];
	}

	public function done():Array<h3d.prim.Polygon> {
		flush();
		return chunks;
	}
}
