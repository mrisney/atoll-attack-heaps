package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Fields of wind-blown grass, terra-style: a fixed budget of blades drawn
	around where the camera is looking.

	Same model as spacejack/terra (whose BLADES / DEPTH settings the owner
	asked for: 85k-100k blades, depth 85), as our own code. Terra is CC BY-NC
	as a whole, so nothing is copied from it.

	- **A fixed budget** (`blades`, default 100k) instead of grass everywhere.
	  Cost is the same wherever you look, and it's the one knob for phones.
	- **Two layers** sharing the budget. NEAR: 80% of the blades in a dense
	  square patch around the view centre (radius `depth * 0.24`, so ~20 m and
	  ~50 blades/m² at the defaults). FAR: the rest, spread out to `depth`
	  metres, wider and sparser, cross-fading in where NEAR fades out. Beyond
	  that the olive ground under fields (TerrainStyle) carries the look, as in
	  the demo.
	- **Wrapping, not following:** each blade lives on a fixed world grid
	  (its patch offset + k × patch size) and is placed on the copy nearest the
	  view centre. Blades never slide when you pan; they appear and disappear
	  at the far edge, where they're faded out.
	- The vertex shader sets each blade on the ground from the island's height
	  grid (R32F, bilinear by hand, matching `Island.heightAt`). A field map
	  (R = field, G = clump, B = dryness) scales blades to nothing outside
	  meadows. Heights and colours come from the world, not the patch.
	- Wind: rolling gusts sweep downwind, bending blades more toward the tips,
	  plus a per-blade flutter. Lighting: translucent (lit from either side),
	  darker toward the root, a soft sheen, lengthwise streaks.
	- Alpha pass (still opaque) keeps the ink pass from outlining blades. They
	  receive shadows but don't cast them. Heaps doesn't frustum-cull meshes
	  without a collider, so a fixed budget is also what keeps this bounded.
**/
class GrassField {
	public static inline var BLADE_SEGS = 4;
	public static inline var MASK_RES = 256;
	/** Blades per mesh (10 vertices each, under the 16-bit index limit). **/
	static inline var CHUNK = 6000;

	/** Total blades drawn (terra's BLADES). **/
	public final blades:Int;
	/** How far from the view centre grass is drawn, in metres (terra's DEPTH). **/
	public final depth:Float;
	/** Field weight map (R field, G clump, B dryness, A wear: see Tracks), linear, for the terrain too. **/
	public var mask(default, null):h3d.mat.Texture;
	/** One shader per layer; `setFocus` moves both. **/
	public final layers:Array<GrassShader> = [];

	/** Connect the trample map, so blades part around units. **/
	public function setTrample(t:Trample) {
		for (l in layers) {
			l.trample = t.texture;
			l.trampleOrigin = t.origin;
			l.trampleSpan = t.span;
		}
	}

	final island:world.Island;

	/** Defaults for new islands; Main sets these from `?blades=` and `?depth=`. **/
	/** Owner first asked for terra's 85k-100k, then "more, and denser together". Phones: lower via ?blades=. **/
	public static var defaultBlades = 200000;
	public static var defaultDepth = 85.0;

	public function new(island:world.Island, ?blades:Int, ?depth:Float) {
		if (blades == null) blades = defaultBlades;
		if (depth == null) depth = defaultDepth;
		this.island = island;
		this.blades = blades;
		this.depth = depth;
	}

	/** Centre the grass on this world point (the camera's look-at), every frame. **/
	public function setFocus(x:Float, y:Float, ?viewDistance:Float) {
		// Zoomed in, the same blades are packed into a smaller patch: denser where
		// individual blades can be seen (owner: "finer, closer together"). Zoomed
		// out, the patch spreads to `depth` and the ground colour carries the look.
		var s = viewDistance == null ? 1.0 : Math.max(0.3, Math.min(1.0, viewDistance / 45));
		for (l in layers) {
			l.focus.set(x, y);
			l.scale = s;
		}
	}

	/**
		Build the fields. `weight(x, y)` says how much field grows at a world
		point (0..1). Called once per island.
	**/
	public function build(parent:h3d.scene.Object, weight:(Float, Float) -> Float, ?wear:(Float, Float) -> Float) {
		var he = island.halfExtent;
		var span = he * 2;

		// --- field map ---------------------------------------------------------
		var clumpN = new world.Noise(island.seed + 606), dryN = new world.Noise(island.seed + 707);
		var px = hxd.Pixels.alloc(MASK_RES, MASK_RES, RGBA);
		inline function c8(v:Float) return Std.int(Math.max(0, Math.min(1, v)) * 255 + 0.5);
		for (j in 0...MASK_RES)
			for (i in 0...MASK_RES) {
				var x = (i + 0.5) / MASK_RES * span - he, y = (j + 0.5) / MASK_RES * span - he;
				var w = weight(x, y);
				var clump = clumpN.fbm(x * 0.45 + 3, y * 0.45 + 3, 2);
				var dry = dryN.fbm(x * 0.09 + 5, y * 0.09 + 5, 3);
				var worn = wear == null ? 0.0 : wear(x, y);
				px.setPixel(i, j, (c8(worn) << 24) | (c8(w) << 16) | (c8(clump) << 8) | c8(dry));
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

		// --- the two layers --------------------------------------------------------
		// A tighter near patch than terra's: ~70 blades/m² at the defaults (owner: "finer,
		// closer together").
		var nearR = depth * 0.25;
		// The near patch fades out over a wide band and the far layer (more blades than
		// terra's, over a shorter reach) fades in under it, so there's no visible edge.
		var nearCount = Std.int(blades * 0.6);
		var farR = depth * 0.6;
		addLayer(parent, nearCount, nearR * 2, 1.0, -2, -1, nearR * 0.55, nearR, 101, heightTex, he, span);
		addLayer(parent, blades - nearCount, farR * 2, 1.8, nearR * 0.45, nearR * 0.9, farR * 0.8, farR, 202, heightTex, he, span);
	}

	function addLayer(parent:h3d.scene.Object, count:Int, size:Float, widthScale:Float, inA:Float, inB:Float, outA:Float, outB:Float,
			seed:Int, heightTex:h3d.mat.Texture, he:Float, span:Float) {
		var sh = new GrassShader();
		sh.mask = mask;
		sh.heights = heightTex;
		sh.gridOrigin.set(-he, -he);
		sh.cell = island.cell;
		sh.gridSize = island.size + 1;
		sh.maskOrigin.set(-he, -he);
		sh.maskSize = span;
		sh.patchSize = size;
		sh.widthScale = widthScale;
		sh.fadeIn.set(inA, inB);
		sh.fadeOut.set(outA, outB);
		layers.push(sh);
		var rnd = new world.Noise(4711 + seed);
		var k = 0;
		var left = count;
		while (left > 0) {
			var n = left < CHUNK ? left : CHUNK;
			left -= n;
			var m = new h3d.scene.Mesh(buildPatch(n, size, () -> rnd.rand(k++, 17)), parent);
			var mat = m.material;
			mat.mainPass.enableLights = false;
			mat.mainPass.culling = None;
			mat.mainPass.addShader(new render.ink.GeoOut());
			mat.mainPass.addShader(sh);
			// Alpha pass (opaque, depth-written) keeps the blades out of the ink outlines.
			mat.blendMode = Alpha;
			FlatMeshBuilder.shadows(mat, false, true);
		}
	}

	/**
		`n` blades scattered over a `size`-metre square (patch-local). Per-blade
		data rides in the standard channels: position = offset in the patch,
		uv = (edge, height fraction), normal = (heading, width, height),
		colour = (lean, curve, tone).
	**/
	static function buildPatch(n:Int, size:Float, r:() -> Float):h3d.prim.Polygon {
		var pts:Array<Point> = [], nrm:Array<Point> = [], col:Array<Point> = [], uvs:Array<UV> = [];
		var idx = new hxd.IndexBuffer();
		for (b in 0...n) {
			var root = new Point(r() * size, r() * size, 0);
			// Fine, long blades (owner's windswept-meadow reference): 1-2 cm wide, 30-70 cm long.
			var nm = new Point(r() * Math.PI * 2, 0.013 + r() * 0.012, 0.3 + r() * 0.4);
			var cl = new Point((r() - 0.5) * 0.3, 0.25 + r() * 0.5, r());
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
		/** View centre the grass wraps around, and this layer's patch size. **/
		@param var focus:Vec2;
		@param var patchSize:Float;
		/** Shrinks the patch (and the fade distances) to pack blades denser when zoomed in. **/
		@param var scale:Float;
		@param var widthScale:Float;
		/** Distance from the focus where the layer fades in (x..y) and out (x..y). **/
		@param var fadeIn:Vec2;
		@param var fadeOut:Vec2;
		/** Trample map (RG push direction, B amount; see Trample). **/
		@param var trample:Sampler2D;
		@param var trampleOrigin:Float;
		@param var trampleSpan:Float;

		/** Toward the sun. **/
		@param var sunDir:Vec3;
		@param var baseColor:Vec3;
		@param var tipColor:Vec3;
		@param var dryColor:Vec3;
		/** Horizontal direction the wind blows toward (normalised). **/
		@param var windDir:Vec2;
		/** How far gusts push blades over (radians at the tip). **/
		@param var windStrength:Float;
		/** Constant lay-over downwind (radians at the tip): a windswept meadow, every blade combed the same way. **/
		@param var sweep:Float;

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
			// Wrap this blade onto the copy of the patch grid nearest the view centre.
			var off = input.position.xy * scale;
			var ps = patchSize * scale;
			var root = off + floor((focus - off) / ps) * ps + ps * 0.5;
			var dist = length(root - focus);
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
			var grow = smoothstep(0.02, 0.5, m.r) * smoothstep(fadeIn.x * scale, fadeIn.y * scale, dist) * (1.0 - smoothstep(fadeOut.x * scale, fadeOut.y * scale, dist));
			// Worn ground (tracks): fewer, shorter, drier blades. Each blade survives up to
			// its own threshold, so the edge frays into straggling tufts, not a clean line.
			var wear = m.a;
			var keep = step(wear * 1.05 - 0.15, fract(tone * 31.0));
			grow *= keep * (1.0 - wear * 0.55);
			height *= grow * (0.55 + 0.9 * m.g);
			width *= (0.4 + 0.6 * grow) * widthScale;
			height *= step(0.001, grow);
			var dry = clamp(m.b * 1.8 - 0.6 + (tone - 0.5) * 0.5 + wear * 0.6, 0.0, 1.0);

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
			// Trampled: blades part away from the unit, bending from the root, and the wind
			// has less to catch.
			var tr = trample.getLod((root - trampleOrigin) / trampleSpan, 0.0);
			var push = tr.b;
			var pdir = tr.rg * 2.0 - 1.0;
			var w = (sweep * (0.75 + 0.5 * curve) + gust * windStrength) * h * h * (1.0 - push * 0.8);
			p.xy += windDir * (sin(w) * height);
			p.z -= (1.0 - cos(w)) * height;
			var tb = push * 1.35 * h;
			p.xy += pdir * (sin(tb) * height * h);
			p.z -= (1.0 - cos(tb)) * height * h;
			transformedPosition = p;

			var n = normalize(vec3(s * cos(a), -c * cos(a), sin(a)));
			n = normalize(n + vec3(windDir, 0.0) * (-sin(w)) * 0.5);
			transformedNormal = n;

			// Translucent: lit from either side; darker toward the root (cheap AO).
			var diffuse = abs(dot(n, sunDir));
			var light = 0.66 + 0.4 * diffuse;
			var low = 1.0 - h;
			light -= low * low * 0.3;
			var view = normalize(camera.position - p);
			var sheen = pow(max(dot(normalize(sunDir + view), n) * sign(dot(n, view)), 0.0), 6.0) * 0.16 * h;
			var col = mix(baseColor, tipColor, h * 0.85 + 0.15 * tone);
			col = mix(col, dryColor, dry * 0.7);
			// Seed heads: about one blade in five ends in a pale, straw-coloured tip.
			col = mix(col, dryColor * 1.08, smoothstep(0.72, 1.0, h) * step(0.8, fract(tone * 17.0)) * 0.85);
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
		sunDir.set(TerrainStyle.SUN.x, TerrainStyle.SUN.y, TerrainStyle.SUN.z);
		sunDir.normalize();
		TerrainStyle.setColor(baseColor, Palette.GRASS_BLADE_BASE);
		TerrainStyle.setColor(tipColor, Palette.GRASS_BLADE_TIP);
		TerrainStyle.setColor(dryColor, Palette.GRASS_BLADE_DRY);
		windDir.set(0.8, 0.6);
		windStrength = 0.55;
		scale = 1;
		sweep = 0.85;
		trample = h3d.mat.Texture.fromColor(0x808000);
		trampleOrigin = 0;
		trampleSpan = 1;
	}
}
