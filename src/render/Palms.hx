package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Coconut palms, replacing the old faceted ones (the owner found them
	"very angular and not very realistic").

	- **Trunk:** a smooth tapered tube along a curve. It leans out (usually
	  toward the sea) near the base, then straightens upward, as real coastal
	  palms do. A flared foot, and alternating slightly raised and darker rings
	  for the leaf scars. Smooth normals, lit by the sun.
	- **Fronds:** each one is an arched strip that rises from the crown and
	  droops toward the tip. Its cross-section is folded (the rib is higher
	  than the edges), and it's textured with a pinnate leaf painted in code:
	  a central rib with many thin, forward-angled leaflets, cut out with an
	  alpha test, so silhouettes and shadows are leafy rather than solid.
	  Young fronds stand up, old ones hang low and turn tan.
	- Fronds sway a little (SwayShader); the trunk doesn't.

	Everything is batched: one trunk mesh and one frond mesh per island chunk.
**/
class Palms {
	static inline var MAX_VERTS = 60000;
	static var frondTex:Null<h3d.mat.Texture> = null;

	// Trunks
	var tp:Array<Point> = [];
	var tn:Array<Point> = [];
	var tc:Array<Point> = [];
	var ti:Array<Int> = [];
	final trunks:Array<h3d.prim.Polygon> = [];

	// Fronds
	var fp:Array<Point> = [];
	var fn:Array<Point> = [];
	var fc:Array<Point> = [];
	var fu:Array<UV> = [];
	var fi:Array<Int> = [];
	final fronds:Array<h3d.prim.Polygon> = [];

	public function new() {}

	/**
		@param r     random source in 0..1 (the caller's seeded generator)
		@param lx,ly direction to lean (normalised)
		@param s     overall scale
	**/
	public function add(x:Float, y:Float, z:Float, lx:Float, ly:Float, s:Float, bark:Int, leaf:Int, r:() -> Float) {
		if (tp.length > MAX_VERTS - 600) flushTrunks();
		if (fp.length > MAX_VERTS - 1200) flushFronds();

		// --- trunk ---------------------------------------------------------------
		var H = (2.3 + r() * 0.9) * s;
		var L = H * (0.18 + r() * 0.32);
		var rings = 26, sides = 8;
		// Side vectors: A is horizontal, perpendicular to the lean; B completes the frame.
		var ax = -ly, ay = lx;
		inline function pos(t:Float):Point {
			var bend = 1 - (1 - t) * (1 - t); // leans early, straightens near the top
			return new Point(x + lx * L * bend, y + ly * L * bend, z - 0.15 + H * t);
		}
		var base = tp.length;
		var br = Palette.r(bark), bg = Palette.g(bark), bb = Palette.b(bark);
		for (k in 0...rings + 1) {
			var t = k / rings;
			var p = pos(t);
			// Tangent from the curve's derivative.
			var dh = 2 * (1 - t) * L;
			var tx = lx * dh, ty = ly * dh, tz = H;
			var tl = Math.sqrt(tx * tx + ty * ty + tz * tz);
			tx /= tl;
			ty /= tl;
			tz /= tl;
			// B = T × A
			var bx = ty * 0 - tz * ay, by = tz * ax - tx * 0, bz = tx * ay - ty * ax;
			var scar = k % 2 == 0;
			var rad = s * (0.13 * (1 - t) + 0.07 * t) + s * 0.09 * Math.exp(-t * 14);
			if (scar) rad *= 1.05;
			var shade = (scar ? 0.95 : 0.8) * (0.8 + 0.2 * Math.min(1, t * 3)); // darker at the foot
			if (k == rings) shade *= 0.7; // shadowed under the crown
			for (j in 0...sides) {
				var a = j / sides * Math.PI * 2;
				var ca = Math.cos(a), sa = Math.sin(a);
				var nx = ax * ca + bx * sa, ny = ay * ca + by * sa, nz = bz * sa;
				tp.push(new Point(p.x + nx * rad, p.y + ny * rad, p.z + nz * rad));
				tn.push(new Point(nx, ny, nz));
				tc.push(new Point(br * shade, bg * shade, bb * shade));
			}
		}
		for (k in 0...rings)
			for (j in 0...sides) {
				var a = base + k * sides + j, b = base + k * sides + (j + 1) % sides;
				var c = a + sides, d = b + sides;
				tri(ti, tp, a, b, d);
				tri(ti, tp, a, d, c);
			}

		// --- fronds --------------------------------------------------------------
		var top = pos(1);
		var count = 10 + Std.int(r() * 4);
		var lr = Palette.r(leaf), lg = Palette.g(leaf), lb = Palette.b(leaf);
		var spin = r() * Math.PI * 2;
		for (k in 0...count) {
			var az = spin + k / count * Math.PI * 2 + (r() - 0.5) * 0.35;
			var dx = Math.cos(az), dy = Math.sin(az);
			var sx = -dy, sy = dx; // across the frond
			var age = r(); // 0 young (upright) .. 1 old (hanging)
			var len = (1.35 + r() * 0.5) * s * (0.85 + age * 0.25);
			var hw = (0.3 + r() * 0.06) * s;
			var rise = 0.95 - age * 0.9; // starting elevation (radians)
			var droop = 1.5 + age * 1.1 + r() * 0.3;
			// Colour: old fronds drift toward tan.
			var tan = Math.max(0, age - 0.75) * 2.4;
			var cr = lr + (0.62 - lr) * tan, cg = lg + (0.52 - lg) * tan, cb = lb + (0.3 - lb) * tan;
			var segs = 10;
			var fb = fp.length;
			var px = top.x + dx * 0.05, py = top.y + dy * 0.05, pz = top.z + 0.02;
			for (i in 0...segs + 1) {
				var u = i / segs;
				if (i > 0) {
					var el = rise - droop * Math.pow(u, 1.4);
					var st = len / segs;
					px += dx * Math.cos(el) * st;
					py += dy * Math.cos(el) * st;
					pz += Math.sin(el) * st;
				}
				// Wide in the middle, narrow at the base and tip; the texture shapes the rest.
				var w = hw * (0.3 + 0.7 * Math.sin(Math.PI * Math.min(1, u * 0.95 + 0.05)));
				var fold = w * 0.38;
				var ao = 0.62 + 0.38 * Math.min(1, u * 3); // darker deep in the crown
				for (side in [-1, 0, 1]) {
					var ex = sx * w * side, ey = sy * w * side, ez = side == 0 ? 0 : -fold;
					fp.push(new Point(px + ex, py + ey, pz + ez));
					var n = new Point(sx * side * 0.45, sy * side * 0.45, 1);
					n.normalize();
					fn.push(n);
					fu.push(new UV((side + 1) * 0.5, u));
					fc.push(new Point(cr * ao, cg * ao, cb * ao));
				}
			}
			for (i in 0...segs) {
				var a = fb + i * 3;
				for (q in [[a, a + 1, a + 4], [a, a + 4, a + 3], [a + 1, a + 2, a + 5], [a + 1, a + 5, a + 4]]) {
					fi.push(q[0]);
					fi.push(q[1]);
					fi.push(q[2]);
				}
			}
		}
	}

	/** Push a triangle, flipping it if needed so it faces outward (away from the trunk axis is handled by callers' ordering). **/
	static inline function tri(idx:Array<Int>, pts:Array<Point>, a:Int, b:Int, c:Int) {
		idx.push(a);
		idx.push(b);
		idx.push(c);
	}

	public function build(parent:h3d.scene.Object) {
		flushTrunks();
		flushFronds();
		for (p in trunks) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			// Winding depends on the frame's handedness; draw both sides rather than guess.
			m.material.mainPass.culling = None;
			FlatMeshBuilder.shadows(m.material, true, true);
		}
		for (p in fronds) {
			var m = new h3d.scene.Mesh(p, parent);
			FlatMeshBuilder.setupMaterial(m.material, true);
			m.material.texture = texture();
			m.material.textureShader.killAlpha = true;
			m.material.textureShader.killAlphaThreshold = 0.35;
			m.material.mainPass.culling = None;
			m.material.mainPass.addShader(new SwayShader(0.05, 0.9));
			FlatMeshBuilder.shadows(m.material, true, true);
		}
	}

	function flushTrunks() {
		if (tp.length == 0) return;
		var ib = new hxd.IndexBuffer();
		for (k in ti) ib.push(k);
		var p = new h3d.prim.Polygon(tp, ib);
		p.normals = tn;
		p.colors = tc;
		trunks.push(p);
		tp = [];
		tn = [];
		tc = [];
		ti = [];
	}

	function flushFronds() {
		if (fp.length == 0) return;
		var ib = new hxd.IndexBuffer();
		for (k in fi) ib.push(k);
		var p = new h3d.prim.Polygon(fp, ib);
		p.normals = fn;
		p.uvs = fu;
		p.colors = fc;
		fronds.push(p);
		fp = [];
		fn = [];
		fc = [];
		fu = [];
		fi = [];
	}

	/**
		Paint the frond once: a pale rib down the middle (u = 0.5), leaflets
		angled toward the tip on both sides, each slightly lighter along its
		middle, ragged lengths, shorter toward the base and tip. Transparent
		pixels carry the leaf colour too, so filtering never darkens the edges.
		The texture is white-ish green and gets tinted by vertex colour.
	**/
	static function texture():h3d.mat.Texture {
		if (frondTex != null) return frondTex;
		var W = 64, H = 192;
		var px = hxd.Pixels.alloc(W, H, RGBA);
		var leaflets = 24.0;
		var slant = 2.2;
		for (y in 0...H)
			for (x in 0...W) {
				var U = (x + 0.5) / W, V = (y + 0.5) / H;
				var d = Math.abs(U - 0.5) * 2;
				var side = U < 0.5 ? 0 : 1;
				// How far leaflets reach at this point along the frond.
				var reach = Math.pow(Math.sin(Math.PI * Math.min(1, V * 1.02)), 0.55) * (V < 0.05 ? V / 0.05 : 1);
				var phase = V * leaflets - d * slant;
				var id = Math.floor(phase);
				// Ragged: each leaflet gets its own length.
				var h = hash(Std.int(id) * 2 + side);
				reach *= 0.78 + 0.22 * h;
				var f = phase - id;
				var wl = 0.62 * (1 - 0.7 * Math.min(1, d / Math.max(reach, 0.001)));
				var a = 0.0;
				var r = 0.62, g = 0.62, b = 0.6;
				if (d < 0.05 + 0.03 * (1 - V)) {
					a = 1;
					r = 0.66;
					g = 0.66;
					b = 0.42;
				} else if (d < reach && f < wl) {
					a = 1;
					var k = f / wl;
					var mid = 0.86 + 0.14 * Math.sin(Math.PI * k);
					var tip = 1 - 0.22 * (d / reach);
					r *= mid * tip;
					g *= mid * tip;
					b *= mid * tip;
				}
				// The texture is multiplied by vertex colour (the palm's leaf tint),
				// so normalise toward white-ish green.
				var sc = 1.6;
				inline function c8(v:Float) return Std.int(Math.max(0, Math.min(1, v)) * 255);
				px.setPixel(x, y, (c8(a) << 24) | (c8(r * sc) << 16) | (c8(g * sc) << 8) | c8(b * sc));
			}
		var t = new h3d.mat.Texture(W, H, [MipMapped]);
		t.uploadPixels(px);
		t.mipMap = Linear;
		t.filter = Linear;
		t.wrap = Clamp;
		frondTex = t;
		return t;
	}

	static function hash(n:Int):Float {
		var h:haxe.Int32 = n * 374761393 + 668265263;
		h = (h ^ (h >>> 13)) * 1274126177;
		h = h ^ (h >>> 16);
		return (h & 0xffff) / 65535.0;
	}
}
