package ui;

import render.Palette;

/**
	The battle's 2D layer, kept minimal like the rest of the game:

	- a small health bar over a character once it's hurt (or when it's
	  selected), in its team colour;
	- the flag going up: a progress bar over the apex while a captain raises it;
	- the result: a banner when a side wins, with how.

	Positions are projected from the 3D scene every frame (device pixels, so
	sizes are scaled by `ui`).
**/
class BattleOverlay extends h2d.Object {
	public var ui = 1.0;

	final g:h2d.Graphics;
	final banner:h2d.Text;
	final sub:h2d.Text;

	public function new(?parent:h2d.Object) {
		super(parent);
		g = new h2d.Graphics(this);
		var font = hxd.res.DefaultFont.get();
		banner = new h2d.Text(font, this);
		banner.textAlign = Center;
		banner.dropShadow = {dx: 2, dy: 2, color: 0x10202A, alpha: 0.85};
		sub = new h2d.Text(font, this);
		sub.textAlign = Center;
		sub.dropShadow = {dx: 1, dy: 1, color: 0x10202A, alpha: 0.85};
		banner.visible = sub.visible = false;
	}

	public function update(sim:game.Sim, views:Array<render.UnitView>, cam:h3d.Camera, w:Float, h:Float) {
		g.clear();
		var bw = 26 * ui, bh = 3.5 * ui;
		for (v in views) {
			var u = v.unit;
			if (!u.alive || u.aboard >= 0) continue;
			if (u.hp >= u.maxHp && !v.selected) continue;
			var p = cam.project(v.x, v.y, v.z + 2.25, w, h);
			if (p.z < 0 || p.z > 1) continue;
			var f = Math.max(0, u.hp / u.maxHp);
			g.beginFill(Palette.INK, 0.75);
			g.drawRect(p.x - bw / 2 - ui, p.y - ui, bw + ui * 2, bh + ui * 2);
			g.endFill();
			g.beginFill(u.team == 0 ? 0x6E9CDB : 0xDB7B6A, 1);
			g.drawRect(p.x - bw / 2, p.y, bw * f, bh);
			g.endFill();
		}

		// The flag going up.
		for (u in sim.units)
			if (u.alive && u.kind == Captain && u.flagProgress > 0) {
				var p = cam.project(sim.island.apexX, sim.island.apexY, sim.island.apexH + 3.6, w, h);
				var fw = 70 * ui, fh = 6 * ui;
				var f = Math.min(1, u.flagProgress / game.Rules.FLAG_TIME);
				g.beginFill(Palette.INK, 0.8);
				g.drawRect(p.x - fw / 2 - ui * 1.5, p.y - ui * 1.5, fw + ui * 3, fh + ui * 3);
				g.endFill();
				g.beginFill(0xF2EEDF, 1);
				g.drawRect(p.x - fw / 2, p.y, fw * f, fh);
				g.endFill();
			}

		if (sim.winner >= 0) {
			banner.visible = sub.visible = true;
			banner.text = (sim.winner == 0 ? "BLUE" : "RED") + " WINS";
			banner.textColor = sim.winner == 0 ? 0x9CC2F0 : 0xF0A898;
			var how = switch sim.winReason {
				case "flag": "The flag is planted on the summit.";
				case "captain": "The enemy captain has fallen.";
				default: "The enemy crew is gone.";
			};
			sub.text = how + "   R: new island";
			banner.setScale(4 * ui);
			sub.setScale(1.6 * ui);
			banner.setPosition(w / 2, h * 0.32);
			sub.setPosition(w / 2, h * 0.32 + 52 * ui);
		} else
			banner.visible = sub.visible = false;
	}
}
