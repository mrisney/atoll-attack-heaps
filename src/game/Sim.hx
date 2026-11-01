package game;

import game.Unit.UnitKind;
import world.Island;

/**
	Fixed-timestep simulation. Rendering interpolates on top of it; input
	only ever reaches it through `queue()`.
**/
class Sim {
	public static inline var TICK = 1 / 30;

	public final island:Island;
	public final units:Array<Unit> = [];
	public var tick(default, null) = 0;

	var pending:Array<Command> = [];
	var accumulator = 0.0;
	var nextId = 1;

	public function new(island:Island) {
		this.island = island;
		spawnTeam(0, Math.PI * 0.25);
		spawnTeam(1, Math.PI * 1.25);
	}

	function spawnTeam(team:Int, angle:Float) {
		var base = island.findLandNear(angle);
		var kinds = [Captain, Swordsman, Swordsman, Swordsman, Archer, Archer, Archer];
		for (k in 0...kinds.length) {
			var o = formationOffset(k, 1.3);
			var x = base.x + o.x, y = base.y + o.y;
			if (!island.isWalkable(x, y)) {
				x = base.x;
				y = base.y;
			}
			var u = new Unit(nextId++, team, kinds[k], x, y);
			u.z = island.heightAt(x, y);
			units.push(u);
		}
	}

	public function queue(cmd:Command) {
		pending.push(cmd);
	}

	public function getUnit(id:Int):Null<Unit> {
		for (u in units)
			if (u.id == id) return u;
		return null;
	}

	/** Advance by real time; runs as many fixed ticks as needed. **/
	public function update(dt:Float) {
		accumulator += Math.min(dt, 0.25);
		while (accumulator >= TICK) {
			step();
			accumulator -= TICK;
		}
	}

	function step() {
		for (c in pending) apply(c);
		pending = [];

		for (u in units) {
			if (!u.hasTarget) continue;
			var dx = u.tx - u.x, dy = u.ty - u.y;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < 0.15) {
				u.hasTarget = false;
				continue;
			}
			var stepLen = Math.min(dist, u.baseSpeed * TICK);
			var nx = u.x + dx / dist * stepLen;
			var ny = u.y + dy / dist * stepLen;

			// Uphill is slower, downhill a little faster — elevation matters.
			var dh = island.heightAt(nx, ny) - island.heightAt(u.x, u.y);
			var slope = clamp(1 - (dh / stepLen) * 0.5, 0.35, 1.25);
			nx = u.x + dx / dist * stepLen * slope;
			ny = u.y + dy / dist * stepLen * slope;

			if (!island.isWalkable(nx, ny)) {
				// Land units stop at the shoreline.
				u.hasTarget = false;
				continue;
			}
			u.facing = Math.atan2(dy, dx);
			u.x = nx;
			u.y = ny;
		}

		separate();
		for (u in units) u.z = island.heightAt(u.x, u.y);
		tick++;
	}

	/** Cheap O(n²) push-apart so units don't stack. Fine for dozens of units. **/
	function separate() {
		var minDist = 1.15;
		for (i in 0...units.length)
			for (j in i + 1...units.length) {
				var a = units[i], b = units[j];
				var dx = b.x - a.x, dy = b.y - a.y;
				var d2 = dx * dx + dy * dy;
				if (d2 >= minDist * minDist || d2 < 1e-6) continue;
				var d = Math.sqrt(d2);
				var push = (minDist - d) * 0.5;
				var px = dx / d * push, py = dy / d * push;
				if (island.isWalkable(a.x - px, a.y - py)) {
					a.x -= px;
					a.y -= py;
				}
				if (island.isWalkable(b.x + px, b.y + py)) {
					b.x += px;
					b.y += py;
				}
			}
	}

	function apply(c:Command) {
		switch c {
			case Move(ids, x, y):
				var k = 0;
				for (id in ids) {
					var u = getUnit(id);
					if (u == null) continue;
					var o = formationOffset(k++, 1.25);
					u.tx = x + o.x;
					u.ty = y + o.y;
					u.hasTarget = true;
				}
			case Stop(ids):
				for (id in ids) {
					var u = getUnit(id);
					if (u != null) u.hasTarget = false;
				}
		}
	}

	/** Sunflower spiral — compact, even spacing for any group size. **/
	static function formationOffset(k:Int, spacing:Float):{x:Float, y:Float} {
		if (k == 0) return {x: 0, y: 0};
		var r = Math.sqrt(k) * spacing;
		var a = k * 2.39996323;
		return {x: Math.cos(a) * r, y: Math.sin(a) * r};
	}

	static inline function clamp(v:Float, lo:Float, hi:Float):Float
		return v < lo ? lo : (v > hi ? hi : v);
}
