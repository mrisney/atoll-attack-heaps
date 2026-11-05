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
	/**
		Units go back aboard their own ship: they walk to the shore nearest it
		and climb aboard once it lies still close by. Aboard, they heal; they
		land again with the ship's next landing order.
	**/
	Board(unitIds:Array<Int>, shipId:Int);
	/**
		The ship's guns take this enemy character as their target (out to
		cannon.orderedRange), until it falls, goes aboard, or another target is
		given. targetId -1 hands the guns back to their own choice.
	**/
	ShipFire(shipId:Int, targetId:Int);
	/** Units go after this enemy, wherever it goes. **/
	Attack(unitIds:Array<Int>, targetId:Int);
	/** Walk toward (x, y) but fight whatever comes near on the way, then hold there. **/
	AttackMove(unitIds:Array<Int>, x:Float, y:Float);
	/** Units die; (fromX, fromY) is the source of the hit. Debug blast for now, combat later. **/
	Kill(unitIds:Array<Int>, fromX:Float, fromY:Float);
}
