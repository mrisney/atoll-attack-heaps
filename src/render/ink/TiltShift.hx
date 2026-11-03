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
	}
}
