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


# ---------------------------------------------------------------- chest (Fortnite-style pirate chest, from the user's reference)
from mathutils import Matrix

W, D, HB = 0.82, 0.62, 0.36        # body width / depth / height
LH = 0.20                           # vertical part of the lid front
R = D / 2
KZ = 0.42                           # barrel-top flattening
T = 0.028

# extra materials
WOODW = [mat_wood(f"WoodW{i}", (0.10, 0.045, 0.015), (0.42, 0.22, 0.08), scale=5.0, seed=i * 2.3 + 1) for i in range(3)]
GOLDC = mat_principled("GoldC", (1.0, 0.70, 0.17), metallic=1.0, rough=0.30)
GOLD_EM = GOLD   # keep animated emission hook name


def mat_moss(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 9.0
    nz.inputs["Detail"].default_value = 6.0
    nz.inputs["Roughness"].default_value = 0.65
    rc = nt.nodes.new("ShaderNodeValToRGB")
    rc.color_ramp.elements[0].position = 0.52
    rc.color_ramp.elements[0].color = (0.62, 0.62, 0.58, 1)
    rc.color_ramp.elements[1].position = 0.60
    rc.color_ramp.elements[1].color = (0.22, 0.30, 0.09, 1)
    rr = nt.nodes.new("ShaderNodeValToRGB")
    rr.color_ramp.elements[0].position = 0.52
    rr.color_ramp.elements[0].color = (0.38, 0.38, 0.38, 1)
    rr.color_ramp.elements[1].position = 0.60
    rr.color_ramp.elements[1].color = (0.85, 0.85, 0.85, 1)
    mm = nt.nodes.new("ShaderNodeValToRGB")
    mm.color_ramp.elements[0].position = 0.52
    mm.color_ramp.elements[0].color = (0.75, 0.75, 0.75, 1)
    mm.color_ramp.elements[1].position = 0.60
    mm.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1)
    L = nt.links
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    L.new(nz.outputs["Fac"], rc.inputs["Fac"])
    L.new(nz.outputs["Fac"], rr.inputs["Fac"])
    L.new(nz.outputs["Fac"], mm.inputs["Fac"])
    L.new(rc.outputs["Color"], b.inputs["Base Color"])
    L.new(rr.outputs["Color"], b.inputs["Roughness"])
    L.new(mm.outputs["Color"], b.inputs["Metallic"])
    return m


BONE = mat_moss("SkullMoss")
DARK = mat_principled("Dark", (0.02, 0.015, 0.012), rough=0.6)
PINK = mat_principled("Pink", (0.85, 0.06, 0.70), metallic=0.0, rough=0.06, emis=(0.95, 0.12, 0.80), emis_str=0.35, coat=1.0)
ORANGE = mat_principled("Orange", (1.0, 0.20, 0.01), metallic=0.0, rough=0.06, emis=(1.0, 0.22, 0.01), emis_str=1.2, coat=1.0)
CYAN = mat_principled("Cyan", (0.02, 0.55, 1.0), metallic=0.0, rough=0.05, emis=(0.02, 0.6, 1.0), emis_str=1.6, coat=1.0)


def mesh_obj(name, verts, faces, mat, parent, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update(); me.validate()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = smooth
    link(ob, parent)
    return ob


def gem(name, loc, r, sides, mat, parent, rot=(math.radians(90), 0, 0), crown=0.45, table=0.55, pav=0.55):
    """faceted gem along +Z (crown up), then rotated (default: facing front -Y)"""
    v = []
    f = []
    for i in range(sides):
        a = 2 * math.pi * (i + 0.5) / sides
        v.append((r * math.cos(a), r * math.sin(a), 0.0))
    for i in range(sides):
        a = 2 * math.pi * i / sides
        v.append((r * table * math.cos(a), r * table * math.sin(a), r * crown))
    v.append((0, 0, r * crown))          # table centre
    v.append((0, 0, -r * pav))           # culet
    ct, cu = 2 * sides, 2 * sides + 1
    for i in range(sides):
        j = (i + 1) % sides
        f.append((i, j, sides + j))
        f.append((i, sides + j, sides + i))
        f.append((sides + i, sides + j, ct))
        f.append((j, i, cu))
    ob = mesh_obj(name, v, f, mat, parent)
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def torus(name, loc, Rm, rm, mat, parent, basis, su=16, sv=8, stretch=1.0):
    v, f = [], []
    for i in range(su):
        u = 2 * math.pi * i / su
        cx, cy = math.cos(u) * (Rm * stretch), math.sin(u) * Rm
        for j in range(sv):
            w = 2 * math.pi * j / sv
            nx, ny = math.cos(u), math.sin(u)
            v.append((cx + nx * rm * math.cos(w), cy + ny * rm * math.cos(w), rm * math.sin(w)))
    for i in range(su):
        for j in range(sv):
            a = i * sv + j
            b = ((i + 1) % su) * sv + j
            c = ((i + 1) % su) * sv + (j + 1) % sv
            d = i * sv + (j + 1) % sv
            f.append((a, b, c, d))
    ob = mesh_obj(name, v, f, mat, parent, smooth=True)
    ob.matrix_local = Matrix.Translation(loc) @ basis.to_4x4()
    return ob


def bone(name, p0, p1, width, mat, parent, yf):
    """flat-ish bone relief in the front plane between p0 and p1 (x,z), at depth y = yf"""
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dz)
    ang = math.atan2(dz, dx)
    cx, cz = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    ob = box(name, (0, 0, 0), (L, 0.022, width), mat, parent, bev=width * 0.35, seg=3)
    ob.location = (cx, yf, cz)
    ob.rotation_euler = (0, -ang, 0)
    for sgn in (-1, 1):   # knobbly bone ends
        ex, ez = p1 if sgn > 0 else p0
        nx, nz = -math.sin(ang), math.cos(ang)
        for k in (-1, 1):
            sphere(f"{name}_k{sgn}{k}", (ex + nx * k * width * 0.45, yf, ez + nz * k * width * 0.45), width * 0.42, mat, parent,
                   scale=(1, 0.55, 1), seg=14)
    return ob


def chain(name, p0, p1, p2, yf, parent, n=None):
    """gold chain along a quadratic bezier in the front plane (x,z) at depth yf"""
    pts = []
    for i in range(400):
        s = i / 399
        x = (1 - s) ** 2 * p0[0] + 2 * (1 - s) * s * p1[0] + s * s * p2[0]
        z = (1 - s) ** 2 * p0[1] + 2 * (1 - s) * s * p1[1] + s * s * p2[1]
        pts.append((x, z))
    seg = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(399)]
    total = sum(seg)
    step = 0.040
    acc, k, target, idx = 0.0, 0, 0.0, 0
    links = []
    for i in range(399):
        while acc + seg[i] >= target:
            fr = (target - acc) / seg[i]
            x = pts[i][0] + (pts[i + 1][0] - pts[i][0]) * fr
            z = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * fr
            tx, tz = (pts[i + 1][0] - pts[i][0]) / seg[i], (pts[i + 1][1] - pts[i][1]) / seg[i]
            links.append((x, z, tx, tz))
            target += step
        acc += seg[i]
    for li, (x, z, tx, tz) in enumerate(links):
        t = Vector((tx, 0, tz)).normalized()
        if li % 2 == 0:
            nrm = Vector((0, -1, 0))                    # ring faces the viewer
        else:
            nrm = t.cross(Vector((0, -1, 0))).normalized()  # ring edge-on
        yv = nrm.cross(t).normalized()
        basis = Matrix((t, yv, nrm)).transposed()
        torus(f"{name}{li}", Vector((x, yf - (0.006 if li % 2 else 0.0), z)), 0.019, 0.0068, GOLDC, parent, basis, stretch=1.45)


root = bpy.data.objects.new("ChestRoot", None)   # ground anchor (tracked point)
link(root)
chest = bpy.data.objects.new("Chest", None)      # animated (shake / levitate)
link(chest, root)
root.rotation_euler = (0, 0, math.radians(20))
YF = -D / 2                                       # front plane (body)

# ---- body: liner, planks, base, gold frame
box("LinerBottom", (0, 0, 0.06), (W - 0.08, D - 0.08, 0.02), WOOD_IN, chest, bev=0)
box("LinerF", (0, -D / 2 + 0.05, HB / 2 + 0.02), (W - 0.08, 0.012, HB - 0.04), WOOD_IN, chest, bev=0)
box("LinerB", (0, D / 2 - 0.05, HB / 2 + 0.02), (W - 0.08, 0.012, HB - 0.04), WOOD_IN, chest, bev=0)
box("LinerL", (-W / 2 + 0.05, 0, HB / 2 + 0.02), (0.012, D - 0.08, HB - 0.04), WOOD_IN, chest, bev=0)
box("LinerR", (W / 2 - 0.05, 0, HB / 2 + 0.02), (0.012, D - 0.08, HB - 0.04), WOOD_IN, chest, bev=0)
z_lo, z_hi = 0.06, HB - 0.035
ph = (z_hi - z_lo) / 3
for row in range(3):
    zc = z_lo + ph * (row + 0.5)
    for sgn in (-1, 1):
        box(f"PlankFB{row}{sgn}", (0, sgn * (D / 2 - T / 2), zc), (W - 0.02, T, ph - 0.008), WOODW[row % 3], chest, bev=0.008)
        box(f"PlankLR{row}{sgn}", (sgn * (W / 2 - T / 2), 0, zc), (T, D - 2 * T, ph - 0.008), WOODW[(row + 1) % 3], chest, bev=0.008)
box("Bottom", (0, 0, 0.035), (W - 0.01, D - 0.01, 0.05), WOODW[1], chest, bev=0.006)
box("Plinth", (0, 0, 0.03), (W + 0.05, D + 0.05, 0.06), GOLDC, chest, bev=0.012, seg=3)
for sx in (-1, 1):
    for sy in (-1, 1):
        box(f"Foot{sx}{sy}", (sx * (W / 2 - 0.02), sy * (D / 2 - 0.02), 0.012), (0.12, 0.12, 0.03), GOLDC, chest, bev=0.01, seg=3)
        # corner pillars (wrap both faces)
        box(f"PilA{sx}{sy}", (sx * (W / 2 - 0.04), sy * (D / 2 + 0.008), HB / 2), (0.10, 0.026, HB), GOLDC, chest, bev=0.008, seg=3)
        box(f"PilB{sx}{sy}", (sx * (W / 2 + 0.008), sy * (D / 2 - 0.04), HB / 2), (0.026, 0.10, HB), GOLDC, chest, bev=0.008, seg=3)
box("RimF", (0, -D / 2 - 0.006, HB - 0.02), (W + 0.02, 0.024, 0.04), GOLDC, chest, bev=0.007, seg=3)
box("RimB", (0, D / 2 + 0.006, HB - 0.02), (W + 0.02, 0.024, 0.04), GOLDC, chest, bev=0.007, seg=3)
box("RimL", (-W / 2 - 0.006, 0, HB - 0.02), (0.024, D + 0.02, 0.04), GOLDC, chest, bev=0.007, seg=3)
box("RimR", (W / 2 + 0.006, 0, HB - 0.02), (0.024, D + 0.02, 0.04), GOLDC, chest, bev=0.007, seg=3)
# lower front gems on gold diamond plates
for sx in (-1, 1):
    gx, gz = sx * 0.255, 0.125
    cylinder(f"LowPlate{sx}", (gx, YF - 0.014, gz), 0.085, 0.02, GOLDC, chest, rot=(math.radians(90), 0, 0), seg=32)
    torus(f"LowBezel{sx}", Vector((gx, YF - 0.03, gz)), 0.055, 0.012, GOLDC, chest,
          Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).transposed(), su=24, sv=8)
    gem(f"LowGem{sx}", (gx, YF - 0.032, gz), 0.052, 8, PINK, chest)
    for k, (dx, dz) in enumerate([(-0.07, -0.07), (0.07, -0.07)]):
        cylinder(f"LowScrew{sx}{k}", (gx + dx * 1.35, YF - 0.026, gz + dz * 0.0 - 0.085), 0.013, 0.01, GOLDC, chest,
                 rot=(math.radians(90), 0, 0), seg=16)
# skull jaw + teeth (on the body) and lower bones
yS = YF - 0.04
for sx in (-1, 1):
    bone(f"BoneLow{sx}", (sx * 0.08, HB - 0.13), (sx * 0.21, 0.085), 0.085, BONE, chest, YF - 0.022)
jaw = box("Jaw", (0, yS, HB - 0.14), (0.27, 0.055, 0.11), BONE, chest, bev=0.035, seg=1)
for i, x in enumerate((-0.069, -0.023, 0.023, 0.069)):
    box(f"Tooth{i}", (x, yS - 0.006, HB - 0.045), (0.042, 0.05, 0.088), BONE, chest, bev=0.009, seg=2)
# chains from the sides into the skull's mouth
for sx in (-1, 1):
    chain(f"Chain{sx}", (sx * (W / 2 + 0.01), 0.27), (sx * 0.25, 0.10), (sx * 0.10, HB - 0.06), YF - 0.07, chest)

# treasure (glowing gold pile) inside
sphere("Pile", (0, 0, HB - 0.08), 1.0, TREASURE, chest, scale=(W * 0.40, D * 0.36, 0.12), seg=24)
rnd = random.Random(7)
for i in range(26):
    x = rnd.uniform(-W * 0.33, W * 0.33)
    y = rnd.uniform(-D * 0.28, D * 0.28)
    zz = HB - 0.08 + 0.12 * math.sqrt(max(0.0, 1 - (x / (W * 0.40)) ** 2 - (y / (D * 0.36)) ** 2)) + 0.004
    cylinder(f"Coin{i}", (x, y, zz), 0.03, 0.007, TREASURE, chest, rot=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0))
glow_light = bpy.data.lights.new("InnerGlow", type='POINT')
glow_light.color = (1.0, 0.68, 0.25)
glow_light.energy = 0.0
glow_light.shadow_soft_size = 0.15
gl = bpy.data.objects.new("InnerGlow", glow_light)
gl.location = (0, 0, HB + 0.12)
link(gl, chest)

# ---- lid (hinged at the back top edge of the body)
pivot = bpy.data.objects.new("LidPivot", None)
link(pivot, chest)
pivot.location = (0, D / 2, HB)
cy = -D / 2        # lid centre (relative to pivot)
yfl = -D           # lid front plane (relative)
# box part: front / back / side planks + inner liner
for i in range(2):
    zc = 0.012 + (LH - 0.012) * (i + 0.5) / 2
    box(f"LidPlankF{i}", (0, yfl + T / 2, zc), (W - 0.02, T, (LH - 0.012) / 2 - 0.008), WOODW[i], pivot, bev=0.008)
    box(f"LidPlankB{i}", (0, -T / 2, zc), (W - 0.02, T, (LH - 0.012) / 2 - 0.008), WOODW[i + 1], pivot, bev=0.008)
    for sgn in (-1, 1):
        box(f"LidPlankS{i}{sgn}", (sgn * (W / 2 - T / 2), cy, zc), (T, D - 2 * T, (LH - 0.012) / 2 - 0.008), WOODW[(i + 2) % 3], pivot, bev=0.008)
box("LidLiner", (0, cy, LH * 0.5 + 0.01), (W - 0.08, D - 0.08, 0.012), WOOD_IN, pivot, bev=0)
# barrel top: planks + end caps
nsl = 4
gap = 0.02
for i in range(nsl):
    a0 = math.pi * i / nsl + gap / 2
    a1 = math.pi * (i + 1) / nsl - gap / 2
    shell(f"LidSlat{i}", -W / 2 + 0.015, W / 2 - 0.015, R - T, R, a0, a1, cy, LH, KZ, WOODW[i % 3], pivot)
for sx in (-1, 1):
    semi_disc(f"LidEnd{sx}", sx * (W / 2 - 0.016), 0.03, R - 0.004, cy, LH, KZ, WOODW[2], pivot)
    # gold bands over the barrel (continuing the pillars) and on the end edges
    shell(f"LidBand{sx}", sx * (W / 2 - 0.04) - 0.05, sx * (W / 2 - 0.04) + 0.05, R - 0.004, R + 0.016, -0.02, math.pi + 0.02, cy, LH, KZ, GOLDC, pivot)
    shell(f"LidEdge{sx}", sx * (W / 2 + 0.008) - 0.016, sx * (W / 2 + 0.008) + 0.016, R - 0.01, R + 0.014, -0.02, math.pi + 0.02, cy, LH, KZ, GOLDC, pivot)
    # vertical gold pillars on the lid's box part (front & back) + sides
    box(f"LidPilF{sx}", (sx * (W / 2 - 0.04), yfl - 0.008, LH / 2), (0.10, 0.026, LH), GOLDC, pivot, bev=0.008, seg=3)
    box(f"LidPilB{sx}", (sx * (W / 2 - 0.04), 0.008, LH / 2), (0.10, 0.026, LH), GOLDC, pivot, bev=0.008, seg=3)
    box(f"LidPilS{sx}", (sx * (W / 2 + 0.008), yfl + 0.04, LH / 2), (0.026, 0.10, LH), GOLDC, pivot, bev=0.008, seg=3)
    box(f"LidPilS2{sx}", (sx * (W / 2 + 0.008), -0.04, LH / 2), (0.026, 0.10, LH), GOLDC, pivot, bev=0.008, seg=3)
box("LidRimF", (0, yfl - 0.006, 0.02), (W + 0.02, 0.024, 0.04), GOLDC, pivot, bev=0.007, seg=3)
box("LidRimB", (0, 0.006, 0.02), (W + 0.02, 0.024, 0.04), GOLDC, pivot, bev=0.007, seg=3)
box("LidTopF", (0, yfl - 0.004, LH - 0.012), (W + 0.02, 0.03, 0.05), GOLDC, pivot, bev=0.008, seg=3)
# gold side plates with slot screws on the lid front
for sx in (-1, 1):
    pl = box(f"LidPlate{sx}", (sx * 0.265, yfl - 0.016, 0.075), (0.12, 0.016, 0.10), GOLDC, pivot, bev=0.02, seg=1)
    sc = cylinder(f"LidScrew{sx}", (sx * 0.265, yfl - 0.028, 0.075), 0.022, 0.012, GOLDC, pivot, rot=(math.radians(90), 0, 0), seg=20)
    sl = box(f"LidSlot{sx}", (0, 0, 0), (0.034, 0.006, 0.007), DARK, pivot, bev=0)
    sl.location = (sx * 0.265, yfl - 0.035, 0.075)
    sl.rotation_euler = (0, math.radians(35 * sx), 0)
    for k in (-1, 1):
        cylinder(f"LidRivet{sx}{k}", (sx * (W / 2 - 0.04), yfl - 0.024, LH / 2 + k * 0.06), 0.014, 0.012, GOLDC, pivot,
                 rot=(math.radians(90), 0, 0), seg=16)
# upper pink gems on the barrel front corners (tilted up)
ang_up = math.radians(40)
for sx in (-1, 1):
    a = math.radians(140)       # position on the barrel (from back)
    gy = cy + (R + 0.012) * math.cos(a)
    gz = LH + (R + 0.012) * math.sin(a) * KZ
    rot = (math.radians(90) - ang_up, 0, 0)
    basis = Euler(rot).to_matrix()
    torus(f"UpBezel{sx}", Vector((sx * 0.27, gy - 0.006, gz + 0.004)), 0.058, 0.013, GOLDC, pivot, basis, su=24, sv=8)
    gem(f"UpGem{sx}", (sx * 0.27, gy - 0.008, gz + 0.006), 0.055, 8, PINK, pivot, rot=rot)
# big cyan diamond on the top centre + gold V-plate under it
a = math.radians(128)
gy = cy + (R + 0.02) * math.cos(a)
gz = LH + (R + 0.02) * math.sin(a) * KZ
for k in (-1, 1):
    vp = box(f"VPlate{k}", (0, 0, 0), (0.12, 0.03, 0.04), GOLDC, pivot, bev=0.008, seg=2)
    vp.location = (k * 0.05, gy - 0.012, gz - 0.02)
    vp.rotation_euler = (math.radians(-30), math.radians(-22 * k), 0)
gem("TopGem", (0, gy - 0.01, gz + 0.025), 0.09, 10, CYAN, pivot, rot=(math.radians(35), 0, 0), crown=0.5, table=0.5, pav=0.6)
# skull cranium on the lid front (octagonal / chamfered) + eye gems + keyhole + upper bones
ySl = yfl - 0.04
for sx in (-1, 1):
    bone(f"BoneUp{sx}", (sx * 0.10, 0.10), (sx * 0.25, LH + 0.035), 0.085, BONE, pivot, yfl - 0.022)
cran = box("Cranium", (0, ySl, 0.135), (0.36, 0.06, 0.26), BONE, pivot, bev=0.065, seg=1)
for sx in (-1, 1):
    box(f"Socket{sx}", (sx * 0.078, ySl - 0.027, 0.165), (0.105, 0.012, 0.092), DARK, pivot, bev=0.026, seg=1)
    gem(f"Eye{sx}", (sx * 0.078, ySl - 0.034, 0.165), 0.055, 6, ORANGE, pivot, rot=(math.radians(90), math.radians(30), 0), crown=0.4, table=0.55)
cylinder("KeyholeTop", (0, ySl - 0.031, 0.078), 0.019, 0.01, DARK, pivot, rot=(math.radians(90), 0, 0), seg=16)
box("KeyholeSlot", (0, ySl - 0.031, 0.05), (0.017, 0.01, 0.05), DARK, pivot, bev=0)

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
