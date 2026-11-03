package render;

import h3d.col.Point;

/**
	Procedural boulders: real 3D rock geometry instead of sprites.

	Each rock starts as a subdivided icosphere. Then:
	- its radius is pushed in and out by 3D noise (lumps and hollows);
	- two or three random planes slice it flat (chiselled faces, as rock fractures);
	- it's stretched wider than tall and turned to a random heading;
	- normals are smoothed, so it reads as a solid stone, not a faceted gem;
	- vertex colour darkens the base and the hollows (cheap ambient occlusion);
	- it's sunk about a third into the ground, so it sits in the terrain
	  instead of on it.

	The surface uses the painted rock texture from GroundTextures, projected
	from three sides (triplanar) so it never stretches. Lit by the real sun, so
	every rock agrees with the scene's light, which the sprite boulders
	(with painted-in light) couldn't.

	All rocks share a few big meshes.
**/
class Rocks {
	static inline var MAX_VERTS = 60000;
	static var templates:Map<Int, {verts:Array<Point>, tris:Array<Int>}> = new Map();

	final chunks:Array<h3d.prim.Polygon> = [];
	var pts:Array<Point> = [];
	var nrm:Array<Point> = [];
	var col:Array<Point> = [];
	var idx:Array<Int> = [];
	var count = 0;

	public function new() {}

	/**
		Add a rock.
		@param size   overall diameter in world units
		@param seed   any integer; every seed gives a different rock
		@param ground height of the ground at (x, y)
	**/
	public function add(x:Float, y:Float, ground:Float, size:Float, seed:Int, tint:Int) {
		var t = template(size > 0.7 ? 3 : size > 0.3 ? 2 : 1);
		if (pts.length + t.verts.length > MAX_VERTS) flush();
		var rnd = (k:Int) -> hash3(seed, k, 77);

		// Shape parameters.
		var rx = size * 0.5 * (0.85 + rnd(1) * 0.4);
		var ry = size * 0.5 * (0.75 + rnd(2) * 0.35);
		var rz = size * 0.5 * (0.5 + rnd(3) * 0.3);
		var yaw = rnd(4) * Math.PI * 2;
		var cs = Math.cos(yaw), sn = Math.sin(yaw);
		var off = rnd(6) * 100;

		// gl-rock's scraping (Erkaman/gl-rock, MIT): pick spots on the sphere at least
		// `minDist` apart, and flatten the vertices around each onto a plane pushed
		// `strength` into the rock, only within `radius` of the spot (flood fill over
		// the mesh). Several local flats give chipped facets between rounded parts,
		// which reads much more like a real boulder than whole-rock slices.
		var sphere = [for (v in t.verts) new Point(v.x, v.y, v.z)];
		var normals = [for (v in t.verts) new Point(v.x, v.y, v.z)];
		var adj = neighbours(t);
		var scrapes = (size > 0.7 ? 6 : 4) + Std.int(rnd(5) * 3);
		var minDist = 0.65 + rnd(8) * 0.3;
		var spots:Array<Int> = [];
		var salt = 40;
		for (s in 0...scrapes) {
			var idx = 0;
			for (attempt in 0...100) {
				idx = Std.int(rnd(salt++) * sphere.length) % sphere.length;
				var ok = true;
				for (o in spots) if (sphere[o].distance(sphere[idx]) < minDist) ok = false;
				if (ok) break;
			}
			spots.push(idx);
		}
		for (s in 0...spots.length) {
			var strength = 0.12 + rnd(salt++) * 0.16;
			var radius = 0.4 + rnd(salt++) * 0.25;
			scrape(spots[s], sphere, normals, adj, strength, radius);
		}

		var base = pts.length;
		var local:Array<Point> = [];
		var occ:Array<Float> = [];
		for (k in 0...sphere.length) {
			var v = sphere[k];
			// Then a gentle noise over everything, so flats aren't perfectly flat.
			var n1 = noise3(v.x * 2.0 + off, v.y * 2.0 + off, v.z * 2.0);
			var n2 = noise3(v.x * 4.6 + off, v.y * 4.6, v.z * 4.6 + off);
			var r = 1 + (n1 - 0.5) * 0.22 + (n2 - 0.5) * 0.08;
			local.push(new Point(v.x * r, v.y * r, v.z * r));
			occ.push(v.length() * r);
		}
		// Smooth normals in the rock's own (unstretched) space, then transformed.
		var vn = [for (_ in local) new Point(0, 0, 0)];
		var i = 0;
		while (i < t.tris.length) {
			var a = t.tris[i], b = t.tris[i + 1], c = t.tris[i + 2];
			var pa = scaled(local[a], rx, ry, rz), pb = scaled(local[b], rx, ry, rz), pc = scaled(local[c], rx, ry, rz);
			var fn = pb.sub(pa).cross(pc.sub(pa));
			vn[a] = vn[a].add(fn);
			vn[b] = vn[b].add(fn);
			vn[c] = vn[c].add(fn);
			i += 3;
		}
		var sink = rz * (0.3 + rnd(7) * 0.15);
		var tr = Palette.r(tint), tg = Palette.g(tint), tb = Palette.b(tint);
		for (k in 0...local.length) {
			var p = scaled(local[k], rx, ry, rz);
			var n = vn[k];
			n.normalize();
			// Rotate around Z, place, sink into the ground.
			var wx = x + p.x * cs - p.y * sn, wy = y + p.x * sn + p.y * cs, wz = ground - sink + p.z;
			pts.push(new Point(wx, wy, wz));
			nrm.push(new Point(n.x * cs - n.y * sn, n.x * sn + n.y * cs, n.z));
			// Ambient occlusion: darker near the ground line and in hollows.
			var h = (p.z + rz) / (2 * rz); // 0 at the bottom, 1 at the top
			var ao = (0.62 + 0.38 * Math.min(1, h * 1.6)) * (0.82 + 0.18 * Math.min(1.2, occ[k]));
			col.push(new Point(tr * ao, tg * ao, tb * ao));
		}
		for (k in t.tris) idx.push(base + k);
		count++;
	}

	/** Flatten the vertices around `at` onto a plane (gl-rock's `scrape`). **/
	static function scrape(at:Int, pos:Array<Point>, nrm:Array<Point>, adj:Array<Array<Int>>, strength:Float, radius:Float) {
		var n = nrm[at].clone();
		n.normalize();
		var r0 = pos[at].sub(n.scaled(strength));
		var seen = new Map<Int, Bool>();
		var stack = [at];
		while (stack.length > 0) {
			var i = stack.pop();
			if (seen.exists(i)) continue;
			seen.set(i, true);
			var p = pos[i];
			var t = n.dot(r0.sub(p));
			var q = p.add(n.scaled(t));
			if (q.distance(r0) >= radius) continue;
			// Only ever cut into the rock, never push it out.
			if (t < 0) {
				pos[i] = q;
				nrm[i] = n.clone();
			}
			for (j in adj[i]) stack.push(j);
		}
	}

	static var adjCache:Map<Int, Array<Array<Int>>> = new Map();

	static function neighbours(t:{verts:Array<Point>, tris:Array<Int>}):Array<Array<Int>> {
		var c = adjCache.get(t.verts.length);
		if (c != null) return c;
		var sets = [for (_ in t.verts) new Map<Int, Bool>()];
		var i = 0;
		while (i < t.tris.length) {
			var a = t.tris[i], b = t.tris[i + 1], d = t.tris[i + 2];
			sets[a].set(b, true);
			sets[a].set(d, true);
			sets[b].set(a, true);
			sets[b].set(d, true);
			sets[d].set(a, true);
			sets[d].set(b, true);
			i += 3;
		}
		c = [for (s in sets) [for (k in s.keys()) k]];
		adjCache.set(t.verts.length, c);
		return c;
	}

	public function build(parent:h3d.scene.Object) {
		flush();
		var tex = GroundTextures.get().rock;
		for (p in chunks) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			var sh = new RockShader();
			sh.tex = tex;
			m.material.mainPass.addShader(sh);
			FlatMeshBuilder.shadows(m.material, true, true);
		}
	}

	function flush() {
		if (pts.length == 0) return;
		var ib = new hxd.IndexBuffer();
		for (k in idx) ib.push(k);
		var p = new h3d.prim.Polygon(pts, ib);
		p.normals = nrm;
		p.colors = col;
		chunks.push(p);
		pts = [];
		nrm = [];
		col = [];
		idx = [];
	}

	static inline function scaled(p:Point, sx:Float, sy:Float, sz:Float)
		return new Point(p.x * sx, p.y * sy, p.z * sz);

	// --- icosphere template ---------------------------------------------------

	static function template(level:Int) {
		var t = templates.get(level);
		if (t != null) return t;
		var g = (1 + Math.sqrt(5)) / 2;
		var verts = [
			new Point(-1, g, 0), new Point(1, g, 0), new Point(-1, -g, 0), new Point(1, -g, 0), new Point(0, -1, g), new Point(0, 1, g),
			new Point(0, -1, -g), new Point(0, 1, -g), new Point(g, 0, -1), new Point(g, 0, 1), new Point(-g, 0, -1), new Point(-g, 0, 1)
		];
		for (v in verts) v.normalize();
		var tris = [
			0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8,
			9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1
		];
		for (_ in 0...level) {
			var mid = new Map<String, Int>();
			function midpoint(a:Int, b:Int):Int {
				var key = a < b ? a + "_" + b : b + "_" + a;
				var m = mid.get(key);
				if (m != null) return m;
				var p = verts[a].add(verts[b]);
				p.normalize();
				verts.push(p);
				mid.set(key, verts.length - 1);
				return verts.length - 1;
			}
			var next = [];
			var i = 0;
			while (i < tris.length) {
				var a = tris[i], b = tris[i + 1], c = tris[i + 2];
				var ab = midpoint(a, b), bc = midpoint(b, c), ca = midpoint(c, a);
				next = next.concat([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]);
				i += 3;
			}
			tris = next;
		}
		// Make sure every triangle faces outward (CCW seen from outside).
		var i = 0;
		while (i < tris.length) {
			var a = verts[tris[i]], b = verts[tris[i + 1]], c = verts[tris[i + 2]];
			var n = b.sub(a).cross(c.sub(a));
			if (n.dot(a.add(b).add(c)) < 0) {
				var tmp = tris[i + 1];
				tris[i + 1] = tris[i + 2];
				tris[i + 2] = tmp;
			}
			i += 3;
		}
		t = {verts: verts, tris: tris};
		templates.set(level, t);
		return t;
	}

	// --- 3D value noise ---------------------------------------------------------

	static function hash3(x:Int, y:Int, z:Int):Float {
		var h:haxe.Int32 = 1013904223;
		h = h + (x : haxe.Int32) * (374761393 : haxe.Int32);
		h = h + (y : haxe.Int32) * (668265263 : haxe.Int32);
		h = h + (z : haxe.Int32) * (1440662683 : haxe.Int32);
		h = (h ^ (h >>> 13)) * (1274126177 : haxe.Int32);
		h = h ^ (h >>> 16);
		return (h & 0x7fffffff) / 2147483647.0;
	}

	static function noise3(x:Float, y:Float, z:Float):Float {
		var xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
		var fx = x - xi, fy = y - yi, fz = z - zi;
		var u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy), w = fz * fz * (3 - 2 * fz);
		inline function l(a:Float, b:Float, t:Float) return a + (b - a) * t;
		var c000 = hash3(xi, yi, zi), c100 = hash3(xi + 1, yi, zi), c010 = hash3(xi, yi + 1, zi), c110 = hash3(xi + 1, yi + 1, zi);
		var c001 = hash3(xi, yi, zi + 1), c101 = hash3(xi + 1, yi, zi + 1), c011 = hash3(xi, yi + 1, zi + 1), c111 = hash3(xi + 1, yi + 1, zi + 1);
		return l(l(l(c000, c100, u), l(c010, c110, u), v), l(l(c001, c101, u), l(c011, c111, u), v), w);
	}
}

/** Triplanar rock texture: projected from three axes, blended by the normal. **/
class RockShader extends hxsl.Shader {
	static var SRC = {
		@param var tex:Sampler2D;
		@param var scale:Float;
		@param var strength:Float;
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;

		function fragment() {
			var n = abs(normalize(transformedNormal));
			var w = n * n * n * n;
			w /= (w.x + w.y + w.z);
			var p = transformedPosition / scale;
			var c = tex.get(p.yz).rgb * w.x + tex.get(p.xz).rgb * w.y + tex.get(p.xy).rgb * w.z;
			// The painted rock averages about 0.6 grey; normalise so the tint stays the tint.
			pixelColor.rgb *= mix(vec3(1.0), c * 1.65, strength);
		}
	};

	public function new() {
		super();
		scale = 1.6;
		strength = 0.85;
	}
}
