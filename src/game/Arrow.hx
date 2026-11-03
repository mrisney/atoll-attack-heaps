package game;

/**
	An arrow in flight (sim side). It homes on its target and lands after
	`duration`, so dodging isn't modelled, but a target that dies or gets
	back aboard first is spared. Damage is worked out at the loose (Rules),
	so it still lands if the archer falls meanwhile. The view draws it from
	start to aim point along an arc.
**/
class Arrow {
	public final shooterId:Int;
	public final targetId:Int;
	public final team:Int;
	public final damage:Float;
	public final duration:Float;
	public final startX:Float;
	public final startY:Float;
	public final startZ:Float;
	public var aimX:Float;
	public var aimY:Float;
	public var aimZ:Float;
	/** Seconds since it was loosed. **/
	public var t = 0.0;

	public function new(shooter:Unit, target:Unit, damage:Float, duration:Float) {
		shooterId = shooter.id;
		targetId = target.id;
		team = shooter.team;
		this.damage = damage;
		this.duration = Math.max(duration, 0.15);
		startX = shooter.x;
		startY = shooter.y;
		startZ = shooter.z;
		aimX = target.x;
		aimY = target.y;
		aimZ = target.z;
	}
}
