package render.ink;

/**
	Tilt-shift: a horizontal band in focus, gradually blurring toward the top
	and bottom of the screen. It makes the scene read as a detailed miniature
	and softens the far distance. 13 taps in two rings, so it's cheap enough
	for phones.
**/
class TiltShift extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var frame:Sampler2D;
		@param var texel:Vec2;
		@param var focusCenter:Float;
		@param var focusWidth:Float;
		@param var falloff:Float;
		@param var maxRadius:Float;
		/** Colour grade (0 = off): a little desaturated and warm, gentle contrast, vignette. **/
		@param var grade:Float;

		// Weather (render.Weather), all 0 = clear.
		/** Rain streaks over the frame (0..1 density). **/
		@param var rain:Float;
		/** Storm grade: darker, cooler, flatter light (0..1). **/
		@param var storm:Float;
		/** Fog: a pale haze, thicker toward the top of the frame (the far side), drifting. **/
		@param var fog:Float;
		@param var fogColor:Vec3;
		/** Tileable noise (a ground texture's alpha) for the drifting fog. **/
		@param var noise:Sampler2D;
		@param var time:Float;
		/** Width / height of the frame, so rain streaks stay thin on any aspect. **/
		@param var aspect:Float;

		/** One layer of rain: slanted streaks falling down the screen. **/
		function rainLayer(uv:Vec2, cols:Float, rows:Float, speed:Float, seed:Float):Float {
			var p = vec2(uv.x * aspect, uv.y);
			p.x += p.y * 0.18; // wind-blown slant
			var g = p * vec2(cols, rows);
			var col = floor(g.x);
			var r1 = fract(sin(col * 12.9898 + seed) * 43758.5453);
			var r2 = fract(sin(col * 78.233 + seed * 1.7) * 24634.6345);
			var y = fract(g.y - time * speed * (0.8 + 0.4 * r1) + r1 * 7.0);
			// A short streak with a soft tail, only in some columns.
			var len = 0.22 + 0.12 * r2;
			var streak = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(0.03, len, y));
			var x = abs(fract(g.x) - 0.5);
			var thin = 1.0 - smoothstep(0.04, 0.12, x);
			return streak * thin * step(0.45, r2);
		}

		function fragment() {
			var uv = calculatedUV;
			var d = abs(uv.y - focusCenter);
			var r = smoothstep(focusWidth, focusWidth + falloff, d) * maxRadius;
			var o = texel * r;
			var c = frame.get(uv).rgb * 2.0;
			// Inner ring (6 taps) and outer ring (6 taps, rotated).
			c += frame.get(uv + o * vec2(0.5, 0.0)).rgb;
			c += frame.get(uv + o * vec2(0.25, 0.433)).rgb;
			c += frame.get(uv + o * vec2(-0.25, 0.433)).rgb;
			c += frame.get(uv + o * vec2(-0.5, 0.0)).rgb;
			c += frame.get(uv + o * vec2(-0.25, -0.433)).rgb;
			c += frame.get(uv + o * vec2(0.25, -0.433)).rgb;
			c += frame.get(uv + o * vec2(0.866, 0.5)).rgb;
			c += frame.get(uv + o * vec2(0.0, 1.0)).rgb;
			c += frame.get(uv + o * vec2(-0.866, 0.5)).rgb;
			c += frame.get(uv + o * vec2(-0.866, -0.5)).rgb;
			c += frame.get(uv + o * vec2(0.0, -1.0)).rgb;
			c += frame.get(uv + o * vec2(0.866, -0.5)).rgb;
			c /= 14.0;
			if (grade > 0.0) {
				// Film-like grade, as in the Stronghold screenshots the owner pointed at:
				// muted greens, warm light, a soft S-curve and darkened corners.
				var l = dot(c, vec3(0.3, 0.59, 0.11));
				var g = mix(vec3(l), c, 0.8) * vec3(1.04, 1.0, 0.93);
				g = mix(g, g * g * (3.0 - 2.0 * g), 0.35);
				var v = uv - 0.5;
				g *= 1.0 - dot(v, v) * 0.75;
				c = mix(c, g, grade);
			}
			if (storm > 0.0) {
				// Overcast: darker, cooler, less saturated, flatter.
				var l = dot(c, vec3(0.3, 0.59, 0.11));
				var s = mix(vec3(l), c, 0.62) * vec3(0.9, 0.96, 1.04) * 0.8;
				s = mix(s, vec3(l * 0.8), 0.1);
				c = mix(c, s, storm);
			}
			if (fog > 0.0) {
				// Thicker toward the top of the frame (farther away in this camera), drifting.
				var n = noise.get(uv * vec2(aspect, 1.0) * 0.7 + vec2(time * 0.012, time * 0.004)).a;
				var n2 = noise.get(uv * vec2(aspect, 1.0) * 1.9 - vec2(time * 0.02, 0.0)).a;
				var amount = fog * (0.28 + 0.5 * smoothstep(0.85, 0.0, uv.y)) * (0.7 + 0.45 * n + 0.2 * n2);
				c = mix(c, fogColor, clamp(amount, 0.0, 0.92));
			}
			if (rain > 0.0) {
				var r = rainLayer(uv, 110.0, 3.0, 2.4, 1.0) * 0.55 + rainLayer(uv, 60.0, 1.6, 1.6, 7.0) * 0.8;
				c = mix(c, vec3(0.78, 0.83, 0.88), clamp(r * rain, 0.0, 1.0) * 0.4);
			}
			pixelColor = vec4(c, 1.0);
		}
	};

	public function new() {
		super();
		focusCenter = 0.55;
		focusWidth = 0.16;
		falloff = 0.4;
		maxRadius = 3.2;
		grade = 0;
		rain = 0;
		storm = 0;
		fog = 0;
		time = 0;
		aspect = 1;
		noise = render.GroundTextures.get().dirt;
		render.TerrainStyle.setColor(fogColor, render.Palette.FOG);
	}
}
