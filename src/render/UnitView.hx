package render;

import game.Unit;
import game.Unit.UnitKind;

/**
	A unit drawn in a simple line-art style: rounded paper-white shapes with
	a bold ink outline, no faces or surface detail. Team is shown by a tinted
	tunic (and the captain's banner). Animation is deliberately restrained:
	a gentle arm/leg swing while walking, still when idle.

	When the unit dies, the parts detach and follow a Verlet rag doll
	(see Ragdoll), then settle and lie still.

	The figure faces +X; its left side is +Y.
**/
class UnitView extends h3d.scene.Object {
	static inline var SCALE = 1.6;
	static inline var SWING = 0.34; // max limb swing (radians) while walking
	static inline var ARM_SPREAD = 0.1; // arms rest slightly away from the body

	public final unit:Unit;

	var body:h3d.scene.Object;
	var legL:h3d.scene.Object;
	var legR:h3d.scene.Object;
	var armL:h3d.scene.Object;
	var armR:h3d.scene.Object;
	var ring:h3d.scene.Object;
	var torso:h3d.scene.Object;
	var head:h3d.scene.Object;
	var shadowMeshes:Array<h3d.scene.Mesh> = [];
	var ragdoll:Null<Ragdoll> = null;
	/** World (x, y) → ground height, for the rag doll. **/
	final groundAt:(Float, Float) -> Float;

	var walkTime = 0.0;
	var swing = 0.0;
	var heading = 0.0;
	var lastX:Float;
	var lastY:Float;
	/** How much each arm swings (weapon arms move less). **/
	var armLSwing = 0.7;
	var armRSwing = 0.7;

	public var selected(default, set) = false;

	/**
		Draw units as the rigged, animated FBX character (CharacterModel)
		instead of the line-art shapes. `?figures=rigged`; off by default while
		the character is the generated stand-in.
	**/
	public static var rigged = false;

	var model:Null<CharacterModel> = null;

	public function new(unit:Unit, groundAt:(Float, Float) -> Float, ?parent:h3d.scene.Object) {
		super(parent);
		this.unit = unit;
		this.groundAt = groundAt;

		shadow();

		body = new h3d.scene.Object(this);
		if (rigged) {
			model = new CharacterModel(unit.team, unit.kind, body);
			finish();
			return;
		}
		body.setScale(SCALE);
		var paper = Palette.PAPER;
		var cloth = unit.team == 0 ? Palette.CLOTH_BLUE : Palette.CLOTH_RED;

		legL = limb(0, 0.075, 0.42, 0.062, 0.36, paper);
		legR = limb(0, -0.075, 0.42, 0.062, 0.36, paper);
		torso = InkShape.capsule(body, 0.135, 0.5, 0.65, cloth);
		torso.scaleX = 0.85;
		head = InkShape.sphere(body, 0.118, paper);
		head.z = 0.93;
		armL = limb(0, 0.178, 0.74, 0.046, 0.3, paper);
		armR = limb(0, -0.178, 0.74, 0.046, 0.3, paper);

		var team = unit.team == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		switch unit.kind {
			case Captain:
				// A tall pole with a small rounded pennant.
				var pole = InkShape.rod(armR, 0.06, 0, -0.55, 0.06, 0, 1.15, 0.018, paper);
				var pennant = InkShape.capsule(armR, 0.11, 0.0, 0.1, team);
				pennant.setPosition(0.06, -0.13, 0.98);
				pennant.scaleY = 1.25;
				pennant.scaleX = 0.16;
				armRSwing = 0.15;
				pole.visible = true;
			case Swordsman:
				// Short blade held low and forward, round shield on the left arm.
				InkShape.rod(armR, 0.02, 0, -0.29, 0.26, 0, -0.52, 0.02, paper);
				var shield = InkShape.sphere(armL, 0.17, cloth);
				shield.setPosition(0.02, 0.07, -0.17);
				shield.scaleY = 0.22;
				armLSwing = 0.2;
			case Piker:
				// A long pike held upright.
				InkShape.rod(armR, 0.04, 0, -0.5, 0.04, 0, 1.55, 0.016, paper);
				armRSwing = 0.15;
			case Archer:
				// A simple bow arc in the left hand.
				var n = 7;
				var prev:Null<{x:Float, z:Float}> = null;
				for (k in 0...n + 1) {
					var a = (k / n * 2 - 1) * 0.95;
					var p = {x: 0.02 + Math.cos(a) * 0.2 - 0.12, z: -0.27 + Math.sin(a) * 0.34};
					if (prev != null) InkShape.rod(armL, prev.x, 0.04, prev.z, p.x, 0.04, p.z, 0.016, paper, 0.016);
					prev = p;
				}
				armLSwing = 0.15;
		}

		finish();
	}

	function finish() {
		ring = new h3d.scene.Object(this);
		var rb = new FlatMeshBuilder();
		rb.ring(0, 0, 0.06, 0.62, 0.76, 28, Palette.SELECT);
		rb.build(ring, false);
		ring.visible = false;

		lastX = unit.x;
		lastY = unit.y;
		setPosition(unit.x, unit.y, unit.z);
		pose();
	}

	/** A limb hanging from a pivot (hip or shoulder); rotate the pivot to swing it. **/
	function limb(x:Float, y:Float, z:Float, r:Float, len:Float, fill:Int):h3d.scene.Object {
		var pivot = new h3d.scene.Object(body);
		pivot.setPosition(x, y, z);
		InkShape.capsule(pivot, r, -len, 0, fill);
		return pivot;
	}

	function shadow() {
		var sb = new FlatMeshBuilder();
		sb.disc(0, 0, 0.05, 0.48, 20, 0x000000);
		for (m in sb.build(this, false)) {
			shadowMeshes.push(m);
			m.material.blendMode = Alpha;
			m.material.color.set(1, 1, 1, 0.12); // faint contact shadow; the sun shadow does the rest
			m.material.mainPass.depthWrite = false;
		}
	}

	function set_selected(v:Bool) {
		ring.visible = v;
		return selected = v;
	}

	function pose() {
		if (model != null) {
			// Walk while moving (playback matched to the stride), else idle.
			if (swing > SWING * 0.3) {
				model.play("Walk");
				model.setSpeed(unit.baseSpeed / 3.0 * (swing / SWING));
			} else
				model.play("Idle");
			return;
		}
		var s = Math.sin(walkTime) * swing;
		legL.setRotation(0, s, 0);
		legR.setRotation(0, -s, 0);
		armL.setRotation(ARM_SPREAD, -s * armLSwing, 0);
		armR.setRotation(-ARM_SPREAD, s * armRSwing, 0);
		body.z = Math.abs(Math.sin(walkTime)) * 0.03 * (swing / SWING);
	}

	public var isDown(get, never):Bool;

	inline function get_isDown()
		return ragdoll != null;

	public function syncFromSim(dt:Float) {
		if (!unit.alive) {
			if (ragdoll == null) startRagdoll();
			ragdoll.update(dt);
			applyRagdoll();
			return;
		}

		// Ease toward the sim position (the sim ticks at 30 Hz).
		var k = Math.min(1, dt * 15);
		var nx = x + (unit.x - x) * k;
		var ny = y + (unit.y - y) * k;
		var nz = z + (unit.z - z) * k;
		var moved = Math.abs(unit.x - lastX) + Math.abs(unit.y - lastY) > 0.001;
		lastX = unit.x;
		lastY = unit.y;
		setPosition(nx, ny, nz);

		// Ease the stride in and out rather than snapping.
		var target = moved ? SWING : 0.0;
		swing += (target - swing) * Math.min(1, dt * 8);
		walkTime += dt * 8.5 * (swing / SWING);
		if (swing < 0.01) walkTime = 0;
		pose();

		var diff = unit.facing - heading;
		while (diff > Math.PI) diff -= Math.PI * 2;
		while (diff < -Math.PI) diff += Math.PI * 2;
		heading += diff * Math.min(1, dt * 10);
		body.setRotation(0, 0, heading);
	}

	// --- rag doll ----------------------------------------------------------

	function startRagdoll() {
		selected = false;
		for (m in shadowMeshes) m.visible = false;
		// Ground in this view's local space (its origin stays where the unit fell).
		var ox = x, oy = y, oz = z;
		var ground = (lx:Float, ly:Float) -> Math.max(groundAt(ox + lx, oy + ly), -0.25) - oz;
		// The rigged figure is taller than the line-art one (pelvis ~0.93 m vs 0.45 × SCALE).
		ragdoll = new Ragdoll(heading, model != null ? 1.95 : SCALE, body.z, ground);

		// Fling away from the hit, with a little per-unit variety so a group doesn't fall in lockstep.
		var v = ((unit.id * 7919 + 13) % 101) / 100;
		var dx = unit.x - unit.hitFromX, dy = unit.y - unit.hitFromY;
		var d = Math.sqrt(dx * dx + dy * dy);
		var falloff = Math.max(0.35, 1 - d / 6);
		ragdoll.kick(dx + (v - 0.5) * 0.6 * d, dy, 3.2 * falloff + v * 0.8, 2.2 * falloff + v * 0.6);

		if (model != null) {
			// The rag doll's particles already include the heading.
			body.setRotation(0, 0, 0);
			model.startRagdoll();
			applyRagdoll();
			return;
		}
		// Detach the parts from the walking skeleton; from now on they follow the joints.
		for (o in [torso, head, legL, legR, armL, armR]) {
			o.remove();
			addChild(o);
			o.setScale(SCALE);
		}
		torso.scaleX = SCALE * 0.85;
		body.visible = false;
		applyRagdoll();
	}

	function applyRagdoll() {
		var r = ragdoll;
		if (model != null) {
			model.applyRagdoll(r, x, y, z);
			return;
		}
		inline function px(i:Int) return new h3d.Vector(r.x[i], r.y[i], r.z[i]);

		// Torso frame: up along the spine, left across the shoulders.
		var pelvis = px(Ragdoll.PELVIS), chest = px(Ragdoll.CHEST);
		var up = chest.sub(pelvis).normalized();
		var left = orthoLeft(px(Ragdoll.SH_L).sub(px(Ragdoll.SH_R)), up);
		placeFrame(torso, pelvis.sub(up.scaled(0.45 * SCALE)), left, up);

		var headUp = px(Ragdoll.HEAD).sub(chest).normalized();
		placeFrame(head, px(Ragdoll.HEAD), orthoLeft(left, headUp), headUp);

		// Limbs: the pivot sits at the joint and the capsule hangs along local -Z.
		placeLimb(legL, px(Ragdoll.HIP_L), px(Ragdoll.FOOT_L), left);
		placeLimb(legR, px(Ragdoll.HIP_R), px(Ragdoll.FOOT_R), left);
		placeLimb(armL, px(Ragdoll.SH_L), px(Ragdoll.HAND_L), left);
		placeLimb(armR, px(Ragdoll.SH_R), px(Ragdoll.HAND_R), left);
	}

	function placeLimb(o:h3d.scene.Object, joint:h3d.Vector, end:h3d.Vector, left:h3d.Vector) {
		var axis = joint.sub(end).normalized(); // local +Z points from the end back to the joint
		placeFrame(o, joint, orthoLeft(left, axis), axis);
	}

	/** `left` with its component along `up` removed. **/
	static function orthoLeft(left:h3d.Vector, up:h3d.Vector):h3d.Vector {
		var l = left.sub(up.scaled(left.dot(up)));
		if (l.lengthSq() < 1e-8) l = new h3d.Vector(-up.y, up.x, 0);
		return l.normalized();
	}

	/** Place an object with local X = forward, Y = left, Z = up. **/
	static function placeFrame(o:h3d.scene.Object, pos:h3d.Vector, left:h3d.Vector, up:h3d.Vector) {
		var fwd = left.cross(up);
		var m = new h3d.Matrix();
		m.identity();
		m._11 = fwd.x;
		m._12 = fwd.y;
		m._13 = fwd.z;
		m._21 = left.x;
		m._22 = left.y;
		m._23 = left.z;
		m._31 = up.x;
		m._32 = up.y;
		m._33 = up.z;
		var q = new h3d.Quat();
		q.initRotateMatrix(m);
		o.setRotationQuat(q);
		o.setPosition(pos.x, pos.y, pos.z);
	}
}
