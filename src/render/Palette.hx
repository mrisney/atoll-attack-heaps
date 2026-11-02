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
	public static inline var SAND = 0xEEDFB4;
	public static inline var GRASS = 0xA9BF78;
	public static inline var MEADOW = 0x98B26C;
	public static inline var JUNGLE = 0x7F9E62;
	public static inline var JUNGLE_DARK = 0x6C8B55;
	public static inline var ROCK = 0x8A8072;
	public static inline var PEAK = 0xB7AE9E;

	public static inline var TRUNK = 0x8C6A4E;
	public static inline var PINE_A = 0x6F9157;
	public static inline var PINE_B = 0x86A66A;
	public static inline var STONE = 0xC4BCAE;

	// Prop variety: each instance picks from a list, then gets a small tint.
	public static final LEAF = [0x5C8A3C, 0x6A9A45, 0x77A64D, 0x86B055, 0x9AB352];
	public static final LEAF_AUTUMN = [0xB2A24A, 0xB89048, 0xA88448];
	public static final PINE = [0x3F6E45, 0x4A7A4C, 0x557F48, 0x5F8A52];
	public static final PALM = [0x6FA04A, 0x7EAE52, 0x8BB85A];
	// Wind-blown grass fields (GrassField): darker at the root, sunlit tips, some dry blades.
	public static inline var GRASS_BLADE_BASE = 0x6B9A3A;
	public static inline var GRASS_BLADE_TIP = 0xC3DA7E;
	public static inline var GRASS_BLADE_DRY = 0xC9B873;
	public static final GRASS_TUFT = [0x8FBF4E, 0x9DC757, 0xA9C25E, 0xB7C96A];
	public static final BARK = [0x7A5B42, 0x8C6A4E, 0x6B5040];
	public static final PALM_BARK = [0xA08560, 0x92785A];
	public static final ROCKS = [0xA39C90, 0x938C82, 0xB0A99D, 0x877F75];
	public static inline var DRIFTWOOD = 0xC8B79A;
	public static final FLOWERS = [0xF4F1E6, 0xF2D65C, 0xE9B8C4, 0xC9B6E4, 0xF6E9A8];
	public static final SHELLS = [0xF3E6D6, 0xEBD2C0, 0xF7F0E4];
	public static inline var COCONUT = 0x6E5236;

	/** Shadow tint: cool and light, so shade reads as colour rather than black. **/
	public static inline var SHADOW = 0x6A7390;

	/** Multiply a colour's brightness. **/
	public static function shade(c:Int, k:Float):Int {
		inline function ch(v:Int) {
			var x = Std.int(v * k);
			return x < 0 ? 0 : (x > 255 ? 255 : x);
		}
		return (ch((c >> 16) & 0xFF) << 16) | (ch((c >> 8) & 0xFF) << 8) | ch(c & 0xFF);
	}

	public static inline var TEAM_BLUE = 0x3B5F8E;
	public static inline var TEAM_RED = 0x9C4436;
	public static inline var SKIN = 0xE0B48C;
	public static inline var STEEL = 0xB9BDC2;
	public static inline var WOOD = 0x8A6440;
	public static inline var SELECT = 0xF4E27A;
	public static inline var INK = 0x1F1A15;
	public static inline var LEATHER = 0x5A4130;

	// Line-art figures: paper fill, team shown on the tunic and banner.
	public static inline var PAPER = 0xF6F3EC;
	public static inline var CLOTH_BLUE = 0xC5D3E6;
	public static inline var CLOTH_RED = 0xEBC9C1;

	// Sketch style (architectural presentation drawing).
	/** The page: a cool, slightly warm off-white. **/
	public static inline var SKETCH_PAPER = 0xEDECE8;
	/** Background beyond the page: a touch greyer, so the island floats on it. **/
	public static inline var SKETCH_BG = 0xE2E2DF;
	public static inline var SKETCH_GRAPHITE = 0x2E2D2B;
	/** Shadows go neutral grey on paper (the other styles tint them cool). **/
	public static inline var SKETCH_SHADOW = 0x857C70;
	/** Warm bias for the muted colour that Sketch keeps (pulls green to olive, blue to slate). **/
	public static inline var SKETCH_EARTH = 0xFFF0D2;
	/** Drafting lines and annotation text. **/
	public static inline var SKETCH_LINE = 0x3A3936;
	/** The one warm material: timber. **/
	public static inline var SKETCH_TIMBER = 0xB8773A;

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
