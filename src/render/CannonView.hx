package render;

/**
	The cannons' side of the battle, drawn from the sim each frame:

	- balls in flight: small iron spheres lobbed on a high arc from the deck
	  to where they were aimed;
	- a puff of powder smoke at the ship's side when a gun fires;
	- where a ball comes down: a column of spray at sea, a burst of dust and
	  a crater ashore, splinters off a struck hull.

	Everything here is cosmetic (the sim decides what was hit). Puffs are a
	small reused pool of translucent balls in the alpha pass, so the ink
	outline leaves them soft.
**/
class CannonView extends h3d.scene.Object {
	final sim:game.Sim;
	final decals:Decals;
	final heightAt:(Float, Float) -> Float;
	final balls:Array<h3d.scene.Object> = [];
	final puffs:Array<Puff> = [];
	var lastBall = 0;
	var lastImpact = 0;

	public function new(sim:game.Sim, decals:Decals, ?parent:h3d.scene.Object) {
		super(parent);
		this.sim = sim;
		this.decals = decals;
		heightAt = sim.island.heightAt;
	}

	function makeBall():h3d.scene.Object {
		var o = new h3d.scene.Object(this);
		var b = new FlatMeshBuilder();
		b.ball(0, 0, 0, 0.2, Palette.IRON, 8, 5);
		b.build(o, true, false, false);
		return o;
	}

	function puff(x:Float, y:Float, z:Float, color:Int, r0:Float, r1:Float, life:Float, rise:Float, squash = 1.0, alpha = 0.8) {
		var p:Puff = null;
		for (q in puffs)
			if (!q.obj.visible) {
				p = q;
				break;
			}
		if (p == null) {
			var o = new h3d.scene.Object(this);
			var b = new FlatMeshBuilder();
			b.ball(0, 0, 0, 1, 0xFFFFFF, 9, 6);
			var mats = [];
			for (m in b.build(o, true, false, false)) {
				// Translucent, in the alpha pass (soft: no ink outline, no shadow).
				m.material.blendMode = Alpha;
				m.material.mainPass.depthWrite = false;
				mats.push(m.material);
			}
			p = {obj: o, mats: mats, t: 0, life: 1, r0: 1, r1: 1, rise: 0, z0: 0, squash: 1, alpha: 1};
			puffs.push(p);
		}
		p.obj.visible = true;
		p.obj.setPosition(x, y, z);
		p.t = 0;
		p.life = life;
		p.r0 = r0;
		p.r1 = r1;
		p.rise = rise;
		p.z0 = z;
		p.squash = squash;
		p.alpha = alpha;
		for (m in p.mats) m.color.set(Palette.r(color), Palette.g(color), Palette.b(color), alpha);
	}

	public function syncFromSim(dt:Float) {
		// New shots: smoke at the gun, on the side facing the aim.
		for (b in sim.cannonballs)
			if (b.id > lastBall) {
				lastBall = b.id;
				var dx = b.toX - b.fromX, dy = b.toY - b.fromY;
				var l = Math.max(Math.sqrt(dx * dx + dy * dy), 0.01);
				var sx = b.fromX + dx / l * 2.0, sy = b.fromY + dy / l * 2.0;
				puff(sx, sy, 0.9, Palette.SMOKE, 0.35, 1.8, 2.2, 1.2, 0.8, 0.75);
				puff(sx + dx / l * 0.9, sy + dy / l * 0.9, 0.9, Palette.SMOKE, 0.2, 1.1, 1.4, 0.6, 0.8, 0.6);
			}
		// Where balls came down.
		for (i in sim.impacts)
			if (i.id > lastImpact) {
				lastImpact = i.id;
				if (i.hitShip) {
					puff(i.x, i.y, 1.0, Palette.SPLINTER, 0.3, 1.2, 0.9, 0.8, 1.0, 0.85);
					puff(i.x, i.y, 1.2, Palette.SMOKE, 0.3, 1.5, 1.6, 1.0, 1.0, 0.5);
				} else if (i.water) {
					// A tall column of spray that collapses, and a ring of foam.
					puff(i.x, i.y, 0.2, Palette.SPRAY, 0.25, 0.7, 1.0, 0.4, 3.2, 0.85);
					puff(i.x, i.y, 0.05, Palette.SPRAY, 0.4, 1.6, 1.4, 0.0, 0.12, 0.6);
				} else {
					var z = heightAt(i.x, i.y);
					puff(i.x, i.y, z + 0.3, Palette.DUST, 0.3, 1.9, 1.8, 0.9, 0.7, 0.8);
					puff(i.x, i.y, z + 0.2, Palette.DUST, 0.2, 1.2, 1.0, 1.8, 1.4, 0.6);
					decals.crater(i.x, i.y, 1.3);
				}
			}

		// Balls in flight: a high lob (a quarter of the range up), deck to aim point.
		var k = 0;
		for (b in sim.cannonballs) {
			if (k >= balls.length) balls.push(makeBall());
			var o = balls[k++];
			o.visible = true;
			var f = Math.min(1, b.t / b.duration);
			var dx = b.toX - b.fromX, dy = b.toY - b.fromY;
			var len = Math.sqrt(dx * dx + dy * dy);
			var z0 = 1.0, z1 = Math.max(heightAt(b.toX, b.toY), 0);
			o.setPosition(b.fromX + dx * f, b.fromY + dy * f, z0 + (z1 - z0) * f + len * 0.25 * 4 * f * (1 - f));
		}
		while (k < balls.length) balls[k++].visible = false;

		for (p in puffs) {
			if (!p.obj.visible) continue;
			p.t += dt;
			var f = p.t / p.life;
			if (f >= 1) {
				p.obj.visible = false;
				continue;
			}
			// Grows fast then slows; fades out over its life.
			var g = 1 - (1 - f) * (1 - f);
			var r = p.r0 + (p.r1 - p.r0) * g;
			p.obj.setScale(r);
			p.obj.scaleZ = r * p.squash * (p.squash > 2 ? (1 - f * 0.8) : 1);
			p.obj.z = p.z0 + p.rise * g;
			for (m in p.mats) m.color.a = p.alpha * (1 - f) * (1 - f * 0.3);
		}
	}
}

private typedef Puff = {
	obj:h3d.scene.Object,
	mats:Array<h3d.mat.Material>,
	t:Float,
	life:Float,
	r0:Float,
	r1:Float,
	rise:Float,
	z0:Float,
	squash:Float,
	alpha:Float
};
