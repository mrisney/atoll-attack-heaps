package render;

/**
	A small Verlet rag doll for the line-art figures. It's purely cosmetic
	(render side only), so it doesn't need to be deterministic or networked:
	the sim just says "this unit died, hit from there".

	Eleven particles (feet, hips, pelvis, chest, head, shoulders, hands) held
	together by distance constraints. Each figure part is a rigid capsule, so
	there are no knees or elbows, which keeps the flop restrained. Particles
	collide with the terrain (and float at the water surface), with friction,
	and the body goes to sleep once it settles.

	Coordinates are local to the UnitView (its origin is where the unit died).
**/
class Ragdoll {
	public static inline var FOOT_L = 0;
	public static inline var FOOT_R = 1;
	public static inline var HIP_L = 2;
	public static inline var HIP_R = 3;
	public static inline var PELVIS = 4;
	public static inline var CHEST = 5;
	public static inline var HEAD = 6;
	public static inline var SH_L = 7;
	public static inline var SH_R = 8;
	public static inline var HAND_L = 9;
	public static inline var HAND_R = 10;
	static inline var COUNT = 11;

	static inline var STEP = 1 / 60;
	static inline var GRAVITY = 9.8;
	static inline var ITERATIONS = 10;
	static inline var AIR_DAMPING = 0.993;
	static inline var GROUND_FRICTION = 0.55;

	/** Joint positions in the figure's own (unscaled) space, facing +X. **/
	public static final REST:Array<Array<Float>> = [
		[0, 0.075, 0.0], [0, -0.075, 0.0], // feet
		[0, 0.075, 0.42], [0, -0.075, 0.42], // hips
		[0, 0, 0.45], [0, 0, 0.74], [0, 0, 0.93], // pelvis, chest, head
		[0, 0.178, 0.74], [0, -0.178, 0.74], // shoulders
		[0, 0.178, 0.44], [0, -0.178, 0.44], // hands
	];

	static final RADIUS = [0.1, 0.1, 0.1, 0.1, 0.2, 0.2, 0.19, 0.1, 0.1, 0.07, 0.07];

	/** Bone pairs plus a few braces that keep the torso and hips rigid. **/
	static final LINKS:Array<Array<Int>> = [
		[FOOT_L, HIP_L], [FOOT_R, HIP_R], [SH_L, HAND_L], [SH_R, HAND_R], // limbs
		[HIP_L, HIP_R], [HIP_L, PELVIS], [HIP_R, PELVIS], // hips
		[PELVIS, CHEST], [CHEST, HEAD], [CHEST, SH_L], [CHEST, SH_R], [SH_L, SH_R], // torso
		[PELVIS, SH_L], [PELVIS, SH_R], [HIP_L, CHEST], [HIP_R, CHEST], // braces
		[HEAD, SH_L], [HEAD, SH_R], // stiff neck
	];

	public final x:Array<Float> = [];
	public final y:Array<Float> = [];
	public final z:Array<Float> = [];
	final ox:Array<Float> = [];
	final oy:Array<Float> = [];
	final oz:Array<Float> = [];
	final rest:Array<Float> = [];
	final radius:Array<Float> = [];
	final ground:(Float, Float) -> Float;

	public var sleeping(default, null) = false;

	var accumulator = 0.0;
	var age = 0.0;
	var stillSteps = 0;

	/**
		@param heading the figure's facing when it died
		@param scale   the figure's scale (UnitView.SCALE)
		@param lift    current vertical offset of the body (walk bob)
		@param ground  local (x, y) → local ground height
	**/
	public function new(heading:Float, scale:Float, lift:Float, ground:(Float, Float) -> Float) {
		this.ground = ground;
		var c = Math.cos(heading), s = Math.sin(heading);
		for (i in 0...COUNT) {
			var p = REST[i];
			var px = (p[0] * c - p[1] * s) * scale;
			var py = (p[0] * s + p[1] * c) * scale;
			var pz = p[2] * scale + lift;
			x.push(px);
			y.push(py);
			z.push(pz);
			ox.push(px);
			oy.push(py);
			oz.push(pz);
			radius.push(RADIUS[i] * scale * 0.6);
		}
		for (l in LINKS) rest.push(dist(l[0], l[1]));
	}

	/**
		Fling the body: (dx, dy) is the push direction, `speed` in units/second.
		The upper body gets more of it than the feet, so it topples rather than slides.
	**/
	public function kick(dx:Float, dy:Float, speed:Float, up:Float) {
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-6) {
			dx = 1;
			dy = 0;
			len = 1;
		}
		dx /= len;
		dy /= len;
		var weight = [0.25, 0.25, 0.55, 0.55, 0.75, 1.1, 1.2, 1.0, 1.0, 1.15, 1.15];
		for (i in 0...COUNT) {
			var w = weight[i];
			ox[i] = x[i] - dx * speed * w * STEP;
			oy[i] = y[i] - dy * speed * w * STEP;
			oz[i] = z[i] - up * w * STEP;
		}
	}

	public function update(dt:Float) {
		if (sleeping) return;
		accumulator += Math.min(dt, 0.1);
		while (accumulator >= STEP && !sleeping) {
			step();
			accumulator -= STEP;
		}
	}

	function step() {
		var g = GRAVITY * STEP * STEP;
		var moved = 0.0;
		for (i in 0...COUNT) {
			var vx = (x[i] - ox[i]) * AIR_DAMPING;
			var vy = (y[i] - oy[i]) * AIR_DAMPING;
			var vz = (z[i] - oz[i]) * AIR_DAMPING;
			ox[i] = x[i];
			oy[i] = y[i];
			oz[i] = z[i];
			x[i] += vx;
			y[i] += vy;
			z[i] += vz - g;
		}

		for (_ in 0...ITERATIONS) {
			for (k in 0...LINKS.length) {
				var a = LINKS[k][0], b = LINKS[k][1];
				var dx = x[b] - x[a], dy = y[b] - y[a], dz = z[b] - z[a];
				var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
				if (d < 1e-6) continue;
				var diff = (d - rest[k]) / d * 0.5;
				x[a] += dx * diff;
				y[a] += dy * diff;
				z[a] += dz * diff;
				x[b] -= dx * diff;
				y[b] -= dy * diff;
				z[b] -= dz * diff;
			}
			for (i in 0...COUNT) {
				var floor = ground(x[i], y[i]) + radius[i];
				if (z[i] < floor) z[i] = floor;
			}
		}

		// Friction for anything touching the ground.
		for (i in 0...COUNT) {
			var floor = ground(x[i], y[i]) + radius[i];
			if (z[i] <= floor + 0.01) {
				ox[i] = x[i] - (x[i] - ox[i]) * GROUND_FRICTION;
				oy[i] = y[i] - (y[i] - oy[i]) * GROUND_FRICTION;
			}
			var m = Math.abs(x[i] - ox[i]) + Math.abs(y[i] - oy[i]) + Math.abs(z[i] - oz[i]);
			if (m > moved) moved = m;
		}

		age += STEP;
		stillSteps = moved < 0.0015 ? stillSteps + 1 : 0;
		if ((age > 0.6 && stillSteps > 20) || age > 6) sleeping = true;
	}

	inline function dist(a:Int, b:Int):Float {
		var dx = x[b] - x[a], dy = y[b] - y[a], dz = z[b] - z[a];
		return Math.sqrt(dx * dx + dy * dy + dz * dz);
	}
}
