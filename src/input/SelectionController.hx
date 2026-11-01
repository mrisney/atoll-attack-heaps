package input;

import game.Command;
import game.Sim;
import render.UnitView;

/**
	Turns raw pointer events into selection state and Commands.

	Mouse:  left-drag = box select, left-click = select / move,
	        right-click = move, shift = add to selection.
	Touch:  drag = box select, tap = select / move,
	        two fingers = pan + pinch zoom.
**/
class SelectionController {
	static inline var DRAG_THRESHOLD = 8.0;
	static inline var PICK_RADIUS = 22.0;

	final sim:Sim;
	final views:Array<UnitView>;
	final s3d:h3d.scene.Scene;
	final s2d:h2d.Scene;
	final camera:RtsCamera;
	final box:h2d.Graphics;

	public var localTeam = 0;
	public var mouseX(default, null) = -1.0;
	public var mouseY(default, null) = -1.0;

	var pointers:Map<Int, {x:Float, y:Float}> = new Map();
	var pressX = 0.0;
	var pressY = 0.0;
	var pressing = false;
	var dragging = false;
	var gesture = false;
	var lastPinchDist = 0.0;
	var lastMidX = 0.0;
	var lastMidY = 0.0;

	var marker:h3d.scene.Object;
	var markerTime = 0.0;

	public function new(sim:Sim, views:Array<UnitView>, s3d:h3d.scene.Scene, s2d:h2d.Scene, camera:RtsCamera) {
		this.sim = sim;
		this.views = views;
		this.s3d = s3d;
		this.s2d = s2d;
		this.camera = camera;
		box = new h2d.Graphics(s2d);

		marker = new h3d.scene.Object(s3d);
		var mb = new render.FlatMeshBuilder();
		mb.ring(0, 0, 0.08, 0.35, 0.5, 18, render.Palette.SELECT);
		mb.build(marker, false);
		marker.visible = false;

		hxd.Window.getInstance().addEventTarget(onEvent);
	}

	public function dispose() {
		hxd.Window.getInstance().removeEventTarget(onEvent);
		box.remove();
		marker.remove();
	}

	public function update(dt:Float) {
		if (marker.visible) {
			markerTime += dt;
			var s = 1 + markerTime * 2.5;
			marker.setScale(s);
			if (markerTime > 0.45) marker.visible = false;
		}
	}

	function onEvent(e:hxd.Event) {
		switch e.kind {
			case EPush:
				pointers.set(e.touchId, {x: e.relX, y: e.relY});
				if (countPointers() >= 2) {
					startGesture();
					return;
				}
				if (e.button == 1) {
					// Right click: move order.
					orderMoveAt(e.relX, e.relY);
					return;
				}
				if (e.button != 0) return;
				pressing = true;
				dragging = false;
				pressX = e.relX;
				pressY = e.relY;

			case EMove:
				mouseX = e.relX;
				mouseY = e.relY;
				if (pointers.exists(e.touchId)) pointers.set(e.touchId, {x: e.relX, y: e.relY});
				if (gesture) {
					updateGesture();
					return;
				}
				if (pressing) {
					var dx = e.relX - pressX, dy = e.relY - pressY;
					if (!dragging && dx * dx + dy * dy > DRAG_THRESHOLD * DRAG_THRESHOLD) dragging = true;
					if (dragging) drawBox(e.relX, e.relY);
				}

			case ERelease, EReleaseOutside:
				pointers.remove(e.touchId);
				if (gesture) {
					if (countPointers() == 0) gesture = false;
					return;
				}
				if (!pressing || e.button != 0) return;
				pressing = false;
				box.clear();
				var additive = hxd.Key.isDown(hxd.Key.SHIFT);
				if (dragging) {
					selectInRect(pressX, pressY, e.relX, e.relY, additive);
				} else {
					var hit = pickUnit(e.relX, e.relY);
					if (hit != null && hit.unit.team == localTeam) {
						if (additive) {
							hit.selected = !hit.selected;
						} else {
							clearSelection();
							hit.selected = true;
						}
					} else if (selectedIds().length > 0) {
						orderMoveAt(e.relX, e.relY);
					} else {
						clearSelection();
					}
				}
				dragging = false;

			case EWheel:
				camera.zoom(e.wheelDelta > 0 ? 1.12 : 1 / 1.12);

			default:
		}
	}

	// --- selection -------------------------------------------------------

	public function selectedIds():Array<Int> {
		return [for (v in views) if (v.selected) v.unit.id];
	}

	function clearSelection() {
		for (v in views) v.selected = false;
	}

	function screenPos(v:UnitView):h3d.Vector {
		return s3d.camera.project(v.x, v.y, v.z + 0.6, s2d.width, s2d.height);
	}

	function pickUnit(sx:Float, sy:Float):Null<UnitView> {
		var best:UnitView = null;
		var bestD = PICK_RADIUS * PICK_RADIUS;
		for (v in views) {
			var p = screenPos(v);
			var dx = p.x - sx, dy = p.y - sy;
			var d = dx * dx + dy * dy;
			if (d < bestD) {
				bestD = d;
				best = v;
			}
		}
		return best;
	}

	function selectInRect(x0:Float, y0:Float, x1:Float, y1:Float, additive:Bool) {
		var minX = Math.min(x0, x1), maxX = Math.max(x0, x1);
		var minY = Math.min(y0, y1), maxY = Math.max(y0, y1);
		if (!additive) clearSelection();
		for (v in views) {
			if (v.unit.team != localTeam) continue;
			var p = screenPos(v);
			if (p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY) v.selected = true;
		}
	}

	function drawBox(x:Float, y:Float) {
		box.clear();
		box.beginFill(render.Palette.SELECT, 0.12);
		box.lineStyle(1.5, render.Palette.SELECT, 0.9);
		box.drawRect(Math.min(pressX, x), Math.min(pressY, y), Math.abs(x - pressX), Math.abs(y - pressY));
		box.endFill();
	}

	// --- orders ----------------------------------------------------------

	function orderMoveAt(sx:Float, sy:Float) {
		var ids = selectedIds();
		if (ids.length == 0) return;
		var hit = groundAt(sx, sy);
		if (hit == null) return;
		sim.queue(Move(ids, hit.x, hit.y));
		marker.setPosition(hit.x, hit.y, Math.max(hit.z, 0));
		marker.setScale(1);
		markerTime = 0;
		marker.visible = true;
	}

	/** Ray-march from the cursor until we hit terrain or the sea surface. **/
	function groundAt(sx:Float, sy:Float):Null<h3d.Vector> {
		var ray = s3d.camera.rayFromScreen(sx, sy, Std.int(s2d.width), Std.int(s2d.height));
		var len = Math.sqrt(ray.lx * ray.lx + ray.ly * ray.ly + ray.lz * ray.lz);
		var lx = ray.lx / len, ly = ray.ly / len, lz = ray.lz / len;
		var t = 0.0, stepLen = 0.5;
		var prevAbove = true;
		while (t < 500) {
			var x = ray.px + lx * t, y = ray.py + ly * t, z = ray.pz + lz * t;
			var ground = Math.max(sim.island.heightAt(x, y), world.Island.SEA_LEVEL);
			if (z <= ground) {
				// Refine with a few bisection steps.
				var a = t - stepLen, b = t;
				for (_ in 0...6) {
					var m = (a + b) * 0.5;
					var mx = ray.px + lx * m, my = ray.py + ly * m, mz = ray.pz + lz * m;
					if (mz <= Math.max(sim.island.heightAt(mx, my), 0)) b = m else a = m;
				}
				var hx = ray.px + lx * b, hy = ray.py + ly * b;
				return new h3d.Vector(hx, hy, sim.island.heightAt(hx, hy));
			}
			t += stepLen;
		}
		return null;
	}

	// --- touch gestures --------------------------------------------------

	function countPointers():Int {
		var n = 0;
		for (_ in pointers) n++;
		return n;
	}

	function twoPointers():Array<{x:Float, y:Float}> {
		var out = [];
		for (p in pointers) {
			out.push(p);
			if (out.length == 2) break;
		}
		return out;
	}

	function startGesture() {
		gesture = true;
		pressing = false;
		dragging = false;
		box.clear();
		var p = twoPointers();
		lastPinchDist = dist(p[0], p[1]);
		lastMidX = (p[0].x + p[1].x) * 0.5;
		lastMidY = (p[0].y + p[1].y) * 0.5;
	}

	function updateGesture() {
		if (countPointers() < 2) return;
		var p = twoPointers();
		var d = dist(p[0], p[1]);
		var midX = (p[0].x + p[1].x) * 0.5, midY = (p[0].y + p[1].y) * 0.5;
		if (lastPinchDist > 1 && d > 1) camera.zoom(lastPinchDist / d);
		// Convert pixel drag to world pan, scaled by zoom.
		var k = camera.distance / Math.max(1, s2d.height) * 1.2;
		camera.panScreen(-(midX - lastMidX) * k, (midY - lastMidY) * k);
		lastPinchDist = d;
		lastMidX = midX;
		lastMidY = midY;
	}

	static inline function dist(a:{x:Float, y:Float}, b:{x:Float, y:Float}):Float {
		var dx = a.x - b.x, dy = a.y - b.y;
		return Math.sqrt(dx * dx + dy * dy);
	}
}
