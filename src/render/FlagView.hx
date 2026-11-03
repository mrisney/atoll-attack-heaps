package render;

/**
	The flag on the summit pole, animated from the sim's flag state:

	- nobody's: the pale neutral banner at the top, waiting to be claimed;
	- a captain raising his: the neutral banner is gone and his team's cloth
	  climbs the pole with his progress;
	- planted: the team's cloth flies at the top, rippling;
	- the enemy captain lowering it: it slides down the pole with his progress,
	  and the neutral banner returns once it's down.

	A separate object (not under IslandView), so the Sketch style's tone
	doesn't grey it: like the pole and docks, it keeps its colour.
**/
class FlagView extends h3d.scene.Object {
	final sim:game.Sim;
	final cloth:h3d.scene.Object;
	final mats:Array<h3d.mat.Material> = [];
	final bottom:Float;
	final top:Float;
	var time = 0.0;
	/** Shown height (0 bottom .. 1 top), eased toward the sim's. **/
	var shown = 1.0;

	public function new(sim:game.Sim, ?parent:h3d.scene.Object) {
		super(parent);
		this.sim = sim;
		var is = sim.island;
		setPosition(is.apexX, is.apexY, 0);
		// The pole (IslandView.buildFlagPole) runs from the cairn to about apexH + 2.95.
		bottom = is.apexH + 0.75;
		top = is.apexH + 2.9;
		cloth = new h3d.scene.Object(this);
		var b = new FlatMeshBuilder();
		// A swallowtail pennant along +X, two-sided, built in white and tinted per state.
		var cols = 4;
		for (c in 0...cols) {
			var x0 = c / cols * 1.15, x1 = (c + 1) / cols * 1.15;
			var h0 = 0.7 - c / cols * 0.25, h1 = 0.7 - (c + 1) / cols * 0.25;
			var p00 = new h3d.col.Point(x0, 0, 0), p01 = new h3d.col.Point(x0, 0, -h0);
			var p10 = new h3d.col.Point(x1, 0, 0), p11 = new h3d.col.Point(x1, 0, -h1);
			if (c == cols - 1) {
				// The swallowtail notch.
				var mid = new h3d.col.Point(x1 - 0.18, 0, -h1 / 2);
				b.twoSided(p00, p10, mid, 0xFFFFFF);
				b.twoSided(p00, mid, p01, 0xFFFFFF);
				b.twoSided(p01, mid, p11, 0xFFFFFF);
			} else {
				b.twoSided(p00, p10, p11, 0xFFFFFF);
				b.twoSided(p00, p11, p01, 0xFFFFFF);
			}
		}
		for (m in b.build(cloth, true, true, false)) {
			m.material.mainPass.culling = None;
			mats.push(m.material);
		}
		cloth.z = top;
	}

	function tint(c:Int) {
		for (m in mats) m.color.set(Palette.r(c), Palette.g(c), Palette.b(c), 1);
	}

	public function syncFromSim(dt:Float) {
		time += dt;
		var w = sim.flagWorker();
		var target = 1.0;
		var col = Palette.FLAG_NEUTRAL;
		if (w != null && sim.flagTeam < 0) {
			// Raising: his colour climbs from the bottom.
			target = Math.min(1, w.flagProgress / game.Rules.FLAG_TIME);
			col = w.team == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
			if (shown > 0.98 && target < 0.1) shown = 0; // the neutral banner swaps for his, at the foot
		} else if (w != null) {
			// Lowering the enemy's: it slides down.
			target = 1 - Math.min(1, w.flagProgress / game.Rules.FLAG_LOWER_TIME);
			col = sim.flagTeam == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		} else if (sim.flagTeam >= 0) {
			col = sim.flagTeam == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		} else if (shown < 0.98) {
			// Just lowered (or a raise abandoned): the neutral banner goes back up.
			shown = 1;
		}
		tint(col);
		shown += (target - shown) * Math.min(1, dt * 6);
		cloth.z = bottom + (top - bottom) * shown;
		// Ripple in the wind: a slow swing about the pole and a little flutter.
		var gust = 0.5 + 0.5 * Math.sin(time * 0.7);
		cloth.setRotation(Math.sin(time * 5.3) * 0.08, 0, 0.6 + Math.sin(time * 1.3) * (0.25 + 0.2 * gust));
		cloth.scaleX = 0.92 + 0.08 * Math.sin(time * 4.1);
	}
}
