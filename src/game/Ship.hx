package game;

enum ShipState {
	/** Waiting at sea (the start, or after a plain sail order). **/
	Idle;
	Sailing;
	/** Anchored off a beach, putting its crew ashore. **/
	Landing;
}

/**
	A ship: one per side, carrying the whole band (12-20 characters, per
	the game's concept: a light RTS, one small crew, capture the flag).

	Simulation only, like Unit. It sails through deep water (deeper than
	DRAFT), steering around the island by sampling headings, anchors off the
	chosen beach and puts its crew ashore one by one (`Sim.stepShips`).
	Units aboard are real units with `aboard = ship id`: they keep their ids
	(so selection, views and the network see the same units), they just
	aren't on the island yet.
**/
class Ship {
	/** The keel needs water at least this deep (heights are negative at sea). **/
	public static inline var DRAFT = -0.75;
	public static inline var MAX_SPEED = 4.5;
	/** Turn rate, radians per second. **/
	public static inline var TURN = 0.8;
	/** Seconds between two crew members wading ashore. **/
	public static inline var DISEMBARK_INTERVAL = 0.3;

	public final id:Int;
	public final team:Int;
	public var x:Float;
	public var y:Float;
	public var heading:Float;
	public var speed = 0.0;
	public var state = Idle;

	/** Where it's sailing to (an anchorage when landing). **/
	public var tx = 0.0;
	public var ty = 0.0;
	/** Landing: where the crew comes ashore, and where they head inland to. **/
	public var shoreX = 0.0;
	public var shoreY = 0.0;
	public var inlandX = 0.0;
	public var inlandY = 0.0;
	/** Unit ids still aboard, in the order they go ashore. **/
	public final crew:Array<Int> = [];
	public var landed = 0;
	/** Put the crew ashore on arrival (a landing order, not a plain sail order). **/
	public var landOnArrival = false;
	public var disembarkTimer = 0.0;

	public function new(id:Int, team:Int, x:Float, y:Float, heading:Float) {
		this.id = id;
		this.team = team;
		this.x = x;
		this.y = y;
		this.heading = heading;
	}
}
