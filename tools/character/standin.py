"""
Stand-in character for Atoll Attack, generated entirely in code with Blender.

    python -m venv bl && bl/bin/pip install bpy
    bl/bin/python tools/character/standin.py res/characters/standin.fbx

It exists to prove the real pipeline (Blender -> FBX -> Heaps skinned mesh with
named animation takes) before the final character is modelled. The real model
can replace it as long as it keeps the same contract:

  * one armature, Z up, figure facing +X (its left is +Y), ~1.75 m tall,
    feet at the origin;
  * bones named as in BONES below (or update CharacterView.hx);
  * mesh materials named Skin, Tunic, Trousers, Boots, Wood, Metal, String,
    Pennant ("Tunic" and "Pennant" are tinted by team in the game);
  * prop objects named Prop_Bow, Prop_Quiver, Prop_Sword, Prop_Shield,
    Prop_Pike, Prop_Flag (the game shows only the unit type's own kit);
  * animation takes: Idle, Walk, Shoot, Slash, Thrust, Plant
    (Idle and Walk loop; the others play once).

Nothing here is downloaded: no licence questions.
"""

import math
import sys

import bpy  # must come first: the pip bpy module puts bmesh/mathutils on the path
import bmesh
from mathutils import Matrix, Quaternion, Vector

OUT = sys.argv[-1] if sys.argv[-1].endswith(".fbx") else "standin.fbx"
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

# --- skeleton --------------------------------------------------------------------
# (name, parent, head, tail) in metres. Facing +X, left = +Y, Z up.
L, R = 1, -1


def side(s, y):
    return y * s


BONES = [
    ("hips", None, (0, 0, 0.93), (0, 0, 1.08)),
    ("spine", "hips", (0, 0, 1.08), (0, 0, 1.26)),
    ("chest", "spine", (0, 0, 1.26), (0, 0, 1.44)),
    ("neck", "chest", (0, 0, 1.44), (0, 0, 1.53)),
    ("head", "neck", (0, 0, 1.53), (0, 0, 1.76)),
]
for s, n in ((L, "L"), (R, "R")):
    BONES += [
        (f"shoulder.{n}", "chest", (0, side(s, 0.05), 1.41), (0, side(s, 0.19), 1.42)),
        (f"upper_arm.{n}", f"shoulder.{n}", (0, side(s, 0.19), 1.42), (0, side(s, 0.215), 1.13)),
        (f"forearm.{n}", f"upper_arm.{n}", (0, side(s, 0.215), 1.13), (0.02, side(s, 0.225), 0.88)),
        (f"hand.{n}", f"forearm.{n}", (0.02, side(s, 0.225), 0.88), (0.03, side(s, 0.225), 0.78)),
        (f"thigh.{n}", "hips", (0, side(s, 0.095), 0.92), (0.01, side(s, 0.095), 0.5)),
        (f"shin.{n}", f"thigh.{n}", (0.01, side(s, 0.095), 0.5), (0, side(s, 0.095), 0.09)),
        (f"foot.{n}", f"shin.{n}", (0, side(s, 0.095), 0.09), (0.15, side(s, 0.095), 0.03)),
    ]

arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, parent, h, t in BONES:
    b = arm_data.edit_bones.new(name)
    b.head = h
    b.tail = t
    b.roll = 0
    if parent:
        b.parent = arm_data.edit_bones[parent]
        b.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
SEG = {name: (Vector(h), Vector(t)) for name, _, h, t in BONES}

# --- materials --------------------------------------------------------------------
MATS = {}
for name, col in [
    ("Skin", (0.94, 0.92, 0.88)),
    ("Tunic", (0.97, 0.96, 0.93)),
    ("Trousers", (0.93, 0.92, 0.89)),
    ("Boots", (0.85, 0.83, 0.79)),
    ("Wood", (0.62, 0.5, 0.38)),
    ("Metal", (0.78, 0.8, 0.82)),
    ("String", (0.9, 0.88, 0.84)),
    ("Pennant", (0.95, 0.95, 0.95)),
]:
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*col, 1)
    MATS[name] = m

# --- body: skin-modifier figure ----------------------------------------------------
# Joints (with radii, in metres) and the edges between them; the Skin modifier
# wraps them in a smooth tube surface, then Subdivision rounds it off.
P = {}
EDGES = []


def j(key, pos, r):
    P[key] = (Vector(pos), r)


j("pelvis", (0, 0, 0.9), 0.16)
j("waist", (0, 0, 1.1), 0.15)
j("chest", (0, 0, 1.3), 0.17)
j("neckb", (0, 0, 1.45), 0.065)
j("neckt", (0, 0, 1.52), 0.055)
for s, n in ((L, "L"), (R, "R")):
    y = lambda v: side(s, v)
    j(f"sh{n}", (0, y(0.19), 1.41), 0.065)
    j(f"el{n}", (0.0, y(0.215), 1.13), 0.05)
    j(f"wr{n}", (0.02, y(0.225), 0.88), 0.04)
    j(f"ha{n}", (0.03, y(0.225), 0.79), 0.042)
    j(f"hip{n}", (0, y(0.095), 0.86), 0.098)
    j(f"kn{n}", (0.01, y(0.095), 0.5), 0.07)
    j(f"an{n}", (0, y(0.095), 0.12), 0.058)
    j(f"he{n}", (-0.03, y(0.095), 0.05), 0.055)
    j(f"to{n}", (0.15, y(0.095), 0.04), 0.045)
    EDGES += [("chest", f"sh{n}"), (f"sh{n}", f"el{n}"), (f"el{n}", f"wr{n}"), (f"wr{n}", f"ha{n}"),
              ("pelvis", f"hip{n}"), (f"hip{n}", f"kn{n}"), (f"kn{n}", f"an{n}"), (f"an{n}", f"he{n}"),
              (f"he{n}", f"to{n}")]
EDGES += [("pelvis", "waist"), ("waist", "chest"), ("chest", "neckb"), ("neckb", "neckt")]

keys = list(P.keys())
me = bpy.data.meshes.new("BodyGraph")
me.from_pydata([P[k][0] for k in keys], [(keys.index(a), keys.index(b)) for a, b in EDGES], [])
body = bpy.data.objects.new("Body", me)
scene.collection.objects.link(body)
skin = body.modifiers.new("Skin", "SKIN")
for i, k in enumerate(keys):
    sv = me.skin_vertices[0].data[i]
    sv.radius = (P[k][1], P[k][1])
    if k == "pelvis":
        sv.use_root = True
body.modifiers.new("Sub", "SUBSURF").levels = 1
bpy.context.view_layer.objects.active = body
for m in list(body.modifiers):
    bpy.ops.object.modifier_apply(modifier=m.name)

# Torso is deeper than it is wide only in cartoons: flatten front-to-back.
for v in body.data.vertices:
    if 0.85 < v.co.z < 1.5 and abs(v.co.y) < 0.2:
        v.co.x *= 0.72

# Head: a smooth egg on the neck.
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=12, radius=0.11)
for v in bm.verts:
    v.co.x *= 0.92
    v.co.z *= 1.12
    v.co.z += 1.63
    v.co.x += 0.01
head_me = bpy.data.meshes.new("Head")
bm.to_mesh(head_me)
bm.free()
head = bpy.data.objects.new("Head", head_me)
scene.collection.objects.link(head)

# Join head into the body.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
head.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()


# --- weights: by distance to each bone segment --------------------------------------
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


DEFORM = [n for n, _, _, _ in BONES]


def weigh(obj, only=None):
    groups = {n: obj.vertex_groups.new(name=n) for n in DEFORM}
    for v in obj.data.vertices:
        if only:
            groups[only].add([v.index], 1.0, "REPLACE")
            continue
        p = v.co
        ds = sorted((seg_dist(p, *SEG[n]), n) for n in DEFORM)
        best = ds[:2]
        ws = [1.0 / max(d, 0.01) ** 4 for d, _ in best]
        tot = sum(ws)
        for (d, n), w in zip(best, ws):
            groups[n].add([v.index], w / tot, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.parent = arm


weigh(body)

# Materials by region: the bone that owns each face.
for m in ("Skin", "Tunic", "Trousers", "Boots"):
    body.data.materials.append(MATS[m])
mi = {m: i for i, m in enumerate(["Skin", "Tunic", "Trousers", "Boots"])}
vg = {g.index: g.name for g in body.vertex_groups}
for poly in body.data.polygons:
    c = poly.center
    best, bw = None, -1
    for vi in poly.vertices:
        for g in body.data.vertices[vi].groups:
            if g.weight > bw:
                bw, best = g.weight, vg[g.group]
    if best in ("head",) or best.startswith("hand"):
        m = "Skin"
    elif best.startswith("foot") or (best.startswith("shin") and c.z < 0.2):
        m = "Boots"
    elif best.startswith(("thigh", "shin")) or (best == "hips" and c.z < 0.86):
        m = "Trousers"
    else:
        m = "Tunic"
    poly.material_index = mi[m]
for p in body.data.polygons:
    p.use_smooth = True


# --- props ------------------------------------------------------------------------------
def tube(points, radius, mat, segs=6):
    """A tube along a polyline (list of Vectors)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        r = radius(i / (len(points) - 1)) if callable(radius) else radius
        rings.append([bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * r)
                      for t in [k / segs * 2 * math.pi for k in range(segs)]])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return bm


PROPS = []


def prop(name, parts, bone):
    """
    parts: list of (bmesh, material name), modelled in place on the rest pose.
    Props are rigid and not skinned: they are exported separately, in the frame
    of the bone that holds them, and the game attaches them to that joint.
    (Heaps merges every skinned mesh of one armature into a single geometry,
    so separate skinned props would not survive the import anyway.)
    """
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    mats = []
    for pb, mat in parts:
        if mat not in mats:
            mats.append(mat)
        idx = mats.index(mat)
        for f in pb.faces:
            f.material_index = idx
        tmp = bpy.data.meshes.new("tmp")
        pb.to_mesh(tmp)
        pb.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    # Into the holding bone's rest frame.
    bm.transform(arm_data.bones[bone].matrix_local.inverted())
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(MATS[m])
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    ob["joint"] = bone
    scene.collection.objects.link(ob)
    PROPS.append(ob)
    return ob


hand_l = Vector((0.04, 0.225, 0.8))
hand_r = Vector((0.04, -0.225, 0.8))

# Bow: a recurve, held upright in the left hand (as in the reference drawing).
bow_pts = []
for k in range(15):
    t = k / 14 * 2 - 1
    z = t * 0.66
    x = 0.07 * (1 - t * t) - 0.05 * abs(t) ** 6 + 0.03
    bow_pts.append(hand_l + Vector((x, 0, z)))
string = [bow_pts[0], bow_pts[-1]]
prop("Prop_Bow", [(tube(bow_pts, lambda u: 0.016 - 0.008 * abs(u * 2 - 1), "Wood"), "Wood"),
                  (tube(string, 0.003, "String", 3), "String")], "hand.L")

# Quiver at the right hip, with fletched arrows.
q0 = Vector((-0.02, -0.21, 0.66))
q1 = Vector((0.03, -0.24, 1.0))
parts = [(tube([q0, q1], 0.045, "Tunic", 10), "Tunic")]
for k in range(5):
    o = Vector(((k % 3 - 1) * 0.015, (k // 3 - 0.5) * 0.02, 0))
    parts.append((tube([q1 + o + Vector((0, 0, -0.1)), q1 + o + Vector((0.02, -0.01, 0.12))], 0.005, "Wood", 3), "Wood"))
prop("Prop_Quiver", parts, "hips")

# Sword in the right hand, pointing forward and down; round shield on the left forearm.
prop("Prop_Sword", [(tube([hand_r + Vector((-0.02, 0, 0.03)), hand_r + Vector((0.04, 0, -0.05))], 0.018, "Wood", 6), "Wood"),
                    (tube([hand_r + Vector((0.04, 0, -0.05)), hand_r + Vector((0.42, 0, -0.5))],
                          lambda u: 0.022 * (1 - u * 0.7), "Metal", 4), "Metal")], "hand.R")
sh = bmesh.new()
bmesh.ops.create_cone(sh, cap_ends=True, segments=16, radius1=0.24, radius2=0.2, depth=0.04)
for v in sh.verts:
    v.co = Matrix.Rotation(math.pi / 2, 3, "X") @ v.co + Vector((0.02, 0.29, 1.02))
prop("Prop_Shield", [(sh, "Tunic")], "forearm.L")

# Pike: a long shaft held upright in the right hand.
prop("Prop_Pike", [(tube([hand_r + Vector((0, 0, -0.75)), hand_r + Vector((0, 0, 2.2))], 0.016, "Wood", 6), "Wood"),
                   (tube([hand_r + Vector((0, 0, 2.2)), hand_r + Vector((0, 0, 2.45))], lambda u: 0.03 * (1 - u), "Metal", 4), "Metal")],
     "hand.R")

# Flag: pole and pennant in the right hand.
fp0 = hand_r + Vector((0, 0, -0.55))
fp1 = hand_r + Vector((0, 0, 1.75))
pen = bmesh.new()
a = pen.verts.new(fp1 + Vector((0, -0.01, -0.02)))
b = pen.verts.new(fp1 + Vector((0, -0.62, -0.18)))
c = pen.verts.new(fp1 + Vector((0, -0.01, -0.42)))
pen.faces.new((a, b, c))
pen2 = bmesh.new()
a = pen2.verts.new(fp1 + Vector((0, -0.01, -0.02)))
b = pen2.verts.new(fp1 + Vector((0, -0.62, -0.18)))
c = pen2.verts.new(fp1 + Vector((0, -0.01, -0.42)))
pen2.faces.new((a, c, b))  # back side
prop("Prop_Flag", [(tube([fp0, fp1], 0.017, "Wood", 6), "Wood"), (pen, "Pennant"), (pen2, "Pennant")], "hand.R")

# --- animation ------------------------------------------------------------------------
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"

REST = {b.name: b.matrix_local.to_3x3() for b in arm_data.bones}
FWD = Vector((0, -1, 0))  # rotating a hanging limb about -Y swings it forward (+X)
OUT_L = Vector((-1, 0, 0))  # about -X: left arm swings outward (+Y)
UP = Vector((0, 0, 1))


def rot(bone, axis, deg):
    """A rotation about a world (rest-pose) axis, expressed in the bone's local frame."""
    a = REST[bone].inverted() @ Vector(axis)
    return Quaternion(a.normalized(), math.radians(deg))


def pose(frame, spec, loc=None):
    """spec: {bone: [(axis, degrees), ...]} applied in order; unlisted bones rest."""
    for pb in arm.pose.bones:
        q = Quaternion()
        for axis, deg in spec.get(pb.name, []):
            q = rot(pb.name, axis, deg) @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.location = (0, 0, 0)
        if pb.name == "hips" and loc is not None:
            # Bone-local offset for the hips (Y is up along the bone).
            pb.location = REST["hips"].inverted() @ Vector(loc)
        pb.keyframe_insert("location", frame=frame)


def action(name, keys, loop):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, spec, loc in keys:
        pose(frame, spec, loc)
    act.use_fake_user = True
    act["loop"] = loop
    return act


def arms_rest(extra=None):
    d = {"upper_arm.L": [(OUT_L, 6)], "upper_arm.R": [((1, 0, 0), 6)],
         "forearm.L": [(FWD, 8)], "forearm.R": [(FWD, 8)]}
    if extra:
        for k, v in extra.items():
            d[k] = d.get(k, []) + v
    return d


# Idle: still, with a slow breath.
action("Idle", [(0, arms_rest(), (0, 0, 0)),
                (30, arms_rest({"chest": [((0, 1, 0), -1.5)]}), (0, 0, 0.004)),
                (60, arms_rest(), (0, 0, 0))], True)


# Walk: restrained stride (1 s = two steps), arms swing opposite to legs.
def walk_pose(ph):
    s = math.sin(ph)
    c = math.cos(ph)
    sw = 24
    kneeL = max(0.0, -c) * 38 + 6
    kneeR = max(0.0, c) * 38 + 6
    spec = arms_rest({
        "thigh.L": [(FWD, s * sw)], "thigh.R": [(FWD, -s * sw)],
        "shin.L": [(FWD, -kneeL)], "shin.R": [(FWD, -kneeR)],
        "foot.L": [(FWD, max(0, s) * 10)], "foot.R": [(FWD, max(0, -s) * 10)],
        "upper_arm.L": [(FWD, -s * 16)], "upper_arm.R": [(FWD, s * 16)],
        "forearm.L": [(FWD, 6 + max(0, -s) * 10)], "forearm.R": [(FWD, 6 + max(0, s) * 10)],
        "hips": [(UP, s * 5)], "chest": [(UP, -s * 6), ((0, 1, 0), -3)],
    })
    return spec, (0, 0, -0.025 + abs(math.cos(ph)) * 0.025)


action("Walk", [(f, *walk_pose(f / 30 * 2 * math.pi)) for f in range(0, 31, 3)], True)


# Shoot: raise the bow, draw to the cheek, loose, lower.
def shoot(t):
    raise_ = min(1, t / 0.3) if t < 0.85 else max(0, 1 - (t - 0.85) / 0.15)
    draw = 0 if t < 0.3 else (min(1, (t - 0.3) / 0.35) if t < 0.7 else 0.3)
    spec = {
        "hips": [(UP, 30 * raise_)], "chest": [(UP, -10 * raise_)],
        "upper_arm.L": [(FWD, 85 * raise_), (UP, -25 * raise_)],
        "forearm.L": [(FWD, 4)],
        "hand.L": [(FWD, -85 * raise_)],
        "upper_arm.R": [(FWD, 80 * raise_), (UP, 15 * raise_ + 40 * draw)],
        "forearm.R": [(FWD, 20 * raise_ + 110 * draw)],
    }
    return spec, (0, 0, 0)


action("Shoot", [(f, *shoot(f / 45)) for f in range(0, 46, 3)], False)


# Slash: wind up over the shoulder, cut down and across.
def slash(t):
    up_ = math.sin(min(1, t / 0.4) * math.pi / 2) if t < 0.4 else 0
    cut = 0 if t < 0.4 else min(1, (t - 0.4) / 0.2)
    back = 0 if t < 0.75 else (t - 0.75) / 0.25
    a = up_ * (1 - cut)
    spec = arms_rest({
        "upper_arm.R": [(FWD, 150 * a + 40 * cut * (1 - back)), (UP, -30 * cut * (1 - back))],
        "forearm.R": [(FWD, 40 * a + 10 * cut)],
        "chest": [(UP, 20 * a - 25 * cut * (1 - back))],
        "upper_arm.L": [(FWD, 30 * (a + cut) * (1 - back))],
    })
    return spec, (0, 0, -0.03 * cut * (1 - back))


action("Slash", [(f, *slash(f / 30)) for f in range(0, 31, 2)], False)


# Thrust: drop the pike level and lunge.
def thrust(t):
    lv = min(1, t / 0.3) if t < 0.8 else max(0, 1 - (t - 0.8) / 0.2)
    lunge = 0 if t < 0.35 else (min(1, (t - 0.35) / 0.15) if t < 0.65 else max(0, 1 - (t - 0.65) / 0.15))
    spec = arms_rest({
        "upper_arm.R": [(FWD, 55 * lv + 25 * lunge)],
        "forearm.R": [(FWD, 30 * lv)],
        "hand.R": [(FWD, 70 * lv)],
        "upper_arm.L": [(FWD, 50 * lv + 20 * lunge)],
        "forearm.L": [(FWD, 40 * lv)],
        "chest": [((0, 1, 0), -12 * lunge)],
        "thigh.L": [(FWD, 25 * lunge)], "shin.L": [(FWD, -20 * lunge)],
        "thigh.R": [(FWD, -12 * lunge)],
    })
    return spec, (0.08 * lunge, 0, -0.05 * lunge)


action("Thrust", [(f, *thrust(f / 30)) for f in range(0, 31, 2)], False)


# Plant: lift the flag high with both hands, drive it down, stand back.
def plant(t):
    lift = math.sin(min(1, t / 0.4) * math.pi / 2) if t < 0.4 else max(0, 1 - (t - 0.4) / 0.15)
    drive = 0 if t < 0.4 else (min(1, (t - 0.4) / 0.15) if t < 0.8 else max(0, 1 - (t - 0.8) / 0.2))
    spec = arms_rest({
        "upper_arm.R": [(FWD, 70 * lift + 35 * drive)],
        "forearm.R": [(FWD, 40 * lift + 20 * drive)],
        "upper_arm.L": [(FWD, 70 * lift + 35 * drive), ((1, 0, 0), 15 * (lift + drive))],
        "forearm.L": [(FWD, 50 * (lift + drive))],
        "chest": [((0, 1, 0), -20 * drive)], "spine": [((0, 1, 0), -10 * drive)],
        "thigh.L": [(FWD, 20 * drive)], "shin.L": [(FWD, -30 * drive)],
        "thigh.R": [(FWD, 10 * drive)], "shin.R": [(FWD, -30 * drive)],
    })
    return spec, (0, 0, 0.05 * lift - 0.1 * drive)


action("Plant", [(f, *plant(f / 60)) for f in range(0, 61, 3)], False)

bpy.ops.object.mode_set(mode="OBJECT")
arm.animation_data.action = None

# --- export ----------------------------------------------------------------------------
# Custom split normals make Blender write normals per polygon corner (ByPolygonVertex),
# which is the layout Heaps' FBX converter handles; per-vertex ("ByVertice") normals
# from recent Blender versions trip it up.
for o in bpy.data.objects:
    if o.type == "MESH":
        o.data.normals_split_custom_set_from_vertices([v.normal[:] for v in o.data.vertices])
COMMON = dict(
    add_leaf_bones=False,
    axis_up="Z",
    axis_forward="-Y",
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    use_triangles=True,
    mesh_smooth_type="OFF",
)


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)


select([arm, body])
bpy.ops.export_scene.fbx(
    filepath=OUT,
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    bake_anim=True,
    bake_anim_use_all_actions=True,
    bake_anim_use_nla_strips=False,
    bake_anim_force_startend_keying=True,
    bake_anim_simplify_factor=0.0,
    use_armature_deform_only=True,
    **COMMON,
)
# Props: static meshes, each in its holding joint's frame (CharacterView attaches them).
PROPS_OUT = OUT.replace(".fbx", "-props.fbx")
select(PROPS)
bpy.ops.export_scene.fbx(filepath=PROPS_OUT, use_selection=True, object_types={"MESH"}, bake_anim=False, **COMMON)
tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
print(f"exported {OUT} and {PROPS_OUT}: {tris} triangles, actions: {[a.name for a in bpy.data.actions]}")
print("prop joints:", {o.name: o["joint"] for o in PROPS})
