package game;

import game.Unit.UnitKind;
import world.Island;

/**
	Fixed-timestep simulation. Rendering interpolates on top of it; input
	only ever reaches it through `queue()`.
**/
class Sim {
	public static inline var TICK = 1 / 30;
	/**
		Most simulated time one update may catch up (s). Small, so a stalled frame
		doesn't fast-forward the battle; automation raises it (`?catchup=`).
	**/
	public static var maxCatchUp = 0.25;

	public final island:Island;
	public final units:Array<Unit> = [];
	public final ships:Array<Ship> = [];
	/** Each team's natural landing beach (its dock), by team. **/
	public final homeBeach:Array<{x:Float, y:Float}> = [];

	/**
		One ship's band: 14 plain characters (the concept is 12-20 per ship, no
		resource gathering or base building, just a small crew and the flag).
	**/
	public static final CREW:Array<UnitKind> = [
		Captain, Swordsman, Swordsman, Swordsman, Swordsman, Swordsman, Piker, Piker, Piker, Piker, Archer, Archer, Archer, Archer
	];
	public var tick(default, null) = 0;

	var pending:Array<Command> = [];
	var accumulator = 0.0;
	var nextId = 1;

	public function new(island:Island) {
		this.island = island;
		spawnTeam(0, Math.PI * 0.25);
		spawnTeam(1, Math.PI * 1.25);
		// The red side's ship heads straight for its beach. (A real computer
		// opponent comes with combat; for now it just lands.)
		var red = ships[1];
		queue(ShipTo(red.id, homeBeach[1].x, homeBeach[1].y));
	}

	/**
		A team starts at sea: its ship lies off its home beach, out past the
		shallows, with the whole crew aboard.
	**/
	function spawnTeam(team:Int, angle:Float) {
		var beach = island.findLandNear(angle);
		homeBeach.push(beach);
		// Out from the beach along the bearing until the water is properly deep, then a
		// bit further, staying inside the map.
		var dx = Math.cos(angle), dy = Math.sin(angle);
		var d = 0.0;
		var limit = island.halfExtent * 0.92;
		var r0 = Math.sqrt(beach.x * beach.x + beach.y * beach.y);
		while (r0 + d < limit && island.heightAt(beach.x + dx * d, beach.y + dy * d) > -2.0)
			d += 1;
		d = Math.min(d + 10, limit - r0);
		var ship = new Ship(nextId++, team, beach.x + dx * d, beach.y + dy * d, angle + Math.PI);
		ships.push(ship);
		for (kind in CREW) {
			var u = new Unit(nextId++, team, kind, ship.x, ship.y);
			u.aboard = ship.id;
			u.z = 0;
			units.push(u);
			ship.crew.push(u.id);
		}
	}

	public function getShip(id:Int):Null<Ship> {
		for (s in ships)
			if (s.id == id) return s;
		return null;
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
		accumulator += Math.min(dt, maxCatchUp);
		while (accumulator >= TICK) {
			step();
			accumulator -= TICK;
		}
	}

	function step() {
		for (c in pending) apply(c);
		pending = [];

		stepShips();

		for (u in units) {
			if (!u.alive || !u.hasTarget || u.aboard >= 0) continue;
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
		for (u in units)
			if (u.alive && u.aboard < 0) u.z = island.heightAt(u.x, u.y);
		tick++;
	}

	/** Cheap O(n²) push-apart so units don't stack. Fine for dozens of units. **/
	function separate() {
		var minDist = 1.15;
		for (i in 0...units.length)
			for (j in i + 1...units.length) {
				var a = units[i], b = units[j];
				if (!a.alive || !b.alive || a.aboard >= 0 || b.aboard >= 0) continue;
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
					if (u == null || !u.alive || u.aboard >= 0) continue;
					var o = formationOffset(k++, 1.25);
					u.tx = x + o.x;
					u.ty = y + o.y;
					u.hasTarget = true;
				}
			case Kill(ids, fx, fy):
				for (id in ids) {
					var u = getUnit(id);
					if (u == null || !u.alive) continue;
					u.alive = false;
					u.hasTarget = false;
					u.hitFromX = fx;
					u.hitFromY = fy;
				}
			case ShipTo(id, x, y):
				var s = getShip(id);
				if (s != null) orderShip(s, x, y);
			case Stop(ids):
				for (id in ids) {
					var u = getUnit(id);
					if (u != null) u.hasTarget = false;
				}
		}
	}

	// --- ships -------------------------------------------------------------

	function deep(x:Float, y:Float):Bool
		return island.heightAt(x, y) < Ship.DRAFT;

	/**
		Point a ship somewhere. On land: find the anchorage (the nearest deep
		water to that spot), the shore point between them where the crew wades
		out, and send the crew a little inland from there. At sea: just go.
	**/
	function orderShip(s:Ship, x:Float, y:Float) {
		if (s.crew.length == 0 && s.state == Landing) return;
		if (deep(x, y)) {
			s.tx = x;
			s.ty = y;
			s.state = Sailing;
			s.landOnArrival = false;
			return;
		}
		// Nearest deep water around the spot: rings outward, 24 bearings each.
		var best:Null<{x:Float, y:Float}> = null;
		var r = 2.0;
		while (best == null && r < 40) {
			var bestD = 1e9;
			for (k in 0...24) {
				var a = k / 24 * Math.PI * 2;
				var ax = x + Math.cos(a) * r, ay = y + Math.sin(a) * r;
				// Leave room for the hull: the water around it must be deep too.
				if (!deep(ax, ay) || !deep(ax + Math.cos(a) * 2, ay + Math.sin(a) * 2)) continue;
				var d = (ax - s.x) * (ax - s.x) + (ay - s.y) * (ay - s.y);
				if (d < bestD) {
					bestD = d;
					best = {x: ax, y: ay};
				}
			}
			r += 1.5;
		}
		if (best == null) return;
		// The shore: walk from the anchorage toward the spot until there's dry land.
		var dx = x - best.x, dy = y - best.y;
		var len = Math.max(Math.sqrt(dx * dx + dy * dy), 1e-4);
		var sx = x, sy = y;
		var t = 0.0;
		while (t <= len) {
			var px = best.x + dx / len * t, py = best.y + dy / len * t;
			if (island.isWalkable(px, py)) {
				sx = px;
				sy = py;
				break;
			}
			t += 0.25;
		}
		s.tx = best.x;
		s.ty = best.y;
		s.shoreX = sx;
		s.shoreY = sy;
		// Gather a few metres inland of the shore (or at the clicked spot if it's further).
		var inland = Math.max(len - t, 4.0);
		var ix = sx + dx / len * inland, iy = sy + dy / len * inland;
		if (!island.isWalkable(ix, iy)) {
			ix = sx;
			iy = sy;
		}
		s.inlandX = ix;
		s.inlandY = iy;
		s.state = Sailing;
		s.landOnArrival = true;
	}

	function stepShips() {
		for (s in ships) {
			switch s.state {
				case Idle:
					s.speed = 0;
				case Sailing:
					sail(s);
				case Landing:
					s.speed = 0;
					disembark(s);
			}
			// Crew aboard ride along.
			for (id in s.crew) {
				var u = getUnit(id);
				if (u != null) {
					u.x = s.x;
					u.y = s.y;
				}
			}
		}
	}

	/**
		Steer toward the target through deep water: try headings fanning out from
		the direct one and take the closest that keeps a few hull-lengths of deep
		water ahead. Ease off near the target.
	**/
	function sail(s:Ship) {
		var dx = s.tx - s.x, dy = s.ty - s.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist < 1.2) {
			s.speed = 0;
			if (s.landOnArrival && s.crew.length > 0) {
				s.landOnArrival = false;
				s.state = Landing;
				s.disembarkTimer = 0;
				s.landed = 0;
			} else
				s.state = Idle;
			return;
		}
		var want = Math.atan2(dy, dx);
		var chosen:Null<Float> = null;
		for (k in 0...13) {
			// 0, +15°, -15°, +30°, -30°, ...
			var off = (k + 1 >> 1) * (k % 2 == 1 ? 1 : -1) * Math.PI / 12;
			var h = want + off;
			var ok = true;
			var look = Math.min(dist, 9.0);
			var step = 1.5;
			var t = step;
			while (t <= look) {
				if (!deep(s.x + Math.cos(h) * t, s.y + Math.sin(h) * t)) {
					ok = false;
					break;
				}
				t += step;
			}
			if (ok) {
				chosen = h;
				break;
			}
		}
		if (chosen == null) {
			// Boxed in: stop rather than run aground.
			s.speed = 0;
			s.state = Idle;
			s.landOnArrival = false;
			return;
		}
		// Turn toward the chosen heading at a limited rate.
		var diff = chosen - s.heading;
		while (diff > Math.PI) diff -= Math.PI * 2;
		while (diff < -Math.PI) diff += Math.PI * 2;
		var maxTurn = Ship.TURN * TICK;
		s.heading += clamp(diff, -maxTurn, maxTurn);
		// Slow down for sharp turns and on the approach.
		var target = Ship.MAX_SPEED * clamp(dist / 8, 0.25, 1) * (1 - Math.min(Math.abs(diff), 1.2) * 0.5);
		s.speed += clamp(target - s.speed, -2.5 * TICK, 1.2 * TICK);
		var nx = s.x + Math.cos(s.heading) * s.speed * TICK;
		var ny = s.y + Math.sin(s.heading) * s.speed * TICK;
		if (deep(nx, ny)) {
			s.x = nx;
			s.y = ny;
		} else
			s.speed = 0;
	}

	/** Anchored: crew members wade ashore one at a time and head inland. **/
	function disembark(s:Ship) {
		s.disembarkTimer -= TICK;
		if (s.disembarkTimer > 0 || s.crew.length == 0) {
			if (s.crew.length == 0) s.state = Idle;
			return;
		}
		s.disembarkTimer = Ship.DISEMBARK_INTERVAL;
		var u = getUnit(s.crew.shift());
		if (u == null) return;
		var k = s.landed++;
		// Spread along the waterline a little, then gather in formation inland.
		var o = formationOffset(k % 5, 0.8);
		var x = s.shoreX + o.x, y = s.shoreY + o.y;
		if (!island.isWalkable(x, y)) {
			x = s.shoreX;
			y = s.shoreY;
		}
		u.aboard = -1;
		u.x = x;
		u.y = y;
		u.z = island.heightAt(x, y);
		var g = formationOffset(k, 1.25);
		u.tx = s.inlandX + g.x;
		u.ty = s.inlandY + g.y;
		u.hasTarget = true;
		u.facing = Math.atan2(s.inlandY - s.shoreY, s.inlandX - s.shoreX);
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
