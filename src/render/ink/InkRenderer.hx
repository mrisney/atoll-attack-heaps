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

	var geoPass:h3d.pass.Output;
	var inkFx:h3d.pass.ScreenFx<InkEdge>;

	public function new() {
		super();
		geoPass = new h3d.pass.Output("geo", [Value("geoColor")]);
		allPasses.push(geoPass);
		inkFx = new h3d.pass.ScreenFx(new InkEdge());
		inkFx.pass.setBlendMode(Alpha);

		// Soft sun shadows, tinted cool rather than black.
		shadow.size = 2048;
		shadow.color.set(Palette.r(Palette.SHADOW), Palette.g(Palette.SHADOW), Palette.b(Palette.SHADOW));
		shadow.power = 60;
		shadow.bias = 0.004;
		shadow.blur.radius = 1.5;
	}

	override function render() {
		if (has("shadow"))
			renderPass(shadow, get("shadow"));

		var opaque = get("default");

		if (inkEnabled) {
			var geo = allocTarget("inkGeo", true, 1., RGBA16F);
			ctx.engine.pushTarget(geo);
			// Background: normal pointing up, depth = "infinitely far".
			ctx.engine.clearF(new h3d.Vector4(0.5, 0.5, 1.0, 1.0), 1);
			renderPass(geoPass, opaque);
			ctx.engine.popTarget();
			inkFx.shader.geo = geo;
			inkFx.shader.texel.set(1 / geo.width, 1 / geo.height);
		}

		renderPass(defaultPass, opaque);
		renderPass(defaultPass, get("alpha"), backToFront);
		renderPass(defaultPass, get("additive"));

		if (inkEnabled)
			inkFx.render();
	}
}
