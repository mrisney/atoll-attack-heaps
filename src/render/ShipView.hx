package render;

import h3d.col.Point;

/**
	A ship, built in code: a lofted timber hull with a deck and gunwale, a
	mast and yard, and a square canvas sail with a band in the team colour.
	Timber, like the docks and the flag pole, and never toned by the Sketch
	style (it isn't under IslandView). About 9 m long, sized for a crew of
	12-20.

	Reads the sim's Ship each frame: eases toward its position and heading,
	and bobs, pitches and rolls a little on the swell (more under way).
	Local frame: bow toward +X, port side +Y, waterline at z = 0.
**/
class ShipView extends h3d.scene.Object {
	public static inline var LENGTH = 9.0;
	public static inline var BEAM = 3.0;

	public final ship:game.Ship;
	public var selected(default, set) = false;

	final body:h3d.scene.Object;
	final ring:h3d.scene.Object;
	var heading:Float;
	var time = 0.0;
	/** Seconds since it sank (it settles by the stern and goes under). **/
	var sinkTime = 0.0;
	/** A kick of heel from the last broadside, decaying. **/
	var recoil = 0.0;
	var seenShot = -1000;

	public function new(ship:game.Ship, ?parent:h3d.scene.Object) {
		super(parent);
		this.ship = ship;
		heading = ship.heading;
		body = new h3d.scene.Object(this);
		build(ship.team);

		ring = new h3d.scene.Object(this);
		var rb = new FlatMeshBuilder();
		rb.ring(0, 0, 0.12, LENGTH * 0.62, LENGTH * 0.68, 40, Palette.SELECT);
		rb.build(ring, false);
		ring.visible = false;

		setPosition(ship.x, ship.y, 0);
		body.setRotation(0, 0, heading);
	}

	function set_selected(v:Bool) {
		ring.visible = v;
		return selected = v;
	}

	function build(team:Int) {
		var b = new FlatMeshBuilder();
		var hullCol = Palette.SHIP_HULL, deckCol = Palette.SHIP_DECK, trim = Palette.WOOD;
		var half = LENGTH / 2;
		var keel = -0.55;
		// Stations along the hull: a section (gunwale, bilge, keel) at each.
		var n = 12;
		var stations = [];
		for (i in 0...n + 1) {
			var t = i / n; // 0 = stern, 1 = bow
			var x = -half + t * LENGTH;
			// Fuller aft, fine at the bow; a little stern transom left open.
			var w = BEAM / 2 * Math.pow(Math.sin(Math.PI * (0.08 + t * 0.92)), 0.55) * (t < 0.5 ? 1.0 : 1.0 - (t - 0.5) * 0.25);
			// Sheer: the gunwale rises toward bow and stern.
			var top = 0.65 + Math.pow(Math.abs(t - 0.45) * 2, 2) * 0.45;
			stations.push({
				x: x,
				g: w,
				top: top,
				bilge: w * 0.82,
				bz: 0.0,
				kz: keel * (0.4 + 0.6 * Math.sin(Math.PI * t))
			});
		}
		inline function P(x:Float, y:Float, z:Float) return new Point(x, y, z);
		for (i in 0...n) {
			var a = stations[i], c = stations[i + 1];
			var centre = P((a.x + c.x) / 2, 0, 0.1);
			for (side in [-1.0, 1.0]) {
				// Topsides (gunwale to bilge) and bottom (bilge to keel).
				b.triOut(P(a.x, a.g * side, a.top), P(c.x, c.g * side, c.top), P(c.x, c.bilge * side, c.bz), centre, hullCol);
				b.triOut(P(a.x, a.g * side, a.top), P(c.x, c.bilge * side, c.bz), P(a.x, a.bilge * side, a.bz), centre, hullCol);
				b.triOut(P(a.x, a.bilge * side, a.bz), P(c.x, c.bilge * side, c.bz), P(c.x, 0, c.kz), centre, hullCol, 0.82);
				b.triOut(P(a.x, a.bilge * side, a.bz), P(c.x, 0, c.kz), P(a.x, 0, a.kz), centre, hullCol, 0.82);
				// A darker wale strake along the gunwale.
				b.triOut(P(a.x, a.g * side, a.top), P(c.x, c.g * side, c.top), P(c.x, c.g * side * 1.03, c.top - 0.12), centre, trim);
				b.triOut(P(a.x, a.g * side, a.top), P(c.x, c.g * side * 1.03, c.top - 0.12), P(a.x, a.g * side * 1.03, a.top - 0.12), centre, trim);
			}
			// Deck, a little below the gunwale.
			var dz = 0.48;
			var under = P((a.x + c.x) / 2, 0, -5);
			b.triOut(P(a.x, -a.g * 0.92, dz), P(c.x, -c.g * 0.92, dz), P(c.x, c.g * 0.92, dz), under, deckCol);
			b.triOut(P(a.x, -a.g * 0.92, dz), P(c.x, c.g * 0.92, dz), P(a.x, a.g * 0.92, dz), under, deckCol);
		}
		// Transom at the stern.
		var s = stations[0];
		var aft = P(s.x - 1, 0, 0.2);
		for (side in [-1.0, 1.0]) {
			b.triOut(P(s.x, 0, s.kz), P(s.x, s.bilge * side, s.bz), P(s.x, s.g * side, s.top), aft, hullCol, 0.9);
			b.triOut(P(s.x, 0, s.kz), P(s.x, s.g * side, s.top), P(s.x, 0, s.top), aft, hullCol, 0.9);
		}

		// Mast, yard and a square sail, slightly bellied forward.
		var mx = 0.4;
		b.cone(mx, 0, 0.4, 0.11, 6.2, 6, trim, 0.07);
		b.cone(-half + 0.5, 0, 0.6, 0.06, 0.9, 5, trim, 0.05); // stern post
		var yardZ = 5.4, footZ = 2.1, halfW = 2.2;
		b.place(-Math.PI / 2, 0, 0, mx + 0.12, -halfW - 0.2, yardZ);
		b.cone(0, 0, 0, 0.06, halfW * 2 + 0.4, 5, trim, 0.06);
		b.unplace();
		var sail = Palette.SAIL;
		var band = team == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		var cols = 4, rows = 4;
		inline function sailPt(u:Float, v:Float):Point {
			// u across (-1..1), v down (0 top .. 1 foot); belly forward most in the middle.
			var belly = 0.55 * (1 - u * u) * Math.sin(Math.PI * (0.15 + v * 0.7));
			return P(mx + 0.2 + belly, u * halfW * (1 - v * 0.06), yardZ - 0.1 - v * (yardZ - footZ));
		}
		for (r in 0...rows)
			for (c in 0...cols) {
				var u0 = c / cols * 2 - 1, u1 = (c + 1) / cols * 2 - 1;
				var v0 = r / rows, v1 = (r + 1) / rows;
				var col = r == 1 || r == 2 ? (r == 1 ? band : sail) : sail;
				var p00 = sailPt(u0, v0), p10 = sailPt(u1, v0), p11 = sailPt(u1, v1), p01 = sailPt(u0, v1);
				b.twoSided(p00, p10, p11, col);
				b.twoSided(p00, p11, p01, col);
			}
		// Cannons: two a side, iron barrels poking out over the gunwale.
		for (side in [-1.0, 1.0])
			for (cx in [-1.6, 1.3]) {
				b.place(-side * Math.PI / 2, 0, 0, cx, side * BEAM * 0.36, 0.78);
				b.cone(0, 0, 0, 0.12, 1.0, 7, Palette.IRON, 0.09);
				b.unplace();
				// The carriage.
				b.place(0, 0, 0, cx, side * BEAM * 0.3, 0.48);
				b.prism(0, 0, 0, 0.22, 0.24, 4, trim, Math.PI / 4);
				b.unplace();
			}
		b.build(body, true, true, true);
	}

	/** Follow the sim ship, with a little life on the water. **/
	public function syncFromSim(dt:Float) {
		time += dt;
		var k = Math.min(1, dt * 12);
		setPosition(x + (ship.x - x) * k, y + (ship.y - y) * k, 0);
		var diff = ship.heading - heading;
		while (diff > Math.PI) diff -= Math.PI * 2;
		while (diff < -Math.PI) diff += Math.PI * 2;
		heading += diff * Math.min(1, dt * 6);
		var way = Math.min(1, ship.speed / game.Ship.MAX_SPEED);
		var phase = ship.id * 1.7;
		var bob = Math.sin(time * 1.25 + phase) * 0.07;
		var pitch = Math.sin(time * 0.9 + phase) * (0.025 + 0.02 * way);
		// Heel a little into turns and roll gently on the swell.
		var roll = Math.sin(time * 1.1 + phase * 0.5) * 0.035 + diff * 0.15 * way;
		// A broadside fired: the ship heels away from the guns for a moment.
		if (ship.lastShotTick != seenShot) {
			if (seenShot > -1000) recoil = -ship.lastShotSide * 0.07;
			seenShot = ship.lastShotTick;
		}
		recoil *= Math.exp(-dt * 2.5);
		roll += recoil;
		if (ship.sunk) {
			// Holed: she settles by the stern, lists, and goes under in a few seconds.
			sinkTime += dt;
			selected = false;
			var f = Math.min(1, sinkTime / 7);
			bob -= f * f * 6.5;
			pitch -= f * 0.35;
			roll += f * 0.5;
			if (sinkTime > 8) visible = false;
		}
		body.z = bob;
		var q = new h3d.Quat();
		q.initRotation(roll, pitch, heading);
		body.setRotationQuat(q);
	}
}
