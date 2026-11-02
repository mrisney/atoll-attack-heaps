import game.Sim;
import input.RtsCamera;
import input.SelectionController;
import render.IslandView;
import render.IslandView.VisualStyle;
import world.Island.IslandShape;
import render.Palette;
import render.UnitView;
import world.Island;

/**
	Atoll Attack (Heaps spike): a stylized procedural atoll with two squads
	you can box-select and move. Press R for a new island.
**/
class Main extends hxd.App {
	var seed:Int;
	var island:Island;
	var sim:Sim;
	var islandView:IslandView;
	var unitViews:Array<UnitView> = [];
	var rtsCam:RtsCamera;
	var selection:SelectionController;
	var hud:h2d.Text;
	var inkRenderer:render.ink.InkRenderer;
	var controls:ui.ControlBar;
	var minimap:ui.Minimap;
	/** Size of on-screen UI relative to its design size (2 on Retina screens). **/
	var uiScale = 1.0;
	var style:VisualStyle = Classic;
	var shape:IslandShape = Single;
	/** null = follow the style's default (sprites except in Ink map). **/
	var spriteProps:Null<Bool> = null;

	override function init() {
		// Bakes res/ into the build, so the web version needs no file server for assets.
		hxd.Res.initEmbed();
		engine.backgroundColor = 0xFF2185C4;
		inkRenderer = new render.ink.InkRenderer();
		s3d.renderer = inkRenderer;
		setupLighting();
		rtsCam = new RtsCamera(s3d.camera);

		#if js
		// The 2D layer is in device pixels; scale UI up on Retina so it isn't tiny.
		uiScale = Math.max(1, js.Browser.window.devicePixelRatio);
		#end
		hud = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		hud.textColor = 0xF2EEDF;
		hud.dropShadow = {dx: 1, dy: 1, color: 0x10202A, alpha: 0.8};
		hud.setPosition(12 * uiScale, 10 * uiScale);
		hud.setScale(uiScale);

		seed = Std.int(Date.now().getTime() % 100000);
		readUrlParams();
		buildWorld();
		if (startDistance > 0) {
			rtsCam.distance = startDistance;
			rtsCam.snap();
		}
	}

	function setupLighting() {
		// Warm low sun + cool ambient: the soft "storybook" lighting.
		var ls = Std.downcast(s3d.lightSystem, h3d.scene.fwd.LightSystem);
		if (ls != null) ls.ambientLight.set(0.52, 0.56, 0.64);
		var sun = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.55, -0.35, -0.75), s3d);
		sun.color.set(0.78, 0.72, 0.6);
	}

	function buildWorld() {
		if (islandView != null) islandView.remove();
		for (v in unitViews) v.remove();
		unitViews = [];
		if (selection != null) selection.dispose();

		island = new Island(seed, shape);
		sim = new Sim(island);
		islandView = new IslandView(island, s3d);
		applyStyle();
		for (u in sim.units) unitViews.push(new UnitView(u, island.heightAt, s3d));
		// A dock at each squad's landing beach (the captains start there).
		islandView.addLandings([for (u in sim.units) if (u.kind == Captain) {x: u.x, y: u.y}]);
		selection = new SelectionController(sim, unitViews, s3d, s2d, rtsCam);
		if (controls == null) {
			controls = new ui.ControlBar(rtsCam, recenterOnSquad, s2d);
			controls.setScale(uiScale);
			minimap = new ui.Minimap(rtsCam, s2d);
			minimap.setScale(uiScale);
		}
		minimap.setIsland(island, sim.units);
		minimap.onCommand = selection.orderMoveWorld;
		selection.uiHitTest = (x, y) -> controls.hitTest(x, y) || minimap.hitTest(x, y);
		selection.onBlast = (x, y) -> islandView.decals.crater(x, y, 2.6);

		// Start looking at the blue squad's beach.
		var blue = sim.units[0];
		rtsCam.targetX = blue.x;
		rtsCam.targetY = blue.y;
		rtsCam.bounds = island.halfExtent;
		rtsCam.snap();

		updateHud();
	}

	/** Centre the camera on the selected units, or the whole blue squad if none. **/
	function recenterOnSquad() {
		var ids = selection.selectedIds();
		var sx = 0.0, sy = 0.0, n = 0;
		for (u in sim.units)
			if (u.team == selection.localTeam && (ids.length == 0 || ids.indexOf(u.id) >= 0)) {
				sx += u.x;
				sy += u.y;
				n++;
			}
		if (n == 0) return;
		rtsCam.lookAt(sx / n, sy / n);
	}

	function applyStyle() {
		islandView.setStyle(style);
		islandView.setSpriteProps(spriteProps != null ? spriteProps : style != InkMap);
		inkRenderer.inkEnabled = style == InkMap;
		inkRenderer.tiltShift = style == Painted;
		engine.backgroundColor = switch style {
			case InkMap: 0xFF6E9FB5;
			case Painted: 0xFF235F86;
			case Classic: 0xFF2185C4;
		};
		updateHud();
	}

	function updateHud() {
		hud.text = 'ATOLL ATTACK  ·  seed $seed  ·  ${shape} island  ·  ${style} style\n'
			+ 'Drag: select   Click/RMB: move   Shift: add   Minimap: click to fly, right-click to send units\n'
			+ 'Pan: right/middle-drag, trackpad swipe, WASD (Shift = fast), edges   Zoom: wheel/pinch/+ -   Q/E: rotate   Space: recentre\n'
			+ 'R: new island   G: island shape   T: visual style   I: ink lines   B: tilt-shift   P: sprite/low-poly trees   X: blast at cursor (test)';
	}

	var frames = 0;
	var startDistance = 0.0;

	/**
		Web build only: `index.html?seed=123&style=inkmap&shape=atoll&dist=80`
		makes a run reproducible — used by scripts/snapshot.mjs.
	**/
	function readUrlParams() {
		#if js
		var q = new js.html.URLSearchParams(js.Browser.location.search);
		if (q.has("seed")) seed = Std.parseInt(q.get("seed"));
		if (q.get("style") == "inkmap") style = InkMap;
		if (q.get("style") == "classic") style = Classic;
		if (q.get("style") == "painted") style = Painted;
		if (q.get("shape") == "atoll") shape = Atoll;
		if (q.get("shape") == "single") shape = Single;
		if (q.get("props") == "sprites") spriteProps = true;
		if (q.get("props") == "lowpoly") spriteProps = false;
		if (q.has("dist")) startDistance = Std.parseFloat(q.get("dist"));
		#end
	}

	override function update(dt:Float) {
		frames++;
		#if js
		// Lets automation know the game is up and rendering.
		js.Syntax.code("window.atollFrames = {0}", frames);
		#end
		if (hxd.Key.isPressed(hxd.Key.R)) {
			seed = Std.random(100000);
			buildWorld();
		}
		if (hxd.Key.isPressed(hxd.Key.I))
			inkRenderer.inkEnabled = !inkRenderer.inkEnabled;
		if (hxd.Key.isPressed(hxd.Key.SPACE))
			recenterOnSquad();
		if (hxd.Key.isDown(hxd.Key.QWERTY_EQUALS) || hxd.Key.isDown(hxd.Key.NUMPAD_ADD))
			rtsCam.zoom(Math.pow(1 / 2.2, dt));
		if (hxd.Key.isDown(hxd.Key.QWERTY_MINUS) || hxd.Key.isDown(hxd.Key.NUMPAD_SUB))
			rtsCam.zoom(Math.pow(2.2, dt));
		if (hxd.Key.isPressed(hxd.Key.T)) {
			style = switch style {
				case Classic: Painted;
				case Painted: InkMap;
				case InkMap: Classic;
			};
			applyStyle();
		}
		if (hxd.Key.isPressed(hxd.Key.P)) {
			spriteProps = !(spriteProps != null ? spriteProps : style != InkMap);
			islandView.setSpriteProps(spriteProps);
		}
		if (hxd.Key.isPressed(hxd.Key.B))
			inkRenderer.tiltShift = !inkRenderer.tiltShift;
		if (hxd.Key.isPressed(hxd.Key.G)) {
			shape = shape == Single ? Atoll : Single;
			buildWorld();
		}
		rtsCam.update(dt, selection.mouseX, selection.mouseY, s2d.width, s2d.height);
		sim.update(dt);
		islandView.update(dt);
		for (v in unitViews) v.syncFromSim(dt);
		selection.update(dt);
		controls.update(dt, s2d.width, s2d.height);
		minimap.update(s2d.width, s2d.height);
	}

	static function main() {
		new Main();
	}
}
