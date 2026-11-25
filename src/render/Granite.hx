package render;

/**
	Granite for the summit's dome (render/QuarryView). The owner found the
	dome too patterned with the shared rock texture: its painted crack
	network repeats every couple of metres and read "like a peanut shell".

	Granite is grain, not cracks: a fine speckle of crystals (dark biotite,
	white quartz, a few warm feldspars) over grey, and a slow mottle of
	lighter and darker patches. Two textures painted in code, both tileable
	(speckles wrap round the edges), sampled triplanar at two unrelated
	scales (`GraniteShader`) so neither repeat lines up with the other. The
	big cracks are real geometry (QuarryView's fissures), not texture.
**/
class Granite {
	static var cached:Null<Granite> = null;

	public final grain:h3d.mat.Texture;
	public final mottle:h3d.mat.Texture;

	public static function get():Granite {
		if (cached == null) cached = new Granite();
		return cached;
	}

	function new() {
		grain = paintGrain(256);
		mottle = paintMottle(128);
	}

	/** A little LCG: repeatable, render-side only (never used by the sim). **/
	static var state = 1;

	static inline function rnd():Float {
		state = (state * 1103515 + 12345) & 0x7fffffff;
		return state / 0x7fffffff;
	}

	static function toTexture(n:Int, buf:Array<Float>):h3d.mat.Texture {
		var px = hxd.Pixels.alloc(n, n, RGBA);
		inline function b(v:Float)
			return v < 0 ? 0 : (v > 1 ? 255 : Std.int(v * 255));
		for (y in 0...n)
			for (x in 0...n) {
				var i = (y * n + x) * 3;
				px.setPixel(x, y, (255 << 24) | (b(buf[i]) << 16) | (b(buf[i + 1]) << 8) | b(buf[i + 2]));
			}
		var t = new h3d.mat.Texture(n, n, [MipMapped]);
		t.uploadPixels(px);
		t.wrap = Repeat;
		t.filter = Linear;
		t.mipMap = Linear;
		return t;
	}

	/** Stamp a soft disc of colour, wrapping round the edges (so the tile repeats seamlessly). **/
	static function stamp(buf:Array<Float>, n:Int, cx:Float, cy:Float, r:Float, c:Array<Float>, a:Float) {
		var ri = Std.int(Math.ceil(r + 1));
		for (dy in -ri...ri + 1)
			for (dx in -ri...ri + 1) {
				var d = Math.sqrt(dx * dx + dy * dy) / r;
				if (d > 1) continue;
				var w = a * (1 - d * d);
				var x = ((Std.int(cx) + dx) % n + n) % n, y = ((Std.int(cy) + dy) % n + n) % n;
				var i = (y * n + x) * 3;
				for (k in 0...3) buf[i + k] += (c[k] - buf[i + k]) * w;
			}
	}

	static function paintGrain(n:Int):h3d.mat.Texture {
		state = 9157;
		var buf = [];
		// Grey ground mass with a per-pixel grain.
		for (_ in 0...n * n) {
			var g = 0.6 + (rnd() - 0.5) * 0.08;
			buf.push(g);
			buf.push(g * 0.995);
			buf.push(g * 0.985);
		}
		// Crystals: many small dark flecks, fewer white and warm ones, some clustered.
		for (_ in 0...2600) stamp(buf, n, rnd() * n, rnd() * n, 0.7 + rnd() * 1.3, [0.2, 0.2, 0.21], 0.85);
		for (_ in 0...1500) stamp(buf, n, rnd() * n, rnd() * n, 0.8 + rnd() * 1.8, [0.86, 0.85, 0.82], 0.7);
		for (_ in 0...260) stamp(buf, n, rnd() * n, rnd() * n, 1.0 + rnd() * 2.0, [0.74, 0.64, 0.58], 0.55);
		return toTexture(n, buf);
	}

	static function paintMottle(n:Int):h3d.mat.Texture {
		state = 3301;
		var buf = [for (_ in 0...n * n * 3) 0.6];
		// Big soft patches, a little lighter or darker, a little warmer or cooler.
		for (_ in 0...140) {
			var v = 0.6 + (rnd() - 0.5) * 0.34;
			var warm = (rnd() - 0.5) * 0.03;
			stamp(buf, n, rnd() * n, rnd() * n, 6 + rnd() * 16, [v + warm, v, v - warm], 0.35);
		}
		return toTexture(n, buf);
	}
}

/**
	Triplanar granite: fine crystal grain times a slow mottle, multiplied
	into the vertex colour (which carries the streaks, lichen and shading).
**/
class GraniteShader extends hxsl.Shader {
	static var SRC = {
		@param var grain:Sampler2D;
		@param var mottle:Sampler2D;
		/** Metres per tile of grain and of mottle (unrelated, so they never line up). **/
		@param var grainScale:Float;
		@param var mottleScale:Float;
		@param var strength:Float;
		var transformedPosition:Vec3;
		var transformedNormal:Vec3;
		var pixelColor:Vec4;

		function fragment() {
			var n = abs(normalize(transformedNormal));
			var w = n * n * n * n;
			w /= (w.x + w.y + w.z);
			var p = transformedPosition / grainScale;
			var g = grain.get(p.yz).rgb * w.x + grain.get(p.xz).rgb * w.y + grain.get(p.xy).rgb * w.z;
			var q = transformedPosition / mottleScale;
			var m = mottle.get(q.yz).rgb * w.x + mottle.get(q.xz).rgb * w.y + mottle.get(q.xy).rgb * w.z;
			// Both average about 0.6: normalise so the vertex tint stays the tint.
			pixelColor.rgb *= mix(vec3(1.0), g * m * 2.78, strength);
		}
	};

	public function new() {
		super();
		grainScale = 1.37;
		mottleScale = 11.3;
		strength = 0.9;
	}
}
