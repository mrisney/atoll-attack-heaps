package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Props drawn from painted top-down sprites (res/props).

	Each sprite is mapped onto a shallow dome: a small grid whose middle is
	raised. From the tilted RTS camera the painted top reads as a rounded 3D
	canopy (or bush or boulder), and the dome's slope gives real lighting a
	little form on top of the sprite's own painted light. Transparent pixels
	are discarded (alpha test), so the silhouette is the sprite's own leafy
	outline. Because the shadow pass uses the same test, the cast shadow has
	that shape too.

	All instances of one sprite are merged into one mesh, so a few hundred
	trees cost one draw call per sprite.
**/
class SpriteProps {
	static var textures:Map<String, h3d.mat.Texture> = new Map();

	/** Load (once) a sprite from res/ as a mipmapped texture. **/
	public static function texture(path:String):h3d.mat.Texture {
		var t = textures.get(path);
		if (t != null) return t;
		var px = hxd.Res.load(path).toImage().getPixels();
		px.convert(RGBA);
		bleedEdges(px);
		t = new h3d.mat.Texture(px.width, px.height, [MipMapped]);
		t.uploadPixels(px);
		t.wrap = Clamp;
		t.filter = Linear;
		t.mipMap = Linear;
		textures.set(path, t);
		return t;
	}

	/**
		Transparent pixels in the sprites carry a light colour, which mipmapping
		and filtering smear into a pale fringe around every canopy. Spread the
		nearest opaque colour outward into the transparent area (alpha untouched),
		so the edges blend into leaf colour instead.
	**/
	static function bleedEdges(px:hxd.Pixels) {
		var w = px.width, h = px.height;
		var solid = [for (i in 0...w * h) (px.getPixel(i % w, Std.int(i / w)) >>> 24) > 100];
		// The 2D art has a 1 px pale cut-out outline. It reads as a crisp edge on a
		// flat background but as a halo in 3D, so trim that outer pixel first.
		var rim = [];
		for (y in 0...h)
			for (x in 0...w) {
				if (!solid[y * w + x]) continue;
				for (d in [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
					var nx = x + d[0], ny = y + d[1];
					if (nx < 0 || ny < 0 || nx >= w || ny >= h || !solid[ny * w + nx]) {
						rim.push(y * w + x);
						break;
					}
				}
			}
		for (i in rim) {
			solid[i] = false;
			px.setPixel(i % w, Std.int(i / w), px.getPixel(i % w, Std.int(i / w)) & 0x00FFFFFF);
		}
		for (pass in 0...6) {
			var next = solid.copy();
			for (y in 0...h)
				for (x in 0...w) {
					if (solid[y * w + x]) continue;
					var r = 0, g = 0, b = 0, n = 0;
					for (d in [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
						var nx = x + d[0], ny = y + d[1];
						if (nx < 0 || ny < 0 || nx >= w || ny >= h || !solid[ny * w + nx]) continue;
						var c = px.getPixel(nx, ny);
						r += (c >> 16) & 0xFF;
						g += (c >> 8) & 0xFF;
						b += c & 0xFF;
						n++;
					}
					if (n == 0) continue;
					var a = px.getPixel(x, y) & 0xFF000000;
					px.setPixel(x, y, a | (Std.int(r / n) << 16) | (Std.int(g / n) << 8) | Std.int(b / n));
					next[y * w + x] = true;
				}
			solid = next;
		}
	}

	final batches:Map<String, Batch> = new Map();

	public function new() {}

	/**
		Add a domed sprite.
		@param size   footprint diameter in world units (the sprite's larger side)
		@param z      base height of the dome
		@param dome   how much the middle rises above `z`
		@param yaw    rotation around the vertical (sprites are top-down, so any angle works)
	**/
	public function add(path:String, x:Float, y:Float, z:Float, size:Float, dome:Float, yaw:Float, tint = 1.0) {
		var b = batches.get(path);
		if (b == null) {
			b = new Batch(path);
			batches.set(path, b);
		}
		b.addDome(x, y, z, size, dome, yaw, tint);
	}

	public function build(parent:h3d.scene.Object, castShadow = true) {
		for (b in batches)
			b.build(parent, castShadow);
	}
}

private class Batch {
	static inline var GRID = 8;

	final path:String;
	final pts:Array<Point> = [];
	final nrm:Array<Point> = [];
	final uvs:Array<UV> = [];
	final col:Array<Point> = [];
	final idx = new hxd.IndexBuffer();
	final aspect:Float;

	public function new(path:String) {
		this.path = path;
		var t = SpriteProps.texture(path);
		aspect = t.height / t.width;
	}

	public function addDome(cx:Float, cy:Float, cz:Float, size:Float, dome:Float, yaw:Float, tint:Float) {
		var rx = size * 0.5, ry = size * 0.5;
		if (aspect > 1) rx /= aspect else ry *= aspect;
		var c = Math.cos(yaw), s = Math.sin(yaw);
		var base = pts.length;
		var tc = new Point(tint, tint, tint);
		for (j in 0...GRID + 1)
			for (i in 0...GRID + 1) {
				var u = i / GRID * 2 - 1, v = j / GRID * 2 - 1;
				// A smooth paraboloid over the whole square (corners included), so there's
				// no fold where the painted canopy crosses a dome edge.
				var r2 = (u * u + v * v) * 0.5;
				var h = dome * (1 - r2);
				var gx = u * dome / rx, gy = v * dome / ry;
				var lx = u * rx, ly = v * ry;
				pts.push(new Point(cx + lx * c - ly * s, cy + lx * s + ly * c, cz + h));
				var n = new Point(gx * c - gy * s, gx * s + gy * c, 1);
				n.normalize();
				nrm.push(n);
				// Image rows run top to bottom; flip v so the sprite isn't mirrored.
				uvs.push(new UV((u + 1) * 0.5, 1 - (v + 1) * 0.5));
				col.push(tc);
			}
		var w = GRID + 1;
		for (j in 0...GRID)
			for (i in 0...GRID) {
				var a = base + j * w + i, b = a + 1, d = a + w, e = d + 1;
				// Counter-clockwise seen from above, so the top is the front face.
				for (k in [a, b, e, a, e, d]) idx.push(k);
			}
	}

	public function build(parent:h3d.scene.Object, castShadow:Bool) {
		if (pts.length == 0) return;
		var poly = new h3d.prim.Polygon(pts, idx);
		poly.normals = nrm;
		poly.uvs = uvs;
		poly.colors = col;
		var m = new h3d.scene.Mesh(poly, parent);
		FlatMeshBuilder.setupMaterial(m.material, true);
		m.material.texture = SpriteProps.texture(path);
		m.material.textureShader.killAlpha = true;
		m.material.textureShader.killAlphaThreshold = 0.5;
		// Foliage ripples gently in the breeze; rocks, logs, docks and boats don't.
		var sway = if (path.indexOf("canopy") >= 0) 0.05 else if (path.indexOf("waterline") >= 0) 0.06 else if (path.indexOf("bush") >= 0
			|| path.indexOf("vine-mat") >= 0) 0.03 else 0.0;
		if (sway > 0) m.material.mainPass.addShader(new SwayShader(sway));
		FlatMeshBuilder.shadows(m.material, castShadow, true);
	}
}
