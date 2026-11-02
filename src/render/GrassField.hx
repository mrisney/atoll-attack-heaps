package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Fields of wind-blown grass: real blade geometry, bent in the vertex shader.

	The technique follows spacejack/terra (itself after "poaceae"), but this is
	our own implementation. Terra is CC BY-NC (non-commercial) as a whole, with
	only some files MIT, so nothing is copied from it.

	- Each blade is a narrow strip of BLADE_SEGS segments that tapers to a
	  point. It has its own position, heading, width, height, lean and
	  natural curve, baked once into the mesh. The shader bends it every frame.
	- Wind: rolling gusts sweep across the field along the wind direction (two
	  crossing sine waves, so the gust fronts wander), pushing blades over more
	  toward their tips, plus a small per-blade flutter. No textures, no CPU work.
	- Lighting is like Terra's: blades are translucent, so they're lit from
	  either side (|N·L|), darker toward the base (cheap ambient occlusion),
	  with a soft sheen when the blade faces between the sun and the camera.
	- Blades are drawn in the alpha pass (still opaque, depth-written) so the
	  ink pass doesn't outline every blade. They receive tree shadows but don't
	  cast any (too many, too thin).

	Per-blade data rides in the standard vertex channels (no custom buffers):
	position = blade root (world), uv = (edge 0/1, height fraction),
	normal = (heading, width, height), colour = (lean, curve, dryness).
	Meshes are chunked by area, so Heaps can frustum-cull fields off screen.
**/
class GrassField {
	public static inline var BLADE_SEGS = 3;
	static inline var CHUNK = 16.0; // metres per mesh tile (for culling)
	static inline var MAX_VERTS = 60000;

	final tiles = new Map<Int, Tile>();
	public var count(default, null) = 0;

	public function new() {}

	/** Add one blade rooted at (x, y, z). Shape values are in metres / radians. **/
	public function blade(x:Float, y:Float, z:Float, heading:Float, width:Float, height:Float, lean:Float, curve:Float, dry:Float) {
		var key = Std.int(Math.floor(x / CHUNK) + 1000) * 4096 + Std.int(Math.floor(y / CHUNK) + 1000);
		var t = tiles.get(key);
		if (t == null || t.pts.length + (BLADE_SEGS + 1) * 2 > MAX_VERTS) {
			if (t != null) t.flush();
			if (t == null) {
				t = new Tile();
				tiles.set(key, t);
			}
		}
		var base = t.pts.length;
		var root = new Point(x, y, z);
		var nrm = new Point(heading, width, height);
		var col = new Point(lean, curve, dry);
		for (d in 0...BLADE_SEGS + 1) {
			var h = d / BLADE_SEGS;
			for (edge in 0...2) {
				t.pts.push(root);
				t.nrm.push(nrm);
				t.col.push(col);
				t.uvs.push(new UV(edge, h));
			}
		}
		for (d in 0...BLADE_SEGS) {
			var a = base + d * 2;
			for (k in [a, a + 1, a + 3, a, a + 3, a + 2]) t.idx.push(k);
		}
		count++;
	}

	public function build(parent:h3d.scene.Object):GrassShader {
		var sh = new GrassShader();
		for (t in tiles) {
			t.flush();
			for (p in t.chunks) {
				var m = new h3d.scene.Mesh(p, parent);
				var mat = m.material;
				mat.mainPass.enableLights = false;
				mat.mainPass.culling = None;
				mat.mainPass.addShader(new render.ink.GeoOut());
				mat.mainPass.addShader(sh);
				// Alpha pass (opaque, depth-written) keeps the blades out of the ink outlines.
				mat.blendMode = Alpha;
				mat.castShadows = false;
				mat.receiveShadows = false;
				FlatMeshBuilder.shadows(mat, false, true);
			}
		}
		return sh;
	}
}

private class Tile {
	public var pts:Array<Point> = [];
	public var nrm:Array<Point> = [];
	public var col:Array<Point> = [];
	public var uvs:Array<UV> = [];
	public var idx:Array<Int> = [];
	public final chunks:Array<h3d.prim.Polygon> = [];

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
}

/** Bends, sways and lights the grass blades (see GrassField). **/
class GrassShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
		};
		@global var camera:{
			var position:Vec3;
		};
		@input var input:{
			var position:Vec3;
			var normal:Vec3;
			var uv:Vec2;
			var color:Vec3;
		};
		/** Toward the sun. **/
		@param var sunDir:Vec3;
		@param var baseColor:Vec3;
		@param var tipColor:Vec3;
		@param var dryColor:Vec3;
		/** Horizontal direction the wind blows toward (normalised). **/
		@param var windDir:Vec2;
		/** How far gusts push blades over (radians at the tip). **/
		@param var windStrength:Float;

		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;
		var bladeColor:Vec3;

		function vertex() {
			var root = input.position;
			var edge = input.uv.x;
			var h = input.uv.y;
			var heading = input.normal.x;
			var width = input.normal.y;
			var height = input.normal.z;
			var lean = input.color.r;
			var curve = input.color.g;
			var dry = input.color.b;
			var t = global.time;

			// Gusts: crossing waves rolling downwind, so the field ripples in bands.
			var along = dot(root.xy, windDir);
			var across = dot(root.xy, vec2(-windDir.y, windDir.x));
			var gust = 0.5 + 0.5 * sin(along * 0.33 - t * 1.7 + sin(across * 0.13 + t * 0.4) * 1.5);
			gust = gust * gust * (0.75 + 0.25 * sin(along * 0.07 - t * 0.5));
			var flutter = 0.1 * sin(t * 3.7 + root.x * 1.9 + root.y * 1.3 + heading * 3.0);

			// The blade's own shape: lean at the base, curving more toward the tip.
			var a = lean + (curve + flutter) * h;
			var hw = width * (1.0 - h * h * h) * (edge - 0.5);
			var fwd = height * h * sin(a);
			var up = height * h * cos(a);
			var c = cos(heading);
			var s = sin(heading);
			var p = vec3(root.x + hw * c - fwd * s, root.y + hw * s + fwd * c, root.z + up);
			// Wind pushes everything downwind, more toward the tip, shortening the blade a little.
			var w = gust * windStrength * h * h;
			p.xy += windDir * (sin(w) * height);
			p.z -= (1.0 - cos(w)) * height;
			transformedPosition = p;

			// Blade normal (the strip's face), rotated with the blade, tipped by the wind.
			var n = normalize(vec3(s * cos(a), -c * cos(a), sin(a)));
			n = normalize(n + vec3(windDir, 0.0) * (-sin(w)) * 0.5);
			transformedNormal = n;

			// Translucent: lit from either side. Darker toward the root.
			var diffuse = abs(dot(n, sunDir));
			var light = (0.72 + 0.38 * diffuse) * (0.72 + 0.28 * h);
			var view = normalize(camera.position - p);
			var sheen = pow(max(dot(normalize(sunDir + view), n) * sign(dot(n, view)), 0.0), 6.0) * 0.18 * h;
			var col = mix(baseColor, tipColor, h);
			col = mix(col, dryColor, dry * 0.6);
			bladeColor = col * light + vec3(sheen, sheen, sheen * 0.5);
		}

		function fragment() {
			pixelColor = vec4(bladeColor, 1.0);
		}
	};

	public function new() {
		super();
		sunDir.set(0.55, 0.35, 0.76);
		sunDir.normalize();
		TerrainStyle.setColor(baseColor, Palette.GRASS_BLADE_BASE);
		TerrainStyle.setColor(tipColor, Palette.GRASS_BLADE_TIP);
		TerrainStyle.setColor(dryColor, Palette.GRASS_BLADE_DRY);
		windDir.set(0.8, 0.6);
		windStrength = 0.75;
	}
}
