package render.ink;

import render.Palette;

/**
	Map-style linework painted directly on the terrain:

	- Contour lines every `interval` metres, a heavier "index" contour every
	  `majorEvery` lines (like a topo map).
	- A bold coastline at sea level.
	- Engraving-style diagonal hatching on steep slopes.

	All lines are anti-aliased with screen-space derivatives (fwidth), so they
	stay a consistent pixel width at any zoom.
**/
class TerrainInk extends hxsl.Shader {
	static var SRC = {
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;

		@param var ink:Vec3;
		@param var interval:Float;
		@param var majorEvery:Float;
		@param var minorWidth:Float;
		@param var majorWidth:Float;
		@param var coastWidth:Float;
		@param var minorAlpha:Float;
		@param var majorAlpha:Float;
		@param var hatchSpacing:Float;
		@param var hatchAlpha:Float;
		@param var coastLevel:Float;

		/** 1 on the line, 0 away from it; `w` is the line width in pixels. **/
		function isoLine(v:Float, w:Float):Float {
			var d = abs(fract(v - 0.5) - 0.5) / max(fwidth(v), 0.0001);
			return 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.5, d);
		}

		function fragment() {
			var h = transformedPosition.z;
			var land = smoothstep(0.15, 0.3, h);

			var minor = isoLine(h / interval, minorWidth) * minorAlpha;
			var major = isoLine(h / (interval * majorEvery), majorWidth) * majorAlpha;
			var contour = max(minor, major) * land;

			var coastD = abs(h - coastLevel) / max(fwidth(h), 0.0001);
			var coast = 1.0 - smoothstep(coastWidth * 0.5 - 0.5, coastWidth * 0.5 + 0.5, coastD);

			// Hatch strokes run across the slope; denser feel on steeper ground.
			var n = normalize(transformedNormal);
			var steep = smoothstep(0.25, 0.55, 1.0 - n.z) * smoothstep(0.8, 1.4, h);
			var hv = (transformedPosition.x - transformedPosition.y) / hatchSpacing;
			var hatch = isoLine(hv, 1.2) * steep * hatchAlpha;

			var a = max(max(contour, coast), hatch);
			pixelColor.rgb = mix(pixelColor.rgb, ink, a);
		}
	};

	public function new() {
		super();
		ink.set(Palette.r(Palette.INK), Palette.g(Palette.INK), Palette.b(Palette.INK));
		interval = 0.6;
		majorEvery = 5;
		minorWidth = 1.0;
		majorWidth = 1.8;
		coastWidth = 2.2;
		minorAlpha = 0.28;
		majorAlpha = 0.55;
		hatchSpacing = 0.35;
		hatchAlpha = 0.3;
		coastLevel = 0.1; // just above the water's swell, so it isn't hidden
	}
}
