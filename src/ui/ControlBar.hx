package ui;

import render.Palette;

/**
	On-screen camera controls, bottom-right: zoom in/out, rotate left/right,
	and re-centre on your squad. Paper buttons with an ink outline, sized for
	touch (44 px, Apple's minimum tap target).

	Tap for one step, or hold to keep zooming/rotating.
**/
class ControlBar extends h2d.Object {
	static inline var SIZE = 44.0;
	static inline var GAP = 10.0;
	static inline var MARGIN = 18.0;
	static inline var HOLD_DELAY = 0.3;

	final camera:input.RtsCamera;
	final recenter:() -> Void;

	var buttons:Array<{bg:h2d.Graphics, hit:h2d.Interactive}> = [];
	var held:Null<Float->Void> = null;
	var heldTime = 0.0;

	public function new(camera:input.RtsCamera, recenter:() -> Void, ?parent:h2d.Object) {
		super(parent);
		this.camera = camera;
		this.recenter = recenter;

		// step = one tap, hold = per-second rate while held
		addButton(drawPlus, () -> camera.zoom(1 / 1.25), (dt) -> camera.zoom(Math.pow(1 / 2.2, dt)));
		addButton(drawMinus, () -> camera.zoom(1.25), (dt) -> camera.zoom(Math.pow(2.2, dt)));
		addButton((g) -> drawRotate(g, -1), () -> turnCamera(-Math.PI / 8), (dt) -> turnCamera(-dt * 1.4));
		addButton((g) -> drawRotate(g, 1), () -> turnCamera(Math.PI / 8), (dt) -> turnCamera(dt * 1.4));
		addButton(drawTarget, recenter, null);
	}

	function turnCamera(a:Float) {
		camera.yaw += a;
		camera.apply();
	}

	/** True if a screen point is over a button, so the game can ignore that tap. **/
	public function hitTest(x:Float, y:Float):Bool {
		for (b in buttons) {
			var r = b.hit.getBounds();
			if (x >= r.xMin && x <= r.xMax && y >= r.yMin && y <= r.yMax) return true;
		}
		return false;
	}

	public function update(dt:Float, screenW:Float, screenH:Float) {
		// Vertical stack anchored bottom-right; re-laid out every frame so resizes just work.
		var n = buttons.length;
		var s = scaleX; // UI scale (Retina)
		x = screenW - (MARGIN + SIZE) * s;
		y = screenH - (MARGIN + n * SIZE + (n - 1) * GAP) * s;
		if (held != null) {
			heldTime += dt;
			if (heldTime > HOLD_DELAY) held(dt);
		}
	}

	function addButton(icon:h2d.Graphics->Void, step:() -> Void, hold:Null<Float->Void>) {
		var i = buttons.length;
		var bg = new h2d.Graphics(this);
		bg.y = i * (SIZE + GAP);
		paintButton(bg, false);
		var g = new h2d.Graphics(bg);
		icon(g);

		var hit = new h2d.Interactive(SIZE, SIZE, bg);
		hit.isEllipse = true;
		hit.onPush = function(_) {
			paintButton(bg, true);
			step();
			held = hold;
			heldTime = 0;
		};
		var release = function(_) {
			paintButton(bg, false);
			held = null;
		};
		hit.onRelease = release;
		hit.onReleaseOutside = release;
		buttons.push({bg: bg, hit: hit});
	}

	static function paintButton(g:h2d.Graphics, pressed:Bool) {
		// Keep child (icon) graphics; only redraw this layer.
		g.clear();
		var r = SIZE / 2;
		g.beginFill(0x000000, 0.18); // soft drop shadow
		g.drawCircle(r + 1.5, r + 2.5, r, 32);
		g.endFill();
		g.lineStyle(2.2, Palette.INK, 1);
		g.beginFill(pressed ? 0xE4DED0 : Palette.PAPER, 1);
		g.drawCircle(r, r, r - 1, 32);
		g.endFill();
	}

	// --- icons (ink strokes on a 44 px button) ---------------------------

	static inline function pen(g:h2d.Graphics)
		g.lineStyle(3, Palette.INK, 1);

	static function drawPlus(g:h2d.Graphics) {
		pen(g);
		var c = SIZE / 2;
		g.moveTo(c - 9, c);
		g.lineTo(c + 9, c);
		g.moveTo(c, c - 9);
		g.lineTo(c, c + 9);
	}

	static function drawMinus(g:h2d.Graphics) {
		pen(g);
		var c = SIZE / 2;
		g.moveTo(c - 9, c);
		g.lineTo(c + 9, c);
	}

	/** A curved arrow; dir = -1 anticlockwise, +1 clockwise. **/
	static function drawRotate(g:h2d.Graphics, dir:Int) {
		pen(g);
		var c = SIZE / 2, r = 10.0;
		var a0 = -Math.PI * 0.75, a1 = Math.PI * 0.5;
		var segs = 14;
		for (k in 0...segs + 1) {
			var a = a0 + (a1 - a0) * k / segs;
			var px = c + Math.cos(a) * r * dir, py = c + Math.sin(a) * r;
			if (k == 0) g.moveTo(px, py) else g.lineTo(px, py);
		}
		// Arrowhead at the end of the arc.
		var ex = c + Math.cos(a1) * r * dir, ey = c + Math.sin(a1) * r;
		g.moveTo(ex, ey);
		g.lineTo(ex + 6 * dir, ey - 5);
		g.moveTo(ex, ey);
		g.lineTo(ex + 6 * dir, ey + 5);
	}

	static function drawTarget(g:h2d.Graphics) {
		pen(g);
		var c = SIZE / 2;
		g.drawCircle(c, c, 8, 20);
		g.moveTo(c, c - 14);
		g.lineTo(c, c - 9);
		g.moveTo(c, c + 9);
		g.lineTo(c, c + 14);
		g.moveTo(c - 14, c);
		g.lineTo(c - 9, c);
		g.moveTo(c + 9, c);
		g.lineTo(c + 14, c);
		g.lineStyle();
		g.beginFill(Palette.INK, 1);
		g.drawCircle(c, c, 2.5, 10);
		g.endFill();
	}
}
