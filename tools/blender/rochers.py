# Décor rocheux de l'astéroïde, modélisé par script dans Blender puis exporté en glTF (models/rochers.glb).
# Lancer :  blender --background --python tools/blender/rochers.py -- <chemin absolu>/models/rochers.glb
#
# Roches à facettes irrégulières (déformation par bruit puis réduction « Decimate » : les triangles deviennent inégaux,
# comme le sol). Toutes les pièces sont à l'échelle unité, posées sur z = 0 (Blender, Z vers le haut ; Y vers le haut
# dans le jeu après l'export) ; le jeu les met à l'échelle et les oriente selon la verticale locale.
#   mesa_0..3     plateaux à strates : rayon ~1, de z = -0,7 (enfoncé) à ~0,9 (comme l'ancien mesa_mesh)
#   rocher_0..3   blocs : rayon ~1, dessous aplati à z = -0,25
#   aiguille_0..2 aiguilles : base de rayon ~1, hauteur ~4,5, légèrement courbées
#   arche_0..1    arches : portée ~5, hauteur ~3, pieds enfoncés
#   cristaux_0..1 amas de prismes de cristal (matériau « cristal »), hauteur ~1,5
# Matériaux : roche, cristal.
import bpy
import bmesh
import math
import random
import sys
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "rochers.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, col, emis=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = 0.9
    if emis > 0.0:
        b.inputs["Emission Color"].default_value = (*col, 1.0)
        b.inputs["Emission Strength"].default_value = emis
    return m


ROCHE = mat("roche", (0.4, 0.3, 0.22))
CRISTAL = mat("cristal", (0.3, 0.9, 0.85), 2.0)


def new_obj(name, bm, m):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    return o


def decimate(o, ratio):
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("reduc", "DECIMATE")
    md.decimate_type = "COLLAPSE"
    md.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=md.name)


def bump(p, seed, f1, a1, f2, a2):
    s = Vector((seed * 7.31, seed * 3.17, seed * 5.53))
    return noise.noise(p * f1 + s) * a1 + noise.noise(p * f2 + s * 1.7) * a2


# ------------------------------------------------------------ blocs
def rocher(name, seed):
    random.seed(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    sq = Vector((random.uniform(1.0, 1.4), random.uniform(0.8, 1.1), random.uniform(0.55, 0.85)))
    for v in bm.verts:
        d = v.co.normalized()
        r = 1.0 + bump(d, seed, 1.6, 0.32, 4.2, 0.1)
        p = Vector((d.x * sq.x, d.y * sq.y, d.z * sq.z)) * r
        p.z = max(p.z, -0.25)
        v.co = p
    o = new_obj(name, bm, ROCHE)
    decimate(o, 0.45)
    return o


# ------------------------------------------------------------ plateaux à strates
def mesa(name, seed):
    random.seed(seed)
    K = 14
    rings = [(-0.7, 1.1), (-0.15, 1.02), (0.3, 0.97), (0.42, 0.9), (0.6, 0.88), (0.7, 0.8), (0.82, 0.76), (0.88, 0.6)]
    rad = [random.uniform(0.82, 1.0) for _ in range(K)]
    bm = bmesh.new()
    R = []
    for zi, (z, rr) in enumerate(rings):
        ring = []
        for i in range(K):
            a = 2 * math.pi * i / K
            base = Vector((math.cos(a), math.sin(a) * 0.85, 0.0))
            n = bump(base + Vector((0, 0, z)), seed, 1.8, 0.12, 5.0, 0.05)
            r = rad[i] * rr * (1.0 + n)
            zz = z + (random.uniform(-0.03, 0.03) if z > 0.5 else 0.0)
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r * 0.85, zz)))
        R.append(ring)
    for zi in range(len(R) - 1):
        for i in range(K):
            j = (i + 1) % K
            bm.faces.new((R[zi][i], R[zi][j], R[zi + 1][j], R[zi + 1][i]))
    top = bm.verts.new((random.uniform(-0.1, 0.1), random.uniform(-0.1, 0.1), 0.9))
    for i in range(K):
        j = (i + 1) % K
        bm.faces.new((R[-1][i], R[-1][j], top))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    for v in bm.verts:
        if v.co.z > -0.6:
            d = Vector((v.co.x, v.co.y, 0.0))
            if d.length > 0.05:
                k = 1.0 + bump(v.co, seed + 11, 3.5, 0.06, 9.0, 0.025)
                v.co.x *= k
                v.co.y *= k
    o = new_obj(name, bm, ROCHE)
    decimate(o, 0.5)
    return o


# ------------------------------------------------------------ aiguilles
def aiguille(name, seed):
    random.seed(seed)
    K = 9
    N = 12
    H = random.uniform(4.0, 5.0)
    bend = Vector((random.uniform(-0.6, 0.6), random.uniform(-0.6, 0.6), 0.0))
    bm = bmesh.new()
    R = []
    for zi in range(N + 1):
        t = zi / N
        z = -0.5 + t * (H + 0.5)
        rr = (1.0 - t * 0.85) * (1.0 + 0.12 * math.sin(t * 9.0 + seed))
        c = bend * (t * t)
        ring = []
        for i in range(K):
            a = 2 * math.pi * i / K
            d = Vector((math.cos(a), math.sin(a), 0.0))
            r = rr * (1.0 + bump(d + Vector((0, 0, z * 0.6)), seed, 1.5, 0.18, 4.0, 0.07))
            ring.append(bm.verts.new((c.x + d.x * r, c.y + d.y * r, z)))
        R.append(ring)
    for zi in range(N):
        for i in range(K):
            j = (i + 1) % K
            bm.faces.new((R[zi][i], R[zi][j], R[zi + 1][j], R[zi + 1][i]))
    tip = bm.verts.new((bend.x * 1.1, bend.y * 1.1, H + 0.35))
    for i in range(K):
        bm.faces.new((R[-1][i], R[-1][(i + 1) % K], tip))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    o = new_obj(name, bm, ROCHE)
    decimate(o, 0.6)
    return o


# ------------------------------------------------------------ arches
def arche(name, seed):
    random.seed(seed)
    K = 9
    N = 22
    span = random.uniform(2.2, 2.6)
    hgt = random.uniform(2.6, 3.2)
    bm = bmesh.new()
    R = []
    for si in range(N + 1):
        t = si / N
        a = math.pi * (-0.12 + 1.24 * t)
        cx = -math.cos(a) * span
        cz = math.sin(a) * hgt
        # direction du chemin, puis section perpendiculaire
        tx = math.sin(a) * span
        tz = math.cos(a) * hgt
        tl = math.hypot(tx, tz)
        tang = Vector((tx / tl, 0.0, tz / tl))
        nrm = Vector((-tang.z, 0.0, tang.x))
        side = Vector((0.0, 1.0, 0.0))
        thick = 0.55 + 0.35 * abs(math.cos(a)) + 0.08 * math.sin(t * 11.0 + seed)
        ring = []
        for i in range(K):
            b = 2 * math.pi * i / K
            d = nrm * math.cos(b) + side * math.sin(b) * 1.25
            r = thick * (1.0 + bump(d + Vector((cx, 0, cz)) * 0.5, seed, 1.4, 0.18, 4.0, 0.06))
            ring.append(bm.verts.new(Vector((cx, 0.0, cz)) + d * r))
        R.append(ring)
    for si in range(N):
        for i in range(K):
            j = (i + 1) % K
            bm.faces.new((R[si][i], R[si][j], R[si + 1][j], R[si + 1][i]))
    for ring in (R[0], R[-1]):
        bm.faces.new(ring)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for v in bm.verts:
        v.co.z -= 0.35
    o = new_obj(name, bm, ROCHE)
    decimate(o, 0.55)
    return o


# ------------------------------------------------------------ cristaux
def cristaux(name, seed):
    random.seed(seed)
    bm = bmesh.new()
    for k in range(random.randint(6, 9)):
        h = random.uniform(0.6, 1.6)
        r = random.uniform(0.08, 0.17)
        tilt = Vector((random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), 1.0)).normalized()
        base = Vector((random.uniform(-0.35, 0.35), random.uniform(-0.35, 0.35), -0.15))
        ax = tilt.cross(Vector((1, 0, 0))).normalized()
        ay = tilt.cross(ax).normalized()
        low = []
        high = []
        for i in range(6):
            a = 2 * math.pi * i / 6
            d = ax * math.cos(a) * r + ay * math.sin(a) * r
            low.append(bm.verts.new(base + d))
            high.append(bm.verts.new(base + d + tilt * h))
        tip = bm.verts.new(base + tilt * (h + r * 2.2))
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((low[i], low[j], high[j], high[i]))
            bm.faces.new((high[i], high[j], tip))
        bm.faces.new(list(reversed(low)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return new_obj(name, bm, CRISTAL)


objs = []
for k in range(4):
    objs.append(mesa("mesa_%d" % k, 10 + k))
    objs.append(rocher("rocher_%d" % k, 30 + k))
for k in range(3):
    objs.append(aiguille("aiguille_%d" % k, 50 + k))
for k in range(2):
    objs.append(arche("arche_%d" % k, 70 + k))
    objs.append(cristaux("cristaux_%d" % k, 90 + k))
for o in objs:
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.shade_flat()
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True, export_yup=True)
print("EXPORT", OUT, {o.name: len(o.data.polygons) for o in objs})
