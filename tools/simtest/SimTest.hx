/**
	Headless check of the simulation (no Heaps): runs a match and prints what
	ships and units are doing, and who wins. The sim must stay runnable like
	this (see CLAUDE.md, architecture rules).

	    haxe -cp src -cp tools/simtest -main SimTest --interp [-D seed=5095]

	Both sides are computer-commanded here (blue gets its own TeamAI), so it's
	a full battle: landing, the advance on the apex, fighting, the flag.
**/
class SimTest {
	static function main() {
		var seed = Std.parseInt(haxe.macro.Compiler.getDefine("seed") ?? "5095");
		game.Directives.load(sys.io.File.getContent("res/data/directives.json"));
		var island = new world.Island(seed, Single);
		var naval = haxe.macro.Compiler.getDefine("naval") != null;
		var sim = new game.Sim(island, naval);
		if (!naval) sim.teamAIs.push(new game.TeamAI(sim, 0));
		if (naval) {
			// Sail at each other, a little apart, so they pass broadside to broadside.
			var a = sim.ships[0], b = sim.ships[1];
			sim.queue(ShipTo(a.id, b.x, b.y + 6));
			sim.queue(ShipTo(b.id, a.x, a.y - 6));
		} else
			sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[0].x, sim.homeBeach[0].y));
		// Scenarios: -D bombard sends blue's ship round to red's beach once its crew is
		// ashore (ship duel, shelling the landing); -D heal sends blue's wounded back aboard.
		var bombard = haxe.macro.Compiler.getDefine("bombard") != null;
		var healTest = haxe.macro.Compiler.getDefine("heal") != null;
		var cannonKills = 0;
		for (sec in 0...241) {
			// Naval: come about and pass again every 20 s, like a player would.
			if (naval && sec > 0 && sec % 20 == 0) {
				var a = sim.ships[0], b = sim.ships[1];
				sim.queue(ShipTo(a.id, b.x, b.y + 6));
				sim.queue(ShipTo(b.id, a.x, a.y - 6));
			}
			// -D shipfire: blue's ship fires on the nearest red character within its ordered range.
			if (haxe.macro.Compiler.getDefine("shipfire") != null && sec >= 20 && sec % 5 == 0 && sim.winner < 0) {
				var sh = sim.ships[0];
				var best = null, bd = 1e9;
				for (u in sim.units)
					if (u.team == 1 && u.alive && u.aboard < 0) {
						var d = Math.sqrt((u.x - sh.x) * (u.x - sh.x) + (u.y - sh.y) * (u.y - sh.y));
						if (d < bd) { bd = d; best = u; }
					}
				if (best != null && sh.fireTarget < 0) sim.queue(ShipFire(sh.id, best.id));
				Sys.println('  shipfire: target=${sh.fireTarget} nearest red ${r(bd)} m, shots=${sh.shots}, balls=${sim.cannonballs.length}');
			}
			if (naval && sec % 5 == 0 && sim.winner < 0)
				Sys.println('  t=${sec}s ' + [for (s in sim.ships) 'ship${s.team} ${s.sunk ? "SUNK" : Std.string(s.state)}@(${r(s.x)},${r(s.y)}) hp=${Math.round(s.hp)} shots=${s.shots}'].join("  ") + '  gap=${r(Math.sqrt(Math.pow(sim.ships[0].x - sim.ships[1].x, 2) + Math.pow(sim.ships[0].y - sim.ships[1].y, 2)))}');
			if (bombard && sec == 15) sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[1].x, sim.homeBeach[1].y));
			if (healTest && sec == 12) {
				// Wound four soldiers (test harness only) and send them back aboard.
				var ids = [];
				for (u in sim.units)
					if (u.team == 0 && u.alive && u.aboard < 0 && u.kind != Captain && ids.length < 4) {
						u.hp = u.maxHp * 0.4;
						ids.push(u.id);
					}
				Sys.println('  heal: wounded ${ids} sent back aboard');
				sim.queue(Board(ids, sim.ships[0].id));
			}
			if (healTest && sec == 45) {
				var aboard = [for (u in sim.units) if (u.team == 0 && u.alive && u.aboard >= 0) u.id + ":" + Math.round(u.hp / u.maxHp * 100) + "%"];
				Sys.println('  heal: aboard now ${aboard.join(" ")}; landing them again');
				sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[0].x, sim.homeBeach[0].y));
			}
			if (sec % 10 == 0 || sim.winner >= 0 || (healTest && sec > 12 && sec < 56 && sec % 3 == 0)) {
				var line = 't=${sec}s';
				for (team in 0...2) {
					var alive = 0, ashore = 0, hp = 0.0;
					var cap = "";
					for (u in sim.units)
						if (u.team == team && u.alive) {
							alive++;
							if (u.aboard < 0) ashore++;
							hp += u.hp;
							if (u.kind == Captain) cap = ' cap@(${r(u.x)},${r(u.y)}) flag=${r(u.flagProgress)}';
						}
					line += '  [${team == 0 ? "blue" : "red"} alive=$alive ashore=$ashore hp=${Math.round(hp)}$cap]';
				}
				for (sh in sim.ships)
					line += ' ship${sh.team}:${sh.sunk ? "SUNK" : Std.string(sh.state)}@(${Math.round(sh.x)},${Math.round(sh.y)}) hp=${Math.round(sh.hp)} shots=${sh.shots} crew=${sh.crew.length}';
				for (u in sim.units) if (u.boarding >= 0) line += ' boarding#${u.id}@(${Math.round(u.x)},${Math.round(u.y)})hp${Math.round(u.hp)}';
				line += ' arrows=${sim.arrows.length} flag=${sim.flagTeam < 0 ? "none" : (sim.flagTeam == 0 ? "blue" : "red")}${sim.flagTeam >= 0 ? " " + Math.round(sim.flagHeld) + "s" : ""}';
				Sys.println(line);
				if (haxe.macro.Compiler.getDefine("dump") != null && sec == 100)
					for (u in sim.units)
						if (u.alive) Sys.println('    ${u.team} ${u.kind} #${u.id} (${r(u.x)},${r(u.y)}) guard(${r(u.guardX)},${r(u.guardY)}) tgt=${u.targetId} ord=${u.ordered} mar=${u.marching} hasT=${u.hasTarget} board=${u.boarding}');
			}
			if (sim.winner >= 0) {
				var how = "";
				for (u in sim.units)
					if (u.kind == Captain && !u.alive) {
						var k = sim.getUnit(u.lastHitBy);
						var near = [for (e in sim.units) if (e.alive && e.team != u.team && Math.sqrt((e.x - u.x) * (e.x - u.x) + (e.y - u.y) * (e.y - u.y)) < 10) e].length;
						var guards = [for (e in sim.units) if (e.alive && e.team == u.team && e.aboard < 0) e].length;
						how += ' [${u.team == 0 ? "blue" : "red"} captain killed by ${u.lastHitBy == game.Sim.CANNON ? "cannon" : (k == null ? "?" : Std.string(k.kind))}, ${near} enemies within 10 m, ${guards} of his own alive]';
					}
				Sys.println('WINNER: ${sim.winner == 0 ? "blue" : "red"} (${sim.winReason}) at ${sec}s$how');
				break;
			}
			for (_ in 0...30) sim.update(game.Sim.TICK);
		}
	}

	static function r(v:Float) return Math.round(v * 10) / 10;
}
