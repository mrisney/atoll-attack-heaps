package input;

/**
	Classic RTS camera: orbit a ground target at a fixed pitch.
	Keyboard/edge pan + wheel zoom on desktop, two-finger pan/pinch on touch
	(driven from SelectionController), Q/E to rotate.
**/
class RtsCamera {
	final cam:h3d.Camera;

	public var targetX = 0.0;
	public var targetY = 0.0;
	public var distance = 48.0;
	public var yaw = -Math.PI * 0.5;
	public var pitch = 0.95; // radians above the horizon

	public var minDistance = 14.0;
	public var maxDistance = 110.0;
	public var bounds = 80.0;
	public var edgeScroll = true;

	public function new(cam:h3d.Camera) {
		this.cam = cam;
		cam.fovY = 32;
		cam.zNear = 1;
		cam.zFar = 600;
		apply();
	}

	public function update(dt:Float, mouseX:Float, mouseY:Float, width:Float, height:Float) {
		var speed = distance * 0.9 * dt;
		var mx = 0.0, my = 0.0;
		if (hxd.Key.isDown(hxd.Key.W) || hxd.Key.isDown(hxd.Key.UP)) my += 1;
		if (hxd.Key.isDown(hxd.Key.S) || hxd.Key.isDown(hxd.Key.DOWN)) my -= 1;
		if (hxd.Key.isDown(hxd.Key.A) || hxd.Key.isDown(hxd.Key.LEFT)) mx -= 1;
		if (hxd.Key.isDown(hxd.Key.D) || hxd.Key.isDown(hxd.Key.RIGHT)) mx += 1;

		if (edgeScroll && width > 0) {
			var edge = 6;
			if (mouseX >= 0 && mouseX < edge) mx -= 1;
			if (mouseX > width - edge && mouseX <= width) mx += 1;
			if (mouseY >= 0 && mouseY < edge) my += 1;
			if (mouseY > height - edge && mouseY <= height) my -= 1;
		}
		panScreen(mx * speed, my * speed);

		if (hxd.Key.isDown(hxd.Key.Q)) yaw -= dt * 1.4;
		if (hxd.Key.isDown(hxd.Key.E)) yaw += dt * 1.4;
		apply();
	}

	/** Pan in screen-aligned directions (right, forward) in world units. **/
	public function panScreen(right:Float, forward:Float) {
		// Forward on the ground = from camera toward target.
		var fx = -Math.cos(yaw), fy = -Math.sin(yaw);
		var rx = fy, ry = -fx; // forward × up
		targetX += rx * right + fx * forward;
		targetY += ry * right + fy * forward;
		if (targetX < -bounds) targetX = -bounds;
		if (targetX > bounds) targetX = bounds;
		if (targetY < -bounds) targetY = -bounds;
		if (targetY > bounds) targetY = bounds;
	}

	public function zoom(factor:Float) {
		distance *= factor;
		if (distance < minDistance) distance = minDistance;
		if (distance > maxDistance) distance = maxDistance;
		apply();
	}

	public function apply() {
		var horiz = Math.cos(pitch) * distance;
		cam.target.set(targetX, targetY, 0);
		cam.pos.set(targetX + Math.cos(yaw) * horiz, targetY + Math.sin(yaw) * horiz, Math.sin(pitch) * distance);
		cam.up.set(0, 0, 1);
		cam.update();
	}
}
