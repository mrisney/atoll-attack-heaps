package render.ink;

import render.Palette;

/**
	Forward renderer + a screen-space ink pass.

	1. Geometry pass: opaque objects write normal + linear depth (GeoOut).
	2. The usual colour passes (opaque, then water/alpha, then additive).
	3. InkEdge reads the geometry buffer and blends ink lines on top.

	Water is transparent and isn't in the geometry buffer, so lines come from
	what's solid: units, trees, rocks and the terrain's silhouettes.
**/
class InkRenderer extends h3d.scene.fwd.Renderer {
	public var inkEnabled = true;
	/** Miniature-style blur toward the top and bottom of the screen. **/
	public var tiltShift = false;
	/** Colour grade + vignette (Painted), applied in the same final pass. **/
	public var grade = false;
	/** Weather in the final pass (see render.Weather): rain streaks, storm grade, fog. **/
	public var rain = 0.0;
	public var storm = 0.0;
	public var fog = 0.0;

	public function setWeather(w:render.Weather) {
		rain = w == Rain ? 1 : 0;
		storm = w == Rain ? 1 : 0;
		fog = w == Fog ? 1 : 0;
	}
	var tiltFx:h3d.pass.ScreenFx<TiltShift>;
	/** Sketch style: fade the far part of the frame and the margins to paper (0 = off). **/
	public var paperFade = 0.0;
	/** Ink line strength (the Sketch style draws lighter, finer lines). **/
	public var inkStrength = 0.85;
	/**
		FXAA on the offscreen frame. The browser's MSAA only applies to the
		screen, so when tilt-shift renders the scene to a texture first, thin
		things (grass blades) would alias without this.
	**/
	public var fxaa = true;
	final fxaaPass = new h3d.pass.FXAA();

	var geoPass:h3d.pass.Output;
	var inkFx:h3d.pass.ScreenFx<InkEdge>;

	public function new() {
		super();
		geoPass = new h3d.pass.Output("geo", [Value("geoColor")]);
		allPasses.push(geoPass);
		inkFx = new h3d.pass.ScreenFx(new InkEdge());
		inkFx.pass.setBlendMode(Alpha);
		tiltFx = new h3d.pass.ScreenFx(new TiltShift());

		// Soft sun shadows, tinted cool rather than black.
		shadow.size = 2048;
		setShadowTint(Palette.SHADOW);
		shadow.power = 60;
		shadow.bias = 0.004;
		shadow.blur.radius = 1.5;
	}

	public function setShadowTint(c:Int) {
		shadow.color.set(Palette.r(c), Palette.g(c), Palette.b(c));
	}

	override function render() {
		if (has("shadow"))
			renderPass(shadow, get("shadow"));

		var opaque = get("default");

		// With tilt-shift on, render the whole 3D frame off-screen, then blur it onto the screen.
		var frame:h3d.mat.Texture = null;
		if (tiltShift || grade || rain > 0 || storm > 0 || fog > 0) {
			frame = allocTarget("frame", true);
			ctx.engine.pushTarget(frame);
			var bg = ctx.engine.backgroundColor;
			ctx.engine.clear(bg == null ? 0xFF000000 : bg, 1);
		}

		if (inkEnabled) {
			var geo = allocTarget("inkGeo", true, 1., RGBA16F);
			ctx.engine.pushTarget(geo);
			// Background: normal pointing up, depth = "infinitely far".
			ctx.engine.clearF(new h3d.Vector4(0.5, 0.5, 1.0, 1.0), 1);
			renderPass(geoPass, opaque);
			ctx.engine.popTarget();
			inkFx.shader.geo = geo;
			inkFx.shader.texel.set(1 / geo.width, 1 / geo.height);
			inkFx.shader.fade = paperFade;
			inkFx.shader.strength = inkStrength;
		}

		renderPass(defaultPass, opaque);
		renderPass(defaultPass, get("alpha"), backToFront);
		renderPass(defaultPass, get("additive"));

		if (inkEnabled)
			inkFx.render();

		if (frame != null) {
			ctx.engine.popTarget();
			if (fxaa) {
				var aa = allocTarget("aa", false);
				ctx.engine.pushTarget(aa);
				fxaaPass.apply(frame);
				ctx.engine.popTarget();
				frame = aa;
			}
			tiltFx.shader.frame = frame;
			tiltFx.shader.texel.set(1 / frame.width, 1 / frame.height);
			tiltFx.shader.maxRadius = tiltShift ? 3.2 : 0;
			tiltFx.shader.grade = grade ? 1 : 0;
			tiltFx.shader.rain = rain;
			tiltFx.shader.storm = storm;
			tiltFx.shader.fog = fog;
			tiltFx.shader.time = ctx.time;
			tiltFx.shader.aspect = frame.width / frame.height;
			tiltFx.render();
		}
	}
}
