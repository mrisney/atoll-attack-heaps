package render;

/**
	Where grass is being pushed aside, as a texture over the island.

	Each frame every living unit stamps its footprint:
	- RG = the direction grass is pushed (away from the unit's centre),
	- B  = how hard, which decays over a few seconds, so a unit leaves a
	  parted trail that springs back up behind it,
	- A  = "a unit is right here", not decayed. The tree leaves use it to
	  open a see-through hole in the canopy over the figures.

	It's updated on the CPU (only touched texels are tracked) and uploaded
	every frame. Visual only: the sim never reads it.
**/
class Trample {
	public static inline var RES = 512;
	/** Radius of the parting around a unit, metres. **/
	public static inline var RADIUS = 0.65;
	/** Radius of the canopy see-through hole, metres. **/
	public static inline var REVEAL = 2.2;
	/** Seconds for a trampled patch to recover most of the way. **/
	public static inline var RECOVER = 2.8;

	public final texture:h3d.mat.Texture;
	public final origin:Float;
	public final span:Float;

	final px:hxd.Pixels;
	final amount:haxe.ds.Vector<Float>;
	final dirX:haxe.ds.Vector<Float>;
	final dirY:haxe.ds.Vector<Float>;
	var active:Array<Int> = [];
	final isActive:haxe.ds.Vector<Bool>;
	var revealed:Array<Int> = [];

	public function new(island:world.Island) {
		origin = -island.halfExtent;
		span = island.halfExtent * 2;
		px = hxd.Pixels.alloc(RES, RES, RGBA);
		px.clear(0x00808000); // ARGB: R=G=0.5 (no direction), B=0 (no push), A=0
		amount = new haxe.ds.Vector(RES * RES);
		dirX = new haxe.ds.Vector(RES * RES);
		dirY = new haxe.ds.Vector(RES * RES);
		isActive = new haxe.ds.Vector(RES * RES);
		for (i in 0...RES * RES) {
			amount[i] = 0;
			dirX[i] = 0;
			dirY[i] = 0;
			isActive[i] = false;
		}
		texture = new h3d.mat.Texture(RES, RES, null, RGBA);
		texture.filter = Linear;
		texture.wrap = Clamp;
		texture.uploadPixels(px);
	}

	/** Unit positions at the last upload, to skip work when nothing moved. **/
	var lastStamp:Array<Float> = [];

	/** Decay old trails, stamp the units at (x, y), upload. **/
	public function update(dt:Float, units:Array<{x:Float, y:Float}>) {
		// Optimisation: the upload is a whole 512² RGBA texture (1 MB), which matters on
		// phones. If no trail is still recovering and every unit stands exactly where it
		// was stamped last time, the map can't have changed: skip it all.
		if (active.length == 0 && units.length * 2 == lastStamp.length) {
			var same = true;
			for (k in 0...units.length)
				if (units[k].x != lastStamp[k * 2] || units[k].y != lastStamp[k * 2 + 1]) {
					same = false;
					break;
				}
			if (same) return;
		}
		lastStamp = [];
		for (u in units) {
			lastStamp.push(u.x);
			lastStamp.push(u.y);
		}
		var k = Math.exp(-dt / RECOVER * 2.3);
		// Clear last frame's reveal.
		for (i in revealed) writeA(i, 0);
		revealed = [];
		// Decay.
		var still = [];
		for (i in active) {
			var a = amount[i] * k;
			if (a < 0.01) {
				a = 0;
				isActive[i] = false;
			} else
				still.push(i);
			amount[i] = a;
			write(i);
		}
		active = still;
		// Stamp.
		var cell = span / RES;
		for (u in units) {
			var cx = (u.x - origin) / cell, cy = (u.y - origin) / cell;
			var r = RADIUS / cell;
			for (j in Std.int(cy - r - 1)...Std.int(cy + r + 2))
				for (i in Std.int(cx - r - 1)...Std.int(cx + r + 2)) {
					if (i < 0 || j < 0 || i >= RES || j >= RES) continue;
					var dx = i + 0.5 - cx, dy = j + 0.5 - cy;
					var d = Math.sqrt(dx * dx + dy * dy);
					if (d > r) continue;
					var s = 1 - (d / r) * (d / r);
					var id = j * RES + i;
					if (s > amount[id]) {
						amount[id] = s;
						var l = Math.max(d, 1e-3);
						// Right under the feet blades go flat in all directions; push outward.
						dirX[id] = dx / l;
						dirY[id] = dy / l;
					}
					if (!isActive[id]) {
						isActive[id] = true;
						active.push(id);
					}
					write(id);
				}
			var rr = REVEAL / cell;
			for (j in Std.int(cy - rr)...Std.int(cy + rr + 1))
				for (i in Std.int(cx - rr)...Std.int(cx + rr + 1)) {
					if (i < 0 || j < 0 || i >= RES || j >= RES) continue;
					var dx = i + 0.5 - cx, dy = j + 0.5 - cy;
					var d = Math.sqrt(dx * dx + dy * dy) / rr;
					if (d > 1) continue;
					var id = j * RES + i;
					var v = Std.int(Math.min(1, (1 - d) * 2.5) * 255);
					if (v > readA(id)) writeA(id, v);
					revealed.push(id);
				}
		}
		texture.uploadPixels(px);
	}

	inline function write(id:Int) {
		var a = Std.int(amount[id] * 255);
		var r = Std.int((dirX[id] * 0.5 + 0.5) * 255), g = Std.int((dirY[id] * 0.5 + 0.5) * 255);
		var p = id << 2;
		px.bytes.set(p, r);
		px.bytes.set(p + 1, g);
		px.bytes.set(p + 2, a);
	}

	inline function writeA(id:Int, v:Int)
		px.bytes.set((id << 2) + 3, v);

	inline function readA(id:Int):Int
		return px.bytes.get((id << 2) + 3);
}

/**
	Opens a see-through hole in tree canopies over the units: leaf pixels
	inside the trample map's reveal area are dithered away, so figures stay
	visible as they walk under trees.
**/
class CanopyReveal extends hxsl.Shader {
	static var SRC = {
		@param var trample:Sampler2D;
		@param var origin:Float;
		@param var span:Float;
		var transformedPosition:Vec3;
		var projectedPosition:Vec4;
		var pixelColor:Vec4;

		function fragment() {
			var reveal = trample.get((transformedPosition.xy - origin) / span).a;
			if (reveal > 0.01) {
				// Screen-space dither: keeps a lacy hint of the canopy rather than a hard hole.
				var sp = floor(projectedPosition.xy / projectedPosition.w * 400.0);
				var n = fract(sin(dot(sp, vec2(12.9898, 78.233))) * 43758.5453);
				if (n < reveal * 0.85) discard;
			}
		}
	};
}
