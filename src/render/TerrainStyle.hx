package render;

/**
	Terrain colouring, the same in every style: painted grass, dirt, rock,
	sand and gravel textures blended by height, slope and large-scale noise,
	plus the field tint, worn tracks and windswept streaks under the grass.
	(Ink map once kept soft per-vertex colours here, with contours drawn by a
	separate TerrainInk shader; both were retired when the owner asked for
	consistent scenes.)

	Plus sun shading (`light`: soft form light or a real hillshade) and the
	swash of breaking waves running up the beach. The terrain is unlit by the
	scene and shaded here, so the look is controlled by this shader and
	Palette. (The posterised Classic bands lived here until that style was
	retired; the owner found them unnatural.)
**/
class TerrainStyle extends hxsl.Shader {
	/**
		Toward the sun, shared by the light, terrain, grass and water. Fairly low
		(about 40°) so things cast long shadows, as in the Stronghold screenshots.
	**/
	public static final SUN = {x: 0.62, y: 0.4, z: 0.62};

	static var SRC = {
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;

		/** 0 = soft form light; 1 = real hillshade (Sketch): slopes away from the sun go properly dark. **/
		@param var light:Float;
		@param var sunDir:Vec3;

		/** Colour sand fades into below the waterline. **/
		@param var seabed:Vec3;
		@param var tSand:Float;
		@param var tLowland:Float;
		@param var tUpland:Float;


		@global var global:{
			var time:Float;
		};
		/** Swash: each breaker runs up the beach as a film of water with a foam edge (0 = off). **/
		@param var swash:Float;
		/** How high (in metres of elevation) the swash climbs. **/
		@param var swashHeight:Float;
		/** Colour of the thin film of water (the style's shallow-water colour). **/
		@param var swashColor:Vec3;
		/** OceanWaves atlas: only used for the per-shore timing (same as WaterShader.shoreCycle). **/
		@param var waveTex:Sampler2D;
		/** The water's island map (G = exposure to open swell; see WaterShader.setIsland). **/
		@param var exposureMap:Sampler2D;
		@param var grassTex:Sampler2D;
		@param var dirtTex:Sampler2D;
		@param var sandTex:Sampler2D;
		@param var rockTex:Sampler2D;
		/** Loose gravel for the high ground (owner: "more gravel, loose stone"). **/
		@param var gravelTex:Sampler2D;

		@param var mapOrigin:Vec2;
		/** GrassField's map (R = field), to tint the ground under fields like the blades. **/
		@param var fieldMask:Sampler2D;
		@param var fieldGround:Vec3;
		/** Tint of the dusty earth on worn tracks. **/
		@param var dustTint:Vec3;
		@param var mapSize:Float;

		/** Sample a ground texture at two scales so the tiling never shows. **/
		function twoScale(t:Sampler2D, p:Vec2):Vec3 {
			return mix(t.get(p / 3.2).rgb, t.get(p / 11.0 + vec2(0.37, 0.71)).rgb, 0.35);
		}

		function fragment() {
			var h = transformedPosition.z;
			var n = normalize(transformedNormal);

			// Form lighting from the mesh: soft, or a real hillshade.
			var ndl = max(dot(n, sunDir), 0.0);
			var form = mix(0.78 + 0.32 * ndl, 0.36 + 0.78 * ndl, light);

			var col = pixelColor.rgb * form;
			// Blend grass / dirt / rock / sand textures. Band edges are
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

			// The high ground is loose gravel and stones; only the steepest faces show bare rock.
			var cliffW = smoothstep(0.32, 0.5, steep + (patch - 0.5) * 0.25);
			var gravelW = max(smoothstep(tUpland + 0.7, tUpland + 1.5, h + (broad - 0.5) * 1.4), cliffW);
			var gravel = mix(gravelTex.get(p / 2.6).rgb, gravelTex.get(p / 8.3 + vec2(0.41, 0.17)).rgb, 0.3);
			// Damp and dusty patches, as on a real gravel pile seen from above. (Streaks bent
			// along the downhill direction wrapped the hill in fingerprint-like rings; the
			// owner found that pattern computer-made, so the variation is plain patches now.)
			var q = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
			var damp = dirtTex.get(q / 9.1 + vec2(0.3, 0.8)).a;
			var fine = grassTex.get(p / 2.3 + vec2(0.7, 0.2)).a;
			gravel *= 0.88 + 0.2 * damp + 0.08 * (fine - 0.5);
			gravel *= (0.9 + broad * 0.2) * 1.1; // a touch lighter (owner)
			c = mix(c, gravel, gravelW);
			c = mix(c, twoScale(rockTex, p), smoothstep(0.55, 0.75, steep) * 0.7);

			var sandEdge = tSand - 0.05 + (broad - 0.5) * 0.9;
			var sandW = 1.0 - smoothstep(sandEdge - 0.12, sandEdge + 0.12, h);
			var sandC = twoScale(sandTex, p);
			// Wet sand darkens toward the waterline; below it, sand fades into the water's colour.
			sandC *= mix(0.74, 1.0, smoothstep(0.0, 0.45, h));
			sandC = mix(seabed, sandC, smoothstep(-1.2, 0.0, h));
			c = mix(c, sandC, sandW);

			// Under grass fields, the ground takes the blades' colour so gaps read as grass.
			var fm = fieldMask.get((transformedPosition.xy - mapOrigin) / mapSize);
			// Mottled like a real meadow: drier, yellower patches among the greener ones.
			var fg = fieldGround * (0.85 + 0.3 * fm.g);
			fg = mix(fg, fg * vec3(1.32, 1.22, 0.9), smoothstep(0.35, 0.8, fm.b));
			// Windswept streaks combed downwind (the grass wind blows toward +0.8, +0.6), so
			// where blades thin out the ground still reads as grass. Two layers at unrelated
			// scales so the texture's tiling never lines up into a pattern.
			var wa = dot(p, vec2(0.8, 0.6));
			var wc = dot(p, vec2(-0.6, 0.8));
			var s1 = grassTex.get(vec2(wc / 0.37, wa / 1.9)).a;
			var s2 = dirtTex.get(vec2(wc / 0.61 + 0.3, wa / 3.3 + 0.7)).a;
			fg *= 0.88 + 0.16 * s1 + 0.1 * (s2 - 0.5);
			c = mix(c, fg, smoothstep(0.05, 0.6, fm.r) * 0.85 * (1.0 - sandW));

			// Worn ground (Tracks, in the mask's alpha): pale dusty earth, the edge frayed
			// by noise so it breaks up into the grass.
			// Break-up noise at odd scales on rotated axes, so the textures' tiling can't line
			// up into a visible grid (small repeats read as a plaid pattern on the tracks).
			var q = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
			var speck = dirtTex.get(q / 7.3 + vec2(0.21, 0.63)).a;
			var tuft = grassTex.get(p / 3.7 + vec2(0.57, 0.11)).a;
			var wt = smoothstep(0.25, 0.85, fm.a + (patch - 0.5) * 0.5 + (speck - 0.5) * 0.5 + (tuft - 0.5) * 0.3);
			// Even the middle of a track keeps the odd thin, trodden patch of grass.
			wt *= 0.8 + 0.2 * smoothstep(0.35, 0.6, speck);
			var dust = mix(twoScale(dirtTex, p), twoScale(sandTex, p), 0.5);
			// Dusty and pale, not orange: mostly grey earth with a little warmth left.
			dust = mix(vec3(dot(dust, vec3(0.3, 0.55, 0.15))), dust, 0.65) * dustTint;
			dust *= 0.88 + 0.26 * speck;
			wt *= (1.0 - gravelW) * smoothstep(sandEdge + 0.1, sandEdge + 0.4, h);
			c = mix(c, dust, wt);
			col = c * form;
			var exposed = exposureMap.get(clamp((transformedPosition.xy - mapOrigin) / mapSize, vec2(0.0), vec2(1.0))).g;
			if (swash > 0.0 && exposed > 0.01 && h > -0.05 && h < swashHeight * 1.6) {
				var p = transformedPosition.xy;
				var ph = waveTex.get((1.0 + fract(p / 70.0) * 64.0) / vec2(528.0, 264.0)).b;
				var sc = fract(global.time / 6.5 + ph * 2.5);
				// Quick run-up, slow drain back (the breaker reaches the shore as sc wraps to 0).
				var run = sc < 0.25 ? smoothstep(0.0, 0.25, sc) : 1.0 - smoothstep(0.25, 0.95, sc);
				// The reach varies along the beach.
				var nb = waveTex.get((1.0 + fract(p / 6.0) * 64.0) / vec2(528.0, 264.0)).b;
				var lvl = run * swashHeight * (0.7 + 0.6 * nb) * exposed;
				var px = max(fwidth(h), 0.0001);
				var cover = 1.0 - smoothstep(lvl - 2.0 * px, lvl, h);
				// Wet sand: darker where the swash has been.
				var wet = 1.0 - smoothstep(0.0, swashHeight * 1.3, h);
				col *= 1.0 - 0.13 * wet * swash;
				col = mix(col, swashColor, cover * 0.45 * swash);
				// Foam lace at the leading edge, brightest while it rushes in.
				var edge = 1.0 - smoothstep(0.6, 2.2, abs(h - lvl) / px);
				edge *= step(0.004, lvl) * (sc < 0.25 ? 1.0 : 0.55) * (0.5 + 0.5 * nb);
				col = mix(col, vec3(0.96, 0.97, 0.97), edge * 0.8 * swash);
			}
			pixelColor.rgb = col;
		}
	};

	public function new() {
		super();
		swash = 1;
		swashHeight = 0.13;
		setColor(swashColor, 0x8FD3C6);
		waveTex = OceanWaves.texture();
		light = 0;
		var gt = GroundTextures.get();
		grassTex = gt.grass;
		dirtTex = gt.dirt;
		sandTex = gt.sand;
		rockTex = gt.rock;
		gravelTex = gt.gravel;
		sunDir.set(SUN.x, SUN.y, SUN.z);
		sunDir.normalize();
		setColor(seabed, 0x8FD3C6);
		setColor(fieldGround, Palette.FIELD_GROUND);
		setColor(dustTint, Palette.TRACK_DUST);
		fieldMask = h3d.mat.Texture.fromColor(0);
		tSand = world.Island.classicHeight(0.39);
		tLowland = world.Island.classicHeight(0.54);
		tUpland = world.Island.classicHeight(0.70);
	}

	/** Map the island's extent, for samplers indexed by world position (the exposure map). **/
	public function setIsland(island:world.Island) {
		mapOrigin.set(-island.halfExtent, -island.halfExtent);
		mapSize = island.size * island.cell;
	}

	public static function setColor(v:h3d.Vector, c:Int) {
		v.set(Palette.r(c), Palette.g(c), Palette.b(c));
	}
}
