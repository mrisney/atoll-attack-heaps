package game;

/**
	The computer side's commander: deliberately simple, like the game. It
	only gives the orders a player would (AttackMove / Move through the sim's
	commands); the fighting itself is each character's own AI (Sim.think).

	Once its crew is ashore it advances the band on the apex. The soldiers
	attack-move there, so they fight whatever they meet on the way. The
	captain hangs back behind them, and walks up to plant the flag once the
	apex is clear of enemies and at least three of his own hold it. If the
	soldiers are all gone, he makes a run for it.

	Runs every second (Sim calls it every 30 ticks), deterministic like the
	rest of the sim, so it works the same in lockstep multiplayer.
**/
class TeamAI {
	final sim:Sim;
	final team:Int;
	var captainSent = false;
	var landingTries = 0;

	public function new(sim:Sim, team:Int) {
		this.sim = sim;
		this.team = team;
	}

	public function update() {
		var ship = null;
		for (s in sim.ships)
			if (s.team == team) ship = s;
		// Wait until everyone is ashore. If the ship gave up on the way (shallows,
		// a dead end), try the coast a little further round each time.
		if (ship != null && ship.crew.length > 0) {
			if (ship.state == Idle) {
				landingTries++;
				var b = sim.homeBeach[team];
				var a = Math.atan2(b.y, b.x) + (landingTries % 2 == 0 ? 1 : -1) * Std.int((landingTries + 1) / 2) * 0.35;
				var r = Math.sqrt(b.x * b.x + b.y * b.y);
				sim.queue(ShipTo(ship.id, Math.cos(a) * r, Math.sin(a) * r));
			}
			return;
		}

		var ax = sim.island.apexX, ay = sim.island.apexY;
		var soldiers = [], captain:Null<Unit> = null;
		for (u in sim.units)
			if (u.team == team && u.alive && u.aboard < 0) {
				if (u.kind == Captain) captain = u else soldiers.push(u);
			}
		if (captain == null) return;

		// Soldiers: attack-move on the apex (re-issued only to those not already fighting).
		// (Marchers are already on their way: the flock takes them to the summit.)
		var idle = [for (u in soldiers) if (u.targetId < 0 && !u.ordered && !u.marching) u.id];
		var dgx = 0.0, dgy = 0.0;
		if (idle.length > 0) {
			var u0 = sim.getUnit(idle[0]);
			dgx = u0.guardX - ax;
			dgy = u0.guardY - ay;
		}
		if (idle.length > 0 && dgx * dgx + dgy * dgy > 9 * 9) sim.queue(AttackMove(idle, ax, ay));

		// The captain: behind the band until the apex is held and clear, then up he goes.
		var holding = 0, enemyNear = false;
		for (u in soldiers)
			if (near(u.x, u.y, ax, ay, 10)) holding++;
		// Clear out to arrow range: captains sent up while archers lurked at 15-18 m
		// were shot every time.
		var clear = Rules.stats(Archer).reach + 3;
		for (u in sim.units)
			if (u.team != team && u.alive && u.aboard < 0 && near(u.x, u.y, ax, ay, u.kind == Archer ? clear : 10)) enemyNear = true;
		// Sent up but under fire and hurt: call him back behind the band.
		// (Alone, there's no one to hide behind: then he fights it out.)
		if (captainSent && soldiers.length > 0 && captain.flagProgress == 0) {
			// Recall him as soon as an enemy is within arrow range of him (waiting until
			// he was hurt was too late: focused archers kill him in about 4 s).
			var danger = false;
			for (u in sim.units)
				if (u.alive && u.team != team && u.aboard < 0 && near(u.x, u.y, captain.x, captain.y, Directives.current.marchCaptainHalt)) danger = true;
			if (danger) {
				captainSent = false;
				sim.queue(Stop([captain.id]));
			}
		}
		// The flag: nothing to do while ours stands (the band holds the summit and he
		// waits behind it). If theirs stands, he has to lower it, and when time is short
		// he goes whatever the danger.
		var ownFlag = sim.flagTeam == team;
		var urgent = sim.flagTeam >= 0 && !ownFlag && Rules.FLAG_HOLD_TIME - sim.flagHeld < 20;
		if (ownFlag && captainSent && captain.flagProgress == 0 && !captain.ordered) captainSent = false;
		if (!captainSent && !ownFlag && ((holding >= 3 && !enemyNear) || soldiers.length == 0 || urgent)) {
			captainSent = true;
			sim.queue(Move([captain.id], ax, ay));
		} else if (!captainSent && soldiers.length > 0) {
			// Follow well behind the band's centre (out of most arrows' reach), on the
			// side away from the apex.
			var cx = 0.0, cy = 0.0;
			for (u in soldiers) {
				cx += u.x;
				cy += u.y;
			}
			cx /= soldiers.length;
			cy /= soldiers.length;
			var dx = cx - ax, dy = cy - ay;
			var d = Math.max(Math.sqrt(dx * dx + dy * dy), 0.01);
			var bx = cx + dx / d * 9, by = cy + dy / d * 9;
			if (!captain.marching && sim.island.isWalkable(bx, by) && !near(captain.guardX, captain.guardY, bx, by, 3))
				sim.queue(AttackMove([captain.id], bx, by));
		}
		// If the captain got pushed off the apex, try again later.
		if (captainSent && captain.targetId < 0 && !captain.ordered && !near(captain.x, captain.y, ax, ay, Rules.FLAG_RANGE)) captainSent = false;
	}

	static inline function near(x:Float, y:Float, px:Float, py:Float, r:Float):Bool {
		var dx = x - px, dy = y - py;
		return dx * dx + dy * dy < r * r;
	}
}
