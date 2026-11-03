package game;

/**
	Everything a player can do is a Command. Input code produces them, the
	Sim consumes them. For multiplayer, these are exactly what you send over
	the wire (Steam P2P, WebRTC, ...) and apply on each peer at the same tick.
**/
enum Command {
	Move(unitIds:Array<Int>, x:Float, y:Float);
	/**
		Send a ship to (x, y). On land: sail to the nearest anchorage off that
		spot and put the crew ashore there. At sea: just sail there.
	**/
	ShipTo(shipId:Int, x:Float, y:Float);
	Stop(unitIds:Array<Int>);
	/** Units go after this enemy, wherever it goes. **/
	Attack(unitIds:Array<Int>, targetId:Int);
	/** Walk toward (x, y) but fight whatever comes near on the way, then hold there. **/
	AttackMove(unitIds:Array<Int>, x:Float, y:Float);
	/** Units die; (fromX, fromY) is the source of the hit. Debug blast for now, combat later. **/
	Kill(unitIds:Array<Int>, fromX:Float, fromY:Float);
}
