package game;

enum UnitKind {
	Captain;
	Archer;
	Swordsman;
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
		}
	}
}
