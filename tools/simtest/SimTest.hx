/**
	Headless check of the simulation (no Heaps): runs a match for a while and
	prints what ships and units are doing. The sim must stay runnable like
	this (see CLAUDE.md, architecture rules).

	    haxe -cp src -cp tools/simtest -main SimTest --interp [-D seed=5095]
**/
class SimTest {
	static function main() {
		var seed = Std.parseInt(haxe.macro.Compiler.getDefine("seed") ?? "5095");
		var island = new world.Island(seed, Single);
		var sim = new game.Sim(island);
		// Blue lands at its home beach too, so both sides come ashore.
		sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[0].x, sim.homeBeach[0].y));
		for (sec in 0...41) {
			if (sec % 4 == 0) {
				var line = 't=${sec}s';
				for (s in sim.ships) {
					var ashore = 0;
					for (u in sim.units) if (u.team == s.team && u.aboard < 0 && u.alive) ashore++;
					line += '  ship${s.team} ${s.state} (${r(s.x)},${r(s.y)}) v=${r(s.speed)} crew=${s.crew.length} ashore=$ashore alive=${[for (u in sim.units) if (u.team == s.team && u.alive) u].length}';
				}
				Sys.println(line);
			}
			for (_ in 0...30) sim.update(game.Sim.TICK);
		}
	}

	static function r(v:Float) return Math.round(v * 10) / 10;
}
