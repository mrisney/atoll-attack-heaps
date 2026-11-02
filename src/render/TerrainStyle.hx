package render;

/**
	Terrain colouring, two looks in one shader:

	- Classic (`bands = 1`): the atoll-attack look, ported from
	  island_water.frag — hard posterised elevation bands (sand, lowland,
	  upland, peak) with a crinkly "relief" highlight from the direction of the
	  fbm gradient (baked to a texture per island).
	- Ink map (`bands = 0`): keeps the soft per-vertex colours.

	Either way the terrain is unlit by the scene and shaded here, so the look
	is controlled entirely by this shader and Palette.
**/
class TerrainStyle extends hxsl.Shader {
	static var SRC = {
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;

		@param var bands:Float;
		@param var relief:Float;
		/** 0 = the soft classic form light; 1 = real hillshade (Sketch): slopes away from the sun go properly dark. **/
		@param var light:Float;
		@param var sunDir:Vec3;

		@param var sand:Vec3;
		@param var lowland:Vec3;
		@param var upland:Vec3;
		@param var peak:Vec3;
		@param var seabed:Vec3;
		@param var tSand:Float;
		@param var tLowland:Float;
		@param var tUpland:Float;

		@param var painted:Float;
		@param var grassTex:Sampler2D;
		@param var dirtTex:Sampler2D;
		@param var sandTex:Sampler2D;
		@param var rockTex:Sampler2D;

		@param var reliefMap:Sampler2D;
		@param var mapOrigin:Vec2;
		@param var mapSize:Float;

		/** Sample a ground texture at two scales so the tiling never shows. **/
		function twoScale(t:Sampler2D, p:Vec2):Vec3 {
			return mix(t.get(p / 3.2).rgb, t.get(p / 11.0 + vec2(0.37, 0.71)).rgb, 0.35);
		}

		/** Hard band edge, anti-aliased by one pixel. **/
		function band(h:Float, t:Float):Float {
			var aa = max(fwidth(h), 0.0001);
			return smoothstep(t - aa, t + aa, h);
		}

		function fragment() {
			var h = transformedPosition.z;
			var n = normalize(transformedNormal);

			// Soft form lighting from the mesh, same range as the original's highlight.
			var ndl = max(dot(n, sunDir), 0.0);
			var form = mix(0.78 + 0.32 * ndl, 0.36 + 0.78 * ndl, light);

			var col = pixelColor.rgb * form;
			if (painted > 0.5) {
				// Painted: blend grass / dirt / rock / sand textures. Band edges are
				// pushed around by large-scale noise (texture alpha) so they wander
				// naturally instead of following contour lines.
				var p = transformedPosition.xy;
				var broad = grassTex.get(p / 70.0).a; // very large-scale variation
				var patch = dirtTex.get(p / 26.0).a; // medium patches
				var steep = 1.0 - n.z;

				var grass = twoScale(grassTex, p);
				// Lusher low, drier and darker higher up.
				grass *= mix(vec3(1.05, 1.04, 0.95), vec3(0.86, 0.9, 0.86), smoothstep(tLowland - 0.6, tUpland + 0.4, h + (broad - 0.5) * 1.2));
				grass *= 0.9 + broad * 0.2;
				var c = grass;

				var dirtW = smoothstep(0.6, 0.72, patch) * (1.0 - smoothstep(tUpland, tUpland + 0.6, h));
				c = mix(c, twoScale(dirtTex, p), dirtW);

				var rockW = max(smoothstep(0.32, 0.5, steep + (patch - 0.5) * 0.25), smoothstep(tUpland - 0.3, tUpland + 0.5, h + (broad - 0.5) * 1.4));
				c = mix(c, twoScale(rockTex, p), rockW);

				var sandEdge = tSand - 0.05 + (broad - 0.5) * 0.9;
				var sandW = 1.0 - smoothstep(sandEdge - 0.12, sandEdge + 0.12, h);
				var sandC = twoScale(sandTex, p);
				// Wet sand darkens toward the waterline; below it, sand fades into the water's colour.
				sandC *= mix(0.74, 1.0, smoothstep(0.0, 0.45, h));
				sandC = mix(seabed, sandC, smoothstep(-1.2, 0.0, h));
				c = mix(c, sandC, sandW);

				col = c * form;
			} else if (bands > 0.5) {
				var c = mix(seabed, sand, band(h, -0.05));
				c = mix(c, lowland, band(h, tSand));
				c = mix(c, upland, band(h, tLowland));
				c = mix(c, peak, band(h, tUpland));

				// The original's relief highlight, baked per island (see bakeRelief).
				var hl = 0.7 + reliefMap.get((transformedPosition.xy - mapOrigin) / mapSize).r * 0.4;
				var land = step(-0.05, h);
				hl = mix(1.0, mix(1.0, hl, relief), land);

				col = c * hl * mix(1.0, form, 0.6);
			}
			pixelColor.rgb = col;
		}
	};

	public function new() {
		super();
		bands = 1;
		painted = 0;
		relief = 1;
		light = 0;
		var gt = GroundTextures.get();
		grassTex = gt.grass;
		dirtTex = gt.dirt;
		sandTex = gt.sand;
		rockTex = gt.rock;
		sunDir.set(0.55, 0.35, 0.76);
		sunDir.normalize();
		setColor(sand, 0xFFFFA6);
		setColor(lowland, 0xBDF270);
		setColor(upland, 0x9CCC4F);
		setColor(peak, 0xD9D9D4);
		setColor(seabed, 0x87D1FA);
		tSand = world.Island.classicHeight(0.39);
		tLowland = world.Island.classicHeight(0.54);
		tUpland = world.Island.classicHeight(0.70);
	}

	/**
		Bake the relief highlight into a texture once per island. Doing the
		fbm gradient per pixel costs ~25 noise lookups — fine on a desktop GPU,
		too heavy for phones — so it's computed on the CPU here instead.
	**/
	public function bakeRelief(island:world.Island, res = 384) {
		var px = hxd.Pixels.alloc(res, res, RGBA);
		var n = new world.Noise(island.seed);
		var lx = sunDir.x, ly = sunDir.y;
		var ll = Math.sqrt(lx * lx + ly * ly);
		lx /= ll;
		ly /= ll;
		for (j in 0...res)
			for (i in 0...res) {
				var nx = (i + 0.5) / res * 2 - 1;
				var ny = (j + 0.5) / res * 2 - 1;
				var v = island.shape == Single ? island.classicRelief(nx, ny, n, lx, ly) : 0.9;
				var b = Std.int((v - 0.7) / 0.4 * 255 + 0.5);
				px.setPixel(i, j, 0xFF000000 | (b << 16) | (b << 8) | b);
			}
		if (reliefMap != null) reliefMap.dispose();
		reliefMap = h3d.mat.Texture.fromPixels(px);
		reliefMap.filter = Linear;
		reliefMap.wrap = Clamp;
		mapOrigin.set(-island.halfExtent, -island.halfExtent);
		mapSize = island.size * island.cell;
	}

	public static function setColor(v:h3d.Vector, c:Int) {
		v.set(Palette.r(c), Palette.g(c), Palette.b(c));
	}
}
