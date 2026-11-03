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

	/** Movement goal (the AI and orders set it; Sim moves toward it). **/
	public var hasTarget = false;
	public var tx = 0.0;
	public var ty = 0.0;

	// --- combat and AI (see Sim.think) ---
	public var hp:Float;
	/** Ticks until it can strike again. **/
	public var cooldown = 0;
	/** The enemy it's fighting (-1 = none). **/
	public var targetId = -1;
	/** The player ordered this target: chase it anywhere, don't swap. **/
	public var forcedTarget = false;
	/** A player move in progress: walk there, ignoring enemies, then hold. **/
	public var ordered = false;
	/** Where it holds when it has nothing to fight (the rally point). **/
	public var guardX:Float;
	public var guardY:Float;
	/** Tick of its last strike (the view animates the swing / draw). **/
	public var lastAttackTick = -1000;
	/** Waypoints around water to the movement goal (x0, y0, ...), see Sim.steer. **/
	public var path:Null<Array<Float>> = null;
	/** The goal that path was found for, and when (tick). **/
	public var pathGoalX = 1e9;
	public var pathGoalY = 1e9;
	public var pathTick = -1000;
	/** Captain only: seconds spent raising the flag at the apex. **/
	public var flagProgress = 0.0;

	public var baseSpeed(get, never):Float;

	public function new(id:Int, team:Int, kind:UnitKind, x:Float, y:Float) {
		this.id = id;
		this.team = team;
		this.kind = kind;
		this.x = x;
		this.y = y;
		guardX = x;
		guardY = y;
		hp = Rules.stats(kind).hp;
	}

	public var maxHp(get, never):Float;

	inline function get_maxHp()
		return Rules.stats(kind).hp;

	function get_baseSpeed():Float {
		return switch kind {
			case Captain: 3.2;
			case Archer: 3.6;
			case Swordsman: 3.0;
			case Piker: 2.9;
		}
	}
}
