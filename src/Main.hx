import game.Sim;
import input.RtsCamera;
import input.SelectionController;
import render.IslandView;
import render.IslandView.VisualStyle;
import world.Island.IslandShape;
import render.Palette;
import render.UnitView;
import render.GrassField;
import render.TerrainStyle;
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
	var shipViews:Array<render.ShipView> = [];
	var arrowsView:Null<render.ArrowsView>;
	var cannonView:Null<render.CannonView>;
	var flagView:Null<render.FlagView>;
	var battle:Null<ui.BattleOverlay>;
	var rtsCam:RtsCamera;
	var selection:SelectionController;
	var hud:h2d.Text;
	var inkRenderer:render.ink.InkRenderer;
	var controls:ui.ControlBar;
	var minimap:ui.Minimap;
	var drafting:ui.DraftingOverlay;
	/** Size of on-screen UI relative to its design size (2 on Retina screens). **/
	var uiScale = 1.0;
	var style:VisualStyle = Painted;
	/**
		null = the style's own weather (Ink map sunny, Painted rain; Sketch has
		none: the owner wanted the drawing left as it was); C cycles.
	**/
	var weather:Null<render.Weather> = null;

	function currentWeather():Null<render.Weather>
		return weather != null ? weather : switch style {
			case InkMap: Sunny;
			case Painted: Rain;
			case Sketch: null;
		};
	var shape:IslandShape = Single;
	/** Tree look: null = default (3D); 0 = 3D, 1 = sprites, 2 = low-poly. P cycles. **/
	var treeMode:Null<Int> = null;

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
		hud.setPosition(24 * uiScale, 20 * uiScale);
		hud.setScale(uiScale);

		seed = Std.int(Date.now().getTime() % 100000);
		readUrlParams();
		buildWorld();
		if (startAt != null) {
			rtsCam.targetX = startAt.x;
			rtsCam.targetY = startAt.y;
			rtsCam.snap();
		}
		if (startDistance > 0) {
			rtsCam.distance = startDistance;
			rtsCam.snap();
		}
	}

	function setupLighting() {
		// Warm low sun + cool ambient: the soft "storybook" lighting.
		var ls = Std.downcast(s3d.lightSystem, h3d.scene.fwd.LightSystem);
		if (ls != null) ls.ambientLight.set(0.52, 0.56, 0.64);
		var sun = new h3d.scene.fwd.DirLight(new h3d.Vector(-TerrainStyle.SUN.x, -TerrainStyle.SUN.y, -TerrainStyle.SUN.z), s3d);
		sun.color.set(0.78, 0.72, 0.6);
	}

	function buildWorld() {
		if (islandView != null) islandView.remove();
		for (v in unitViews) v.remove();
		unitViews = [];
		for (v in shipViews) v.remove();
		shipViews = [];
		if (arrowsView != null) arrowsView.remove();
		if (cannonView != null) cannonView.remove();
		if (flagView != null) flagView.remove();
		if (selection != null) selection.dispose();

		island = new Island(seed, shape);
		// The characters' directives and numbers (res/data/directives.json).
		game.Directives.load(hxd.Res.load("data/directives.json").toText());
		sim = new Sim(island, navalTest);
		islandView = new IslandView(island, s3d);
		applyStyle();
		for (u in sim.units) unitViews.push(new UnitView(u, island.heightAt, s3d));
		for (s in sim.ships) shipViews.push(new render.ShipView(s, s3d));
		arrowsView = new render.ArrowsView(sim, s3d);
		cannonView = new render.CannonView(sim, islandView.decals, s3d);
		flagView = new render.FlagView(sim, s3d);
		// A dock at each side's home beach (where its ship lies off at the start).
		var docks = islandView.addLandings(sim.homeBeach);
		selection = new SelectionController(sim, unitViews, s3d, s2d, rtsCam);
		selection.ships = shipViews;
		selection.anyTeamShips = navalTest;
		// Debug (?autoland=1): land the blue crew at its home beach straight away.
		if (autoLand) sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[0].x, sim.homeBeach[0].y));
		// Debug (?blueai=1): a computer commander for blue too, to watch AI vs AI.
		if (blueAI) sim.teamAIs.push(new game.TeamAI(sim, 0));
		bombardSent = false;
		if (controls == null) {
			drafting = new ui.DraftingOverlay(s3d.camera, rtsCam);
			s2d.addChildAt(drafting, 0);
			drafting.ui = uiScale;
			controls = new ui.ControlBar(rtsCam, recenterOnSquad, s2d);
			controls.setScale(uiScale);
			minimap = new ui.Minimap(rtsCam, s2d);
			minimap.setScale(uiScale);
			battle = new ui.BattleOverlay(s2d);
			battle.ui = uiScale;
		}
		// The naval test shows more sea round the island (the ships start out past its edge).
		minimap.range = navalTest ? 1.4 : 1.0;
		minimap.setIsland(island, sim.units, sim.ships);
		drafting.setIsland(island, [
			for (k in 0...docks.length)
				{x: docks[k].x, y: docks[k].y, label: 'LANDING ' + (k == 0 ? "A  -  BLUE" : "B  -  RED")}
		]);
		drafting.visible = style == Sketch;
		selection.onOrder = drafting.addDimension;
		minimap.onCommand = selection.orderMoveWorld;
		minimap.shipsOnly = () -> selection.selectedShip() != null && selection.selectedIds().length == 0;
		selection.uiHitTest = (x, y) -> controls.hitTest(x, y) || minimap.hitTest(x, y);
		selection.onBlast = (x, y) -> islandView.decals.crater(x, y, 2.6);

		// Start looking at the blue ship, with its home beach in view.
		var blue = sim.ships[0];
		rtsCam.targetX = blue.x * 0.7 + sim.homeBeach[0].x * 0.3;
		rtsCam.targetY = blue.y * 0.7 + sim.homeBeach[0].y * 0.3;
		rtsCam.bounds = island.halfExtent;
		if (navalTest) {
			// Between the two ships, out at sea, with room to sail about.
			var red = sim.ships[1];
			rtsCam.targetX = (blue.x + red.x) / 2;
			rtsCam.targetY = (blue.y + red.y) / 2;
			rtsCam.bounds = island.halfExtent * 1.6;
			rtsCam.distance = Math.max(rtsCam.distance, 85);
		}
		rtsCam.snap();

		// Again now that the 2D UI exists (the minimap filter and overlay depend on the style).
		applyStyle();
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
		islandView.setTreeMode(currentTreeMode());
		islandView.setWeather(currentWeather());
		inkRenderer.setWeather(currentWeather());
		inkRenderer.inkEnabled = style == InkMap || style == Sketch;
		inkRenderer.tiltShift = style == Painted;
		inkRenderer.grade = style == Painted;
		inkRenderer.paperFade = style == Sketch ? 1 : 0;
		inkRenderer.setShadowTint(style == Sketch ? Palette.SKETCH_SHADOW : Palette.SHADOW);
		// Ink map's outlines are softer since it moved onto 3D trees: full-strength ink around
		// every leaf card made the canopies scribbly and dark.
		inkRenderer.inkStrength = style == Sketch ? 0.62 : 0.4;
		if (drafting != null) drafting.visible = style == Sketch;
		if (minimap != null) {
			// The minimap is muted to match the island's earth tones.
			var m = new h3d.Matrix();
			m.identity();
			m.colorSaturate(-0.65);
			minimap.filter = style == Sketch ? new h2d.filter.ColorMatrix(m) : null;
		}
		// Dark notes on paper in Sketch; light text with a shadow over the sea otherwise.
		hud.textColor = style == Sketch ? Palette.SKETCH_LINE : 0xF2EEDF;
		hud.dropShadow = style == Sketch ? null : {dx: 1, dy: 1, color: 0x10202A, alpha: 0.8};
		hud.alpha = style == Sketch ? 0.75 : 1;
		engine.backgroundColor = switch style {
			case Sketch: 0xFF000000 | Palette.SKETCH_BG;
			case InkMap: 0xFF235F86;
			case Painted: 0xFF235F86;
		};
		updateHud();
	}

	function currentTreeMode():Int
		return treeMode != null ? treeMode : 0;

	function updateHud() {
		hud.text = 'ATOLL ATTACK  ·  seed $seed  ·  ${shape} island  ·  ${style} style  ${currentWeather() == null ? "" : "  ·  " + currentWeather()}\n'
			+ 'Drag: select   Click/RMB: move   Shift: add   Minimap: click to fly, right-click to send units\n'
			+ 'Pan: right/middle-drag, trackpad swipe, WASD (Shift = fast), edges   Zoom: wheel/pinch/+ -   Q/E: rotate   Space: recentre\n'
			+ 'R: new island   G: island shape   T: visual style   I: ink lines   B: tilt-shift   P: trees (3D / sprite / low-poly)   C: weather   X: blast at cursor (test)'
			+ (navalTest ? '\nNAVAL TEST   1: blue ship   2: red ship   (or click a ship; Shift adds)   click the sea or the minimap to sail   guns fire by themselves off the broadsides' : '');
	}

	var frames = 0;
	var startDistance = 0.0;
	/** `?at=x,y`: start the camera looking at this world point (for reproducible shots). **/
	var startAt:Null<{x:Float, y:Float}> = null;
	var galleryWanted = false;
	var autoLand = false;
	var blueAI = false;
	/** Debug (?bombard=1): once blue is ashore its ship sails round to shell red's beach. **/
	var bombard = false;
	var bombardSent = false;
	/** Test (?naval=1): both ships out at sea, both yours to sail, nobody lands. **/
	var navalTest = false;
	var lastStamp = -1.0;

	/**
		Web build only: `index.html?seed=123&style=inkmap&shape=atoll&dist=80`
		makes a run reproducible — used by scripts/snapshot.mjs.
	**/
	function readUrlParams() {
		#if js
		var q = new js.html.URLSearchParams(js.Browser.location.search);
		if (q.has("seed")) seed = Std.parseInt(q.get("seed"));
		if (q.get("style") == "inkmap") style = InkMap;
		if (q.get("style") == "classic") style = Painted; // retired; old links still open
		if (q.get("style") == "painted") style = Painted;
		if (q.get("style") == "sketch") style = Sketch;
		if (q.get("weather") == "sunny") weather = Sunny;
		if (q.get("weather") == "fog") weather = Fog;
		if (q.get("weather") == "rain") weather = Rain;
		if (q.get("shape") == "atoll") shape = Atoll;
		if (q.get("shape") == "single") shape = Single;
		if (q.get("props") == "proc" || q.get("trees") == "proc") treeMode = 0;
		if (q.get("props") == "sprites" || q.get("trees") == "sprites") treeMode = 1;
		if (q.get("props") == "lowpoly" || q.get("trees") == "lowpoly") treeMode = 2;
		if (q.has("dist")) startDistance = Std.parseFloat(q.get("dist"));
		// Grass budget, like terra's BLADES / DEPTH settings.
		if (q.get("figures") == "rigged") UnitView.rigged = true;
		galleryWanted = q.has("gallery");
		autoLand = q.has("autoland");
		blueAI = q.has("blueai");
		bombard = q.has("bombard");
		navalTest = q.has("naval");
		if (q.has("catchup")) Sim.maxCatchUp = Std.parseFloat(q.get("catchup"));
		if (q.has("blades")) GrassField.defaultBlades = Std.parseInt(q.get("blades"));
		if (q.has("depth")) GrassField.defaultDepth = Std.parseFloat(q.get("depth"));
		if (q.get("aa") == "0") inkRenderer.fxaa = false;
		if (q.has("at")) {
			var a = q.get("at").split(",");
			if (a.length == 2) startAt = {x: Std.parseFloat(a[0]), y: Std.parseFloat(a[1])};
		}
		#end
	}

	/**
		Debug: `?gallery=1` lines up one rigged figure per kind and take at the
		`at` point (or the view centre), facing the camera, every take looping.
		For checking the character pipeline; not part of the game.
	**/
	var gallery:Null<Array<render.CharacterModel>> = null;

	function buildGallery() {
		gallery = [];
		var cx = startAt != null ? startAt.x : s3d.camera.target.x, cy = startAt != null ? startAt.y : s3d.camera.target.y;
		var dx = s3d.camera.pos.x - cx, dy = s3d.camera.pos.y - cy;
		var face = Math.atan2(dy, dx);
		// Line up across the view (perpendicular to the camera direction).
		var ax = -Math.sin(face), ay = Math.cos(face);
		var shows:Array<{kind:game.Unit.UnitKind, take:String}> = [
			{kind: Archer, take: "Idle"}, {kind: Archer, take: "Shoot"}, {kind: Swordsman, take: "Walk"},
			{kind: Swordsman, take: "Slash"}, {kind: Piker, take: "Thrust"}, {kind: Captain, take: "Plant"},
		];
		for (k in 0...shows.length) {
			var o = (k - (shows.length - 1) / 2) * 1.6;
			var m = new render.CharacterModel(k % 2, shows[k].kind, s3d);
			var x = cx + ax * o, y = cy + ay * o;
			m.setPosition(x, y, island.heightAt(x, y));
			m.setRotation(0, 0, face);
			m.play(shows[k].take, 1.0, true);
			gallery.push(m);
		}
		// Two more in front of the line that fall as rag dolls, to check the skeleton mapping.
		for (k in 0...2) {
			var o = (k - 0.5) * 3.0;
			var x = cx + ax * o + Math.cos(face) * 2.5, y = cy + ay * o + Math.sin(face) * 2.5;
			var m = new render.CharacterModel(k, k == 0 ? Swordsman : Archer, s3d);
			var z = island.heightAt(x, y);
			m.setPosition(x, y, z);
			m.startRagdoll();
			var ground = (lx:Float, ly:Float) -> Math.max(island.heightAt(x + lx, y + ly), -0.25) - z;
			var rd = new render.Ragdoll(face + k * 1.3, 1.95, 0, ground);
			rd.kick(Math.cos(face + 2.0), Math.sin(face + 2.0), 3.0, 2.0);
			galleryRagdolls.push({m: m, r: rd, x: x, y: y, z: z});
		}
	}

	var galleryRagdolls:Array<{m:render.CharacterModel, r:render.Ragdoll, x:Float, y:Float, z:Float}> = [];

	override function update(dt:Float) {
		if (galleryWanted && gallery == null && frames > 2) buildGallery();
		for (g in galleryRagdolls) {
			g.r.update(Math.min(dt, 0.1));
			g.m.applyRagdoll(g.r, g.x, g.y, g.z);
		}
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
				case Painted: InkMap;
				case InkMap: Sketch;
				case Sketch: Painted;
			};
			applyStyle();
		}
		if (hxd.Key.isPressed(hxd.Key.C)) {
			weather = switch currentWeather() {
				case null: Sunny;
				case Sunny: Fog;
				case Fog: Rain;
				case Rain: Sunny;
			};
			applyStyle();
		}
		if (hxd.Key.isPressed(hxd.Key.P)) {
			treeMode = (currentTreeMode() + 1) % 3;
			islandView.setTreeMode(treeMode);
		}
		if (hxd.Key.isPressed(hxd.Key.B))
			inkRenderer.tiltShift = !inkRenderer.tiltShift;
		if (hxd.Key.isPressed(hxd.Key.G)) {
			shape = shape == Single ? Atoll : Single;
			buildWorld();
		}
		rtsCam.update(dt, selection.mouseX, selection.mouseY, s2d.width, s2d.height);
		// The sim runs on wall-clock time (Heaps' dt is smoothed and lags far behind
		// when frames are slow); Sim.update still caps how much it catches up at once.
		var now = haxe.Timer.stamp();
		var simDt = lastStamp < 0 ? dt : now - lastStamp;
		lastStamp = now;
		#if js
		// Automation can hold the sim at a tick (snapshot.mjs --untiltick) so the shot
		// shows that moment: software rendering takes far longer than a tick per frame.
		var hold:Null<Int> = js.Syntax.code("window.atollHoldTick");
		sim.update(simDt, hold == null ? -1 : hold);
		#else
		sim.update(simDt);
		#end
		#if js
		// For automation (scripts/snapshot.mjs): where the ships are and what they're doing.
		js.Syntax.code("window.atollSim = {0}", 'tick=${sim.tick} winner=${sim.winner}@${sim.winTick} firstflag=${sim.firstFlagTick} flag=${sim.flagTeam}:${Math.round(sim.flagHeld)} ' + [for (sh in sim.ships) 'ship${sh.team}:${sh.sunk ? "SUNK" : Std.string(sh.state)}@${Math.round(sh.x)},${Math.round(sh.y)} crew=${sh.crew.length} hp=${Math.round(sh.hp)} shots=${sh.shots}'].join(" ")
			+ ' red:' + [for (u in sim.units) if (u.team == 1 && u.alive) '${Math.round(u.x)},${Math.round(u.y)}${u.ordered ? "o" : ""}${u.targetId >= 0 ? "t" : ""}'].join(" "));
		#end
		if (bombard && !bombardSent && sim.tick > 90 && sim.ships[0].crew.length == 0) {
			bombardSent = true;
			sim.queue(ShipTo(sim.ships[0].id, sim.homeBeach[1].x, sim.homeBeach[1].y));
		}
		islandView.update(dt);
		islandView.setGrassFocus(s3d.camera.target.x, s3d.camera.target.y, rtsCam.distance);
		islandView.updateTrample(dt, [for (v in unitViews) if (v.unit.alive && v.unit.aboard < 0) {x: v.x, y: v.y}]);
		UnitView.simTick = sim.tick;
		for (v in unitViews) v.syncFromSim(dt);
		for (v in shipViews) v.syncFromSim(dt);
		arrowsView.syncFromSim();
		cannonView.syncFromSim(dt);
		flagView.syncFromSim(dt);
		var ss = selection.selectedShip();
		battle.selectedShip = ss == null ? null : ss.ship;
		battle.update(sim, unitViews, s3d.camera, s2d.width, s2d.height);
		selection.update(dt);
		controls.update(dt, s2d.width, s2d.height);
		minimap.update(s2d.width, s2d.height);
		drafting.update(dt, s2d.width, s2d.height);
	}

	static function main() {
		// 4x MSAA on the screen (applies when nothing renders offscreen; the
		// renderer adds FXAA when tilt-shift does).
		h3d.Engine.ANTIALIASING = 4;
		new Main();
	}
}
