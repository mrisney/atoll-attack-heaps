package ui;

import render.Palette;

/**
	The battle's 2D layer, kept minimal like the rest of the game:

	- a small health bar over a character once it's hurt (or when it's
	  selected), in its team colour, and a wider one over a holed ship;
	- the flag going up: a progress bar over the apex while a captain raises it;
	- the result: a banner when a side wins, with how.

	Positions are projected from the 3D scene every frame (device pixels, so
	sizes are scaled by `ui`).
**/
class BattleOverlay extends h2d.Object {
	public var ui = 1.0;
	/** The ship the player has selected (its gun ranges are drawn), or null. **/
	public var selectedShip:Null<game.Ship> = null;

	final g:h2d.Graphics;
	final banner:h2d.Text;
	final sub:h2d.Text;
	final flagLabel:h2d.Text;
	final countdown:h2d.Text;
	final topLine:h2d.Text;

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
		flagLabel = text(font);
		countdown = text(font);
		topLine = text(font);
	}

	function text(font:h2d.Font):h2d.Text {
		var t = new h2d.Text(font, this);
		t.textAlign = Center;
		t.dropShadow = {dx: 1, dy: 1, color: 0x10202A, alpha: 0.85};
		t.visible = false;
		return t;
	}

	static inline function teamLight(team:Int):Int
		return team == 0 ? 0x9CC2F0 : 0xF0A898;

	/** An arc as a polyline (h2d.Graphics' current line style). **/
	function arc(cx:Float, cy:Float, r:Float, start:Float, len:Float) {
		var n = Std.int(Math.max(2, Math.abs(len) / (Math.PI * 2) * 48));
		for (k in 0...n + 1) {
			var a = start + len * k / n;
			var x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r;
			if (k == 0) g.moveTo(x, y) else g.lineTo(x, y);
		}
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

		// A selected ship: the reach of its guns (its own choice inside, yours out to
		// the outer ring), and a cross-hair on the character you told it to fire on.
		if (selectedShip != null && !selectedShip.sunk) {
			var dd = game.Directives.current;
			for (ring in [dd.cannonRange, dd.cannonOrderedRange]) {
				g.lineStyle(1.6 * ui, 0xF2E6B0, ring == dd.cannonRange ? 0.55 : 0.3);
				var first = true;
				for (k in 0...73) {
					var a = k / 72 * Math.PI * 2;
					var wx = selectedShip.x + Math.cos(a) * ring, wy = selectedShip.y + Math.sin(a) * ring;
					var p = cam.project(wx, wy, Math.max(sim.island.heightAt(wx, wy), 0) + 0.3, w, h);
					if (p.z < 0 || p.z > 1) {
						first = true;
						continue;
					}
					if (first) g.moveTo(p.x, p.y) else g.lineTo(p.x, p.y);
					first = false;
				}
			}
			g.lineStyle();
		}
		for (s in sim.ships) {
			if (s.sunk || s.fireTarget < 0) continue;
			var t = sim.getUnit(s.fireTarget);
			if (t == null || !t.alive) continue;
			var p = cam.project(t.x, t.y, sim.island.heightAt(t.x, t.y) + 0.9, w, h);
			if (p.z < 0 || p.z > 1) continue;
			var r = 11 * ui;
			g.lineStyle(2 * ui, s.team == 0 ? 0x9CC2F0 : 0xF0A898, 0.95);
			arc(p.x, p.y, r, 0, Math.PI * 2);
			for (k in 0...4) {
				var a = k * Math.PI / 2;
				g.moveTo(p.x + Math.cos(a) * r * 0.6, p.y + Math.sin(a) * r * 0.6);
				g.lineTo(p.x + Math.cos(a) * r * 1.5, p.y + Math.sin(a) * r * 1.5);
			}
			g.lineStyle();
		}

		// Ships: a wider bar over the mast once a ship is holed.
		var sw = 54 * ui, sh = 5 * ui;
		for (s in sim.ships) {
			if (s.sunk || s.hp >= s.maxHp) continue;
			var p = cam.project(s.x, s.y, 7.2, w, h);
			if (p.z < 0 || p.z > 1) continue;
			var f = Math.max(0, s.hp / s.maxHp);
			g.beginFill(Palette.INK, 0.75);
			g.drawRect(p.x - sw / 2 - ui, p.y - ui, sw + ui * 2, sh + ui * 2);
			g.endFill();
			g.beginFill(s.team == 0 ? 0x6E9CDB : 0xDB7B6A, 1);
			g.drawRect(p.x - sw / 2, p.y, sw * f, sh);
			g.endFill();
		}

		// The flag: raising or lowering (a bar with what's happening), and once it's
		// planted, a countdown ring over the summit plus a line at the top of the screen.
		var is = sim.island;
		var ap = cam.project(is.apexX, is.apexY, is.apexH + 4.0, w, h);
		var onScreen = ap.z > 0 && ap.z < 1;
		var worker = sim.flagWorker();
		flagLabel.visible = false;
		if (worker != null && onScreen) {
			var raising = sim.flagTeam < 0;
			var need = raising ? game.Rules.FLAG_TIME : game.Rules.FLAG_LOWER_TIME;
			var f = Math.min(1, worker.flagProgress / need);
			var fw = 80 * ui, fh = 6 * ui;
			var y = ap.y - 30 * ui;
			g.beginFill(Palette.INK, 0.8);
			g.drawRect(ap.x - fw / 2 - ui * 1.5, y - ui * 1.5, fw + ui * 3, fh + ui * 3);
			g.endFill();
			g.beginFill(teamLight(worker.team), 1);
			g.drawRect(ap.x - fw / 2, y, fw * (raising ? f : 1 - f), fh);
			g.endFill();
			flagLabel.visible = true;
			flagLabel.text = (worker.team == 0 ? "BLUE" : "RED") + (raising ? " RAISING THE FLAG" : " LOWERING THE FLAG");
			flagLabel.textColor = teamLight(worker.team);
			flagLabel.setScale(1.3 * ui);
			flagLabel.setPosition(ap.x, y - 18 * ui);
		}
		countdown.visible = false;
		topLine.visible = false;
		if (sim.flagTeam >= 0 && sim.winner < 0) {
			var left = Math.max(0, game.Rules.FLAG_HOLD_TIME - sim.flagHeld);
			var col = teamLight(sim.flagTeam);
			var secs = Std.int(Math.ceil(left));
			var clock = Std.int(secs / 60) + ":" + StringTools.lpad(Std.string(secs % 60), "0", 2);
			if (onScreen) {
				// A ring that empties as the clock runs down, the seconds inside.
				var r = 20 * ui, cx = ap.x, cy = ap.y - (worker != null ? 70 : 20) * ui;
				g.lineStyle(7 * ui, Palette.INK, 0.6);
				arc(cx, cy, r, 0, Math.PI * 2);
				g.lineStyle(4.5 * ui, col, 1);
				var frac = left / game.Rules.FLAG_HOLD_TIME;
				arc(cx, cy, r, -Math.PI / 2, Math.PI * 2 * frac);
				g.lineStyle();
				countdown.visible = true;
				countdown.text = Std.string(secs);
				countdown.textColor = col;
				countdown.setScale(1.6 * ui);
				countdown.setPosition(cx, cy - 8 * ui);
			}
			topLine.visible = true;
			topLine.text = (sim.flagTeam == 0 ? "BLUE" : "RED") + " FLAG FLIES  " + clock;
			topLine.textColor = col;
			topLine.setScale(2.2 * ui);
			topLine.setPosition(w / 2, 14 * ui);
		}

		if (sim.winner >= 0) {
			banner.visible = sub.visible = true;
			banner.text = (sim.winner == 0 ? "BLUE" : "RED") + " WINS";
			banner.textColor = sim.winner == 0 ? 0x9CC2F0 : 0xF0A898;
			var how = switch sim.winReason {
				case "flag": "Their flag held the summit for " + Std.int(game.Rules.FLAG_HOLD_TIME) + " seconds.";
				case "captain": "The enemy captain has fallen.";
				case "sunk": "Their ship went down with the captain aboard.";
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
