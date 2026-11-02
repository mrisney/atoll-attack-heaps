import game.Sim;
import input.RtsCamera;
import input.SelectionController;
import render.IslandView;
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

	override function init() {
		engine.backgroundColor = 0xFF000000 | Palette.OCEAN_DEEP;
		inkRenderer = new render.ink.InkRenderer();
		s3d.renderer = inkRenderer;
		setupLighting();
		rtsCam = new RtsCamera(s3d.camera);

		hud = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		hud.textColor = 0xF2EEDF;
		hud.dropShadow = {dx: 1, dy: 1, color: 0x10202A, alpha: 0.8};
		hud.setPosition(12, 10);

		seed = Std.int(Date.now().getTime() % 100000);
		buildWorld();
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

		island = new Island(seed);
		sim = new Sim(island);
		islandView = new IslandView(island, s3d);
		for (u in sim.units) unitViews.push(new UnitView(u, s3d));
		selection = new SelectionController(sim, unitViews, s3d, s2d, rtsCam);

		// Start looking at the blue squad's beach.
		var blue = sim.units[0];
		rtsCam.targetX = blue.x;
		rtsCam.targetY = blue.y;
		rtsCam.bounds = island.halfExtent;
		rtsCam.apply();

		hud.text = 'ATOLL ATTACK  ·  seed $seed\n'
			+ 'Drag: select   Click/RMB: move   Shift: add\n'
			+ 'WASD/edges: pan   Wheel: zoom   Q/E: rotate   R: new island   I: ink lines';
	}

	override function update(dt:Float) {
		if (hxd.Key.isPressed(hxd.Key.R)) {
			seed = Std.random(100000);
			buildWorld();
		}
		if (hxd.Key.isPressed(hxd.Key.I))
			inkRenderer.inkEnabled = !inkRenderer.inkEnabled;
		rtsCam.update(dt, selection.mouseX, selection.mouseY, s2d.width, s2d.height);
		sim.update(dt);
		for (v in unitViews) v.syncFromSim(dt);
		selection.update(dt);
	}

	static function main() {
		new Main();
	}
}
