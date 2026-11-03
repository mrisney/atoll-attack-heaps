package render;

/**
	Shadows of passing clouds: big soft dark patches drifting across the
	ground, grass, trees and rocks with the wind (the Stronghold screenshots
	the owner pointed at have them, and they make the land read as large).

	Added to every island material except the water (IslandView). It reads
	the world position, so it costs two texture taps per pixel, and the
	noise is the ground textures' tileable alpha, so nothing new is baked.
	Purely visual; `strength` 0 turns it off (only Painted uses it).
**/
class CloudShadow extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
		};
		var transformedPosition:Vec3;
		var pixelColor:Vec4;

		@param var noise:Sampler2D;
		@param var noise2:Sampler2D;
		/** How dark a full cloud shadow is (0 = off). **/
		@param var strength:Float;
		/** Drift, metres per second. **/
		@param var drift:Vec2;
		/** Colour light takes in the shade (skylight is bluish). **/
		@param var shade:Vec3;

		function fragment() {
			if (strength > 0.0) {
				var p = transformedPosition.xy - drift * global.time;
				var n = noise.get(p / 150.0).a * 0.7 + noise2.get(p / 61.0 + vec2(0.3, 0.6)).a * 0.3;
				var cloud = smoothstep(0.45, 0.7, n) * strength;
				pixelColor.rgb *= mix(vec3(1.0), shade, cloud);
			}
		}
	};

	public function new() {
		super();
		var gt = GroundTextures.get();
		noise = gt.dirt;
		noise2 = gt.grass;
		strength = 0;
		drift.set(1.1, 0.8);
		TerrainStyle.setColor(shade, Palette.CLOUD_SHADE);
	}
}
