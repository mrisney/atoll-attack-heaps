package game;

/**
	Everything a player can do is a Command. Input code produces them, the
	Sim consumes them. For multiplayer, these are exactly what you send over
	the wire (Steam P2P, WebRTC, ...) and apply on each peer at the same tick.
**/
enum Command {
	Move(unitIds:Array<Int>, x:Float, y:Float);
	Stop(unitIds:Array<Int>);
}
