package game;

enum UnitKind {
	Captain;
	Archer;
	Swordsman;
	/** Long pike: melee with reach. **/
	Piker;
}

/**
	Simulation-side unit. No rendering references, so the sim can run
	headless (tests, a server, or a lockstep peer).
**/
class Unit {
	public final id:Int;
	public final team:Int;
	public final kind:UnitKind;

	public var x:Float;
	public var y:Float;
	public var z:Float = 0;
	public var facing:Float = 0;

	public var alive = true;
	/** The ship this unit is aboard (not on the island yet), or -1. **/
	public var aboard = -1;
	/** Where the killing blow came from — the view uses it to fling the body away. **/
	public var hitFromX = 0.0;
	public var hitFromY = 0.0;

	public var hasTarget = false;
	public var tx = 0.0;
	public var ty = 0.0;

	public var baseSpeed(get, never):Float;

	public function new(id:Int, team:Int, kind:UnitKind, x:Float, y:Float) {
		this.id = id;
		this.team = team;
		this.kind = kind;
		this.x = x;
		this.y = y;
	}

	function get_baseSpeed():Float {
		return switch kind {
			case Captain: 3.2;
			case Archer: 3.6;
			case Swordsman: 3.0;
			case Piker: 2.9;
		}
	}
}
