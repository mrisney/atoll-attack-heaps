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
		var island = new world.Island(seed, Single);
		var sim = new game.Sim(island);
		sim.teamAIs.push(new game.TeamAI(sim, 0));
		sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[0].x, sim.homeBeach[0].y));
		for (sec in 0...241) {
			if (sec % 10 == 0 || sim.winner >= 0) {
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
				line += ' arrows=${sim.arrows.length} apex=(${r(island.apexX)},${r(island.apexY)})';
				Sys.println(line);
			}
			if (sim.winner >= 0) {
				Sys.println('WINNER: ${sim.winner == 0 ? "blue" : "red"} (${sim.winReason}) at ${sec}s');
				break;
			}
			for (_ in 0...30) sim.update(game.Sim.TICK);
		}
	}

	static function r(v:Float) return Math.round(v * 10) / 10;
}
