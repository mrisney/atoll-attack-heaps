package render.ink;

/**
	Added to every opaque material. In the normal colour pass `geoColor` is
	unused and stripped by the shader compiler; in the geometry pass it is the
	only output: world normal (packed to 0..1) + linear view depth.
**/
class GeoOut extends hxsl.Shader {
	public static inline var DEPTH_RANGE = 600.0;

	static var SRC = {
		var transformedNormal:Vec3;
		var projectedPosition:Vec4;
		var geoColor:Vec4;

		function fragment() {
			geoColor = vec4(normalize(transformedNormal) * 0.5 + 0.5, projectedPosition.w / 600.0);
		}
	};
}
