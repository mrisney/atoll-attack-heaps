package render;

/**
	Pencil drawing look for the rigged characters (CharacterModel), after the
	owner's line-art archer reference: paper-white forms, a fine graphite
	outline, and light diagonal hatching on the sides turned away from the
	sun (a second, crossing layer only in the deepest shade).

	- `CharacterHatch` replaces lighting on the main pass: flat paper tone,
	  hatched by screen-space lines whose coverage follows N·L, so the
	  strokes stay a constant pencil width at any zoom.
	- `CharacterOutline` is an inverted hull drawn as a second pass of the
	  same (skinned) material: the posed surface pushed out along its normals,
	  back faces only, in graphite. It runs after the skinning shader, so
	  the outline follows the animation and the rag doll.
**/
class CharacterHatch extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var pixelSize:Vec2;
		};
		var transformedNormal:Vec3;
		var ndcPosition:Vec2;
		var pixelColor:Vec4;

		@param var sunDir:Vec3;
		@param var ink:Vec3;
		/** Stroke spacing in pixels. **/
		@param var spacing:Float;
		/** 0 = no hatching. **/
		@param var amount:Float;

		function fragment() {
			var n = normalize(transformedNormal);
			var ndl = dot(n, sunDir);
			// Paper: almost flat, a hint of form so the volume reads.
			var base = pixelColor.rgb * (0.86 + 0.16 * clamp(ndl, 0.0, 1.0));
			var px = ndcPosition / global.pixelSize;
			// Strokes at 45°, and the crossing set at -45° for deep shade.
			var a = fract((px.x + px.y) / spacing);
			var b = fract((px.x - px.y) / spacing);
			var shade = clamp(0.35 - ndl, 0.0, 1.0) * 1.6; // 0 in light, up to ~1 facing away
			var w1 = smoothstep(0.0, 0.35, shade) * 0.16; // line width as a fraction of the spacing
			var w2 = smoothstep(0.45, 0.9, shade) * 0.12;
			var l1 = 1.0 - smoothstep(w1 * 0.6, w1, abs(a - 0.5));
			var l2 = 1.0 - smoothstep(w2 * 0.6, w2, abs(b - 0.5));
			var line = max(l1 * step(0.001, w1), l2 * step(0.001, w2)) * amount;
			pixelColor.rgb = mix(base, ink, line * 0.55);
		}
	};

	public function new() {
		super();
		sunDir.set(TerrainStyle.SUN.x, TerrainStyle.SUN.y, TerrainStyle.SUN.z);
		sunDir.normalize();
		TerrainStyle.setColor(ink, Palette.INK);
		spacing = 4.5;
		amount = 1;
	}
}

class CharacterOutline extends hxsl.Shader {
	static var SRC = {
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;
		@global var camera:{
			var position:Vec3;
		};

		/** Outline thickness, metres at 10 m from the camera (it grows with distance, so it stays roughly constant on screen). **/
		@param var width:Float;
		@param var ink:Vec3;

		function vertex() {
			var d = length(camera.position - transformedPosition);
			transformedPosition += normalize(transformedNormal) * width * clamp(d / 10.0, 0.4, 6.0);
		}

		function fragment() {
			pixelColor = vec4(ink, 1.0);
		}
	};

	public function new() {
		super();
		width = 0.008;
		TerrainStyle.setColor(ink, Palette.INK);
	}
}
