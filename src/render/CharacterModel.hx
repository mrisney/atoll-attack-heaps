package render;

import game.Unit.UnitKind;

/**
	A rigged, animated character loaded from FBX (res/characters), drawn as
	paper-white line art: flat light shading, the screen-space ink pass for
	outlines, the tunic and pennant tinted by team.

	The asset contract (see tools/character/standin.py, which generates the
	stand-in that proves this pipeline):
	- `standin.fbx`: one armature + one skinned body mesh, Z up, facing +X,
	  feet at the origin. Takes: Idle, Walk (loop); Shoot, Slash, Thrust,
	  Plant (once).
	- `standin-props.fbx`: rigid props (Prop_Bow, Prop_Quiver, Prop_Sword,
	  Prop_Shield, Prop_Pike, Prop_Flag), each modelled in the frame of the
	  joint that holds it. They're attached to that joint at runtime, so one
	  body serves every unit type. (They can't be skinned: Heaps merges all
	  skinned meshes of an armature into one geometry.)
	- Material names: Skin, Tunic, Trousers, Boots, Wood, Metal, String,
	  Pennant.

	The final figure replaces it by keeping the same names.
**/
class CharacterModel extends h3d.scene.Object {
	static var lib:hxd.fmt.hmd.Library;
	static var propLib:hxd.fmt.hmd.Library;
	static final anims = new Map<String, h3d.anim.Animation>();

	/** Which joint holds each prop. (Blender's "hand.L" arrives in Heaps as "hand_L".) **/
	static final PROP_JOINT = [
		"Prop_Bow" => "hand_L", "Prop_Quiver" => "hips", "Prop_Sword" => "hand_R", "Prop_Shield" => "forearm_L", "Prop_Pike" => "hand_R",
		"Prop_Flag" => "hand_R",
	];

	public static final hatch = new CharacterInk.CharacterHatch();
	public static final outlineShader = new CharacterInk.CharacterOutline();

	public final skin:h3d.scene.Skin;
	public var current(default, null) = "";

	static function load() {
		if (lib != null) return;
		lib = hxd.Res.load("characters/standin.fbx").toModel().toHmd();
		propLib = hxd.Res.load("characters/standin-props.fbx").toModel().toHmd();
		for (a in lib.header.animations) {
			var anim = lib.loadAnimation(a.name);
			// Blender names takes "Armature|Walk".
			var short = a.name.indexOf("|") >= 0 ? a.name.substr(a.name.lastIndexOf("|") + 1) : a.name;
			anims.set(short, anim);
		}
	}

	public static function kit(kind:UnitKind):Array<String> {
		return switch kind {
			case Archer: ["Prop_Bow", "Prop_Quiver"];
			case Swordsman: ["Prop_Sword", "Prop_Shield"];
			case Captain: ["Prop_Flag"];
			case Piker: ["Prop_Pike"];
		}
	}

	public function new(team:Int, kind:UnitKind, ?parent:h3d.scene.Object) {
		super(parent);
		load();
		var root = lib.makeObject();
		addChild(root);
		skin = cast root.find(o -> Std.isOfType(o, h3d.scene.Skin) ? o : null);
		// Heaps only poses visible skins; a blend that starts from a pose never computed
		// (unit off screen) reads undefined matrices. Squads are small, so always pose.
		skin.alwaysSyncAnimation = true;
		var cloth = team == 0 ? Palette.CLOTH_BLUE : Palette.CLOTH_RED;
		var teamCol = team == 0 ? Palette.TEAM_BLUE : Palette.TEAM_RED;
		for (m in root.getMaterials()) style(m, cloth, teamCol);

		var props = propLib.makeObject();
		var joints = new Map<String, JointFollower>();
		for (name in kit(kind)) {
			var p = props.getObjectByName(name);
			if (p == null) continue;
			var jname = PROP_JOINT.get(name);
			var joint = joints.get(jname);
			if (joint == null) {
				joint = new JointFollower(skin, jname);
				joints.set(jname, joint);
			}
			p.remove();
			p.defaultTransform = null;
			p.setPosition(0, 0, 0);
			p.setRotation(0, 0, 0);
			joint.addChild(p);
			// Thin, flat pieces (shield disc, pennant) get no hull: it shows through them.
			for (m in p.getMaterials()) style(m, cloth, teamCol, name != "Prop_Shield" && m.name != "Pennant");
		}
		play("Idle");
	}

	function style(m:h3d.mat.Material, cloth:Int, teamCol:Int, withOutline = true) {
		var c = switch m.name {
			case "Tunic": cloth;
			case "Pennant": teamCol;
			case "Wood": Palette.CHAR_WOOD;
			case "Metal": Palette.CHAR_METAL;
			default: Palette.PAPER;
		};
		m.texture = null;
		m.color.set(Palette.r(c), Palette.g(c), Palette.b(c), 1);
		m.mainPass.culling = Back;
		// Drawn, not lit: paper tone and pencil hatching (CharacterInk) instead of scene lights.
		m.mainPass.enableLights = false;
		m.specularAmount = 0;
		m.mainPass.addShader(new render.ink.GeoOut());
		m.mainPass.addShader(hatch);
		// Graphite outline: an inverted hull, as a second pass of the same skinned material.
		if (withOutline) {
			var outline = new h3d.mat.Pass("default", null, m.mainPass);
			outline.culling = Front;
			outline.addShader(outlineShader);
			m.addPass(outline);
		}
		m.castShadows = true;
		m.receiveShadows = false;
	}

	/** Switch take, blending from the current pose. `speed` scales playback. **/
	public function play(name:String, speed = 1.0, blend = 0.0, ?loop:Bool) {
		var a = anims.get(name);
		if (a == null) return;
		if (name == current) {
			if (skin.currentAnimation != null) skin.currentAnimation.speed = speed;
			return;
		}
		var inst = a.createInstance(skin);
		inst.loop = loop != null ? loop : (name == "Idle" || name == "Walk");
		inst.speed = speed;
		// Cut, don't blend: Heaps' SmoothTransition reads poses it hasn't computed yet
		// when walk/idle switch quickly (undefined matrices, and it can't nest). TODO:
		// our own crossfade between the two instances.
		skin.switchToAnimation(inst);
		current = name;
	}

	// --- rag doll -----------------------------------------------------------------

	/** Which rag doll frame drives each joint; the rest follow their parent at rest. **/
	static final RAG_FRAME = [
		"hips" => 0, "spine" => 0, "chest" => 0, "neck" => 0, "shoulder_L" => 0, "shoulder_R" => 0, "head" => 1, "thigh_L" => 2,
		"thigh_R" => 3, "upper_arm_L" => 4, "upper_arm_R" => 5,
	];

	/** Stop animating; from now on `applyRagdoll` poses the skeleton. **/
	public function startRagdoll() {
		skin.stopAnimation();
		skin.currentAnimation = null;
		// The root's translation comes from the rag doll, so don't let retargeting reset it.
		skin.enableRetargeting = false;
		current = "";
	}

	/**
		Pose the skeleton from the rag doll's particles (local to the unit view,
		whose world origin is `ox, oy, oz`). Each body part's rotation is the
		rest pose turned into the frame the rag doll gives it: torso from pelvis,
		chest and shoulders; head; each leg hip→foot; each arm shoulder→hand.
		Lower limbs stay straight, like the line-art figures (no knees or elbows).
		Cosmetic only, like the rag doll itself.
	**/
	@:access(h3d.scene.Skin)
	public function applyRagdoll(r:Ragdoll, ox:Float, oy:Float, oz:Float) {
		inline function px(i:Int) return new h3d.Vector(r.x[i], r.y[i], r.z[i]);
		var pelvis = px(Ragdoll.PELVIS), chest = px(Ragdoll.CHEST);
		var up = chest.sub(pelvis).normalized();
		var left = orthoLeft(px(Ragdoll.SH_L).sub(px(Ragdoll.SH_R)), up);
		var frames = [
			frame(left, up),
			frame(left, px(Ragdoll.HEAD).sub(chest).normalized()),
			frame(left, px(Ragdoll.HIP_L).sub(px(Ragdoll.FOOT_L)).normalized()),
			frame(left, px(Ragdoll.HIP_R).sub(px(Ragdoll.FOOT_R)).normalized()),
			frame(left, px(Ragdoll.SH_L).sub(px(Ragdoll.HAND_L)).normalized()),
			frame(left, px(Ragdoll.SH_R).sub(px(Ragdoll.HAND_R)).normalized()),
		];

		var sd = skin.getSkinData();
		var sAbs = skin.getAbsPos();
		var abs = new Map<Int, h3d.Matrix>();
		var restAbs = new Map<Int, h3d.Matrix>();
		var inv = new h3d.Matrix();
		for (j in jointsByDepth()) {
			var pAbs = j.parent == null ? sAbs : abs.get(j.parent.index);
			var pRest = j.parent == null ? sAbs : restAbs.get(j.parent.index);
			var ra = new h3d.Matrix();
			ra.multiply3x4(j.defMat, pRest);
			restAbs.set(j.index, ra);
			var f = RAG_FRAME.get(j.name);
			var a = new h3d.Matrix();
			if (f == null) {
				a.multiply3x4(j.defMat, pAbs);
			} else {
				// Rotation: the rest orientation turned into the part's rag doll frame.
				a.multiply3x4(ra, frames[f]);
				// Position: the rest offset from the parent, except the root, which sits
				// at the rag doll's pelvis.
				if (j.parent == null) {
					a._41 = ox + pelvis.x;
					a._42 = oy + pelvis.y;
					a._43 = oz + pelvis.z;
				} else {
					var t = new h3d.Vector(j.defMat._41, j.defMat._42, j.defMat._43);
					t.transform(pAbs);
					a._41 = t.x;
					a._42 = t.y;
					a._43 = t.z;
				}
			}
			abs.set(j.index, a);
			inv.inverse3x4(pAbs);
			var rel = new h3d.Matrix();
			rel.multiply3x4(a, inv);
			skin.jointsData[j.index].currentRelPos = rel;
		}
		skin.jointsUpdated = true;
	}

	var depthOrder:Null<Array<h3d.anim.Skin.Joint>> = null;

	function jointsByDepth() {
		if (depthOrder == null) {
			inline function depth(j:h3d.anim.Skin.Joint) {
				var d = 0;
				while (j.parent != null) {
					d++;
					j = j.parent;
				}
				return d;
			}
			depthOrder = skin.getSkinData().allJoints.copy();
			depthOrder.sort((a, b) -> depth(a) - depth(b));
		}
		return depthOrder;
	}

	/** A rotation taking the rest axes (X forward, Y left, Z up) to this frame. **/
	static function frame(left:h3d.Vector, up:h3d.Vector):h3d.Matrix {
		var l = orthoLeft(left, up);
		var fwd = l.cross(up);
		var m = new h3d.Matrix();
		m.identity();
		m._11 = fwd.x;
		m._12 = fwd.y;
		m._13 = fwd.z;
		m._21 = l.x;
		m._22 = l.y;
		m._23 = l.z;
		m._31 = up.x;
		m._32 = up.y;
		m._33 = up.z;
		return m;
	}

	static function orthoLeft(left:h3d.Vector, up:h3d.Vector):h3d.Vector {
		var l = left.sub(up.scaled(left.dot(up)));
		if (l.lengthSq() < 1e-8) l = new h3d.Vector(-up.y, up.x, 0);
		return l.normalized();
	}

	public function setSpeed(speed:Float) {
		var a = skin.currentAnimation;
		if (a == null) return;
		var t = Std.downcast(a, h3d.anim.Transition);
		if (t != null) t.anim2.speed = speed else a.speed = speed;
	}
}

/**
	Follows one joint of a skin, so rigid props can hang on it. Heaps'
	own Skin.getObjectByName gives a detached Joint that isn't meant to sit
	in the scene graph (adding one breaks name lookups during animation
	binding), so this is a plain child of the skin that copies the joint's
	world matrix every frame, after the animation has posed it.
**/
@:access(h3d.scene.Skin)
class JointFollower extends h3d.scene.Object {
	final sk:h3d.scene.Skin;
	final index:Int;

	public function new(skin:h3d.scene.Skin, joint:String) {
		super(skin);
		sk = skin;
		index = skin.getSkinData().namedJoints.get(joint).index;
	}

	override function sync(ctx:h3d.scene.RenderContext) {
		posChanged = true; // the joint moves every frame
	}

	override function calcAbsPos() {
		sk.syncJoints();
		absPos.load(sk.jointsData[index].currentAbsPos);
		if (invPos != null) invPos._44 = 0;
	}
}
