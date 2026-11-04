package game;

/**
	A cannonball in flight (sim side), lobbed from a ship's broadside. Unlike
	an arrow it doesn't home: it was aimed at a spot (the target's position,
	or where a moving ship will be, plus a scatter that grows with range), and
	whatever stands there when it lands is hit (Sim.cannonImpact). So a unit
	that walks on is spared, and one that walks in isn't.

	The view draws it on a high arc from (fromX, fromY) to (toX, toY) over
	`duration`; `id` lets it notice new shots (the muzzle puff).
**/
class Cannonball {
	public final id:Int;
	public final shipId:Int;
	public final team:Int;
	public final fromX:Float;
	public final fromY:Float;
	public final toX:Float;
	public final toY:Float;
	public final duration:Float;
	/** Seconds since it was fired. **/
	public var t = 0.0;

	public function new(id:Int, ship:Ship, toX:Float, toY:Float, duration:Float) {
		this.id = id;
		shipId = ship.id;
		team = ship.team;
		fromX = ship.x;
		fromY = ship.y;
		this.toX = toX;
		this.toY = toY;
		this.duration = duration;
	}
}

/** Where a ball came down, for the view (splash, dust, crater). Kept a few seconds. **/
typedef Impact = {
	var id:Int;
	var x:Float;
	var y:Float;
	/** Came down in the sea (a splash) rather than on land. **/
	var water:Bool;
	/** Struck a ship's hull. **/
	var hitShip:Bool;
	var tick:Int;
}
