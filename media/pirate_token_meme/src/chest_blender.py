"""Build and render a stylized pirate treasure chest (Fortnite-like look) with Blender/Cycles.

Usage: python chest_blender.py OUTDIR START END SAMPLES RES
Renders RGBA PNG frames (transparent film + shadow catcher ground) at 60 fps.
Animation timeline (chest-local frames):
  0            idle
  1..96        rumble / shake, escalating, levitation starts ~45%
  97           BURST: lid flies open
  97..186      post-burst settle into hover
  187..282     hover loop (period 96 frames) -> loop-able
"""
import sys, math, json, random
import bpy
import bmesh
from mathutils import Vector, Euler
from bpy_extras.object_utils import world_to_camera_view

OUT = sys.argv[1]
START, END = int(sys.argv[2]), int(sys.argv[3])
SAMPLES = int(sys.argv[4])
RES = int(sys.argv[5])

BURST = 97
HOVER0 = 161
PERIOD = 64

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_adaptive_sampling = True
scene.cycles.adaptive_threshold = 0.03
scene.cycles.use_denoising = True
import os
THREADS = int(os.environ.get('CHEST_THREADS', '0'))
if THREADS:
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = THREADS
scene.render.use_persistent_data = True
scene.cycles.max_bounces = 4
scene.cycles.diffuse_bounces = 2
scene.cycles.glossy_bounces = 2
scene.cycles.transmission_bounces = 0
scene.cycles.volume_bounces = 0
scene.cycles.caustics_reflective = False
scene.cycles.caustics_refractive = False
scene.cycles.blur_glossy = 1.0
scene.cycles.transparent_max_bounces = 4
scene.render.film_transparent = True
scene.render.resolution_x = RES
scene.render.resolution_y = RES
scene.render.resolution_percentage = 100
scene.render.fps = 60
scene.render.use_motion_blur = True
scene.render.motion_blur_shutter = 0.5
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '16'
scene.view_settings.view_transform = 'Standard'
scene.view_settings.exposure = -0.35

# ---------------------------------------------------------------- materials

def mat_principled(name, base, metallic=0.0, rough=0.5, emis=None, emis_str=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if coat:
        b.inputs["Coat Weight"].default_value = coat
    if emis is not None:
        b.inputs["Emission Color"].default_value = (*emis, 1)
        b.inputs["Emission Strength"].default_value = emis_str
    return m


def mat_wood(name, dark, light, scale=6.0, seed=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Location"].default_value = (seed, seed * 0.37, seed * 0.11)
    mp.inputs["Scale"].default_value = (1.0, 7.0, 7.0)   # grain stretched along X
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'Y'
    wave.inputs["Scale"].default_value = scale
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    wave.inputs["Detail Scale"].default_value = 1.5
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 18.0
    noise.inputs["Detail"].default_value = 6.0
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'FLOAT'
    mix.inputs["Factor"].default_value = 0.35
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (*light, 1)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.002
    L = nt.links
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    L.new(mp.outputs["Vector"], wave.inputs["Vector"])
    L.new(mp.outputs["Vector"], noise.inputs["Vector"])
    L.new(wave.outputs["Fac"], mix.inputs["A"])
    L.new(noise.outputs["Fac"], mix.inputs["B"])
    L.new(mix.outputs["Result"], ramp.inputs["Fac"])
    L.new(ramp.outputs["Color"], b.inputs["Base Color"])
    L.new(mix.outputs["Result"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.62
    return m


WOOD = [mat_wood(f"Wood{i}", (0.045, 0.016, 0.006), (0.30, 0.11, 0.035), seed=i * 3.1) for i in range(4)]
WOOD_IN = mat_wood("WoodIn", (0.03, 0.012, 0.005), (0.12, 0.05, 0.02), seed=9.0)
GOLD = mat_principled("Gold", (1.0, 0.66, 0.22), metallic=1.0, rough=0.22, emis=(1.0, 0.6, 0.15), emis_str=0.0)
IRON = mat_principled("Iron", (0.03, 0.025, 0.02), metallic=0.7, rough=0.45)
TREASURE = mat_principled("Treasure", (1.0, 0.7, 0.2), metallic=1.0, rough=0.2, emis=(1.0, 0.62, 0.18), emis_str=4.0)

# ---------------------------------------------------------------- geometry helpers

def link(obj, parent=None):
    scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def bevel(obj, w=0.006, seg=2):
    md = obj.modifiers.new("Bevel", 'BEVEL')
    md.width = w
    md.segments = seg
    md.limit_method = 'ANGLE'
    return obj


def box(name, center, size, mat, parent=None, bev=0.006, seg=2):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + center[0], v.co.y * size[1] + center[1], v.co.z * size[2] + center[2]))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    link(ob, parent)
    if bev:
        bevel(ob, bev, seg)
    return ob


def shell(name, x0, x1, r0, r1, a0, a1, cy, cz, kz, mat, parent=None, n=24, bev=0.004):
    """Curved slat: cylinder shell segment along X, angle a from 0 (back) to pi (front)."""
    me = bpy.data.meshes.new(name)
    verts, faces = [], []
    steps = max(2, int(n * (a1 - a0) / math.pi) + 1)
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        for r in (r0, r1):
            y = cy + r * math.cos(a)
            z = cz + r * math.sin(a) * kz
            verts.append((x0, y, z))
            verts.append((x1, y, z))
    # index: ring i, radius j (0 inner,1 outer), side k (0 x0, 1 x1)
    def idx(i, j, k):
        return i * 4 + j * 2 + k
    for i in range(steps):
        faces.append((idx(i, 1, 0), idx(i, 1, 1), idx(i + 1, 1, 1), idx(i + 1, 1, 0)))  # outer
        faces.append((idx(i, 0, 0), idx(i + 1, 0, 0), idx(i + 1, 0, 1), idx(i, 0, 1)))  # inner
        faces.append((idx(i, 0, 0), idx(i, 1, 0), idx(i + 1, 1, 0), idx(i + 1, 0, 0)))  # side x0
        faces.append((idx(i, 0, 1), idx(i + 1, 0, 1), idx(i + 1, 1, 1), idx(i, 1, 1)))  # side x1
    faces.append((idx(0, 0, 0), idx(0, 0, 1), idx(0, 1, 1), idx(0, 1, 0)))
    faces.append((idx(steps, 0, 0), idx(steps, 1, 0), idx(steps, 1, 1), idx(steps, 0, 1)))
    me.from_pydata(verts, [], faces)
    me.update()
    me.validate()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    link(ob, parent)
    if bev:
        bevel(ob, bev, 2)
    return ob


def semi_disc(name, xc, thick, R, cy, cz, kz, mat, parent=None, n=32):
    bm = bmesh.new()
    pts = []
    for i in range(n + 1):
        a = math.pi * i / n
        pts.append((cy + R * math.cos(a), cz + R * math.sin(a) * kz))
    v0 = [bm.verts.new((xc - thick / 2, y, z)) for y, z in pts]
    v1 = [bm.verts.new((xc + thick / 2, y, z)) for y, z in pts]
    bm.faces.new(v0)
    bm.faces.new(list(reversed(v1)))
    for i in range(n):
        bm.faces.new((v0[i], v0[i + 1], v1[i + 1], v1[i]))
    bm.faces.new((v0[n], v0[0], v1[0], v1[n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    link(ob, parent)
    bevel(ob, 0.004, 2)
    return ob


def sphere(name, loc, r, mat, parent=None, scale=(1, 1, 1), seg=12):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2 + 2, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0] + loc[0], v.co.y * scale[1] + loc[1], v.co.z * scale[2] + loc[2]))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    link(ob, parent)
    return ob


def cylinder(name, loc, r, h, mat, parent=None, rot=(0, 0, 0), seg=24):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=h)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    ob.location = loc
    ob.rotation_euler = rot
    link(ob, parent)
    bevel(ob, 0.0015, 1)
    return ob


# ---------------------------------------------------------------- chest
W, D, HB = 0.80, 0.50, 0.36
R = D / 2
KZ = 0.82          # flattened dome
T = 0.028          # plank thickness

root = bpy.data.objects.new("ChestRoot", None)   # ground anchor (tracked point)
link(root)
chest = bpy.data.objects.new("Chest", None)      # animated (shake / levitate)
link(chest, root)
root.rotation_euler = (0, 0, math.radians(22))

# inner liner (dark) - open box (no top)
box("LinerBottom", (0, 0, 0.03), (W - 0.06, D - 0.06, 0.02), WOOD_IN, chest, bev=0)
box("LinerF", (0, -D / 2 + 0.04, HB / 2 + 0.01), (W - 0.06, 0.012, HB - 0.02), WOOD_IN, chest, bev=0)
box("LinerB", (0, D / 2 - 0.04, HB / 2 + 0.01), (W - 0.06, 0.012, HB - 0.02), WOOD_IN, chest, bev=0)
box("LinerL", (-W / 2 + 0.04, 0, HB / 2 + 0.01), (0.012, D - 0.06, HB - 0.02), WOOD_IN, chest, bev=0)
box("LinerR", (W / 2 - 0.04, 0, HB / 2 + 0.01), (0.012, D - 0.06, HB - 0.02), WOOD_IN, chest, bev=0)

# planks: 3 rows on every side
z_lo, z_hi = 0.045, HB - 0.03
ph = (z_hi - z_lo) / 3
k = 0
for row in range(3):
    zc = z_lo + ph * (row + 0.5)
    hh = ph - 0.008
    for sgn in (-1, 1):
        box(f"PlankFB{row}{sgn}", (0, sgn * (D / 2 - T / 2), zc), (W - 0.01, T, hh), WOOD[k % 4], chest, bev=0.007); k += 1
        box(f"PlankLR{row}{sgn}", (sgn * (W / 2 - T / 2), 0, zc), (T, D - 2 * T, hh), WOOD[k % 4], chest, bev=0.007); k += 1
# bottom slab
box("Bottom", (0, 0, 0.022), (W - 0.01, D - 0.01, 0.045), WOOD[1], chest, bev=0.006)

# gold trims on body
GT = 0.014
box("TrimBot", (0, 0, 0.026), (W + 0.022, D + 0.022, 0.05), GOLD, chest, bev=0.006, seg=3)
box("TrimTopF", (0, -D / 2 - 0.004, HB - 0.018), (W + 0.02, GT, 0.036), GOLD, chest, bev=0.005, seg=3)
box("TrimTopB", (0, D / 2 + 0.004, HB - 0.018), (W + 0.02, GT, 0.036), GOLD, chest, bev=0.005, seg=3)
box("TrimTopL", (-W / 2 - 0.004, 0, HB - 0.018), (GT, D + 0.02, 0.036), GOLD, chest, bev=0.005, seg=3)
box("TrimTopR", (W / 2 + 0.004, 0, HB - 0.018), (GT, D + 0.02, 0.036), GOLD, chest, bev=0.005, seg=3)
BX = 0.255
for sx in (-1, 1):
    for sy in (-1, 1):
        box(f"Band{sx}{sy}", (sx * BX, sy * (D / 2 + 0.003), HB / 2), (0.062, GT, HB), GOLD, chest, bev=0.005, seg=3)
        # corner brackets
        box(f"CornerA{sx}{sy}", (sx * (W / 2 - 0.03), sy * (D / 2 + 0.006), HB / 2), (0.075, GT, HB + 0.004), GOLD, chest, bev=0.005, seg=3)
        box(f"CornerB{sx}{sy}", (sx * (W / 2 + 0.006), sy * (D / 2 - 0.03), HB / 2), (GT, 0.075, HB + 0.004), GOLD, chest, bev=0.005, seg=3)
        for z in (0.1, 0.19, 0.28):
            sphere(f"Rivet{sx}{sy}{z}", (sx * BX, sy * (D / 2 + 0.012), z), 0.011, GOLD, chest)
# lock plate + skull emblem
box("LockPlate", (0, -D / 2 - 0.012, 0.215), (0.15, 0.016, 0.16), GOLD, chest, bev=0.012, seg=4)
box("LockInset", (0, -D / 2 - 0.021, 0.205), (0.11, 0.006, 0.11), IRON, chest, bev=0.004, seg=2)
skull_curve = bpy.data.curves.new("Skull", type='FONT')
skull_curve.body = "☠"
skull_curve.font = bpy.data.fonts.load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
skull_curve.size = 0.115
skull_curve.extrude = 0.004
skull_curve.align_x = 'CENTER'
skull_curve.align_y = 'CENTER'
skull = bpy.data.objects.new("SkullObj", skull_curve)
skull.data.materials.append(GOLD)
skull.location = (0, -D / 2 - 0.026, 0.203)
skull.rotation_euler = (math.radians(90), 0, 0)
link(skull, chest)

# treasure (glowing gold pile) inside
sphere("Pile", (0, 0, HB - 0.07), 1.0, TREASURE, chest, scale=(W * 0.40, D * 0.36, 0.11), seg=24)
rnd = random.Random(7)
for i in range(26):
    x = rnd.uniform(-W * 0.33, W * 0.33)
    y = rnd.uniform(-D * 0.28, D * 0.28)
    zz = HB - 0.07 + 0.11 * math.sqrt(max(0.0, 1 - (x / (W * 0.40)) ** 2 - (y / (D * 0.36)) ** 2)) + 0.004
    cylinder(f"Coin{i}", (x, y, zz), 0.03, 0.007, TREASURE, chest,
             rot=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0))
glow_light = bpy.data.lights.new("InnerGlow", type='POINT')
glow_light.color = (1.0, 0.68, 0.25)
glow_light.energy = 0.0
glow_light.shadow_soft_size = 0.15
gl = bpy.data.objects.new("InnerGlow", glow_light)
gl.location = (0, 0, HB + 0.12)
link(gl, chest)

# lid
pivot = bpy.data.objects.new("LidPivot", None)
link(pivot, chest)
pivot.location = (0, D / 2, HB)
cy, cz = -D / 2, 0.0       # dome centre relative to pivot
nsl = 5
gap = 0.022
for i in range(nsl):
    a0 = math.pi * i / nsl + gap / 2
    a1 = math.pi * (i + 1) / nsl - gap / 2
    shell(f"LidSlat{i}", -W / 2 + 0.012, W / 2 - 0.012, R - T, R, a0, a1, cy, cz, KZ, WOOD[i % 4], pivot)
shell("LidInner", -W / 2 + 0.03, W / 2 - 0.03, R - T - 0.012, R - T - 0.002, 0.02, math.pi - 0.02, cy, cz, KZ, WOOD_IN, pivot, bev=0)
for sx in (-1, 1):
    semi_disc(f"LidEnd{sx}", sx * (W / 2 - 0.016), 0.03, R - 0.004, cy, cz, KZ, WOOD[2], pivot)
    shell(f"LidEdge{sx}", sx * (W / 2 + 0.008) - 0.024, sx * (W / 2 + 0.008) + 0.024, R - 0.006, R + 0.012, -0.02, math.pi + 0.02, cy, cz, KZ, GOLD, pivot)
    shell(f"LidBand{sx}", sx * BX - 0.031, sx * BX + 0.031, R - 0.004, R + 0.012, -0.02, math.pi + 0.02, cy, cz, KZ, GOLD, pivot)
    for j in range(1, 6):
        a = math.pi * j / 6
        rr = R + 0.014
        sphere(f"LidRivet{sx}{j}", (sx * BX, cy + rr * math.cos(a), cz + rr * math.sin(a) * KZ), 0.011, GOLD, pivot)
box("LidRimF", (0, cy - R - 0.004, 0.018), (W + 0.02, GT, 0.036), GOLD, pivot, bev=0.005, seg=3)
box("LidRimB", (0, cy + R + 0.004, 0.018), (W + 0.02, GT, 0.036), GOLD, pivot, bev=0.005, seg=3)
box("Hasp", (0, cy - R - 0.016, -0.03), (0.06, 0.016, 0.11), GOLD, pivot, bev=0.008, seg=3)
cylinder("Keyhole", (0, cy - R - 0.026, -0.045), 0.011, 0.008, IRON, pivot, rot=(math.radians(90), 0, 0), seg=16)

# ---------------------------------------------------------------- ground / shadow catcher
gme = bpy.data.meshes.new("Ground")
gme.from_pydata([(-4, -4, 0), (4, -4, 0), (4, 4, 0), (-4, 4, 0)], [], [(0, 1, 2, 3)])
ground = bpy.data.objects.new("Ground", gme)
ground.data.materials.append(mat_principled("GroundMat", (0.25, 0.22, 0.2), rough=0.9))
link(ground)
ground.is_shadow_catcher = True

# ---------------------------------------------------------------- world + lights
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
bg = wn.get("Background")
tc = wn.new("ShaderNodeTexCoord")
sep = wn.new("ShaderNodeSeparateXYZ")
ramp = wn.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.40
ramp.color_ramp.elements[0].color = (0.05, 0.04, 0.045, 1)   # ground (dark purple/brown)
ramp.color_ramp.elements[1].position = 0.56
ramp.color_ramp.elements[1].color = (0.55, 0.58, 0.56, 1)    # pale wall
mapr = wn.new("ShaderNodeMapRange")
mapr.inputs["From Min"].default_value = -1.0
mapr.inputs["From Max"].default_value = 1.0
wl.new(tc.outputs["Generated"], sep.inputs["Vector"])
wl.new(sep.outputs["Z"], mapr.inputs["Value"])
wl.new(mapr.outputs["Result"], ramp.inputs["Fac"])
wl.new(ramp.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 0.55

key_d = bpy.data.lights.new("Key", type='AREA')
key_d.energy = 900
key_d.size = 1.6
key_d.color = (1.0, 0.92, 0.80)
key = bpy.data.objects.new("Key", key_d)
key.location = (-2.6, -3.0, 3.2)
link(key)
tgt = bpy.data.objects.new("Target", None)
tgt.location = (0, 0, 0.3)
link(tgt)
c = key.constraints.new('TRACK_TO')
c.target = tgt
c.track_axis = 'TRACK_NEGATIVE_Z'
c.up_axis = 'UP_Y'

rim_d = bpy.data.lights.new("Rim", type='AREA')
rim_d.energy = 160
rim_d.size = 2.0
rim_d.color = (0.85, 0.95, 1.0)
rim = bpy.data.objects.new("Rim", rim_d)
rim.location = (2.5, 2.5, 2.2)
link(rim)
c = rim.constraints.new('TRACK_TO')
c.target = tgt
c.track_axis = 'TRACK_NEGATIVE_Z'
c.up_axis = 'UP_Y'

# ---------------------------------------------------------------- camera
cam_d = bpy.data.cameras.new("Cam")
cam_d.lens = 50
cam_d.sensor_width = 36
cam_d.shift_y = 0.12
cam = bpy.data.objects.new("Cam", cam_d)
PITCH = 35.0
DIST = 2.5
cam.location = (0, -DIST * math.cos(math.radians(PITCH)), 0.3 + DIST * math.sin(math.radians(PITCH)))
cam.rotation_euler = (math.radians(90 - PITCH), 0, 0)
link(cam)
scene.camera = cam

# ---------------------------------------------------------------- animation

def smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


rng = random.Random(1234)
jit = [(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1), rng.random())
       for _ in range(400)]


def state(f):
    """returns (loc, rot_deg, lid_deg, inner_emission, light_energy, gold_emis)"""
    loc = [0.0, 0.0, 0.0]
    rot = [0.0, 0.0, 0.0]
    lid = 0.0
    if f <= 0:
        return loc, rot, 0.0, 1.5, 0.0, 0.0
    j = jit[f % 400]
    if f < BURST:
        t = f / (BURST - 1)
        e = t ** 1.4
        # rumble bursts: stronger on beats
        beat = 0.6 + 0.4 * abs(math.sin(f * 0.9))
        amp = e * beat
        loc = [amp * 0.012 * j[0], amp * 0.012 * j[1], amp * 0.010 * abs(j[2])]
        rot = [amp * 3.5 * j[3], amp * 3.5 * j[4], amp * 5.0 * j[5]]
        lev = 0.085 * smooth(0.40, 1.0, t)
        loc[2] += lev + lev * 0.15 * math.sin(f * 0.5)
        lid = e * (2.0 + 6.0 * j[6])   # rattle -> light leaks out
        inner = 0.5 + 2.5 * e
        light = 22 * e
        gold = 0.12 * e
        return loc, rot, lid, inner, light, gold
    # burst & after
    fb = f - BURST
    # lid: fast open with overshoot then damped settle to 108 deg
    if fb <= 6:
        x = fb / 6.0
        lid = 124 * (1 - (1 - x) ** 3)
    else:
        x = (fb - 6) / 60.0
        lid = 108 + 16 * math.exp(-4.0 * x) * math.cos(9.0 * x)
    # vertical kick then hover
    hover = 0.13 + 0.018 * math.sin(2 * math.pi * (f - HOVER0) / PERIOD)
    kick = 0.10 * math.exp(-fb / 6.0) * math.sin(fb / 2.2)
    settle = smooth(0, 40, fb)
    base = 0.085 * (1 - settle) + hover * settle
    loc = [0, 0, base + kick]
    shake = math.exp(-fb / 10.0)
    loc[0] += shake * 0.015 * j[0]
    loc[1] += shake * 0.015 * j[1]
    rot = [shake * 5 * j[3] + 1.5 * math.sin(2 * math.pi * (f - HOVER0) / PERIOD + 1.0) * settle,
           shake * 5 * j[4] + 1.2 * math.sin(2 * math.pi * (f - HOVER0) / PERIOD * 2 + 0.3) * settle,
           shake * 6 * j[5]]
    inner = 2.6 + 3.5 * math.exp(-fb / 12.0)
    light = 45 + 120 * math.exp(-fb / 10.0)
    gold = 0.1 + 0.25 * math.exp(-fb / 12.0)
    return loc, rot, lid, inner, light, gold


tre_emis = TREASURE.node_tree.nodes.get("Principled BSDF").inputs["Emission Strength"]
gold_emis = GOLD.node_tree.nodes.get("Principled BSDF").inputs["Emission Strength"]
for f in range(-2, 300):
    loc, rot, lid, inner, light, gold = state(f)
    chest.location = loc
    chest.rotation_euler = Euler([math.radians(r) for r in rot])
    pivot.rotation_euler = Euler((-math.radians(lid), 0, 0))
    chest.keyframe_insert("location", frame=f)
    chest.keyframe_insert("rotation_euler", frame=f)
    pivot.keyframe_insert("rotation_euler", frame=f)
    tre_emis.default_value = inner
    tre_emis.keyframe_insert("default_value", frame=f)
    gold_emis.default_value = gold
    gold_emis.keyframe_insert("default_value", frame=f)
    glow_light.energy = light
    glow_light.keyframe_insert("energy", frame=f)

# linear interpolation for crisp shake
def make_linear(idb):
    ad = idb.animation_data
    if not ad or not ad.action:
        return
    act = ad.action
    curves = []
    if hasattr(act, "fcurves"):
        try:
            curves = list(act.fcurves)
        except Exception:
            curves = []
    if not curves and hasattr(act, "layers"):
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    curves += list(cb.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'

for idb in (chest, pivot, TREASURE.node_tree, GOLD.node_tree, glow_light):
    make_linear(idb)

# ---------------------------------------------------------------- projection info
scene.frame_set(0)
bpy.context.view_layer.update()
info = {}
for nm, p in {"anchor": (0, 0, 0), "left": (-W / 2, 0, 0), "right": (W / 2, 0, 0), "mouth": (0, 0, HB)}.items():
    wp = root.matrix_world @ Vector(p)
    co = world_to_camera_view(scene, cam, wp)
    info[nm] = (co.x * RES, (1 - co.y) * RES)
# chest-mouth position follows the chest: store per frame for the light-beam origin
mouth = {}
for f in range(0, 300):
    scene.frame_set(f)
    wp = chest.matrix_world @ Vector((0, 0, HB + 0.02))
    co = world_to_camera_view(scene, cam, wp)
    mouth[f] = (co.x * RES, (1 - co.y) * RES)
info["mouth_per_frame"] = mouth
info["res"] = RES
with open(f"{OUT}/chest_info.json", "w") as fh:
    json.dump(info, fh)

# ---------------------------------------------------------------- render
scene.frame_start = START
scene.frame_end = END
scene.render.filepath = f"{OUT}/c_####"
bpy.ops.render.render(animation=True)
print("DONE")
