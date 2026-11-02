package render;

/**
	Open-sea waves, after Tessendorf's FFT ocean ("Simulating Ocean Water"),
	baked once at startup instead of simulated every frame, so on the GPU it's
	just texture lookups (cheap enough for phones).

	1. Build a random wave spectrum h0(k) from the Phillips spectrum for a
	   steady wind: long swell along the wind, little across it, tiny ripples
	   damped.
	2. Each wave travels at its own speed (deep-water dispersion ω = √(g·|k|)).
	   The frequencies are rounded to multiples of 2π/PERIOD, so the whole
	   field repeats exactly every PERIOD seconds. That's what lets us bake a
	   seamless loop.
	3. For FRAMES moments in that loop, inverse-FFT the spectrum into a height
	   map and its x/y slopes (64×64, tiling).
	4. Pack all frames into one atlas: R = slope x, G = slope y, B = height,
	   each normalised to 0..1. Every tile has a 1-pixel wrapped border, so
	   bilinear filtering tiles seamlessly without mipmaps.

	`WaterShader` samples it at two scales and rotations (hiding the tiling),
	blends between neighbouring frames, and uses the slopes to light the water.

	Deterministic (seeded hash), and it never touches the sim: purely visual.
**/
class OceanWaves {
	public static inline var N = 64;
	public static inline var FRAMES = 32;
	public static inline var COLS = 8;
	public static inline var ROWS = 4;
	public static inline var PAD = N + 2;
	/** Loop length in seconds. **/
	public static inline var PERIOD = 9.0;
	/** World size of one tile, in metres. **/
	public static inline var TILE = 34.0;

	static var tex:Null<h3d.mat.Texture> = null;

	public static function texture():h3d.mat.Texture {
		if (tex != null) return tex;
		var n = N, nn = N * N;
		var g = 9.81;
		var wind = 6.5; // m/s
		var wx = 0.8, wy = 0.6; // wind direction
		var Lw = wind * wind / g; // largest wave from this wind
		var damp = 0.12; // suppress the tiniest ripples (m)
		var w0 = 2 * Math.PI / PERIOD;

		// --- spectrum h0(k) and per-wave frequency ------------------------------
		var h0r = new Array<Float>(), h0i = new Array<Float>(), omega = new Array<Float>();
		var kxs = new Array<Float>(), kys = new Array<Float>();
		h0r.resize(nn);
		h0i.resize(nn);
		omega.resize(nn);
		kxs.resize(nn);
		kys.resize(nn);
		for (j in 0...n)
			for (i in 0...n) {
				var ni = i < n / 2 ? i : i - n, nj = j < n / 2 ? j : j - n;
				var kx = 2 * Math.PI * ni / TILE, ky = 2 * Math.PI * nj / TILE;
				var k = Math.sqrt(kx * kx + ky * ky);
				var id = j * n + i;
				kxs[id] = kx;
				kys[id] = ky;
				if (k < 1e-6) {
					h0r[id] = h0i[id] = omega[id] = 0;
					continue;
				}
				var kd = (kx * wx + ky * wy) / k;
				var ph = Math.exp(-1 / (k * Lw * k * Lw)) / (k * k * k * k) * kd * kd * Math.exp(-k * k * damp * damp);
				if (kd < 0) ph *= 0.25; // some waves against the wind, but fewer
				var amp = Math.sqrt(ph * 0.5);
				h0r[id] = gauss(id * 2) * amp;
				h0i[id] = gauss(id * 2 + 1) * amp;
				// Quantised dispersion → the loop is exact.
				omega[id] = Math.max(1, Math.round(Math.sqrt(g * k) / w0)) * w0;
			}

		// --- frames ---------------------------------------------------------------
		var frames:Array<{h:Array<Float>, sx:Array<Float>, sy:Array<Float>}> = [];
		var hr = new Array<Float>(), hi = new Array<Float>();
		var xr = new Array<Float>(), xi = new Array<Float>();
		var yr = new Array<Float>(), yi = new Array<Float>();
		for (a in [hr, hi, xr, xi, yr, yi]) a.resize(nn);
		var maxH = 1e-9, maxS = 1e-9;
		for (f in 0...FRAMES) {
			var t = f / FRAMES * PERIOD;
			for (j in 0...n)
				for (i in 0...n) {
					var id = j * n + i;
					var mid = ((n - j) % n) * n + (n - i) % n; // index of -k
					var c = Math.cos(omega[id] * t), s = Math.sin(omega[id] * t);
					// H = h0(k)·e^{iωt} + conj(h0(-k))·e^{-iωt}
					var ar = h0r[id] * c - h0i[id] * s, ai = h0r[id] * s + h0i[id] * c;
					// conj(h0(-k))·e^{-iωt} = conj(h0(-k)·e^{iωt})
					var br = h0r[mid] * c - h0i[mid] * s, bi = -(h0r[mid] * s + h0i[mid] * c);
					var Hr = ar + br, Hi = ai + bi;
					hr[id] = Hr;
					hi[id] = Hi;
					// Slopes: i·k·H
					xr[id] = -kxs[id] * Hi;
					xi[id] = kxs[id] * Hr;
					yr[id] = -kys[id] * Hi;
					yi[id] = kys[id] * Hr;
				}
			fft2(hr, hi, n);
			fft2(xr, xi, n);
			fft2(yr, yi, n);
			var fh = hr.copy(), fx = xr.copy(), fy = yr.copy();
			for (k in 0...nn) {
				maxH = Math.max(maxH, Math.abs(fh[k]));
				maxS = Math.max(maxS, Math.max(Math.abs(fx[k]), Math.abs(fy[k])));
			}
			frames.push({h: fh, sx: fx, sy: fy});
		}

		// --- pack into a padded atlas -------------------------------------------
		var W = COLS * PAD, H = ROWS * PAD;
		var px = hxd.Pixels.alloc(W, H, RGBA);
		inline function c8(v:Float) return Std.int(Math.max(0, Math.min(1, v)) * 255 + 0.5);
		for (f in 0...FRAMES) {
			var fr = frames[f];
			var ox = (f % COLS) * PAD, oy = Std.int(f / COLS) * PAD;
			for (y in 0...PAD)
				for (x in 0...PAD) {
					var sx = (x - 1 + n) % n, sy = (y - 1 + n) % n;
					var id = sy * n + sx;
					var r = fr.sx[id] / maxS * 0.5 + 0.5;
					var gg = fr.sy[id] / maxS * 0.5 + 0.5;
					var b = fr.h[id] / maxH * 0.5 + 0.5;
					px.setPixel(ox + x, oy + y, 0xFF000000 | (c8(r) << 16) | (c8(gg) << 8) | c8(b));
				}
		}
		var t = h3d.mat.Texture.fromPixels(px);
		t.filter = Linear;
		t.mipMap = None;
		t.wrap = Clamp;
		tex = t;
		return t;
	}

	/** In-place 2D FFT (sign +, unnormalised): rows, then columns. **/
	static function fft2(re:Array<Float>, im:Array<Float>, n:Int) {
		var tr = new Array<Float>(), ti = new Array<Float>();
		tr.resize(n);
		ti.resize(n);
		for (row in 0...n) {
			for (i in 0...n) {
				tr[i] = re[row * n + i];
				ti[i] = im[row * n + i];
			}
			fft1(tr, ti, n);
			for (i in 0...n) {
				re[row * n + i] = tr[i];
				im[row * n + i] = ti[i];
			}
		}
		for (col in 0...n) {
			for (i in 0...n) {
				tr[i] = re[i * n + col];
				ti[i] = im[i * n + col];
			}
			fft1(tr, ti, n);
			for (i in 0...n) {
				re[i * n + col] = tr[i];
				im[i * n + col] = ti[i];
			}
		}
	}

	/** Iterative radix-2 FFT with a + sign (an inverse transform without the 1/n). **/
	static function fft1(re:Array<Float>, im:Array<Float>, n:Int) {
		// Bit-reversal permutation.
		var j = 0;
		for (i in 1...n) {
			var bit = n >> 1;
			while (j & bit != 0) {
				j ^= bit;
				bit >>= 1;
			}
			j ^= bit;
			if (i < j) {
				var t = re[i];
				re[i] = re[j];
				re[j] = t;
				t = im[i];
				im[i] = im[j];
				im[j] = t;
			}
		}
		var len = 2;
		while (len <= n) {
			var ang = 2 * Math.PI / len;
			var wr = Math.cos(ang), wi = Math.sin(ang);
			var i = 0;
			while (i < n) {
				var cr = 1.0, ci = 0.0;
				for (k in 0...len >> 1) {
					var a = i + k, b = a + (len >> 1);
					var xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
					re[b] = re[a] - xr;
					im[b] = im[a] - xi;
					re[a] += xr;
					im[a] += xi;
					var nr = cr * wr - ci * wi;
					ci = cr * wi + ci * wr;
					cr = nr;
				}
				i += len;
			}
			len <<= 1;
		}
	}

	/** Standard normal sample from a seeded hash (Box-Muller). **/
	static function gauss(n:Int):Float {
		var u1 = Math.max(1e-7, hash(n * 2 + 11)), u2 = hash(n * 2 + 12);
		return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
	}

	static function hash(n:Int):Float {
		var h:haxe.Int32 = n * 374761393 + 668265263;
		h = (h ^ (h >>> 13)) * 1274126177;
		h = h ^ (h >>> 16);
		return (h & 0xffffff) / 16777215.0;
	}
}
