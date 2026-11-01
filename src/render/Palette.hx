package render;

/**
	The whole look lives here. Tweak these to push the art direction —
	a tight, slightly desaturated palette is most of the "Northgard" feel.
**/
class Palette {
	public static inline var OCEAN_DEEP = 0x1B4A6B;
	public static inline var OCEAN_MID = 0x22708E;
	public static inline var LAGOON = 0x43B8AE;
	public static inline var FOAM = 0xD8F1EA;

	public static inline var SEABED = 0x9C8A5E;
	public static inline var WET_SAND = 0xC6AE77;
	public static inline var SAND = 0xE6D29B;
	public static inline var GRASS = 0x93AE5C;
	public static inline var MEADOW = 0x7C9C4B;
	public static inline var JUNGLE = 0x4E7A3A;
	public static inline var JUNGLE_DARK = 0x3A5F2E;
	public static inline var ROCK = 0x8A8072;
	public static inline var PEAK = 0xB7AE9E;

	public static inline var TRUNK = 0x6B4A32;
	public static inline var PINE_A = 0x3F6B35;
	public static inline var PINE_B = 0x557F3E;
	public static inline var STONE = 0x9A9284;

	public static inline var TEAM_BLUE = 0x3B5F8E;
	public static inline var TEAM_RED = 0x9C4436;
	public static inline var SKIN = 0xE0B48C;
	public static inline var STEEL = 0xB9BDC2;
	public static inline var WOOD = 0x8A6440;
	public static inline var SELECT = 0xF4E27A;
	public static inline var INK = 0x1F1A15;
	public static inline var LEATHER = 0x5A4130;

	public static inline function r(c:Int):Float
		return ((c >> 16) & 0xFF) / 255;

	public static inline function g(c:Int):Float
		return ((c >> 8) & 0xFF) / 255;

	public static inline function b(c:Int):Float
		return (c & 0xFF) / 255;

	public static function mix(a:Int, b2:Int, t:Float):Int {
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		var rr = Std.int(((a >> 16) & 0xFF) * (1 - t) + ((b2 >> 16) & 0xFF) * t);
		var gg = Std.int(((a >> 8) & 0xFF) * (1 - t) + ((b2 >> 8) & 0xFF) * t);
		var bb = Std.int((a & 0xFF) * (1 - t) + (b2 & 0xFF) * t);
		return (rr << 16) | (gg << 8) | bb;
	}

	/** Terrain color by elevation band. **/
	public static function terrain(h:Float):Int {
		if (h < -5.0) return mix(OCEAN_DEEP, SEABED, (h + 8) / 3); // fades into the open sea
		if (h < -2.0) return mix(SEABED, WET_SAND, (h + 5) / 3);
		if (h < 0.15) return mix(WET_SAND, SAND, (h + 2) / 2.15);
		if (h < 0.9) return SAND;
		if (h < 1.6) return mix(SAND, GRASS, (h - 0.9) / 0.7);
		if (h < 2.4) return mix(GRASS, MEADOW, (h - 1.6) / 0.8);
		if (h < 4.4) return mix(JUNGLE, JUNGLE_DARK, (h - 2.4) / 2.0);
		if (h < 5.4) return mix(JUNGLE_DARK, ROCK, (h - 4.4) / 1.0);
		return mix(ROCK, PEAK, (h - 5.4) / 1.5);
	}

	/** Water color by depth below the surface. **/
	public static function water(depth:Float):Int {
		if (depth < 0.6) return mix(FOAM, LAGOON, depth / 0.6);
		if (depth < 3.0) return mix(LAGOON, OCEAN_MID, (depth - 0.6) / 2.4);
		return mix(OCEAN_MID, OCEAN_DEEP, (depth - 3.0) / 4.0);
	}
}
