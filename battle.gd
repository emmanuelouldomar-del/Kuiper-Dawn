extends Node3D
## Bataille de formations à l'échelle réelle (mètres).
## Une unité = une formation : 30 fusiliers, 12 lance-flammes, 6 robots de soutien ou 2 chars (voir KIND).
## Soldat 1,85 m · robot 2,4 m (+30 %) · char ~9 m.
## Les soldats sont dessinés par instanciation (MultiMesh) avec 4 poses de marche + 1 pose arrêtée.

var w
var PERP: Vector3
var F_cover_tmp := PackedByteArray()
var P0: Vector3
var P1: Vector3
var RL: float
var MIDN: Vector3
var MIDP: Vector3
const LANES := [-48.0, 0.0, 48.0]
var KIND := {
	"rifle": {"n": 30, "cols": 10, "spx": 4.2, "spz": 3.6, "hp": 10.0, "speed": 2.2, "rng": 110.0, "dps": 0.12, "fire": 0.5, "h": 1.35},
	"flame": {"n": 12, "cols": 6, "spx": 4.0, "spz": 3.8, "hp": 14.0, "speed": 2.3, "rng": 28.0, "dps": 1.1, "fire": 0.0, "h": 1.2},
	"robot": {"n": 6, "cols": 3, "spx": 6.0, "spz": 6.0, "hp": 90.0, "speed": 1.8, "rng": 120.0, "dps": 0.9, "fire": 1.4, "h": 1.9},
	"tank": {"n": 2, "cols": 2, "spx": 16.0, "spz": 14.0, "hp": 500.0, "speed": 3.0, "rng": 220.0, "dps": 13.0, "fire": 0.31, "h": 3.4},
}
var MULT := {
	"rifle": {"rifle": 1.0, "flame": 1.0, "robot": 0.35, "tank": 0.03},
	"flame": {"rifle": 1.0, "flame": 1.0, "robot": 0.6, "tank": 0.3},
	"robot": {"rifle": 1.0, "flame": 1.0, "robot": 0.5, "tank": 0.15},
	"tank": {"rifle": 0.8, "flame": 0.8, "robot": 1.0, "tank": 1.0},
}
var FORM: Array = []
var TR: Array = []
var SHELLS: Array = []
var FX: Array = []
var WR: Array = []
var FT: Array = []
var DS: Array = []
var TUR: Array = []
var wave := 1
var ds_down := 0          # vaisseaux de débarquement abattus
var kronos_dead := false  # Kronos conquis : plus de renforts pirates
var wt := 0.0
var time := 0.0
var kills := {"b": 0, "r": 0}
var PAL := {}
var BODY: Material
var EMIS := {}
var CHAR: StandardMaterial3D
var glow_tex: Texture2D
var MM := {}
var DEAD := {}
var dead_t := 0.0
var TANKM := {}
var FIGHTM := {}


# ================================================================ cuisson des modèles (builder)
var BV := PackedVector3Array()
var BN := PackedVector3Array()
var BC := PackedColorArray()
var BI := PackedInt32Array()
var EV := PackedVector3Array()
var EN := PackedVector3Array()
var EC := PackedColorArray()
var EI := PackedInt32Array()
var XS: Array = [Transform3D.IDENTITY]
var PRIM := {}


func prim_arrays(kind: String) -> Array:
	if not PRIM.has(kind):
		var m: PrimitiveMesh
		if kind == "box":
			m = BoxMesh.new()
		elif kind == "cyl":
			var c := CylinderMesh.new()
			c.top_radius = 1.0
			c.bottom_radius = 1.0
			c.height = 1.0
			c.radial_segments = 12
			c.rings = 1
			m = c
		else:
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = 12
			s.rings = 7
			m = s
		PRIM[kind] = m.get_mesh_arrays()
	return PRIM[kind]


func b_begin(base := Transform3D.IDENTITY) -> void:
	BV = PackedVector3Array()
	BN = PackedVector3Array()
	BC = PackedColorArray()
	BI = PackedInt32Array()
	EV = PackedVector3Array()
	EN = PackedVector3Array()
	EC = PackedColorArray()
	EI = PackedInt32Array()
	XS = [base]


func bpush(t: Transform3D) -> void:
	XS.append(XS[-1] * t)


func bpop() -> void:
	XS.pop_back()


func prim(kind: String, t: Transform3D, col: Color, emis := false) -> void:
	var arr := prim_arrays(kind)
	var T: Transform3D = XS[-1] * t
	var nb := T.basis.inverse().transposed()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if emis:
		var base := EV.size()
		for k in verts.size():
			EV.append(T * verts[k])
			EN.append((nb * norms[k]).normalized())
			EC.append(col)
		for k in idx:
			EI.append(base + k)
	else:
		var base := BV.size()
		for k in verts.size():
			BV.append(T * verts[k])
			BN.append((nb * norms[k]).normalized())
			BC.append(col)
		for k in idx:
			BI.append(base + k)


func bx(x: float, y: float, z: float, sx: float, sy: float, sz: float, col: Color, emis := false) -> void:
	prim("box", Transform3D(Basis.from_scale(Vector3(sx, sy, sz)), Vector3(x, y, z)), col, emis)


func cy(x: float, y: float, z: float, r: float, h: float, col: Color, axis := "y", emis := false) -> void:
	var b := Basis.IDENTITY
	if axis == "x":
		b = Basis(Vector3(0, 0, 1), PI / 2)
	elif axis == "z":
		b = Basis(Vector3(1, 0, 0), PI / 2)
	prim("cyl", Transform3D(b * Basis.from_scale(Vector3(r, h, r)), Vector3(x, y, z)), col, emis)


func sp(x: float, y: float, z: float, r: float, col: Color, scl := Vector3.ONE, emis := false) -> void:
	prim("sph", Transform3D(Basis.from_scale(scl * r), Vector3(x, y, z)), col, emis)


func b_end(emis_mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = BV
	a[Mesh.ARRAY_NORMAL] = BN
	a[Mesh.ARRAY_COLOR] = BC
	a[Mesh.ARRAY_INDEX] = BI
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.surface_set_material(0, BODY)
	if EV.size() > 0:
		var e := []
		e.resize(Mesh.ARRAY_MAX)
		e[Mesh.ARRAY_VERTEX] = EV
		e[Mesh.ARRAY_NORMAL] = EN
		e[Mesh.ARRAY_COLOR] = EC
		e[Mesh.ARRAY_INDEX] = EI
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e)
		m.surface_set_material(1, emis_mat)
	return m


# ================================================================ modèles
func trooper(C: Dictionary, flame: bool, sw: float) -> void:
	# fantassin lourd : armure camouflée, grosses épaulières, casque à rebord, masque à gaz, sac à dos
	for sd in [-1.0, 1.0]:
		bpush(Transform3D(Basis(Vector3(0, 0, 1), sw * sd), Vector3(0, 0.95, 0.13 * sd)))
		bx(0, -0.2, 0, 0.19, 0.42, 0.19, C.c2 if sd > 0 else C.c1)
		bx(0.1, -0.46, 0, 0.1, 0.15, 0.17, C.c3)
		bx(0.01, -0.67, 0, 0.17, 0.36, 0.17, C.c1)
		bx(0.05, -0.88, 0, 0.29, 0.14, 0.2, C.dark)
		bpop()
	bx(0, 1.0, 0, 0.32, 0.18, 0.38, C.suit)
	bx(0, 1.08, 0, 0.34, 0.07, 0.42, C.gear)
	for z in [-0.14, 0.0, 0.14]:
		bx(0.19, 1.05, z, 0.07, 0.12, 0.1, C.gear)
	bx(0, 1.32, 0, 0.32, 0.44, 0.44, C.suit)
	bx(0.06, 1.34, 0, 0.27, 0.42, 0.46, C.c1)
	bx(0.11, 1.45, 0.09, 0.22, 0.15, 0.22, C.c2)
	bx(0.11, 1.24, -0.08, 0.22, 0.12, 0.2, C.c3)
	for sd in [-1.0, 1.0]:
		sp(0.0, 1.5, 0.29 * sd, 0.165, C.c3 if sd > 0 else C.c2, Vector3(1.15, 0.8, 1.0))
		bx(0.0, 1.43, 0.33 * sd, 0.3, 0.08, 0.12, C.c1)
		bx(0.03, 1.26, 0.3 * sd, 0.12, 0.3, 0.12, C.suit)
	if flame:
		for z in [-0.1, 0.1]:
			cy(-0.28, 1.3, z, 0.1, 0.52, C.fuel)
		bx(-0.28, 1.58, 0, 0.08, 0.05, 0.3, C.metal)
	else:
		bx(-0.25, 1.32, 0, 0.22, 0.5, 0.4, C.gear)
		bx(-0.37, 1.24, 0, 0.05, 0.22, 0.3, C.c2)
		cy(-0.26, 1.62, 0, 0.08, 0.4, C.c2, "z")
		cy(-0.3, 1.85, 0.12, 0.008, 0.5, C.metal)
	# tête : casque à rebord, masque à gaz à deux lentilles, cartouche filtrante et tuyau
	bx(0, 1.6, 0, 0.12, 0.08, 0.12, C.suit)
	sp(0, 1.75, 0, 0.16, C.c1, Vector3(1.1, 0.82, 1.05))
	bx(-0.02, 1.69, 0, 0.38, 0.035, 0.36, C.c1)
	bx(0.11, 1.66, 0, 0.09, 0.13, 0.19, C.dark)
	for sd in [-1.0, 1.0]:
		sp(0.16, 1.69, 0.055 * sd, 0.036, C.visor, Vector3.ONE, true)
	cy(0.2, 1.6, 0, 0.05, 0.09, C.metal, "x")
	cy(0.13, 1.48, 0.07, 0.025, 0.22, C.metal)
	# bras et arme
	bx(0.2, 1.17, 0.2, 0.3, 0.1, 0.1, C.c1)
	bx(0.2, 1.19, -0.16, 0.3, 0.1, 0.1, C.c1)
	if flame:
		cy(0.48, 1.16, 0.03, 0.05, 0.62, C.metal, "x")
		cy(0.81, 1.16, 0.03, 0.035, 0.08, C.dark, "x")
		bx(0.32, 1.08, 0.03, 0.08, 0.12, 0.07, C.metal)
	else:
		bx(0.42, 1.2, 0.03, 0.82, 0.12, 0.08, C.dark)
		bx(0.3, 1.09, 0.03, 0.08, 0.16, 0.06, C.dark)
		cy(0.26, 1.3, 0.03, 0.05, 0.18, C.metal, "x")
		bx(0.55, 1.27, 0.03, 0.14, 0.03, 0.09, C.visor, true)
		cy(0.92, 1.21, 0.03, 0.028, 0.26, C.metal, "x")


func prone(C: Dictionary, flame: bool, cr: float) -> void:
	# soldat allongé sur le ventre, arme vers l'avant (+X) ; cr = mouvement de reptation
	bx(0.0, 0.2, 0, 0.75, 0.28, 0.42, C.suit)
	bx(0.02, 0.33, 0, 0.62, 0.1, 0.44, C.armor)
	for sd in [-1.0, 1.0]:
		var c: float = cr * sd
		bpush(Transform3D(Basis(Vector3.UP, c * 0.5), Vector3(-0.38, 0.13, 0.12 * sd)))
		bx(-0.45, 0, 0, 0.9, 0.17, 0.17, C.suit)
		bx(-0.3, 0.05, 0, 0.3, 0.19, 0.19, C.armor)
		bx(-0.92, 0.02, 0, 0.14, 0.2, 0.2, C.dark)
		bpop()
		bpush(Transform3D(Basis(Vector3.UP, -c * 0.6), Vector3(0.3, 0.16, 0.2 * sd)))
		bx(0.2, 0, 0, 0.4, 0.1, 0.1, C.armor)
		bpop()
		sp(0.28, 0.34, 0.24 * sd, 0.11, C.plate, Vector3(1.0, 0.7, 1.0))
	if flame:
		for z in [-0.1, 0.1]:
			cy(-0.1, 0.45, z, 0.09, 0.45, C.fuel, "x")
		cy(0.75, 0.2, 0.06, 0.05, 0.6, C.metal, "x")
	else:
		bx(-0.1, 0.45, 0, 0.4, 0.17, 0.32, C.gear)
		bx(0.75, 0.22, 0.06, 0.85, 0.08, 0.06, C.dark)
		bx(0.6, 0.29, 0.06, 0.16, 0.05, 0.05, C.metal)
		cy(1.2, 0.22, 0.06, 0.02, 0.18, C.metal, "x")
	sp(0.5, 0.32, 0, 0.16, C.c1, Vector3(1.05, 0.85, 1.05))
	bx(0.47, 0.27, 0, 0.36, 0.035, 0.36, C.c1)
	bx(0.62, 0.25, 0, 0.09, 0.12, 0.19, C.dark)
	for sd in [-1.0, 1.0]:
		sp(0.67, 0.27, 0.055 * sd, 0.036, C.visor, Vector3.ONE, true)
	cy(0.7, 0.18, 0, 0.05, 0.09, C.metal, "x")


func robot(C: Dictionary, sw: float) -> void:
	for sd in [-1.0, 1.0]:
		bpush(Transform3D(Basis(Vector3(0, 0, 1), sw * sd * 0.7), Vector3(0, 1.5, 0.5 * sd)))
		bx(0, -0.4, 0, 0.45, 0.82, 0.45, C.suit)
		sp(0.06, -0.82, 0, 0.25, C.metal)
		bx(0.03, -1.13, 0, 0.47, 0.68, 0.45, C.plate)
		bx(0.11, -1.43, 0, 0.77, 0.16, 0.52, C.metal)
		bpop()
	bx(0, 1.55, 0, 0.8, 0.35, 1.1, C.metal)
	bx(0, 2.35, 0, 1.2, 1.25, 1.5, C.armor)
	bx(0.42, 2.4, 0, 0.45, 0.9, 0.95, C.plate)
	bx(0.62, 2.45, 0, 0.06, 0.45, 0.5, C.metal)
	bx(0.64, 2.05, 0, 0.02, 0.06, 1.2, C.acc)
	for z in [-1.0, 1.0]:
		bx(0.05, 2.95, z * 0.95, 1.0, 0.75, 0.55, C.plate)
		bx(0.05, 3.34, z * 0.95, 0.8, 0.06, 0.4, C.metal)
	bx(-0.6, 2.4, 0, 0.35, 1.0, 1.1, C.gear)
	bx(0.35, 3.25, 0, 0.5, 0.45, 0.45, C.armor)
	bx(0.6, 3.22, 0, 0.06, 0.16, 0.34, C.visor, true)
	sp(0.5, 3.28, -0.2, 0.12, C.metal)
	# bras canon rotatif
	bx(0.1, 2.3, 1.05, 0.3, 0.9, 0.3, C.metal)
	bx(0.2, 1.7, 1.05, 0.45, 0.55, 0.45, C.armor)
	for yz in [[1.45, 0.97], [1.45, 1.13], [1.33, 1.05]]:
		cy(0.65, yz[0], yz[1], 0.06, 0.8, C.dark, "x")
	cy(0.4, 1.41, 1.05, 0.16, 0.25, C.metal, "x")
	# bras pince
	bx(0, 2.25, -1.05, 0.28, 1.0, 0.28, C.metal)
	bx(0.05, 1.6, -1.05, 0.4, 0.5, 0.4, C.armor)
	for z in [-0.12, 0.0, 0.12]:
		bx(0.18, 1.27, -1.05 + z, 0.08, 0.25, 0.06, C.dark)


# char super-lourd (repère du modèle ×2,4 = mètres, environ 12 m × 7,4 m) : caissons de chenilles à avant incliné,
# tourelles latérales à canons rotatifs, caisse à pont moteur, canon de caisse ; tourelle massive et canon à bobines
func gatling(x: float, y: float, z: float, l: float, r: float, C: Dictionary) -> void:
	cy(x - 0.05, y, z, r * 2.2, 0.1, C.metal, "x")
	for k in 3:
		var a := TAU * k / 3.0
		cy(x + l * 0.5, y + cos(a) * r, z + sin(a) * r, r * 0.55, l, C.dark, "x")


func tank_hull(C: Dictionary) -> void:
	var cam := [C.c1, C.c2, C.c3]
	for z in [-1.0, 1.0]:
		var zc: float = z * 1.15
		# chenille et galets
		bx(0, 0.22, zc, 4.9, 0.4, 0.64, C.dark)
		for i in 8:
			cy(-2.1 + i * 0.6, 0.24, zc + z * 0.31, 0.19, 0.06, C.metal, "z")
		# caisson de chenille, avant et arrière inclinés
		bx(-0.1, 0.72, zc, 4.2, 0.62, 0.66, C.c1)
		bpush(Transform3D(Basis(Vector3(0, 0, 1), -0.75), Vector3(2.05, 0.68, zc)))
		bx(0, 0, 0, 0.8, 0.5, 0.66, C.c2)
		bpop()
		bpush(Transform3D(Basis(Vector3(0, 0, 1), 0.6), Vector3(-2.25, 0.66, zc)))
		bx(0, 0, 0, 0.5, 0.45, 0.66, C.c2)
		bpop()
		# plaques de blindage latérales en camouflage
		for i in 5:
			bx(-1.6 + i * 0.75, 0.74, zc + z * 0.34, 0.7, 0.5, 0.04, cam[(i + (1 if z > 0 else 0)) % 3])
		# tourelle latérale (sponson) à canons rotatifs
		bx(0.45, 0.95, zc + z * 0.48, 0.7, 0.42, 0.34, C.c3)
		sp(0.78, 0.95, zc + z * 0.5, 0.2, C.c1)
		gatling(1.0, 0.95, zc + z * 0.5, 0.6, 0.06, C)
		bx(1.0, 0.85, zc + z * 0.2, 0.05, 0.08, 0.12, C.visor, true)
	# caisse centrale, glacis, pont moteur
	bx(-0.2, 1.05, 0, 3.8, 0.56, 1.7, C.c1)
	bpush(Transform3D(Basis(Vector3(0, 0, 1), -0.5), Vector3(1.75, 1.0, 0)))
	bx(0, 0, 0, 0.8, 0.34, 1.64, C.c2)
	bpop()
	bx(-0.5, 1.34, -0.4, 1.2, 0.04, 0.7, C.c3)
	bx(0.55, 1.34, 0.35, 1.0, 0.04, 0.6, C.c2)
	for i in 7:
		bx(-1.95 + i * 0.12, 1.36, 0, 0.06, 0.05, 1.2, C.dark)
	for z in [-0.6, 0.6]:
		cy(-2.0, 1.5, z, 0.09, 0.45, C.metal)
		cy(-2.0, 1.74, z, 0.1, 0.05, C.dark)
	# canon de caisse à bobines
	cy(2.2, 1.0, 0.45, 0.07, 1.0, C.metal, "x")
	for i in 3:
		cy(1.95 + i * 0.18, 1.0, 0.45, 0.095, 0.05, C.visor, "x", true)
	for z in [-0.55, 0.55]:
		bx(2.12, 0.86, z, 0.04, 0.08, 0.14, C.visor, true)
	cy(0.9, 1.37, -0.45, 0.16, 0.06, C.c3)
	cy(-1.0, 1.6, 0.6, 0.01, 0.6, C.metal)


func tank_turret(C: Dictionary) -> void:
	bx(0, 0.2, 0, 1.7, 0.4, 1.4, C.c1)
	bx(-0.05, 0.47, 0, 1.4, 0.16, 1.15, C.c2)
	for z in [-1.0, 1.0]:
		bx(0.5, 0.2, z * 0.72, 0.62, 0.32, 0.06, C.c3)
		for i in 3:
			cy(0.45 + i * 0.1, 0.43, z * 0.6, 0.035, 0.12, C.dark, "x")
	bx(0.9, 0.22, 0, 0.22, 0.36, 0.62, C.c3)
	bx(-0.95, 0.25, 0, 0.4, 0.3, 1.2, C.c2)
	cy(-0.3, 0.62, 0.32, 0.17, 0.14, C.c3)
	bx(-0.18, 0.66, 0.32, 0.04, 0.04, 0.2, C.visor, true)
	# tourelleau à canons rotatifs sur le toit
	bx(0.15, 0.64, -0.3, 0.36, 0.16, 0.26, C.c1)
	gatling(0.35, 0.66, -0.3, 0.5, 0.04, C)
	cy(-0.75, 0.95, -0.5, 0.01, 0.8, C.metal)


func tank_barrel(C: Dictionary) -> void:
	# canon lourd à bobines lumineuses
	cy(0.1, 0, 0, 0.14, 0.3, C.metal, "x")
	cy(1.15, 0, 0, 0.11, 2.0, C.metal, "x")
	for i in 4:
		cy(0.55 + i * 0.36, 0, 0, 0.13, 0.06, C.visor, "x", true)
	cy(2.2, 0, 0, 0.16, 0.22, C.dark, "x")


func fighter(C: Dictionary) -> void:
	# nez vers -Z
	bx(0, 0, 0, 0.9, 0.6, 3.6, C.plate)
	bx(0, 0.1, 0.3, 4.2, 0.12, 1.4, C.armor)
	bx(0, 0.42, -1.0, 0.5, 0.3, 0.9, C.dark)
	bx(0, 0.5, 1.4, 0.1, 0.9, 0.8, C.armor)
	for x in [-1.6, 1.6]:
		bx(x, 0.05, 0.1, 0.25, 0.25, 1.6, C.metal)
	for x in [-0.3, 0.3]:
		cy(x, 0, 1.85, 0.18, 0.2, C.visor, "z", true)


# ================================================================ mise en place
func setup(world) -> void:
	w = world
	P0 = w.BATTLE_A
	P1 = w.BATTLE_B
	PERP = Vector3.UP.cross((P1 - P0).normalized()).normalized()
	MIDN = Vector3.UP
	var mid := (P0 + P1) * 0.5
	MIDP = w.gp(mid.x, mid.z)
	MIDN = w.up_at(MIDP)
	RL = 0.0
	var prev: Vector3 = frame(0.0, 0.0).p
	for i in range(1, 21):
		var p: Vector3 = frame(i / 20.0, 0.0).p
		RL += p.distance_to(prev)
		prev = p

	# unités : plastique et métal peints, couleur de sommet (style « figurines » des images de référence)
	BODY = StandardMaterial3D.new()
	BODY.vertex_color_use_as_albedo = true
	BODY.vertex_color_is_srgb = true
	BODY.roughness = 0.5
	BODY.metallic = 0.25
	CHAR = StandardMaterial3D.new()
	CHAR.albedo_color = Color(0.09, 0.08, 0.07)
	CHAR.roughness = 1.0
	# camouflage : vert olive pour la colonie, rouille pour les pirates (c1 dominante, c2 sombre, c3 claire)
	PAL["b"] = {"armor": Color("3c4826"), "plate": Color("57553a"), "suit": Color("20261a"), "gear": Color("3a3424"), "metal": Color("3a3d3a"),
		"dark": Color("1c1e1a"), "fuel": Color("7a2a18"), "acc": Color("40e0ff"), "visor": Color("5ff0ff"), "tr": Color(1.0, 0.72, 0.28),
		"c1": Color("3c4826"), "c2": Color("283019"), "c3": Color("5a573a")}
	PAL["r"] = {"armor": Color("552018"), "plate": Color("6e4430"), "suit": Color("22120e"), "gear": Color("302a2a"), "metal": Color("3c3c42"),
		"dark": Color("1f1914"), "fuel": Color("7a2a18"), "acc": Color("ffb040"), "visor": Color("6dff4a"), "tr": Color(0.55, 1.0, 0.3),
		"c1": Color("552018"), "c2": Color("381410"), "c3": Color("6e4430")}
	for s in ["b", "r"]:
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0, 0, 0)
		em.emission_enabled = true
		em.emission = PAL[s].visor
		em.emission_energy_multiplier = 2.5 if s == "b" else 5.0
		EMIS[s] = em
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	glow_tex = gt

	# cuisson : 4 poses de marche + 1 pose arrêtée, et une pose couchée (morts)
	var swings := [0.42, 0.0, -0.42, 0.0, 0.0]
	var lying := Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0.95, 0.2, 0))
	for s in ["b", "r"]:
		var C: Dictionary = PAL[s]
		for k in ["rifle", "flame", "robot"]:
			var cap: int = {"rifle": 700, "flame": 260, "robot": 130}[k]
			for f in 5:
				if k == "robot":
					b_begin(Transform3D(Basis.from_scale(Vector3.ONE * 0.68), Vector3.ZERO))
					robot(C, swings[f])
				else:
					b_begin()
					trooper(C, k == "flame", swings[f])
				var mesh := b_end(EMIS[s])
				MM[s + k + str(f)] = make_mm(mesh, cap)
			if k != "robot":
				for f in [5, 6, 7]:
					b_begin()
					prone(C, k == "flame", 0.0 if f == 5 else (0.35 if f == 6 else -0.35))
					MM[s + k + str(f)] = make_mm(b_end(EMIS[s]), cap)
				b_begin(Transform3D(Basis.from_scale(Vector3(1.0, 0.68, 1.0)), Vector3.ZERO))
				trooper(C, k == "flame", 0.0)
				MM[s + k + "8"] = make_mm(b_end(EMIS[s]), cap)
			if k == "robot":
				b_begin(Transform3D(Basis(Vector3(0, 0, 1), PI / 2) * Basis.from_scale(Vector3.ONE * 0.68), Vector3(1.5, 0.5, 0)))
				robot(C, 0.0)
			else:
				b_begin(lying)
				trooper(C, k == "flame", 0.3)
			var dm := b_end(EMIS[s])
			DEAD[s + k] = {"mm": make_mm(dm, 1500), "list": [], "i": 0, "dirty": false}
		var S := Transform3D(Basis.from_scale(Vector3.ONE * 2.4), Vector3.ZERO)
		b_begin(S)
		tank_hull(C)
		TANKM[s + "hull"] = b_end(EMIS[s])
		b_begin(S)
		tank_turret(C)
		TANKM[s + "tur"] = b_end(EMIS[s])
		b_begin(S)
		tank_barrel(C)
		TANKM[s + "bar"] = b_end(EMIS[s])
		load_tank_glb(s, C)
		b_begin(Transform3D(Basis.from_scale(Vector3.ONE * 2.5), Vector3.ZERO))
		fighter(C)
		FIGHTM[s] = b_end(EMIS[s])
		b_begin(Transform3D(Basis.from_scale(Vector3.ONE * 6.0), Vector3.ZERO))
		fighter(C)
		FIGHTM[s + "big"] = b_end(EMIS[s])
		MM[s + "tracer"] = make_mm(box_mesh(Vector3(0.07, 0.07, 2.6), glow_mat(PAL[s].tr, 6.0)), 1600)
	MM["shell"] = make_mm(box_mesh(Vector3(0.3, 0.3, 1.4), glow_mat(Color(1.0, 0.8, 0.3), 8.0)), 300)

	# tourelles anti-aériennes de la colonie
	for lane in [-55.0, 55.0]:
		var g := Node3D.new()
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.4
		cm.bottom_radius = 3.0
		cm.height = 2.0
		base.mesh = cm
		base.material_override = mat(Color("5f6469"))
		base.position.y = 1.0
		g.add_child(base)
		var hd := Node3D.new()
		hd.position.y = 2.6
		g.add_child(hd)
		var body := MeshInstance3D.new()
		body.mesh = box_mesh(Vector3(3.6, 1.6, 3.0), mat(Color("8e9290")))
		hd.add_child(body)
		for z in [-0.7, 0.7]:
			var gun := MeshInstance3D.new()
			gun.mesh = box_mesh(Vector3(4.5, 0.25, 0.25), mat(Color("2a2d2f")))
			gun.position = Vector3(3.0, 0.3, z)
			hd.add_child(gun)
		add_child(g)
		# tourelle bien droite (verticale locale) sur un sol aplani à sa hauteur
		var fr := frame(0.06, lane)
		var upt: Vector3 = w.up_at(fr.p)
		var fwt: Vector3 = (fr.f - upt * fr.f.dot(upt)).normalized()
		g.basis = Basis(fwt, upt, fwt.cross(upt))
		g.position = fr.p
		w.add_flat_zone(fr.p, 4.5)
		TUR.append({"g": g, "hd": hd, "cool": 0.0})

	for i in 5:
		spawn("b", mix(), randf_range(0.06, 0.4))
		spawn("r", mix(), randf_range(0.6, 0.94))


# char modélisé dans Blender (tools/blender/char_lourd.py → models/char_lourd.glb) : remplace le modèle cuit en code s'il existe.
# Les matériaux du fichier (camo, sombre, metal, lueur) sont remplacés par ceux du camp.
const CAMO_SH := preload("res://shaders/camo.gdshader")
func load_tank_glb(s: String, C: Dictionary) -> void:
	if not ResourceLoader.exists("res://models/char_lourd.glb"):
		return
	var sc: PackedScene = load("res://models/char_lourd.glb")
	if sc == null:
		return
	var root: Node = sc.instantiate()
	var camo := ShaderMaterial.new()
	camo.shader = CAMO_SH
	camo.set_shader_parameter("c1", C.c1)
	camo.set_shader_parameter("c2", C.c2)
	camo.set_shader_parameter("c3", C.c3)
	var sombre := StandardMaterial3D.new()
	sombre.albedo_color = C.dark
	sombre.roughness = 0.85
	var metal := StandardMaterial3D.new()
	metal.albedo_color = C.metal
	metal.metallic = 0.6
	metal.roughness = 0.45
	var by := {"camo": camo, "sombre": sombre, "metal": metal, "lueur": EMIS[s]}
	for pair in [["coque", "hull"], ["tourelle", "tur"], ["canon", "bar"]]:
		var mi := root.find_child(pair[0], true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mesh: Mesh = mi.mesh.duplicate()
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			var nm: String = m.resource_name if m != null else ""
			if by.has(nm):
				mesh.surface_set_material(i, by[nm])
		TANKM[s + pair[1]] = mesh
	root.free()


func mat(c: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.4
	return m


func glow_mat(c: Color, e := 4.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func box_mesh(s: Vector3, m: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	b.material = m
	return b


func make_mm(mesh: Mesh, cap: int) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	var buf := PackedFloat32Array()
	buf.resize(cap * 12)
	return {"mm": mm, "mi": mi, "buf": buf, "cap": cap, "n": 0, "last": 0}


# ================================================================ géométrie du front
func frame(s: float, lane: float) -> Dictionary:
	var dv := (P1 - P0).normalized()
	var q := P0.lerp(P1, s) + PERP * lane
	var p: Vector3 = w.gp(q.x, q.z)
	var e := 2.0
	var p2: Vector3 = w.gp(q.x + dv.x * e, q.z + dv.z * e)
	var p3: Vector3 = w.gp(q.x + PERP.x * e, q.z + PERP.z * e)
	var tn := (p3 - p).cross(p2 - p).normalized()
	# verticale locale de l'astéroïde (et non la verticale du monde)
	var up: Vector3 = w.up_at(p)
	if tn.dot(up) < 0:
		tn = -tn
	var n: Vector3 = (tn * 0.5 + up * 0.5).normalized()
	var f := p2 - p
	f = (f - n * f.dot(n)).normalized()
	return {"p": p, "n": n, "f": f}


# point du sol à la verticale (radiale) d'un point 3D
func ground(p: Vector3) -> Vector3:
	return w.surf_point((p + Vector3(0, w.RC, 0)).normalized())


# repère d'un fantassin couché ou debout, posé sur le sol réel : axe X = direction du corps, Y = normale du terrain
func ground_frame(c: Vector3, fw: Vector3, half_len: float) -> Basis:
	var up0: Vector3 = w.up_at(c)
	var f0 := (fw - up0 * fw.dot(up0)).normalized()
	var s0 := f0.cross(up0)
	var pf := ground(c + f0 * half_len)
	var pb := ground(c - f0 * half_len)
	var pl := ground(c - s0 * 0.35)
	var pr := ground(c + s0 * 0.35)
	var fwd := (pf - pb).normalized()
	var up := (pr - pl).cross(fwd).normalized()
	if up.dot(up0) < 0.0:
		up = -up
	fwd = (fwd - up * fwd.dot(up)).normalized()
	return Basis(fwd, up, fwd.cross(up))


# demi-longueur et demi-écartement des chenilles d'un char (m)
const TRACK_HL := 5.6
const TRACK_HW := 2.75


# pose d'un char sur le terrain : les 4 extrémités des chenilles touchent le sol
func tank_pose(c: Vector3, fw: Vector3) -> Transform3D:
	var up0: Vector3 = w.up_at(c)
	var f0 := (fw - up0 * fw.dot(up0)).normalized()
	var s0 := f0.cross(up0)
	var pf := ground(c + f0 * TRACK_HL)
	var pb := ground(c - f0 * TRACK_HL)
	var pl := ground(c - s0 * TRACK_HW)
	var pr := ground(c + s0 * TRACK_HW)
	var fwd := (pf - pb).normalized()
	var up := (pr - pl).cross(fwd).normalized()
	if up.dot(up0) < 0.0:
		up = -up
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var o := (pf + pb + pl + pr) * 0.25
	# une bosse sous le milieu du char ne doit pas traverser la caisse
	var gc := ground(c)
	var d := (gc - o).dot(up)
	if d > 0.0:
		o += up * d
	return Transform3D(Basis(fwd, up, fwd.cross(up)), o)


# ================================================================ formations
func mix() -> String:
	var r := randf()
	if r < 0.55:
		return "rifle"
	if r < 0.67:
		return "flame"
	if r < 0.85:
		return "robot"
	return "tank"


func depth_of(k: String) -> float:
	var K: Dictionary = KIND[k]
	return ceil(float(K.n) / K.cols) * K.spx


func gap_m(a: Dictionary, b: Dictionary, same: bool) -> float:
	return (a.depth + b.depth) * 0.5 + (6.0 if same else 18.0)


func lane_free(lane: float, s: float, k: String) -> bool:
	var dp := depth_of(k)
	for v in FORM:
		if v.lane == lane and absf(v.s - s) * RL < (dp + v.depth) * 0.5 + 8.0:
			return false
	return true


func spawn(side: String, k: String, s := -99.0, want_lane = null) -> bool:
	if s == -99.0:
		s = -0.05 if side == "b" else 1.05
	var lanes := LANES.duplicate()
	lanes.shuffle()
	if want_lane != null:
		lanes.erase(want_lane)
		lanes.push_front(want_lane)
	var lane = null
	for l in lanes:
		if lane_free(l, s, k):
			lane = l
			break
	if lane == null:
		return false
	var K: Dictionary = KIND[k]
	var n: int = K.n
	var cols: int = K.cols
	var rows := int(ceil(float(n) / cols))
	var ox := PackedFloat32Array()
	var oz := PackedFloat32Array()
	var ph := PackedFloat32Array()
	var alive := PackedInt32Array()
	var pos := PackedVector3Array()
	F_cover_tmp = PackedByteArray()
	var jit: float = 1.3 if k != "tank" else 2.5
	for i in n:
		var r := i / cols
		var c := i % cols
		ox.append(((rows - 1) * 0.5 - r) * K.spx + randf_range(-jit, jit))
		oz.append((c - (cols - 1) * 0.5) * K.spz + randf_range(-jit, jit))
		ph.append(randf() * 4.0)
		alive.append(i)
		F_cover_tmp.append(0)
		pos.append(Vector3.ZERO)
	var F := {"side": side, "kind": k, "K": K, "s": s, "lane": lane, "dir": 1.0 if side == "b" else -1.0, "ox": ox, "oz": oz, "ph": ph,
		"alive": alive, "pos": pos, "s_cache": -9.0, "f_cache": Vector3.ZERO, "basis": Basis(), "dmg": 0.0, "moving": false, "target": null,
		"retarget": 0.0, "fire_acc": 0.0, "heal_t": randf_range(0, 3), "depth": depth_of(k), "p": Vector3.ZERO, "n": Vector3.UP, "f": Vector3.RIGHT,
		"tanks": [], "tcool": PackedFloat32Array(), "dead": false, "n0": n, "cover": F_cover_tmp, "state": "march", "danger": false, "los": 1.0}
	if k == "tank":
		for i in n:
			var h := Node3D.new()
			var hull := MeshInstance3D.new()
			hull.mesh = TANKM[side + "hull"]
			h.add_child(hull)
			var tu := Node3D.new()
			tu.position = Vector3(-0.3 * 2.4, 1.36 * 2.4, 0)
			h.add_child(tu)
			var tm := MeshInstance3D.new()
			tm.mesh = TANKM[side + "tur"]
			tu.add_child(tm)
			var br := Node3D.new()
			br.position = Vector3(1.0 * 2.4, 0.22 * 2.4, 0)
			tu.add_child(br)
			var bm := MeshInstance3D.new()
			bm.mesh = TANKM[side + "bar"]
			br.add_child(bm)
			add_child(h)
			F.tanks.append({"h": h, "tu": tu, "br": br, "rec": 0.0})
			F.tcool.append(randf_range(0, 3.2))
	# colonie : les renforts sortent du hangar le plus proche et marchent jusqu'à leur couloir du front
	if side == "b" and s < 0.0 and w.HANGARS.size() > 0:
		var entry: Vector3 = frame(s, lane).p
		var best: Dictionary = w.HANGARS[0]
		for hg in w.HANGARS:
			if (hg.door as Vector3).distance_to(entry) < (best.door as Vector3).distance_to(entry):
				best = hg
		var a: Vector2 = w.planar(best.door)
		var b: Vector2 = w.planar(entry)
		F.tr = {"a": a, "b": b, "d": 0.0, "dc": 0.0, "L": maxf(a.distance_to(b), 1.0)}
	FORM.append(F)
	if F.has("tr"):
		tr_frame(F)
	else:
		upd_frame(F)
	recompute(F)
	return true


# position d'une formation en route du hangar vers le front (chemin à plat, posé sur le sol)
func tr_frame(F: Dictionary) -> void:
	var tr: Dictionary = F.tr
	var u: float = clampf(tr.d / tr.L, 0.0, 1.0)
	var q: Vector2 = (tr.a as Vector2).lerp(tr.b, u)
	var q2: Vector2 = (tr.a as Vector2).lerp(tr.b, minf(1.0, u + 2.0 / tr.L))
	if q2.distance_to(q) < 0.5:
		q2 = q + ((tr.b as Vector2) - (tr.a as Vector2)).normalized() * 2.0
	var p: Vector3 = w.gp(q.x, q.y)
	var p2: Vector3 = w.gp(q2.x, q2.y)
	var n: Vector3 = w.up_at(p)
	var f := p2 - p
	F.p = p
	F.n = n
	F.f = (f - n * f.dot(n)).normalized()


func upd_frame(F: Dictionary) -> void:
	var fr := frame(F.s, F.lane)
	F.p = fr.p
	F.n = fr.n
	F.f = fr.f


func recompute(F: Dictionary) -> void:
	var fw: Vector3 = F.f * F.dir
	var n: Vector3 = F.n
	var side := fw.cross(n)
	var pos: PackedVector3Array = F.pos
	var ox: PackedFloat32Array = F.ox
	var oz: PackedFloat32Array = F.oz
	var cov: PackedByteArray = F.cover
	var fight: bool = F.state != "march" and F.kind != "robot" and F.kind != "tank"
	# au contact, l'unité se disperse (espacement plus large)
	var spread: float = 1.0 if F.state == "march" or F.kind == "tank" else 1.6
	# en route depuis le hangar : formation resserrée
	if F.has("tr"):
		spread = 0.55
	for i in F.alive:
		var q: Vector3 = F.p + fw * ox[i] * spread + side * oz[i] * spread
		cov[i] = 0
		if fight:
			var rk = w.cover_near(q, 4.5)
			if rk != null:
				var c: Vector3 = rk[0]
				var rr: float = rk[1]
				q = c - fw * (rr + 0.55) + side * (hash_f(i) - 0.5) * rr
				cov[i] = 1
		pos[i] = q
	separate(F, pos)
	# chaque fantassin est posé et orienté sur le sol réel sous lui (un corps couché ne doit pas s'enfoncer)
	var mb: Array = F.get("mb", [])
	mb.resize(pos.size())
	# debout : aligné sur la pesanteur (vers le centre de masse de l'astéroïde), et non sur la pente
	var mg: Array = F.get("mg", [])
	mg.resize(pos.size())
	var mgo := PackedVector3Array()
	mgo.resize(pos.size())
	for i in F.alive:
		pos[i] = ground(pos[i])
		if F.kind != "tank":
			var yaw := (hash_f(i * 13 + 1) - 0.5) * 0.7
			var fwi := fw.rotated(w.up_at(pos[i]), yaw)
			mb[i] = ground_frame(pos[i], fwi, 1.1)
			pos[i] += (mb[i] as Basis).y * 0.03
			var g: Vector3 = w.grav_up(pos[i])
			var fg := (fwi - g * fwi.dot(g)).normalized()
			mg[i] = Basis(fg, g, fg.cross(g))
			# sur une pente, les pieds côté montée ne doivent pas s'enfoncer : on relève de pente × demi-pied
			var c := clampf(g.dot((mb[i] as Basis).y), 0.3, 1.0)
			mgo[i] = g * (0.3 * sqrt(1.0 - c * c) / c)
	F.mb = mb
	F.mg = mg
	F.mgo = mgo
	F.pos = pos
	F.cover = cov
	F.s_cache = F.s
	F.f_cache = F.f
	F.basis = Basis(fw, n, side)


# rayon d'encombrement au sol de chaque type (m)
func body_r(k: String) -> float:
	match k:
		"tank":
			return 6.6
		"robot":
			return 1.1
	return 0.55


# aucun modèle ne rentre dans un autre : ni entre soldats, ni dans les rochers, ni dans une autre formation
func separate(F: Dictionary, pos: PackedVector3Array) -> void:
	var r: float = body_r(F.kind)
	var al: PackedInt32Array = F.alive
	var n := al.size()
	# formations voisines (positions déjà posées)
	var others := []
	for G in FORM:
		if G == F or G.dead:
			continue
		if (G.p as Vector3).distance_to(F.p) < (F.depth + G.depth) * 0.5 + 30.0:
			others.append(G)
	for it in 3:
		# entre membres de la formation
		for a in n:
			var ia: int = al[a]
			for b in range(a + 1, n):
				var ib: int = al[b]
				var d: Vector3 = pos[ib] - pos[ia]
				var L := d.length()
				var need := 2.0 * r
				if L < need:
					var dirv: Vector3 = d / L if L > 0.001 else F.basis.z
					var push: Vector3 = dirv * (need - L) * 0.5
					pos[ia] -= push
					pos[ib] += push
		for a in n:
			var ia: int = al[a]
			var q: Vector3 = pos[ia]
			# rochers
			var rk = w.cover_near(q, r + 0.1)
			if rk != null:
				var c: Vector3 = rk[0]
				var dd := Vector3(q.x - c.x, 0.0, q.z - c.z)
				var L := dd.length()
				var need: float = float(rk[1]) + r
				if L < need:
					q += (dd / L if L > 0.001 else Vector3.RIGHT) * (need - L)
			# autres formations
			for G in others:
				var rg: float = body_r(G.kind)
				var gp: PackedVector3Array = G.pos
				var sh: Vector3 = G.f_cache * ((G.s - G.s_cache) * RL)
				var moved := false
				for j in G.alive:
					var o: Vector3 = gp[j] + sh
					var d2: Vector3 = q - o
					var L2 := d2.length()
					if L2 < r + rg:
						var u: Vector3 = d2 / L2 if L2 > 0.001 else F.basis.z
						if rg >= r:
							q += u * (r + rg - L2)
						else:
							# le plus petit s'écarte (les fantassins laissent passer le char)
							o -= u * (r + rg - L2 + 0.1)
							gp[j] = ground(o) - sh
							moved = true
				if moved:
					G.pos = gp
			pos[ia] = q


func hash_f(i: int) -> float:
	return fposmod(sin(i * 12.9898) * 43758.5453, 1.0)


func mpos(F: Dictionary, i: int) -> Vector3:
	return F.pos[i] + F.f_cache * ((F.s - F.s_cache) * RL)


func rand_member(F: Dictionary) -> int:
	var al: PackedInt32Array = F.alive
	return al[randi() % al.size()]


func kill_one(F: Dictionary) -> void:
	var al: PackedInt32Array = F.alive
	if al.size() == 0:
		return
	var j := randi() % al.size()
	if F.kind != "tank":
		# les premiers rangs tombent d'abord
		var best := j
		for t in 3:
			var c := randi() % al.size()
			if F.ox[al[c]] > F.ox[al[best]]:
				best = c
		j = best
	var idx: int = al[j]
	al[j] = al[al.size() - 1]
	al.resize(al.size() - 1)
	F.alive = al
	kills["r" if F.side == "b" else "b"] += 1
	var p := mpos(F, idx)
	var n: Vector3 = F.n
	if F.kind == "tank":
		var t: Dictionary = F.tanks[idx]
		boom(p + n * 2.5, n, 2.6)
		for c in t.h.find_children("*", "MeshInstance3D", true, false):
			c.material_override = CHAR
		WR.append({"o": t.h, "l": 40.0, "n": n})
		t.dead = true
	elif PARTS < 700:
		var src: Vector3 = (F.target.p as Vector3) if F.target != null else F.p - F.f * F.dir * 50.0
		dismember(F, p, n, (p - src).normalized())
	else:
		var D: Dictionary = DEAD[F.side + F.kind]
		# le corps est couché à plat sur le sol réel, dans une direction au hasard
		var g := ground(p)
		var b: Basis = ground_frame(g, (F.basis as Basis).x.rotated(w.up_at(g), randf() * TAU), 1.0)
		var tf := Transform3D(b, g + b.y * 0.03)
		if D.list.size() < D.mm.cap:
			D.list.append(tf)
		else:
			D.list[D.i] = tf
			D.i = (D.i + 1) % D.mm.cap
		D.dirty = true
		if randf() < 0.25:
			spr(p + n * 0.6, Color(0.6, 0.55, 0.5, 0.6), 2.0, 0.8, n * 1.5, true, false)
	if al.size() == 0:
		F.dead = true


func damage(T: Dictionary, amount: float) -> void:
	if T.dead:
		return
	T.dmg += amount
	var hp: float = T.K.hp * (1.0 + wave * 0.02)
	while T.dmg >= hp and not T.dead:
		T.dmg -= hp
		kill_one(T)


# ================================================================ effets
func los_frac(F: Dictionary, T: Dictionary) -> float:
	if F.alive.size() == 0 or T.alive.size() == 0:
		return 0.0
	var vis := 0
	var n := 6
	var soldier: bool = F.kind == "rifle" or F.kind == "flame"
	var tsold: bool = T.kind == "rifle" or T.kind == "flame"
	for k in n:
		var mi := rand_member(F)
		var hh: float = (0.9 if F.cover[mi] == 1 else 0.3) if soldier else float(F.K.h)
		var a: Vector3 = mpos(F, mi) + F.n * hh
		var tm := rand_member(T)
		var th: float = ((0.9 if T.cover[tm] == 1 else 0.35) if T.state != "march" else 1.3) if tsold else float(T.K.h) * 0.8
		var b: Vector3 = mpos(T, tm) + T.n * th
		if w.los_hit(a, b) == null:
			vis += 1
	return float(vis) / n


func puff(p: Vector3, c: Color, size: float, life: float, vel := Vector3.ZERO) -> void:
	# nuage de poussière / fumée (sprite face caméra, éclairé)
	if FX.size() > 650:
		return
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	m.mesh = q
	var mt := StandardMaterial3D.new()
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mt.billboard_keep_scale = true
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_texture = w.smoke_tex
	mt.albedo_color = c
	mt.roughness = 1.0
	mt.disable_receive_shadows = true
	m.material_override = mt
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = p
	m.scale = Vector3.ONE * size * 0.35
	add_child(m)
	FX.append({"o": m, "k": "puff", "l": life, "L": life, "sc": size, "v": vel, "mat": mt, "a0": c.a})


func tank_smoke(t: Dictionary, F: Dictionary) -> void:
	# le souffle du tir soulève la poussière tout autour du char, plus un nuage devant le canon
	var c: Vector3 = t.h.position
	var up: Vector3 = F.n
	var e1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var e2 := up.cross(e1).normalized()
	for i in 12:
		var ang := TAU * i / 12.0 + randf_range(-0.2, 0.2)
		var dv := e1 * cos(ang) + e2 * sin(ang)
		puff(c + dv * randf_range(3.0, 6.0) + up * randf_range(0.6, 1.6), Color(0.48, 0.38, 0.3, 0.8), randf_range(6.0, 10.0), randf_range(2.6, 4.2),
			dv * randf_range(4.0, 8.0) + up * randf_range(0.4, 1.6))
	var fw: Vector3 = t.br.global_transform.basis.x.normalized()
	var muz: Vector3 = t.br.to_global(Vector3(2.3 * 2.4, 0, 0))
	for i in 5:
		puff(muz + fw * (i * 2.2), Color(0.58, 0.55, 0.51, 0.75), randf_range(3.0, 6.5), randf_range(1.8, 3.0), fw * randf_range(3.0, 9.0) + up * randf_range(0.3, 1.2))


func spr(p: Vector3, c: Color, size: float, life: float, vel := Vector3.ZERO, grow := false, add := true) -> void:
	if FX.size() > 420:
		return
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	m.mesh = q
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mt.billboard_keep_scale = true
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_texture = glow_tex
	mt.albedo_color = c
	m.material_override = mt
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = p
	m.scale = Vector3.ONE * size * (0.3 if grow else 1.0)
	add_child(m)
	FX.append({"o": m, "k": "spr", "l": life, "L": life, "sc": size, "v": vel, "grow": grow, "mat": mt, "c": c})


func ball(p: Vector3, c: Color, size: float, life: float, vel: Vector3, glow: bool) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 12
	s.rings = 6
	m.mesh = s
	var mt := StandardMaterial3D.new()
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = c
	if glow:
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mt.roughness = 1.0
	m.material_override = mt
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = p
	m.scale = Vector3.ONE * 0.01
	add_child(m)
	FX.append({"o": m, "k": "ball", "l": life, "L": life, "sc": size, "v": vel, "mat": mt, "a0": c.a})


func boom(p: Vector3, n: Vector3, k: float) -> void:
	ball(p, Color(1.6, 1.4, 0.8), 1.4 * k, 0.25, Vector3.ZERO, true)
	ball(p, Color(1.4, 0.55, 0.15), 3.0 * k, 0.55, Vector3.ZERO, true)
	spr(p, Color(1.0, 0.7, 0.35), 12.0 * k, 0.22)
	var li := OmniLight3D.new()
	li.light_color = Color(1.0, 0.65, 0.3)
	li.light_energy = 8.0 * k
	li.omni_range = 18.0 * k
	li.position = p + n * 2.0
	add_child(li)
	FX.append({"o": li, "k": "light", "l": 0.4, "L": 0.4, "e": 8.0 * k})
	for i in int(4 * k):
		ball(p, Color(0.3, 0.29, 0.28, 0.85), randf_range(1.5, 3.0) * k, randf_range(2.0, 3.5),
			n * randf_range(1.5, 4.0) + Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)), false)
	for i in int(5 * k):
		var d := MeshInstance3D.new()
		d.mesh = box_mesh(Vector3.ONE, CHAR)
		d.scale = Vector3.ONE * randf_range(0.2, 0.6)
		d.position = p
		add_child(d)
		FX.append({"o": d, "k": "deb", "l": randf_range(1.0, 1.8), "L": 1.8, "n": n,
			"v": n * randf_range(6, 14) + Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))})


func tracer(from: Vector3, to: Vector3, side: String, speed := 380.0, ric := false) -> void:
	if TR.size() > 1500:
		return
	# un tir venant de l'extérieur s'écrase sur le bouclier du centre de commandement
	var hit = w.shield_clip(from, to)
	if hit != null:
		to = hit
		ric = false
	var d := to - from
	var L := d.length()
	if L < 1.0:
		return
	var t := {"p": from, "v": d / L * speed, "l": L / speed, "side": side, "ric": ric}
	if hit != null:
		t.sh = true
	TR.append(t)


# balle déviée : étincelle et nouvelle trajectoire courte
func ricochet(t: Dictionary) -> void:
	var p: Vector3 = t.p
	var n: Vector3 = w.up_at(p)
	var v: Vector3 = t.v
	var r: Vector3 = v - 2.0 * v.dot(n) * n
	r = (r.normalized() + Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.6), randf_range(-0.5, 0.5))).normalized()
	if r.dot(n) < 0.15:
		r = (r + n * 0.5).normalized()
	spr(p, Color(1.6, 1.3, 0.7), randf_range(0.5, 0.9), 0.12)
	var L := randf_range(12.0, 40.0)
	TR.append({"p": p, "v": r * v.length() * 0.6, "l": L / (v.length() * 0.6), "side": t.side, "ric": false})


# morceaux du soldat ou du robot projetés selon le point d'impact
var PARTS := 0
var PMESH := {}
func part_mesh(key: String, size: Vector3, c: Color, sphere: bool) -> Mesh:
	if PMESH.has(key):
		return PMESH[key]
	var m: Mesh
	if sphere:
		var sm := SphereMesh.new()
		sm.radius = size.x
		sm.height = size.x * 2.0
		sm.radial_segments = 10
		sm.rings = 6
		m = sm
	else:
		var bm := BoxMesh.new()
		bm.size = size
		m = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = 0.8
	m.surface_set_material(0, mt)
	PMESH[key] = m
	return m


func dismember(F: Dictionary, p: Vector3, n: Vector3, dirv: Vector3) -> void:
	var C: Dictionary = PAL[F.side]
	var robo: bool = F.kind == "robot"
	var k := 2.0 if robo else 1.0
	var fw: Vector3 = F.f * F.dir
	var sd: Vector3 = fw.cross(n).normalized()
	# [nom, taille, hauteur, décalage latéral, couleur, sphère, zone]
	var parts := [
		["tete", Vector3(0.15, 0, 0), 1.7, 0.0, C.armor, true, 0],
		["torse", Vector3(0.32, 0.45, 0.42), 1.3, 0.0, C.armor, false, 1],
		["brasg", Vector3(0.12, 0.42, 0.12), 1.25, -0.27, C.suit, false, 1],
		["brasd", Vector3(0.12, 0.42, 0.12), 1.25, 0.27, C.suit, false, 1],
		["jambeg", Vector3(0.17, 0.75, 0.17), 0.55, -0.12, C.armor, false, 2],
		["jambed", Vector3(0.17, 0.75, 0.17), 0.55, 0.12, C.armor, false, 2],
		["piedg", Vector3(0.27, 0.12, 0.17), 0.06, -0.12, C.dark, false, 2],
		["piedd", Vector3(0.27, 0.12, 0.17), 0.06, 0.12, C.dark, false, 2],
	]
	if not robo:
		parts.append(["arme", Vector3(0.86, 0.09, 0.06), 1.2, 0.2, C.dark, false, 1])
	var zone := 0 if randf() < 0.2 else (1 if randf() < 0.65 else 2)
	for pt in parts:
		var o := MeshInstance3D.new()
		o.mesh = part_mesh(F.side + F.kind + pt[0], pt[1] * k, pt[4], pt[5])
		o.position = p + n * pt[2] * k + sd * pt[3] * k
		o.basis = F.basis
		add_child(o)
		var hit: bool = pt[6] == zone
		var sp_: float = randf_range(5.0, 9.0) if hit else randf_range(0.8, 2.5)
		var v: Vector3 = dirv * sp_ + n * randf_range(1.5, 4.0 if hit else 2.0) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * (2.5 if hit else 1.2)
		FX.append({"o": o, "k": "part", "l": 60.0, "L": 60.0, "n": n, "v": v, "rest": false,
			"av": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)) * (1.0 if hit else 0.4), "hs": (pt[1] as Vector3).y * k * 0.5 if not pt[5] else (pt[1] as Vector3).x * k})
		PARTS += 1
	spr(p + n * 1.2 * k, Color(1.4, 1.1, 0.6), 1.2 * k, 0.1)


func shell(from: Vector3, to: Vector3) -> void:
	var hit = w.shield_clip(from, to)
	if hit != null:
		to = hit
	var d := to - from
	var L := d.length()
	var s := {"p": from, "v": d / L * 240.0, "l": L / 240.0, "to": to}
	if hit != null:
		s.sh = true
	SHELLS.append(s)


# ================================================================ boucle de simulation
func step(dt: float) -> void:
	time += dt
	wt += dt
	if wt > 60:
		wt = 0
		wave += 1
	var fb := -1.0
	var fr := 2.0
	var nb := 0
	var nr := 0
	for F in FORM:
		if F.side == "b":
			fb = maxf(fb, F.s)
			nb += 1
		else:
			fr = minf(fr, F.s)
			nr += 1
	var front := 0.5
	if fb < 0:
		front = 0.5 if fr > 1 else fr - 0.05
	elif fr > 1:
		front = fb + 0.05
	else:
		front = (fb + fr) / 2
	var bias := front - 0.5
	if nb < 9 and randf() < dt * 0.09 * (1.0 + bias * 3.0):
		spawn("b", mix())
	# pirates : renforts uniquement par vaisseaux de débarquement (voir air())
	if not kronos_dead and nr + DS.size() < 9 and DS.size() < 3 and randf() < dt * 0.08 * (1.0 - bias * 3.0):
		request_drop()

	for F in FORM:
		if F.dead:
			continue
		F.moving = false
		# en route depuis le hangar : marche jusqu'au couloir, sans combattre
		if F.has("tr"):
			var trd: Dictionary = F.tr
			trd.d += float(F.K.speed) * dt
			F.moving = true
			if trd.d >= trd.L:
				F.erase("tr")
				upd_frame(F)
				recompute(F)
			else:
				tr_frame(F)
				if trd.d - trd.dc > 1.5:
					recompute(F)
					trd.dc = trd.d
			continue
		F.retarget -= dt
		var dir: float = F.dir
		var K: Dictionary = F.K
		if F.retarget <= 0 or (F.target != null and (F.target.dead or F.target.alive.size() == 0)):
			F.retarget = 0.5
			F.target = null
			var bd := 1e9
			var near := 1e9
			for T in FORM:
				if T.dead or T.side == F.side or (T.s - F.s) * dir < -0.03:
					continue
				var d: float = F.p.distance_to(T.p) - (F.depth + T.depth) * 0.5
				near = minf(near, d)
				if d < K.rng and d < bd:
					bd = d
					F.target = T
			F.danger = near < K.rng * 1.8
			# ligne de vue réelle : relief du sol et rochers
			F.los = los_frac(F, F.target) if F.target != null else 1.0
			var st := "fight" if (F.target != null and F.los >= 0.15) else ("crawl" if (F.danger or F.target != null) else "march")
			if st != F.state:
				F.state = st
				recompute(F)
		var T = F.target
		if T != null and F.los >= 0.15:
			var al: int = F.alive.size()
			var mult: float = MULT[F.kind][T.kind]
			damage(T, al * K.dps * dt * mult * randf_range(0.7, 1.3) * F.los)
			if T.dead or T.alive.size() == 0:
				F.target = null
				continue
			# visuels
			if F.kind == "flame":
				F.fire_acc += dt * 26.0
				var fw: Vector3 = F.f * dir
				while F.fire_acc >= 1.0:
					F.fire_acc -= 1.0
					var i := rand_member(F)
					if F.ox[i] < 0:
						continue
					var p: Vector3 = mpos(F, i) + F.n * 1.15 + fw * 0.8
					spr(p, [Color(1, 0.82, 0.38), Color(1, 0.54, 0.16), Color(1, 0.35, 0.1)].pick_random(), randf_range(1.2, 2.2), randf_range(0.6, 0.9),
						fw * randf_range(18, 26) + F.n * randf_range(0.0, 2.5) + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), true)
			elif F.kind == "tank":
				var tc: PackedFloat32Array = F.tcool
				for i in F.alive:
					tc[i] -= dt
					if tc[i] <= 0:
						tc[i] = randf_range(2.8, 3.6)
						var t: Dictionary = F.tanks[i]
						var from: Vector3 = t.br.to_global(Vector3(2.3 * 2.4, 0, 0))
						var to: Vector3 = mpos(T, rand_member(T)) + T.n * 1.0 + Vector3(randf_range(-3, 3), randf_range(-1, 1), randf_range(-3, 3))
						var hitp = w.los_hit(from, to)
						if hitp != null:
							to = hitp
						shell(from, to)
						spr(from, Color(1.0, 0.75, 0.4), 6.0, 0.12)
						tank_smoke(t, F)
						t.rec = 0.3
				F.tcool = tc
			else:
				F.fire_acc += al * K.fire * dt
				var nmax := 40
				while F.fire_acc >= 1.0 and nmax > 0:
					F.fire_acc -= 1.0
					nmax -= 1
					var mi := rand_member(F)
					var hh: float = K.h if F.kind == "robot" else (0.9 if F.cover[mi] == 1 else 0.3)
					var from: Vector3 = mpos(F, mi) + F.n * hh + F.f * dir * 0.8
					var th: float = T.K.h * 0.8 if (T.kind == "robot" or T.kind == "tank" or T.state == "march") else 0.35
					var to: Vector3 = mpos(T, rand_member(T)) + T.n * th
					if randf() < 0.3:
						to += Vector3(randf_range(-3, 3), randf_range(-1, 3), randf_range(-3, 3))
					if randf() > F.los:
						# tir arrêté par le relief ou un rocher
						to = from.lerp(to, randf_range(0.25, 0.85))
						if randf() < 0.25:
							puff(to, Color(0.6, 0.48, 0.38, 0.6), randf_range(1.0, 2.0), randf_range(0.8, 1.4), F.n * 0.8)
					# blindage non percé : la balle ricoche
					var ric := 0.0
					if T.kind == "tank":
						ric = 0.85 if F.kind != "robot" else 0.55
					elif T.kind == "robot":
						ric = 0.5 if F.kind != "robot" else 0.2
					var blocked := to.distance_to(mpos(T, 0)) > 30.0
					if blocked:
						ric = 0.35
					tracer(from, to, F.side, 420.0 if F.kind == "robot" else 360.0, randf() < ric)
		else:
			var ns: float = F.s + dir * K.speed * (0.32 if (F.state == "crawl" and F.kind != "tank" and F.kind != "robot") else 1.0) / RL * dt
			var ok := true
			for v in FORM:
				if v == F or v.dead or v.lane != F.lane or (v.s - F.s) * dir <= 0:
					continue
				if absf(v.s - ns) * RL < gap_m(F, v, v.side == F.side):
					ok = false
					break
			if ok:
				F.s = ns
				F.moving = true
				upd_frame(F)
				if absf(F.s - F.s_cache) * RL > 1.5:
					recompute(F)
		if K.has("heal") or F.kind == "robot":
			F.heal_t -= dt
			if F.heal_t <= 0:
				F.heal_t = 3.0
				for G in FORM:
					if G.side == F.side and not G.dead and G.alive.size() > 0 and G.p.distance_to(F.p) < 90.0 and G.dmg > 0:
						G.dmg = maxf(0.0, G.dmg - 4.0 * F.alive.size())
						for i in 3:
							spr(mpos(G, rand_member(G)) + G.n * 2.5, Color(0.5, 1, 0.45), 1.6, 1.0, G.n * 2.5)
		if F.s < -0.1 or F.s > 1.1:
			F.dead = true
	for F in FORM:
		if F.dead and F.kind == "tank":
			for t in F.tanks:
				if not t.has("dead"):
					t.h.queue_free()
	FORM = FORM.filter(func(x): return not x.dead)

	# projectiles
	var newric := []
	for t in TR:
		t.p += t.v * dt
		t.l -= dt
		if t.l <= 0 and t.has("sh"):
			spr(t.p, Color(0.45, 0.85, 1.0), 2.2, 0.25)
			w.shield_hit(t.p, 0.08)
		elif t.l <= 0 and t.ric:
			newric.append(t)
	TR = TR.filter(func(x): return x.l > 0)
	for t in newric:
		ricochet(t)
	for s in SHELLS:
		s.p += s.v * dt
		s.l -= dt
		if s.l <= 0:
			if s.has("sh"):
				spr(s.to, Color(0.5, 0.9, 1.0), 9.0, 0.4)
				w.shield_hit(s.to, 1.2)
			else:
				boom(s.to, MIDN, 0.7)
	SHELLS = SHELLS.filter(func(x): return x.l > 0)

	# épaves fumantes
	for wr in WR:
		wr.l -= dt
		if wr.l > 15 and randf() < dt * 4:
			ball(wr.o.position + wr.n * 3, Color(0.15, 0.15, 0.15, 0.8), randf_range(1.5, 2.5), 3.0, wr.n * 3.0, false)
	for wr in WR:
		if wr.l <= 0:
			wr.o.queue_free()
	WR = WR.filter(func(x): return x.l > 0)

	air(dt)


# ================================================================ aviation
func fpos(f: Dictionary, t: float) -> Vector3:
	var c: Vector3 = MIDP + MIDN * f.h
	var u := PERP
	var v := MIDN.cross(u).normalized()
	return c + u * cos(t) * f.R + v * sin(t) * f.R * 0.7 + MIDN * sin(t * 2 + f.tilt) * 8.0


func aim_node(m: Node3D, d: Vector3) -> void:
	if d.length() < 0.001:
		return
	var up := MIDN if absf(d.normalized().dot(MIDN)) < 0.98 else PERP
	m.basis = Basis.looking_at(d, up)


func air(dt: float) -> void:
	var cb := 0
	var cr := 0
	for f in FT:
		if f.side == "b":
			cb += 1
		else:
			cr += 1
	# chasseurs de la colonie en vol : 2, plus les vaisseaux des flottes en patrouille défensive
	var cap_b := 2
	if w.strategy != null:
		cap_b = mini(10, 2 + w.strategy.nships(w.strategy.def_ships()))
	if cb < cap_b and randf() < dt * 0.5:
		add_fighter("b")
	if not kronos_dead and cr < 4 and randf() < dt * 0.5:
		add_fighter("r")
	for f in FT:
		if f.dead:
			continue
		f.t += f.w * dt
		var p := fpos(f, f.t)
		var q := fpos(f, f.t + f.w * 0.05)
		# chasseurs de la colonie : décollage depuis un hangar, puis montée vers leur orbite
		if f.has("l") and f.l < 1.0:
			f.l = minf(1.0, f.l + dt / 6.0)
			var e := smoothstep(0.0, 1.0, f.l)
			var door: Vector3 = f.door
			var up: Vector3 = w.up_at(door)
			p = (door + up * (3.0 + 40.0 * e * e)).lerp(p, e)
			q = p + (fpos(f, f.t) - p).normalized() + up * 0.3
		# chasseurs pirates : le bouclier les empêche d'entrer
		if f.side == "r":
			p = w.shield_push(p, 15.0)
			q = w.shield_push(q, 15.0)
		f.g.position = p
		aim_node(f.g, q - p)
		f.cool -= dt
		if f.cool <= 0:
			f.cool = randf_range(0.15, 0.4)
			var best = null
			var bd := 170.0
			for o in FT:
				if o.side != f.side and not o.dead and o.g.position.distance_to(p) < bd:
					bd = o.g.position.distance_to(p)
					best = o
			# la colonie chasse en priorité les vaisseaux de débarquement (fragiles, chargés de troupes)
			if f.side == "b":
				for d in DS:
					if not d.dead and d.g.position.distance_to(p) < 260.0:
						best = d
						break
			if best != null:
				tracer(p, best.g.position + Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)), f.side, 600.0)
				if randf() < 0.12:
					best.hp -= 1
					if best.hp <= 0 and not best.dead:
						if best.has("drop"):
							ds_destroyed(best)
						else:
							best.dead = true
							boom(best.g.position, MIDN, 1.6)
							best.g.queue_free()
	FT = FT.filter(func(x): return not x.dead)
	for tu in TUR:
		tu.cool -= dt
		var tg = null
		var bd := 260.0
		for f in FT:
			if f.side == "r" and f.g.position.distance_to(tu.g.position) < bd:
				bd = f.g.position.distance_to(tu.g.position)
				tg = f
		for d in DS:
			if not d.dead and d.g.position.distance_to(tu.g.position) < bd:
				bd = d.g.position.distance_to(tu.g.position)
				tg = d
		if tg != null:
			var tp: Vector3 = tg.g.position
			var l: Vector3 = tu.hd.to_local(tp)
			tu.hd.rotation.y += atan2(-l.z, l.x) * minf(1.0, dt * 4)
			if tu.cool <= 0:
				tu.cool = 0.12
				var from: Vector3 = tu.hd.to_global(Vector3(5.5, 0.3, 0))
				tracer(from, tp + Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), "b", 700.0)
				if randf() < 0.03:
					tg.hp -= 1
					if tg.hp <= 0 and not tg.dead:
						if tg.has("drop"):
							ds_destroyed(tg)
						else:
							tg.dead = true
							boom(tp, MIDN, 1.6)
							tg.g.queue_free()
	# vaisseaux pirates de débarquement : seul moyen d'amener des troupes. Fragiles, ils se posent au bout du front,
	# à l'opposé de la zone défendue par le centre de commandement, débarquent leur formation puis repartent.
	for d in DS:
		if d.dead:
			continue
		d.t += dt
		var fr0 := frame(d.s, d.lane)
		var land: Vector3 = fr0.p
		var n: Vector3 = fr0.n
		var away: Vector3 = fr0.f
		var p: Vector3
		var look: Vector3
		if d.t < 9.0:
			# approche : descente depuis l'espace, en venant du côté opposé à la base
			var e: float = 1.0 - pow(1.0 - d.t / 9.0, 2.0)
			p = land + n * lerpf(240.0, 6.0, e) + away * lerpf(280.0, 0.0, e)
			look = -away - n * 0.6 * (1.0 - e)
		elif d.t < 15.0:
			p = land + n * 6.0
			look = -away
			if not d.drop and d.t > 10.0:
				d.drop = spawn("r", d.kind, d.s, d.lane)
				if d.drop:
					for i in 8:
						puff(land + Vector3(randf_range(-8, 8), 0.5, randf_range(-8, 8)), Color(0.55, 0.53, 0.5, 0.6), randf_range(4, 8), 2.0, n * 1.5)
		else:
			# redécollage (si personne n'a pu débarquer, les troupes restent à bord)
			var u: float = (d.t - 15.0) / 8.0
			p = land + n * (6.0 + u * u * 280.0) + away * u * 140.0
			look = away + n * 0.5
		d.g.position = p
		aim_node(d.g, look)
		if d.t > 23.0:
			d.dead = true
			d.g.queue_free()
	DS = DS.filter(func(x): return not x.dead)


# nouveau vaisseau de débarquement pirate, chargé d'une formation
func request_drop(s := -1.0) -> void:
	var g := MeshInstance3D.new()
	g.mesh = FIGHTM["rbig"]
	add_child(g)
	DS.append({"g": g, "t": 0.0, "hp": 4, "dead": false, "drop": false, "s": s if s >= 0.0 else randf_range(0.88, 0.98), "lane": LANES.pick_random(), "kind": mix()})


# vaisseau de débarquement abattu : s'il n'a pas encore débarqué, toute la formation à bord est perdue
func ds_destroyed(d: Dictionary) -> void:
	d.dead = true
	var p: Vector3 = d.g.position
	boom(p, MIDN, 3.0)
	for i in 6:
		ball(p, Color(0.15, 0.15, 0.15, 0.8), randf_range(2.0, 4.0), 3.0, Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), false)
	if not d.drop:
		kills["b"] += int(KIND[d.kind].n)
	ds_down += 1
	d.g.queue_free()


func add_fighter(side: String) -> void:
	var g := MeshInstance3D.new()
	g.mesh = FIGHTM[side]
	add_child(g)
	var R := randf_range(110, 240)
	var f := {"side": side, "g": g, "t": randf_range(0, 6), "R": R, "h": randf_range(55, 130),
		"w": (60.0 / R) * (1.0 if randf() < 0.5 else -1.0), "tilt": randf_range(-0.6, 0.6), "hp": 4, "cool": randf_range(0, 1), "dead": false}
	# la colonie déploie ses chasseurs depuis ses hangars
	if side == "b" and w.HANGARS.size() > 0:
		f.l = 0.0
		f.door = w.HANGARS.pick_random().door
	FT.append(f)


# ================================================================ rendu (instanciation)
func put_inst(e: Dictionary, b: Basis, o: Vector3) -> void:
	var n: int = e.n
	if n >= e.cap:
		return
	var buf: PackedFloat32Array = e.buf
	var k := n * 12
	buf[k] = b.x.x
	buf[k + 1] = b.y.x
	buf[k + 2] = b.z.x
	buf[k + 3] = o.x
	buf[k + 4] = b.x.y
	buf[k + 5] = b.y.y
	buf[k + 6] = b.z.y
	buf[k + 7] = o.y
	buf[k + 8] = b.x.z
	buf[k + 9] = b.y.z
	buf[k + 10] = b.z.z
	buf[k + 11] = o.z
	e.buf = buf
	e.n = n + 1


func render(dt: float) -> void:
	for key in MM:
		MM[key].n = 0
	for F in FORM:
		var shift: Vector3 = F.f_cache * ((F.s - F.s_cache) * RL)
		if F.has("tr"):
			shift = F.f_cache * (float(F.tr.d) - float(F.tr.dc))
		var b: Basis = F.basis
		var pos: PackedVector3Array = F.pos
		if F.kind == "tank":
			var T = F.target
			var fwt: Vector3 = b.x
			for i in F.alive:
				var t: Dictionary = F.tanks[i]
				var tp := tank_pose(pos[i] + shift, fwt)
				# orientation lissée : le char bascule doucement en franchissant une bosse
				if t.has("q"):
					var q: Quaternion = (t.q as Quaternion).slerp(tp.basis.get_rotation_quaternion(), minf(1.0, dt * 8.0))
					t.q = q
				else:
					t.q = tp.basis.get_rotation_quaternion()
				t.h.basis = Basis(t.q as Quaternion)
				t.h.position = tp.origin
				if T != null:
					var l: Vector3 = t.h.to_local(T.p)
					var want := atan2(-l.z, l.x)
					t.tu.rotation.y = lerp_angle(t.tu.rotation.y, want, minf(1.0, dt * 2.0))
				t.rec = maxf(0.0, t.rec - dt)
				t.br.position.x = 1.0 * 2.4 - t.rec * 2.0
			continue
		var ph: PackedFloat32Array = F.ph
		var base: String = F.side + F.kind
		var rate := 3.2 if F.kind == "robot" else 4.6
		var cov: PackedByteArray = F.cover
		var soldier: bool = F.kind != "robot"
		var mbs: Array = F.mb
		var mgs: Array = F.mg
		var mgos: PackedVector3Array = F.mgo
		for i in F.alive:
			var fi := 4
			var hv := hash_f(i * 7 + 3)
			if soldier and F.state == "fight":
				# à couvert : accroupi derrière le rocher ; à découvert : mélange couchés / à genoux
				fi = 8 if (cov[i] == 1 or hv < 0.35) else 5
			elif soldier and F.state == "crawl":
				if F.moving:
					# certains rampent, d'autres avancent à genoux pour se disperser
					fi = 8 if hv < 0.3 else (6 + int(time * 1.6 + ph[i]) % 2)
				else:
					fi = 8 if (cov[i] == 1 or hv < 0.4) else 5
			elif F.moving:
				fi = int(time * rate + ph[i]) % 4
			elif hv < 0.25 and soldier:
				fi = 8
			# couché (pose 8) : à plat sur le sol ; debout, à genoux ou en marche : droit selon la pesanteur
			if fi == 8:
				put_inst(MM[base + str(fi)], mbs[i], pos[i] + shift)
			else:
				put_inst(MM[base + str(fi)], mgs[i], pos[i] + shift + mgos[i])
	# traçantes
	var tb := Basis()
	for t in TR:
		tb = Basis.looking_at(t.v, MIDN if absf(t.v.normalized().dot(MIDN)) < 0.98 else PERP)
		put_inst(MM[t.side + "tracer"], tb, t.p)
	for s in SHELLS:
		tb = Basis.looking_at(s.v, MIDN if absf(s.v.normalized().dot(MIDN)) < 0.98 else PERP)
		put_inst(MM["shell"], tb, s.p)
	for key in MM:
		var e: Dictionary = MM[key]
		if e.n > 0 or e.last > 0:
			e.mm.buffer = e.buf
			e.mm.visible_instance_count = e.n
			e.last = e.n
	# morts
	dead_t -= dt
	if dead_t <= 0:
		dead_t = 0.5
		for key in DEAD:
			var D: Dictionary = DEAD[key]
			if D.dirty:
				D.dirty = false
				var e: Dictionary = D.mm
				e.n = 0
				for tf in D.list:
					put_inst(e, tf.basis, tf.origin)
				e.mm.buffer = e.buf
				e.mm.visible_instance_count = e.n
	# effets
	for f in FX:
		f.l -= dt
		var k: float = 1.0 - f.l / f.L
		match f.k:
			"spr":
				f.o.position += f.v * dt
				f.o.scale = Vector3.ONE * (f.sc * (0.3 + k) if f.grow else f.sc * (1.0 - k * 0.4))
				f.mat.albedo_color = Color(f.c.r, f.c.g, f.c.b, maxf(0.0, (1.0 - k) * f.c.a))
			"ball":
				f.o.position += f.v * dt
				f.o.scale = Vector3.ONE * maxf(0.01, f.sc * (0.3 + k * 0.9))
				var c: Color = f.mat.albedo_color
				c.a = maxf(0.0, f.a0 * (1.0 - k * k))
				f.mat.albedo_color = c
			"puff":
				f.v *= maxf(0.0, 1.0 - dt * 0.9)
				f.o.position += f.v * dt
				f.o.scale = Vector3.ONE * f.sc * (0.35 + 0.65 * sqrt(k))
				var pc: Color = f.mat.albedo_color
				pc.a = f.a0 * pow(1.0 - k, 1.4)
				f.mat.albedo_color = pc
			"deb":
				# gravité réelle de l'astéroïde (microgravité) : les débris rapides partent dans l'espace
				f.v += w.grav_at(f.o.position) * dt
				f.o.position += f.v * dt
				f.o.rotate_x(dt * 6)
				f.o.rotate_y(dt * 4)
			"light":
				f.o.light_energy = f.e * maxf(0.0, 1.0 - k)
			"part":
				if not f.rest:
					f.v += w.grav_at(f.o.position) * dt
					f.o.position += f.v * dt
					f.o.rotate(f.av.normalized(), f.av.length() * dt)
					var a: float = w.alt(f.o.position)
					if a < f.hs and (f.v as Vector3).dot(f.n) < 0.0:
						f.o.position += w.up_at(f.o.position) * (f.hs - a)
						if (f.v as Vector3).length() > 2.5:
							f.v = (f.v - 1.6 * (f.v as Vector3).dot(f.n) * f.n) * 0.4
							f.av *= 0.5
						else:
							f.rest = true
				if f.l < 3.0:
					f.o.scale = Vector3.ONE * maxf(0.01, f.l / 3.0)
		if f.l <= 0:
			if f.k == "part":
				PARTS -= 1
			f.o.queue_free()
	FX = FX.filter(func(x): return x.l > 0)


func stats() -> Dictionary:
	var f := {}
	var m := {}
	var fs := 0.0
	var n := 0
	for F in FORM:
		var k: String = F.side + F.kind
		f[k] = f.get(k, 0) + 1
		m[k] = m.get(k, 0) + F.alive.size()
		fs += F.s
		n += 1
	return {"f": f, "m": m, "wave": wave, "kills": kills, "front": fs / n if n > 0 else 0.5, "ds_down": ds_down, "ds": DS.size()}
