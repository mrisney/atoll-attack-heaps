package world;

/**
	Walking paths around water: A* over a coarse grid of the island
	(1 m cells, 8 directions), then shortened by cutting corners wherever
	the straight line stays on land.

	Units only use it when the straight line to their goal crosses water
	(see Sim.steer); open ground stays a straight walk. Deterministic (no
	floats in the queue order beyond a fixed tie-break), so lockstep peers
	get identical paths.
**/
class NavGrid {
	public static inline var CELL = 1.0;

	final island:Island;
	final n:Int;
	final origin:Float;
	final walk:haxe.ds.Vector<Bool>;
	// Search scratch (reused between queries).
	final g:haxe.ds.Vector<Float>;
	final from:haxe.ds.Vector<Int>;
	final stamp:haxe.ds.Vector<Int>;
	var search = 0;

	public function new(island:Island) {
		this.island = island;
		origin = -island.halfExtent;
		n = Std.int(island.halfExtent * 2 / CELL);
		walk = new haxe.ds.Vector(n * n);
		g = new haxe.ds.Vector(n * n);
		from = new haxe.ds.Vector(n * n);
		stamp = new haxe.ds.Vector(n * n);
		for (j in 0...n)
			for (i in 0...n) {
				var x = origin + (i + 0.5) * CELL, y = origin + (j + 0.5) * CELL;
				walk[j * n + i] = island.isWalkable(x, y);
				stamp[j * n + i] = 0;
			}
	}

	/** True if the straight walk from a to b stays on land (sampled every 0.4 m). **/
	public function clearLine(ax:Float, ay:Float, bx:Float, by:Float):Bool {
		var dx = bx - ax, dy = by - ay;
		var len = Math.sqrt(dx * dx + dy * dy);
		var steps = Std.int(len / 0.4) + 1;
		for (k in 1...steps + 1) {
			var t = k / steps;
			if (!island.isWalkable(ax + dx * t, ay + dy * t)) return false;
		}
		return true;
	}

	/**
		Waypoints (x0, y0, x1, y1, ...) from a to b, ending at b, or null if b
		can't be reached (it's water, or cut off).
	**/
	public function find(ax:Float, ay:Float, bx:Float, by:Float):Null<Array<Float>> {
		var s = nearestWalkable(cellOf(ax), cellOf(ay));
		var e = nearestWalkable(cellOf(bx), cellOf(by));
		if (s < 0 || e < 0) return null;
		search++;
		var ex = e % n, ey = Std.int(e / n);
		var open = new Heap();
		g[s] = 0;
		from[s] = -1;
		stamp[s] = search;
		open.push(s, h(s % n, Std.int(s / n), ex, ey));
		var found = false;
		var budget = n * n;
		while (open.size > 0 && budget-- > 0) {
			var c = open.pop();
			if (c == e) {
				found = true;
				break;
			}
			var cx = c % n, cy = Std.int(c / n);
			for (k in 0...8) {
				var nx = cx + DX[k], ny = cy + DY[k];
				if (nx < 0 || ny < 0 || nx >= n || ny >= n) continue;
				var id = ny * n + nx;
				if (!walk[id]) continue;
				// No cutting diagonally between two water cells.
				if (k >= 4 && (!walk[cy * n + nx] || !walk[ny * n + cx])) continue;
				var cost = g[c] + (k >= 4 ? 1.41421356 : 1.0);
				if (stamp[id] == search && cost >= g[id]) continue;
				stamp[id] = search;
				g[id] = cost;
				from[id] = c;
				open.push(id, cost + h(nx, ny, ex, ey));
			}
		}
		if (!found) return null;
		// Walk back, then smooth: keep only the corners the straight line can't skip.
		var cells = [];
		var c = e;
		while (c >= 0) {
			cells.push(c);
			c = from[c];
		}
		cells.reverse();
		var pts = [ax, ay];
		for (c in cells) {
			pts.push(origin + (c % n + 0.5) * CELL);
			pts.push(origin + (Std.int(c / n) + 0.5) * CELL);
		}
		pts.push(bx);
		pts.push(by);
		var out = [];
		var i = 0;
		var last = Std.int(pts.length / 2) - 1;
		while (i < last) {
			var j = last;
			while (j > i + 1 && !clearLine(pts[i * 2], pts[i * 2 + 1], pts[j * 2], pts[j * 2 + 1])) j--;
			out.push(pts[j * 2]);
			out.push(pts[j * 2 + 1]);
			i = j;
		}
		return out;
	}

	static final DX = [1, -1, 0, 0, 1, 1, -1, -1];
	static final DY = [0, 0, 1, -1, 1, -1, 1, -1];

	inline function cellOf(v:Float):Int {
		var c = Std.int((v - origin) / CELL);
		return c < 0 ? 0 : (c >= n ? n - 1 : c);
	}

	static inline function h(x:Int, y:Int, ex:Int, ey:Int):Float {
		var dx = x > ex ? x - ex : ex - x, dy = y > ey ? y - ey : ey - y;
		return (dx > dy ? dx : dy) + 0.41421356 * (dx < dy ? dx : dy);
	}

	/** The cell itself if walkable, else the nearest walkable one within a few cells. **/
	function nearestWalkable(i:Int, j:Int):Int {
		if (walk[j * n + i]) return j * n + i;
		for (r in 1...6)
			for (dj in -r...r + 1)
				for (di in -r...r + 1) {
					var x = i + di, y = j + dj;
					if (x < 0 || y < 0 || x >= n || y >= n) continue;
					if (walk[y * n + x]) return y * n + x;
				}
		return -1;
	}
}

/** A small binary min-heap of (cell, priority), with a deterministic tie-break. **/
private class Heap {
	final ids:Array<Int> = [];
	final pr:Array<Float> = [];

	public var size(get, never):Int;

	inline function get_size()
		return ids.length;

	public function new() {}

	inline function less(a:Int, b:Int):Bool
		return pr[a] < pr[b] || (pr[a] == pr[b] && ids[a] < ids[b]);

	public function push(id:Int, p:Float) {
		ids.push(id);
		pr.push(p);
		var i = ids.length - 1;
		while (i > 0) {
			var parent = (i - 1) >> 1;
			if (!less(i, parent)) break;
			swap(i, parent);
			i = parent;
		}
	}

	public function pop():Int {
		var top = ids[0];
		var last = ids.length - 1;
		swap(0, last);
		ids.pop();
		pr.pop();
		var i = 0;
		while (true) {
			var l = i * 2 + 1, r = l + 1, m = i;
			if (l < ids.length && less(l, m)) m = l;
			if (r < ids.length && less(r, m)) m = r;
			if (m == i) break;
			swap(i, m);
			i = m;
		}
		return top;
	}

	inline function swap(a:Int, b:Int) {
		var t = ids[a];
		ids[a] = ids[b];
		ids[b] = t;
		var q = pr[a];
		pr[a] = pr[b];
		pr[b] = q;
	}
}
