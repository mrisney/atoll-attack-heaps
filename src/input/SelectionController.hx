package input;

import game.Command;
import game.Sim;
import render.UnitView;

enum PointerMode {
	Idle;
	/** Button/finger down, not yet decided between a click and a drag. **/
	Pending;
	BoxSelect;
	/** Grab-pan: the grabbed ground point stays under the cursor/finger. **/
	Pan;
	/** Two fingers: pan + pinch. **/
	Gesture;
}

/**
	Turns raw pointer events into selection state, camera moves and Commands.

	Mouse:
	  left-drag = box select, left-click = select / move order
	  right-click = move order, right- or middle-drag = grab and pan the map
	  shift = add to selection
	Trackpad (web): two-finger swipe = pan, pinch = zoom
	Mouse wheel: zoom
	Touch:
	  one-finger drag = pan, tap = select / move order
	  press and hold, then drag = box select
	  two fingers = pan + pinch zoom
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
	/** Returns true when a point is over on-screen UI, so taps there aren't orders. **/
	public var uiHitTest:Null<(Float, Float) -> Bool> = null;
	public var mouseX(default, null) = -1.0;
	public var mouseY(default, null) = -1.0;

	static inline var HOLD_TO_SELECT = 0.35;

	var pointers:Map<Int, {x:Float, y:Float}> = new Map();
	var mode:PointerMode = Idle;
	var pressX = 0.0;
	var pressY = 0.0;
	var pressButton = 0;
	var pressTouch = false;
	var pressTime = 0.0;
	/** Grab-pan anchor: world point under the cursor when the drag started. **/
	var anchor:Null<h3d.Vector> = null;
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
		#if js
		installWebInput(this);
		#end
	}

	public function dispose() {
		hxd.Window.getInstance().removeEventTarget(onEvent);
		#if js
		if (webTarget == this) webTarget = null;
		#end
		box.remove();
		marker.remove();
	}

	/** Debug: knock down every unit near the cursor (tests the rag dolls). **/
	public var blastRadius = 3.5;

	public function blastAt(sx:Float, sy:Float) {
		var hit = groundAt(sx, sy);
		if (hit == null) return;
		var ids = [];
		for (v in views) {
			var dx = v.unit.x - hit.x, dy = v.unit.y - hit.y;
			if (v.unit.alive && dx * dx + dy * dy < blastRadius * blastRadius) ids.push(v.unit.id);
		}
		if (ids.length > 0) sim.queue(Kill(ids, hit.x, hit.y));
		marker.setPosition(hit.x, hit.y, Math.max(hit.z, 0));
		marker.setScale(3);
		markerTime = 0;
		marker.visible = true;
	}

	public function update(dt:Float) {
		if (hxd.Key.isPressed(hxd.Key.X) && mouseX >= 0) blastAt(mouseX, mouseY);
		// Touch: holding still turns the press into a box select.
		if (mode == Pending && pressTouch) {
			pressTime += dt;
			if (pressTime >= HOLD_TO_SELECT) {
				mode = BoxSelect;
				drawBox(pressX + 1, pressY + 1);
			}
		}
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
				if (uiHitTest != null && uiHitTest(e.relX, e.relY)) return;
				pointers.set(e.touchId, {x: e.relX, y: e.relY});
				if (countPointers() >= 2) {
					startGesture();
					return;
				}
				pressX = e.relX;
				pressY = e.relY;
				pressButton = e.button;
				pressTouch = lastInputWasTouch;
				pressTime = 0;
				if (e.button == 2) {
					// Middle button: always pan.
					startPan(e.relX, e.relY);
				} else {
					mode = Pending;
				}

			case EMove:
				mouseX = e.relX;
				mouseY = e.relY;
				if (pointers.exists(e.touchId)) pointers.set(e.touchId, {x: e.relX, y: e.relY});
				switch mode {
					case Gesture:
						updateGesture();
					case Pending:
						var dx = e.relX - pressX, dy = e.relY - pressY;
						if (dx * dx + dy * dy > DRAG_THRESHOLD * DRAG_THRESHOLD) {
							// Left mouse drags select; right drag and one-finger touch drag pan.
							if (pressButton == 0 && !pressTouch) {
								mode = BoxSelect;
								drawBox(e.relX, e.relY);
							} else {
								startPan(pressX, pressY);
								dragPan(e.relX, e.relY);
							}
						}
					case BoxSelect:
						drawBox(e.relX, e.relY);
					case Pan:
						dragPan(e.relX, e.relY);
					case Idle:
				}

			case ERelease, EReleaseOutside:
				pointers.remove(e.touchId);
				switch mode {
					case Gesture:
						if (countPointers() == 0) mode = Idle;
					case BoxSelect:
						box.clear();
						selectInRect(pressX, pressY, e.relX, e.relY, hxd.Key.isDown(hxd.Key.SHIFT));
						mode = Idle;
					case Pan:
						anchor = null;
						mode = Idle;
					case Pending:
						mode = Idle;
						if (e.kind == EReleaseOutside) return;
						if (pressButton == 1) orderMoveAt(e.relX, e.relY) else if (pressButton == 0) click(e.relX, e.relY);
					case Idle:
				}

			case EWheel:
				// On the web the DOM handler below deals with wheel/trackpad/pinch.
				#if !js
				camera.zoom(e.wheelDelta > 0 ? 1.12 : 1 / 1.12);
				#end

			case EOut, EFocusLost:
				// Stop edge-scrolling when the cursor leaves the window.
				mouseX = -1;
				mouseY = -1;

			default:
		}
	}

	/** A click/tap without dragging: select a unit, or order selected units there. **/
	function click(sx:Float, sy:Float) {
		var additive = hxd.Key.isDown(hxd.Key.SHIFT);
		var hit = pickUnit(sx, sy);
		if (hit != null && hit.unit.team == localTeam) {
			if (additive) {
				hit.selected = !hit.selected;
			} else {
				clearSelection();
				hit.selected = true;
			}
		} else if (selectedIds().length > 0) {
			orderMoveAt(sx, sy);
		} else {
			clearSelection();
		}
	}

	// --- grab pan -----------------------------------------------------------

	function startPan(sx:Float, sy:Float) {
		mode = Pan;
		box.clear();
		var g = groundAt(sx, sy);
		var z = g == null ? 0.0 : Math.max(g.z, 0);
		anchor = camera.screenToPlane(sx, sy, s2d.width, s2d.height, z);
	}

	function dragPan(sx:Float, sy:Float) {
		if (anchor == null) return;
		var p = camera.screenToPlane(sx, sy, s2d.width, s2d.height, anchor.z);
		if (p == null) return;
		camera.shift(anchor.x - p.x, anchor.y - p.y);
	}

	// --- web wheel / trackpad --------------------------------------------------
	#if js
	static var webTarget:Null<SelectionController> = null;
	static var webInstalled = false;
	static var lastInputWasTouch = false;

	/**
		The browser tells us more than Heaps' wheel event does: horizontal
		deltas, and ctrlKey for trackpad pinches. Use it to make a Mac trackpad
		behave like a map (swipe pans, pinch zooms) while a mouse wheel still zooms.
	**/
	static function installWebInput(target:SelectionController) {
		webTarget = target;
		if (webInstalled) return;
		webInstalled = true;
		var w = js.Browser.window;
		w.addEventListener("touchstart", (_) -> lastInputWasTouch = true, {capture: true, passive: true});
		w.addEventListener("mousedown", (_) -> lastInputWasTouch = false, {capture: true, passive: true});
		w.addEventListener("wheel", (e:js.html.WheelEvent) -> {
			e.preventDefault();
			e.stopPropagation();
			if (webTarget != null) webTarget.onWebWheel(e);
		}, {capture: true, passive: false});
	}

	function onWebWheel(e:js.html.WheelEvent) {
		var px = e.deltaMode == 1 ? 16.0 : (e.deltaMode == 2 ? 400.0 : 1.0);
		var dx = e.deltaX * px, dy = e.deltaY * px;
		if (e.ctrlKey) {
			// Trackpad pinch (browsers report it as ctrl + wheel).
			camera.zoom(Math.exp(dy * 0.01), true);
		} else if (dx != 0 || Math.abs(dy) < 40 || dy % 1 != 0) {
			// Two-finger swipe: move the map with the fingers.
			var k = camera.distance / Math.max(1, js.Browser.window.innerHeight) * 1.1;
			var fx = -Math.cos(camera.yaw), fy = -Math.sin(camera.yaw);
			var rx = fy, ry = -fx;
			camera.shift((rx * dx - fx * dy) * k, (ry * dx - fy * dy) * k);
		} else {
			// Mouse wheel notch.
			camera.zoom(dy > 0 ? 1.15 : 1 / 1.15);
		}
	}
	#else
	static var lastInputWasTouch = false;
	#end

	// --- selection -------------------------------------------------------

	public function selectedIds():Array<Int> {
		return [for (v in views) if (v.selected && v.unit.alive) v.unit.id];
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
			if (!v.unit.alive) continue;
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
			if (v.unit.team != localTeam || !v.unit.alive) continue;
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

	/** Order the selected units to a world position (used by the minimap). **/
	public function orderMoveWorld(x:Float, y:Float) {
		var ids = selectedIds();
		if (ids.length == 0) return;
		sim.queue(Move(ids, x, y));
		marker.setPosition(x, y, Math.max(sim.island.heightAt(x, y), 0));
		marker.setScale(1);
		markerTime = 0;
		marker.visible = true;
	}

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
		mode = Gesture;
		anchor = null;
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
		if (lastPinchDist > 1 && d > 1) camera.zoom(lastPinchDist / d, true);
		// Move the map with the fingers' midpoint.
		var a = camera.screenToPlane(lastMidX, lastMidY, s2d.width, s2d.height, 0);
		var b = camera.screenToPlane(midX, midY, s2d.width, s2d.height, 0);
		if (a != null && b != null) camera.shift(a.x - b.x, a.y - b.y);
		lastPinchDist = d;
		lastMidX = midX;
		lastMidY = midY;
	}

	static inline function dist(a:{x:Float, y:Float}, b:{x:Float, y:Float}):Float {
		var dx = a.x - b.x, dy = a.y - b.y;
		return Math.sqrt(dx * dx + dy * dy);
	}
}
