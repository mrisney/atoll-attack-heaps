package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Fields of wind-blown grass, dense enough to read as a carpet.

	The approach follows spacejack/terra (after "poaceae"), as our own code:
	Terra is CC BY-NC as a whole, so nothing is copied from it.

	- **One shared patch** of TILE×TILE metres holds thousands of blades, each a
	  tapered strip of BLADE_SEGS segments with its own heading, width, height,
	  lean, curve and a random tone. The same geometry is drawn at every tile
	  that has field in it (one Mesh per tile sharing one primitive), so density
	  costs GPU time only where you're looking, and almost no memory.
	- The vertex shader puts each blade on the ground by reading the island's
	  height grid (R32F, bilinear done by hand so it matches `Island.heightAt`
	  exactly). It reads a field map (R = how much field grows, G = clumpiness,
	  B = dryness) and scales blades down to nothing at field edges and in
	  forest. That way the repeating patch never shows: heights and colours
	  come from the world, not the patch.
	- Wind: rolling gusts sweep downwind and bend blades more toward the tips,
	  plus a per-blade flutter.
	- Lighting: translucent (lit from either side), darker toward the root,
	  a soft sheen toward the sun, and lengthwise streaks across each blade.
	  The ground under fields is tinted to the blade colour (TerrainStyle), so
	  any gaps read as grass, not as bare painted ground.
	- Alpha pass (still opaque) keeps the ink pass from outlining blades. They
	  receive shadows but don't cast them.
**/
class GrassField {
	public static inline var BLADE_SEGS = 3;
	public static inline var TILE = 10.0;
	/** Blades per square metre at full field strength. **/
	public static inline var DENSITY = 34.0;
	public static inline var MASK_RES = 256;

	public var bladesPerTile(default, null) = 0;
	public var tileCount(default, null) = 0;
	/** Field weight map (R field, G clump, B dryness), linear, for the terrain tint too. **/
	public var mask(default, null):h3d.mat.Texture;

	final island:world.Island;

	public function new(island:world.Island) {
		this.island = island;
	}

	/**
		Build the fields. `weight(x, y)` says how much field grows at a world
		point (0..1). Called once per island.
	**/
	public function build(parent:h3d.scene.Object, weight:(Float, Float) -> Float):GrassShader {
		var he = island.halfExtent;
		var span = he * 2;

		// --- field map ---------------------------------------------------------
		var clumpN = new world.Noise(island.seed + 606), dryN = new world.Noise(island.seed + 707);
		var px = hxd.Pixels.alloc(MASK_RES, MASK_RES, RGBA);
		var wts = new Array<Float>();
		wts.resize(MASK_RES * MASK_RES);
		inline function c8(v:Float) return Std.int(Math.max(0, Math.min(1, v)) * 255 + 0.5);
		for (j in 0...MASK_RES)
			for (i in 0...MASK_RES) {
				var x = (i + 0.5) / MASK_RES * span - he, y = (j + 0.5) / MASK_RES * span - he;
				var w = weight(x, y);
				wts[j * MASK_RES + i] = w;
				var clump = clumpN.fbm(x * 0.45 + 3, y * 0.45 + 3, 2);
				var dry = dryN.fbm(x * 0.09 + 5, y * 0.09 + 5, 3);
				px.setPixel(i, j, 0xFF000000 | (c8(w) << 16) | (c8(clump) << 8) | c8(dry));
			}
		mask = h3d.mat.Texture.fromPixels(px);
		mask.filter = Linear;
		mask.wrap = Clamp;

		// --- height grid (exact ground under every blade) ------------------------
		var w = island.size + 1;
		var hp = hxd.Pixels.alloc(w, w, R32F);
		for (j in 0...w)
			for (i in 0...w)
				hp.bytes.setFloat((j * w + i) << 2, island.heightAtVertex(i, j));
		var heightTex = new h3d.mat.Texture(w, w, null, R32F);
		heightTex.uploadPixels(hp);
		heightTex.filter = Nearest;
		heightTex.wrap = Clamp;

		// --- the shared patch ----------------------------------------------------
		var patch = buildPatch();

		var sh = new GrassShader();
		sh.mask = mask;
		sh.heights = heightTex;
		sh.gridOrigin.set(-he, -he);
		sh.cell = island.cell;
		sh.gridSize = w;
		sh.maskOrigin.set(-he, -he);
		sh.maskSize = span;

		// --- a mesh per tile that has any field in it ---------------------------
		var tiles = Std.int(Math.ceil(span / TILE));
		for (tj in 0...tiles)
			for (ti in 0...tiles) {
				var x0 = -he + ti * TILE, y0 = -he + tj * TILE;
				// Any field in this tile? (check the map over its area, with a margin)
				var any = false;
				var i0 = Std.int((x0 + he) / span * MASK_RES) - 1, i1 = Std.int((x0 + TILE + he) / span * MASK_RES) + 1;
				var j0 = Std.int((y0 + he) / span * MASK_RES) - 1, j1 = Std.int((y0 + TILE + he) / span * MASK_RES) + 1;
				for (j in Std.int(Math.max(0, j0))...Std.int(Math.min(MASK_RES, j1)))
					for (i in Std.int(Math.max(0, i0))...Std.int(Math.min(MASK_RES, i1)))
						if (wts[j * MASK_RES + i] > 0.02) any = true;
				if (!any) continue;
				var m = new h3d.scene.Mesh(patch, parent);
				m.x = x0;
				m.y = y0;
				var mat = m.material;
				mat.mainPass.enableLights = false;
				mat.mainPass.culling = None;
				mat.mainPass.addShader(new render.ink.GeoOut());
				mat.mainPass.addShader(sh);
				// Alpha pass (opaque, depth-written) keeps the blades out of the ink outlines.
				mat.blendMode = Alpha;
				FlatMeshBuilder.shadows(mat, false, true);
				tileCount++;
			}
		return sh;
	}

	/**
		TILE×TILE metres of blades in tile-local coordinates. Per-blade data rides
		in the standard channels: position = root (local), uv = (edge, height
		fraction), normal = (heading, width, height), colour = (lean, curve, tone).
	**/
	function buildPatch():h3d.prim.Polygon {
		var pts:Array<Point> = [], nrm:Array<Point> = [], col:Array<Point> = [], uvs:Array<UV> = [];
		var idx = new hxd.IndexBuffer();
		var n = Std.int(TILE * TILE * DENSITY);
		var rnd = new world.Noise(4711);
		var k = 0;
		inline function r():Float return rnd.rand(k++, 17);
		for (b in 0...n) {
			var root = new Point(r() * TILE, r() * TILE, 0);
			var nm = new Point(r() * Math.PI * 2, 0.05 + r() * 0.04, 0.32 + r() * 0.36);
			var cl = new Point((r() - 0.5) * 0.45, 0.2 + r() * 0.45, r());
			var base = pts.length;
			for (d in 0...BLADE_SEGS + 1)
				for (edge in 0...2) {
					pts.push(root);
					nrm.push(nm);
					col.push(cl);
					uvs.push(new UV(edge, d / BLADE_SEGS));
				}
			for (d in 0...BLADE_SEGS) {
				var a = base + d * 2;
				for (q in [a, a + 1, a + 3, a, a + 3, a + 2]) idx.push(q);
			}
		}
		// A zero-area triangle spanning heights -10..14 m, so the patch's bounds
		// cover any ground height (the shader sets the real z) and culling stays correct.
		var base = pts.length;
		for (z in [-10.0, 14.0, 14.0]) {
			pts.push(new Point(TILE * 0.5, TILE * 0.5, z));
			nrm.push(new Point(0, 0, 0));
			col.push(new Point(0, 0, 0));
			uvs.push(new UV(0, 0));
		}
		for (q in [base, base + 1, base + 2]) idx.push(q);
		bladesPerTile = n;
		var p = new h3d.prim.Polygon(pts, idx);
		p.normals = nrm;
		p.colors = col;
		p.uvs = uvs;
		return p;
	}
}

/** Places, bends, sways and lights the grass blades (see GrassField). **/
class GrassShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
			@perObject var modelView:Mat4;
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
		@param var heights:Sampler2D;
		@param var gridOrigin:Vec2;
		@param var cell:Float;
		@param var gridSize:Float;
		@param var mask:Sampler2D;
		@param var maskOrigin:Vec2;
		@param var maskSize:Float;

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
		var bladeEdge:Float;

		function texel(i:Float, j:Float):Float {
			return heights.getLod((vec2(i, j) + 0.5) / gridSize, 0.0).r;
		}

		/** Ground height, bilinear over the island's vertex grid (matches Island.heightAt). **/
		function ground(p:Vec2):Float {
			var g = clamp((p - gridOrigin) / cell, vec2(0.0), vec2(gridSize - 1.001));
			var i = floor(g);
			var f = g - i;
			var a = texel(i.x, i.y);
			var b = texel(i.x + 1.0, i.y);
			var c = texel(i.x, i.y + 1.0);
			var d = texel(i.x + 1.0, i.y + 1.0);
			return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
		}

		function vertex() {
			var root = (input.position * global.modelView.mat3x4()).xy;
			var edge = input.uv.x;
			var h = input.uv.y;
			var heading = input.normal.x;
			var width = input.normal.y;
			var height = input.normal.z;
			var lean = input.color.r;
			var curve = input.color.g;
			var tone = input.color.b;
			var t = global.time;

			// How much field grows here, clumpiness and dryness: from the world, not the patch.
			var m = mask.getLod((root - maskOrigin) / maskSize, 0.0);
			var grow = smoothstep(0.02, 0.5, m.r);
			height *= grow * (0.55 + 0.9 * m.g);
			width *= 0.4 + 0.6 * grow;
			var dry = clamp(m.b * 1.6 - 0.55 + (tone - 0.5) * 0.5, 0.0, 1.0);

			// Gusts: crossing waves rolling downwind, so the field ripples in bands.
			var along = dot(root, windDir);
			var across = dot(root, vec2(-windDir.y, windDir.x));
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
			var p = vec3(root.x + hw * c - fwd * s, root.y + hw * s + fwd * c, ground(root) - 0.03 + up);
			// Wind pushes everything downwind, more toward the tip, shortening the blade a little.
			var w = gust * windStrength * h * h;
			p.xy += windDir * (sin(w) * height);
			p.z -= (1.0 - cos(w)) * height;
			transformedPosition = p;

			var n = normalize(vec3(s * cos(a), -c * cos(a), sin(a)));
			n = normalize(n + vec3(windDir, 0.0) * (-sin(w)) * 0.5);
			transformedNormal = n;

			// Translucent: lit from either side; darker toward the root (cheap AO).
			var diffuse = abs(dot(n, sunDir));
			var light = 0.66 + 0.4 * diffuse;
			var low = 1.0 - h;
			light -= low * low * 0.42;
			var view = normalize(camera.position - p);
			var sheen = pow(max(dot(normalize(sunDir + view), n) * sign(dot(n, view)), 0.0), 6.0) * 0.16 * h;
			var col = mix(baseColor, tipColor, h * 0.85 + 0.15 * tone);
			col = mix(col, dryColor, dry * 0.7);
			// Per-blade variation, so the carpet isn't one flat colour.
			col *= vec3(0.9 + 0.2 * tone, 0.94 + 0.12 * fract(tone * 7.0), 0.9 + 0.1 * fract(tone * 13.0));
			bladeColor = col * light + vec3(sheen, sheen, sheen * 0.4);
			bladeEdge = edge;
		}

		function fragment() {
			// Lengthwise streaks: a lighter midrib, darker edges.
			var e = abs(bladeEdge - 0.5) * 2.0;
			var streak = 1.04 - 0.2 * e * e;
			pixelColor = vec4(bladeColor * streak, 1.0);
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
		windStrength = 0.7;
	}
}
