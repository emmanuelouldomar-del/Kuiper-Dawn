extends Node3D
## K-240 — base minière réaliste sur un grand astéroïde (rayon ~20 km, 1 unité = 1 m).
## Jeu K-240 en style minimaliste & géométrique (façon Monument Valley). Touches 1…6 : points de vue · S : changer de filtre · souris : caméra libre · Échap : quitter.
## Structure du fichier :
##   terrain (tuile précalculée terrain/*.bin, 2 échelles + courbure)
##   ciel, soleil, Terre
##   base : moyeu + antenne, tubes, dôme géodésique, habitats, pas de tir + fusées,
##          panneaux solaires, chantier naval, excavatrices + poussière, routes, rochers
##   VUES : liste des 10 points de vue (caméra, soleil, état des fusées)

const TILE := 512.0
const BIG := 5.7
const BIGH := 4.0
const BSC := 0.5
const LOBE_FUSED := false  # le second lobe est une sphère à part (pas de texture étirée)  # échelle des bâtiments de la base
var RC := 2500.0
var TAILLE_K := 10.0
const FRONT_LEN := 340.0
const N := 1024
var HB := PackedFloat32Array()
var mats := {}
var rng := RandomNumberGenerator.new()
var cam: Camera3D
var sun: DirectionalLight3D
var earth_light: DirectionalLight3D
var env: Environment
var earth: MeshInstance3D
var rockets: Array = []
var lamps: Array = []
var blinks: Array = []
var smoke_tex: Texture2D
var time := 0.0
var view := 0
var terr_mats: Array = []
var sv: SubViewport
var post: ShaderMaterial
var style_lbl: Label
var shots_dir := ""
var shot_i := -1
var shot_wait := 0
var target := Vector3.ZERO
var cb := Basis()
var dist := 100.0

# point de vue : caméra, cible, élévation et azimut du soleil (°), direction de la Terre, état des fusées
var VUES := [
	{"nom": "Ligne de front", "mode": 12, "cam": Vector3(-30, 14, 236), "look": Vector3(20, 3, 300), "el": 38.0, "az": 205.0, "earth": Vector2(22, 12), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Vue tactique", "mode": 12, "cam": Vector3(-110, 150, 260), "look": Vector3(20, 0, 345), "el": 45.0, "az": 210.0, "earth": null, "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "La base", "mode": 12, "cam": Vector3(-48, 13, 75), "look": Vector3(5, 3, 5), "el": 30.0, "az": 215.0, "earth": Vector2(-30, 14), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Le dôme", "mode": 12, "cam": Vector3(35, 3, -56), "look": Vector3(25, 4.5, -31), "el": 25.0, "az": 160.0, "earth": Vector2(-20, 13), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Pas de tir", "mode": 12, "cam": Vector3(36, 7, 89), "look": Vector3(16, 23, 56), "el": 22.0, "az": 35.0, "earth": Vector2(-26, 26), "fus": "decollage", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Côté pirates", "mode": 12, "cam": Vector3(70, 16, 520), "look": Vector3(20, 3, 470), "el": 30.0, "az": 20.0, "earth": Vector2(-24, 12), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
]
const BATTLE_A := Vector3(20, 0, 175)
const BATTLE_B := Vector3(20, 0, 515)
var war
var tscale := 1.0
var paused := false
var lbl_stats: Label
var lbl_units: Label
var hud_t := 0.0


# ================================================================ hauteur du terrain (identique au shader)
func hsample(u: float, v: float) -> float:
	u = fposmod(u, 1.0) * N - 0.5
	v = fposmod(v, 1.0) * N - 0.5
	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var fx := u - x0
	var fy := v - y0
	var a := HB[posmod(y0, N) * N + posmod(x0, N)]
	var b := HB[posmod(y0, N) * N + posmod(x0 + 1, N)]
	var c := HB[posmod(y0 + 1, N) * N + posmod(x0, N)]
	var d := HB[posmod(y0 + 1, N) * N + posmod(x0 + 1, N)]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func hdisp(x: float, z: float) -> float:
	var h1 := hsample(x / TILE, z / TILE)
	var h2 := hsample(x / (TILE * BIG) + 0.37, z / (TILE * BIG) + 0.11)
	var m := smoothstep(150.0, 320.0, Vector2(x, z).length())
	var mc := maxf(smoothstep(95.0, 175.0, absf(x - 20.0)), maxf(smoothstep(560.0, 650.0, z), smoothstep(120.0, 60.0, z)))
	# style cartoon : petites bosses très atténuées, grandes ondulations douces
	return (h2 * BIGH * 0.3) * minf(lerpf(0.12, 1.0, m), lerpf(0.22, 1.0, mc))


# l'astéroïde est une sphère de rayon RC : le plan (x, z) est enroulé autour (même calcul que le shader)
# ---- forme irrégulière (patate, allongée, binaire), tirée au hasard ; la zone base + front reste régulière
var SH_TYPE := ""
var SH_ELL := Vector3.ONE
var SH_LOBE_C := Vector3.ZERO
var SH_LOBE_R := 0.0
var SH_BLOBS := PackedVector4Array()
var SH_BW := PackedFloat32Array()
var SH_POLE := 1.0
var SH_TH0 := 0.3


func make_shape(dice: RandomNumberGenerator) -> void:
	var t := dice.randi() % 3
	SH_TYPE = ["patate", "allongé", "binaire"][t]
	if t == 0:
		SH_ELL = Vector3(1.0, dice.randf_range(0.75, 0.95), dice.randf_range(0.8, 1.1))
	elif t == 1:
		SH_ELL = Vector3(dice.randf_range(1.5, 1.9), dice.randf_range(0.7, 0.85), dice.randf_range(0.75, 0.9))
	else:
		SH_ELL = Vector3(1.0, dice.randf_range(0.82, 0.95), dice.randf_range(0.9, 1.0))
		var a := dice.randf() * TAU
		SH_LOBE_C = Vector3(cos(a), dice.randf_range(-0.35, 0.05), sin(a)).normalized() * dice.randf_range(1.25, 1.5)
		SH_LOBE_R = dice.randf_range(0.65, 0.85)
	SH_BLOBS = PackedVector4Array()
	SH_BW = PackedFloat32Array()
	for i in 16:
		var d := Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1)).normalized()
		SH_BLOBS.append(Vector4(d.x, d.y, d.z, dice.randf_range(-0.06, 0.09)))
		SH_BW.append(dice.randf_range(0.04, 0.16))
	SH_POLE = 1.0
	SH_POLE = shape_raw(Vector3.UP)
	SH_TH0 = minf(720.0 / RC, 1.9)


# ---- grand relief (cratères géants, canyons, falaises), tiré au hasard
var GCR := PackedVector4Array()
var GCD := PackedFloat32Array()
var CYN := PackedVector4Array()
var CYC := PackedVector4Array()
var CYD := PackedFloat32Array()
var SCP := PackedVector4Array()
var SCH := PackedFloat32Array()


func rdir(dice: RandomNumberGenerator) -> Vector3:
	return Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1)).normalized()


func make_relief(dice: RandomNumberGenerator) -> void:
	GCR = PackedVector4Array()
	GCD = PackedFloat32Array()
	for i in 10:
		var d := rdir(dice)
		var rm := dice.randf_range(300.0, 900.0)
		var a := minf(rm / RC, 0.6)
		GCR.append(Vector4(d.x, d.y, d.z, a))
		GCD.append(0.0 if i >= 3 else minf(a * RC * dice.randf_range(0.03, 0.05), RC * 0.015))
	CYN = PackedVector4Array()
	CYC = PackedVector4Array()
	CYD = PackedFloat32Array()
	for i in 4:
		var nrm := rdir(dice)
		var c := rdir(dice)
		c = (c - nrm * c.dot(nrm)).normalized()
		var w := minf(dice.randf_range(120.0, 250.0) / RC, 0.3)
		var L := dice.randf_range(0.6, 1.4)
		CYN.append(Vector4(nrm.x, nrm.y, nrm.z, w))
		CYC.append(Vector4(c.x, c.y, c.z, cos(L * 0.5)))
		CYD.append(0.0)
	SCP = PackedVector4Array()
	SCH = PackedFloat32Array()
	for i in 3:
		var u := rdir(dice)
		SCP.append(Vector4(u.x, u.y, u.z, dice.randf_range(-0.2, 0.6)))
		var h := minf(dice.randf_range(70.0, 160.0), RC * 0.04) * (1.0 if dice.randf() < 0.5 else -1.0)
		SCH.append(0.0 * h)


func relief_m(d: Vector3) -> float:
	var off := 0.0
	for i in GCR.size():
		if GCD[i] > 0.0:
			var c: Vector4 = GCR[i]
			var t := acos(clampf(d.x * c.x + d.y * c.y + d.z * c.z, -1.0, 1.0)) / c.w
			if t < 3.0:
				var D: float = GCD[i]
				var bowl := (t * t - 1.0) * D if t < 1.0 else 0.0
				off += bowl + 0.24 * D * exp(-pow((t - 1.0) / 0.2, 2.0))
	for i in CYN.size():
		if CYD[i] > 0.0:
			var nv: Vector4 = CYN[i]
			var cv: Vector4 = CYC[i]
			var n3 := Vector3(nv.x, nv.y, nv.z)
			var c3 := Vector3(cv.x, cv.y, cv.z)
			var sd := asin(clampf(d.dot(n3), -1.0, 1.0))
			var side := n3.cross(c3)
			sd += 0.35 * nv.w * sin(d.dot(side) * 22.0 + float(i) * 1.7)
			var ma := smoothstep(cv.w - 0.04, cv.w + 0.04, d.dot(c3))
			off -= CYD[i] * (1.0 - smoothstep(0.5 * nv.w, nv.w, absf(sd))) * ma
	for i in SCP.size():
		var u: Vector4 = SCP[i]
		off += SCH[i] * smoothstep(-0.006, 0.006, d.x * u.x + d.y * u.y + d.z * u.z - u.w)
	return off


func relief_mask(x: float, z: float) -> float:
	var mb := smoothstep(240.0, 330.0, sqrt(x * x + z * z))
	var mc := maxf(smoothstep(110.0, 180.0, absf(x - 20.0)), maxf(smoothstep(580.0, 660.0, z), smoothstep(110.0, 40.0, z)))
	return mb * mc


func shape_raw(d: Vector3) -> float:
	var e := 1.0 / sqrt(d.x * d.x / (SH_ELL.x * SH_ELL.x) + d.y * d.y / (SH_ELL.y * SH_ELL.y) + d.z * d.z / (SH_ELL.z * SH_ELL.z))
	if SH_LOBE_R > 0.0 and LOBE_FUSED:
		var dc := d.dot(SH_LOBE_C)
		var disc := dc * dc - SH_LOBE_C.length_squared() + SH_LOBE_R * SH_LOBE_R
		if disc > 0.0:
			var tb := dc + sqrt(disc)
			var k := 0.12
			var m := maxf(e, tb)
			e = m + k * log(exp((e - m) / k) + exp((tb - m) / k))
	var b := 0.0
	for i in SH_BLOBS.size():
		var bl: Vector4 = SH_BLOBS[i]
		b += bl.w * exp((d.x * bl.x + d.y * bl.y + d.z * bl.z - 1.0) / SH_BW[i])
	return e * (1.0 + b)


func radius_at(d: Vector3) -> float:
	var th := acos(clampf(d.y, -1.0, 1.0))
	if th <= SH_TH0:
		return RC
	var m := smoothstep(SH_TH0, SH_TH0 + 0.6, th)
	return RC * (1.0 + (shape_raw(d) / SH_POLE - 1.0) * m)


func gp(x: float, z: float, lift := 0.0) -> Vector3:
	var h := hdisp(x, z) + lift
	var r := sqrt(x * x + z * z)
	if r < 0.001:
		return Vector3(0, h, 0)
	var th := minf(r / RC, PI)
	var s := sin(th)
	var dir := Vector3(s * x / r, cos(th), s * z / r)
	var mr := relief_mask(x, z)
	var rel := relief_m(dir) * mr if mr > 0.0 else 0.0
	return dir * (radius_at(dir) + rel + h) - Vector3(0, RC, 0)


# ---- ligne de vue : relief et rochers
func alt(P: Vector3) -> float:
	var v := P + Vector3(0, RC, 0)
	var L := v.length()
	var d := v / L
	var th := acos(clampf(d.y, -1.0, 1.0))
	var sh := sqrt(d.x * d.x + d.z * d.z)
	var q := Vector2.ZERO
	if sh > 1e-6:
		q = Vector2(d.x, d.z) / sh * th * RC
	var mr := relief_mask(q.x, q.y)
	var rel := relief_m(d) * mr if mr > 0.0 else 0.0
	return L - (radius_at(d) + rel + hdisp(q.x, q.y))


func los_hit(a: Vector3, b: Vector3):
	var dv := b - a
	var L := dv.length()
	if L < 3.0:
		return null
	var n := int(ceil(L / 5.0))
	for i in range(1, n):
		var t := float(i) / n
		if t * L < 2.5 or (1.0 - t) * L < 2.0:
			continue
		var p := a + dv * t
		var al := alt(p)
		if al < 0.0:
			return p
		var rk = cover_near(p, 0.0)
		if rk != null and al < float(rk[1]) * 0.65:
			return p
	return null


func height(x: float, z: float) -> float:
	return gp(x, z).y


func up_at(p: Vector3) -> Vector3:
	return (p + Vector3(0, RC, 0)).normalized()


# ================================================================ démarrage
func _ready() -> void:
	# économie de la carte graphique : 60 images/s au maximum
	Engine.max_fps = 60
	# taille de l'astéroïde tirée au hasard à chaque partie : diamètre = 10 à 30 fois le champ de bataille
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	TAILLE_K = dice.randf_range(1.2, 3.0)
	RC = TAILLE_K * FRONT_LEN * 0.5
	make_shape(dice)
	make_relief(dice)
	# vue stratégique : l'astéroïde entier avec la bataille sur sa courbure
	var qm := Vector2(20, 345)
	var thm := qm.length() / RC
	var upm := Vector3(sin(thm) * qm.x / qm.length(), cos(thm), sin(thm) * qm.y / qm.length())
	var ctr := Vector3(0, -RC, 0)
	var tow := (Vector3.UP - upm * Vector3.UP.dot(upm)).normalized()
	var ext := 1.0
	for k in 300:
		ext = maxf(ext, shape_raw(rdir(dice)) / SH_POLE)
	if SH_LOBE_R > 0.0:
		ext = maxf(ext, (SH_LOBE_C.length() + SH_LOBE_R) / SH_POLE)
	VUES.insert(0, {"nom": "Vue stratégique", "mode": 12, "abs": true, "cam": ctr + (upm * 3.0 + tow * 1.2 + Vector3(0.4, 0, 0)).normalized() * RC * (1.0 + 1.75 * ext), "look": ctr + upm * RC * 0.3, "el": 40.0, "az": 200.0, "earth": null, "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)})
	VUES.append({"nom": "L'astéroïde entier", "mode": 12, "abs": true, "cam": Vector3(-RC * 1.6, RC * 1.6, RC * 2.6), "look": Vector3(0, -RC, 0), "el": 30.0, "az": 210.0, "earth": null, "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)})
	rng.seed = 7
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shots" and i + 1 < args.size():
			shots_dir = args[i + 1]
	var f := FileAccess.open("res://terrain/height.bin", FileAccess.READ)
	HB = f.get_buffer(f.get_length()).to_float32_array()
	var fa := FileAccess.open("res://terrain/albedo.bin", FileAccess.READ)
	var AB := fa.get_buffer(fa.get_length())
	cam = Camera3D.new()
	cam.fov = 50
	cam.near = 0.1
	cam.far = 40000
	build_pipeline()
	smoke_tex = make_smoke()
	build_sky()
	build_terrain(HB.to_byte_array(), AB)
	build_base()
	war = preload("res://battle.gd").new()
	add_child(war)
	war.setup(self)
	build_hud()
	apply_view(0)
	if shots_dir != "":
		shot_i = 0
		shot_wait = 6
		apply_view(0)


# ================================================================ matériaux
func M(name: String) -> Material:
	if mats.has(name):
		return mats[name]
	var m := StandardMaterial3D.new()
	match name:
		"acier":
			m.albedo_color = Color("b9bdc3"); m.metallic = 0.9; m.roughness = 0.32
		"acier_sombre":
			m.albedo_color = Color("5d6168"); m.metallic = 0.85; m.roughness = 0.45
		"blanc":
			m.albedo_color = Color("d8dadc"); m.metallic = 0.1; m.roughness = 0.55
		"gris":
			m.albedo_color = Color("7c7f84"); m.metallic = 0.3; m.roughness = 0.7
		"beton":
			m.albedo_color = Color("6e6c69"); m.roughness = 0.95
		"noir":
			m.albedo_color = Color("1a1b1e"); m.metallic = 0.5; m.roughness = 0.6
		"or":
			m.albedo_color = Color("d9a640"); m.metallic = 1.0; m.roughness = 0.25
		"orange":
			m.albedo_color = Color("c8832a"); m.metallic = 0.4; m.roughness = 0.55
		"rouille":
			m.albedo_color = Color("8a5a32"); m.metallic = 0.5; m.roughness = 0.7
		"solaire":
			m.albedo_color = Color("141c3a"); m.metallic = 0.7; m.roughness = 0.15
		"verre":
			m.albedo_color = Color(0.7, 0.85, 0.95, 0.12); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.6; m.roughness = 0.05; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"vitre":
			m.albedo_color = Color("0a0c10"); m.emission_enabled = true; m.emission = Color("9fd8ff"); m.emission_energy_multiplier = 2.5
		"chaud":
			m.albedo_color = Color("100a04"); m.emission_enabled = true; m.emission = Color("ffb35a"); m.emission_energy_multiplier = 4.0
		"bleu":
			m.albedo_color = Color("04080f"); m.emission_enabled = true; m.emission = Color("4fb8ff"); m.emission_energy_multiplier = 5.0
		"rouge":
			m.albedo_color = Color("100000"); m.emission_enabled = true; m.emission = Color("ff2a1a"); m.emission_energy_multiplier = 8.0
		"anneau":
			m.albedo_color = Color("120c04"); m.emission_enabled = true; m.emission = Color("ffd08a"); m.emission_energy_multiplier = 6.0
	mats[name] = m
	return m


func make_smoke() -> Texture2D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.frequency = 0.06
	nz.fractal_octaves = 4
	for y in 128:
		for x in 128:
			var r := Vector2(x - 63.5, y - 63.5).length() / 64.0
			var n := nz.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - r) * 1.6 - (1.0 - n) * 0.7, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


# ================================================================ primitives
func mi(par: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	par.add_child(m)
	return m


func box(par: Node3D, mat: String, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mi(par, b, M(mat), pos, rot)


func cyl(par: Node3D, mat: String, pos: Vector3, r: float, h: float, r2 := -1.0, rot := Vector3.ZERO, seg := 24) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0 else r2
	c.height = h
	c.radial_segments = seg
	return mi(par, c, M(mat), pos, rot)


func sph(par: Node3D, mat: String, pos: Vector3, r: float, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = 32
	s.rings = 16
	return mi(par, s, M(mat), pos)


func strut(par: Node3D, mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = L
	c.radial_segments = 8
	var m := mi(par, c, M(mat), (a + b) * 0.5)
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	m.basis = Basis(x, y, x.cross(y) * -1.0).orthonormalized()


func tube_x(par: Node3D, mat: String, a: Vector3, L: float, r: float) -> MeshInstance3D:
	return cyl(par, mat, a + Vector3(L * 0.5, 0, 0), r, L, -1.0, Vector3(0, 0, PI / 2), 32)


func tube_z(par: Node3D, mat: String, a: Vector3, L: float, r: float) -> MeshInstance3D:
	return cyl(par, mat, a + Vector3(0, 0, L * 0.5), r, L, -1.0, Vector3(PI / 2, 0, 0), 32)


func lamp(par: Node3D, pos: Vector3, col: Color, energy := 4.0, rng_m := 25.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.6
	l.position = pos
	l.set_meta("e0", energy)
	par.add_child(l)
	lamps.append(l)


func beacon(par: Node3D, pos: Vector3) -> void:
	var b := sph(par, "rouge", pos, 0.35)
	blinks.append(b)


func dust(par: Node3D, pos: Vector3, size: float, alpha := 0.45, col := Color(0.62, 0.6, 0.57)) -> void:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	m.mesh = q
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = smoke_tex
	mt.albedo_color = Color(col.r, col.g, col.b, alpha)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mt.disable_receive_shadows = true
	mt.roughness = 1.0
	m.material_override = mt
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	par.add_child(m)


# ================================================================ ciel, soleil, Terre
func build_sky() -> void:
	var W := 4096
	var H := 2048
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.004, 0.006))
	img.fill_rect(Rect2i(0, H / 2 + 200, W, H / 2 - 200), Color(0.03, 0.03, 0.03))
	for i in 7000:
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(0, H / 2 - 4)
		var b := rng.randf()
		img.set_pixel(x, y, Color(0.8, 0.85, 1.0) * (0.1 + b * b * b * 0.9))
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = ImageTexture.create_from_image(img)
	var sky := Sky.new()
	sky.sky_material = pano
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.06
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = false
	env.ssao_radius = 1.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 3.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_split_1 = 0.04
	sun.directional_shadow_split_2 = 0.12
	sun.directional_shadow_split_3 = 0.35
	sun.shadow_bias = 0.3
	sun.shadow_normal_bias = 2.5
	add_child(sun)
	earth_light = DirectionalLight3D.new()
	earth_light.light_color = Color(0.55, 0.7, 1.0)
	earth_light.light_energy = 0.0
	add_child(earth_light)
	earth = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1400
	sm.height = 2800
	sm.radial_segments = 96
	sm.rings = 48
	earth.mesh = sm
	var em := ShaderMaterial.new()
	em.shader = load("res://shaders/planet.gdshader")
	earth.material_override = em
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)


# ================================================================ terrain
func build_terrain(hb: PackedByteArray, ab: PackedByteArray) -> void:
	var himg := Image.create_from_data(N, N, false, Image.FORMAT_RF, hb)
	var aimg := Image.create_from_data(N, N, false, Image.FORMAT_RF, ab)
	var ht := ImageTexture.create_from_image(himg)
	var at := ImageTexture.create_from_image(aimg)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	fn.fractal_octaves = 5
	var dn := NoiseTexture2D.new()
	dn.seamless = true
	dn.as_normal_map = true
	dn.bump_strength = 10.0
	dn.width = 512
	dn.height = 512
	dn.noise = fn
	var fn2 := FastNoiseLite.new()
	fn2.frequency = 0.02
	fn2.fractal_octaves = 3
	var da := NoiseTexture2D.new()
	da.seamless = true
	da.width = 256
	da.height = 256
	da.noise = fn2
	var sh := load("res://shaders/terrain.gdshader")
	# un seul maillage qui enveloppe tout l'astéroïde : plus de raccord entre deux plans
	for k in 1:
		var pm := PlaneMesh.new()
		var tsz := TAU * RC * 1.02
		var nsub := clampi(int(tsz / 3.5), 400, 800)
		pm.size = Vector2(tsz, tsz)
		pm.subdivide_width = nsub
		pm.subdivide_depth = nsub
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("hmap", ht)
		m.set_shader_parameter("amap", at)
		m.set_shader_parameter("detail_n", dn)
		m.set_shader_parameter("detail_a", da)
		m.set_shader_parameter("outer", k == 1)
		m.set_shader_parameter("vlod", 0.0 if k == 0 else 3.0)
		m.set_shader_parameter("Rc", RC)
		m.set_shader_parameter("ell", SH_ELL)
		m.set_shader_parameter("lobe_c", SH_LOBE_C)
		m.set_shader_parameter("lobe_r", SH_LOBE_R if LOBE_FUSED else 0.0)
		m.set_shader_parameter("blobs", SH_BLOBS)
		m.set_shader_parameter("bwid", SH_BW)
		m.set_shader_parameter("pole", SH_POLE)
		m.set_shader_parameter("th0", SH_TH0)
		m.set_shader_parameter("gcr", GCR)
		m.set_shader_parameter("gcd", GCD)
		m.set_shader_parameter("cyn", CYN)
		m.set_shader_parameter("cyc", CYC)
		m.set_shader_parameter("cyd", CYD)
		m.set_shader_parameter("scp", SCP)
		m.set_shader_parameter("sch", SCH)
		m.set_shader_parameter("sink", 0.0 if k == 0 else 0.4)
		var t := MeshInstance3D.new()
		t.mesh = pm
		t.material_override = m
		terr_mats.append(m)
		t.extra_cull_margin = RC * 2.5
		# le sol ne projette pas d'ombre sur lui-même (évite les rayures)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)
	# second lobe de l'astéroïde binaire : sphère séparée posée contre le corps principal
	if SH_LOBE_R > 0.0 and not LOBE_FUSED:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 128
		sm.rings = 64
		var lm := ShaderMaterial.new()
		lm.shader = load("res://shaders/lobe.gdshader")
		lm.set_shader_parameter("amap", at)
		terr_mats.append(lm)
		var lo := MeshInstance3D.new()
		lo.mesh = sm
		lo.material_override = lm
		lo.position = lobe_center()
		lo.scale = Vector3.ONE * lobe_radius()
		lo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lo)


func lobe_center() -> Vector3:
	return Vector3(0, -RC, 0) + SH_LOBE_C * RC / SH_POLE


func lobe_radius() -> float:
	return SH_LOBE_R * RC / SH_POLE


# ================================================================ la base
func build_base() -> void:
	var B := Node3D.new()
	add_child(B)
	hub_and_dish(B)
	pipes(B)
	geodome(B, Vector3(52, 0, -62), 17.0)
	habitats(B)
	pads(B)
	solar(B, Vector3(115, 0, -30), 6, 9)
	solar(B, Vector3(-125, 0, 35), 5, 8)
	shipyard(B)
	for e in [[0.0, 52.0, 2.6], [22.0, 60.0, 3.4], [38.0, 48.0, 2.2], [-12.0, 66.0, 3.0]]:
		excavator(B, Vector3(e[0], 0, e[1]), e[2])
	roads(B)
	convoy(B)
	rocks(B)
	# chaque bâtiment est redressé selon la verticale locale de la sphère
	for c in B.get_children():
		if c.get_class() == "Node3D" and (c as Node3D).position.length() > 3.0:
			var n3: Node3D = c
			n3.basis = Basis(Quaternion(Vector3.UP, up_at(n3.position))) * n3.basis
	# bâtiments réduits de moitié (la base entière est ramenée vers son centre)
	for c in B.get_children():
		if c is Node3D and not (c is MultiMeshInstance3D):
			var n4: Node3D = c
			var P := n4.position
			var q := planar(P)
			var np := gp(q.x * BSC, q.y * BSC, alt(P) * BSC)
			n4.basis = Basis(Quaternion(up_at(P), up_at(np))) * n4.basis.scaled(Vector3.ONE * BSC)
			n4.position = np
	for r in rockets:
		r.base = (r.g as Node3D).position
	peaks()


# position à plat (x, z) d'un point de la sphère
func planar(P: Vector3) -> Vector2:
	var v := P + Vector3(0, RC, 0)
	var d := v.normalized()
	var th := acos(clampf(d.y, -1.0, 1.0))
	var sh := sqrt(d.x * d.x + d.z * d.z)
	if sh < 1e-6:
		return Vector2.ZERO
	return Vector2(d.x, d.z) / sh * th * RC


# massifs rocheux mauves en pics, style dessin animé, hors base et hors front
func peaks() -> void:
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	# massifs en dalles inclinées, facettes peintes orange / rose / violet (style illustré)
	var pk := slab_mesh(dice)
	var xf: Array[Transform3D] = []
	var pr: Array[float] = []
	var pg: Array[Vector3] = []
	var nclu := clampi(int(4.0 * PI * RC * RC / 25000.0), 10, 30)
	var tries := 0
	while xf.size() < nclu * 5 and tries < 4000:
		tries += 1
		var a := dice.randf() * TAU
		var rr := sqrt(dice.randf()) * PI * RC * 0.88
		var c := Vector2(cos(a), sin(a)) * rr
		if relief_mask(c.x, c.y) < 0.6:
			continue
		var n := dice.randi_range(3, 7)
		var yaw0 := dice.randf() * TAU
		var hmax := dice.randf_range(22.0, 50.0) * clampf(RC / 300.0, 0.6, 1.3)
		for k in n:
			var o := Vector2(dice.randf_range(-1, 1), dice.randf_range(-1, 1)) * hmax * 1.3
			var q := c + o
			if relief_mask(q.x, q.y) < 0.5:
				continue
			var h := hmax * dice.randf_range(0.45, 1.0)
			var p := gp(q.x, q.y, h * 0.5 - 1.5)
			if SH_LOBE_R > 0.0 and p.distance_to(lobe_center()) < lobe_radius() + 2.0:
				continue
			# pics sans chevauchement entre eux ni avec les rochers
			var rb := h * 0.4
			var g0 := gp(q.x, q.y)
			var hit := false
			for k2 in xf.size():
				if pg[k2].distance_to(g0) < rb + pr[k2]:
					hit = true
					break
			if hit or cover_near(g0, rb) != null:
				continue
			pr.append(rb)
			pg.append(g0)
			var b := Basis(Quaternion(Vector3.UP, up_at(p))) * Basis(Vector3.UP, yaw0 + dice.randf_range(-0.5, 0.5)) * Basis(Vector3(0, 0, 1), -dice.randf_range(0.1, 0.4))
			xf.append(Transform3D(b * Basis.from_scale(Vector3(h * dice.randf_range(0.3, 0.45), h, h * dice.randf_range(0.22, 0.32))), p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pk
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	tufts(dice)


func slab_mesh(dice: RandomNumberGenerator) -> ArrayMesh:
	var N := 6
	var bp: Array[Vector3] = []
	var tp: Array[Vector3] = []
	for i in N:
		var an := TAU * i / N + dice.randf_range(-0.25, 0.25)
		var r := dice.randf_range(0.75, 1.0)
		var x := cos(an) * r
		var z := sin(an) * r * 0.65
		bp.append(Vector3(x, -0.5, z))
		# sommet tronqué en biais
		tp.append(Vector3(x * 0.7 + 0.12, 0.5 - 0.4 * (x * 0.5 + 0.5) + dice.randf_range(-0.05, 0.05), z * 0.7))
	var L := Vector3(1.0, 0.7, 0.4).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tc := Vector3.ZERO
	for t in tp:
		tc += t
	tc /= N
	for i in N:
		var j := (i + 1) % N
		var nf := (bp[j] - bp[i]).cross(tp[i] - bp[i]).normalized()
		var mid := (bp[i] + bp[j]) * 0.5
		if nf.dot(Vector3(mid.x, 0, mid.z)) < 0:
			nf = -nf
		var d := nf.dot(L)
		var col := Color(0.62, 0.3, 0.2) if d > 0.2 else (Color(0.42, 0.2, 0.32) if d > -0.35 else Color(0.24, 0.11, 0.24))
		for v in [bp[i], bp[j], tp[j], bp[i], tp[j], tp[i]]:
			st.set_color(col)
			st.set_normal(nf)
			st.add_vertex(v)
	for i in N:
		var j := (i + 1) % N
		var nt := (tp[i] - tc).cross(tp[j] - tc).normalized()
		if nt.y < 0:
			nt = -nt
		for v in [tc, tp[i], tp[j]]:
			st.set_color(Color(0.72, 0.42, 0.28))
			st.set_normal(nt)
			st.add_vertex(v)
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 1.0
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mt)
	return m


# touffes de cristaux bleu-vert (façon agaves), hors base et hors chemins
func tufts(dice: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var an := TAU * i / 9.0 + dice.randf_range(-0.2, 0.2)
		var lean := dice.randf_range(0.35, 0.9)
		var ln := dice.randf_range(0.7, 1.0)
		var tip := Vector3(cos(an) * sin(lean), cos(lean), sin(an) * sin(lean)) * ln
		var a := Vector3(-sin(an), 0, cos(an)) * 0.07
		var b := -a
		var c := Vector3(cos(an), 0, sin(an)) * 0.07
		for f in [[a, b, tip], [b, c, tip], [c, a, tip]]:
			var nn: Vector3 = ((f[1] - f[0]) as Vector3).cross(f[2] - f[0]).normalized()
			for v in f:
				st.set_normal(nn)
				st.add_vertex(v)
	var tm := st.commit()
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.05, 0.24, 0.3)
	mt.roughness = 0.9
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.surface_set_material(0, mt)
	var xf: Array[Transform3D] = []
	var want := clampi(int(4.0 * PI * RC * RC / 900.0), 300, 1500)
	var tries := 0
	while xf.size() < want and tries < want * 6:
		tries += 1
		var a := dice.randf() * TAU
		var rr := sqrt(dice.randf()) * PI * RC * 0.9
		var q := Vector2(cos(a), sin(a)) * rr
		if relief_mask(q.x, q.y) < 0.15 or rr < 140.0:
			continue
		var g := gp(q.x, q.y)
		if cover_near(g, 1.5) != null:
			continue
		if SH_LOBE_R > 0.0 and g.distance_to(lobe_center()) < lobe_radius():
			continue
		var sc := dice.randf_range(0.6, 1.4)
		var b := Basis(Quaternion(Vector3.UP, up_at(g))) * Basis(Vector3.UP, dice.randf() * TAU)
		xf.append(Transform3D(b.scaled_local(Vector3.ONE * sc), g))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func hub_and_dish(B: Node3D) -> void:
	var g := Node3D.new()
	g.position = gp(0, 0, -0.3)
	B.add_child(g)
	cyl(g, "acier", Vector3(0, 3.5, 0), 7.0, 7.0, 7.4, Vector3.ZERO, 48)
	cyl(g, "acier_sombre", Vector3(0, 7.2, 0), 7.2, 0.5)
	for i in 12:
		var a := TAU * i / 12.0
		box(g, "vitre", Vector3(cos(a) * 7.05, 4.5, sin(a) * 7.05), Vector3(0.2, 0.5, 1.6), Vector3(0, -a, 0))
	box(g, "bleu", Vector3(7.2, 2.0, 0), Vector3(0.2, 0.5, 4.0))
	# pylône en treillis
	var base_y := 7.4
	var top_y := 24.0
	var legs := []
	for i in 4:
		var a := PI / 4 + TAU * i / 4.0
		legs.append([Vector3(cos(a) * 4.5, base_y, sin(a) * 4.5), Vector3(cos(a) * 1.4, top_y, sin(a) * 1.4)])
	for l in legs:
		strut(g, "acier", l[0], l[1], 0.25)
	for s in 6:
		var t0 := s / 6.0
		var t1 := (s + 1) / 6.0
		for i in 4:
			var a: Array = legs[i]
			var b: Array = legs[(i + 1) % 4]
			strut(g, "acier_sombre", a[0].lerp(a[1], t0), b[0].lerp(b[1], t1), 0.09)
			strut(g, "acier_sombre", a[0].lerp(a[1], t1), b[0].lerp(b[1], t0), 0.09)
			strut(g, "acier_sombre", a[0].lerp(a[1], t1), b[0].lerp(b[1], t1), 0.08)
	cyl(g, "acier_sombre", Vector3(0, top_y + 0.5, 0), 2.0, 1.0)
	# parabole
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := 11.0
	var D := 3.2
	var NS := 48
	var NR := 10
	for j in NR:
		for i in NS:
			var r0 := R * j / NR
			var r1 := R * (j + 1) / NR
			var a0 := TAU * i / NS
			var a1 := TAU * (i + 1) / NS
			var p := func(r: float, a: float) -> Vector3: return Vector3(cos(a) * r, D * (r / R) * (r / R), sin(a) * r)
			for v in [p.call(r0, a0), p.call(r1, a0), p.call(r1, a1), p.call(r0, a0), p.call(r1, a1), p.call(r0, a1)]:
				st.add_vertex(v)
	st.generate_normals()
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("c9ccd0")
	dm.metallic = 0.6
	dm.roughness = 0.35
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dish := MeshInstance3D.new()
	dish.mesh = st.commit()
	dish.material_override = dm
	dish.position = Vector3(0, top_y + 1.0, 0)
	dish.rotation = Vector3(0.25, 0.6, 0)
	g.add_child(dish)
	for i in 3:
		var a := TAU * i / 3.0
		strut(dish, "acier_sombre", Vector3(cos(a) * R * 0.95, D * 0.9, sin(a) * R * 0.95), Vector3(0, 7.5, 0), 0.08)
	cyl(dish, "acier", Vector3(0, 4.5, 0), 0.25, 9.0)
	beacon(dish, Vector3(0, 9.2, 0))
	lamp(g, Vector3(9, 3, 0), Color("9fd8ff"), 3.0, 20)


func pipe_run(B: Node3D, a: Vector3, b: Vector3) -> void:
	# tube horizontal de a vers b (x ou z), posé sur pieds, avec bagues et modules
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var L := a.distance_to(b)
	var dir := (b - a).normalized()
	var r := 2.4
	var g := Node3D.new()
	B.add_child(g)
	var steps := int(L / 2.0)
	for i in steps:
		var p := a + dir * (i * 2.0 + 1.0)
		var y := height(p.x, p.z) + 3.4
		var seg_pos := Vector3(p.x, y, p.z)
		if along_x:
			cyl(g, "acier", seg_pos, r, 2.02, -1.0, Vector3(0, 0, PI / 2), 32)
		else:
			cyl(g, "acier", seg_pos, r, 2.02, -1.0, Vector3(PI / 2, 0, 0), 32)
		if i % 6 == 0:
			var rot := Vector3(0, 0, PI / 2) if along_x else Vector3(PI / 2, 0, 0)
			cyl(g, "acier_sombre", seg_pos, r + 0.35, 0.7, -1.0, rot, 32)
			var gy := height(p.x, p.z)
			for s in [-1.0, 1.0]:
				var side := Vector3(0, 0, s * 1.6) if along_x else Vector3(s * 1.6, 0, 0)
				strut(g, "acier_sombre", Vector3(p.x, gy, p.z) + side * 1.3, seg_pos + side * 0.6 - Vector3(0, 1.4, 0), 0.18)
			box(g, "bleu", seg_pos + (Vector3(0, 0, r + 0.37) if along_x else Vector3(r + 0.37, 0, 0)), Vector3(0.3, 0.25, 0.3))
		if i % 15 == 8:
			var rot2 := Vector3(0, 0, PI / 2) if along_x else Vector3(PI / 2, 0, 0)
			cyl(g, "blanc", seg_pos, r + 1.0, 7.0, -1.0, rot2, 32)
			for w in 5:
				var off := (Vector3(-2.4 + w * 1.2, 0.8, r + 1.02) if along_x else Vector3(r + 1.02, 0.8, -2.4 + w * 1.2))
				box(g, "vitre", seg_pos + off, Vector3(0.6, 0.35, 0.05) if along_x else Vector3(0.05, 0.35, 0.6))
			box(g, "or", seg_pos + Vector3(0, r + 1.05, 0), Vector3(3, 0.15, 2) if along_x else Vector3(2, 0.15, 3))
			lamp(g, seg_pos + (Vector3(0, -1, 5) if along_x else Vector3(5, -1, 0)), Color("ffcf8a"), 2.0, 14)
	# passerelle
	var mid := (a + b) * 0.5
	for s in [-1.0, 1.0]:
		var o := Vector3(0, 0, s * 3.4) if along_x else Vector3(s * 3.4, 0, 0)
		var p0 := a + o
		var p1 := b + o
		var segs := int(L / 6.0)
		for i in segs:
			var q0 := p0.lerp(p1, float(i) / segs)
			var q1 := p0.lerp(p1, float(i + 1) / segs)
			strut(g, "gris", Vector3(q0.x, height(q0.x, q0.z) + 1.2, q0.z), Vector3(q1.x, height(q1.x, q1.z) + 1.2, q1.z), 0.06)


func pipes(B: Node3D) -> void:
	pipe_run(B, Vector3(9, 0, 0), Vector3(95, 0, 0))
	pipe_run(B, Vector3(-9, 0, 0), Vector3(-90, 0, 0))
	pipe_run(B, Vector3(0, 0, -9), Vector3(0, 0, -95))
	pipe_run(B, Vector3(0, 0, 9), Vector3(0, 0, 40))
	for p in [Vector3(97, 0, 0), Vector3(-92, 0, 0), Vector3(0, 0, -97)]:
		var g := Node3D.new()
		g.position = gp(p.x, p.z, -0.3)
		B.add_child(g)
		cyl(g, "acier", Vector3(0, 3.4, 0), 4.4, 6.8, 4.7, Vector3.ZERO, 40)
		cyl(g, "or", Vector3(0, 6.9, 0), 4.0, 0.3)
		for i in 8:
			var a := TAU * i / 8.0
			box(g, "vitre", Vector3(cos(a) * 4.45, 4.6, sin(a) * 4.45), Vector3(0.2, 0.4, 1.2), Vector3(0, -a, 0))
		cyl(g, "acier_sombre", Vector3(2.5, 9.0, 0), 0.12, 5.0)
		beacon(g, Vector3(2.5, 11.6, 0))


func geodome(B: Node3D, c: Vector3, R: float) -> void:
	var g := Node3D.new()
	g.position = gp(c.x, c.z, -0.4)
	B.add_child(g)
	cyl(g, "beton", Vector3(0, 0.5, 0), R + 1.2, 1.4, R + 1.6, Vector3.ZERO, 64)
	# icosphère fréquence 3 (demi-sphère)
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var fs := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var edges := {}
	var tris: Array = []
	var nf := 3
	for f in fs:
		var a: Vector3 = vs[f[0]].normalized()
		var b: Vector3 = vs[f[1]].normalized()
		var cc: Vector3 = vs[f[2]].normalized()
		for i in nf:
			for j in nf - i:
				var p0 := (a * (nf - i - j) + b * i + cc * j) / nf
				var p1 := (a * (nf - i - j - 1) + b * (i + 1) + cc * j) / nf
				var p2 := (a * (nf - i - j - 1) + b * i + cc * (j + 1)) / nf
				tris.append([p0.normalized(), p1.normalized(), p2.normalized()])
				if j < nf - i - 1:
					var p3 := (a * (nf - i - j - 2) + b * (i + 1) + cc * (j + 1)) / nf
					tris.append([p1.normalized(), p3.normalized(), p2.normalized()])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tr in tris:
		var cen: Vector3 = (tr[0] + tr[1] + tr[2]) / 3.0
		if cen.y < -0.02:
			continue
		for v in tr:
			st.set_normal(v)
			st.add_vertex(v * R)
		for k in 3:
			var p: Vector3 = tr[k]
			var q: Vector3 = tr[(k + 1) % 3]
			var key := str(snappedf(p.x + q.x, 0.001)) + "_" + str(snappedf(p.y + q.y, 0.001)) + "_" + str(snappedf(p.z + q.z, 0.001))
			if not edges.has(key) and p.y > -0.05 and q.y > -0.05:
				edges[key] = [p * R, q * R]
	var glass := MeshInstance3D.new()
	glass.mesh = st.commit()
	glass.material_override = M("verre")
	glass.position.y = 1.2
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(glass)
	var frame := Node3D.new()
	frame.position.y = 1.2
	g.add_child(frame)
	for k in edges:
		strut(frame, "acier", edges[k][0], edges[k][1], 0.12)
	# intérieur : serres et bâtiments éclairés
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, R * 0.7)
		var h := rng.randf_range(1.0, 3.5)
		box(g, "blanc" if i % 3 else "gris", Vector3(cos(a) * r, 1.4 + h * 0.5, sin(a) * r), Vector3(rng.randf_range(2, 4), h, rng.randf_range(2, 4)), Vector3(0, a, 0))
		box(g, "chaud", Vector3(cos(a) * r, 1.4 + h * 0.6, sin(a) * r), Vector3(rng.randf_range(2.1, 4.1), 0.3, 0.3), Vector3(0, a, 0))
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, R * 0.75)
		cyl(g, "chaud", Vector3(cos(a) * r, 1.5, sin(a) * r), 0.15, 0.2)
		sph(g, "gris", Vector3(cos(a) * r, 2.6, sin(a) * r), 0.9)
	lamp(g, Vector3(0, 5, 0), Color("ffc27a"), 6.0, R * 1.6)
	lamp(g, Vector3(R * 0.5, 3, R * 0.3), Color("ffd9a0"), 3.0, R)


func habitats(B: Node3D) -> void:
	var spots := [Vector3(-75, 0, -55), Vector3(-95, 0, -78), Vector3(-60, 0, -88), Vector3(-112, 0, -50), Vector3(-82, 0, -105), Vector3(-120, 0, -88)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var g := Node3D.new()
		g.position = gp(p.x, p.z, -0.3)
		B.add_child(g)
		var R := rng.randf_range(5.0, 8.0)
		cyl(g, "beton", Vector3(0, 0.4, 0), R + 0.8, 1.0, R + 1.0, Vector3.ZERO, 40)
		sph(g, "blanc", Vector3(0, 0.8, 0), R, true)
		cyl(g, "chaud", Vector3(0, 1.4, 0), R + 0.02, 0.35, -1.0, Vector3.ZERO, 40)
		cyl(g, "or", Vector3(0, 0.8 + R * 0.98, 0), 1.2, 0.5)
		if i > 0:
			var q: Vector3 = spots[i - 1]
			var a3 := gp(p.x, p.z, 1.6)
			var b3 := gp(q.x, q.z, 1.6)
			strut(B, "acier", a3, b3, 1.1)
		lamp(g, Vector3(R + 2, 2, 0), Color("ffb35a"), 2.0, 14)
	strut(B, "acier", gp(-75, -55, 1.6), gp(-9, -2, 2.0), 1.1)


func rocket(par: Node3D, pos: Vector3) -> Dictionary:
	var g := Node3D.new()
	g.position = pos
	par.add_child(g)
	var body := Node3D.new()
	g.add_child(body)
	cyl(body, "acier", Vector3(0, 15, 0), 2.3, 26, -1.0, Vector3.ZERO, 40)
	cyl(body, "acier", Vector3(0, 31.5, 0), 0.25, 7, 2.3, Vector3.ZERO, 40)
	for y in [6.0, 18.0, 27.0]:
		cyl(body, "acier_sombre", Vector3(0, y, 0), 2.35, 0.3, -1.0, Vector3.ZERO, 40)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4
		box(body, "acier_sombre", Vector3(cos(a) * 2.6, 3.4, sin(a) * 2.6), Vector3(0.3, 5.0, 2.2), Vector3(0, -a, 0))
		strut(body, "acier_sombre", Vector3(cos(a) * 2.0, 4.0, sin(a) * 2.0), Vector3(cos(a) * 4.5, 0.2, sin(a) * 4.5), 0.18)
		box(body, "acier", Vector3(cos(a) * 2.5, 28.0, sin(a) * 2.5), Vector3(0.2, 2.6, 1.4), Vector3(0, -a, 0))
	for k in 6:
		box(body, "vitre", Vector3(2.32, 24.0 - k * 0.0, 0).rotated(Vector3.UP, k * 0.3 - 0.8), Vector3(0.05, 0.45, 0.45))
	cyl(body, "noir", Vector3(0, 1.4, 0), 1.0, 1.4, 1.5)
	var pl := Node3D.new()
	g.add_child(pl)
	var plm := ShaderMaterial.new()
	plm.shader = load("res://shaders/plume.gdshader")
	var outer := cyl(pl, "acier", Vector3(0, -9.0, 0), 1.3, 20.0, 4.5, Vector3.ZERO, 32)
	outer.material_override = plm
	var cm := ShaderMaterial.new()
	cm.shader = plm.shader
	cm.set_shader_parameter("col", Color(1.0, 0.95, 0.85))
	cm.set_shader_parameter("power", 12.0)
	var core := cyl(pl, "acier", Vector3(0, -5.0, 0), 0.8, 11.0, 1.6, Vector3.ZERO, 24)
	core.material_override = cm
	for m in [outer, core]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fl := OmniLight3D.new()
	fl.light_color = Color("ffd8a0")
	fl.light_energy = 14.0
	fl.omni_range = 70.0
	fl.shadow_enabled = false
	fl.position = Vector3(0, -2, 0)
	pl.add_child(fl)
	var smoke := Node3D.new()
	g.add_child(smoke)
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4, 16)
		dust(smoke, Vector3(cos(a) * r, rng.randf_range(1, 6), sin(a) * r), rng.randf_range(9, 18), 0.35)
	return {"g": g, "body": body, "plume": pl, "smoke": smoke, "base": pos}


func pads(B: Node3D) -> void:
	var spots := [Vector3(-40, 0, 95), Vector3(32, 0, 112), Vector3(100, 0, 85)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var g := Node3D.new()
		g.position = gp(p.x, p.z, -0.6)
		B.add_child(g)
		cyl(g, "beton", Vector3(0, 0.6, 0), 15, 1.4, 16, Vector3.ZERO, 64)
		cyl(g, "gris", Vector3(0, 1.32, 0), 12.5, 0.1, -1.0, Vector3.ZERO, 64)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 12.6
		tm.outer_radius = 13.2
		tm.rings = 64
		ring.mesh = tm
		ring.material_override = M("anneau")
		ring.position.y = 1.35
		ring.scale = Vector3(1, 0.3, 1)
		g.add_child(ring)
		for k in 16:
			var a := TAU * k / 16.0
			box(g, "anneau", Vector3(cos(a) * 15.2, 1.3, sin(a) * 15.2), Vector3(0.5, 0.2, 0.5))
		lamp(g, Vector3(0, 4, 0), Color("ffd08a"), 2.0, 25)
		rockets.append(rocket(B, g.position + Vector3(0, 1.4, 0)))
		# passerelle vers le centre
		var a3 := gp(p.x * 0.85, p.z * 0.85, 0.8)
		var b3 := gp(p.x * 0.25, p.z * 0.35, 0.8)
		box(B, "gris", (a3 + b3) * 0.5, Vector3(3.0, 0.4, a3.distance_to(b3)), Vector3(0, atan2(a3.x - b3.x, a3.z - b3.z), 0))
		box(B, "chaud", (a3 + b3) * 0.5 + Vector3(0, 0.25, 0), Vector3(0.2, 0.1, a3.distance_to(b3)), Vector3(0, atan2(a3.x - b3.x, a3.z - b3.z), 0))


func solar(B: Node3D, c: Vector3, rows: int, cols: int) -> void:
	for r in rows:
		for k in cols:
			var p := c + Vector3(k * 7.5 - cols * 3.75, 0, r * 6.0 - rows * 3.0)
			var g := Node3D.new()
			g.position = gp(p.x, p.z)
			B.add_child(g)
			cyl(g, "acier_sombre", Vector3(0, 1.0, 0), 0.12, 2.0)
			var pn := box(g, "solaire", Vector3(0, 2.0, 0), Vector3(6.8, 0.08, 4.0), Vector3(0.55, 0, 0))
			box(pn, "acier", Vector3(0, -0.05, 0), Vector3(6.9, 0.04, 4.1))


func shipyard(B: Node3D) -> void:
	var c := gp(-25, -155)
	var g := Node3D.new()
	g.position = c
	B.add_child(g)
	for k in 9:
		var x := -56.0 + k * 14.0
		for s in [-1.0, 1.0]:
			strut(g, "acier_sombre", Vector3(x, 0, s * 13), Vector3(x, 30, s * 13), 0.45)
			strut(g, "acier_sombre", Vector3(x, 0, s * 13), Vector3(x + 14, 30, s * 13) if k < 8 else Vector3(x, 30, s * 13), 0.18)
		strut(g, "acier_sombre", Vector3(x, 30, -13), Vector3(x, 30, 13), 0.4)
		strut(g, "acier_sombre", Vector3(x, 6, -13), Vector3(x, 6, 13), 0.3)
	strut(g, "acier_sombre", Vector3(-56, 30, -13), Vector3(56, 30, -13), 0.4)
	strut(g, "acier_sombre", Vector3(-56, 30, 13), Vector3(56, 30, 13), 0.4)
	var hull := Node3D.new()
	hull.position = Vector3(0, 17, 0)
	g.add_child(hull)
	tube_x(hull, "acier", Vector3(-50, 0, 0), 100, 9.0)
	for k in 7:
		tube_x(hull, "acier_sombre", Vector3(-48 + k * 15.0, 0, 0), 2.0, 9.4)
	cyl(hull, "acier", Vector3(54, 0, 0), 3.0, 8.0, 9.0, Vector3(0, 0, PI / 2), 40)
	for s in [-1.0, 1.0]:
		cyl(hull, "noir", Vector3(-53, s * 4.0, 0), 3.0, 6.0, 2.2, Vector3(0, 0, -PI / 2), 32)
	box(hull, "or", Vector3(10, 9.1, 0), Vector3(30, 0.3, 6))
	for k in 20:
		box(hull, "vitre", Vector3(-40 + k * 4.0, 3.5, 8.6), Vector3(1.2, 0.5, 0.2))
	cyl(g, "acier", Vector3(-35, 40, 0), 0.6, 20.0)
	box(g, "orange", Vector3(-35, 31, 0), Vector3(3, 2, 3))
	for k in 6:
		lamp(g, Vector3(-50 + k * 20.0, 28, rng.randf_range(-10, 10)), Color("cfe6ff"), 4.0, 35)
	beacon(g, Vector3(-35, 50.5, 0))


func excavator(B: Node3D, p: Vector3, yaw: float) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.z, 0.0)
	g.rotation.y = yaw
	B.add_child(g)
	for s in [-1.0, 1.0]:
		box(g, "noir", Vector3(0, 0.55, s * 1.55), Vector3(5.2, 1.1, 0.9))
		for k in 5:
			cyl(g, "acier_sombre", Vector3(-2.0 + k * 1.0, 0.55, s * 1.55), 0.42, 0.95, -1.0, Vector3(PI / 2, 0, 0), 16)
	box(g, "rouille", Vector3(0, 1.35, 0), Vector3(3.6, 0.6, 2.6))
	var up := Node3D.new()
	up.position = Vector3(0, 1.65, 0)
	up.rotation.y = rng.randf_range(-0.6, 0.6)
	g.add_child(up)
	box(up, "orange", Vector3(-0.4, 0.8, 0), Vector3(3.4, 1.6, 2.4))
	box(up, "acier_sombre", Vector3(-2.0, 0.6, 0), Vector3(0.8, 1.2, 2.3))
	box(up, "orange", Vector3(0.9, 1.9, 0.7), Vector3(1.4, 1.4, 1.0))
	box(up, "vitre", Vector3(1.61, 1.95, 0.7), Vector3(0.05, 0.8, 0.8))
	cyl(up, "orange", Vector3(-1.2, 2.0, -0.6), 0.12, 1.0)
	beacon(up, Vector3(-1.2, 2.6, -0.6))
	var a0 := Vector3(1.4, 1.4, -0.4)
	var a1 := Vector3(4.6, 4.8, -0.4)
	var a2 := Vector3(7.0, 1.2, -0.4)
	box(up, "orange", (a0 + a1) * 0.5, Vector3(a0.distance_to(a1), 0.55, 0.5), Vector3(0, 0, atan2(a1.y - a0.y, a1.x - a0.x)))
	box(up, "orange", (a1 + a2) * 0.5, Vector3(a1.distance_to(a2), 0.45, 0.45), Vector3(0, 0, atan2(a2.y - a1.y, a2.x - a1.x)))
	strut(up, "acier", a0 + Vector3(0.3, -0.3, 0.3), a1.lerp(a0, 0.3) + Vector3(0, -0.2, 0.3), 0.08)
	strut(up, "acier", a1 + Vector3(-0.3, 0.3, 0.3), a1.lerp(a2, 0.4) + Vector3(0, 0.3, 0.3), 0.07)
	box(up, "acier_sombre", a2 + Vector3(0.3, -0.5, 0), Vector3(1.0, 1.0, 1.3), Vector3(0, 0, -0.5))
	lamp(up, Vector3(2.5, 2.2, 0), Color("ffd29a"), 2.5, 16)
	for i in 6:
		dust(B, g.position + Vector3(rng.randf_range(-6, 6), rng.randf_range(0.8, 2.5), rng.randf_range(-6, 6)).rotated(Vector3.UP, 0.0), rng.randf_range(3.5, 7.0), 0.5)
	# traces de chenilles
	for s in [-1.0, 1.0]:
		for k in 8:
			var q := g.position + Vector3(-3.0 - k * 2.5, 0, s * 1.55).rotated(Vector3.UP, yaw)
			box(B, "noir", Vector3(q.x, height(q.x, q.z) + 0.02, q.z), Vector3(2.6, 0.04, 0.8), Vector3(0, yaw, 0))


func roads(B: Node3D) -> void:
	var n := 260
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var R := 135.0
		var p0 := gp(cos(a0) * R, sin(a0) * R, -0.02)
		var p1 := gp(cos(a1) * R, sin(a1) * R, -0.02)
		var bs := Basis.looking_at(p1 - p0, Vector3.UP)
		var rd := box(B, "beton", (p0 + p1) * 0.5, Vector3(5.0, 0.12, p0.distance_to(p1) + 0.15))
		rd.basis = bs
		if i % 3 == 0:
			var ln := box(B, "chaud", (p0 + p1) * 0.5 + Vector3(0, 0.07, 0), Vector3(0.12, 0.05, p0.distance_to(p1) * 0.7))
			ln.basis = bs
	for k in 10:
		var a := TAU * k / 10.0
		var p := gp(cos(a) * 139.0, sin(a) * 139.0)
		cyl(B, "acier_sombre", p + Vector3(0, 3, 0), 0.12, 6.0)
		sph(B, "chaud", p + Vector3(0, 6.1, 0), 0.25)
		lamp(B, p + Vector3(0, 5.8, 0), Color("ffb35a"), 2.5, 18)


func convoy(B: Node3D) -> void:
	for k in 4:
		var p := Vector3(150 + k * 12.0, 0, 160 + k * 11.0)
		var g := Node3D.new()
		g.position = gp(p.x, p.z, 0.0)
		g.rotation.y = -0.85
		B.add_child(g)
		for s in [-1.0, 1.0]:
			for w in 3:
				cyl(g, "noir", Vector3(-1.6 + w * 1.6, 0.6, s * 1.4), 0.6, 0.5, -1.0, Vector3(PI / 2, 0, 0), 16)
		box(g, "blanc", Vector3(0, 1.4, 0), Vector3(5.0, 1.2, 2.4))
		box(g, "blanc" if k % 2 else "or", Vector3(-0.6, 2.4, 0), Vector3(3.2, 0.9, 2.1))
		box(g, "vitre", Vector3(2.52, 1.7, 0), Vector3(0.05, 0.5, 1.8))
		var l := SpotLight3D.new()
		l.light_color = Color("e8f2ff")
		l.light_energy = 6.0
		l.spot_range = 40
		l.spot_angle = 30
		l.position = Vector3(2.6, 1.5, 0)
		l.rotation = Vector3(0, -PI / 2, 0)
		l.set_meta("e0", 6.0)
		g.add_child(l)
		lamps.append(l)
		dust(B, g.position + Vector3(-4, 1.0, 3).rotated(Vector3.UP, -0.85), 5.0, 0.35)


# blocs rocheux façon Bennu (amas de gravats) ; ceux du champ de bataille servent d'abris
var boulders: Array = []
var bgrid := {}
const BCELL := 8.0


func cover_near(p: Vector3, maxd: float):
	var cx := int(floor(p.x / BCELL))
	var cz := int(floor(p.z / BCELL))
	var best = null
	var bd := maxd
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(cx + dx, cz + dz)
			if not bgrid.has(k):
				continue
			for idx in bgrid[k]:
				var b: Array = boulders[idx]
				var c: Vector3 = b[0]
				# petit astéroïde : ignorer un rocher de l'autre côté qui partage les mêmes x, z
				if c.distance_to(p) > float(b[1]) + maxd + 4.0:
					continue
				var d := Vector2(c.x - p.x, c.z - p.z).length() - float(b[1])
				if d < bd:
					bd = d
					best = b
	return best


func rocks(B: Node3D) -> void:
	var meshes := []
	for k in 5:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 14
		s.rings = 9
		var st := SurfaceTool.new()
		st.create_from(s, 0)
		var arr := st.commit_to_arrays()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nz := FastNoiseLite.new()
		nz.seed = k * 13 + 1
		nz.frequency = 0.9
		for i in vs.size():
			var v: Vector3 = vs[i]
			vs[i] = v * (0.85 + 0.3 * nz.get_noise_3dv(v)) * Vector3(1.25, 0.7, 1.0)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_NORMAL] = null
		arr[Mesh.ARRAY_TANGENT] = null
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var st2 := SurfaceTool.new()
		st2.create_from(am, 0)
		st2.deindex()
		st2.generate_normals()
		meshes.append(st2.commit())
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.albedo_color = Color(1, 1, 1)
	rm.roughness = 0.95
	var lists := [[], [], [], [], []]
	var cols := [[], [], [], [], []]
	var rcols := [Color(0.32, 0.16, 0.09), Color(0.27, 0.13, 0.08), Color(0.36, 0.19, 0.11), Color(0.32, 0.16, 0.09), Color(0.27, 0.13, 0.08), Color(0.36, 0.19, 0.11)]
	var placed := 0
	while placed < 700:
		var x := rng.randf_range(-600, 600)
		var z := rng.randf_range(-600, 600)
		var rr := Vector2(x, z).length()
		if rr < 165 or rr > PI * RC * 0.92:
			continue
		var in_field := absf(x - 20.0) < 120.0 and z > 150.0 and z < 560.0
		var s := pow(rng.randf(), 2.6) * (2.6 if in_field else 7.0) + 0.3
		if in_field and rng.randf() < 0.35:
			s = rng.randf_range(0.9, 2.2)
		var k := rng.randi() % 5
		var p := gp(x, z, -0.25 * s)
		var b := (Basis(Quaternion(Vector3.UP, up_at(p))) * Basis(Vector3.UP, rng.randf() * TAU)).scaled_local(Vector3.ONE * s)
		lists[k].append(Transform3D(b, p))
		cols[k].append(rcols[rng.randi() % rcols.size()] if rng.randf() < 0.92 else rcols[5])
		if s > 0.8:
			boulders.append([gp(x, z), s * 1.1])
			var key := Vector2i(int(floor(x / BCELL)), int(floor(z / BCELL)))
			if not bgrid.has(key):
				bgrid[key] = []
			bgrid[key].append(boulders.size() - 1)
		placed += 1
	for k in 5:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[k]
		mm.instance_count = lists[k].size()
		for i in lists[k].size():
			mm.set_instance_transform(i, lists[k][i])
			mm.set_instance_color(i, cols[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var rmk := StandardMaterial3D.new()
		rmk.albedo_color = rcols[k % 3]
		rmk.roughness = 0.95
		mmi.material_override = rmk
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		B.add_child(mmi)

# ================================================================ points de vue
func apply_view(i: int) -> void:
	view = i
	var v: Dictionary = VUES[i]
	var el := deg_to_rad(v.el)
	var az := deg_to_rad(v.az)
	var sd := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	if not v.has("abs"):
		# soleil défini par rapport à la verticale locale du point regardé
		var lv: Vector3 = v.look
		sd = Quaternion(Vector3.UP, up_at(gp(lv.x, lv.z))) * sd
	else:
		# vues lointaines : soleil derrière l'épaule de la caméra, l'astre est toujours éclairé
		var vc: Vector3 = (v.cam - v.look).normalized()
		var sx := vc.cross(Vector3.UP).normalized()
		sd = (vc + sx * 0.6 + Vector3.UP * 0.4).normalized()
	sun.basis = Basis.looking_at(-sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.FORWARD)
	var night: bool = v.el < 0
	sun.light_energy = 0.0 if night else 2.4
	sun.visible = not night
	earth_light.light_energy = 0.35 if night else 0.0
	env.ambient_light_energy = 0.05 if night else 0.4
	env.tonemap_exposure = 1.7 if night else 1.25
	var lampe_e := 1.0 if night else 0.55
	for l in lamps:
		l.light_energy = float(l.get_meta("e0")) * lampe_e
	earth.visible = v.earth != null
	if v.earth != null:
		var cp0 := cam_pos_for(v)
		var lk0: Vector3 = v.look
		var fw := (lk0 - cp0)
		fw.y = 0
		fw = fw.normalized()
		var e2: Vector2 = v.earth
		var ed := fw.rotated(Vector3.UP, deg_to_rad(-e2.x))
		ed = (ed * cos(deg_to_rad(e2.y)) + Vector3.UP * sin(deg_to_rad(e2.y))).normalized()
		earth.position = cp0 + ed * 10000.0
		earth_light.basis = Basis.looking_at(-ed, Vector3.UP)
	var mode: String = v.fus
	for k in rockets.size():
		var r: Dictionary = rockets[k]
		var fire := mode == "feu" or (mode == "decollage" and k == 1)
		r.plume.visible = fire
		r.smoke.visible = fire
		var lift := BSC * (38.0 if (mode == "decollage" and k == 1) else (12.0 + k * 3.0 if mode == "feu" else 0.0))
		r.g.position = r.base + up_at(r.base) * lift
		r.smoke.position = Vector3(0, -lift, 0)
	post.set_shader_parameter("mode", int(v.mode))
	for tm in terr_mats:
		tm.set_shader_parameter("tint", v.tint)
	env.fog_enabled = v.has("fog")
	if v.has("fog"):
		env.fog_light_color = v.fog
		env.fog_density = v.fogd
		env.fog_sky_affect = 0.35
		env.fog_light_energy = 1.0
	style_lbl.text = "%d — %s" % [i + 1, String(v.nom).to_upper()]
	var cp: Vector3 = v.cam
	var lk: Vector3 = v.look
	if not v.has("abs"):
		cp = gp(cp.x, cp.z, cp.y)
		lk = gp(lk.x, lk.z, lk.y)
	target = lk
	dist = cp.distance_to(lk)
	cb = Basis.looking_at(lk - cp, up_at(lk) if not v.has("abs") else Vector3.UP)
	update_cam()


func cam_pos_for(v: Dictionary) -> Vector3:
	var cp: Vector3 = v.cam
	return gp(cp.x, cp.z, cp.y)


func update_cam() -> void:
	cb = cb.orthonormalized()
	cam.basis = cb
	cam.position = target + cb.z * dist
	# la caméra ne passe jamais sous le sol (verticale locale de la sphère)
	var ag := alt(cam.position)
	if ag < 1.2:
		cam.position += up_at(cam.position) * (1.2 - ag)


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(3.0, dist * 0.88)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(60000.0, dist / 0.88)
	elif e is InputEventMouseMotion:
		var m: int = e.button_mask
		if m & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			target += (-cb.x * e.relative.x + cb.y * e.relative.y) * dist * 0.0013
		elif m & MOUSE_BUTTON_MASK_LEFT:
			cb = Basis(Vector3.UP, -e.relative.x * 0.005) * cb
			cb = Basis(cb.x, -e.relative.y * 0.005) * cb
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode >= KEY_1 and e.keycode <= KEY_8:
			apply_view(e.keycode - KEY_1)
		elif e.keycode == KEY_H or e.keycode == KEY_HOME:
			apply_view(view)
		elif e.keycode == KEY_SPACE:
			paused = not paused
		elif e.keycode == KEY_PLUS or e.keycode == KEY_KP_ADD or e.keycode == KEY_EQUAL:
			tscale = minf(8.0, tscale * 2.0)
		elif e.keycode == KEY_MINUS or e.keycode == KEY_KP_SUBTRACT:
			tscale = maxf(0.25, tscale / 2.0)
		elif e.keycode == KEY_F:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif e.keycode == KEY_S:
			var md := (int(post.get_shader_parameter("mode")) + 1) % 13
			post.set_shader_parameter("mode", md)
			style_lbl.text = "FILTRE %d" % md
		elif e.keycode == KEY_ESCAPE:
			get_tree().quit()


func _process(delta: float) -> void:
	time += delta
	update_cam()
	var dt := minf(delta, 0.05)
	if shots_dir != "":
		tscale = 4.0
	if not paused:
		var sdt := dt * tscale
		var n := int(ceil(sdt / 0.05))
		for k in n:
			war.step(sdt / n)
	war.render(dt)
	hud_t -= delta
	if hud_t <= 0:
		hud_t = 0.4
		update_hud()
	if shots_dir != "" and war.time < 45.0:
		return
	var on := fmod(time, 1.5) < 0.4
	for b in blinks:
		b.visible = on or shots_dir != ""
	for r in rockets:
		if r.plume.visible:
			r.plume.scale = Vector3(1, 1.0 + 0.06 * sin(time * 40.0), 1)
	if shot_i >= 0:
		shot_wait -= 1
		if shot_wait <= 0:
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(shots_dir + "/k240_jeu_%02d.png" % (shot_i + 1))
			print("vue ", shot_i + 1, " ok")
			shot_i += 1
			if shot_i >= VUES.size():
				get_tree().quit()
			else:
				apply_view(shot_i)
				shot_wait = 5


# ================================================================ rendu en deux temps (scène -> filtre de style)
func build_pipeline() -> void:
	sv = SubViewport.new()
	sv.size = get_viewport().size
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	sv.add_child(cam)
	cam.current = true
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/post.gdshader")
	post.set_shader_parameter("res", Vector2(sv.size))
	post.set_shader_parameter("src", sv.get_texture())
	var cl := CanvasLayer.new()
	add_child(cl)
	var tr := TextureRect.new()
	tr.texture = sv.get_texture()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.material = post
	cl.add_child(tr)
	var cl2 := CanvasLayer.new()
	cl2.layer = 2
	add_child(cl2)
	style_lbl = Label.new()
	style_lbl.position = Vector2(22, 16)
	style_lbl.add_theme_font_size_override("font_size", 22)
	style_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	style_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	style_lbl.add_theme_constant_override("outline_size", 6)
	cl2.add_child(style_lbl)
	get_viewport().size_changed.connect(func():
		sv.size = get_viewport().size
		post.set_shader_parameter("res", Vector2(sv.size)))


# ================================================================ bataille de chars et d'infanterie
func team_mat(team: String) -> String:
	var k := "equipe_" + team
	if not mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("2b5fc4") if team == "b" else Color("b8281c")
		m.metallic = 0.3
		m.roughness = 0.5
		mats[k] = m
	return k


func tank(par: Node3D, x: float, z: float, yaw: float, team: String, fire: bool, wreck := false) -> void:
	var g := Node3D.new()
	var p := gp(x, z, 0.0)
	g.position = p
	g.rotation.y = yaw
	par.add_child(g)
	var body := "noir" if wreck else "acier_sombre"
	for s in [-1.0, 1.0]:
		box(g, "noir", Vector3(0, 0.6, s * 1.75), Vector3(7.4, 1.2, 1.0))
		for k in 6:
			cyl(g, "gris" if not wreck else "noir", Vector3(-3.0 + k * 1.2, 0.55, s * 1.75), 0.5, 1.05, -1.0, Vector3(PI / 2, 0, 0), 14)
	box(g, body, Vector3(0, 1.45, 0), Vector3(7.0, 0.9, 3.2))
	box(g, body, Vector3(3.2, 1.25, 0), Vector3(1.2, 0.8, 3.0), Vector3(0, 0, -0.5))
	box(g, team_mat(team) if not wreck else "noir", Vector3(-0.5, 1.95, 1.62), Vector3(3.5, 0.3, 0.05))
	box(g, team_mat(team) if not wreck else "noir", Vector3(-0.5, 1.95, -1.62), Vector3(3.5, 0.3, 0.05))
	var tu := Node3D.new()
	tu.position = Vector3(-0.6, 2.4, 0)
	tu.rotation.y = rng.randf_range(-0.15, 0.15)
	g.add_child(tu)
	box(tu, body, Vector3(0, 0, 0), Vector3(3.6, 1.1, 2.7))
	box(tu, body, Vector3(-1.9, 0.1, 0), Vector3(1.0, 0.9, 2.3))
	box(tu, team_mat(team) if not wreck else "noir", Vector3(0.2, 0.58, 0), Vector3(1.2, 0.06, 1.2))
	cyl(tu, body, Vector3(4.3, 0.1, 0), 0.22, 5.2, -1.0, Vector3(0, 0, PI / 2), 14)
	cyl(tu, "noir", Vector3(6.9, 0.1, 0), 0.32, 0.6, -1.0, Vector3(0, 0, PI / 2), 14)
	cyl(tu, "acier_sombre", Vector3(-1.2, 1.4, 0.9), 0.04, 2.0)
	if fire and not wreck:
		var fx := Node3D.new()
		fx.position = Vector3(8.2, 0.1, 0)
		tu.add_child(fx)
		dust(fx, Vector3(0.8, 0, 0), 4.5, 0.95, Color(1.0, 0.62, 0.22))
		sph(fx, "anneau", Vector3(0, 0, 0), 0.6)
		dust(g, Vector3(10, 2.5, 0), 6.0, 0.35, Color(0.45, 0.43, 0.42))
		var l := OmniLight3D.new()
		l.light_color = Color("ffb060")
		l.light_energy = 6.0
		l.omni_range = 18.0
		fx.add_child(l)
	if wreck:
		for k in 5:
			dust(g, Vector3(rng.randf_range(-1, 1), 3.0 + k * 3.0, rng.randf_range(-1, 1)), 4.0 + k * 1.5, 0.55, Color(0.12, 0.11, 0.11))
		dust(g, Vector3(0, 2.6, 0), 3.0, 0.9, Color(1.0, 0.5, 0.15))
		var l2 := OmniLight3D.new()
		l2.light_color = Color("ff8a3a")
		l2.light_energy = 3.0
		l2.omni_range = 14.0
		l2.position = Vector3(0, 3, 0)
		g.add_child(l2)


func explosion(par: Node3D, x: float, z: float, s: float) -> void:
	var p := gp(x, z, 1.0)
	var g := Node3D.new()
	g.position = p
	par.add_child(g)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.03, 0.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.15)
	m.emission_energy_multiplier = 6.0
	for k in 4:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = s * rng.randf_range(0.5, 0.9)
		sm.height = sm.radius * 2.0
		b.mesh = sm
		b.material_override = m
		b.position = Vector3(rng.randf_range(-s, s) * 0.6, s * (0.3 + k * 0.35), rng.randf_range(-s, s) * 0.6)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(b)
	for k in 7:
		dust(g, Vector3(rng.randf_range(-s, s), s * (1.0 + k * 0.6), rng.randf_range(-s, s)), s * rng.randf_range(2.2, 3.5), 0.6, Color(0.18, 0.17, 0.16))
	for k in 10:
		var d := box(g, "noir", Vector3(rng.randf_range(-3, 3) * s, rng.randf_range(1, 5) * s, rng.randf_range(-3, 3) * s), Vector3.ONE * rng.randf_range(0.2, 0.5))
		d.rotation = Vector3(rng.randf() * 3, rng.randf() * 3, 0)
	var l := OmniLight3D.new()
	l.light_color = Color("ff9a40")
	l.light_energy = 10.0
	l.omni_range = 30.0 * s / 2.0
	l.position = Vector3(0, s, 0)
	g.add_child(l)


func soldiers(par: Node3D, cx: float, cz: float, n: int, team: String, yaw: float) -> void:
	var cm := CapsuleMesh.new()
	cm.radius = 0.28
	cm.height = 1.8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = n
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = hm
	mm2.instance_count = n
	for i in n:
		var x := cx + (i % 8) * 1.8 + rng.randf_range(-0.5, 0.5)
		var z := cz + (i / 8) * 2.0 + rng.randf_range(-0.5, 0.5)
		var p := gp(x, z, 0.9)
		var crouch := rng.randf() < 0.4
		var b := Basis(Vector3.UP, yaw + rng.randf_range(-0.3, 0.3))
		if crouch:
			b = b.scaled(Vector3(1, 0.65, 1))
			p.y -= 0.3
		mm.set_instance_transform(i, Transform3D(b, p))
		mm2.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, 0.95 if not crouch else 0.62, 0)))
	var a := MultiMeshInstance3D.new()
	a.multimesh = mm
	a.material_override = M(team_mat(team))
	par.add_child(a)
	var h := MultiMeshInstance3D.new()
	h.multimesh = mm2
	h.material_override = M("acier_sombre")
	par.add_child(h)


func tracer_line(par: Node3D, a: Vector3, b: Vector3, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 8.0
	var d := b - a
	var L := minf(d.length() * 0.18, 9.0)
	var mid := a + d * rng.randf_range(0.2, 0.8)
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, L)
	t.mesh = bm
	t.material_override = m
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	par.add_child(t)
	t.position = mid
	t.basis = Basis.looking_at(d, Vector3.UP)


func battle(B: Node3D) -> void:
	var W := Node3D.new()
	B.add_child(W)
	# tranchées et barricades
	for row in [[200.0, "b"], [242.0, "r"]]:
		for k in 30:
			var x := -40.0 + k * 3.6
			var z: float = row[0] + sin(k * 0.7) * 2.0
			var bag := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.35
			cm.height = 1.3
			bag.mesh = cm
			bag.material_override = M("rouille")
			bag.position = gp(x, z, 0.3)
			bag.rotation = Vector3(0, 0.1, PI / 2)
			W.add_child(bag)
			if k % 3 == 0:
				box(W, "acier_sombre", gp(x, z + 1.2, 0.6), Vector3(2.4, 1.2, 0.15), Vector3(0.2, rng.randf_range(-0.4, 0.4), 0))
			if k % 4 == 1:
				for c in 2:
					strut(W, "noir", gp(x + c, z - 2.0, 0.0), gp(x + c + 0.6, z - 2.0, 1.4), 0.08)
	# armées
	for k in 9:
		tank(W, -30 + k * 10.0, 182 + (k % 2) * 6.0, -PI / 2, "b", k % 2 == 0)
	for k in 9:
		tank(W, -28 + k * 10.0, 258 + (k % 2) * 6.0, PI / 2, "r", k % 3 != 1, k == 4 or k == 7)
	tank(W, 12, 214, -PI / 2 + 0.6, "b", false, true)
	for k in 4:
		soldiers(W, -38 + k * 22.0, 192.0, 24, "b", -PI / 2)
		soldiers(W, -36 + k * 22.0, 246.0, 24, "r", PI / 2)
	for e in [[0.0, 226.0, 2.5], [25.0, 236.0, 3.0], [48.0, 214.0, 2.0], [-18.0, 232.0, 1.8], [62.0, 240.0, 2.6], [36.0, 205.0, 1.5]]:
		explosion(W, e[0], e[1], e[2])
	for k in 45:
		var a := gp(rng.randf_range(-35, 70), rng.randf_range(185, 198), 1.5)
		var b := gp(rng.randf_range(-35, 70), rng.randf_range(244, 262), 1.5)
		if k % 2 == 0:
			tracer_line(W, a, b, Color(0.45, 0.9, 1.0))
		else:
			tracer_line(W, b, a, Color(1.0, 0.5, 0.2))
	for k in 18:
		dust(W, gp(rng.randf_range(-40, 80), rng.randf_range(200, 250), rng.randf_range(2, 8)), rng.randf_range(10, 22), 0.25, Color(0.4, 0.38, 0.36))


# ================================================================ interface façon bande dessinée
func bd_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f7efd8")
	sb.border_color = Color("111111")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.9)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(5, 5)
	return sb


func bd_label(size: int, col := Color("111111"), bold := 800) -> Label:
	var l := Label.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	f.font_weight = bold
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 3
	add_child(cl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	var title := Label.new()
	title.text = "K-240 · FRONT DE SURFACE"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd23f"))
	title.add_theme_color_override("font_outline_color", Color("111111"))
	title.add_theme_constant_override("outline_size", 10)
	title.position = Vector2(20, 44)
	root.add_child(title)
	var p1 := PanelContainer.new()
	p1.add_theme_stylebox_override("panel", bd_panel())
	p1.position = Vector2(20, 96)
	p1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_stats = bd_label(15)
	p1.add_child(lbl_stats)
	root.add_child(p1)
	var p2 := PanelContainer.new()
	p2.add_theme_stylebox_override("panel", bd_panel())
	p2.anchor_left = 1.0
	p2.anchor_right = 1.0
	p2.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p2.offset_right = -24
	p2.offset_top = 20
	p2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_units = bd_label(15)
	p2.add_child(lbl_units)
	root.add_child(p2)
	var help := Label.new()
	help.text = "1-8 : vues · Clic gauche : tourner · Molette enfoncée / clic droit : déplacer · Molette : zoom · + / - : vitesse · Espace : pause · H : recadrer · S : filtre · F : plein écran · Échap : quitter"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(1, 1, 1))
	help.add_theme_color_override("font_outline_color", Color("111111"))
	help.add_theme_constant_override("outline_size", 6)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 20
	help.offset_top = -34
	root.add_child(help)


func update_hud() -> void:
	var h: Dictionary = war.stats()
	var names := {"rifle": "Fusiliers", "flame": "Lance-flammes", "robot": "Robots soutien", "tank": "Chars"}
	var t := "EFFECTIFS          COLONIE        PIRATES\n                 unités hommes  unités hommes\n"
	var tb := 0
	var tr := 0
	for k in ["rifle", "flame", "robot", "tank"]:
		var fb: int = h.f.get("b" + k, 0)
		var fr: int = h.f.get("r" + k, 0)
		var mb: int = h.m.get("b" + k, 0)
		var mr: int = h.m.get("r" + k, 0)
		tb += mb
		tr += mr
		t += "%-16s %5d %6d  %6d %6d\n" % [names[k], fb, mb, fr, mr]
	t += "%-16s %12d  %13d" % ["TOTAL", tb, tr]
	lbl_units.text = t
	var front: float = clampf(h.front, 0.03, 0.97)
	var bar := ""
	for i in 26:
		bar += "█" if i < int(front * 26) else "░"
	var spd := "PAUSE" if paused else "x%s" % str(tscale)
	lbl_stats.text = "IMAGES/S         %d\nASTÉROÏDE        Ø %.1f km\n                 (x%.1f le front)\nFORME            %s\nVAGUE            %d\nPERTES PIRATES   %d\nPERTES COLONIE   %d\nVITESSE          %s\n\nLIGNE DE FRONT\n%s" % [Engine.get_frames_per_second(), RC * 2.0 / 1000.0, TAILLE_K, SH_TYPE, h.wave, h.kills.b, h.kills.r, spd, bar]
