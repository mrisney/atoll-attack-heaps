package render;

/**
	Draws the sim's arrows in flight: a thin dark shaft with pale fletching,
	flying from the archer to its target on a shallow arc and pointing along
	its path. A small pool of meshes is reused, so arrows cost nothing when
	none are flying.
**/
class ArrowsView extends h3d.scene.Object {
	final sim:game.Sim;
	final pool:Array<h3d.scene.Object> = [];

	public function new(sim:game.Sim, ?parent:h3d.scene.Object) {
		super(parent);
		this.sim = sim;
	}

	function makeArrow():h3d.scene.Object {
		var o = new h3d.scene.Object(this);
		var b = new FlatMeshBuilder();
		// Along +X: shaft, head, fletching. Long enough to read from the RTS camera.
		b.place(0, Math.PI / 2, 0, -0.45, 0, 0);
		b.cone(0, 0, 0, 0.022, 0.9, 4, Palette.CHAR_WOOD, 0.022);
		b.unplace();
		b.place(0, Math.PI / 2, 0, 0.45, 0, 0);
		b.cone(0, 0, 0, 0.05, 0.14, 4, Palette.INK);
		b.unplace();
		b.place(0, Math.PI / 2, 0, -0.45, 0, 0);
		b.cone(0, 0, 0, 0.07, 0.16, 3, Palette.PAPER, 0.02);
		b.unplace();
		b.build(o, true, false, false);
		return o;
	}

	public function syncFromSim() {
		var i = 0;
		for (a in sim.arrows) {
			if (i >= pool.length) pool.push(makeArrow());
			var o = pool[i++];
			o.visible = true;
			var f = Math.min(1, a.t / a.duration);
			var dx = a.aimX - a.startX, dy = a.aimY - a.startY;
			var len = Math.sqrt(dx * dx + dy * dy);
			// Loosed at shoulder height, landing at chest height, on a shallow arc.
			var z0 = a.startZ + 1.4, z1 = a.aimZ + 1.1;
			var arc = len * 0.12;
			var x = a.startX + dx * f, y = a.startY + dy * f;
			var z = z0 + (z1 - z0) * f + arc * 4 * f * (1 - f);
			var slope = ((z1 - z0) + arc * 4 * (1 - 2 * f)) / Math.max(len, 0.01);
			o.setPosition(x, y, z);
			o.setRotation(0, -Math.atan(slope), Math.atan2(dy, dx));
		}
		while (i < pool.length) pool[i++].visible = false;
	}
}
