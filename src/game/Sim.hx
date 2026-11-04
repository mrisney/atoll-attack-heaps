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
	public final nav:world.NavGrid;
	public final units:Array<Unit> = [];
	public final ships:Array<Ship> = [];
	/** Arrows in flight. **/
	public final arrows:Array<Arrow> = [];
	/** -1 while the battle is on; then the winning team. **/
	public var winner(default, null) = -1;
	/** Whose flag stands on the summit (-1 = none, the neutral banner). **/
	public var flagTeam(default, null) = -1;
	/** How long it has stood (s); it wins at Rules.FLAG_HOLD_TIME. **/
	public var flagHeld(default, null) = 0.0;
	/** The tick the first flag was planted (-1 = not yet): for determinism checks. **/
	public var firstFlagTick(default, null) = -1;
	/** The tick the match was decided (for replays and determinism checks). **/
	public var winTick(default, null) = -1;
	/** "flag", "captain" or "eliminated". **/
	public var winReason(default, null) = "";
	/** Computer commanders (red by default; add one for blue to watch AI vs AI). **/
	public final teamAIs:Array<TeamAI> = [];
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
		nav = new world.NavGrid(island);
		spawnTeam(0, Math.PI * 0.25);
		spawnTeam(1, Math.PI * 1.25);
		// The red side's ship heads straight for its beach. (A real computer
		// opponent comes with combat; for now it just lands.)
		var red = ships[1];
		queue(ShipTo(red.id, homeBeach[1].x, homeBeach[1].y));
		teamAIs.push(new TeamAI(this, 1));
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
		// Just past the shallows: deep enough to sail, close enough to be seen from the
		// beach at the starting zoom (it used to sit in the map corner, off screen).
		while (r0 + d < limit && island.heightAt(beach.x + dx * d, beach.y + dy * d) > Ship.DRAFT - 0.6)
			d += 0.5;
		d = Math.min(d + 4, limit - r0);
		var ship = new Ship(nextId++, team, beach.x + dx * d, beach.y + dy * d, angle + Math.PI);
		ships.push(ship);
		var captainId = -1;
		for (kind in CREW) {
			var u = new Unit(nextId++, team, kind, ship.x, ship.y);
			u.aboard = ship.id;
			u.z = 0;
			units.push(u);
			if (kind == Captain && Directives.current.captainLandsLast) captainId = u.id else ship.crew.push(u.id);
		}
		// The captain comes ashore last, once his band holds the beach.
		if (captainId >= 0) ship.crew.push(captainId);
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
	public function update(dt:Float, stopAtTick = -1) {
		accumulator += Math.min(dt, maxCatchUp);
		while (accumulator >= TICK) {
			// Hold at an exact tick (automation: a snapshot of that moment).
			if (stopAtTick >= 0 && tick >= stopAtTick) {
				accumulator = 0;
				break;
			}
			step();
			accumulator -= TICK;
		}
	}

	function step() {
		for (c in pending) apply(c);
		pending = [];

		stepShips();
		if (winner < 0) {
			if (tick % 30 == 0) for (ai in teamAIs) ai.update();
			// Alternate the order each tick: units listed first would otherwise always
			// strike first (blue's crew is spawned first, and won almost every test).
			var n = units.length;
			for (k in 0...n) {
				var u = units[tick % 2 == 0 ? k : n - 1 - k];
				if (u.alive && u.aboard < 0) think(u);
			}
		}

		for (u in units) {
			if (!u.alive || !u.hasTarget || u.aboard >= 0) continue;
			var fx = u.tx - u.x, fy = u.ty - u.y;
			if (fx * fx + fy * fy < 0.15 * 0.15) {
				u.hasTarget = false;
				u.path = null;
				continue;
			}
			// Head for the goal, or the next waypoint around the water.
			var w = steer(u);
			if (w == null) {
				// No way there on foot.
				u.hasTarget = false;
				continue;
			}
			var dx = w.x - u.x, dy = w.y - u.y;
			var dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1e-4);
			var stepLen = Math.min(dist, Math.min(u.baseSpeed, u.speedCap) * TICK);
			var nx = u.x + dx / dist * stepLen;
			var ny = u.y + dy / dist * stepLen;

			// Uphill is slower, downhill a little faster — elevation matters.
			var dh = island.heightAt(nx, ny) - island.heightAt(u.x, u.y);
			var slope = clamp(1 - (dh / stepLen) * 0.5, 0.35, 1.25);
			nx = u.x + dx / dist * stepLen * slope;
			ny = u.y + dy / dist * stepLen * slope;

			if (!island.isWalkable(nx, ny)) {
				// Clipped the shoreline: slide along it (try steps turned up to 90° either
				// way). A unit wedged on a spit, with water straight ahead, used to re-plan
				// the same route every tick and never move.
				var len = Math.sqrt((nx - u.x) * (nx - u.x) + (ny - u.y) * (ny - u.y));
				var base = Math.atan2(ny - u.y, nx - u.x);
				var slid = false;
				for (k in 1...7) {
					var a = base + (k % 2 == 1 ? 1 : -1) * Std.int((k + 1) / 2) * Math.PI / 6;
					var sx = u.x + Math.cos(a) * len, sy = u.y + Math.sin(a) * len;
					if (island.isWalkable(sx, sy)) {
						nx = sx;
						ny = sy;
						slid = true;
						break;
					}
				}
				if (!slid) {
					// Truly boxed in: find a way round next tick.
					u.path = null;
					u.pathTick = -1000;
					u.pathGoalX = 1e9;
					continue;
				}
			}
			u.facing = Math.atan2(dy, dx);
			u.x = nx;
			u.y = ny;
		}

		stepArrows();
		checkMarches();
		separate();
		for (u in units)
			if (u.alive && u.aboard < 0) u.z = island.heightAt(u.x, u.y);
		if (winner < 0) {
			if (flagTeam >= 0) {
				flagHeld += TICK;
				if (flagHeld >= Rules.FLAG_HOLD_TIME) win(flagTeam, "flag");
			}
			checkVictory();
		}
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
				// Twisted ~35° so two units walking into each other slide past instead of
				// freezing face to face (a straight push exactly cancels their steps; a
				// captain and two pikers stayed gridlocked for a minute in a test).
				var nx = dx / d, ny = dy / d;
				var px = (nx * 0.82 - ny * 0.57) * push, py = (nx * 0.57 + ny * 0.82) * push;
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
				// A plain move: walk there whatever happens, then hold there.
				var k = 0;
				for (id in ids) {
					var u = getUnit(id);
					if (u == null || !u.alive || u.aboard >= 0) continue;
					var o = formationOffset(k++, 1.25);
					u.tx = x + o.x;
					u.ty = y + o.y;
					u.hasTarget = true;
					u.ordered = true;
					endMarch(u);
					u.targetId = -1;
					u.forcedTarget = false;
					u.guardX = u.tx;
					u.guardY = u.ty;
				}
			case AttackMove(ids, x, y):
				// Head there, but the unit AI fights whatever it meets (see think()).
				var k = 0;
				for (id in ids) {
					var u = getUnit(id);
					if (u == null || !u.alive || u.aboard >= 0) continue;
					var o = formationOffset(k++, 1.6);
					u.guardX = x + o.x;
					u.guardY = y + o.y;
					u.ordered = false;
					endMarch(u);
				}
			case Attack(ids, target):
				var t = getUnit(target);
				if (t == null || !t.alive) return;
				for (id in ids) {
					var u = getUnit(id);
					if (u == null || !u.alive || u.aboard >= 0 || u.team == t.team) continue;
					u.targetId = target;
					u.forcedTarget = true;
					u.ordered = false;
					endMarch(u);
				}
			case Kill(ids, fx, fy):
				for (id in ids) {
					var u = getUnit(id);
					if (u == null || !u.alive) continue;
					kill(u, fx, fy);
				}
			case ShipTo(id, x, y):
				var s = getShip(id);
				if (s != null) orderShip(s, x, y);
			case Stop(ids):
				for (id in ids) {
					var u = getUnit(id);
					if (u == null) continue;
					endMarch(u);
					u.hasTarget = false;
					u.ordered = false;
					u.targetId = -1;
					u.forcedTarget = false;
					u.guardX = u.x;
					u.guardY = u.y;
				}
		}
	}

	// --- the march: a flock heading for the summit ------------------------------

	/** Each team's march path (waypoints x0, y0, ...) from its landing to the summit. **/
	public final marchPath:Array<Null<Array<Float>>> = [null, null];

	/**
		The last of the crew (the captain) is wading ashore: everyone of this
		team ashore and not already busy with an order sets off for the summit.
	**/
	function startMarch(s:Ship, last:Unit) {
		var path = nav.find(s.inlandX, s.inlandY, island.apexX, island.apexY);
		if (path == null) path = [island.apexX, island.apexY];
		marchPath[s.team] = path;
		// The band keeps to its slowest member.
		var slowest = 1e9;
		for (u in units)
			if (u.team == s.team && u.alive) slowest = Math.min(slowest, u.baseSpeed);
		for (u in units)
			if (u.team == s.team && u.alive && !u.ordered && !u.forcedTarget) {
				u.marching = true;
				u.marchIdx = 0;
				u.speedCap = slowest;
				// Start heading inland (deterministic: from the unit's id, not a random angle).
				var a = Math.atan2(s.inlandY - s.shoreY, s.inlandX - s.shoreX) + ((u.id * 37) % 11 - 5) * 0.06;
				u.vx = Math.cos(a) * slowest * 0.5;
				u.vy = Math.sin(a) * slowest * 0.5;
			}
		last.marching = Directives.current.marchOnLanding;
	}

	function endMarch(u:Unit) {
		if (!u.marching) return;
		u.marching = false;
		u.speedCap = 1e9;
		u.vx = u.vy = 0;
	}

	/**
		One marcher, one tick: Reynolds' boids (separation, alignment, cohesion
		among marching teammates within `perception`) plus a pull toward the next
		waypoint of the march path. The captain is pulled instead toward a point
		`standBack` metres behind the band's centre, on the side away from the
		summit. The result sets a short-range walking goal, so the ordinary mover
		(slopes, shorelines) still does the stepping. Weights: directives.json
		"march".
	**/
	function flockStep(u:Unit) {
		var d = Directives.current;
		var w = d.flockWeights;
		var speed = Math.min(u.baseSpeed, u.speedCap);
		// Neighbours.
		var sx = 0.0, sy = 0.0, ax = 0.0, ay = 0.0, cx = 0.0, cy = 0.0, n = 0;
		var bx = 0.0, by = 0.0, bandN = 0;
		for (o in units) {
			if (o == u || !o.alive || o.aboard >= 0 || o.team != u.team || !o.marching) continue;
			if (o.kind != Captain) {
				bx += o.x;
				by += o.y;
				bandN++;
			}
			var dx = u.x - o.x, dy = u.y - o.y;
			var dd = Math.sqrt(dx * dx + dy * dy);
			if (dd >= d.flockPerception || dd < 1e-4) continue;
			if (dd < d.flockSeparation) {
				// Push apart, harder the closer they are.
				sx += dx / dd / dd;
				sy += dy / dd / dd;
			}
			ax += o.vx;
			ay += o.vy;
			cx += o.x;
			cy += o.y;
			n++;
		}
		// Goal.
		var gx = 0.0, gy = 0.0;
		if (u.kind == Captain && nearestEnemy(u, d.marchCaptainHalt, false) != null) {
			// Enemies close: he halts and holds (the band fights on; evade() takes over).
			endMarch(u);
			u.guardX = u.x;
			u.guardY = u.y;
			u.hasTarget = false;
			return;
		}
		if (u.kind == Captain) {
			if (bandN == 0) {
				// No band left marching: he stops where he is.
				endMarch(u);
				u.guardX = u.x;
				u.guardY = u.y;
				return;
			}
			bx /= bandN;
			by /= bandN;
			var ox = bx - island.apexX, oy = by - island.apexY;
			var ol = Math.max(Math.sqrt(ox * ox + oy * oy), 0.01);
			var px = bx + ox / ol * d.marchCaptainBack, py = by + oy / ol * d.marchCaptainBack;
			if (!island.isWalkable(px, py) || !nav.clearLine(u.x, u.y, px, py)) {
				px = bx;
				py = by;
			}
			gx = px - u.x;
			gy = py - u.y;
			// Ease in: no need to rush when he's already in his place.
			var gl = Math.sqrt(gx * gx + gy * gy);
			if (gl < 1.2) {
				gx *= gl / 1.2;
				gy *= gl / 1.2;
			}
		} else {
			var path = marchPath[u.team];
			if (path == null) path = [island.apexX, island.apexY];
			var last = Std.int(path.length / 2) - 1;
			if (u.marchIdx > last) u.marchIdx = last;
			var wx = path[u.marchIdx * 2], wy = path[u.marchIdx * 2 + 1];
			if (u.marchIdx < last && (wx - u.x) * (wx - u.x) + (wy - u.y) * (wy - u.y) < 3 * 3) {
				u.marchIdx++;
				wx = path[u.marchIdx * 2];
				wy = path[u.marchIdx * 2 + 1];
			}
			// Drifted so the straight line to the waypoint crosses water: walk the
			// ordinary path round it this tick (two marchers froze on an inlet).
			if (!nav.clearLine(u.x, u.y, wx, wy)) {
				u.tx = wx;
				u.ty = wy;
				u.hasTarget = true;
				u.vx = unitX(wx - u.x, wy - u.y) * speed;
				u.vy = unitY(wx - u.x, wy - u.y) * speed;
				return;
			}
			gx = wx - u.x;
			gy = wy - u.y;
		}
		var fx = unitX(gx, gy) * w.goal, fy = unitY(gx, gy) * w.goal;
		if (u.kind == Captain) {
			var gl = Math.sqrt(gx * gx + gy * gy);
			var ease = Math.min(1, gl / 1.2);
			fx *= ease;
			fy *= ease;
		}
		fx += unitX(sx, sy) * w.separation;
		fy += unitY(sx, sy) * w.separation;
		if (n > 0) {
			fx += unitX(ax, ay) * w.alignment;
			fy += unitY(ax, ay) * w.alignment;
			fx += unitX(cx / n - u.x, cy / n - u.y) * w.cohesion;
			fy += unitY(cx / n - u.x, cy / n - u.y) * w.cohesion;
		}
		// Steer: velocity turns toward the combined force, capped at the band's pace.
		var fl = Math.sqrt(fx * fx + fy * fy);
		var want = fl > 1e-4 ? speed * Math.min(1, fl) : 0.0;
		var dvx = (fl > 1e-4 ? fx / fl * want : 0) - u.vx, dvy = (fl > 1e-4 ? fy / fl * want : 0) - u.vy;
		u.vx += dvx * 0.15;
		u.vy += dvy * 0.15;
		var vl = Math.sqrt(u.vx * u.vx + u.vy * u.vy);
		if (vl < 0.05) {
			u.hasTarget = false;
			return;
		}
		u.tx = u.x + u.vx * 0.6;
		u.ty = u.y + u.vy * 0.6;
		u.hasTarget = true;
	}

	static inline function unitX(x:Float, y:Float):Float {
		var l = Math.sqrt(x * x + y * y);
		return l > 1e-6 ? x / l : 0;
	}

	static inline function unitY(x:Float, y:Float):Float {
		var l = Math.sqrt(x * x + y * y);
		return l > 1e-6 ? y / l : 0;
	}

	/** The march ends for a team when its band's centre reaches the summit: they hold there. **/
	function checkMarches() {
		for (team in 0...2) {
			var cx = 0.0, cy = 0.0, n = 0;
			for (u in units)
				if (u.team == team && u.alive && u.marching && u.kind != Captain) {
					cx += u.x;
					cy += u.y;
					n++;
				}
			if (n == 0) continue;
			cx /= n;
			cy /= n;
			var dx = cx - island.apexX, dy = cy - island.apexY;
			if (dx * dx + dy * dy > Directives.current.marchArrive * Directives.current.marchArrive) continue;
			for (u in units)
				if (u.team == team && u.marching) {
					endMarch(u);
					u.guardX = u.x;
					u.guardY = u.y;
					u.hasTarget = false;
				}
		}
	}

	/**
		The point to walk toward this tick: the goal itself when the straight
		line is clear of water, else the next waypoint of an A* path round it
		(NavGrid), found again when the goal moves (or every second while
		chasing). Null if the goal can't be reached on foot.
	**/
	function steer(u:Unit):Null<{x:Float, y:Float}> {
		var moved = Math.abs(u.tx - u.pathGoalX) + Math.abs(u.ty - u.pathGoalY);
		var stale = moved > 2.5 || (moved > 0.3 && tick - u.pathTick > 30);
		if (u.path == null || stale) {
			if (nav.clearLine(u.x, u.y, u.tx, u.ty)) {
				u.path = [];
			} else {
				u.path = nav.find(u.x, u.y, u.tx, u.ty);
				if (u.path == null) return null;
			}
			u.pathGoalX = u.tx;
			u.pathGoalY = u.ty;
			u.pathTick = tick;
		}
		while (u.path.length >= 2) {
			var px = u.path[0], py = u.path[1];
			var dx = px - u.x, dy = py - u.y;
			// Reached a waypoint (the last one is the goal itself).
			if (dx * dx + dy * dy < 0.6 * 0.6 && u.path.length > 2) {
				u.path.shift();
				u.path.shift();
				continue;
			}
			return {x: px, y: py};
		}
		return {x: u.tx, y: u.ty};
	}

	// --- unit AI and combat ---------------------------------------------------

	/**
		Each character's own little mind, every tick. Player orders win: a plain
		move ignores enemies until it arrives; an attack order chases its target
		anywhere. Otherwise the unit holds its rally point (guard), takes on
		enemies that come within its aggro range, and lets them go past the
		leash. Archers shoot from range and step back from melee. The captain
		only defends himself, and raises the flag when he stands at the apex.
	**/
	function think(u:Unit) {
		if (u.cooldown > 0) u.cooldown--;
		if (u.kind == Captain) workFlag(u);
		if (u.ordered) {
			if (u.hasTarget) return;
			// Arrived: hold here.
			u.ordered = false;
			u.guardX = u.x;
			u.guardY = u.y;
		}
		var s = Rules.stats(u.kind);
		if (u.kind == Captain && evade(u)) return;
		var t = u.targetId >= 0 ? getUnit(u.targetId) : null;
		// First duty: protect the captain. An enemy near him outranks whatever else this
		// unit was doing (only a player's attack order comes first).
		if (u.kind != Captain && !u.forcedTarget) {
			var threat = captainThreat(u);
			if (threat != null) t = threat;
		}
		if (t != null && (!t.alive || t.aboard >= 0 || (!u.forcedTarget && dist(u, t) > Rules.LEASH))) {
			t = null;
			u.forcedTarget = false;
		}
		// Look around now and then (staggered, so units don't all think at once).
		if (!u.forcedTarget && (t == null || (tick + u.id) % 10 == 0)) {
			var n = acquire(u, s.aggro);
			if (n != null) t = n;
		}
		// Captains duel: one near the other blocks his flag work, and captains otherwise
		// avoid fights, so two lone captains at the summit stood off forever.
		if (u.kind == Captain && t == null) {
			var rival = captainOf(1 - u.team);
			if (rival != null && dist(u, rival) < Rules.FLAG_CONTEST + 2) t = rival;
		}
		u.targetId = t == null ? -1 : t.id;
		if (t == null && u.marching) {
			flockStep(u);
			return;
		}
		if (t == null) {
			// Nothing to fight: go back to (or stay at) the rally point.
			var gx = u.guardX - u.x, gy = u.guardY - u.y;
			if (gx * gx + gy * gy > 0.6 * 0.6) {
				u.tx = u.guardX;
				u.ty = u.guardY;
				u.hasTarget = true;
			}
			return;
		}
		var d = dist(u, t);
		if (u.kind == Archer) {
			// Keep away from blades and pikes: step back if one is close.
			var threat = nearestEnemy(u, Rules.ARCHER_KITE, true);
			if (threat != null) {
				var td = Math.max(dist(u, threat), 0.01);
				var ax = u.x + (u.x - threat.x) / td * 3, ay = u.y + (u.y - threat.y) / td * 3;
				if (island.isWalkable(ax, ay)) {
					u.tx = ax;
					u.ty = ay;
					u.hasTarget = true;
					return;
				}
			}
		}
		if (d <= s.reach + 0.2) {
			u.hasTarget = false;
			u.facing = Math.atan2(t.y - u.y, t.x - u.x);
			strike(u, t, d);
		} else {
			u.tx = t.x;
			u.ty = t.y;
			u.hasTarget = true;
		}
	}

	function strike(u:Unit, t:Unit, d:Float) {
		if (u.cooldown > 0) return;
		u.cooldown = Math.round(Rules.stats(u.kind).cooldown / TICK);
		u.lastAttackTick = tick;
		if (u.kind == Archer && d > 2.5) {
			arrows.push(new Arrow(u, t, Rules.damage(u, t, false), d / Rules.ARROW_SPEED));
		} else
			hurt(t, Rules.damage(u, t, true), u);
	}

	/** Damage a unit; it fights back if it was minding its own business. **/
	function hurt(t:Unit, amount:Float, from:Unit) {
		if (!t.alive) return;
		t.hp -= amount;
		t.lastHitBy = from.id;
		if (t.hp <= 0) {
			kill(t, from.x, from.y);
			return;
		}
		if (t.targetId < 0 && !t.ordered && from.alive && dist(t, from) < Rules.LEASH) t.targetId = from.id;
	}

	function kill(u:Unit, fromX:Float, fromY:Float) {
		u.alive = false;
		u.hp = 0;
		u.hasTarget = false;
		u.hitFromX = fromX;
		u.hitFromY = fromY;
		u.flagProgress = 0;
	}

	/** The best enemy within `radius`: close, hurt, valuable (Rules.targetScore). **/
	function acquire(u:Unit, radius:Float):Null<Unit> {
		var best:Null<Unit> = null;
		var bestScore = -1e9;
		for (e in units) {
			if (!e.alive || e.aboard >= 0 || e.team == u.team) continue;
			var d = dist(u, e);
			if (d > radius) continue;
			var sc = Rules.targetScore(u, e, d);
			if (sc > bestScore) {
				bestScore = sc;
				best = e;
			}
		}
		return best;
	}

	function nearestEnemy(u:Unit, radius:Float, meleeOnly:Bool):Null<Unit> {
		var best:Null<Unit> = null;
		var bd = radius;
		for (e in units) {
			if (!e.alive || e.aboard >= 0 || e.team == u.team) continue;
			if (meleeOnly && e.kind == Archer) continue;
			var d = dist(u, e);
			if (d < bd) {
				bd = d;
				best = e;
			}
		}
		return best;
	}

	/** Each team's captain, alive and ashore (cached per tick). **/
	var captainCache:Array<Null<Unit>> = [null, null];
	var captainCacheTick = -1;

	function captainOf(team:Int):Null<Unit> {
		if (captainCacheTick != tick) {
			captainCacheTick = tick;
			captainCache = [null, null];
			for (c in units)
				if (c.kind == Captain && c.alive && c.aboard < 0) captainCache[c.team] = c;
		}
		return captainCache[team];
	}

	/**
		Bodyguard duty: the enemy closest to this unit's captain, if one is within
		the threat radius and this unit is close enough to answer the call
		(directives.json, "bodyguard").
	**/
	function captainThreat(u:Unit):Null<Unit> {
		var cap = captainOf(u.team);
		if (cap == null) return null;
		var d = Directives.current;
		if (dist(u, cap) > d.guardCallRange) return null;
		var best:Null<Unit> = null;
		var bd = 1e9;
		for (e in units) {
			if (!e.alive || e.aboard >= 0 || e.team == u.team) continue;
			var de = dist(e, cap);
			// Close to him, or aiming at him from range (archers sniped captains every
			// time when only nearby enemies counted).
			var aiming = e.targetId == cap.id && de < d.guardCallRange;
			if ((de < d.guardThreatRadius || aiming) && de < bd) {
				bd = de;
				best = e;
			}
		}
		return best;
	}

	/**
		The captain steps back toward his own band when an enemy fighter gets
		close, unless the player (or the commander) sent him somewhere. Returns
		true if he's stepping away this tick.
	**/
	function evade(u:Unit):Bool {
		var threat = nearestEnemy(u, Directives.current.captainEvade, false);
		// He doesn't run from the other captain (they duel, see think()).
		if (threat != null && threat.kind == Captain) threat = null;
		// Under fire: an archer aiming at him. Pull back behind the band, out of range.
		if (threat == null && Directives.current.captainTakesCover)
			for (e in units)
				if (e.alive && e.aboard < 0 && e.team != u.team && e.targetId == u.id && e.kind == Archer) {
					threat = e;
					break;
				}
		if (threat == null) return false;
		// Toward the middle of his own band, away from the threat.
		var cx = 0.0, cy = 0.0, n = 0;
		for (f in units)
			if (f.team == u.team && f.alive && f.aboard < 0 && f != u) {
				cx += f.x;
				cy += f.y;
				n++;
			}
		var ax = u.x - threat.x, ay = u.y - threat.y;
		var al = Math.max(Math.sqrt(ax * ax + ay * ay), 0.01);
		var mx = ax / al, my = ay / al;
		if (n > 0) {
			// A little toward his band, but mostly away: the band's centre is often the
			// fight itself, and flankers caught him walking into it.
			var bx = cx / n - u.x, by = cy / n - u.y;
			var bl = Math.max(Math.sqrt(bx * bx + by * by), 0.01);
			mx += bx / bl * 0.35;
			my += by / bl * 0.35;
		}
		var ml = Math.max(Math.sqrt(mx * mx + my * my), 0.01);
		var ex = u.x + mx / ml * 3, ey = u.y + my / ml * 3;
		if (!island.isWalkable(ex, ey)) return false;
		u.tx = ex;
		u.ty = ey;
		u.hasTarget = true;
		u.targetId = -1;
		return true;
	}

	/**
		Captain at the summit, standing still: he raises his flag if none stands,
		or lowers the enemy's if theirs does (which resets its clock). Paused
		while an enemy is close (contested). `flagProgress` is the seconds of work
		done; the view shows it as the flag going up or down the pole.
	**/
	function workFlag(u:Unit) {
		var dx = island.apexX - u.x, dy = island.apexY - u.y;
		if (dx * dx + dy * dy > Rules.FLAG_RANGE * Rules.FLAG_RANGE) {
			u.flagProgress = 0;
			return;
		}
		// Not while chasing someone. (He used not to work it while still walking, but
		// with a soldier standing on the exact summit he never "arrived".)
		if (u.targetId >= 0) return;
		for (e in units)
			if (e.alive && e.aboard < 0 && e.team != u.team) {
				var ex = island.apexX - e.x, ey = island.apexY - e.y;
				if (ex * ex + ey * ey < Rules.FLAG_CONTEST * Rules.FLAG_CONTEST) return; // contested
			}
		if (flagTeam == u.team) {
			u.flagProgress = 0;
			return;
		}
		u.flagProgress += TICK;
		if (flagTeam < 0 && u.flagProgress >= Rules.FLAG_TIME) {
			if (firstFlagTick < 0) firstFlagTick = tick;
			flagTeam = u.team;
			flagHeld = 0;
			u.flagProgress = 0;
		} else if (flagTeam >= 0 && u.flagProgress >= Rules.FLAG_LOWER_TIME) {
			flagTeam = -1;
			flagHeld = 0;
			u.flagProgress = 0;
		}
	}

	/** The captain working the flag right now (raising or lowering), if any. **/
	public function flagWorker():Null<Unit> {
		for (u in units)
			if (u.alive && u.kind == Captain && u.flagProgress > 0) return u;
		return null;
	}

	function stepArrows() {
		var k = arrows.length;
		while (k-- > 0) {
			var a = arrows[k];
			a.t += TICK;
			var t = getUnit(a.targetId);
			if (t != null && t.alive && t.aboard < 0) {
				a.aimX = t.x;
				a.aimY = t.y;
				a.aimZ = t.z;
			}
			if (a.t >= a.duration) {
				arrows.splice(k, 1);
				var shooter = getUnit(a.shooterId);
				if (t != null && t.alive && t.aboard < 0 && shooter != null) hurt(t, a.damage, shooter);
			}
		}
	}

	function checkVictory() {
		for (team in 0...2) {
			var any = false, captain = false;
			for (u in units)
				if (u.team == team && u.alive) {
					any = true;
					if (u.kind == Captain) captain = true;
				}
			if (!any) {
				win(1 - team, "eliminated");
				return;
			}
			if (!captain) {
				win(1 - team, "captain");
				return;
			}
		}
	}

	function win(team:Int, reason:String) {
		if (winner >= 0) return;
		winner = team;
		winReason = reason;
		winTick = tick;
	}

	static inline function dist(a:Unit, b:Unit):Float {
		var dx = a.x - b.x, dy = a.y - b.y;
		return Math.sqrt(dx * dx + dy * dy);
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
				// Leave room for the hull, with depth to spare: an anchorage in barely-deep
				// water left ships stuck in the shallows on the approach.
				var spare = Ship.DRAFT - 0.35;
				if (island.heightAt(ax, ay) > spare || island.heightAt(ax + Math.cos(a) * 2, ay + Math.sin(a) * 2) > spare) continue;
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
		s.stuckTicks = 0;
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
		// No headway for a while (shallows ahead): give up rather than sail on the spot.
		// Close enough to the anchorage, the crew can wade in from here.
		s.stuckTicks = s.speed < 0.05 ? s.stuckTicks + 1 : 0;
		if (s.stuckTicks > 45) {
			s.stuckTicks = 0;
			s.speed = 0;
			if (s.landOnArrival && dist < 10 && s.crew.length > 0) {
				s.landOnArrival = false;
				s.state = Landing;
				s.disembarkTimer = 0;
				s.landed = 0;
			} else {
				s.state = Idle;
				s.landOnArrival = false;
			}
		}
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
		if (s.crew.length == 0 && Directives.current.marchOnLanding) startMarch(s, u);
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
		if (u.kind == Captain) {
			// At the back of the band: between its rally point and the shore.
			var bx = s.shoreX - s.inlandX, by = s.shoreY - s.inlandY;
			var bl = Math.max(Math.sqrt(bx * bx + by * by), 0.01);
			var back = Math.min(Directives.current.captainStandBack, bl * 0.8);
			u.tx = s.inlandX + bx / bl * back;
			u.ty = s.inlandY + by / bl * back;
		}
		u.hasTarget = true;
		// Their rally point is where they gather inland.
		u.guardX = u.tx;
		u.guardY = u.ty;
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
