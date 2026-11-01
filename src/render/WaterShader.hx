package render;

/**
	Gentle swell + shimmer for the water surface. Depth coloring comes from
	vertex colors (baked from the heightfield); this shader only animates.
**/
class WaterShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
			@perObject var modelView:Mat4;
		};

		@param var amplitude:Float;
		@param var shimmer:Float;

		var relativePosition:Vec3;
		var transformedPosition:Vec3;
		var pixelColor:Vec4;

		function vertex() {
			var p = relativePosition * global.modelView.mat3x4();
			var t = global.time;
			p.z += (sin(p.x * 0.35 + t * 1.1) + cos(p.y * 0.28 + t * 0.9)) * amplitude;
			transformedPosition = p;
		}

		function fragment() {
			var t = global.time;
			var s = sin(transformedPosition.x * 0.9 + t * 1.7) * sin(transformedPosition.y * 0.8 - t * 1.3);
			pixelColor.rgb += vec3(shimmer * s);
		}
	};

	public function new(amplitude = 0.05, shimmer = 0.035) {
		super();
		this.amplitude = amplitude;
		this.shimmer = shimmer;
	}
}
