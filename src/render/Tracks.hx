package render;

import world.Island;
import world.Noise;

/**
	Worn ground: dusty tracks and scuffed patches through the meadows, as in
	the Stronghold screenshots the owner pointed at.

	Tracks run from four beaches (the two squads' landings plus two more) up
	to the high ground, wandering as they climb, so they read as paths worn
	by people going to the summit, which is where the fighting will be.
	Broad scuffed patches are added where a low-frequency noise is high.

	The result is a `RES`² grid of wear (0..1) over the island. GrassField
	thins and shortens the blades with it (mask alpha), TerrainStyle paints
	dusty dirt under it, and Props keeps trees off it and scatters pebbles on
	it. Purely visual: seeded from the island, never read by the sim.
**/
class Tracks {
	public static inline var RES = 256;

	public final grid:haxe.ds.Vector<Float>;
	final origin:Float;
	final span:Float;
	final island:Island;

	public function new(island:Island, tSand:Float, tUp:Float) {
		this.island = island;
		origin = -island.halfExtent;
		span = island.halfExtent * 2;
		grid = new haxe.ds.Vector(RES * RES);
		for (i in 0...RES * RES) grid[i] = 0;

		var wander = new Noise(island.seed + 1201);
		var widthN = new Noise(island.seed + 1202);
		var k = 0;
		for (angle in [0.25, 1.25, 0.8, 1.75]) {
			k++;
			var start = island.findLandNear(Math.PI * angle);
			var x = start.x, y = start.y;
			var travelled = 0.0;
			// Walk uphill toward the apex, wandering left and right as the path climbs.
			for (step in 0...600) {
				var dx = island.apexX - x, dy = island.apexY - y;
				var d = Math.sqrt(dx * dx + dy * dy);
				if (d < 5) break;
				var a = Math.atan2(dy, dx) + (wander.fbm(travelled * 0.025 + k * 17, k * 5.3, 2) - 0.5) * 2.4;
				x += Math.cos(a) * 0.6;
				y += Math.sin(a) * 0.6;
				travelled += 0.6;
				var h = island.heightAt(x, y);
				if (h < tSand - 0.1) continue; // still on the beach / in the shallows
				// Wider near the beach and the summit, where traffic gathers; a little
				// narrower in between.
				var hw = 0.9 + widthN.fbm(travelled * 0.05 + k * 9, 3.1, 2) * 1.6;
				stamp(x, y, hw);
			}
		}

		// Broad scuffed patches in the open ground.
		var patchN = new Noise(island.seed + 1203);
		for (j in 0...RES)
			for (i in 0...RES) {
				var x = origin + (i + 0.5) / RES * span, y = origin + (j + 0.5) / RES * span;
				var p = smoothstep(0.64, 0.78, patchN.fbm(x * 0.05 + 11, y * 0.05 + 11, 3)) * 0.65;
				var id = j * RES + i;
				if (p > grid[id]) grid[id] = p;
			}
	}

	function stamp(x:Float, y:Float, hw:Float) {
		var cell = span / RES;
		var outer = hw + 1.6;
		var cx = (x - origin) / cell, cy = (y - origin) / cell, r = outer / cell;
		for (j in Std.int(cy - r - 1)...Std.int(cy + r + 2))
			for (i in Std.int(cx - r - 1)...Std.int(cx + r + 2)) {
				if (i < 0 || j < 0 || i >= RES || j >= RES) continue;
				var dx = (i + 0.5 - cx) * cell, dy = (j + 0.5 - cy) * cell;
				var d = Math.sqrt(dx * dx + dy * dy);
				var w = 1 - smoothstep(hw * 0.4, outer, d);
				var id = j * RES + i;
				if (w > grid[id]) grid[id] = w;
			}
	}

	/** Wear at a world point (bilinear). **/
	public function at(x:Float, y:Float):Float {
		var gx = (x - origin) / span * RES - 0.5, gy = (y - origin) / span * RES - 0.5;
		var i = Std.int(Math.floor(gx)), j = Std.int(Math.floor(gy));
		var fx = gx - i, fy = gy - j;
		inline function g(a:Int, b:Int):Float {
			if (a < 0) a = 0;
			if (b < 0) b = 0;
			if (a >= RES) a = RES - 1;
			if (b >= RES) b = RES - 1;
			return grid[b * RES + a];
		}
		var top = g(i, j) * (1 - fx) + g(i + 1, j) * fx;
		var bot = g(i, j + 1) * (1 - fx) + g(i + 1, j + 1) * fx;
		return top * (1 - fy) + bot * fy;
	}

	static inline function smoothstep(a:Float, b:Float, x:Float):Float {
		var t = Math.max(0, Math.min(1, (x - a) / (b - a)));
		return t * t * (3 - 2 * t);
	}
}
