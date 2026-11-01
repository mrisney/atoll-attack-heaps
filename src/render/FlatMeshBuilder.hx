package render;

import h3d.col.Point;

/**
	Builds flat-shaded, vertex-colored low-poly geometry — the core of the
	stylized look. Every triangle gets its own vertices and a face normal,
	so lighting reads as crisp facets instead of smooth gradients.

	Geometry is split into chunks under the 16-bit index limit.
**/
class FlatMeshBuilder {
	static inline var MAX_VERTS = 65000;

	var chunks:Array<h3d.prim.Polygon> = [];
	var pts:Array<Point>;
	var nrm:Array<Point>;
	var col:Array<Point>;

	public function new() {
		reset();
	}

	function reset() {
		pts = [];
		nrm = [];
		col = [];
	}

	function flush() {
		if (pts.length == 0) return;
		var idx = new hxd.IndexBuffer();
		for (i in 0...pts.length) idx.push(i);
		var p = new h3d.prim.Polygon(pts, idx);
		p.normals = nrm;
		p.colors = col;
		chunks.push(p);
		reset();
	}

	public function tri(a:Point, b:Point, c:Point, color:Int, shade = 1.0) {
		if (pts.length + 3 > MAX_VERTS) flush();
		var n = b.sub(a).cross(c.sub(a));
		n.normalize();
		var cc = new Point(Palette.r(color) * shade, Palette.g(color) * shade, Palette.b(color) * shade);
		for (p in [a, b, c]) {
			pts.push(p);
			nrm.push(n);
			col.push(cc);
		}
	}

	public inline function quad(a:Point, b:Point, c:Point, d:Point, color:Int, shade = 1.0) {
		tri(a, b, c, color, shade);
		tri(a, c, d, color, shade);
	}

	/** Cone (or truncated cone when topRadius > 0) standing on z. **/
	public function cone(x:Float, y:Float, z:Float, radius:Float, height:Float, sides:Int, color:Int, topRadius = 0.0, rot = 0.0) {
		var top = new Point(x, y, z + height);
		for (s in 0...sides) {
			var a0 = rot + s / sides * Math.PI * 2;
			var a1 = rot + (s + 1) / sides * Math.PI * 2;
			var p0 = new Point(x + Math.cos(a0) * radius, y + Math.sin(a0) * radius, z);
			var p1 = new Point(x + Math.cos(a1) * radius, y + Math.sin(a1) * radius, z);
			// Alternate a tiny shade per facet — reads as "hand-painted".
			var shade = (s % 2 == 0) ? 1.0 : 0.93;
			if (topRadius <= 0) {
				tri(p0, p1, top, color, shade);
			} else {
				var t0 = new Point(x + Math.cos(a0) * topRadius, y + Math.sin(a0) * topRadius, z + height);
				var t1 = new Point(x + Math.cos(a1) * topRadius, y + Math.sin(a1) * topRadius, z + height);
				quad(p0, p1, t1, t0, color, shade);
				tri(t0, t1, top, color, 1.05);
			}
		}
	}

	/** Upright n-sided prism. **/
	public inline function prism(x:Float, y:Float, z:Float, radius:Float, height:Float, sides:Int, color:Int, rot = 0.0) {
		cone(x, y, z, radius, height, sides, color, radius, rot);
	}

	/** Flat ring lying on z (selection circles, markers). **/
	public function ring(x:Float, y:Float, z:Float, inner:Float, outer:Float, segs:Int, color:Int) {
		for (s in 0...segs) {
			var a0 = s / segs * Math.PI * 2;
			var a1 = (s + 1) / segs * Math.PI * 2;
			var c0 = Math.cos(a0), s0 = Math.sin(a0), c1 = Math.cos(a1), s1 = Math.sin(a1);
			quad(new Point(x + c0 * inner, y + s0 * inner, z), new Point(x + c0 * outer, y + s0 * outer, z),
				new Point(x + c1 * outer, y + s1 * outer, z), new Point(x + c1 * inner, y + s1 * inner, z), color);
		}
	}

	/** Turn everything into meshes under `parent`. **/
	public function build(parent:h3d.scene.Object, lit = true):Array<h3d.scene.Mesh> {
		flush();
		var out = [];
		for (p in chunks) {
			var m = new h3d.scene.Mesh(p, parent);
			setupMaterial(m.material, lit);
			out.push(m);
		}
		chunks = [];
		return out;
	}

	public static function setupMaterial(mat:h3d.mat.Material, lit = true) {
		mat.color.set(1, 1, 1, 1);
		mat.mainPass.culling = None;
		mat.mainPass.addShader(new h3d.shader.VertexColor());
		mat.mainPass.enableLights = lit;
		mat.specularAmount = 0;
	}
}
