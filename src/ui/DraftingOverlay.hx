package ui;

import render.Palette;

/**
	The Sketch style's drafting layer: the linework an architect puts
	around a presentation drawing, used here as game UI.

	- A sheet frame with registration ticks, and a title block (island,
	  shape, scale, sheet number).
	- A scale bar whose length in metres follows the zoom, and a north arrow
	  that turns with the camera.
	- Datum lines through the apex (the flag you fight over), with its
	  elevation, and leaders labelling each landing beach.
	- Move orders drawn as dimension lines: extension lines, slashed ticks,
	  and the distance in metres, fading after a few seconds.

	Pure 2D (h2d) and redrawn each frame from world positions projected
	through the 3D camera, so it costs almost nothing.
**/
class DraftingOverlay extends h2d.Object {
	static inline var DIM_LIFE = 3.2;

	final cam:h3d.Camera;
	final rts:input.RtsCamera;
	final lines:h2d.Graphics;
	final font:h2d.Font;
	final texts:Array<h2d.Text> = [];
	var textUsed = 0;
	var island:Null<world.Island> = null;
	var landings:Array<{x:Float, y:Float, label:String}> = [];
	var shapeName = "";
	final dims:Array<{fx:Float, fy:Float, tx:Float, ty:Float, age:Float}> = [];
	/** UI scale (devicePixelRatio): line widths and text are multiplied by it. **/
	public var ui = 1.0;

	public function new(cam:h3d.Camera, rts:input.RtsCamera, ?parent:h2d.Object) {
		super(parent);
		this.cam = cam;
		this.rts = rts;
		lines = new h2d.Graphics(this);
		font = hxd.res.DefaultFont.get();
	}

	public function setIsland(island:world.Island, landings:Array<{x:Float, y:Float, label:String}>) {
		this.island = island;
		this.landings = landings;
		shapeName = Std.string(island.shape).toUpperCase();
		dims.resize(0);
	}

	/** Draw a move order as a dimension line (world xy, from → to). **/
	public function addDimension(fx:Float, fy:Float, tx:Float, ty:Float) {
		dims.push({fx: fx, fy: fy, tx: tx, ty: ty, age: 0});
		if (dims.length > 4) dims.shift();
	}

	public function update(dt:Float, w:Float, h:Float) {
		lines.clear();
		textUsed = 0;
		if (visible && island != null) {
			frame(w, h);
			datum(w, h);
			for (l in landings) landing(l.x, l.y, l.label);
			var i = dims.length;
			while (i-- > 0) {
				dims[i].age += dt;
				if (dims[i].age > DIM_LIFE) dims.splice(i, 1);
			}
			for (d in dims) dimension(d.fx, d.fy, d.tx, d.ty, 1 - Math.pow(d.age / DIM_LIFE, 3), w, h);
			titleBlock(w, h);
			scaleBar(w, h);
		}
		for (k in textUsed...texts.length) texts[k].visible = false;
	}

	// --- pieces --------------------------------------------------------------

	function frame(w:Float, h:Float) {
		var m = 14 * ui;
		pen(1, 0.55);
		lines.drawRect(m, m, w - 2 * m, h - 2 * m);
		// Registration ticks past each corner, and a few along the edges.
		pen(1, 0.4);
		for (c in [[m, m], [w - m, m], [m, h - m], [w - m, h - m]]) {
			seg(c[0] - 8 * ui, c[1], c[0] + 8 * ui, c[1]);
			seg(c[0], c[1] - 8 * ui, c[0], c[1] + 8 * ui);
		}
		for (k in 1...8) {
			var x = m + (w - 2 * m) * k / 8;
			seg(x, m, x, m + (k % 2 == 0 ? 7 : 4) * ui);
			seg(x, h - m, x, h - m - (k % 2 == 0 ? 7 : 4) * ui);
		}
	}

	/** Long construction lines through the apex, with its elevation. **/
	function datum(w:Float, h:Float) {
		var top = island.apexH + 3.0;
		var base = project(island.apexX, island.apexY, island.apexH);
		var p = project(island.apexX, island.apexY, top);
		if (p == null || base == null) return;
		var m = 14 * ui;
		pen(1, 0.16);
		seg(m, p.y, w - m, p.y);
		seg(p.x, m, p.x, h - m);
		pen(1, 0.6);
		lines.drawCircle(p.x, p.y, 4 * ui, 12);
		seg(p.x, p.y, base.x, base.y);
		// Leader up and to the right, then the label on a short shelf.
		var lx = p.x + 34 * ui, ly = p.y - 34 * ui;
		seg(p.x + 3 * ui, p.y - 3 * ui, lx, ly);
		seg(lx, ly, lx + 92 * ui, ly);
		label(lx + 2 * ui, ly - 14 * ui, "APEX / FLAG", 0.85);
		label(lx + 2 * ui, ly + 3 * ui, 'EL. +' + fmt(island.apexH, 2) + ' M', 0.6);
	}

	function landing(x:Float, y:Float, text:String) {
		var p = project(x, y, Math.max(island.heightAt(x, y), 0) + 0.2);
		if (p == null) return;
		pen(1, 0.55);
		lines.drawCircle(p.x, p.y, 3 * ui, 10);
		// Leader straight down, clear of the dock, then the label on a shelf.
		var lx = p.x, ly = p.y + 64 * ui;
		seg(p.x, p.y + 3 * ui, lx, ly);
		seg(lx, ly, lx + 112 * ui, ly);
		label(lx + 4 * ui, ly - 14 * ui, text, 0.8);
	}

	/** An architect's dimension line between two ground points. **/
	function dimension(fx:Float, fy:Float, tx:Float, ty:Float, alpha:Float, w:Float, h:Float) {
		var za = Math.max(island.heightAt(fx, fy), 0), zb = Math.max(island.heightAt(tx, ty), 0);
		var a = project(fx, fy, za), b = project(tx, ty, zb);
		if (a == null || b == null) return;
		var dx = b.x - a.x, dy = b.y - a.y;
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len < 12 * ui) return;
		var ux = dx / len, uy = dy / len;
		// Offset the dimension line to one side, joined by extension lines.
		var nx = uy, ny = -ux;
		if (ny > 0) {
			nx = -nx;
			ny = -ny;
		}
		var off = 22 * ui, ext = 6 * ui;
		var a2x = a.x + nx * off, a2y = a.y + ny * off, b2x = b.x + nx * off, b2y = b.y + ny * off;
		pen(1, 0.45 * alpha);
		seg(a.x + nx * 4 * ui, a.y + ny * 4 * ui, a2x + nx * ext, a2y + ny * ext);
		seg(b.x + nx * 4 * ui, b.y + ny * 4 * ui, b2x + nx * ext, b2y + ny * ext);
		pen(1, 0.85 * alpha);
		// The line runs a little past each extension line, as drafters draw it.
		seg(a2x - ux * ext, a2y - uy * ext, b2x + ux * ext, b2y + uy * ext);
		// Slashed ticks (45° to the line) at both ends.
		pen(2, 0.9 * alpha);
		var t = 5 * ui;
		var sx = (ux + nx) * 0.7071 * t, sy = (uy + ny) * 0.7071 * t;
		seg(a2x - sx, a2y - sy, a2x + sx, a2y + sy);
		seg(b2x - sx, b2y - sy, b2x + sx, b2y + sy);
		// Distance in metres, beside the middle of the line.
		var mx = (a2x + b2x) / 2 + nx * 12 * ui, my = (a2y + b2y) / 2 + ny * 12 * ui;
		var metres = Math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy));
		var tt = label(0, 0, fmt(metres, 1) + " M", alpha);
		tt.setPosition(mx - tt.textWidth * tt.scaleX / 2, my - tt.textHeight * tt.scaleY / 2);
		// Target: a small cross in a circle, like a survey point.
		pen(1, 0.8 * alpha);
		lines.drawCircle(b.x, b.y, 5 * ui, 14);
		seg(b.x - 8 * ui, b.y, b.x + 8 * ui, b.y);
		seg(b.x, b.y - 8 * ui, b.x, b.y + 8 * ui);
	}

	function titleBlock(w:Float, h:Float) {
		var m = 14 * ui;
		var bw = 220 * ui, row = 17 * ui;
		var x = w - m - bw, y = m;
		var rows = [
			{t: "ATOLL ATTACK", a: 1.0},
			{t: 'SITE PLAN  -  ISLAND No. ' + island.seed, a: 0.8},
			{t: shapeName + ' ISLAND   SHEET A-01', a: 0.6},
			{t: 'DRAWN  M.R.     CHECKED  -', a: 0.5},
		];
		pen(1, 0.6);
		lines.drawRect(x, y, bw, row * rows.length);
		for (k in 0...rows.length) {
			if (k > 0) {
				pen(1, 0.3);
				seg(x, y + row * k, x + bw, y + row * k);
			}
			label(x + 6 * ui, y + row * k + 3 * ui, rows[k].t, rows[k].a);
		}
		northArrow(x + bw - 26 * ui, y + row * rows.length + 34 * ui, 15 * ui);
	}

	/** North arrow: world +Y projected to the screen, so it turns with the camera. **/
	function northArrow(cx:Float, cy:Float, r:Float) {
		var a = project(rts.targetX, rts.targetY, 0), b = project(rts.targetX, rts.targetY + 10, 0);
		if (a == null || b == null) return;
		var dx = b.x - a.x, dy = b.y - a.y;
		var l = Math.sqrt(dx * dx + dy * dy);
		if (l < 1e-3) return;
		dx /= l;
		dy /= l;
		pen(1, 0.6);
		lines.drawCircle(cx, cy, r, 24);
		var tipx = cx + dx * r * 1.35, tipy = cy + dy * r * 1.35;
		var px = -dy * r * 0.35, py = dx * r * 0.35;
		lines.lineStyle();
		lines.beginFill(Palette.SKETCH_LINE, 0.85);
		lines.moveTo(tipx, tipy);
		lines.lineTo(cx + px, cy + py);
		lines.lineTo(cx, cy);
		lines.lineTo(tipx, tipy);
		lines.endFill();
		pen(1, 0.85);
		seg(tipx, tipy, cx - px, cy - py);
		seg(cx - px, cy - py, cx, cy);
		var t = label(0, 0, "N", 0.9);
		t.setPosition(tipx + dx * 8 * ui - t.textWidth * t.scaleX / 2, tipy + dy * 8 * ui - t.textHeight * t.scaleY / 2);
	}

	/** A scale bar in metres, sized to the current zoom. **/
	function scaleBar(w:Float, h:Float) {
		var cy = h * 0.5;
		var p0 = rts.screenToPlane(w * 0.5, cy, w, h, 0), p1 = rts.screenToPlane(w * 0.5 + 100, cy, w, h, 0);
		if (p0 == null || p1 == null) return;
		var mPerPx = Math.sqrt((p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y)) / 100;
		if (mPerPx <= 0) return;
		// The round length (1, 2, 5, 10…) closest to ~160 px on screen.
		var target = 160 * ui * mPerPx;
		var nice = 1.0;
		for (n in [1.0, 2, 5, 10, 20, 50, 100, 200])
			if (Math.abs(Math.log(n / target)) < Math.abs(Math.log(nice / target))) nice = n;
		var px = nice / mPerPx;
		var x = w * 0.5 - px / 2, y = h - 14 * ui - 26 * ui, bh = 5 * ui;
		for (k in 0...4) {
			var sx = x + px * k / 4;
			lines.lineStyle(1 * ui, Palette.SKETCH_LINE, 0.8);
			lines.beginFill(k % 2 == 0 ? Palette.SKETCH_LINE : Palette.SKETCH_PAPER, k % 2 == 0 ? 0.8 : 0.6);
			lines.drawRect(sx, y, px / 4, bh);
			lines.endFill();
		}
		for (k in [0, 2, 4]) {
			var v = nice * k / 4;
			var t = label(0, 0, (v == Std.int(v) ? Std.string(Std.int(v)) : fmt(v, 1)) + (k == 4 ? " M" : ""), 0.7);
			t.setPosition(x + px * k / 4 - (k == 4 ? 0 : t.textWidth * t.scaleX / 2), y + bh + 3 * ui);
		}
		var t = label(0, 0, "SCALE", 0.5);
		t.setPosition(x - t.textWidth * t.scaleX - 10 * ui, y - 2 * ui);
	}

	// --- helpers -------------------------------------------------------------

	function project(x:Float, y:Float, z:Float):Null<h3d.Vector> {
		var p = cam.project(x, y, z, getScene().width, getScene().height);
		if (p.z < 0 || p.z > 1 || !Math.isFinite(p.x)) return null;
		return p;
	}

	inline function pen(width:Float, alpha:Float)
		lines.lineStyle(width * ui, Palette.SKETCH_LINE, alpha);

	inline function seg(x0:Float, y0:Float, x1:Float, y1:Float) {
		lines.moveTo(x0, y0);
		lines.lineTo(x1, y1);
	}

	function label(x:Float, y:Float, text:String, alpha:Float):h2d.Text {
		var t:h2d.Text;
		if (textUsed < texts.length) t = texts[textUsed] else {
			t = new h2d.Text(font, this);
			t.textColor = Palette.SKETCH_LINE;
			texts.push(t);
		}
		textUsed++;
		t.visible = true;
		t.text = text;
		t.alpha = alpha;
		t.setScale(ui);
		t.setPosition(x, y);
		return t;
	}

	static function fmt(v:Float, digits:Int):String {
		var p = Math.pow(10, digits);
		var s = Std.string(Math.round(v * p) / p);
		if (digits > 0 && s.indexOf(".") < 0) s += "." + [for (_ in 0...digits) "0"].join("");
		return s;
	}
}
