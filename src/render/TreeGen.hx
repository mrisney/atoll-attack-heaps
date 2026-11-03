package render;

/**
	Procedural tree skeletons and meshes, ported from EZ-Tree by Daniel
	Greenheck (github.com/dgreenheck/ez-tree, MIT licence; see THIRD_PARTY.md).
	Write-up: "Fractals to Forests" (Codrops, 2025).

	The algorithm, as in the original:
	- A queue of branches, starting with the trunk. Each branch grows section
	  by section. Its radius tapers. Each section tilts randomly by
	  "gnarliness" (more on thin branches), twists, and bends toward a growth
	  force (up for broadleaf trees, slightly down for pines).
	- Children sprout along the parent between `start` and the tip, spread
	  evenly around it (shuffled slots plus jitter), at `angle` from the
	  parent. Deciduous branches also continue past their tip at the next level.
	- The last level carries leaves: textured quads (two crossed per leaf).

	The generator works in EZ-Tree's own units and Y-up space, exactly like the
	original. `mesh()` converts the result to our Z-up world and scales it to a
	target height. Visual only: it never touches the sim.
**/
typedef TreeOptions = {
	var seed:Int;
	var evergreen:Bool;
	var levels:Int;
	var angle:Array<Float>; // per level (index 1..3), degrees
	var children:Array<Int>; // per level (index 0..2)
	var forceStrength:Float; // toward +Y
	var gnarliness:Array<Float>;
	var length:Array<Float>;
	var radius:Array<Float>;
	var sections:Array<Int>;
	var segments:Array<Int>;
	var start:Array<Float>;
	var taper:Array<Float>;
	var twist:Array<Float>;
	var leafAngle:Float;
	var leafCount:Int;
	var leafStart:Float;
	var leafSize:Float;
	var leafSizeVariance:Float;
}

typedef TreeMesh = {
	var barkPos:Array<Float>; // xyz
	var barkNrm:Array<Float>;
	var barkUv:Array<Float>; // u around, v along (in metres)
	var barkIdx:Array<Int>;
	var leafPos:Array<Float>;
	var leafNrm:Array<Float>; // rounded around the crown
	var leafUv:Array<Float>;
	var leafShade:Array<Float>; // 0 deep inside the crown .. 1 at its surface
	var leafIdx:Array<Int>;
	var height:Float;
}

private typedef Section = {o:V3, e:V3, r:Float};
private typedef Bud = {o:V3, e:V3, len:Float, radius:Float, level:Int, sections:Int, segments:Int};

class TreeGen {
	final opt:TreeOptions;
	var rng:Rng;
	final queue:Array<Bud> = [];
	final branches:Array<{sections:Array<Section>, segments:Int}> = [];
	final leaves:Array<{o:V3, e:V3, size:Float}> = [];

	public function new(opt:TreeOptions) {
		this.opt = opt;
	}

	// --- skeleton (EZ-Tree's generate/growBranch/generateChildBranches/generateLeaves) ---

	function generate() {
		rng = new Rng(opt.seed);
		queue.push({o: new V3(0, 0, 0), e: new V3(0, 0, 0), len: opt.length[0], radius: opt.radius[0], level: 0, sections: opt.sections[0],
			segments: opt.segments[0]});
		while (queue.length > 0) growBranch(queue.shift());
	}

	function growBranch(b:Bud) {
		var e = b.e.clone();
		var o = b.o.clone();
		var secLen = b.len / b.sections;
		var sections:Array<Section> = [];
		for (i in 0...b.sections + 1) {
			var r = b.radius;
			if (i == b.sections && b.level == opt.levels) r = 0.001;
			else if (!opt.evergreen) r *= 1 - opt.taper[b.level] * (i / b.sections);
			else r *= 1 - i / b.sections;
			sections.push({o: o.clone(), e: e.clone(), r: r});

			o = o.add(Q.fromEuler(e).rotate(new V3(0, secLen, 0)));
			var g = Math.max(1, 1 / Math.sqrt(r)) * opt.gnarliness[b.level];
			e.x += rng.range(-g, g);
			e.z += rng.range(-g, g);
			var q = Q.fromEuler(e).mul(Q.axisAngle(new V3(0, 1, 0), opt.twist[b.level]));
			// Bend toward the growth force (+Y), by strength / radius, never past it.
			var up = q.rotate(new V3(0, 1, 0));
			var target = new V3(0, opt.forceStrength >= 0 ? 1 : -1, 0);
			var axis = up.cross(target);
			var s = axis.len();
			if (s > 1e-6) {
				axis = axis.scale(1 / s);
				var full = Math.atan2(s, up.dot(target));
				var step = Math.abs(opt.forceStrength) / r;
				q = Q.axisAngle(axis, Math.max(-full, Math.min(full, step))).mul(q);
			}
			e = q.toEuler();
		}
		branches.push({sections: sections, segments: b.segments});

		if (!opt.evergreen) {
			var last = sections[sections.length - 1];
			if (b.level < opt.levels)
				queue.push({o: last.o, e: last.e, len: opt.length[b.level + 1], radius: last.r, level: b.level + 1, sections: b.sections,
					segments: b.segments});
			else
				recordLeaf(last.o, last.e);
		}
		if (b.level == opt.levels) generateLeaves(sections);
		else if (b.level < opt.levels) generateChildren(opt.children[b.level], b.level + 1, sections);
	}

	/** Point and orientation a fraction `t` of the way along a branch. **/
	function along(sections:Array<Section>, t:Float) {
		var n = sections.length - 1;
		var i = Std.int(Math.floor(t * n));
		var a = sections[i], b = i == n ? a : sections[i + 1];
		var alpha = (t - i / n) * n;
		return {
			o: a.o.lerp(b.o, alpha),
			r: (1 - alpha) * a.r + alpha * b.r,
			q: Q.fromEuler(b.e).slerp(Q.fromEuler(a.e), alpha)
		};
	}

	function generateChildren(count:Int, level:Int, sections:Array<Section>) {
		var radial0 = rng.next();
		var startMin = opt.start[level];
		var step = (1 - startMin) / count;
		var slots = shuffled(count);
		for (i in 0...count) {
			var t = startMin + (i + rng.next()) * step;
			var p = along(sections, t);
			var jitter = rng.range(-0.5, 0.5);
			var ang = 2 * Math.PI * (radial0 + (slots[i] + jitter) / count);
			var q = p.q.mul(Q.axisAngle(new V3(0, 1, 0), ang).mul(Q.axisAngle(new V3(1, 0, 0), opt.angle[level] * Math.PI / 180)));
			var len = opt.length[level] * (opt.evergreen ? 1 - t : 1);
			queue.push({o: p.o, e: q.toEuler(), len: len, radius: opt.radius[level] * p.r, level: level, sections: opt.sections[level],
				segments: opt.segments[level]});
		}
	}

	function generateLeaves(sections:Array<Section>) {
		var radial0 = rng.next();
		var count = opt.leafCount;
		var step = (1 - opt.leafStart) / count;
		var slots = shuffled(count);
		for (i in 0...count) {
			var t = opt.leafStart + (i + rng.next()) * step;
			var p = along(sections, t);
			var jitter = rng.range(-0.5, 0.5);
			var ang = 2 * Math.PI * (radial0 + (slots[i] + jitter) / count);
			var q = p.q.mul(Q.axisAngle(new V3(0, 1, 0), ang).mul(Q.axisAngle(new V3(1, 0, 0), opt.leafAngle * Math.PI / 180)));
			recordLeaf(p.o, q.toEuler());
		}
	}

	function recordLeaf(o:V3, e:V3) {
		leaves.push({o: o.clone(), e: e.clone(), size: opt.leafSize * (1 + rng.range(-opt.leafSizeVariance, opt.leafSizeVariance))});
	}

	function shuffled(count:Int):Array<Int> {
		var a = [for (k in 0...count) k];
		var k = count - 1;
		while (k > 0) {
			var r = Std.int(Math.floor(rng.next() * (k + 1)));
			var t = a[k];
			a[k] = a[r];
			a[r] = t;
			k--;
		}
		return a;
	}

	// --- mesh -------------------------------------------------------------------

	/**
		Generate and mesh the tree, converted to Z-up and scaled so it's
		`height` metres tall. Leaves are two crossed quads each.
	**/
	public function mesh(height:Float):TreeMesh {
		generate();
		// Height in tree units (Y up), to find the scale.
		var top = 0.0;
		for (b in branches)
			for (s in b.sections) top = Math.max(top, s.o.y);
		for (l in leaves) top = Math.max(top, l.o.y + l.size * 0.8);
		var k = height / Math.max(top, 1e-6);
		// Y-up → Z-up (a rotation about X, so winding is preserved): (x, y, z) → (x, -z, y).
		inline function px(v:V3) return v.x * k;
		inline function py(v:V3) return -v.z * k;
		inline function pz(v:V3) return v.y * k;

		var m:TreeMesh = {
			barkPos: [], barkNrm: [], barkUv: [], barkIdx: [],
			leafPos: [], leafNrm: [], leafUv: [], leafShade: [], leafIdx: [],
			height: height
		};

		for (b in branches) {
			var segs = Std.int(Math.max(3, b.segments));
			var base = Std.int(m.barkPos.length / 3);
			var dist = 0.0;
			for (si in 0...b.sections.length) {
				var s = b.sections[si];
				if (si > 0) dist += s.o.sub(b.sections[si - 1].o).len() * k;
				var q = Q.fromEuler(s.e);
				for (j in 0...segs + 1) {
					var a = 2 * Math.PI * (j % segs) / segs;
					var n = q.rotate(new V3(Math.cos(a), 0, Math.sin(a)));
					var v = s.o.add(n.scale(s.r));
					m.barkPos.push(px(v));
					m.barkPos.push(py(v));
					m.barkPos.push(pz(v));
					m.barkNrm.push(n.x);
					m.barkNrm.push(-n.z);
					m.barkNrm.push(n.y);
					m.barkUv.push(j / segs);
					m.barkUv.push(dist);
				}
			}
			var N = segs + 1;
			for (i in 0...b.sections.length - 1)
				for (j in 0...segs) {
					var v1 = base + i * N + j, v2 = v1 + 1, v3 = v1 + N, v4 = v2 + N;
					for (x in [v1, v3, v2, v2, v3, v4]) m.barkIdx.push(x);
				}
		}

		// Crown centre and radius, for rounded leaf normals and inner shading.
		var cx = 0.0, cy = 0.0, cz = 0.0;
		for (l in leaves) {
			cx += l.o.x;
			cy += l.o.y;
			cz += l.o.z;
		}
		var nl = Math.max(1, leaves.length);
		var centre = new V3(cx / nl, cy / nl, cz / nl);
		var crownR = 1e-6;
		for (l in leaves) crownR = Math.max(crownR, l.o.sub(centre).len());

		for (l in leaves) {
			var q = Q.fromEuler(l.e);
			var W = l.size, L = l.size;
			for (rot in [0.0, Math.PI / 2]) {
				var qr = q.mul(Q.axisAngle(new V3(0, 1, 0), rot));
				var base = Std.int(m.leafPos.length / 3);
				var corners = [new V3(-W / 2, L, 0), new V3(-W / 2, 0, 0), new V3(W / 2, 0, 0), new V3(W / 2, L, 0)];
				var uvs = [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]];
				for (c in 0...4) {
					var v = qr.rotate(corners[c]).add(l.o);
					// Rounded normal: out from the crown centre, a little upward.
					var d = v.sub(centre);
					var n = d.scale(1 / Math.max(d.len(), 1e-6)).add(new V3(0, 0.6, 0));
					n = n.scale(1 / n.len());
					m.leafPos.push(px(v));
					m.leafPos.push(py(v));
					m.leafPos.push(pz(v));
					m.leafNrm.push(n.x);
					m.leafNrm.push(-n.z);
					m.leafNrm.push(n.y);
					m.leafUv.push(uvs[c][0]);
					m.leafUv.push(uvs[c][1]);
					m.leafShade.push(Math.min(1, d.len() / crownR));
				}
				for (x in [base, base + 1, base + 2, base, base + 2, base + 3]) m.leafIdx.push(x);
			}
		}
		return m;
	}
}

/** EZ-Tree's RNG (multiply-with-carry), so presets grow the same shapes. **/
private class Rng {
	var w:Int;
	var z:Int;

	public function new(seed:Int) {
		w = (123456789 + seed) | 0;
		z = (987654321 - seed) | 0;
	}

	public function next():Float {
		z = (36969 * (z & 65535) + (z >> 16)) | 0;
		w = (18000 * (w & 65535) + (w >> 16)) | 0;
		var r:Float = ((z << 16) + (w & 65535)) | 0;
		if (r < 0) r += 4294967296.0;
		return r / 4294967296.0;
	}

	public inline function range(min:Float, max:Float):Float
		return min + (max - min) * next();
}

private class V3 {
	public var x:Float;
	public var y:Float;
	public var z:Float;

	public inline function new(x:Float, y:Float, z:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	public inline function clone() return new V3(x, y, z);

	public inline function add(b:V3) return new V3(x + b.x, y + b.y, z + b.z);

	public inline function sub(b:V3) return new V3(x - b.x, y - b.y, z - b.z);

	public inline function scale(s:Float) return new V3(x * s, y * s, z * s);

	public inline function dot(b:V3) return x * b.x + y * b.y + z * b.z;

	public inline function cross(b:V3) return new V3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);

	public inline function len() return Math.sqrt(x * x + y * y + z * z);

	public inline function lerp(b:V3, t:Float) return new V3(x + (b.x - x) * t, y + (b.y - y) * t, z + (b.z - z) * t);
}

/** Quaternion with three.js conventions (Euler order XYZ), to match EZ-Tree. **/
private class Q {
	public var x:Float;
	public var y:Float;
	public var z:Float;
	public var w:Float;

	public inline function new(x:Float, y:Float, z:Float, w:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}

	public static function axisAngle(a:V3, ang:Float):Q {
		var s = Math.sin(ang / 2);
		return new Q(a.x * s, a.y * s, a.z * s, Math.cos(ang / 2));
	}

	public static function fromEuler(e:V3):Q {
		var c1 = Math.cos(e.x / 2), c2 = Math.cos(e.y / 2), c3 = Math.cos(e.z / 2);
		var s1 = Math.sin(e.x / 2), s2 = Math.sin(e.y / 2), s3 = Math.sin(e.z / 2);
		return new Q(s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3);
	}

	public function toEuler():V3 {
		var x2 = x + x, y2 = y + y, z2 = z + z;
		var xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2;
		var wx = w * x2, wy = w * y2, wz = w * z2;
		var m11 = 1 - (yy + zz), m12 = xy - wz, m13 = xz + wy;
		var m22 = 1 - (xx + zz), m23 = yz - wx;
		var m32 = yz + wx, m33 = 1 - (xx + yy);
		var ey = Math.asin(Math.max(-1, Math.min(1, m13)));
		if (Math.abs(m13) < 0.9999999) return new V3(Math.atan2(-m23, m33), ey, Math.atan2(-m12, m11));
		return new V3(Math.atan2(m32, m22), ey, 0);
	}

	/** this × b **/
	public function mul(b:Q):Q {
		return new Q(x * b.w + w * b.x + y * b.z - z * b.y, y * b.w + w * b.y + z * b.x - x * b.z, z * b.w + w * b.z + x * b.y - y * b.x,
			w * b.w - x * b.x - y * b.y - z * b.z);
	}

	public function rotate(v:V3):V3 {
		// v + 2w(q×v) + 2q×(q×v)
		var tx = 2 * (y * v.z - z * v.y), ty = 2 * (z * v.x - x * v.z), tz = 2 * (x * v.y - y * v.x);
		return new V3(v.x + w * tx + y * tz - z * ty, v.y + w * ty + z * tx - x * tz, v.z + w * tz + x * ty - y * tx);
	}

	public function slerp(b:Q, t:Float):Q {
		if (t <= 0) return new Q(x, y, z, w);
		if (t >= 1) return new Q(b.x, b.y, b.z, b.w);
		var bx = b.x, by = b.y, bz = b.z, bw = b.w;
		var c = w * bw + x * bx + y * by + z * bz;
		if (c < 0) {
			bx = -bx;
			by = -by;
			bz = -bz;
			bw = -bw;
			c = -c;
		}
		if (c >= 1) return new Q(x, y, z, w);
		var s2 = 1 - c * c;
		if (s2 <= 1e-12) {
			var s = 1 - t;
			var r = new Q(s * x + t * bx, s * y + t * by, s * z + t * bz, s * w + t * bw);
			var l = Math.sqrt(r.x * r.x + r.y * r.y + r.z * r.z + r.w * r.w);
			return new Q(r.x / l, r.y / l, r.z / l, r.w / l);
		}
		var s = Math.sqrt(s2);
		var h = Math.atan2(s, c);
		var ra = Math.sin((1 - t) * h) / s, rb = Math.sin(t * h) / s;
		return new Q(x * ra + bx * rb, y * ra + by * rb, z * ra + bz * rb, w * ra + bw * rb);
	}
}
