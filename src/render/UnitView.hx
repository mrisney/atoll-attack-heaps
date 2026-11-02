package render;

import game.Unit;
import game.Unit.UnitKind;

/**
	A unit drawn in a simple line-art style: rounded paper-white shapes with
	a bold ink outline, no faces or surface detail. Team is shown by a tinted
	tunic (and the captain's banner). Animation is deliberately restrained:
	a gentle arm/leg swing while walking, still when idle.

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

	var walkTime = 0.0;
	var swing = 0.0;
	var heading = 0.0;
	var lastX:Float;
	var lastY:Float;
	/** How much each arm swings (weapon arms move less). **/
	var armLSwing = 0.7;
	var armRSwing = 0.7;

	public var selected(default, set) = false;

	public function new(unit:Unit, ?parent:h3d.scene.Object) {
		super(parent);
		this.unit = unit;

		shadow();

		body = new h3d.scene.Object(this);
		body.setScale(SCALE);
		var paper = Palette.PAPER;
		var cloth = unit.team == 0 ? Palette.CLOTH_BLUE : Palette.CLOTH_RED;

		legL = limb(0, 0.075, 0.42, 0.062, 0.36, paper);
		legR = limb(0, -0.075, 0.42, 0.062, 0.36, paper);
		var torso = InkShape.capsule(body, 0.135, 0.5, 0.65, cloth);
		torso.scaleX = 0.85;
		var head = InkShape.sphere(body, 0.118, paper);
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
			m.material.blendMode = Alpha;
			m.material.color.set(1, 1, 1, 0.22);
			m.material.mainPass.depthWrite = false;
		}
	}

	function set_selected(v:Bool) {
		ring.visible = v;
		return selected = v;
	}

	function pose() {
		var s = Math.sin(walkTime) * swing;
		legL.setRotation(0, s, 0);
		legR.setRotation(0, -s, 0);
		armL.setRotation(ARM_SPREAD, -s * armLSwing, 0);
		armR.setRotation(-ARM_SPREAD, s * armRSwing, 0);
		body.z = Math.abs(Math.sin(walkTime)) * 0.03 * (swing / SWING);
	}

	public function syncFromSim(dt:Float) {
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
}
