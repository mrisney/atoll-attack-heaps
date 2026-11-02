package render;

import h3d.col.Point;

/**
	Smooth rounded shapes with an ink outline, for the line-drawing look:
	paper-white fill, bold dark contour, no surface detail.

	Every shape is a capsule along local Z (a sphere when z0 == z1). The
	outline is an "inverted hull": the same mesh pushed out along its normals,
	drawn back-faces-only in ink. Fill is unlit with a very soft baked shade so
	figures read as drawings rather than lit plastic.
**/
class InkShape {
	static final LIGHT = new Point(0.45, -0.35, 0.82).normalized();

	/** Default line weight (local units, before the unit's scale). **/
	public static inline var LINE = 0.026;

	/**
		Capsule from z0 to z1 (centers of the end caps) with radius r.
		Returns an Object you can position, rotate and scale.
	**/
	public static function capsule(parent:h3d.scene.Object, r:Float, z0:Float, z1:Float, fill:Int, ink = LINE, segs = 16,
			rings = 6):h3d.scene.Object {
		var o = new h3d.scene.Object(parent);
		var pts:Array<Point> = [], nrm:Array<Point> = [];
		var total = 2 * (rings + 1);
		for (k in 0...total) {
			var top = k <= rings;
			var phi = top ? (k / rings) * Math.PI / 2 : Math.PI / 2 + ((k - rings - 1) / rings) * Math.PI / 2;
			var zc = top ? z1 : z0;
			var sp = Math.sin(phi), cp = Math.cos(phi);
			for (s in 0...segs + 1) {
				var t = s / segs * Math.PI * 2;
				var nx = sp * Math.cos(t), ny = sp * Math.sin(t), nz = cp;
				pts.push(new Point(nx * r, ny * r, zc + nz * r));
				nrm.push(new Point(nx, ny, nz));
			}
		}
		var idx = new hxd.IndexBuffer();
		var w = segs + 1;
		for (k in 0...total - 1)
			for (s in 0...segs) {
				var a = k * w + s, b = a + 1, c = a + w + 1, d = a + w;
				addTri(pts, nrm, idx, a, b, c);
				addTri(pts, nrm, idx, a, c, d);
			}
		makeMeshes(o, pts, nrm, idx, fill, ink);
		return o;
	}

	public static inline function sphere(parent:h3d.scene.Object, r:Float, fill:Int, ink = LINE):h3d.scene.Object {
		return capsule(parent, r, 0, 0, fill, ink);
	}

	/** A rod between two points in the parent's space (bows, poles, swords). **/
	public static function rod(parent:h3d.scene.Object, ax:Float, ay:Float, az:Float, bx:Float, by:Float, bz:Float, r:Float, fill:Int,
			ink = LINE):h3d.scene.Object {
		var dx = bx - ax, dy = by - ay, dz = bz - az;
		var len = Math.sqrt(dx * dx + dy * dy + dz * dz);
		var o = capsule(parent, r, 0, len, fill, ink, 8, 3);
		o.setPosition(ax, ay, az);
		// Align local +Z with the direction: tilt from +Z around Y, then yaw around Z.
		var tilt = new h3d.Quat(), yaw = new h3d.Quat(), q = new h3d.Quat();
		tilt.initRotateAxis(0, 1, 0, Math.acos(Math.max(-1, Math.min(1, dz / len))));
		yaw.initRotateAxis(0, 0, 1, Math.atan2(dy, dx));
		q.multiply(yaw, tilt);
		o.setRotationQuat(q);
		return o;
	}

	static function addTri(pts:Array<Point>, nrm:Array<Point>, idx:hxd.IndexBuffer, a:Int, b:Int, c:Int) {
		var n = pts[b].sub(pts[a]).cross(pts[c].sub(pts[a]));
		if (n.lengthSq() < 1e-12) return; // degenerate (poles)
		var vn = nrm[a].add(nrm[b]).add(nrm[c]);
		// Wind so the face points outward (front face).
		if (n.dot(vn) < 0) {
			idx.push(a);
			idx.push(c);
			idx.push(b);
		} else {
			idx.push(a);
			idx.push(b);
			idx.push(c);
		}
	}

	static function makeMeshes(o:h3d.scene.Object, pts:Array<Point>, nrm:Array<Point>, idx:hxd.IndexBuffer, fill:Int, ink:Float) {
		var cols = [];
		for (n in nrm) {
			var shade = 0.86 + 0.14 * Math.max(0, n.dot(LIGHT));
			cols.push(new Point(Palette.r(fill) * shade, Palette.g(fill) * shade, Palette.b(fill) * shade));
		}
		var poly = new h3d.prim.Polygon(pts, idx);
		poly.normals = nrm;
		poly.colors = cols;
		var m = new h3d.scene.Mesh(poly, o);
		FlatMeshBuilder.setupMaterial(m.material, false);
		FlatMeshBuilder.shadows(m.material, true, true);

		if (ink <= 0) return;
		var hullPts = [for (i in 0...pts.length) pts[i].add(nrm[i].scaled(ink))];
		var inkCol = new Point(Palette.r(Palette.INK), Palette.g(Palette.INK), Palette.b(Palette.INK));
		var hull = new h3d.prim.Polygon(hullPts, idx);
		hull.normals = nrm;
		hull.colors = [for (_ in 0...pts.length) inkCol];
		var hm = new h3d.scene.Mesh(hull, o);
		FlatMeshBuilder.setupMaterial(hm.material, false);
		hm.material.mainPass.culling = Front;
	}
}
