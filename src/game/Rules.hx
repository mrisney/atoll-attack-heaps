package game;

import game.Unit.UnitKind;

/**
	Unit stats and combat numbers, in one place so balance is easy to tune.

	The numbers themselves live in res/data/directives.json (game/Directives).
	Ported from the Flutter game's rules (lib/rules/combat_rules.dart,
	lib/models/unit_model.dart, lib/constants/game_config.dart) and rescaled
	from its pixels to metres (about 0.3 m per pixel): archers reach ~18 m,
	melee is arm's length, the flag is raised within 2.5 m of the apex for
	5 s. Pikers are new here: melee with reach, good against swordsmen.

	The matchups are a loose rock-paper-scissors: swordsmen beat archers
	(they close the distance), pikers beat swordsmen (reach), archers beat
	pikers and captains (slow, exposed), and shields blunt arrows.
**/
typedef UnitStats = {
	var hp:Float;
	var damage:Float;
	/** Seconds between attacks. **/
	var cooldown:Float;
	/** How far it can hit (m). **/
	var reach:Float;
	/** Percent damage reduction (capped at 50%). **/
	var defense:Float;
	/** How close an enemy has to come before this unit takes it on by itself (m). **/
	var aggro:Float;
}

class Rules {
	// All numbers come from res/data/directives.json (game/Directives.hx).
	public static var ARCHER_KITE(get, never):Float;
	public static var ARROW_SPEED(get, never):Float;
	public static var FLAG_RANGE(get, never):Float;
	public static var FLAG_TIME(get, never):Float;
	public static var FLAG_CONTEST(get, never):Float;
	public static var LEASH(get, never):Float;

	static inline function get_ARCHER_KITE() return Directives.current.archerKite;
	static inline function get_ARROW_SPEED() return Directives.current.arrowSpeed;
	static inline function get_FLAG_RANGE() return Directives.current.flagRange;
	static inline function get_FLAG_TIME() return Directives.current.flagTime;
	static inline function get_FLAG_CONTEST() return Directives.current.flagContest;
	static inline function get_LEASH() return Directives.current.leash;

	public static inline function stats(kind:UnitKind):UnitStats
		return Directives.current.stats.get(Directives.key(kind));

	/** Type advantage: attacker vs defender (1.0 unless the directives say otherwise). **/
	public static function advantage(a:UnitKind, d:UnitKind):Float {
		var v = Directives.current.advantage.get(Directives.key(a) + ">" + Directives.key(d));
		return v == null ? 1.0 : v;
	}

	public static function damage(a:Unit, d:Unit, melee:Bool):Float {
		var s = stats(a.kind);
		var dmg = s.damage * advantage(a.kind, d.kind);
		// An archer caught in melee only has a knife.
		if (a.kind == Archer && melee) dmg *= 0.4;
		var def = Math.min(stats(d.kind).defense / 100, 0.5);
		return dmg * (1 - def);
	}

	/** How attractive a target is (higher = better): close, hurt, and valuable. **/
	public static function targetScore(a:Unit, t:Unit, dist:Float):Float {
		var score = -dist * 2;
		score += (1 - t.hp / stats(t.kind).hp) * 6;
		score += (advantage(a.kind, t.kind) - 1) * 20;
		if (t.kind == Captain) score += 4;
		return score;
	}
}
