package render;

/**
	Subtle foliage sway. Each vertex drifts by a few centimetres with a phase
	that depends on its position, so canopy edges ripple in the breeze
	instead of the whole tree swinging. That follows the WildCurrent art notes:
	"subtle shader sway only; never rotate the whole canopy". It runs in the
	shadow pass too, so shadows flutter with the leaves.
**/
class SwayShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
		};
		@param var amount:Float;
		@param var speed:Float;
		var transformedPosition:Vec3;

		function vertex() {
			var p = transformedPosition;
			var t = global.time * speed;
			p.x += sin(t * 1.3 + p.x * 0.8 + p.y * 0.6) * amount;
			p.y += cos(t * 1.1 + p.y * 0.9 - p.x * 0.4) * amount * 0.8;
			transformedPosition = p;
		}
	};

	public function new(amount = 0.05, speed = 1.0) {
		super();
		this.amount = amount;
		this.speed = speed;
	}
}
