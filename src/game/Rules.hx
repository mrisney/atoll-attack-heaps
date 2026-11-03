package game;

import game.Unit.UnitKind;

/**
	Unit stats and combat numbers, in one place so balance is easy to tune.

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
	public static inline var ARCHER_RANGE = 18.0;
	/** Archers step back when melee enemies come this close (m). **/
	public static inline var ARCHER_KITE = 4.5;
	/** Arrow speed (m/s): arrows are projectiles, so a fast target can outrun one. **/
	public static inline var ARROW_SPEED = 24.0;
	/** Captains raise the flag standing within this distance of the apex (m)... **/
	public static inline var FLAG_RANGE = 2.5;
	/** ...for this long (s)... **/
	public static inline var FLAG_TIME = 5.0;
	/** ...unless an enemy is this close to the apex (it pauses). **/
	public static inline var FLAG_CONTEST = 6.0;
	/** A unit gives up a chase when its target gets this far away (m). **/
	public static inline var LEASH = 16.0;

	public static function stats(kind:UnitKind):UnitStats {
		return switch kind {
			// Health is 1.5x the Flutter game's: at its numbers a skirmish was over in seconds,
			// too fast to manoeuvre a small band.
			// The captain is sturdier: losing him loses the game, and in early tests archers
			// sniped him within half a minute every time.
			case Captain: {hp: 220, damage: 12, cooldown: 0.8, reach: 1.3, defense: 20, aggro: 2.5};
			case Swordsman: {hp: 180, damage: 20, cooldown: 0.8, reach: 1.4, defense: 15, aggro: 8};
			case Piker: {hp: 165, damage: 17, cooldown: 1.0, reach: 2.4, defense: 10, aggro: 8};
			case Archer: {hp: 150, damage: 15, cooldown: 1.0, reach: ARCHER_RANGE, defense: 5, aggro: ARCHER_RANGE};
		}
	}

	/** Type advantage: attacker vs defender. **/
	public static function advantage(a:UnitKind, d:UnitKind):Float {
		return switch [a, d] {
			case [Swordsman, Archer]: 1.3;
			case [Swordsman, Captain]: 0.9;
			case [Swordsman, Piker]: 0.85;
			case [Piker, Swordsman]: 1.25;
			case [Archer, Captain]: 1.2;
			case [Archer, Piker]: 1.15;
			case [Archer, Swordsman]: 0.8; // shields
			case [Captain, Swordsman]: 1.1;
			default: 1.0;
		}
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
