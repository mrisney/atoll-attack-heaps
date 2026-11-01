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
		b.outline = 0.028; // ink edge, in model units (before the 1.6 scale)
		var team = unit.team == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		var teamDark = Palette.mix(team, 0x1A1A1A, 0.4);
		var s = unit.kind == Captain ? 1.1 : 1.0;

		// Grounded proportions: stocky, broad-shouldered, modest head.
		// Unit faces +X; its left side is +Y.
		b.prism(0, 0.085, 0, 0.065 * s, 0.36 * s, 6, Palette.LEATHER); // legs
		b.prism(0, -0.085, 0, 0.065 * s, 0.36 * s, 6, Palette.LEATHER);
		b.cone(0, 0, 0.3 * s, 0.25 * s, 0.32 * s, 8, teamDark, 0.2 * s); // tunic skirt
		b.cone(0, 0, 0.6 * s, 0.2 * s, 0.34 * s, 8, team, 0.25 * s); // torso, wider at the shoulders
		b.prism(0, 0, 0.58 * s, 0.215 * s, 0.05 * s, 8, Palette.LEATHER); // belt
		b.prism(0, 0.27 * s, 0.55 * s, 0.055 * s, 0.36 * s, 6, team); // arms
		b.prism(0, -0.27 * s, 0.55 * s, 0.055 * s, 0.36 * s, 6, team);
		b.cone(0, 0, 0.94 * s, 0.1 * s, 0.17 * s, 7, Palette.SKIN, 0.11 * s); // head
		b.cone(0, 0, 1.06 * s, 0.135 * s, 0.17 * s, 8, Palette.STEEL, 0.02 * s); // helmet
		b.prism(0.105 * s, 0, 0.98 * s, 0.015 * s, 0.1 * s, 4, Palette.STEEL); // nose guard

		switch unit.kind {
			case Captain:
				// Cloak + banner pole with the team standard.
				b.cone(-0.06, 0, 0.32, 0.27, 0.6, 8, teamDark, 0.24);
				b.prism(-0.2, 0, 0.2, 0.025, 1.65, 5, Palette.WOOD);
				var top = 1.82, bot = 1.38;
				var p0 = new h3d.Vector(-0.2, 0, top), p1 = new h3d.Vector(-0.2, 0.55, top - 0.06);
				var p2 = new h3d.Vector(-0.2, 0.5, bot), p3 = new h3d.Vector(-0.2, 0, bot + 0.04);
				b.quad(p0, p1, p2, p3, team);
				b.quad(p0, p3, p2, p1, team); // two-sided
			case Swordsman:
				// Round shield on the left arm (an upright disc), sword in the right hand.
				b.place(Math.PI / 2, 0, 0, 0.05, 0.36, 0.62);
				b.prism(0, 0, -0.03, 0.24, 0.06, 10, Palette.mix(team, Palette.WOOD, 0.35));
				b.prism(0, 0, 0.0, 0.07, 0.06, 6, Palette.STEEL); // boss
				b.unplace();
				b.place(0, 0.35, 0, 0.12, -0.3, 0.55);
				b.prism(0, 0, 0, 0.03, 0.6, 4, Palette.STEEL);
				b.prism(0, 0, -0.02, 0.08, 0.025, 4, Palette.LEATHER); // crossguard
				b.unplace();
			case Archer:
				// Hood instead of a helmet look, quiver on the back, longbow in hand.
				b.cone(-0.03, 0, 1.0, 0.15, 0.24, 8, teamDark, 0.03);
				b.place(0, -0.35, 0, -0.17, 0.08, 0.6);
				b.prism(0, 0, 0, 0.06, 0.42, 6, Palette.LEATHER);
				b.unplace();
				for (k in 0...7) {
					var a = (k - 3) / 3 * 0.9;
					b.place(0, -a * 0.9, 0, 0.2 + Math.cos(a) * 0.12, -0.3, 0.75 + Math.sin(a) * 0.42);
					b.prism(0, 0, -0.07, 0.022, 0.14, 4, Palette.WOOD);
					b.unplace();
				}
		}
		b.build(body);
		body.setScale(1.6);

		// Soft blob shadow grounds the figure on the terrain.
		var sb = new FlatMeshBuilder();
		sb.disc(0, 0, 0.05, 0.5, 16, 0x000000);
		for (m in sb.build(this, false)) {
			m.material.blendMode = Alpha;
			m.material.color.set(1, 1, 1, 0.28);
			m.material.mainPass.depthWrite = false;
		}

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
