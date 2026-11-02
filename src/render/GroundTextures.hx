package render;

/**
	Painted, tileable ground textures generated in code at startup: grass,
	dirt, sand and rock. No external assets, so there's nothing to license,
	download or ship, and they can be tweaked here like any other code.

	Each texture is 256×256 and wraps seamlessly (all noise is periodic and
	brush strokes wrap around the edges). RGB is the painted surface. Alpha
	holds an independent tileable noise that the terrain shader uses for
	large-scale variation (dirt patches, wobbly band edges) without extra
	textures.

	The style aims for hand-painted, not photographic: soft colour noise plus
	short directional brush strokes and speckles, in the same palette family
	as the rest of the game.
**/
class GroundTextures {
	public static inline var SIZE = 256;

	static var cache:Null<GroundTextures> = null;

	public final grass:h3d.mat.Texture;
	public final dirt:h3d.mat.Texture;
	public final sand:h3d.mat.Texture;
	public final rock:h3d.mat.Texture;

	/** Generated once and shared by every island. **/
	public static function get():GroundTextures {
		if (cache == null) cache = new GroundTextures();
		return cache;
	}

	function new() {
		grass = paintGrass();
		dirt = paintDirt();
		sand = paintSand();
		rock = paintRock();
	}

	// --- periodic noise -------------------------------------------------------

	static inline function hash(x:Int, y:Int, seed:Int):Float {
		var h:haxe.Int32 = seed;
		h = h + (x : haxe.Int32) * (374761393 : haxe.Int32);
		h = h + (y : haxe.Int32) * (668265263 : haxe.Int32);
		h = (h ^ (h >>> 13)) * (1274126177 : haxe.Int32);
		h = h ^ (h >>> 16);
		return (h & 0x7fffffff) / 2147483647.0;
	}

	/** Value noise that repeats every `period` lattice cells. **/
	static function pnoise(x:Float, y:Float, period:Int, seed:Int):Float {
		var xi = Math.floor(x), yi = Math.floor(y);
		var fx = x - xi, fy = y - yi;
		var u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
		inline function w(i:Int)
			return ((i % period) + period) % period;
		var x0 = w(xi), x1 = w(xi + 1), y0 = w(yi), y1 = w(yi + 1);
		var a = hash(x0, y0, seed), b = hash(x1, y0, seed);
		var c = hash(x0, y1, seed), d = hash(x1, y1, seed);
		var top = a + (b - a) * u, bot = c + (d - c) * u;
		return top + (bot - top) * v;
	}

	/** Tileable fbm over the texture: `base` lattice cells across, doubling per octave. **/
	static function fbm(px:Int, py:Int, base:Int, octaves:Int, seed:Int):Float {
		var sum = 0.0, amp = 0.5, norm = 0.0, period = base;
		for (o in 0...octaves) {
			var s = period / SIZE;
			sum += pnoise(px * s, py * s, period, seed + o * 101) * amp;
			norm += amp;
			amp *= 0.5;
			period *= 2;
		}
		return sum / norm;
	}

	// --- painting helpers -----------------------------------------------------

	static function lerpRgb(a:Int, b:Int, t:Float):Array<Float> {
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		return [
			Palette.r(a) + (Palette.r(b) - Palette.r(a)) * t,
			Palette.g(a) + (Palette.g(b) - Palette.g(a)) * t,
			Palette.b(a) + (Palette.b(b) - Palette.b(a)) * t
		];
	}

	/** A short brush stroke (wraps around edges), blended into the canvas. **/
	static function stroke(buf:Array<Float>, x:Float, y:Float, angle:Float, len:Float, width:Float, color:Int, alpha:Float) {
		var steps = Std.int(len * 2) + 1;
		var cr = Palette.r(color), cg = Palette.g(color), cb = Palette.b(color);
		var dx = Math.cos(angle), dy = Math.sin(angle);
		for (s in 0...steps) {
			var t = s / steps;
			var cx = x + dx * len * t, cy = y + dy * len * t;
			var taper = 1 - Math.abs(t - 0.5) * 1.2; // thicker in the middle
			var r = width * taper;
			var ir = Std.int(Math.ceil(r));
			for (oy in -ir...ir + 1)
				for (ox in -ir...ir + 1) {
					if (ox * ox + oy * oy > r * r) continue;
					var px = ((Std.int(cx) + ox) % SIZE + SIZE) % SIZE;
					var py = ((Std.int(cy) + oy) % SIZE + SIZE) % SIZE;
					var i = (py * SIZE + px) * 3;
					buf[i] += (cr - buf[i]) * alpha;
					buf[i + 1] += (cg - buf[i + 1]) * alpha;
					buf[i + 2] += (cb - buf[i + 2]) * alpha;
				}
		}
	}

	static function toTexture(buf:Array<Float>, alphaSeed:Int):h3d.mat.Texture {
		var px = hxd.Pixels.alloc(SIZE, SIZE, RGBA);
		inline function b(v:Float)
			return v < 0 ? 0 : (v > 1 ? 255 : Std.int(v * 255));
		for (y in 0...SIZE)
			for (x in 0...SIZE) {
				var i = (y * SIZE + x) * 3;
				// Alpha: independent large-scale noise for the shader's macro variation.
				var a = fbm(x, y, 3, 3, alphaSeed);
				px.setPixel(x, y, (b(a) << 24) | (b(buf[i]) << 16) | (b(buf[i + 1]) << 8) | b(buf[i + 2]));
			}
		var t = new h3d.mat.Texture(SIZE, SIZE, [MipMapped]);
		t.uploadPixels(px);
		t.wrap = Repeat;
		t.filter = Linear;
		t.mipMap = Linear;
		return t;
	}

	static function base(c0:Int, c1:Int, scale:Int, seed:Int):Array<Float> {
		var buf = [for (_ in 0...SIZE * SIZE * 3) 0.0];
		for (y in 0...SIZE)
			for (x in 0...SIZE) {
				var n = fbm(x, y, scale, 4, seed);
				var c = lerpRgb(c0, c1, (n - 0.3) * 2.2);
				var i = (y * SIZE + x) * 3;
				buf[i] = c[0];
				buf[i + 1] = c[1];
				buf[i + 2] = c[2];
			}
		return buf;
	}

	// --- the four materials ---------------------------------------------------

	function paintGrass():h3d.mat.Texture {
		var buf = base(0x5E8F3A, 0x8AB352, 4, 11);
		var rng = new world.Noise(12);
		// Short, mostly upright blade strokes in several greens.
		var greens = [0x4F7E33, 0x6B9C40, 0x8DB653, 0xA4C462, 0x5A8A38];
		for (k in 0...3800) {
			var x = rng.rand(k, 1) * SIZE, y = rng.rand(k, 2) * SIZE;
			var a = -Math.PI / 2 + (rng.rand(k, 3) - 0.5) * 0.9;
			stroke(buf, x, y, a, 3 + rng.rand(k, 4) * 5, 0.9, greens[k % greens.length], 0.55);
		}
		// Tiny warm specks (seed heads, dry blades).
		for (k in 0...500) {
			var x = rng.rand(k, 5) * SIZE, y = rng.rand(k, 6) * SIZE;
			stroke(buf, x, y, 0, 1, 0.8, k % 3 == 0 ? 0xD8D27A : 0xB9C268, 0.6);
		}
		return toTexture(buf, 21);
	}

	function paintDirt():h3d.mat.Texture {
		var buf = base(0x8A6A48, 0xB08B60, 5, 31);
		var rng = new world.Noise(32);
		// Darker clods and lighter pebbles.
		for (k in 0...700) {
			var x = rng.rand(k, 1) * SIZE, y = rng.rand(k, 2) * SIZE;
			stroke(buf, x, y, rng.rand(k, 3) * Math.PI, 1.5 + rng.rand(k, 4) * 3, 1.3, 0x6E5238, 0.45);
		}
		for (k in 0...450) {
			var x = rng.rand(k, 5) * SIZE, y = rng.rand(k, 6) * SIZE;
			stroke(buf, x, y, rng.rand(k, 7) * Math.PI, 1, 1.2, k % 2 == 0 ? 0xCDB58E : 0xA89A88, 0.7);
		}
		return toTexture(buf, 41);
	}

	function paintSand():h3d.mat.Texture {
		var buf = base(0xE3D2A2, 0xF2E5BF, 6, 51);
		// Gentle wind ripples: wrapped sine bands distorted by noise.
		for (y in 0...SIZE)
			for (x in 0...SIZE) {
				var d = fbm(x, y, 4, 2, 53) * 6.0;
				var rip = Math.sin((y + d * 8) / SIZE * Math.PI * 2 * 14);
				var k = 1 + rip * 0.035;
				var i = (y * SIZE + x) * 3;
				buf[i] *= k;
				buf[i + 1] *= k;
				buf[i + 2] *= k;
			}
		var rng = new world.Noise(52);
		for (k in 0...900) {
			var x = rng.rand(k, 1) * SIZE, y = rng.rand(k, 2) * SIZE;
			stroke(buf, x, y, 0, 1, 0.7, k % 4 == 0 ? 0xB8A27A : 0xFFF6DA, 0.5);
		}
		return toTexture(buf, 61);
	}

	function paintRock():h3d.mat.Texture {
		var buf = base(0x8C877E, 0xB4AEA4, 3, 71);
		// Cracks: thin dark lines where a ridged noise crosses zero.
		for (y in 0...SIZE)
			for (x in 0...SIZE) {
				var r = Math.abs(fbm(x, y, 5, 3, 73) - 0.5);
				if (r < 0.018) {
					var k = 0.72 + r * 8;
					var i = (y * SIZE + x) * 3;
					buf[i] *= k;
					buf[i + 1] *= k;
					buf[i + 2] *= k;
				}
			}
		var rng = new world.Noise(72);
		for (k in 0...600) {
			var x = rng.rand(k, 1) * SIZE, y = rng.rand(k, 2) * SIZE;
			stroke(buf, x, y, rng.rand(k, 3) * Math.PI, 2 + rng.rand(k, 4) * 4, 1.2, k % 3 == 0 ? 0xC7C1B6 : 0x7D776F, 0.35);
		}
		// A hint of lichen.
		for (k in 0...140) {
			var x = rng.rand(k, 5) * SIZE, y = rng.rand(k, 6) * SIZE;
			stroke(buf, x, y, 0, 1.5, 1.6, 0x9AA06A, 0.4);
		}
		return toTexture(buf, 81);
	}
}
