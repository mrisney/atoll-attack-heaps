package render;

/**
	Ambient sailboats: a few white-sail dinghies (WildCurrent's 12-heading
	sprite set) sailing slow loops offshore. Purely decorative, render-side
	only, so they never touch the sim.

	Each boat shows the frame closest to its heading. The sprites are drawn
	top-down with heading 0 = image-up, clockwise. They lie flat on the water
	with a gentle bob and roll, like the canopies.
**/
class Boats extends h3d.scene.Object {
	static inline var FRAMES = 12;
	static inline var SIZE = 7.5;

	final boats:Array<Boat> = [];
	var time = 0.0;

	public function new(island:world.Island, ?parent:h3d.scene.Object) {
		super(parent);
		var n = new world.Noise(island.seed + 1201);
		var he = island.halfExtent;
		var count = 3 + Std.int(n.rand(1, 1) * 2);
		for (k in 0...count) {
			// A loop in open water: well outside the coast, inside the map.
			var radius = he * (0.88 + n.rand(k, 2) * 0.14);
			var b = new Boat(this, radius, n.rand(k, 3) * Math.PI * 2, (0.018 + n.rand(k, 4) * 0.012) * (n.rand(k, 5) < 0.5 ? -1 : 1),
				n.rand(k, 6) * 10);
			// Skip loops that would cross land.
			var ok = true;
			for (s in 0...24) {
				var a = s / 24 * Math.PI * 2;
				if (island.heightAt(Math.cos(a) * radius, Math.sin(a) * radius) > -0.8) {
					ok = false;
					break;
				}
			}
			if (ok) boats.push(b) else b.remove();
		}
	}

	public function update(dt:Float) {
		time += dt;
		for (b in boats) b.step(dt, time);
	}
}

private class Boat extends h3d.scene.Object {
	/** One holder per heading frame; only the current one is visible. **/
	final frames:Array<h3d.scene.Object> = [];
	final radius:Float;
	var angle:Float;
	final speed:Float; // radians per second around the loop (sign = direction)
	final bobPhase:Float;
	var shown = -1;

	public function new(parent:h3d.scene.Object, radius:Float, angle:Float, speed:Float, bobPhase:Float) {
		super(parent);
		this.radius = radius;
		this.angle = angle;
		this.speed = speed;
		this.bobPhase = bobPhase;
		for (f in 0...12) {
			var path = "boats/dinghy-" + StringTools.lpad(Std.string(f * 30), "0", 3) + ".png";
			var sp = new SpriteProps();
			sp.add(path, 0, 0, 0, 7.5, 0.0, 0.0);
			var holder = new h3d.scene.Object(this);
			sp.build(holder, true);
			holder.visible = false;
			frames.push(holder);
		}
		step(0, 0);
	}

	public function step(dt:Float, t:Float) {
		angle += speed * dt;
		var x = Math.cos(angle) * radius, y = Math.sin(angle) * radius;
		// Tangent of the loop = direction of travel.
		var dirX = -Math.sin(angle) * (speed > 0 ? 1 : -1), dirY = Math.cos(angle) * (speed > 0 ? 1 : -1);
		var worldAngle = Math.atan2(dirY, dirX); // CCW from +X
		var compass = 90 - worldAngle * 180 / Math.PI; // clockwise from +Y (image-up)
		var f = Std.int(Math.round(compass / 30)) % 12;
		if (f < 0) f += 12;
		if (f != shown) {
			if (shown >= 0) frames[shown].visible = false;
			frames[f].visible = true;
			shown = f;
		}
		setPosition(x, y, 0.16 + Math.sin(t * 1.4 + bobPhase) * 0.05);
		setRotation(Math.sin(t * 1.1 + bobPhase) * 0.03, Math.cos(t * 0.9 + bobPhase) * 0.03, 0);
	}
}
