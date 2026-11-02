package input;

/**
	Classic RTS camera: orbit a ground target at a fixed pitch.

	The public fields (`targetX`, `targetY`, `distance`, `yaw`) are where the
	camera *wants* to be. Each frame the actual view eases toward them, so
	keyboard and edge panning, zoom, rotation and re-centring all glide instead
	of jumping. Direct manipulation (grab-dragging the map, touch gestures,
	trackpad swipes) uses `shift()` and `snap()`, which move the view
	immediately so it stays glued to your finger or cursor.
**/
class RtsCamera {
	final cam:h3d.Camera;

	// Desired state.
	public var targetX = 0.0;
	public var targetY = 0.0;
	public var distance = 48.0;
	public var yaw = -Math.PI * 0.5;
	public var pitch = 0.95; // radians above the horizon

	public var minDistance = 14.0;
	public var maxDistance = 95.0;
	public var bounds = 80.0;
	public var edgeScroll = true;
	/** Higher = snappier easing. **/
	public var smoothing = 10.0;

	// Current (displayed) state.
	var curX = 0.0;
	var curY = 0.0;
	var curDist = 48.0;
	var curYaw = -Math.PI * 0.5;

	public function new(cam:h3d.Camera) {
		this.cam = cam;
		cam.fovY = 32;
		cam.zNear = 1;
		cam.zFar = 600;
		snap();
	}

	public function update(dt:Float, mouseX:Float, mouseY:Float, width:Float, height:Float) {
		var fast = hxd.Key.isDown(hxd.Key.SHIFT) ? 2.5 : 1.0;
		var speed = distance * 0.9 * dt * fast;
		var mx = 0.0, my = 0.0;
		if (hxd.Key.isDown(hxd.Key.W) || hxd.Key.isDown(hxd.Key.UP)) my += 1;
		if (hxd.Key.isDown(hxd.Key.S) || hxd.Key.isDown(hxd.Key.DOWN)) my -= 1;
		if (hxd.Key.isDown(hxd.Key.A) || hxd.Key.isDown(hxd.Key.LEFT)) mx -= 1;
		if (hxd.Key.isDown(hxd.Key.D) || hxd.Key.isDown(hxd.Key.RIGHT)) mx += 1;

		// Edge scroll only while the cursor is actually inside the window.
		if (edgeScroll && width > 0 && mouseX >= 0 && mouseY >= 0) {
			var edge = 8;
			if (mouseX < edge) mx -= 1;
			if (mouseX > width - edge) mx += 1;
			if (mouseY < edge) my += 1;
			if (mouseY > height - edge) my -= 1;
		}
		if (mx != 0 || my != 0) panScreen(mx * speed, my * speed);

		if (hxd.Key.isDown(hxd.Key.Q)) yaw -= dt * 1.4;
		if (hxd.Key.isDown(hxd.Key.E)) yaw += dt * 1.4;

		// Ease the view toward the desired state (frame-rate independent).
		var k = 1 - Math.exp(-dt * smoothing);
		curX += (targetX - curX) * k;
		curY += (targetY - curY) * k;
		curDist += (distance - curDist) * k;
		curYaw += (yaw - curYaw) * k;
		apply();
	}

	/** Pan in screen-aligned directions (right, forward) in world units. Eased. **/
	public function panScreen(right:Float, forward:Float) {
		var fx = -Math.cos(yaw), fy = -Math.sin(yaw);
		var rx = fy, ry = -fx; // forward × up
		targetX += rx * right + fx * forward;
		targetY += ry * right + fy * forward;
		clamp();
	}

	/** Move the view by a world-space offset *immediately* (drag, swipe, pinch). **/
	public function shift(dx:Float, dy:Float) {
		targetX += dx;
		targetY += dy;
		clamp();
		curX = targetX;
		curY = targetY;
		apply();
	}

	/** Zoom by a factor. Eased unless `immediate`. **/
	public function zoom(factor:Float, immediate = false) {
		distance *= factor;
		if (distance < minDistance) distance = minDistance;
		if (distance > maxDistance) distance = maxDistance;
		if (immediate) {
			curDist = distance;
			apply();
		}
	}

	/** Glide to look at a world position (minimap clicks, re-centre). **/
	public function lookAt(x:Float, y:Float) {
		targetX = x;
		targetY = y;
		clamp();
	}

	/** Jump the view to the desired state with no easing. **/
	public function snap() {
		clamp();
		curX = targetX;
		curY = targetY;
		curDist = distance;
		curYaw = yaw;
		apply();
	}

	/**
		Where a screen point hits the horizontal plane at height `z`, using the
		*current* view. Used for grab-panning: the grabbed point stays under the
		cursor.
	**/
	public function screenToPlane(sx:Float, sy:Float, w:Float, h:Float, z:Float):Null<h3d.Vector> {
		var ray = cam.rayFromScreen(sx, sy, Std.int(w), Std.int(h));
		if (Math.abs(ray.lz) < 1e-6) return null;
		var t = (z - ray.pz) / ray.lz;
		if (t < 0) return null;
		return new h3d.Vector(ray.px + ray.lx * t, ray.py + ray.ly * t, z);
	}

	/** The four ground corners of the current view (for the minimap). **/
	public function viewFootprint(w:Float, h:Float):Array<h3d.Vector> {
		var out = [];
		for (c in [[0.0, 0.0], [w, 0.0], [w, h], [0.0, h]]) {
			var p = screenToPlane(c[0], c[1], w, h, 0);
			if (p != null) out.push(p);
		}
		return out;
	}

	function clamp() {
		if (targetX < -bounds) targetX = -bounds;
		if (targetX > bounds) targetX = bounds;
		if (targetY < -bounds) targetY = -bounds;
		if (targetY > bounds) targetY = bounds;
	}

	public function apply() {
		var horiz = Math.cos(pitch) * curDist;
		cam.target.set(curX, curY, 0);
		cam.pos.set(curX + Math.cos(curYaw) * horiz, curY + Math.sin(curYaw) * horiz, Math.sin(pitch) * curDist);
		cam.up.set(0, 0, 1);
		cam.update();
	}
}
