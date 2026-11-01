package world;

import haxe.Int32;

/**
	Seeded 2D value noise + fractal Brownian motion.

	The lattice hash uses Int32 math only, so the same seed produces the same
	island on HashLink, JS and HL/C — which matters once two players generate
	the map locally from a shared seed.
**/
class Noise {
	final seed:Int32;

	public function new(seed:Int) {
		this.seed = seed;
	}

	function hash(x:Int, y:Int):Float {
		var h:Int32 = seed;
		h = h + (x : Int32) * (374761393 : Int32);
		h = h + (y : Int32) * (668265263 : Int32);
		h = (h ^ (h >>> 13)) * (1274126177 : Int32);
		h = h ^ (h >>> 16);
		return (h & 0x7fffffff) / 2147483647.0;
	}

	/** Smooth value noise in [0,1]. **/
	public function value(x:Float, y:Float):Float {
		var xi = Math.floor(x), yi = Math.floor(y);
		var xf = x - xi, yf = y - yi;
		var u = xf * xf * (3 - 2 * xf);
		var v = yf * yf * (3 - 2 * yf);
		var a = hash(xi, yi), b = hash(xi + 1, yi);
		var c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1);
		var top = a + (b - a) * u;
		var bottom = c + (d - c) * u;
		return top + (bottom - top) * v;
	}

	/** Fractal noise in [0,1]. **/
	public function fbm(x:Float, y:Float, octaves = 4):Float {
		var sum = 0.0, amp = 0.5, freq = 1.0, norm = 0.0;
		for (_ in 0...octaves) {
			sum += value(x * freq, y * freq) * amp;
			norm += amp;
			amp *= 0.5;
			freq *= 2.0;
		}
		return sum / norm;
	}

	/** Deterministic per-cell random in [0,1] — handy for scattering props. **/
	public inline function rand(x:Int, y:Int):Float {
		return hash(x, y);
	}
}
