package ui;

import render.Palette;

/**
	Minimap, bottom-left: the island from above, both squads as dots, and the
	camera's current view as an outline.

	- Click or drag (left button / one finger) to fly the camera there.
	- Right-click to send the selected units there.

	North-up: world +X is right, world +Y is up.
**/
class Minimap extends h2d.Object {
	public static inline var SIZE = 168.0;
	static inline var MARGIN = 18.0;

	final camera:input.RtsCamera;
	final frame:h2d.Graphics;
	var map:Null<h2d.Bitmap> = null;
	final overlay:h2d.Graphics;
	final hit:h2d.Interactive;

	var island:Null<world.Island> = null;
	var units:Array<game.Unit> = [];
	var dragging = false;

	/** Called with a world position on right-click. **/
	public var onCommand:Null<(Float, Float) -> Void> = null;

	public function new(camera:input.RtsCamera, ?parent:h2d.Object) {
		super(parent);
		this.camera = camera;

		frame = new h2d.Graphics(this);
		frame.beginFill(0x000000, 0.22); // drop shadow
		frame.drawRoundedRect(2, 3, SIZE, SIZE, 8);
		frame.endFill();
		frame.lineStyle(2.2, Palette.INK, 1);
		frame.beginFill(Palette.PAPER, 1);
		frame.drawRoundedRect(-3, -3, SIZE + 6, SIZE + 6, 8);
		frame.endFill();

		overlay = new h2d.Graphics(this);

		hit = new h2d.Interactive(SIZE, SIZE, this);
		hit.cursor = Default;
		hit.onPush = function(e) {
			if (e.button == 1) {
				var w = toWorld(e.relX, e.relY);
				if (onCommand != null) onCommand(w.x, w.y);
				return;
			}
			dragging = true;
			flyTo(e.relX, e.relY);
		};
		hit.onMove = function(e) if (dragging) flyTo(e.relX, e.relY);
		hit.onRelease = function(_) dragging = false;
		hit.onReleaseOutside = function(_) dragging = false;
	}

	/** Rebuild the map image for a new island. **/
	var ships:Array<game.Ship> = [];

	public function setIsland(island:world.Island, units:Array<game.Unit>, ?ships:Array<game.Ship>) {
		this.ships = ships == null ? [] : ships;
		this.island = island;
		this.units = units;
		var res = 128;
		var px = hxd.Pixels.alloc(res, res, RGBA);
		var he = island.halfExtent;
		var tSand = world.Island.classicHeight(0.39), tLow = world.Island.classicHeight(0.54), tUp = world.Island.classicHeight(0.70);
		for (j in 0...res)
			for (i in 0...res) {
				var x = (i + 0.5) / res * he * 2 - he;
				var y = he - (j + 0.5) / res * he * 2; // north-up
				var h = island.heightAt(x, y);
				var c = if (h < -1.7) 0x2E6F99 else if (h < -0.8) 0x4C9BC4 else if (h < 0) 0x86C9E3 else if (h < tSand) 0xEADBA8 else
					if (h < tLow) 0x9DC266 else if (h < tUp) 0x7DA352 else 0xBDB8AE;
				px.setPixel(i, j, 0xFF000000 | c);
			}
		if (map != null) map.remove();
		var tile = h2d.Tile.fromPixels(px);
		tile.scaleToSize(SIZE, SIZE);
		map = new h2d.Bitmap(tile);
		addChildAt(map, 1);
	}

	/** True if a screen point is over the minimap (so the game ignores the click). **/
	public function hitTest(sx:Float, sy:Float):Bool {
		var b = hit.getBounds();
		return sx >= b.xMin && sx <= b.xMax && sy >= b.yMin && sy <= b.yMax;
	}

	public function update(screenW:Float, screenH:Float) {
		var s = scaleX;
		x = MARGIN * s;
		y = screenH - (MARGIN + SIZE) * s;
		if (island == null) return;

		overlay.clear();
		// Camera view footprint.
		var fp = camera.viewFootprint(screenW, screenH);
		if (fp.length >= 3) {
			overlay.lineStyle(1.6, 0xFFFFFF, 0.95);
			var first = toMap(fp[0].x, fp[0].y);
			overlay.moveTo(first.x, first.y);
			for (k in 1...fp.length + 1) {
				var p = toMap(fp[k % fp.length].x, fp[k % fp.length].y);
				overlay.lineTo(p.x, p.y);
			}
		}
		// Ships: a small hull pointing along their heading.
		overlay.lineStyle();
		for (s in ships) {
			if (s.sunk) continue;
			var c = Math.cos(s.heading), sn = Math.sin(s.heading);
			inline function pt(fx:Float, fy:Float) return toMap(s.x + c * fx - sn * fy, s.y + sn * fx + c * fy);
			var a = pt(5, 0), b = pt(-4, 2), d = pt(-4, -2);
			overlay.beginFill(Palette.INK, 1);
			overlay.moveTo(a.x, a.y);
			overlay.lineTo(b.x, b.y);
			overlay.lineTo(d.x, d.y);
			overlay.lineTo(a.x, a.y);
			overlay.endFill();
			var p = toMap(s.x, s.y);
			overlay.beginFill(s.team == 0 ? 0x5B8FD6 : 0xD66A5B, 1);
			overlay.drawCircle(p.x, p.y, 2.0, 8);
			overlay.endFill();
		}
		// Units (ashore only; the crew aboard is the ship's).
		for (u in units) {
			if (!u.alive || u.aboard >= 0) continue;
			var p = toMap(u.x, u.y);
			overlay.beginFill(Palette.INK, 1);
			overlay.drawCircle(p.x, p.y, 3.2, 8);
			overlay.endFill();
			overlay.beginFill(u.team == 0 ? 0x5B8FD6 : 0xD66A5B, 1);
			overlay.drawCircle(p.x, p.y, 2.2, 8);
			overlay.endFill();
		}
	}

	function flyTo(mx:Float, my:Float) {
		var w = toWorld(mx, my);
		camera.lookAt(w.x, w.y);
	}

	inline function extent()
		return island == null ? 60.0 : island.halfExtent;

	function toMap(wx:Float, wy:Float):{x:Float, y:Float} {
		var he = extent();
		var px = (wx + he) / (he * 2) * SIZE;
		var py = (he - wy) / (he * 2) * SIZE;
		return {x: Math.max(0, Math.min(SIZE, px)), y: Math.max(0, Math.min(SIZE, py))};
	}

	function toWorld(mx:Float, my:Float):{x:Float, y:Float} {
		var he = extent();
		return {x: mx / SIZE * he * 2 - he, y: he - my / SIZE * he * 2};
	}
}
