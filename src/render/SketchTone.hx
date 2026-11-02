package render;

/**
	The Sketch style's colour treatment, after architectural presentation
	drawings: nature goes to muted earth tones on warm paper (sage instead of
	bright green, slate instead of bright blue), and what people built from
	wood (docks, the flag pole) keeps its full colour, so timber stays the
	warmest, richest thing on the page.

	Two shared instances: a light one for the ground and water (lifts toward
	the page) and a darker one for props (trees read as graphite against
	the page). Every island material except the timber ones gets one. `amount = 0` turns it off for the other styles.

	- Brightness is remapped (gain/curve) and then a fraction of the original
	  hue is put back (`chroma`), pulled toward ochre (`earth`), so greens read
	  as olive and sage, and blues as grey-green slate.
	- A faint, blotchy grain (from the painted dirt texture's noise, in world
	  space) gives the ground the scuffed marks of a printed drawing.
**/
class SketchTone extends hxsl.Shader {
	static var SRC = {
		@param var amount:Float;
		/** Brightness gain and curve: ground lifts toward the page, props stay darker. **/
		@param var gain:Float;
		@param var curve:Float;
		/** How much of the original hue survives (0 = pure graphite). **/
		@param var chroma:Float;
		/** Warm bias applied to the restored colour. **/
		@param var earth:Vec3;
		@param var paper:Vec3;
		@param var graphite:Vec3;
		@param var grain:Sampler2D;
		var transformedPosition:Vec3;
		var pixelColor:Vec4;

		function fragment() {
			var c = pixelColor.rgb;
			var l = dot(c, vec3(0.3, 0.59, 0.11));
			// Lift midtones to the page, keep darks dark.
			var v = pow(clamp(l * gain, 0.0, 1.0), curve);
			var g = mix(graphite, paper, v);
			// Put back a muted share of the hue, biased warm.
			var hue = c / max(l, 0.001);
			g *= mix(vec3(1.0), hue * earth, chroma);
			var p = transformedPosition.xy;
			var blot = grain.get(p / 21.0).a;
			var fleck = grain.get(p / 2.7).r;
			g *= 0.95 + 0.07 * blot + 0.04 * (fleck - 0.5);
			pixelColor.rgb = mix(c, g, amount);
		}
	};

	public function new(gain = 1.22, curve = 0.8, chroma = 0.0) {
		super();
		amount = 0;
		this.chroma = chroma;
		TerrainStyle.setColor(earth, Palette.SKETCH_EARTH);
		this.gain = gain;
		this.curve = curve;
		TerrainStyle.setColor(paper, Palette.SKETCH_PAPER);
		TerrainStyle.setColor(graphite, Palette.SKETCH_GRAPHITE);
		grain = GroundTextures.get().dirt;
	}
}
