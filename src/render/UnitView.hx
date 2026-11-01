package render;

import game.Unit;
import game.Unit.UnitKind;

/**
	Low-poly figure for one unit, plus its selection ring. Built at the
	origin and moved as a whole.
**/
class UnitView extends h3d.scene.Object {
	public final unit:Unit;

	var body:h3d.scene.Object;
	var ring:h3d.scene.Object;
	var walkTime = 0.0;
	var heading = 0.0;
	var lastX:Float;
	var lastY:Float;

	public var selected(default, set) = false;

	public function new(unit:Unit, ?parent:h3d.scene.Object) {
		super(parent);
		this.unit = unit;

		body = new h3d.scene.Object(this);
		var b = new FlatMeshBuilder();
		var team = unit.team == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		var s = unit.kind == Captain ? 1.15 : 1.0;

		// Legs/tunic, torso, head, helmet.
		b.cone(0, 0, 0, 0.26 * s, 0.45 * s, 8, Palette.mix(team, 0x222222, 0.35), 0.2 * s);
		b.cone(0, 0, 0.45 * s, 0.22 * s, 0.4 * s, 8, team, 0.17 * s);
		b.cone(0, 0, 0.85 * s, 0.13 * s, 0.22 * s, 8, Palette.SKIN, 0.13 * s);
		b.cone(0, 0, 1.03 * s, 0.16 * s, 0.18 * s, 8, Palette.STEEL, 0);

		switch unit.kind {
			case Captain:
				// Banner pole on the back.
				b.prism(-0.18, 0, 0.3, 0.03, 1.5, 4, Palette.WOOD);
				b.quad(new h3d.Vector(-0.18, 0, 1.75), new h3d.Vector(-0.18, 0.55, 1.68), new h3d.Vector(-0.18, 0.55, 1.35),
					new h3d.Vector(-0.18, 0, 1.4), team);
			case Swordsman:
				// Shield on the left arm, sword on the right.
				b.prism(0, 0.27, 0.45, 0.2, 0.06, 8, Palette.mix(team, 0xFFFFFF, 0.25));
				b.prism(0.08, -0.26, 0.55, 0.035, 0.55, 4, Palette.STEEL);
			case Archer:
				// Bow as a thin arc of prisms.
				for (k in 0...5) {
					var a = (k - 2) * 0.35;
					b.prism(0.22 + Math.cos(a) * 0.08, -0.22, 0.5 + k * 0.12, 0.025, 0.13, 4, Palette.WOOD);
				}
		}
		b.build(body);
		body.setScale(1.6);

		ring = new h3d.scene.Object(this);
		var rb = new FlatMeshBuilder();
		rb.ring(0, 0, 0.06, 0.62 * s, 0.78 * s, 24, Palette.SELECT);
		rb.build(ring, false);
		ring.visible = false;

		lastX = unit.x;
		lastY = unit.y;
		setPosition(unit.x, unit.y, unit.z);
	}

	function set_selected(v:Bool) {
		ring.visible = v;
		return selected = v;
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
		if (moved) walkTime += dt * 12 else walkTime = 0;
		setPosition(nx, ny, nz);
		body.z = moved ? Math.abs(Math.sin(walkTime)) * 0.08 : 0;
		// Smoothly turn toward facing.
		var diff = unit.facing - heading;
		while (diff > Math.PI) diff -= Math.PI * 2;
		while (diff < -Math.PI) diff += Math.PI * 2;
		heading += diff * Math.min(1, dt * 10);
		body.setRotation(0, 0, heading);
	}
}
