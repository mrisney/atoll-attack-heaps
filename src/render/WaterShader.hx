package render;

/**
	Water: the atoll-attack look — three hard-edged depth bands (shallows,
	mid, deep) read from a heightmap of the island — plus a gentle swell and
	a little shimmer so it stays alive in 3D.
**/
class WaterShader extends hxsl.Shader {
	static var SRC = {
		@global var global:{
			var time:Float;
			@perObject var modelView:Mat4;
		};

		@param var amplitude:Float;
		@param var shimmer:Float;

		@param var heightMap:Sampler2D;
		@param var mapOrigin:Vec2;
		@param var mapSize:Float;
		@param var heightRange:Float;

		@param var shallow:Vec3;
		@param var mid:Vec3;
		@param var deep:Vec3;
		@param var tShallow:Float;
		@param var tMid:Float;

		var relativePosition:Vec3;
		var transformedPosition:Vec3;
		var pixelColor:Vec4;

		function vertex() {
			var p = relativePosition * global.modelView.mat3x4();
			var t = global.time;
			p.z += (sin(p.x * 0.35 + t * 1.1) + cos(p.y * 0.28 + t * 0.9)) * amplitude;
			transformedPosition = p;
		}

		function fragment() {
			var uv = (transformedPosition.xy - mapOrigin) / mapSize;
			var inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
			var h = (heightMap.get(uv).r * 2.0 - 1.0) * heightRange;
			var depth = mix(heightRange, -h, inside);

			var aa = max(fwidth(depth), 0.0001);
			var c = mix(shallow, mid, smoothstep(tShallow - aa, tShallow + aa, depth));
			c = mix(c, deep, smoothstep(tMid - aa, tMid + aa, depth));

			var t = global.time;
			var s = sin(transformedPosition.x * 0.9 + t * 1.7) * sin(transformedPosition.y * 0.8 - t * 1.3);
			pixelColor.rgb = c + vec3(shimmer * s);
			pixelColor.a = 1.0;
		}
	};

	public function new(amplitude = 0.04, shimmer = 0.018) {
		super();
		this.amplitude = amplitude;
		this.shimmer = shimmer;
		heightRange = 10.0;
		setClassicColors();
		// Same elevation thresholds as the original shader (0.25 and 0.18).
		tShallow = -world.Island.classicHeight(0.25);
		tMid = -world.Island.classicHeight(0.18);
	}

	public function setClassicColors() {
		TerrainStyle.setColor(shallow, 0x87D1FA);
		TerrainStyle.setColor(mid, 0x4AABE8);
		TerrainStyle.setColor(deep, 0x2185C4);
	}

	/** Muted, nautical-chart tones for the ink style. **/
	public function setChartColors() {
		TerrainStyle.setColor(shallow, 0xC9E3E2);
		TerrainStyle.setColor(mid, 0x9CC6CF);
		TerrainStyle.setColor(deep, 0x6E9FB5);
	}

	/** Bake the island's heights into a texture the water can sample. **/
	public function setIsland(island:world.Island) {
		var w = island.size + 1;
		var px = hxd.Pixels.alloc(w, w, RGBA);
		for (j in 0...w)
			for (i in 0...w) {
				var h = island.heightAtVertex(i, j) / heightRange;
				if (h < -1) h = -1;
				if (h > 1) h = 1;
				var v = Std.int((h * 0.5 + 0.5) * 255 + 0.5);
				px.setPixel(i, j, 0xFF000000 | (v << 16) | (v << 8) | v);
			}
		if (heightMap != null) heightMap.dispose();
		heightMap = h3d.mat.Texture.fromPixels(px);
		heightMap.filter = Linear;
		heightMap.wrap = Clamp;
		mapOrigin.set(-island.halfExtent, -island.halfExtent);
		mapSize = island.size * island.cell;
	}
}
