package ui;

import game.Unit;
import render.Palette;

/**
	The only standing HUD, kept sparse (owner: "introduce it sparingly...
	this game stresses minimalism"; he pointed at Defilade's unit card and
	asked for much less):

	- **Card**: hover over a character (either side) or select one, and a
	  small card fades in: what it is (with a glyph: sword, pike, bow, the
	  captain's flag), whose, what it's doing, and its health. Ships get one
	  too: hull, who's aboard, the guns.
	- **Group panel**: select several and it shows the band instead: how many
	  of each kind, each one a pip that empties as it's hurt, and the group's
	  health overall. A hovered character's card sits above it.

	Both fade in quickly and out slowly, and sit bottom-left beside the
	minimap. Sizes are in UI points; `ui` scales to device pixels.
**/
class UnitCard extends h2d.Object {
	public var ui = 1.0;

	static inline var CARD_W = 236.0;
	static inline var CARD_H = 66.0;
	static inline var PAD = 10.0;

	final card:h2d.Object;
	final cardG:h2d.Graphics;
	final title:h2d.Text;
	final line:h2d.Text;
	final hpText:h2d.Text;
	var cardAlpha = 0.0;

	final group:h2d.Object;
	final groupG:h2d.Graphics;
	final groupTitle:h2d.Text;
	final groupHp:h2d.Text;
	final rowTexts:Array<h2d.Text> = [];
	var groupAlpha = 0.0;
	var groupH = 0.0;

	public function new(?parent:h2d.Object) {
		super(parent);
		var font = hxd.res.DefaultFont.get();
		group = new h2d.Object(this);
		groupG = new h2d.Graphics(group);
		groupTitle = text(font, group, Palette.HUD_TEXT, 1.0);
		groupHp = text(font, group, Palette.HUD_DIM, 1.0);
		for (_ in 0...4) rowTexts.push(text(font, group, Palette.HUD_TEXT, 1.0));
		card = new h2d.Object(this);
		cardG = new h2d.Graphics(card);
		title = text(font, card, Palette.HUD_TEXT, 1.0);
		line = text(font, card, Palette.HUD_DIM, 1.0);
		hpText = text(font, card, Palette.HUD_DIM, 1.0);
		card.alpha = group.alpha = 0;
	}

	static function text(font:h2d.Font, parent:h2d.Object, color:Int, scale:Float):h2d.Text {
		var t = new h2d.Text(font, parent);
		t.textColor = color;
		t.letterSpacing = 1;
		t.setScale(scale);
		return t;
	}

	static inline function setText(t:h2d.Text, s:String)
		if (t.text != s) t.text = s;

	/**
		`hover` / `hoverShip`: under the cursor. `selected`: the player's
		selected characters; `selShip`: a selected ship. `left`/`bottom`: where
		the panels sit (device pixels).
	**/
	public function update(dt:Float, hover:Null<Unit>, hoverShip:Null<game.Ship>, selected:Array<Unit>, selShip:Null<game.Ship>, left:Float,
			bottom:Float) {
		setScale(ui);
		x = left;
		// The card: what's under the cursor, else the one selected character (or ship).
		var u = hover;
		var s = u == null ? hoverShip : null;
		if (u == null && s == null) {
			if (selected.length == 1) u = selected[0] else if (selected.length == 0) s = selShip;
		}
		var showCard = (u != null && u.alive) || (s != null && !s.sunk);
		if (showCard) {
			if (u != null) drawUnit(u) else drawShip(s);
		}
		var showGroup = selected.length > 1;
		if (showGroup) drawGroup(selected);
		cardAlpha = ease(cardAlpha, showCard ? 1 : 0, dt);
		groupAlpha = ease(groupAlpha, showGroup ? 1 : 0, dt);
		card.alpha = cardAlpha;
		group.alpha = groupAlpha;
		card.visible = cardAlpha > 0.01;
		group.visible = groupAlpha > 0.01;
		// Stack: the group panel at the bottom, the card above it while both show.
		var b = bottom / ui;
		group.y = b - groupH;
		card.y = (group.visible ? group.y - 8 : b) - CARD_H;
	}

	/** Fade in fast, out slowly (so a cursor passing over doesn't flicker it). **/
	static function ease(a:Float, target:Float, dt:Float):Float
		return target > a ? Math.min(target, a + dt * 9) : Math.max(target, a - dt * 3);

	static function kindName(k:UnitKind):String
		return switch k {
			case Captain: "CAPTAIN";
			case Swordsman: "SWORDSMAN";
			case Piker: "PIKER";
			case Archer: "ARCHER";
		};

	static function doing(u:Unit):String {
		if (u.aboard >= 0) return "ABOARD, MENDING";
		if (u.boarding >= 0) return "GOING ABOARD";
		if (u.flagProgress > 0) return "AT THE FLAG";
		if (u.targetId >= 0) return "FIGHTING";
		if (u.marching) return "MARCHING";
		if (u.hasTarget) return "MOVING";
		return "HOLDING";
	}

	static inline function teamName(t:Int) return t == 0 ? "BLUE" : "RED";

	static inline function teamCol(t:Int) return t == 0 ? Palette.HUD_BLUE : Palette.HUD_RED;

	static function healthCol(f:Float):Int
		return f > 0.6 ? Palette.HEALTH_OK : f > 0.3 ? Palette.HEALTH_LOW : Palette.HEALTH_CRIT;

	function panel(g:h2d.Graphics, w:Float, h:Float, team:Int) {
		g.clear();
		g.beginFill(Palette.HUD_PANEL, 0.82);
		g.drawRect(0, 0, w, h);
		g.endFill();
		// A thin team-coloured edge on the left: whose it is at a glance.
		g.beginFill(teamCol(team), 0.9);
		g.drawRect(0, 0, 2.5, h);
		g.endFill();
	}

	function bar(g:h2d.Graphics, x:Float, y:Float, w:Float, h:Float, f:Float) {
		f = Math.max(0, Math.min(1, f));
		g.beginFill(0xFFFFFF, 0.12);
		g.drawRect(x, y, w, h);
		g.endFill();
		g.beginFill(healthCol(f), 1);
		g.drawRect(x, y, w * f, h);
		g.endFill();
	}

	function drawUnit(u:Unit) {
		panel(cardG, CARD_W, CARD_H, u.team);
		glyph(cardG, u.kind, PAD + 2, PAD, 26, teamCol(u.team));
		setText(title, kindName(u.kind));
		title.setPosition(PAD + 38, PAD - 1);
		setText(line, teamName(u.team) + " / " + doing(u));
		line.setPosition(PAD + 38, PAD + 17);
		var f = u.hp / u.maxHp;
		bar(cardG, PAD + 2, CARD_H - PAD - 5, CARD_W - PAD * 2 - 74, 5, f);
		setText(hpText, Math.ceil(Math.max(0, u.hp)) + " / " + Math.round(u.maxHp));
		hpText.setPosition(CARD_W - PAD - 64, CARD_H - PAD - 10);
	}

	function drawShip(s:game.Ship) {
		panel(cardG, CARD_W, CARD_H, s.team);
		shipGlyph(cardG, PAD + 2, PAD, 26, teamCol(s.team));
		title.setPosition(PAD + 38, PAD - 1);
		var state = switch s.state {
			case Sailing: "UNDER SAIL";
			case Landing: "LANDING";
			case Idle: "AT ANCHOR";
		};
		setText(title, "SHIP" + (s.reload > 0 ? "   RELOADING" : ""));
		setText(line, teamName(s.team) + " / " + state + " / " + s.crew.length + " ABOARD");
		line.setPosition(PAD + 38, PAD + 17);
		bar(cardG, PAD + 2, CARD_H - PAD - 5, CARD_W - PAD * 2 - 74, 5, s.hp / s.maxHp);
		setText(hpText, "HULL " + Math.round(s.hp / s.maxHp * 100) + "%");
		hpText.setPosition(CARD_W - PAD - 64, CARD_H - PAD - 10);
	}

	function drawGroup(sel:Array<Unit>) {
		var kinds:Array<UnitKind> = [Captain, Swordsman, Piker, Archer];
		var rows = [for (k in kinds) [for (u in sel) if (u.kind == k) u]].filter(r -> r.length > 0);
		var rowH = 20.0;
		groupH = PAD * 2 + 22 + rows.length * rowH + 4;
		var w = CARD_W;
		panel(groupG, w, groupH, sel[0].team);
		var hp = 0.0, max = 0.0;
		for (u in sel) {
			hp += Math.max(0, u.hp);
			max += u.maxHp;
		}
		setText(groupTitle, sel.length + " SELECTED");
		groupTitle.setPosition(PAD + 2, PAD - 2);
		setText(groupHp, Math.round(hp / max * 100) + "%");
		groupHp.setPosition(w - PAD - 30, PAD - 1);
		bar(groupG, PAD + 2, PAD + 14, w - PAD * 2 - 2, 3, hp / max);
		for (k in 0...rowTexts.length) rowTexts[k].visible = k < rows.length;
		for (k in 0...rows.length) {
			var r = rows[k];
			var y = PAD + 26 + k * rowH;
			glyph(groupG, r[0].kind, PAD + 2, y, 14, teamCol(r[0].team));
			var t = rowTexts[k];
			setText(t, kindName(r[0].kind) + (r.length > 1 ? "  ×" + r.length : ""));
			t.setPosition(PAD + 22, y);
			// One pip per character, emptying as it's hurt.
			var px = w - PAD - r.length * 7;
			for (u in r) {
				var f = Math.max(0, u.hp / u.maxHp);
				groupG.beginFill(0xFFFFFF, 0.14);
				groupG.drawRect(px, y + 1, 4, 12);
				groupG.endFill();
				groupG.beginFill(healthCol(f), 1);
				groupG.drawRect(px, y + 1 + 12 * (1 - f), 4, 12 * f);
				groupG.endFill();
				px += 7;
			}
		}
	}

	// --- glyphs: a few ink strokes each, in a size x size box -----------------

	static function stroke(g:h2d.Graphics, pts:Array<Float>, x:Float, y:Float, s:Float) {
		g.moveTo(x + pts[0] * s, y + pts[1] * s);
		var k = 2;
		while (k < pts.length) {
			g.lineTo(x + pts[k] * s, y + pts[k + 1] * s);
			k += 2;
		}
	}

	public static function glyph(g:h2d.Graphics, kind:UnitKind, x:Float, y:Float, s:Float, col:Int) {
		g.lineStyle(Math.max(1.2, s * 0.08), col, 1);
		switch kind {
			case Swordsman:
				stroke(g, [0.5, 0.06, 0.5, 0.72], x, y, s); // blade
				stroke(g, [0.28, 0.72, 0.72, 0.72], x, y, s); // guard
				stroke(g, [0.5, 0.72, 0.5, 0.92], x, y, s); // grip
			case Piker:
				stroke(g, [0.18, 0.94, 0.8, 0.2], x, y, s); // shaft
				stroke(g, [0.72, 0.16, 0.92, 0.06, 0.84, 0.28, 0.72, 0.16], x, y, s); // head
			case Archer:
				// The bow: an arc, its string, and an arrow nocked across.
				var n = 10;
				for (k in 0...n + 1) {
					var a = -1.0 + 2.0 * k / n;
					var px = x + (0.3 + Math.cos(a) * 0.42) * s, py = y + (0.5 + Math.sin(a) * 0.46) * s;
					if (k == 0) g.moveTo(px, py) else g.lineTo(px, py);
				}
				var ex = 0.3 + Math.cos(1.0) * 0.42;
				stroke(g, [ex, 0.5 - Math.sin(1.0) * 0.46, ex, 0.5 + Math.sin(1.0) * 0.46], x, y, s);
				stroke(g, [0.12, 0.5, 0.92, 0.5], x, y, s);
				stroke(g, [0.8, 0.4, 0.92, 0.5, 0.8, 0.6], x, y, s);
			case Captain:
				stroke(g, [0.28, 0.96, 0.28, 0.06], x, y, s); // pole
				g.lineStyle();
				g.beginFill(col, 1);
				g.moveTo(x + 0.3 * s, y + 0.08 * s);
				g.lineTo(x + 0.9 * s, y + 0.24 * s);
				g.lineTo(x + 0.3 * s, y + 0.42 * s);
				g.endFill();
		}
		g.lineStyle();
	}

	static function shipGlyph(g:h2d.Graphics, x:Float, y:Float, s:Float, col:Int) {
		g.lineStyle(Math.max(1.2, s * 0.08), col, 1);
		stroke(g, [0.06, 0.7, 0.94, 0.7, 0.8, 0.9, 0.2, 0.9, 0.06, 0.7], x, y, s); // hull
		stroke(g, [0.5, 0.7, 0.5, 0.06], x, y, s); // mast
		g.lineStyle();
		g.beginFill(col, 0.85);
		g.moveTo(x + 0.54 * s, y + 0.1 * s);
		g.lineTo(x + 0.86 * s, y + 0.6 * s);
		g.lineTo(x + 0.54 * s, y + 0.6 * s);
		g.endFill();
	}
}
