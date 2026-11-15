# Char super-lourd de K-240, modélisé par script dans Blender puis exporté en glTF (models/char_lourd.glb).
# Lancer :  blender --background --python tools/blender/char_lourd.py -- models/char_lourd.glb
#
# Repère du jeu (Godot) : X vers l'avant, Y vers le haut, Z sur le côté ; 1 unité = 1 m.
# Blender est en Z vers le haut : un point (x, y, z) du jeu devient (x, -z, y) dans Blender
# (l'export glTF « Y vers le haut » refait la conversion inverse).
# Trois objets, chacun avec son origine au pivot utilisé par battle.gd :
#   coque    : origine au sol, au centre du char
#   tourelle : origine au pivot de la tourelle (en (-0,72 ; 3,264) dans la coque)
#   canon    : origine au tourillon du canon (en (2,4 ; 0,528) dans la tourelle)
# Matériaux (remplacés dans le jeu selon le camp) : camo, sombre, metal, lueur.
import bpy
import math
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "char_lourd.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)

MATS = {}


def mat(name, col, emis=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = 0.7
    if emis > 0.0:
        b.inputs["Emission Color"].default_value = (*col, 1.0)
        b.inputs["Emission Strength"].default_value = emis
    MATS[name] = m
    return m


CAMO = mat("camo", (0.05, 0.07, 0.02))
SOMBRE = mat("sombre", (0.012, 0.013, 0.01))
METAL = mat("metal", (0.04, 0.045, 0.04))
LUEUR = mat("lueur", (0.3, 0.9, 1.0), 4.0)

PARTS = {"coque": [], "tourelle": [], "canon": []}
CUR = ["coque"]


def B(x, y, z):
    return (x, -z, y)


def finish(o, m, bevel):
    o.data.materials.append(m)
    if bevel > 0.0:
        md = o.modifiers.new("biseau", "BEVEL")
        md.width = bevel
        md.segments = 2
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(50)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=md.name)
    PARTS[CUR[0]].append(o)
    return o


def box(c, s, m, bevel=0.05, rz=0.0):
    """boîte de centre c et de taille s (repère du jeu), tournée de rz autour de l'axe Z du jeu (avant vers le haut)"""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=B(*c))
    o = bpy.context.active_object
    o.scale = (s[0], s[2], s[1])
    o.rotation_euler = (0.0, -rz, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(o, m, min(bevel, min(s) * 0.45))


def cyl(c, r, d, axis, m, bevel=0.02, verts=24):
    """cylindre de centre c, rayon r, longueur d, le long de l'axe 'x', 'y' ou 'z' du jeu"""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d, location=B(*c))
    o = bpy.context.active_object
    if axis == "x":
        o.rotation_euler = (0.0, math.pi / 2, 0.0)
    elif axis == "z":
        o.rotation_euler = (math.pi / 2, 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return finish(o, m, min(bevel, r * 0.4, d * 0.4))


def sph(c, r, m, scl=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=r, location=B(*c))
    o = bpy.context.active_object
    o.scale = (scl[0], scl[2], scl[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, m, 0.0)


def gatling(x, y, z, length, r, n=6):
    """canon rotatif : manchon, couronne de tubes, frette de bouche"""
    cyl((x, y, z), r * 2.6, 0.3, "x", METAL)
    cyl((x + 0.2, y, z), r * 1.2, 0.3, "x", SOMBRE)
    for k in range(n):
        a = 2 * math.pi * k / n
        cyl((x + 0.15 + length * 0.5, y + math.cos(a) * r, z + math.sin(a) * r), r * 0.42, length, "x", SOMBRE, verts=10)
    cyl((x + 0.15 + length * 0.82, y, z), r * 1.55, 0.08, "x", METAL)
    cyl((x + 0.15 + length * 0.97, y, z), r * 1.55, 0.06, "x", METAL)


def rivets(x0, x1, y, z, n, m=METAL):
    for i in range(n):
        x = x0 + (x1 - x0) * i / max(1, n - 1)
        cyl((x, y, z), 0.045, 0.06, "z", m, bevel=0.015, verts=8)


# ============================================================ coque
CUR[0] = "coque"
for sd in (-1.0, 1.0):
    zc = sd * 2.76
    zo = zc + sd * 0.8   # face extérieure
    # chenille : bande à extrémités arrondies, maillons sur le dessus et le dessous
    box((0.0, 0.58, zc), (10.8, 1.1, 1.5), SOMBRE, 0.08)
    for ex in (-5.4, 5.4):
        cyl((ex, 0.58, zc), 0.56, 1.5, "z", SOMBRE, 0.05)
    for i in range(34):
        x = -5.3 + i * 0.32
        box((x, 1.15, zc), (0.14, 0.07, 1.54), METAL, 0.02)
        box((x, 0.03, zc), (0.14, 0.07, 1.54), METAL, 0.02)
    # galets et barbotins
    for i in range(8):
        x = -5.04 + i * 1.44
        cyl((x, 0.58, zc + sd * 0.72), 0.46, 0.16, "z", METAL, 0.03)
        cyl((x, 0.58, zc + sd * 0.82), 0.2, 0.08, "z", SOMBRE, 0.02)
    for ex in (-5.4, 5.4):
        cyl((ex, 0.6, zc + sd * 0.74), 0.5, 0.14, "z", METAL, 0.03)
        for k in range(8):
            a = 2 * math.pi * k / 8
            box((ex + math.cos(a) * 0.5, 0.6 + math.sin(a) * 0.5, zc + sd * 0.74), (0.12, 0.12, 0.16), SOMBRE, 0.02)
    # caisson de chenille et pans inclinés avant et arrière
    box((-0.24, 1.73, zc), (10.08, 1.49, 1.6), CAMO, 0.1)
    box((4.92, 1.63, zc), (1.92, 1.2, 1.6), CAMO, 0.1, rz=-0.75)
    box((-5.4, 1.58, zc), (1.2, 1.08, 1.6), CAMO, 0.1, rz=0.6)
    # jupes de blindage boulonnées
    for i in range(5):
        x = -3.84 + i * 1.8
        box((x, 1.78, zo + sd * 0.02), (1.68, 1.2, 0.1), CAMO, 0.03)
        rivets(x - 0.7, x + 0.7, 2.28, zo + sd * 0.08, 6)
        rivets(x - 0.7, x + 0.7, 1.28, zo + sd * 0.08, 6)
    # tourelle latérale (sponson) à canon rotatif
    box((1.08, 2.28, zc + sd * 1.1), (1.68, 1.0, 0.82), CAMO, 0.08)
    sph((1.87, 2.28, zc + sd * 1.15), 0.48, CAMO)
    gatling(2.05, 2.28, zc + sd * 1.15, 1.4, 0.13)
    box((2.4, 2.0, zc + sd * 0.45), (0.1, 0.18, 0.3), LUEUR, 0.0)

# caisse centrale et glacis
box((-0.48, 2.52, 0.0), (9.12, 1.34, 4.08), CAMO, 0.12)
box((4.2, 2.4, 0.0), (1.92, 0.82, 3.94), CAMO, 0.1, rz=-0.5)
rivets(-4.6, 3.4, 3.2, 2.06, 18)
rivets(-4.6, 3.4, 3.2, -2.06, 18)
# plaques du pont, trappe, outils
box((-1.2, 3.22, -0.96), (2.88, 0.1, 1.68), CAMO, 0.03)
box((1.32, 3.22, 0.84), (2.4, 0.1, 1.44), CAMO, 0.03)
cyl((2.16, 3.3, -1.08), 0.38, 0.14, "y", CAMO, 0.04)
cyl((2.16, 3.38, -1.08), 0.2, 0.06, "y", METAL)
for i in range(3):
    box((4.15, 2.62 - i * 0.03, -1.0 + i * 0.7), (0.5, 0.06, 0.55), SOMBRE, 0.02, rz=-0.5)
# pont moteur à grilles, échappements, jerricans
box((-3.8, 3.2, 0.0), (2.4, 0.08, 3.1), SOMBRE, 0.02)
for i in range(9):
    box((-4.8 + i * 0.25, 3.27, 0.0), (0.1, 0.1, 2.9), METAL, 0.02)
for z in (-1.44, 1.44):
    cyl((-4.8, 3.65, z), 0.22, 1.1, "y", METAL, 0.03)
    cyl((-4.8, 4.2, z), 0.26, 0.1, "y", SOMBRE, 0.02)
    box((-5.25, 2.5, z * 0.9), (0.4, 0.6, 0.35), CAMO, 0.04)
# canon de caisse à bobines, phares
box((4.3, 2.4, 1.08), (0.6, 0.6, 0.7), CAMO, 0.08)
cyl((5.4, 2.4, 1.08), 0.16, 2.2, "x", METAL)
for i in range(3):
    cyl((4.75 + i * 0.42, 2.4, 1.08), 0.23, 0.12, "x", LUEUR, 0.0)
cyl((6.5, 2.4, 1.08), 0.22, 0.2, "x", SOMBRE)
for z in (-1.32, 1.32):
    box((5.0, 2.06, z), (0.3, 0.3, 0.44), SOMBRE, 0.04)
    box((5.16, 2.06, z), (0.04, 0.2, 0.34), LUEUR, 0.0)
cyl((-2.4, 3.95, 1.44), 0.025, 1.5, "y", METAL, 0.0, verts=8)

# ============================================================ tourelle
CUR[0] = "tourelle"
box((0.0, 0.48, 0.0), (4.08, 0.96, 3.36), CAMO, 0.14)
box((-0.12, 1.13, 0.0), (3.36, 0.38, 2.76), CAMO, 0.1)
rivets(-1.6, 1.6, 0.9, 1.69, 12)
rivets(-1.6, 1.6, 0.9, -1.69, 12)
for sd in (-1.0, 1.0):
    box((1.2, 0.48, sd * 1.73), (1.49, 0.77, 0.14), CAMO, 0.04)
    for i in range(3):
        cyl((1.0 + i * 0.26, 1.03, sd * 1.44), 0.085, 0.32, "x", SOMBRE, 0.02, verts=12)
    box((-2.28, 0.62, sd * 1.5), (0.8, 0.5, 0.25), CAMO, 0.04)
box((2.16, 0.53, 0.0), (0.53, 0.86, 1.49), CAMO, 0.12)
box((-2.28, 0.6, 0.0), (0.96, 0.72, 2.88), CAMO, 0.08)
for i in range(4):
    box((-2.28, 1.0, -1.05 + i * 0.7), (0.7, 0.08, 0.5), SOMBRE, 0.02)
cyl((-0.72, 1.49, 0.77), 0.41, 0.34, "y", CAMO, 0.06)
cyl((-0.72, 1.7, 0.77), 0.33, 0.08, "y", METAL, 0.02)
box((-0.33, 1.52, 0.77), (0.1, 0.1, 0.42), LUEUR, 0.0)
box((0.36, 1.54, -0.72), (0.86, 0.38, 0.62), CAMO, 0.06)
gatling(0.8, 1.58, -0.72, 1.1, 0.09)
cyl((-1.8, 2.3, -1.2), 0.025, 1.9, "y", METAL, 0.0, verts=8)

# ============================================================ canon
CUR[0] = "canon"
cyl((0.24, 0.0, 0.0), 0.36, 0.72, "x", METAL, 0.05)
cyl((2.76, 0.0, 0.0), 0.26, 4.8, "x", METAL, 0.03)
for i in range(4):
    cyl((1.32 + i * 0.86, 0.0, 0.0), 0.33, 0.16, "x", LUEUR, 0.0)
    cyl((1.12 + i * 0.86, 0.0, 0.0), 0.31, 0.06, "x", SOMBRE, 0.01)
cyl((5.28, 0.0, 0.0), 0.38, 0.55, "x", SOMBRE, 0.05)
for sd in (-1.0, 1.0):
    box((5.28, 0.0, sd * 0.36), (0.36, 0.14, 0.1), METAL, 0.02)


# ============================================================ assemblage et export
def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    except Exception:
        bpy.ops.object.shade_smooth()
    return o


for name, objs in PARTS.items():
    join(name, objs)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True, export_yup=True)
print("EXPORT", OUT, {n: len(o) for n, o in PARTS.items()})
