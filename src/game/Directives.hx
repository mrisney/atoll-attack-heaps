package game;

import game.Rules.UnitStats;
import game.Unit.UnitKind;

/**
	The characters' directives and numbers, read from res/data/directives.json
	(see that file for what each value means and why). Sim code reads
	`Directives.current`; nothing here touches Heaps: Main loads the text
	from resources, SimTest from disk.

	Built-in defaults match the file, so the sim also runs without it.
	For lockstep multiplayer every peer must load the same file.
**/
class Directives {
	public static var current = new Directives();

	public var stats:Map<String, UnitStats> = [
		"captain" => {hp: 220, damage: 12, cooldown: 0.8, reach: 1.3, defense: 20, aggro: 2.5},
		"swordsman" => {hp: 180, damage: 20, cooldown: 0.8, reach: 1.4, defense: 15, aggro: 8},
		"piker" => {hp: 165, damage: 17, cooldown: 1.0, reach: 2.4, defense: 10, aggro: 8},
		"archer" => {hp: 150, damage: 15, cooldown: 1.0, reach: 18, defense: 5, aggro: 18},
	];
	public var advantage:Map<String, Float> = [
		"swordsman>archer" => 1.3, "swordsman>captain" => 0.9, "swordsman>piker" => 0.85, "piker>swordsman" => 1.25, "archer>captain" => 1.2,
		"archer>piker" => 1.15, "archer>swordsman" => 0.8, "captain>swordsman" => 1.1,
	];
	public var captainLandsLast = true;
	public var captainStandBack = 4.0;
	public var captainEvade = 5.0;
	public var captainTakesCover = true;
	public var guardThreatRadius = 9.0;
	public var guardCallRange = 24.0;
	public var archerKite = 4.5;
	public var arrowSpeed = 24.0;
	public var leash = 16.0;
	public var flagRange = 2.5;
	public var flagTime = 5.0;
	public var flagContest = 6.0;

	public function new() {}

	public static function key(k:UnitKind):String {
		return switch k {
			case Captain: "captain";
			case Swordsman: "swordsman";
			case Piker: "piker";
			case Archer: "archer";
		}
	}

	/** Parse the JSON text and make it current. Missing values keep their defaults. **/
	public static function load(json:String) {
		var d = new Directives();
		var j:Dynamic = haxe.Json.parse(json);
		for (k in ["captain", "swordsman", "piker", "archer"]) {
			var o:Dynamic = Reflect.field(j, k);
			if (o == null) continue;
			var s = d.stats.get(k);
			d.stats.set(k, {
				hp: num(o, "hp", s.hp),
				damage: num(o, "damage", s.damage),
				cooldown: num(o, "cooldown", s.cooldown),
				reach: num(o, "reach", s.reach),
				defense: num(o, "defense", s.defense),
				aggro: num(o, "aggro", s.aggro),
			});
		}
		var cap:Dynamic = j.captain;
		if (cap != null) {
			if (Reflect.hasField(cap, "landsLast")) d.captainLandsLast = cap.landsLast == true;
			d.captainStandBack = num(cap, "standBack", d.captainStandBack);
			d.captainEvade = num(cap, "evadeRadius", d.captainEvade);
			if (Reflect.hasField(cap, "takesCover")) d.captainTakesCover = cap.takesCover == true;
		}
		var bg:Dynamic = j.bodyguard;
		if (bg != null) {
			d.guardThreatRadius = num(bg, "threatRadius", d.guardThreatRadius);
			d.guardCallRange = num(bg, "callRange", d.guardCallRange);
		}
		if (j.archer != null) d.archerKite = num(j.archer, "kiteRadius", d.archerKite);
		var c:Dynamic = j.combat;
		if (c != null) {
			d.arrowSpeed = num(c, "arrowSpeed", d.arrowSpeed);
			d.leash = num(c, "leash", d.leash);
			if (c.advantage != null)
				for (f in Reflect.fields(c.advantage))
					d.advantage.set(f, Reflect.field(c.advantage, f));
		}
		var f:Dynamic = j.flag;
		if (f != null) {
			d.flagRange = num(f, "range", d.flagRange);
			d.flagTime = num(f, "raiseTime", d.flagTime);
			d.flagContest = num(f, "contest", d.flagContest);
		}
		current = d;
	}

	static function num(o:Dynamic, f:String, def:Float):Float {
		var v:Dynamic = Reflect.field(o, f);
		return v == null ? def : (v : Float);
	}
}
