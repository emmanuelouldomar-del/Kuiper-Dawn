extends Node3D
## K-240 — le monde : astéroïde, base minière, caméra, vues, filtres et interface (1 unité = 1 m).
## Style minimaliste & géométrique (façon Monument Valley). La bataille elle-même est dans battle.gd.
## Astéroïde tiré au hasard à chaque partie : rayon RC ≈ 200–510 m, forme patate / allongée / binaire.
## Touches 1…8 : points de vue · S : filtre · +/- : vitesse · Espace : pause · F : plein écran · Échap : quitter.
## Structure du fichier :
##   surface de l'astéroïde façon Planetary Annihilation : forme + bruit 3D + brosses (cratères, plateaux, crêtes)
##     -> surf_eval(dir), source unique pour le sol, la base, les unités et les collisions (gp, alt, up_at, los_hit)
##   maillage cube-sphère généré en parallèle (build_terrain) ; biome désert cartoon (shaders/terrain.gdshader)
##   ciel, soleil, Terre
##   base : moyeu + antenne, tubes, dôme géodésique, habitats, pas de tir + fusées,
##          panneaux solaires, chantier naval, excavatrices + poussière, routes, rochers
##   décor du désert : rochers mesas, agaves, cactus, cailloux, graviers (shaders/toon.gdshader)
##   VUES : points de vue (caméra, soleil, état des fusées) ; rendu en deux temps (scène -> filtre post) ; HUD

const BSC := 0.5  # échelle des bâtiments de la base
const LOBE_FUSED := false  # le second lobe (astéroïdes bilobés) est un corps à part, maillé autour de son propre centre
var RC := 2500.0
var TAILLE_K := 10.0
const FRONT_LEN := 340.0
var mats := {}
var rng := RandomNumberGenerator.new()
var cam: Camera3D
var sun: DirectionalLight3D
var earth_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var env: Environment
var earth: MeshInstance3D
var rockets: Array = []
var plumes: Array = []       # bouffées de fumée animées (cheminées, tours de refroidissement)
var harvesters: Array = []   # moissonneuses-racleuses mobiles
var base_root: Node3D        # nœud parent des bâtiments de la base
var colony                   # économie de la colonie (colony.gd)
var bridge                   # passerelle de commandement (bridge.gd)
var strategy                 # flottes, carte, Kronos, pilote automatique (strategy.gd)
var factions                 # diplomatie, superviseurs, opérations spéciales (factions.gd)
var survival                 # survie à 40 UA, Terre, vaisseau-arche (survival.gd)
var ark_hull: Node3D         # coque du vaisseau-arche en cours d'assemblage
var siege: Array = []        # vaisseaux pirates qui pilonnent le bouclier
var screen_tex: TextureRect  # image de la vue 3D (après le filtre de style)
var screen_layer: CanvasLayer
var hud_root: Control        # ancien HUD (vue 3D plein écran)
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
var verif_chars := false
var auto_test := false       # --autopilote : le pilote automatique joue, rapport chaque minute de jeu
var auto_next := 60.0
var verif_n := 0
var verif_min := INF
var verif_max := -INF
var verif_in := 0
var verif_imin := INF
var verif_imax := -INF
var verif_amax := 0.0
var verif_asum := 0.0
var verif_an := 0
var shot_i := -1
var shot_wait := 0
var target := Vector3.ZERO
var cb := Basis()
var dist := 100.0

# point de vue : caméra, cible, élévation et azimut du soleil (°), direction de la Terre, état des fusées
var VUES := [
	{"nom": "Ligne de front", "mode": 0, "cam": Vector3(-30, 14, 236), "look": Vector3(20, 3, 300), "el": 38.0, "az": 205.0, "earth": Vector2(22, 12), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Vue tactique", "mode": 0, "cam": Vector3(-110, 150, 260), "look": Vector3(20, 0, 345), "el": 45.0, "az": 210.0, "earth": null, "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "La base", "mode": 0, "cam": Vector3(14, 20, 58), "look": Vector3(-2, 3, -2), "el": 30.0, "az": 215.0, "earth": Vector2(-30, 14), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Zone industrielle", "mode": 0, "cam": Vector3(100, 28, 6), "look": Vector3(50, 14, -38), "el": 25.0, "az": 160.0, "earth": Vector2(-20, 13), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Spatioport", "mode": 0, "cam": Vector3(46, 26, -34), "look": Vector3(-4, 8, -92), "el": 22.0, "az": 35.0, "earth": Vector2(-26, 26), "fus": "decollage", "tint": Vector3(1.05, 1.0, 0.95)},
	{"nom": "Côté pirates", "mode": 0, "cam": Vector3(70, 16, 520), "look": Vector3(20, 3, 470), "el": 30.0, "az": 20.0, "earth": Vector2(-24, 12), "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)},
]
const BATTLE_A := Vector3(20, 0, 175)
const BATTLE_B := Vector3(20, 0, 515)
var war
var tscale := 1.0
var paused := false
var lbl_stats: Label
var lbl_units: Label
var hud_t := 0.0


# ================================================================ surface de l'astéroïde (source unique de vérité)
# Façon Planetary Annihilation : forme générale + bruit 3D + « brosses » (cratères, plateaux, crêtes).
# Le maillage du sol (cube-sphère), les bâtiments, les unités et les collisions utilisent tous surf_eval().

# ---- forme inspirée d'un astéroïde réel (proportions réelles, taille du jeu), tirée au hasard
# Densités apparentes mesurées par les missions spatiales (g/cm³) : elles donnent la masse, donc la gravité.
const MODELES := [
	# nom affiché, type de forme, densité (g/cm³), source
	["Bennu (toupie)", "toupie", 1.19, "OSIRIS-REx"],
	["Itokawa (cacahuète)", "cacahuete", 1.90, "Hayabusa"],
	["Arrokoth (bilobé aplati)", "arrokoth", 0.24, "New Horizons, ceinture de Kuiper"],
	["Éros (allongé)", "eros", 2.67, "NEAR Shoemaker"],
	["Kléopâtre (os)", "os", 3.40, "observations radar / optique adaptative"],
	["Psyché (patate)", "patate", 3.90, "estimations depuis la Terre"],
]
const G_NEWTON := 6.674e-11
var SH_TYPE := ""
var SH_KIND := ""
var SH_RHO := 2.0          # densité (kg/m³ après conversion)
var SH_ROT := Basis()      # repère du corps : la base est posée sur l'axe +Y du monde
var SH_ELL := Vector3.ONE
var SH_LOBE_C := Vector3.ZERO
var SH_LOBE_R := 0.0
var SH_LOBE_ELL := Vector3.ONE
var SH_BLOBS := PackedVector4Array()
var SH_BW := PackedFloat32Array()
var SH_POLE := 1.0
var SH_TH0 := 0.3
var AST_MASS := 0.0        # kg
var AST_COM := Vector3.ZERO  # centre de masse (point d'attraction de la gravité)
var AST_G := 0.0           # gravité de surface sous la base (m/s²)
var AST_VESC := 0.0        # vitesse de libération (m/s)


func make_shape(dice: RandomNumberGenerator) -> void:
	var md: Array = MODELES[dice.randi() % MODELES.size()]
	# option de lancement --forme <nom> (ex. cacahuete, arrokoth, toupie) : impose la forme
	var args := OS.get_cmdline_user_args()
	var fi := args.find("--forme")
	if fi >= 0 and fi + 1 < args.size():
		for m in MODELES:
			if String(m[1]) == args[fi + 1] or String(m[0]).to_lower().begins_with(args[fi + 1].to_lower()):
				md = m
	SH_TYPE = md[0]
	SH_KIND = md[1]
	SH_RHO = float(md[2]) * 1000.0
	SH_LOBE_R = 0.0
	SH_LOBE_ELL = Vector3.ONE
	SH_ROT = Basis()
	var bump := 0.04
	match SH_KIND:
		"toupie":
			# double cône arrondi avec bourrelet équatorial ; la base est posée sur le bourrelet
			SH_ELL = Vector3(1.0, 0.88, 1.0)
			SH_ROT = Basis(Vector3(0, 0, 1), PI / 2)
			bump = 0.025
		"cacahuete":
			SH_ELL = Vector3(1.0, 0.72, 0.7)
			SH_LOBE_C = Vector3(1.25, 0.08, 0.0)
			SH_LOBE_R = 0.62
			SH_LOBE_ELL = Vector3(1.1, 0.8, 0.85)
		"arrokoth":
			# deux lobes aplatis en contact (un grand, un petit)
			SH_ELL = Vector3(1.0, 0.95, 0.5)
			SH_LOBE_C = Vector3(1.45, 0.0, 0.0)
			SH_LOBE_R = 0.72
			SH_LOBE_ELL = Vector3(0.9, 1.0, 0.62)
			bump = 0.02
		"eros":
			SH_ELL = Vector3(1.9, 0.72, 0.68)
		"os":
			SH_ELL = Vector3(2.1, 0.62, 0.62)
			SH_LOBE_C = Vector3(-1.7, 0.0, 0.0)
			SH_LOBE_R = 0.75
		_:
			# Psyché : environ 278 × 232 × 189 km
			SH_ELL = Vector3(1.0, 0.83, 0.68)
			bump = 0.07
	SH_ROT = Basis(Vector3.UP, dice.randf() * TAU) * SH_ROT
	SH_BLOBS = PackedVector4Array()
	SH_BW = PackedFloat32Array()
	for i in 16:
		var d := Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1)).normalized()
		SH_BLOBS.append(Vector4(d.x, d.y, d.z, dice.randf_range(-bump, bump * 1.4)))
		SH_BW.append(dice.randf_range(0.04, 0.16))
	if SH_KIND == "os":
		# Kléopâtre : extrémités renflées
		SH_BLOBS.append(Vector4(1, 0, 0, 0.25))
		SH_BW.append(0.25)
	SH_POLE = 1.0
	SH_POLE = shape_raw(Vector3.UP)
	# seule une petite calotte autour de la base reste sphérique : la forme réelle se voit partout ailleurs
	SH_TH0 = clampf(170.0 / RC, 0.25, 0.75)
	NZ_LUMP.seed = dice.randi()
	NZ_LUMP.frequency = 0.95
	NZ_LUMP.fractal_octaves = 3
	NZ_LUMP.fractal_gain = 0.55


# masse (volume de la forme × densité réelle), centre de masse et gravité de surface : g = G·M / r²
func make_gravity(dice: RandomNumberGenerator) -> void:
	var s := 0.0
	var m1 := Vector3.ZERO
	var n := 3000
	for i in n:
		var d := Vector3(dice.randfn(), dice.randfn(), dice.randfn()).normalized()
		var r := radius_at(d)
		s += r * r * r
		# moment du premier ordre d'un corps étoilé : ∫ r⁴/4 · d dΩ
		m1 += d * (r * r * r * r * 0.75)
	var vol := 4.0 / 3.0 * PI * s / n
	var c0 := Vector3(0, -RC, 0)
	# centre de masse du corps principal (centroïde de la forme), puis avec le lobe
	var com := c0 + m1 / s
	if SH_LOBE_R > 0.0 and not LOBE_FUSED:
		var lv := lobe_volume()
		com = (com * vol + lobe_center() * lv) / (vol + lv)
		vol += lv
	AST_COM = com
	AST_MASS = SH_RHO * vol
	AST_G = G_NEWTON * AST_MASS / maxf(AST_COM.length_squared(), 1.0)
	AST_VESC = sqrt(2.0 * G_NEWTON * AST_MASS / maxf(AST_COM.length(), 1.0))


# accélération de la pesanteur en un point : vers le centre de masse de l'astéroïde
func grav_at(p: Vector3) -> Vector3:
	var v := AST_COM - p
	var d2 := maxf(v.length_squared(), RC * RC * 0.25)
	return v.normalized() * (G_NEWTON * AST_MASS / d2)


# verticale de la pesanteur (opposée à la gravité) : les unités debout s'alignent dessus
func grav_up(p: Vector3) -> Vector3:
	var v := p - AST_COM
	return v / maxf(v.length(), 1e-3)


# ---- zones aplanies sous les objets fixes (comme les bâtiments de Planetary Annihilation)
var FZ_DIR := PackedVector3Array()
var FZ_ANG := PackedFloat32Array()
var FZ_COS := PackedFloat32Array()
var FZ_R := PackedFloat32Array()


# le sol est aplani à la hauteur de p sur un disque de rayon radius (m), avec un raccord doux autour
func add_flat_zone(p: Vector3, radius: float) -> void:
	var v := p + Vector3(0, RC, 0)
	var ang := radius / v.length()
	FZ_DIR.append(v.normalized())
	FZ_ANG.append(ang)
	FZ_COS.append(cos(minf(ang * 1.8, PI)))
	FZ_R.append(v.length())


func flatten(d: Vector3, r: float) -> float:
	for i in FZ_DIR.size():
		var c := d.dot(FZ_DIR[i])
		if c < FZ_COS[i]:
			continue
		var t := acos(minf(c, 1.0)) / FZ_ANG[i]
		r = lerpf(r, FZ_R[i], 1.0 - smoothstep(1.0, 1.8, t))
	return r


# ---- relief : bruits 3D et brosses
const BR_CRATER := 0
const BR_MESA := 1
const BR_RIDGE := 2
var BR_DIR := PackedVector3Array()
var BR_AXIS := PackedVector3Array()
var BR_ANG := PackedFloat32Array()   # rayon (cratère, plateau) ou demi-longueur (crête), en radians
var BR_COS := PackedFloat32Array()   # rejet rapide : cos du rayon d'influence
var BR_KIND := PackedInt32Array()
var BR_H := PackedFloat32Array()     # profondeur (cratère) ou hauteur (plateau, crête), en m
var BR_W := PackedFloat32Array()     # crête : demi-largeur en m
var NZ_DUNE := FastNoiseLite.new()
var NZ_LUMP := FastNoiseLite.new()   # grosses bosses irrégulières de la forme (pas de silhouette trop ronde)
const LUMP_A := 0.2                      # amplitude relative des bosses
var NZ_EDGE := FastNoiseLite.new()
var NZ_CD := FastNoiseLite.new()     # cratères moyens : distance au germe (cellulaire)
var NZ_CV := FastNoiseLite.new()     # cratères moyens : valeur de la cellule (taille, présence)
var NZ_CD2 := FastNoiseLite.new()    # petits cratères
var NZ_CV2 := FastNoiseLite.new()


func rdir(dice: RandomNumberGenerator) -> Vector3:
	return Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1)).normalized()


func make_relief(dice: RandomNumberGenerator) -> void:
	var s := dice.randi() % 100000
	NZ_DUNE.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	NZ_DUNE.seed = s
	NZ_DUNE.frequency = 1.0 / 90.0
	NZ_DUNE.fractal_octaves = 3
	NZ_EDGE.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	NZ_EDGE.seed = s + 5
	NZ_EDGE.frequency = 1.0 / 14.0
	NZ_EDGE.fractal_octaves = 2
	for cfg in [[NZ_CD, NZ_CV, 1.0 / 70.0, s + 17], [NZ_CD2, NZ_CV2, 1.0 / 22.0, s + 91]]:
		for k in 2:
			var z: FastNoiseLite = cfg[k]
			z.noise_type = FastNoiseLite.TYPE_CELLULAR
			z.seed = cfg[3]
			z.frequency = cfg[2]
			z.fractal_type = FastNoiseLite.FRACTAL_NONE
			z.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			z.cellular_jitter = 0.85
			z.cellular_return_type = FastNoiseLite.RETURN_DISTANCE if k == 0 else FastNoiseLite.RETURN_CELL_VALUE
	BR_DIR = PackedVector3Array()
	BR_AXIS = PackedVector3Array()
	BR_ANG = PackedFloat32Array()
	BR_COS = PackedFloat32Array()
	BR_KIND = PackedInt32Array()
	BR_H = PackedFloat32Array()
	BR_W = PackedFloat32Array()
	var k_sc := clampf(RC / 350.0, 0.6, 1.4)
	var want := [[BR_CRATER, 7], [BR_MESA, clampi(int(RC / 35.0), 6, 16)], [BR_RIDGE, 4]]
	for w in want:
		var kind: int = w[0]
		var placed := 0
		var tries := 0
		while placed < int(w[1]) and tries < 400:
			tries += 1
			var d := rdir(dice)
			var q := planar_of(d)
			# les brosses restent hors de la base et du couloir de bataille
			if relief_mask(q.x, q.y) < 0.95:
				continue
			var ang := 0.0
			var h := 0.0
			var wd := 0.0
			var ax := Vector3.ZERO
			var infl := 1.0
			if kind == BR_CRATER:
				var rm := dice.randf_range(0.1, 0.3) * RC
				ang = rm / RC
				h = rm * dice.randf_range(0.16, 0.26)
				infl = 1.6
			elif kind == BR_MESA:
				var rm := dice.randf_range(22.0, 60.0) * k_sc
				ang = rm / RC
				h = dice.randf_range(10.0, 26.0) * k_sc
				infl = 1.15
			else:
				ang = dice.randf_range(0.25, 0.6)
				h = dice.randf_range(8.0, 20.0) * k_sc
				wd = dice.randf_range(14.0, 30.0) * k_sc
				ax = rdir(dice)
				ax = (ax - d * ax.dot(d)).normalized()
				infl = 1.05
			BR_DIR.append(d)
			BR_AXIS.append(ax)
			BR_ANG.append(ang)
			BR_COS.append(cos(minf(ang * infl, PI)))
			BR_KIND.append(kind)
			BR_H.append(h)
			BR_W.append(wd)
			placed += 1


# cratère « cellulaire » : un germe par cellule, taille et présence tirées par cellule
func cell_crater(p: Vector3, nd: FastNoiseLite, nv: FastNoiseLite, cell: float) -> Vector2:
	var v := nv.get_noise_3dv(p)
	if v < -0.3:
		return Vector2.ZERO
	var dist := nd.get_noise_3dv(p) + 1.0
	var r := 0.16 + 0.16 * (v * 0.5 + 0.5)
	var t := dist / r
	if t > 1.7:
		return Vector2.ZERO
	var D := r * cell * 0.2
	var off := (t * t - 1.0) * D if t < 1.0 else 0.0
	off += 0.3 * D * exp(-pow((t - 1.0) / 0.22, 2.0))
	var shade := -clampf(1.0 - t, 0.0, 1.0) * 1.5 + exp(-pow((t - 1.0) / 0.12, 2.0))
	return Vector2(off, shade)


func relief_mask(x: float, z: float) -> float:
	var mb := smoothstep(240.0, 330.0, sqrt(x * x + z * z))
	var mc := maxf(smoothstep(110.0, 180.0, absf(x - 20.0)), maxf(smoothstep(580.0, 660.0, z), smoothstep(110.0, 40.0, z)))
	return mb * mc


# rayon de la forme (sans unité) dans la direction d0 du monde
func shape_raw(d0: Vector3) -> float:
	var d := SH_ROT * d0
	var e: float
	if SH_KIND == "toupie":
		# double cône arrondi (superellipsoïde) + bourrelet équatorial, comme Bennu et Ryugu
		var rho := sqrt(d.x * d.x + d.z * d.z)
		var p := 1.35
		e = 1.0 / pow(pow(absf(d.y) / SH_ELL.y, p) + pow(rho, p), 1.0 / p)
		e *= 1.0 + 0.035 * exp(-pow(d.y / 0.1, 2.0))
	else:
		e = 1.0 / sqrt(d.x * d.x / (SH_ELL.x * SH_ELL.x) + d.y * d.y / (SH_ELL.y * SH_ELL.y) + d.z * d.z / (SH_ELL.z * SH_ELL.z))
	if SH_LOBE_R > 0.0 and LOBE_FUSED:
		# second lobe ellipsoïdal soudé au premier (union douce le long du rayon)
		var re := SH_LOBE_ELL * SH_LOBE_R
		var dd := d / re
		var cc := SH_LOBE_C / re
		var qa := dd.dot(dd)
		var qb := -2.0 * dd.dot(cc)
		var qc := cc.dot(cc) - 1.0
		var disc := qb * qb - 4.0 * qa * qc
		if disc > 0.0:
			var tb := (-qb + sqrt(disc)) / (2.0 * qa)
			if tb > 0.0:
				var k := 0.12
				var m := maxf(e, tb)
				e = m + k * log(exp((e - m) / k) + exp((tb - m) / k))
	var b := 0.0
	for i in SH_BLOBS.size():
		var bl: Vector4 = SH_BLOBS[i]
		b += bl.w * exp((d.x * bl.x + d.y * bl.y + d.z * bl.z - 1.0) / SH_BW[i])
	return e * (1.0 + b)


func radius_raw(d: Vector3) -> float:
	var th := acos(clampf(d.y, -1.0, 1.0))
	if th <= SH_TH0:
		return RC
	var m := smoothstep(SH_TH0, SH_TH0 + 0.45, th)
	var lump := 1.0 + NZ_LUMP.get_noise_3dv(d) * LUMP_A * m
	return RC * (1.0 + (shape_raw(d) / SH_POLE - 1.0) * m) * lump


# ---- raccord doux entre les deux lobes d'un astéroïde binaire (union douce des deux formes)
# largeur du congé (m)
func neck_k() -> float:
	return lobe_radius() * 0.45


# poids du congé (1 au contact, 0 à la distance k) : le relief y est atténué pour un raccord lisse
func neck_w(s: float) -> float:
	return clampf(1.0 - s / neck_k(), 0.0, 1.0)


# distance (approchée, radiale) d'un point à la surface lisse du lobe, et au corps principal
func lobe_sd(p: Vector3) -> float:
	var v := p - lobe_center()
	var L := v.length()
	return L - lobe_raw(v / L) if L > 1e-3 else -lobe_radius()


func main_sd(p: Vector3) -> float:
	var v := p + Vector3(0, RC, 0)
	var L := v.length()
	return L - radius_raw(v / L) if L > 1e-3 else -RC


func has_lobe() -> bool:
	return SH_LOBE_R > 0.0 and not LOBE_FUSED


# distance au lobe du point de la forme lisse principale dans la direction d
func main_neck_s(d: Vector3) -> float:
	if not has_lobe():
		return INF
	return lobe_sd(Vector3(0, -RC, 0) + d * radius_raw(d))


# union douce (polynomiale) de deux distances
func smin_k(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


# surface de l'union douce le long d'un rayon (centre c, direction d), r0 = rayon du corps seul.
# lobe = true : le rayon part du centre du lobe et l'autre corps est le corps principal.
func neck_solve(c: Vector3, d: Vector3, r0: float, lobe: bool) -> float:
	var k := neck_k()
	var b0 := main_sd(c + d * r0) if lobe else lobe_sd(c + d * r0)
	if b0 > k:
		return r0
	var lo := r0
	var hi := r0 + k
	for it in 10:
		var r := (lo + hi) * 0.5
		var b := main_sd(c + d * r) if lobe else lobe_sd(c + d * r)
		if smin_k(r - r0, b, k) < 0.0:
			lo = r
		else:
			hi = r
	return (lo + hi) * 0.5


func radius_at(d: Vector3) -> float:
	var r := radius_raw(d)
	if has_lobe():
		r = neck_solve(Vector3(0, -RC, 0), d, r, false)
	return r


# coordonnées « à plat » (x, z) d'une direction (projection azimutale équidistante autour de la base)
func planar_of(d: Vector3) -> Vector2:
	var th := acos(clampf(d.y, -1.0, 1.0))
	var sh := sqrt(d.x * d.x + d.z * d.z)
	if sh < 1e-6:
		return Vector2.ZERO if d.y > 0.0 else Vector2(PI * RC, 0.0)
	return Vector2(d.x, d.z) / sh * th * RC


# rayon de la surface dans la direction d : x = rayon (m), y = ombrage des cratères (-1 fond, +1 rebord), z = masque du relief
func surf_eval(d: Vector3) -> Vector3:
	var q := planar_of(d)
	var r := radius_at(d)
	var p := d * RC
	# dunes douces, presque plates dans la base et le couloir de bataille
	var ql := q.length()
	var m := smoothstep(150.0, 320.0, ql)
	var mc := maxf(smoothstep(95.0, 175.0, absf(q.x - 20.0)), maxf(smoothstep(560.0, 650.0, q.y), smoothstep(120.0, 60.0, q.y)))
	r += (NZ_DUNE.get_noise_3dv(p) * 0.5 + 0.5) * 2.4 * minf(lerpf(0.12, 1.0, m), lerpf(0.22, 1.0, mc))
	var mr := smoothstep(240.0, 330.0, ql) * maxf(smoothstep(110.0, 180.0, absf(q.x - 20.0)), maxf(smoothstep(580.0, 660.0, q.y), smoothstep(110.0, 40.0, q.y)))
	# relief atténué dans le congé entre les deux lobes
	if mr > 0.001 and has_lobe():
		mr *= 1.0 - neck_w(main_neck_s(d))
	if mr <= 0.001:
		return Vector3(flatten(d, r), 0.0, 0.0)
	var off := 0.0
	var shade := 0.0
	var c1 := cell_crater(p, NZ_CD, NZ_CV, 70.0)
	var c2 := cell_crater(p + Vector3(31, 7, 13), NZ_CD2, NZ_CV2, 22.0)
	off += c1.x + c2.x * 0.8
	shade += c1.y + c2.y * 0.6
	for i in BR_DIR.size():
		var c := d.dot(BR_DIR[i])
		if c < BR_COS[i]:
			continue
		var ang: float = BR_ANG[i]
		var t := acos(minf(c, 1.0)) / ang
		var H: float = BR_H[i]
		match BR_KIND[i]:
			BR_CRATER:
				if t < 1.0:
					off += (t * t - 1.0) * H
					shade -= (1.0 - t) * 1.2
				off += 0.28 * H * exp(-pow((t - 1.0) / 0.22, 2.0))
				shade += exp(-pow((t - 1.0) / 0.1, 2.0))
			BR_MESA:
				# plateau à falaises raides, bord irrégulier
				var e := t + NZ_EDGE.get_noise_3dv(p) * 0.08
				off += H * (1.0 - smoothstep(0.84, 1.0, e))
			BR_RIDGE:
				var sd := asin(clampf(d.dot(BR_AXIS[i]), -1.0, 1.0)) * RC / BR_W[i]
				off += H * exp(-sd * sd * 2.2) * (1.0 - smoothstep(0.65, 1.0, t))
	return Vector3(flatten(d, r + off * mr), clampf(shade * mr, -1.0, 1.0), mr)


func surf_point(d: Vector3) -> Vector3:
	return d * surf_eval(d).x - Vector3(0, RC, 0)


func gp(x: float, z: float, lift := 0.0) -> Vector3:
	var r := sqrt(x * x + z * z)
	var dir := Vector3.UP
	if r > 0.001:
		var th := minf(r / RC, PI)
		var s := sin(th)
		dir = Vector3(s * x / r, cos(th), s * z / r)
	return dir * (surf_eval(dir).x + lift) - Vector3(0, RC, 0)


# ---- ligne de vue : relief et rochers
func alt(P: Vector3) -> float:
	var v := P + Vector3(0, RC, 0)
	var L := v.length()
	return L - surf_eval(v / L).x


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


# normale réelle du sol sous un point, mesurée sur une échelle e (m)
func ground_normal(p: Vector3, e: float) -> Vector3:
	var u := up_at(p)
	var a := u.cross(Vector3.RIGHT if absf(u.x) < 0.9 else Vector3.FORWARD).normalized()
	var b := u.cross(a)
	var c := Vector3(0, RC, 0)
	var p1 := surf_point((p + a * e + c).normalized())
	var p2 := surf_point((p - a * e + c).normalized())
	var p3 := surf_point((p + b * e + c).normalized())
	var p4 := surf_point((p - b * e + c).normalized())
	var n := (p1 - p2).cross(p3 - p4).normalized()
	return n if n.dot(u) > 0.0 else -n


# verticale locale : normale de la forme lisse de l'astéroïde (sans dunes ni cratères).
# Radiale dans la calotte sphérique de la base ; ailleurs, perpendiculaire au sol même sur une forme allongée.
func up_at(p: Vector3) -> Vector3:
	var d := (p + Vector3(0, RC, 0)).normalized()
	if acos(clampf(d.y, -1.0, 1.0)) <= SH_TH0:
		return d
	var a := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.FORWARD).normalized()
	var b := d.cross(a)
	var h := 6.0 / RC
	var d1 := (d + a * h).normalized()
	var d2 := (d - a * h).normalized()
	var d3 := (d + b * h).normalized()
	var d4 := (d - b * h).normalized()
	var n := (d1 * radius_at(d1) - d2 * radius_at(d2)).cross(d3 * radius_at(d3) - d4 * radius_at(d4)).normalized()
	return n if n.dot(d) > 0.0 else -n


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
	make_gravity(dice)
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
	VUES.insert(0, {"nom": "Vue stratégique", "mode": 0, "abs": true, "cam": ctr + (upm * 3.0 + tow * 1.2 + Vector3(0.4, 0, 0)).normalized() * RC * (1.0 + 1.75 * ext), "look": ctr + upm * RC * 0.3, "el": 40.0, "az": 200.0, "earth": null, "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)})
	# recul adapté à l'étendue réelle de la forme (allongée, bilobée…)
	var ext_l := ext
	if SH_LOBE_R > 0.0:
		ext_l = maxf(ext, (lobe_center() - ctr).length() / RC + lobe_radius() / RC)
	VUES.append({"nom": "L'astéroïde entier", "mode": 0, "abs": true, "cam": ctr + Vector3(-1.6, 1.6, 2.6).normalized() * RC * (1.6 + 2.0 * ext_l), "look": ctr, "el": 30.0, "az": 210.0, "earth": null, "fus": "sol", "tint": Vector3(1.05, 1.0, 0.95)})
	rng.seed = 7
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shots" and i + 1 < args.size():
			shots_dir = args[i + 1]
		if args[i] == "--verif-chars":
			verif_chars = true
		if args[i] == "--autopilote":
			auto_test = true
	cam = Camera3D.new()
	cam.fov = 50
	cam.near = 0.1
	cam.far = 40000
	build_pipeline()
	smoke_tex = make_smoke()
	build_sky()
	build_base()
	war = preload("res://battle.gd").new()
	add_child(war)
	war.setup(self)
	build_shield()
	colony = preload("res://colony.gd").new()
	add_child(colony)
	colony.setup(self)
	strategy = preload("res://strategy.gd").new()
	add_child(strategy)
	strategy.setup(self, colony)
	factions = preload("res://factions.gd").new()
	add_child(factions)
	factions.setup(self, colony, strategy)
	survival = preload("res://survival.gd").new()
	add_child(survival)
	survival.setup(self, colony)
	if auto_test:
		strategy.bot_toggle()
	# le maillage du sol est construit en dernier : il intègre les zones aplanies sous les bâtiments et les tourelles
	build_terrain()
	build_hud()
	var bl := CanvasLayer.new()
	bl.layer = 0
	add_child(bl)
	bridge = preload("res://bridge.gd").new()
	bl.add_child(bridge)
	bridge.setup(self, colony)
	if shots_dir != "" and not OS.get_cmdline_user_args().has("--passerelle"):
		bridge.visible = false
		layout_screen()
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
		# style militaire de la base (d'après les images de référence : combinaisons kaki, visières dorées, tuyaux)
		"kaki":
			m.albedo_color = Color("4c5158"); m.metallic = 0.55; m.roughness = 0.55
		"kaki_clair":
			m.albedo_color = Color("737a83"); m.metallic = 0.5; m.roughness = 0.5
		"blinde":
			m.albedo_color = Color("2c3036"); m.metallic = 0.6; m.roughness = 0.55
		"orange_mil":
			m.albedo_color = Color("c4600f"); m.metallic = 0.1; m.roughness = 0.6
		"tuyau":
			m.albedo_color = Color("a9a59a"); m.metallic = 0.1; m.roughness = 0.65
		"visiere":
			m.albedo_color = Color("e8a020"); m.metallic = 0.75; m.roughness = 0.12
			m.emission_enabled = true; m.emission = Color("ffb43a"); m.emission_energy_multiplier = 0.35
		"visiere_verre":
			m.albedo_color = Color(0.95, 0.66, 0.14, 0.38); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.6; m.roughness = 0.1; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"noyau":
			m.albedo_color = Color("140800"); m.emission_enabled = true; m.emission = Color("ff7a1a"); m.emission_energy_multiplier = 5.0
		# industrie et spatioport (béton gris, marquages de danger, vitres vertes et rouges)
		"gris_dep":
			m.albedo_color = Color("5a6068"); m.metallic = 0.5; m.roughness = 0.55
		"tarmac":
			m.albedo_color = Color("1f2124"); m.roughness = 0.95
		"tarmac2":
			m.albedo_color = Color("26282b"); m.roughness = 0.95
		"danger":
			m.albedo_color = Color("c99a10"); m.metallic = 0.1; m.roughness = 0.6
		"vert":
			m.albedo_color = Color("041008"); m.emission_enabled = true; m.emission = Color("4dff8a"); m.emission_energy_multiplier = 2.2
		"rouge_vitre":
			m.albedo_color = Color("100202"); m.emission_enabled = true; m.emission = Color("ff3a2a"); m.emission_energy_multiplier = 2.5
	mats[name] = m
	return mats[name]


# style low-poly : matériau opaque converti en facettes mates (les transparents restent standard)
var LOWPOLY: Shader


func lowpoly_from(m: StandardMaterial3D) -> Material:
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return m
	if LOWPOLY == null:
		LOWPOLY = load("res://shaders/lowpoly.gdshader")
	var s := ShaderMaterial.new()
	s.shader = LOWPOLY
	s.set_shader_parameter("albedo", m.albedo_color)
	s.set_shader_parameter("metallic", m.metallic * 0.35)
	s.set_shader_parameter("roughness", maxf(m.roughness, 0.65))
	if m.emission_enabled:
		s.set_shader_parameter("emission", m.emission)
		s.set_shader_parameter("emission_energy", m.emission_energy_multiplier)
	s.set_meta("lowpoly", true)
	return s


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
	c.radial_segments = mini(seg, 24)
	c.rings = 1
	return mi(par, c, M(mat), pos, rot)


func sph(par: Node3D, mat: String, pos: Vector3, r: float, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = 24
	s.rings = 12
	return mi(par, s, M(mat), pos)


func strut(par: Node3D, mat: String, a: Vector3, b: Vector3, r: float, seg := 6) -> MeshInstance3D:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return null
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = L
	c.radial_segments = mini(seg, 10)
	c.rings = 1
	var m := mi(par, c, M(mat), (a + b) * 0.5)
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	m.basis = Basis(x, y, x.cross(y) * -1.0).orthonormalized()
	return m


# tube qui suit la surface : découpé en tronçons courts (une corde longue passerait sous le sol)
func link(B: Node3D, a: Vector2, b: Vector2, lift_a: float, lift_b: float, r: float, mat: String) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / 4.0)))
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		var m := strut(B, mat, gp(p0.x, p0.y, lerpf(lift_a, lift_b, t0)), gp(p1.x, p1.y, lerpf(lift_a, lift_b, t1)), r, 24)
		if m:
			m.set_meta("libre", true)


# passerelle plate qui suit la surface, en tronçons orientés selon la verticale locale
func walkway(B: Node3D, a: Vector2, b: Vector2, lift: float, w: float, h: float, mat: String) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / 4.0)))
	for i in n:
		var p0 := gp(a.lerp(b, float(i) / n).x, a.lerp(b, float(i) / n).y, lift)
		var p1 := gp(a.lerp(b, float(i + 1) / n).x, a.lerp(b, float(i + 1) / n).y, lift)
		var mid := (p0 + p1) * 0.5
		var bx := box(B, mat, mid, Vector3(w, h, p0.distance_to(p1) + 0.1))
		bx.basis = Basis.looking_at(p1 - p0, up_at(mid))
		bx.set_meta("libre", true)


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
	# ciel procédural : nébuleuse colorée et étoiles (shaders/sky.gdshader)
	var pano := ShaderMaterial.new()
	pano.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = pano
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_32
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
	# lumière d'appoint côté nuit (venant de l'opposé du soleil, sans ombre) : le relief reste lisible dans la partie sombre
	fill_light = DirectionalLight3D.new()
	fill_light.light_color = Color(0.5, 0.6, 0.85)
	fill_light.light_energy = 1.4
	fill_light.shadow_enabled = false
	add_child(fill_light)
	# planète de fond : géante gazeuse à bandes et à anneaux (comme sur les images de référence)
	earth = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1400
	sm.height = 2800
	sm.radial_segments = 64
	sm.rings = 32
	earth.mesh = sm
	var bands := Image.create(8, 256, false, Image.FORMAT_RGB8)
	var bn := FastNoiseLite.new()
	bn.frequency = 0.05
	for y in 256:
		var v := bn.get_noise_1d(y) * 0.5 + 0.5 + 0.25 * sin(y * 0.21)
		var c := Color("c79a6a").lerp(Color("f0d6a8"), clampf(v, 0.0, 1.0)).lerp(Color("8a5a3a"), clampf(sin(y * 0.09) * 0.5, 0.0, 1.0) * 0.5)
		for x in 8:
			bands.set_pixel(x, y, c)
	var em := StandardMaterial3D.new()
	em.albedo_texture = ImageTexture.create_from_image(bands)
	em.roughness = 1.0
	em.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	earth.material_override = em
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth.rotation = Vector3(0.35, 0.0, 0.28)
	add_child(earth)
	var ring := MeshInstance3D.new()
	var rq := PlaneMesh.new()
	rq.size = Vector2(1400 * 4.6, 1400 * 4.6)
	ring.mesh = rq
	var ri := Image.create(512, 1, false, Image.FORMAT_RGBA8)
	var rn := FastNoiseLite.new()
	rn.frequency = 0.08
	for x in 512:
		var r := x / 511.0
		var a := smoothstep(0.55, 0.6, r) * (1.0 - smoothstep(0.96, 1.0, r)) * (0.35 + 0.65 * (rn.get_noise_1d(x) * 0.5 + 0.5))
		if r > 0.78 and r < 0.81:
			a *= 0.15
		ri.set_pixel(x, 0, Color(0.85, 0.75, 0.62, a))
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/ring.gdshader")
	rm.set_shader_parameter("prof", ImageTexture.create_from_image(ri))
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth.add_child(ring)


# ================================================================ maillage de l'astéroïde : cube-sphère
# Un cube subdivisé dont chaque sommet est projeté sur la sphère (cube « sphérifié » : mailles régulières,
# pas de pincement aux pôles), puis placé à la hauteur donnée par surf_eval(). Les 6 faces sont calculées en parallèle.
const CUBE_N := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
var _faces: Array = []
var _mtx := Mutex.new()
var _pl_n := 128
var _pl_lobe := false


func cube_dir(f: int, u: float, v: float) -> Vector3:
	var n: Vector3 = CUBE_N[f]
	var a := Vector3(n.y, n.z, n.x)
	var b := n.cross(a)
	var p := n + a * u + b * v
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z
	return Vector3(p.x * sqrt(maxf(0.0, 1.0 - y2 * 0.5 - z2 * 0.5 + y2 * z2 / 3.0)),
		p.y * sqrt(maxf(0.0, 1.0 - z2 * 0.5 - x2 * 0.5 + z2 * x2 / 3.0)),
		p.z * sqrt(maxf(0.0, 1.0 - x2 * 0.5 - y2 * 0.5 + x2 * y2 / 3.0))).normalized()


# second lobe d'un astéroïde binaire : sphère bosselée et cratérisée
func lobe_eval(d: Vector3) -> Vector3:
	var lr := lobe_radius()
	var p := d * lr
	# lobe ellipsoïdal (proportions du modèle réel), dans le repère du corps
	var db := SH_ROT * d
	var e := SH_LOBE_ELL
	var rs := 1.0 / sqrt(db.x * db.x / (e.x * e.x) + db.y * db.y / (e.y * e.y) + db.z * db.z / (e.z * e.z))
	# raccord doux avec le corps principal : bourrelet du congé, relief atténué près du contact
	var r0 := lr * rs
	var ns := main_sd(lobe_center() + d * r0)
	var rw := 1.0 - neck_w(ns)
	var r := neck_solve(lobe_center(), d, r0, true) + r0 * 0.05 * NZ_DUNE.get_noise_3dv(p * 0.5) * rw
	var c1 := cell_crater(p + Vector3(400, 0, 0), NZ_CD, NZ_CV, 70.0)
	var c2 := cell_crater(p + Vector3(431, 7, 13), NZ_CD2, NZ_CV2, 22.0)
	return Vector3(r + (c1.x + c2.x * 0.8) * rw, clampf((c1.y + c2.y * 0.6) * rw, -1.0, 1.0), rw)


func _face_task(f: int) -> void:
	var N := _pl_n
	var W := N + 3
	var C := lobe_center() if _pl_lobe else Vector3(0, -RC, 0)
	var P := PackedVector3Array()
	P.resize(W * W)
	var S := PackedFloat32Array()
	S.resize(W * W)
	# forme lisse seule (sans relief) : sert à mesurer la pente du relief, pas celle de la forme générale
	var Q := PackedVector3Array()
	Q.resize(W * W)
	# grille avec une bordure d'un sommet : normales continues d'une face à l'autre
	for j in W:
		for i in W:
			var d := cube_dir(f, -1.0 + 2.0 * (i - 1) / N, -1.0 + 2.0 * (j - 1) / N)
			# facettes irrégulières : sommet décalé le long de la surface (il reste exactement sur le sol)
			d = facet_jitter(d, N)
			var e := lobe_eval(d) if _pl_lobe else surf_eval(d)
			P[j * W + i] = C + d * e.x
			S[j * W + i] = e.y
			Q[j * W + i] = C + d * (lobe_shape_r(d) if _pl_lobe else radius_at(d))
	var nv := (N + 1) * (N + 1)
	var V := PackedVector3Array()
	V.resize(nv)
	var NR := PackedVector3Array()
	NR.resize(nv)
	var UV := PackedVector2Array()
	UV.resize(nv)
	var CO := PackedVector2Array()
	CO.resize(nv)
	for j in N + 1:
		for i in N + 1:
			var k := (j + 1) * W + (i + 1)
			var o := j * (N + 1) + i
			var p := P[k]
			var nn := (P[k + 1] - P[k - 1]).cross(P[k + W] - P[k - W]).normalized()
			if nn.dot(p - C) < 0.0:
				nn = -nn
			var sn := (Q[k + 1] - Q[k - 1]).cross(Q[k + W] - Q[k - W]).normalized()
			if sn.dot(p - C) < 0.0:
				sn = -sn
			V[o] = p
			NR[o] = nn
			# coordonnées à plat près de la base seulement (loin : valeur hors des chemins)
			var q := Vector2(1e6, 1e6)
			if not _pl_lobe:
				var qq := planar_of((p - C).normalized())
				if qq.length() < 0.62 * PI * RC:
					q = qq
			UV[o] = q
			CO[o] = Vector2(S[k], 1.0 - nn.dot(sn))
	var I := PackedInt32Array()
	I.resize(N * N * 6)
	var w := 0
	for j in N:
		for i in N:
			var a := j * (N + 1) + i
			var b := a + 1
			var c := a + N + 1
			var dd := c + 1
			# sens horaire vu de l'extérieur (faces avant pour Godot) ; diagonale tirée au hasard (facettes moins régulières)
			if (((i * 73856093) ^ (j * 19349663) ^ (f * 83492791)) & 4) == 0:
				I[w] = a; I[w + 1] = c; I[w + 2] = b
				I[w + 3] = b; I[w + 4] = c; I[w + 5] = dd
			else:
				I[w] = a; I[w + 1] = c; I[w + 2] = dd
				I[w + 3] = a; I[w + 4] = dd; I[w + 5] = b
			w += 6
	_mtx.lock()
	_faces[f] = [V, NR, UV, CO, I]
	_mtx.unlock()


# facettes irrégulières (style astéroïde à facettes) : décale une direction du maillage le long de la surface,
# d'au plus ~0,4 maille, avec un bruit continu (le même sommet reçoit le même décalage sur deux faces voisines du cube)
var NZ_FACET: FastNoiseLite = null
func facet_jitter(d: Vector3, n: int) -> Vector3:
	if NZ_FACET == null:
		return d
	var fq := float(n) * 0.9
	var p := d * fq
	var jv := Vector3(NZ_FACET.get_noise_3dv(p), NZ_FACET.get_noise_3dv(p + Vector3(31.7, 0, 0)), NZ_FACET.get_noise_3dv(p + Vector3(0, 57.3, 0)))
	jv -= d * d.dot(jv)
	return (d + jv * (0.75 * PI * 0.5 / n)).normalized()


func planet_mesh(lobe: bool, n: int) -> ArrayMesh:
	_pl_lobe = lobe
	_pl_n = n
	_faces = [null, null, null, null, null, null]
	var tid := WorkerThreadPool.add_group_task(_face_task, 6)
	WorkerThreadPool.wait_for_group_task_completion(tid)
	var V := PackedVector3Array()
	var NR := PackedVector3Array()
	var UV := PackedVector2Array()
	var CO := PackedVector2Array()
	var I := PackedInt32Array()
	for f in 6:
		var fd: Array = _faces[f]
		var base := V.size()
		V.append_array(fd[0])
		NR.append_array(fd[1])
		UV.append_array(fd[2])
		CO.append_array(fd[3])
		var fi: PackedInt32Array = fd[4]
		for k in fi.size():
			fi[k] += base
		I.append_array(fi)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = NR
	arr[Mesh.ARRAY_TEX_UV] = UV
	arr[Mesh.ARRAY_TEX_UV2] = CO
	arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# texture de bruit en virgule flottante, raccordable sur ses bords (une texture 8 bits ferait des bords de pistes en escalier)
func float_noise_tex(n: int, freq: float) -> ImageTexture:
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	fn.fractal_octaves = 4
	var vals := PackedFloat32Array()
	vals.resize(n * n)
	var lo := INF
	var hi := -INF
	for y in n:
		var v := float(y) / n
		for x in n:
			var u := float(x) / n
			var a := fn.get_noise_2d(x, y)
			var b := fn.get_noise_2d(x - n, y)
			var c := fn.get_noise_2d(x, y - n)
			var d := fn.get_noise_2d(x - n, y - n)
			var s := lerpf(lerpf(a, b, u), lerpf(c, d, u), v)
			vals[y * n + x] = s
			lo = minf(lo, s)
			hi = maxf(hi, s)
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color((vals[y * n + x] - lo) / (hi - lo), 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func build_terrain() -> void:
	if NZ_FACET == null:
		NZ_FACET = FastNoiseLite.new()
		NZ_FACET.noise_type = FastNoiseLite.TYPE_VALUE
		NZ_FACET.frequency = 1.0
		NZ_FACET.fractal_type = FastNoiseLite.FRACTAL_NONE
		NZ_FACET.seed = 9
	var sh := load("res://shaders/terrain.gdshader")
	var nt := float_noise_tex(256, 0.024)
	# mailles d’environ 6 m : facettes visibles (style « astéroïde à facettes »)
	var bodies := [[false, clampi(int(PI * 0.5 * RC / 6.0), 54, 130)]]
	if SH_LOBE_R > 0.0 and not LOBE_FUSED:
		bodies.append([true, clampi(int(PI * 0.5 * lobe_radius() / 6.0), 32, 96)])
	for b in bodies:
		var lobe: bool = b[0]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("center", lobe_center() if lobe else Vector3(0, -RC, 0))
		m.set_shader_parameter("noise_tex", nt)
		terr_mats.append(m)
		var t := MeshInstance3D.new()
		t.mesh = planet_mesh(lobe, b[1])
		t.material_override = m
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)


func lobe_center() -> Vector3:
	return Vector3(0, -RC, 0) + SH_ROT.transposed() * (SH_LOBE_C * RC / SH_POLE)


func lobe_radius() -> float:
	return SH_LOBE_R * RC / SH_POLE


# rayon de l'ellipsoïde du lobe (sans relief ni congé)
func lobe_raw(d: Vector3) -> float:
	var db := SH_ROT * d
	var e := SH_LOBE_ELL
	var lump := 1.0 + NZ_LUMP.get_noise_3dv(d * 1.3 + Vector3(7.0, 3.0, -5.0)) * LUMP_A * 1.2
	return lobe_radius() * lump / sqrt(db.x * db.x / (e.x * e.x) + db.y * db.y / (e.y * e.y) + db.z * db.z / (e.z * e.z))


# rayon de la forme lisse du lobe, congé compris (sans relief)
func lobe_shape_r(d: Vector3) -> float:
	return neck_solve(lobe_center(), d, lobe_raw(d), true)


# volume du lobe (m³), pour la masse totale
func lobe_volume() -> float:
	var lr := lobe_radius()
	return 4.0 / 3.0 * PI * lr * lr * lr * SH_LOBE_ELL.x * SH_LOBE_ELL.y * SH_LOBE_ELL.z


# ================================================================ la base
func build_base() -> void:
	var B := Node3D.new()
	add_child(B)
	base_root = B
	# base de style militaire (kaki, blindage, visières dorées, tuyaux) ; coordonnées avant la réduction BSC
	command_post(B)
	corridor(B, Vector3(9, 0, 0), Vector3(58, 0, 0))
	corridor(B, Vector3(-9, 0, 0), Vector3(-56, 0, 0))
	corridor(B, Vector3(0, 0, -9), Vector3(0, 0, -56))
	corridor(B, Vector3(0, 0, 9), Vector3(0, 0, 40))
	reactor(B, Vector2(68, 0))
	tank_farm(B, Vector2(-70, 0))
	radar_tower(B, Vector2(-45, -40))
	# surface industrielle (remake K-240) : seulement l'industrie polluante, l'extraction et le stockage
	refinery(B, Vector2(118, -70), 0.3)
	link(B, Vector2(76, -6), Vector2(104, -56), 2.0, 2.0, 0.8, "tuyau")
	fission_smr(B, Vector2(-175, -95))
	link(B, Vector2(-80, -8), Vector2(-160, -86), 1.6, 1.6, 0.7, "danger")
	mass_driver(B, Vector2(150, 60), -0.9)
	storage_silos(B, Vector2(-120, 50))
	link(B, Vector2(-80, 8), Vector2(-108, 40), 1.6, 1.6, 0.6, "tuyau")
	# spatioport : grand, du côté opposé au front
	spaceport(B, Vector2(0, -175))
	# deux hangars, portes tournées vers le front : les défenseurs y déploient leurs unités
	hangar(B, Vector2(-90, 150), -PI / 2)
	hangar(B, Vector2(140, 150), -PI / 2)
	for e in [[0.0, 52.0, 2.6], [22.0, 60.0, 3.4], [38.0, 48.0, 2.2], [-12.0, 66.0, 3.0]]:
		drill_rig(B, Vector2(e[0], e[1]), e[2])
	roads(B)
	rocks(B)
	# chaque objet est redressé selon la verticale locale de la sphère
	# (sauf les pièces « libres », déjà orientées : tubes de liaison, passerelles, routes)
	for c in B.get_children():
		if c is Node3D and not (c is MultiMeshInstance3D) and not c.has_meta("libre"):
			var n3: Node3D = c
			if n3.position.length() > 3.0:
				n3.basis = Basis(Quaternion(n3.basis.y.normalized(), up_at(n3.position))) * n3.basis
	# bâtiments réduits de moitié (la base entière est ramenée vers son centre)
	for c in B.get_children():
		if c is Node3D and not (c is MultiMeshInstance3D):
			var n4: Node3D = c
			var P := n4.position
			var q := planar(P)
			var np := gp(q.x * BSC, q.y * BSC, alt(P) * BSC)
			n4.basis = Basis(Quaternion(up_at(P), up_at(np))) * n4.basis.scaled(Vector3.ONE * BSC)
			n4.position = np
	# collisions avec le sol : aucun objet ne traverse le terrain, socles et fondations comblent les vides
	settle(B)
	# le sol est aplani sous chaque bâtiment à socle, exactement à la hauteur de sa base
	for c in B.get_children():
		if c is Node3D and c.has_meta("socle"):
			var nb: Node3D = c
			add_flat_zone(nb.position, float(c.get_meta("socle")) * nb.basis.get_scale().x * 1.08)
	# portes des hangars (au sol, devant la porte) : points de sortie des unités de la colonie
	HANGARS.clear()
	for c in B.get_children():
		if c.has_meta("hangar"):
			var hn: Node3D = c
			var dp := hn.global_transform * Vector3(36, 0, 0)
			HANGARS.append({"door": surf_point((dp + Vector3(0, RC, 0)).normalized()), "node": hn})
	for r in rockets:
		if r.pad != null:
			var pad: Node3D = r.pad
			r.g.basis = pad.basis * Basis(Vector3.UP, float(r.get("yaw", 0.0)))
			r.g.position = pad.position + pad.basis * Vector3(0, float(r.get("pad_off", 1.4)), 0)
		r.base = (r.g as Node3D).position
	peaks()
	# moissonneuses-racleuses : engins mobiles qui tournent sur les champs de régolithe autour de la base
	for k in 5:
		add_harvester()


const HARV_FIELDS := [Vector2(-150, -40), Vector2(-120, 70), Vector2(110, -120), Vector2(150, 20), Vector2(-60, -160), Vector2(-185, 20), Vector2(175, -60), Vector2(30, -170)]


# nouvelle moissonneuse-racleuse sur le champ de régolithe suivant
func add_harvester() -> void:
	var k := harvesters.size()
	var hv := harvester_mesh()
	hv.scale = Vector3.ONE * 0.8
	add_child(hv)
	var cen: Vector2 = HARV_FIELDS[k % HARV_FIELDS.size()] + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
	harvesters.append({"n": hv, "c": cen, "r": rng.randf_range(22.0, 34.0), "a": rng.randf() * TAU, "w": rng.randf_range(0.04, 0.07) * (1.0 if k % 2 == 0 else -1.0)})
	update_harvesters(0.0)


func update_harvesters(dt: float) -> void:
	for h in harvesters:
		h.a += h.w * dt
		var c: Vector2 = h.c
		var q: Vector2 = c + Vector2(cos(h.a), sin(h.a)) * float(h.r)
		var q2: Vector2 = c + Vector2(cos(h.a + signf(h.w) * 0.05), sin(h.a + signf(h.w) * 0.05)) * float(h.r)
		var p := gp(q.x, q.y)
		var p2 := gp(q2.x, q2.y)
		var u := up_at(p)
		var f := p2 - p
		f = (f - u * f.dot(u)).normalized()
		var n: Node3D = h.n
		n.basis = Basis(f, u, f.cross(u)).scaled(Vector3.ONE * 0.8)
		n.position = p


func update_plumes(dt: float) -> void:
	for pl in plumes:
		pl.k = fmod(pl.k + dt * 0.12, 1.0)
		var n: Node3D = pl.n
		var k: float = pl.k
		n.position = (pl.base as Vector3) + Vector3(sin(k * 7.0 + pl.base.x) * 2.0, k * float(pl.rise), cos(k * 5.0) * 2.0)
		n.scale = Vector3.ONE * lerpf(1.0, 3.0, k)


# ================================================================ collisions avec le sol
# points de contrôle d'un maillage (repère local) : anneaux pour les formes rondes, coins pour le reste
func mesh_probe(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	var bb := mesh.get_aabb()
	var c := bb.get_center()
	var e := bb.size * 0.5
	if mesh is CylinderMesh or mesh is SphereMesh or mesh is TorusMesh:
		for ly in [-1.0, 0.0, 1.0]:
			for k in 8:
				var a := TAU * k / 8.0
				out.append(c + Vector3(cos(a) * e.x, ly * e.y, sin(a) * e.z))
		out.append(c - Vector3(0, e.y, 0))
	else:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append(c + Vector3(sx * e.x, sy * e.y, sz * e.z))
		for sx in [-1.0, 1.0]:
			out.append(c + Vector3(sx * e.x, -e.y, 0))
			out.append(c + Vector3(0, -e.y, sx * e.z))
		out.append(c - Vector3(0, e.y, 0))
	return out


func is_solid(m: MeshInstance3D) -> bool:
	if not m.visible or m.mesh == null:
		return false
	var mt := m.material_override
	if mt is ShaderMaterial and not mt.has_meta("lowpoly"):
		return false
	if mt is StandardMaterial3D:
		var s: StandardMaterial3D = mt
		if s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or s.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			return false
	return true


func collect_probes(n: Node, pts: PackedVector3Array) -> void:
	if n is MeshInstance3D and is_solid(n):
		var xf: Transform3D = (n as MeshInstance3D).global_transform
		for p in mesh_probe((n as MeshInstance3D).mesh):
			pts.append(xf * p)
	for ch in n.get_children():
		collect_probes(ch, pts)


# pose de nouveaux enfants de la base (construits en cours de partie) : redressement, réduction BSC, collisions
func place_new(B: Node3D, from_idx: int) -> Array:
	var out: Array = []
	for i in range(from_idx, B.get_child_count()):
		var c := B.get_child(i)
		if not (c is Node3D) or c is MultiMeshInstance3D:
			continue
		var n: Node3D = c
		if not n.has_meta("libre") and n.position.length() > 3.0:
			n.basis = Basis(Quaternion(n.basis.y.normalized(), up_at(n.position))) * n.basis
		var P := n.position
		var q := planar(P)
		var np := gp(q.x * BSC, q.y * BSC, alt(P) * BSC)
		n.basis = Basis(Quaternion(up_at(P), up_at(np))) * n.basis.scaled(Vector3.ONE * BSC)
		n.position = np
		settle_node(n)
		out.append(n)
	return out


func settle(B: Node3D) -> void:
	for c in B.get_children():
		settle_node(c)


func settle_node(c: Node) -> void:
	if not (c is Node3D) or c is MultiMeshInstance3D or c is Light3D or c.has_meta("fusee"):
		return
	var n: Node3D = c
	var pts := PackedVector3Array()
	collect_probes(n, pts)
	if pts.is_empty():
		return
	var amin := INF
	for p in pts:
		amin = minf(amin, alt(p))
	# l'objet traverse le sol : on le soulève jusqu'à ce que son point le plus bas touche le terrain
	if amin < 0.0:
		n.position += up_at(n.position) * (0.02 - amin)
	var sc := n.basis.get_scale().x
	if n.has_meta("socle"):
		var r: float = n.get_meta("socle")
		var gap := alt(n.global_position)
		for k in 24:
			var a := TAU * k / 24.0
			gap = maxf(gap, alt(n.global_transform * Vector3(cos(a) * r, 0, sin(a) * r)))
		var h := (maxf(gap, 0.0) + 0.8) / sc
		var so := cyl(n, "beton", Vector3(0, 0.05 - h * 0.5, 0), r * 0.98, h, r * 1.02, Vector3.ZERO, 48)
		so.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n.has_meta("pieds"):
		for f in n.get_meta("pieds"):
			var fv: Vector3 = f
			var h := (maxf(alt(n.global_transform * fv), 0.0) + 0.6) / sc
			cyl(n, "beton", fv + Vector3(0, 0.3 / sc - h * 0.5, 0), 1.0, h, 1.3, Vector3.ZERO, 16)


# position à plat (x, z) d'un point de la sphère
func planar(P: Vector3) -> Vector2:
	var v := P + Vector3(0, RC, 0)
	var d := v.normalized()
	var th := acos(clampf(d.y, -1.0, 1.0))
	var sh := sqrt(d.x * d.x + d.z * d.z)
	if sh < 1e-6:
		return Vector2.ZERO
	return Vector2(d.x, d.z) / sh * th * RC


# ================================================================ décor du désert (style dessin animé)
# rochers mauves arrondis à sommet plat (facettes), agaves bleues, cactus, cailloux, zones de graviers
var toon_sh: Shader


func toon_mat(col := Color.WHITE) -> ShaderMaterial:
	if toon_sh == null:
		toon_sh = load("res://shaders/toon.gdshader")
	var m := ShaderMaterial.new()
	m.shader = toon_sh
	m.set_shader_parameter("base", col)
	return m


func flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	var mid := (a + b + c) / 3.0
	if n.dot(Vector3(mid.x, maxf(mid.y, 0.0) * 0.5, mid.z)) < 0.0:
		n = -n
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)


# rocher « mesa » : flancs gris en facettes, épaulement arrondi, sommet plat plus clair
func mesa_mesh(dice: RandomNumberGenerator) -> ArrayMesh:
	var K := 9
	var rad: Array[float] = []
	for i in K:
		rad.append(dice.randf_range(0.82, 1.0))
	var rings := [[-0.7, 1.1], [0.0, 1.0], [0.55, 0.93], [0.76, 0.8], [0.86, 0.6]]
	var cols := [Color("3a3836"), Color("4a4744"), Color("58554f"), Color("6a665f"), Color("85807a")]
	var R: Array = []
	for r in rings:
		var ring: Array[Vector3] = []
		for i in K:
			var a := TAU * i / K
			ring.append(Vector3(cos(a) * rad[i] * r[1], r[0] + (dice.randf_range(-0.03, 0.03) if r[0] > 0.5 else 0.0), sin(a) * rad[i] * r[1] * 0.85))
		R.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in R.size() - 1:
		var col: Color = cols[ri + 1]
		for i in K:
			var j := (i + 1) % K
			var a: Vector3 = R[ri][i]
			var b: Vector3 = R[ri][j]
			var c: Vector3 = R[ri + 1][j]
			var d: Vector3 = R[ri + 1][i]
			flat_tri(st, a, b, c, col, col, col)
			flat_tri(st, a, c, d, col, col, col)
	var top: Array = R[R.size() - 1]
	var tc := Vector3(0, 0.88, 0)
	for i in K:
		var j := (i + 1) % K
		flat_tri(st, tc, top[i], top[j], cols[4], cols[4], cols[4])
	var m := st.commit()
	m.surface_set_material(0, toon_mat())
	return m


# caillou à facettes (low-poly) : sphère grossière déformée, faces en aplats de gris, plus clair au sommet
func rock_mesh(dice: RandomNumberGenerator) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 7
	sm.rings = 4
	var arr := sm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	# même déformation pour les sommets confondus (couture de la sphère) : pas de trou
	var off := {}
	var sq := Vector3(dice.randf_range(1.0, 1.4), dice.randf_range(0.5, 0.8), dice.randf_range(0.8, 1.1))
	for i in vs.size():
		var key := Vector3i((vs[i] * 1000.0).round())
		if not off.has(key):
			off[key] = dice.randf_range(0.8, 1.15)
		var v: Vector3 = vs[i] * float(off[key]) * sq
		v.y = maxf(v.y, -0.25)
		vs[i] = v
	var cols := [Color("44413d"), Color("57534d"), Color("6d6962"), Color("8a857d")]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := vs[idx[t]]
		var b := vs[idx[t + 1]]
		var c := vs[idx[t + 2]]
		if (b - a).cross(c - a).length() < 1e-5:
			continue
		var h := ((a + b + c) / 3.0).y
		var col: Color = cols[clampi(int((h + 0.3) / 0.28) + dice.randi_range(-1, 0), 0, 3)]
		flat_tri(st, a, b, c, col, col, col)
	var m := st.commit()
	m.surface_set_material(0, toon_mat())
	return m


func pebble_mesh() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.3
	s.radial_segments = 7
	s.rings = 4
	return s


func mm_add(mesh: Mesh, xf: Array, mat: Material = null, shadow := false) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if mat != null:
		inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func ground_xf(q: Vector2, sc: Vector3, yaw: float, sink := 0.0) -> Transform3D:
	var g := gp(q.x, q.y, -sink)
	var b := Basis(Quaternion(Vector3.UP, up_at(g))) * Basis(Vector3.UP, yaw)
	return Transform3D(b * Basis.from_scale(sc), g)


func in_lobe(g: Vector3, margin := 0.0) -> bool:
	return SH_LOBE_R > 0.0 and not LOBE_FUSED and g.distance_to(lobe_center()) < lobe_radius() + margin


func peaks() -> void:
	var dice := RandomNumberGenerator.new()
	dice.randomize()
	var meshes := []
	for k in 4:
		meshes.append(mesa_mesh(dice))
	var xf_by := [[], [], [], []]
	var pr: Array[float] = []
	var pg: Array[Vector3] = []
	var ksc := clampf(RC / 350.0, 0.7, 1.3)
	var nclu := clampi(int(4.0 * PI * RC * RC / 9000.0), 24, 110)
	var placed := 0
	var tries := 0
	while placed < nclu and tries < 6000:
		tries += 1
		var c := planar_of(rdir(dice))
		if relief_mask(c.x, c.y) < 0.5:
			continue
		placed += 1
		var hmax := dice.randf_range(5.0, 22.0) * ksc
		for k in dice.randi_range(1, 4):
			var q := c + Vector2(dice.randf_range(-1, 1), dice.randf_range(-1, 1)) * hmax * 1.4
			if relief_mask(q.x, q.y) < 0.4:
				continue
			var h := hmax * dice.randf_range(0.45, 1.0)
			var wdt := h * dice.randf_range(0.9, 1.6)
			var g0 := gp(q.x, q.y)
			if in_lobe(g0, 2.0):
				continue
			# rochers sans chevauchement entre eux ni avec les abris du champ de bataille
			var rb := wdt * 0.9
			var hit := false
			for k2 in pg.size():
				if pg[k2].distance_to(g0) < rb + pr[k2]:
					hit = true
					break
			if hit or cover_near(g0, rb) != null:
				continue
			pr.append(rb)
			pg.append(g0)
			xf_by[dice.randi() % 4].append(ground_xf(q, Vector3(wdt, h, wdt), dice.randf() * TAU))
	for k in 4:
		mm_add(meshes[k], xf_by[k], null, true)
	decor(dice)


func decor(dice: RandomNumberGenerator) -> void:
	var area := 4.0 * PI * RC * RC
	var ag := [rock_mesh(dice), rock_mesh(dice), rock_mesh(dice)]
	var xa := [[], [], []]
	var xc := []
	var xp_o := []
	var xp_b := []
	var xg := []
	var free_spot := func(q: Vector2, min_r: float, rad: float) -> bool:
		if q.length() < min_r:
			return false
		var g := gp(q.x, q.y)
		return not in_lobe(g) and cover_near(g, rad) == null
	# cailloux à facettes (petits) et blocs (plus gros, avec ombre)
	var n_ag := clampi(int(area / 900.0), 300, 1600)
	for i in n_ag * 2:
		if xa[0].size() + xa[1].size() + xa[2].size() >= n_ag:
			break
		var q := planar_of(rdir(dice))
		if not free_spot.call(q, 140.0, 1.5):
			continue
		var s := dice.randf_range(0.35, 1.1)
		xa[dice.randi() % 3].append(ground_xf(q, Vector3.ONE * s, dice.randf() * TAU, s * 0.2))
	for i in n_ag / 6:
		var q := planar_of(rdir(dice))
		if not free_spot.call(q, 160.0, 1.0):
			continue
		var sb := dice.randf_range(1.0, 2.2)
		xc.append(ground_xf(q, Vector3.ONE * sb, dice.randf() * TAU, sb * 0.2))
	# cailloux épars
	var n_pb := clampi(int(area / 250.0), 800, 5000)
	for i in n_pb:
		var q := planar_of(rdir(dice))
		if q.length() < 90.0:
			continue
		var s := dice.randf_range(0.15, 0.55)
		var xf := ground_xf(q, Vector3(s, s, s * dice.randf_range(0.7, 1.3)), dice.randf() * TAU, s * 0.25)
		(xp_o if dice.randf() < 0.6 else xp_b).append(xf)
	# zones de graviers : amas de pierres grises et de cailloux à facettes
	var n_gr := clampi(int(area / 20000.0), 20, 90)
	for i in n_gr:
		var c := planar_of(rdir(dice))
		if c.length() < 150.0:
			continue
		var rz := dice.randf_range(6.0, 14.0)
		for k in dice.randi_range(10, 22):
			var q := c + Vector2(dice.randf_range(-1, 1), dice.randf_range(-1, 1)) * rz
			var s := dice.randf_range(0.3, 1.1)
			xg.append(ground_xf(q, Vector3(s * 1.3, s * 0.6, s), dice.randf() * TAU, s * 0.15))
		for k in dice.randi_range(2, 6):
			var q := c + Vector2(dice.randf_range(-1, 1), dice.randf_range(-1, 1)) * rz
			xa[dice.randi() % 3].append(ground_xf(q, Vector3.ONE * dice.randf_range(0.3, 0.7), dice.randf() * TAU, 0.08))
	for k in 3:
		mm_add(ag[k], xa[k])
	mm_add(rock_mesh(dice), xc, null, true)
	var pm := pebble_mesh()
	mm_add(pm, xp_o, toon_mat(Color("6a6660")))
	mm_add(pm, xp_b, toon_mat(Color("45423e")))
	mm_add(pm, xg, toon_mat(Color("8c877f")))


# ================================================================ la base : style militaire
# Kaki olive, plaques blindées gris acier, bandes orange, vitres dorées façon visière de casque,
# tuyaux annelés blanc et orange, feux rouges (d'après les images de référence de l'utilisateur).

# tuyau souple entre deux points (repère du parent), qui pend un peu, bagues orange
func hose(par: Node3D, a: Vector3, b: Vector3, sag: float, r := 0.18) -> void:
	var n := 8
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		strut(par, "orange_mil" if i % 4 == 2 else "tuyau", prev, p, r)
		prev = p


# plaque de blindage inclinée sur une face (angle a autour du bâtiment, rayon rr)
func armor_plate(par: Node3D, a: float, rr: float, y: float, size: Vector3, tilt: float, mat := "kaki_clair") -> void:
	var pl := box(par, mat, Vector3(cos(a) * rr, y, sin(a) * rr), size)
	pl.rotation = Vector3(0, -a, tilt)


# poste de commandement : bunker octogonal à flancs blindés, coupole-visière, mât et radar
func command_post(B: Node3D) -> void:
	var g := Node3D.new()
	g.position = gp(0, 0, -0.3)
	g.set_meta("socle", 9.8)
	B.add_child(g)
	cyl(g, "blinde", Vector3(0, 0.6, 0), 9.4, 1.2, 9.8, Vector3.ZERO, 8)
	cyl(g, "kaki", Vector3(0, 3.6, 0), 7.2, 4.8, 8.6, Vector3.ZERO, 8)
	cyl(g, "orange_mil", Vector3(0, 1.75, 0), 8.32, 0.35, 8.36, Vector3.ZERO, 8)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		armor_plate(g, a, 7.75, 3.7, Vector3(0.35, 3.2, 3.4), 0.28)
		# fentes de visée dorées
		armor_plate(g, a, 7.2, 5.4, Vector3(0.2, 0.45, 2.2), 0.28, "visiere")
	cyl(g, "blinde", Vector3(0, 6.25, 0), 7.3, 0.5, 7.3, Vector3.ZERO, 8)
	# coupole d'observation : visière dorée dans un anneau blindé
	cyl(g, "blinde", Vector3(0, 6.8, 0), 4.2, 0.8, 4.4, Vector3.ZERO, 16)
	sph(g, "visiere", Vector3(0, 7.2, 0), 3.4, true)
	for i in 4:
		var a := TAU * i / 4.0
		strut(g, "kaki_clair", Vector3(cos(a) * 3.5, 7.2, sin(a) * 3.5), Vector3(cos(a) * 1.2, 10.4, sin(a) * 1.2), 0.18)
	# mât d'antenne et petit radar
	cyl(g, "blinde", Vector3(5.2, 9.6, 2.0), 0.22, 6.5)
	beacon(g, Vector3(5.2, 13.0, 2.0))
	cyl(g, "kaki_clair", Vector3(-5.0, 8.4, -2.4), 1.9, 0.35, 0.35, Vector3(0.55, 0.4, 0), 16)
	cyl(g, "blinde", Vector3(-5.0, 7.3, -2.4), 0.3, 1.6)
	# porte blindée
	box(g, "blinde", Vector3(8.55, 1.9, 0), Vector3(0.7, 2.8, 2.6))
	box(g, "orange_mil", Vector3(8.95, 3.45, 0), Vector3(0.1, 0.3, 2.6))
	sph(g, "rouge", Vector3(8.95, 3.9, 1.0), 0.18)
	# tuyaux le long des flancs
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		hose(g, Vector3(cos(a) * 8.9, 1.3, sin(a) * 8.9), Vector3(cos(a + 0.5) * 7.4, 5.8, sin(a + 0.5) * 7.4), -0.7, 0.2)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4
		sph(g, "rouge", Vector3(cos(a) * 7.0, 6.6, sin(a) * 7.0), 0.2)
	lamp(g, Vector3(11, 3, 0), Color("ffb060"), 3.0, 22)


# couloir blindé de a vers b (selon x ou z), en tronçons de 2 m posés sur la sphère
func corridor(B: Node3D, a: Vector3, b: Vector3) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var L := a.distance_to(b)
	var dir := (b - a).normalized()
	var side_v := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var steps := int(L / 2.0)
	for i in steps:
		var p := a + dir * (i * 2.0 + 1.0)
		var g := Node3D.new()
		g.position = gp(p.x, p.z)
		B.add_child(g)
		var sz := Vector3(2.04, 3.2, 4.2) if along_x else Vector3(4.2, 3.2, 2.04)
		var roof := Vector3(2.04, 0.35, 3.0) if along_x else Vector3(3.0, 0.35, 2.04)
		var strip := Vector3(2.04, 0.28, 0.06) if along_x else Vector3(0.06, 0.28, 2.04)
		box(g, "blinde", Vector3(0, 0.3, 0), sz * Vector3(1, 0.19, 1) + side_v * 0.4)
		box(g, "kaki", Vector3(0, 2.2, 0), sz)
		box(g, "kaki_clair", Vector3(0, 3.95, 0), roof)
		for s: float in [-1.0, 1.0]:
			box(g, "orange_mil", Vector3(0, 1.2, 0) + side_v * s * 2.13, strip)
		# câble sur le toit
		strut(g, "tuyau", Vector3(0, 4.25, 0) + side_v * 1.1 - dir * 1.02, Vector3(0, 4.25, 0) + side_v * 1.1 + dir * 1.02, 0.14)
		if i % 4 == 0:
			box(g, "blinde", Vector3(0, 2.25, 0), (Vector3(0.5, 3.8, 4.7) if along_x else Vector3(4.7, 3.8, 0.5)))
		if i % 15 == 8:
			# sas : module plus large avec visières et feu
			box(g, "kaki", Vector3(0, 2.6, 0), Vector3(2.04, 4.6, 7.0) if along_x else Vector3(7.0, 4.6, 2.04))
			for s: float in [-1.0, 1.0]:
				box(g, "visiere", Vector3(0, 3.4, 0) + side_v * s * 3.52, strip * Vector3(0.8, 2.0, 1.0))
			sph(g, "rouge", Vector3(0, 5.0, 0) + side_v * 3.0, 0.2)
			lamp(g, Vector3(0, 2.0, 0) + side_v * 5.0, Color("ffb060"), 2.0, 14)


# réacteur : cylindre à ailettes de refroidissement, cœur orange lumineux
func reactor(B: Node3D, c: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(c.x, c.y, -0.3)
	g.set_meta("socle", 8.8)
	B.add_child(g)
	cyl(g, "blinde", Vector3(0, 0.6, 0), 8.4, 1.2, 8.8, Vector3.ZERO, 12)
	cyl(g, "kaki", Vector3(0, 4.7, 0), 5.8, 7.2, 6.2, Vector3.ZERO, 12)
	cyl(g, "orange_mil", Vector3(0, 2.0, 0), 6.15, 0.4, 6.18, Vector3.ZERO, 12)
	for i in 12:
		var a := TAU * i / 12.0
		var f := box(g, "kaki_clair", Vector3(cos(a) * 6.5, 4.8, sin(a) * 6.5), Vector3(1.6, 6.0, 0.28))
		f.rotation = Vector3(0, -a, 0)
	for i in 6:
		var a := TAU * (i + 0.5) / 6.0
		armor_plate(g, a, 5.9, 6.6, Vector3(0.15, 0.5, 1.6), 0.05, "visiere")
	cyl(g, "blinde", Vector3(0, 8.7, 0), 4.6, 1.0, 5.6, Vector3.ZERO, 12)
	cyl(g, "noyau", Vector3(0, 9.3, 0), 2.4, 0.4, -1.0, Vector3.ZERO, 24)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4
		hose(g, Vector3(cos(a) * 5.0, 9.0, sin(a) * 5.0), Vector3(cos(a) * 8.0, 1.3, sin(a) * 8.0), -1.0, 0.28)
		cyl(g, "blinde", Vector3(cos(a) * 8.0, 10.0, sin(a) * 8.0), 0.15, 2.4)
		beacon(g, Vector3(cos(a) * 8.0, 11.3, sin(a) * 8.0))
	lamp(g, Vector3(0, 11, 0), Color("ff8a30"), 4.0, 24)


# réservoir sphérique dans une cage, avec bande orange et vanne
func fuel_tank(B: Node3D, c: Vector2, R: float) -> Node3D:
	var g := Node3D.new()
	g.position = gp(c.x, c.y, -0.3)
	g.set_meta("socle", R + 1.2)
	B.add_child(g)
	cyl(g, "blinde", Vector3(0, 0.5, 0), R + 0.9, 1.0, R + 1.2, Vector3.ZERO, 12)
	sph(g, "kaki", Vector3(0, R + 1.0, 0), R)
	cyl(g, "orange_mil", Vector3(0, R + 1.0, 0), R + 0.05, 0.45, -1.0, Vector3.ZERO, 32)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4
		strut(g, "blinde", Vector3(cos(a) * (R + 0.6), 1.0, sin(a) * (R + 0.6)), Vector3(cos(a) * (R * 0.75), R * 1.9 + 1.0, sin(a) * (R * 0.75)), 0.2)
	cyl(g, "blinde", Vector3(0, R * 2.0 + 1.2, 0), 0.8, 0.6)
	box(g, "blinde", Vector3(R + 0.9, 1.6, 0), Vector3(1.2, 1.2, 1.2))
	sph(g, "rouge", Vector3(0, R * 2.0 + 1.7, 0), 0.2)
	return g


func tank_farm(B: Node3D, c: Vector2) -> void:
	var spots := [[Vector2(0, 0), 4.6], [Vector2(-12, 7), 3.8], [Vector2(-11, -8), 4.2]]
	for k in spots.size():
		var o: Vector2 = spots[k][0]
		fuel_tank(B, c + o, spots[k][1])
	link(B, c + Vector2(-5, 1), c + Vector2(-8, 4), 1.4, 1.4, 0.35, "tuyau")
	link(B, c + Vector2(-5, -1), c + Vector2(-7, -4), 1.4, 1.4, 0.35, "tuyau")


# tour radar : fût blindé à huit pans, plate-forme et antenne inclinée
func radar_tower(B: Node3D, p: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y, -0.3)
	g.set_meta("socle", 4.4)
	B.add_child(g)
	cyl(g, "blinde", Vector3(0, 0.5, 0), 4.0, 1.0, 4.4, Vector3.ZERO, 8)
	cyl(g, "kaki", Vector3(0, 8.0, 0), 1.5, 14.0, 2.4, Vector3.ZERO, 8)
	for y: float in [4.0, 9.0, 13.0]:
		cyl(g, "orange_mil", Vector3(0, y, 0), 2.45 - y * 0.065, 0.35, -1.0, Vector3.ZERO, 8)
	cyl(g, "kaki_clair", Vector3(0, 15.3, 0), 3.0, 0.6, 3.0, Vector3.ZERO, 8)
	box(g, "visiere", Vector3(0, 16.3, 0), Vector3(2.2, 1.2, 2.2))
	var dish := Node3D.new()
	dish.position = Vector3(0, 18.6, 0)
	dish.rotation = Vector3(0.7, rng.randf() * TAU, 0)
	g.add_child(dish)
	cyl(dish, "kaki_clair", Vector3(0, 0, 0), 4.2, 0.6, 1.0, Vector3.ZERO, 16)
	strut(dish, "blinde", Vector3(0, 0, 0), Vector3(0, 3.0, 0), 0.12)
	sph(dish, "rouge", Vector3(0, 3.1, 0), 0.22)
	hose(g, Vector3(1.4, 14.5, 0.6), Vector3(3.6, 1.0, 0.6), 0.6, 0.15)
	beacon(g, Vector3(-2.6, 16.2, 0))


# foreuse minière : tour en treillis kaki, trémie, tige de forage, poussière
func drill_rig(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y, -0.2)
	g.rotation.y = yaw
	g.set_meta("socle", 5.0)
	B.add_child(g)
	box(g, "blinde", Vector3(0, 0.5, 0), Vector3(7.0, 1.0, 7.0))
	box(g, "kaki", Vector3(0, 2.6, 0), Vector3(5.0, 3.2, 5.0))
	box(g, "orange_mil", Vector3(0, 1.4, 0), Vector3(5.06, 0.3, 5.06))
	box(g, "visiere", Vector3(2.53, 3.2, 0), Vector3(0.08, 0.6, 2.4))
	var legs := []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			legs.append([Vector3(sx * 2.2, 4.2, sz * 2.2), Vector3(sx * 0.6, 15.0, sz * 0.6)])
	for l in legs:
		strut(g, "kaki_clair", l[0], l[1], 0.2)
	for s in 4:
		var t0 := s / 4.0
		var t1 := (s + 1) / 4.0
		for i in 4:
			var a: Array = legs[i]
			var b: Array = legs[[1, 3, 0, 2][i]]
			strut(g, "blinde", a[0].lerp(a[1], t0), b[0].lerp(b[1], t1), 0.08)
	cyl(g, "blinde", Vector3(0, 9.0, 0), 0.45, 11.0)
	box(g, "kaki_clair", Vector3(0, 15.6, 0), Vector3(2.2, 1.4, 2.2))
	box(g, "orange_mil", Vector3(0, 16.4, 0), Vector3(2.3, 0.25, 2.3))
	beacon(g, Vector3(0, 16.9, 0))
	cyl(g, "kaki", Vector3(4.2, 4.8, 0), 1.9, 2.6, 0.7, Vector3.ZERO, 8)
	strut(g, "blinde", Vector3(4.2, 1.0, 0), Vector3(4.2, 3.6, 0), 0.25)
	hose(g, Vector3(2.5, 3.6, 1.0), Vector3(4.2, 5.8, 1.2), -0.5, 0.16)
	lamp(g, Vector3(3.0, 6.0, 3.0), Color("ffd29a"), 2.5, 16)
	for i in 5:
		dust(B, g.position + Vector3(rng.randf_range(-5, 5), rng.randf_range(0.8, 2.5), rng.randf_range(-5, 5)), rng.randf_range(3.0, 6.0), 0.4)


# hangar : voûte kaki en arceaux (demi-cylindre), porte à chevrons orange
# porte : extrémité +x du repère local ; les unités de la colonie en sortent pour gagner le front
func hangar(B: Node3D, c: Vector2, yaw := 0.0) -> void:
	var g := Node3D.new()
	g.position = gp(c.x, c.y)
	g.rotation.y = yaw
	g.set_meta("hangar", true)
	B.add_child(g)
	var L := 56.0
	var R := 14.0
	var feet: Array = []
	var N := 12
	for k in N:
		var a0 := PI * k / N
		var a1 := PI * (k + 1) / N
		var am := (a0 + a1) * 0.5
		var chord := 2.0 * R * sin(PI / N * 0.5) + 0.05
		var pn := box(g, "kaki" if k % 2 == 0 else "kaki_clair", Vector3(0, sin(am) * R, cos(am) * R), Vector3(L, 0.5, chord))
		pn.rotation = Vector3(PI / 2 - am, 0, 0)
	for k in 8:
		var x := -L * 0.5 + k * L / 7.0
		for kk in N:
			var a0 := PI * kk / N
			var a1 := PI * (kk + 1) / N
			strut(g, "blinde", Vector3(x, sin(a0) * (R + 0.35), cos(a0) * (R + 0.35)), Vector3(x, sin(a1) * (R + 0.35), cos(a1) * (R + 0.35)), 0.3)
		for s: float in [-1.0, 1.0]:
			feet.append(Vector3(x, 0, s * R))
	g.set_meta("pieds", feet)
	# fond fermé, avant ouvert avec cadre de porte à chevrons
	for s: float in [-1.0, 1.0]:
		box(g, "blinde", Vector3(L * 0.5 + 0.3, R * 0.45, s * (R - 1.0)), Vector3(0.8, R * 0.9, 2.0))
		for k in 5:
			var ch := box(g, "orange_mil", Vector3(L * 0.5 + 0.75, 1.5 + k * 2.4, s * (R - 1.0)), Vector3(0.1, 0.6, 1.8))
			ch.rotation = Vector3(s * 0.6, 0, 0)
	box(g, "blinde", Vector3(L * 0.5 + 0.3, R - 0.6, 0), Vector3(0.8, 1.6, R * 2.0 - 2.0))
	box(g, "kaki", Vector3(-L * 0.5, R * 0.42, 0), Vector3(0.6, R * 0.84, R * 1.9))
	box(g, "visiere", Vector3(-L * 0.5 - 0.35, R * 0.62, 0), Vector3(0.1, 0.8, R * 1.2))
	for k in 4:
		lamp(g, Vector3(-18 + k * 12.0, R * 0.7, 0), Color("cfe6ff"), 3.0, 30)
	beacon(g, Vector3(0, R + 1.0, 0))


# ================================================================ surface industrielle (d'après le remake K-240)
# En surface : uniquement l'industrie polluante et dangereuse pour la population, l'extraction et le stockage.
# Les habitats et la vie de la colonie sont sous terre (non représentés pour l'instant).

# bande de danger jaune et noire le long de l'axe x (repère du parent)
func hazard_x(par: Node3D, c: Vector3, L: float, h := 0.5, t := 0.08) -> void:
	var n := maxi(2, int(L / 1.6))
	for k in n:
		box(par, "danger" if k % 2 == 0 else "noir", c + Vector3(-L * 0.5 + (k + 0.5) * L / n, 0, 0), Vector3(L / n + 0.01, h, t))


# panache de fumée animé (pollution) : bouffées qui montent puis renaissent
func smoke_stack(par: Node3D, top: Vector3, n: int, col := Color(0.32, 0.31, 0.3)) -> void:
	for i in n:
		var holder := Node3D.new()
		holder.position = top
		par.add_child(holder)
		dust(holder, Vector3.ZERO, 11.0, 0.75, col)
		plumes.append({"n": holder, "base": top, "k": float(i) / n, "rise": 34.0, "s0": 5.0, "s1": 18.0})


# raffinerie : hauts fourneaux, cheminées fumantes, cuves, tuyauteries (polluante, à l'écart des habitats)
func refinery(B: Node3D, c: Vector2, yaw: float) -> void:
	var g := Node3D.new()
	g.position = gp(c.x, c.y, -0.3)
	g.rotation.y = yaw
	g.set_meta("socle", 18.0)
	B.add_child(g)
	box(g, "beton", Vector3(0, 0.6, 0), Vector3(34, 1.2, 26))
	# hall principal
	box(g, "gris_dep", Vector3(-6, 6.0, 0), Vector3(18, 10.0, 16))
	box(g, "blinde", Vector3(-6, 11.3, 0), Vector3(18.6, 0.8, 16.6))
	hazard_x(g, Vector3(-6, 1.6, 8.05), 18.0)
	for k in 5:
		box(g, "vert", Vector3(-13 + k * 3.5, 8.2, 8.05), Vector3(1.6, 0.9, 0.1))
	box(g, "blinde", Vector3(3.05, 4.0, 0), Vector3(0.3, 6.5, 7.0))
	hazard_x(g, Vector3(-6, 7.6, -8.05), 18.0, 0.5)
	# hauts fourneaux
	for k in 2:
		var p := Vector3(9.0, 0, -6.0 + k * 9.0)
		cyl(g, "rouille", p + Vector3(0, 8.0, 0), 3.0, 14.0, 3.6, Vector3.ZERO, 12)
		cyl(g, "noyau", p + Vector3(0, 2.0, 0), 2.0, 0.6, -1.0, Vector3.ZERO, 16)
		cyl(g, "blinde", p + Vector3(0, 15.5, 0), 2.0, 1.2, 3.0, Vector3.ZERO, 12)
		for y: float in [5.0, 10.0]:
			cyl(g, "danger", p + Vector3(0, y, 0), 3.35 - y * 0.03, 0.4, -1.0, Vector3.ZERO, 12)
		hose(g, p + Vector3(-2.5, 14.0, 0), Vector3(1.0, 10.5, -6.0 + k * 9.0), -1.5, 0.45)
	# cheminées
	for k in 3:
		var p := Vector3(-14.0 + k * 4.5, 0, -10.0)
		cyl(g, "gris_dep", p + Vector3(0, 17.0, 0), 1.0, 32.0, 1.5, Vector3.ZERO, 10)
		cyl(g, "danger", p + Vector3(0, 29.0, 0), 1.08, 1.2, -1.0, Vector3.ZERO, 10)
		cyl(g, "noir", p + Vector3(0, 30.5, 0), 1.08, 1.2, -1.0, Vector3.ZERO, 10)
		sph(g, "rouge", p + Vector3(0, 33.3, 0), 0.3)
		smoke_stack(g, p + Vector3(0, 33.0, 0), 7, Color(0.55, 0.49, 0.42))
	# cuves
	for k in 3:
		cyl(g, "kaki", Vector3(-12 + k * 5.5, 3.5, 11.5), 2.2, 5.0, -1.0, Vector3.ZERO, 12)
		cyl(g, "danger", Vector3(-12 + k * 5.5, 5.2, 11.5), 2.25, 0.35, -1.0, Vector3.ZERO, 12)
	lamp(g, Vector3(0, 6, 14), Color("ff9a40"), 4.0, 30)
	lamp(g, Vector3(9, 4, 0), Color("ff6a20"), 3.0, 18)


# réacteur à fission (SMR) : installé à l'écart, refroidi par la glace ; zone interdite clôturée
func fission_smr(B: Node3D, c: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(c.x, c.y, -0.3)
	g.set_meta("socle", 15.0)
	B.add_child(g)
	cyl(g, "beton", Vector3(0, 0.6, 0), 14.0, 1.2, 15.0, Vector3.ZERO, 24)
	# enceinte de confinement
	cyl(g, "gris_dep", Vector3(0, 5.5, 0), 6.5, 9.0, 7.0, Vector3.ZERO, 24)
	sph(g, "gris_dep", Vector3(0, 10.0, 0), 6.5, true)
	cyl(g, "danger", Vector3(0, 3.0, 0), 6.85, 0.6, -1.0, Vector3.ZERO, 24)
	cyl(g, "noir", Vector3(0, 3.6, 0), 6.82, 0.6, -1.0, Vector3.ZERO, 24)
	# panneau radioactif (trèfle stylisé)
	box(g, "danger", Vector3(6.9, 7.0, 0), Vector3(0.1, 2.4, 2.4))
	for k in 3:
		var a := TAU * k / 3.0 + PI / 2
		box(g, "noir", Vector3(6.97, 7.0 + sin(a) * 0.55, cos(a) * 0.55), Vector3(0.05, 0.6, 0.6), Vector3(a, 0, 0))
	# tours de refroidissement à glace (vapeur)
	for s: float in [-1.0, 1.0]:
		var p := Vector3(-3.0, 0, s * 9.5)
		cyl(g, "beton", p + Vector3(0, 5.5, 0), 2.6, 10.0, 3.6, Vector3.ZERO, 16)
		smoke_stack(g, p + Vector3(0, 10.5, 0), 5, Color(0.85, 0.88, 0.92))
	# clôture de la zone interdite
	for k in 24:
		var a := TAU * k / 24.0
		cyl(g, "noir", Vector3(cos(a) * 13.6, 2.0, sin(a) * 13.6), 0.12, 2.8)
		var b := box(g, "danger" if k % 2 == 0 else "noir", Vector3(cos(a + PI / 24) * 13.6, 2.6, sin(a + PI / 24) * 13.6), Vector3(0.1, 0.5, 3.5))
		b.rotation.y = -a - PI / 24
	for k in 4:
		var a := TAU * k / 4.0
		sph(g, "rouge", Vector3(cos(a) * 13.6, 3.8, sin(a) * 13.6), 0.3)
	beacon(g, Vector3(0, 17.0, 0))
	lamp(g, Vector3(0, 8, 0), Color("b8ff6a"), 2.0, 26)


# catapulte électromagnétique : longue rampe inclinée qui expédie lingots et bonbonnes d'Hélium-3 en orbite
func mass_driver(B: Node3D, c: Vector2, yaw: float) -> void:
	var g := Node3D.new()
	g.position = gp(c.x, c.y, -0.2)
	g.rotation.y = yaw
	B.add_child(g)
	var L := 90.0
	var ang := 0.32
	var dir := Vector3(cos(ang), sin(ang), 0)
	var feet: Array = []
	box(g, "gris_dep", Vector3(-4, 3.0, 0), Vector3(12, 6.0, 10))
	hazard_x(g, Vector3(-4, 0.8, 5.05), 12.0)
	box(g, "vert", Vector3(-4, 4.5, 5.05), Vector3(6, 0.8, 0.1))
	for k in 12:
		var t := (k + 0.5) / 12.0
		var p := dir * (t * L) + Vector3(0, 2.5, 0)
		var rail := box(g, "blinde", p, Vector3(L / 12.0 + 0.05, 0.8, 3.0))
		rail.rotation.z = ang
		# bobines d'accélération
		var coil := cyl(g, "noyau" if k % 3 == 0 else "orange_mil", p + Vector3(0, 1.0, 0), 1.6, 0.6, -1.0, Vector3(0, 0, PI / 2 + ang), 12)
		coil.scale = Vector3(1, 1, 1)
		if k % 2 == 0:
			strut(g, "kaki_clair", Vector3(p.x, 0, -2.0), p - Vector3(0, 0.4, 1.2), 0.3)
			strut(g, "kaki_clair", Vector3(p.x, 0, 2.0), p - Vector3(0, 0.4, -1.2), 0.3)
			feet.append(Vector3(p.x, 0, -2.0))
			feet.append(Vector3(p.x, 0, 2.0))
	g.set_meta("pieds", feet)
	beacon(g, dir * L + Vector3(0, 4.0, 0))


# silos de stockage (régolithe, glace, volatils) reliés par un convoyeur
func storage_silos(B: Node3D, c: Vector2) -> void:
	for k in 4:
		var g := Node3D.new()
		var q := c + Vector2((k % 2) * 13.0 - 6.5, (k / 2) * 13.0 - 6.5)
		g.position = gp(q.x, q.y, -0.3)
		g.set_meta("socle", 5.4)
		B.add_child(g)
		cyl(g, "blinde", Vector3(0, 0.6, 0), 5.0, 1.2, 5.4, Vector3.ZERO, 12)
		cyl(g, "gris_dep", Vector3(0, 9.0, 0), 4.2, 16.0, -1.0, Vector3.ZERO, 16)
		cyl(g, "gris_dep", Vector3(0, 18.0, 0), 1.2, 2.0, 4.2, Vector3.ZERO, 16)
		for y: float in [4.0, 9.0, 14.0]:
			cyl(g, "blinde", Vector3(0, y, 0), 4.3, 0.35, -1.0, Vector3.ZERO, 16)
		cyl(g, ["danger", "orange_mil", "kaki_clair", "danger"][k], Vector3(0, 12.0, 0), 4.32, 1.2, -1.0, Vector3.ZERO, 16)
		box(g, "vert", Vector3(4.25, 6.0, 0), Vector3(0.1, 0.6, 1.4))
		sph(g, "rouge", Vector3(0, 19.3, 0), 0.25)
	# convoyeur
	link(B, c + Vector2(-6.5, -6.5), c + Vector2(6.5, -6.5), 14.0, 14.0, 0.6, "blinde")
	link(B, c + Vector2(-6.5, 6.5), c + Vector2(6.5, 6.5), 14.0, 14.0, 0.6, "blinde")
	link(B, c + Vector2(0, -6.5), c + Vector2(0, 6.5), 14.5, 14.5, 0.6, "orange_mil")


# moissonneuse-racleuse : engin mobile qui racle le régolithe (Hélium-3, gaz rares), poussière derrière lui
func harvester_mesh() -> Node3D:
	var g := Node3D.new()
	for s: float in [-1.0, 1.0]:
		box(g, "noir", Vector3(0, 0.9, s * 2.4), Vector3(9.0, 1.8, 1.4))
		for k in 5:
			cyl(g, "blinde", Vector3(-3.6 + k * 1.8, 0.9, s * 2.4), 0.75, 1.5, -1.0, Vector3(PI / 2, 0, 0), 12)
	box(g, "kaki", Vector3(0, 2.6, 0), Vector3(8.0, 2.2, 4.2))
	box(g, "danger", Vector3(0, 3.8, 0), Vector3(8.1, 0.25, 4.3))
	# racleuse rotative à l'avant
	cyl(g, "orange_mil", Vector3(5.6, 1.0, 0), 1.0, 5.6, -1.0, Vector3(PI / 2, 0, 0), 12)
	for k in 6:
		box(g, "blinde", Vector3(5.6, 1.0, -2.4 + k * 0.95), Vector3(2.3, 0.25, 0.2), Vector3(0, 0, k * 0.6))
	# four à 800 °C et cabine
	cyl(g, "rouille", Vector3(-1.5, 5.0, 0), 1.6, 2.6, 1.9, Vector3.ZERO, 12)
	cyl(g, "noyau", Vector3(-1.5, 6.4, 0), 1.0, 0.3, -1.0, Vector3.ZERO, 12)
	box(g, "gris_dep", Vector3(2.8, 4.6, 1.0), Vector3(2.0, 1.8, 1.8))
	box(g, "vert", Vector3(3.82, 4.8, 1.0), Vector3(0.05, 0.8, 1.4))
	# bonbonnes d'Hélium-3
	for k in 3:
		cyl(g, "tuyau", Vector3(-3.4, 4.3, -1.4 + k * 1.4), 0.55, 1.6, -1.0, Vector3.ZERO, 10)
	sph(g, "rouge", Vector3(-3.8, 5.4, 1.8), 0.2)
	var hz := Node3D.new()
	g.add_child(hz)
	for k in 4:
		dust(hz, Vector3(-6.0 - k * 2.5, 1.2 + k * 0.4, 0), 4.0 + k * 1.5, 0.45)
	return g


# ================================================================ spatioport
# Grand dépôt militaire : terminal à portes de hangar, tour de contrôle, 3 plateformes avec leurs transports,
# grues, paraboles, passerelles, conteneurs. Coordonnées avant réduction BSC.

# transport spatial anguleux (façon « Terra-Corps ») : coque à pans, verrière rouge et verte, ailerons, réacteurs
func shuttle(par: Node3D, pos: Vector3, yaw: float, tag: int) -> Dictionary:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	par.add_child(g)
	var body := Node3D.new()
	body.position.y = 3.2
	g.add_child(body)
	# coque : caisson central, flancs inclinés, nez en coin
	box(body, "gris_dep", Vector3(0, 2.2, 0), Vector3(20, 4.4, 7.0))
	for s: float in [-1.0, 1.0]:
		var fl := box(body, "blinde", Vector3(0, 2.6, s * 4.1), Vector3(19, 3.4, 1.6))
		fl.rotation.x = s * 0.35
		var wg := box(body, "gris_dep", Vector3(-3.0, 1.2, s * 7.6), Vector3(9.0, 0.5, 6.0))
		wg.rotation = Vector3(s * -0.12, s * 0.35, 0)
		box(body, "danger", Vector3(-1.2, 1.5, s * 10.2), Vector3(4.5, 0.15, 0.8), Vector3(0, s * 0.35, 0))
		var fin := box(body, "blinde", Vector3(-8.5, 5.6, s * 2.2), Vector3(4.0, 3.6, 0.35))
		fin.rotation = Vector3(s * 0.3, 0, -0.35)
		sph(body, "rouge", Vector3(-1.2, 1.5, s * 10.6), 0.22)
	var nose := box(body, "gris_dep", Vector3(11.4, 1.6, 0), Vector3(5.0, 3.2, 6.2))
	nose.rotation.z = -0.32
	var top := box(body, "blinde", Vector3(1.0, 4.9, 0), Vector3(12, 1.2, 4.0))
	top.rotation.z = -0.03
	# verrière : vitres rouge et verte comme sur l'image
	var cw := box(body, "rouge_vitre", Vector3(11.2, 3.5, 1.5), Vector3(2.6, 1.0, 2.4))
	cw.rotation.z = -0.55
	var cw2 := box(body, "vert", Vector3(11.2, 3.5, -1.5), Vector3(2.6, 1.0, 2.4))
	cw2.rotation.z = -0.55
	# porte latérale et marquage
	box(body, "vert", Vector3(2.0, 2.0, 3.52), Vector3(2.2, 2.6, 0.05))
	hazard_x(body, Vector3(0, 0.25, 3.52), 18.0, 0.35, 0.06)
	box(body, "danger" if tag % 2 == 0 else "orange_mil", Vector3(-3.5, 3.6, 3.53), Vector3(5.0, 0.9, 0.05))
	# réacteurs arrière
	for s: float in [-1.0, 1.0]:
		cyl(body, "blinde", Vector3(-10.6, 2.0, s * 2.0), 1.4, 2.2, 1.7, Vector3(0, 0, PI / 2), 12)
		cyl(body, "noyau", Vector3(-11.75, 2.0, s * 2.0), 1.1, 0.1, -1.0, Vector3(0, 0, PI / 2), 12)
	# train d'atterrissage
	for p: Vector3 in [Vector3(7, 0, 2.2), Vector3(7, 0, -2.2), Vector3(-6, 0, 3.0), Vector3(-6, 0, -3.0)]:
		strut(g, "blinde", p, p + Vector3(0, 3.4, 0), 0.25)
		box(g, "noir", p + Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.0))
	# panache vertical (décollage)
	var pl := Node3D.new()
	g.add_child(pl)
	var plm := ShaderMaterial.new()
	plm.shader = load("res://shaders/plume.gdshader")
	var cm := ShaderMaterial.new()
	cm.shader = plm.shader
	cm.set_shader_parameter("col", Color(1.0, 0.95, 0.85))
	cm.set_shader_parameter("power", 12.0)
	for s: float in [-1.0, 1.0]:
		var outer := cyl(pl, "acier", Vector3(-4.0, -4.0, s * 3.5), 1.2, 12.0, 3.0, Vector3.ZERO, 24)
		outer.material_override = plm
		var core := cyl(pl, "acier", Vector3(-4.0, -1.5, s * 3.5), 0.7, 7.0, 1.2, Vector3.ZERO, 16)
		core.material_override = cm
		for m in [outer, core]:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fl2 := OmniLight3D.new()
	fl2.light_color = Color("ffd8a0")
	fl2.light_energy = 12.0
	fl2.omni_range = 60.0
	fl2.position = Vector3(-4, -2, 0)
	pl.add_child(fl2)
	var smoke := Node3D.new()
	g.add_child(smoke)
	for i in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4, 16)
		dust(smoke, Vector3(cos(a) * r, rng.randf_range(1, 6), sin(a) * r), rng.randf_range(9, 18), 0.35)
	g.set_meta("fusee", true)
	return {"g": g, "body": body, "plume": pl, "smoke": smoke, "base": pos, "pad": null}


# grue à tour en treillis orange
func tower_crane(par: Node3D, p: Vector3, yaw: float, H: float) -> void:
	var g := Node3D.new()
	g.position = p
	par.add_child(g)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			strut(g, "orange_mil", Vector3(sx * 1.0, 0, sz * 1.0), Vector3(sx * 1.0, H, sz * 1.0), 0.15, 6)
	for k in int(H / 3.0):
		var y := k * 3.0
		strut(g, "orange_mil", Vector3(-1, y, -1), Vector3(1, y + 3, -1), 0.07, 4)
		strut(g, "orange_mil", Vector3(-1, y, 1), Vector3(1, y + 3, 1), 0.07, 4)
		strut(g, "orange_mil", Vector3(-1, y, -1), Vector3(-1, y + 3, 1), 0.07, 4)
		strut(g, "orange_mil", Vector3(1, y, -1), Vector3(1, y + 3, 1), 0.07, 4)
	var jib := Node3D.new()
	jib.position.y = H
	jib.rotation.y = yaw
	g.add_child(jib)
	box(jib, "orange_mil", Vector3(8, 0.6, 0), Vector3(26, 1.0, 1.4))
	box(jib, "blinde", Vector3(-7, 0.4, 0), Vector3(4, 2.0, 2.4))
	box(jib, "gris_dep", Vector3(1.6, -1.0, 0), Vector3(2.0, 1.6, 1.8))
	box(jib, "vert", Vector3(2.62, -1.0, 0), Vector3(0.05, 0.8, 1.4))
	strut(jib, "orange_mil", Vector3(0, 0.6, 0), Vector3(0, 5.5, 0), 0.2, 6)
	strut(jib, "blinde", Vector3(0, 5.5, 0), Vector3(19, 1.0, 0), 0.06, 4)
	strut(jib, "blinde", Vector3(0, 5.5, 0), Vector3(-8, 1.0, 0), 0.06, 4)
	strut(jib, "noir", Vector3(16, 0, 0), Vector3(16, -10, 0), 0.05, 4)
	box(jib, "danger", Vector3(16, -10.5, 0), Vector3(1.2, 0.8, 1.2))
	sph(jib, "rouge", Vector3(0, 6.0, 0), 0.25)
	sph(jib, "rouge", Vector3(21, 1.4, 0), 0.25)


# parabole sur pylône en treillis
func dish_tower(par: Node3D, p: Vector3, H: float, R: float) -> void:
	var g := Node3D.new()
	g.position = p
	par.add_child(g)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4
		strut(g, "blinde", Vector3(cos(a) * 2.2, 0, sin(a) * 2.2), Vector3(cos(a) * 0.8, H, sin(a) * 0.8), 0.14, 6)
	for y in range(2, int(H), 3):
		cyl(g, "blinde", Vector3(0, y, 0), 2.2 - y * 1.4 / H, 0.12, -1.0, Vector3.ZERO, 4)
	box(g, "gris_dep", Vector3(0, H + 0.6, 0), Vector3(3.0, 1.2, 3.0))
	var d := Node3D.new()
	d.position = Vector3(0, H + 2.5, 0)
	d.rotation = Vector3(0.0, rng.randf() * TAU, 0.8)
	g.add_child(d)
	cyl(d, "tuyau", Vector3.ZERO, R, 0.5, R * 0.25, Vector3.ZERO, 20)
	strut(d, "blinde", Vector3.ZERO, Vector3(0, R * 0.8, 0), 0.1, 4)
	sph(d, "rouge", Vector3(0, R * 0.85, 0), 0.25)


func spaceport(B: Node3D, c: Vector2) -> void:
	# tarmac : dalles de béton posées sur la sphère, marquage jaune
	var W := 150.0
	var D := 100.0
	var T := 10.0
	for i in int(W / T):
		for j in int(D / T):
			var q := c + Vector2(-W * 0.5 + (i + 0.5) * T, -D * 0.5 + (j + 0.5) * T)
			var t := Node3D.new()
			t.position = gp(q.x, q.y, 0.15)
			B.add_child(t)
			box(t, "tarmac" if (i + j) % 2 == 0 else "tarmac2", Vector3(0, 0.1, 0), Vector3(T + 0.05, 0.4, T + 0.05))
			if j == 3:
				box(t, "danger", Vector3(0, 0.33, 0), Vector3(T * 0.6, 0.05, 0.5))
	# terminal / dépôt : long bâtiment gris, 4 portes de hangar à chevrons, enseigne, vitres vertes
	var dep := Node3D.new()
	dep.position = gp(c.x, c.y - 38.0, 0.0)
	B.add_child(dep)
	var feet: Array = []
	for k in 7:
		for s: float in [-1.0, 1.0]:
			feet.append(Vector3(-54.0 + k * 18.0, 0, s * 9.0))
	dep.set_meta("pieds", feet)
	box(dep, "gris_dep", Vector3(0, 9.0, 0), Vector3(112, 18.0, 20))
	box(dep, "blinde", Vector3(0, 18.6, 0), Vector3(114, 1.2, 22))
	box(dep, "gris_dep", Vector3(-30, 21.5, -3), Vector3(30, 5.0, 12))
	for k in 4:
		var x := -42.0 + k * 28.0
		box(dep, "blinde", Vector3(x, 6.5, 10.05), Vector3(18, 13, 0.3))
		for r in 6:
			box(dep, "noir", Vector3(x, 1.2 + r * 2.1, 10.25), Vector3(17.6, 0.15, 0.05))
		for s: float in [-1.0, 1.0]:
			for kk in 5:
				var ch := box(dep, "danger", Vector3(x + s * 9.6, 1.5 + kk * 2.5, 10.3), Vector3(0.12, 1.0, 0.12))
				ch.scale = Vector3(1, 1, 1)
				box(dep, "danger" if kk % 2 == 0 else "noir", Vector3(x + s * 9.6, 1.25 + kk * 2.5, 10.25), Vector3(1.2, 1.25, 0.1))
		sph(dep, "rouge", Vector3(x, 13.8, 10.3), 0.3)
		box(dep, "vert", Vector3(x, 15.6, 10.1), Vector3(14, 1.2, 0.1))
	# enseigne
	box(dep, "tuyau", Vector3(-40, 22.5, 3.05), Vector3(22, 3.0, 0.2))
	box(dep, "noir", Vector3(-40, 22.5, 3.2), Vector3(20, 0.5, 0.05))
	# tuyauteries sur la façade arrière et le côté
	for k in 4:
		strut(dep, "tuyau", Vector3(-56, 3 + k * 1.2, -10.4), Vector3(56, 3 + k * 1.2, -10.4), 0.35, 8)
	for k in 6:
		sph(dep, "rouge", Vector3(-55 + k * 22.0, 19.6, 10.8), 0.3)
	lamp(dep, Vector3(0, 12, 16), Color("e8f4ff"), 5.0, 40)
	lamp(dep, Vector3(-40, 12, 16), Color("e8f4ff"), 4.0, 30)
	lamp(dep, Vector3(40, 12, 16), Color("e8f4ff"), 4.0, 30)
	# tour de contrôle : fût, cabine octogonale aux vitres vertes, antennes, feux rouges
	var tw := Node3D.new()
	tw.position = gp(c.x + 62.0, c.y - 34.0, -0.3)
	tw.set_meta("socle", 7.5)
	B.add_child(tw)
	cyl(tw, "beton", Vector3(0, 0.6, 0), 7.0, 1.2, 7.5, Vector3.ZERO, 8)
	box(tw, "gris_dep", Vector3(0, 6.0, 0), Vector3(11, 10, 11))
	hazard_x(tw, Vector3(0, 1.8, 5.55), 11.0)
	cyl(tw, "gris_dep", Vector3(0, 21.0, 0), 3.2, 22.0, 4.0, Vector3.ZERO, 8)
	for y: float in [14.0, 20.0, 26.0]:
		cyl(tw, "blinde", Vector3(0, y, 0), 3.6 - (y - 14.0) * 0.03, 0.6, -1.0, Vector3.ZERO, 8)
	cyl(tw, "blinde", Vector3(0, 32.5, 0), 6.5, 1.0, 4.0, Vector3.ZERO, 8)
	cyl(tw, "vert", Vector3(0, 35.0, 0), 6.6, 3.6, 6.2, Vector3.ZERO, 8)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		strut(tw, "blinde", Vector3(cos(a) * 6.5, 33.2, sin(a) * 6.5), Vector3(cos(a) * 6.2, 36.8, sin(a) * 6.2), 0.18, 4)
	cyl(tw, "blinde", Vector3(0, 37.6, 0), 6.0, 1.4, 6.8, Vector3.ZERO, 8)
	box(tw, "gris_dep", Vector3(0, 39.5, 0), Vector3(4.0, 2.4, 4.0))
	for k in 3:
		cyl(tw, "blinde", Vector3(-1.2 + k * 1.2, 44.0, 0.5 * (k - 1)), 0.08, 7.0 + k * 1.5)
		sph(tw, "rouge", Vector3(-1.2 + k * 1.2, 47.6 + k * 0.75, 0.5 * (k - 1)), 0.25)
	beacon(tw, Vector3(3.5, 39.5, 3.5))
	lamp(tw, Vector3(0, 35, 8), Color("9affb8"), 3.0, 30)
	# trois plateformes d'atterrissage surélevées, chacune avec son transport
	for k in 3:
		var pc := c + Vector2(-46.0 + k * 46.0, 18.0)
		var pd := Node3D.new()
		pd.position = gp(pc.x, pc.y, -0.3)
		pd.set_meta("socle", 17.0)
		B.add_child(pd)
		cyl(pd, "blinde", Vector3(0, 1.0, 0), 16.0, 2.0, 17.0, Vector3.ZERO, 8)
		cyl(pd, "tarmac", Vector3(0, 2.05, 0), 15.0, 0.1, -1.0, Vector3.ZERO, 8)
		for kk in 8:
			var a := TAU * (kk + 0.5) / 8.0
			var st := box(pd, "danger" if kk % 2 == 0 else "noir", Vector3(cos(a) * 15.3, 2.1, sin(a) * 15.3), Vector3(0.6, 0.1, 11.0))
			st.rotation.y = -a
			sph(pd, "rouge" if kk % 2 == 0 else "vert", Vector3(cos(a) * 16.4, 2.3, sin(a) * 16.4), 0.3)
		# grand H et cercle de visée
		box(pd, "danger", Vector3(0, 2.13, -3.0), Vector3(8.0, 0.05, 1.0))
		box(pd, "danger", Vector3(0, 2.13, 3.0), Vector3(8.0, 0.05, 1.0))
		box(pd, "danger", Vector3(0, 2.13, 0), Vector3(1.0, 0.05, 6.0))
		lamp(pd, Vector3(0, 6, 0), Color("ffe0a0"), 2.5, 28)
		var yw := -PI / 2 + (k - 1) * 0.25
		var sh := shuttle(B, pd.position + Vector3(0, 2.1, 0), yw, k)
		sh.pad = pd
		sh.pad_off = 2.1
		sh.yaw = yw
		rockets.append(sh)
	# passerelle surélevée entre les plateformes et le terminal
	walkway(B, c + Vector2(-46, 2), c + Vector2(46, 2), 6.0, 3.0, 0.5, "blinde")
	walkway(B, c + Vector2(-46, 2), c + Vector2(46, 2), 6.35, 0.25, 0.12, "danger")
	for k in 9:
		var x := -46.0 + k * 11.5
		var post := Node3D.new()
		post.position = gp(c.x + x, c.y + 2.0)
		B.add_child(post)
		cyl(post, "blinde", Vector3(0, 3.0, 0), 0.25, 6.0)
	# grues, paraboles, conteneurs, véhicule
	var cr1 := Node3D.new()
	cr1.position = gp(c.x - 70.0, c.y - 8.0)
	B.add_child(cr1)
	tower_crane(cr1, Vector3.ZERO, 0.4, 34.0)
	var cr2 := Node3D.new()
	cr2.position = gp(c.x + 28.0, c.y - 60.0)
	B.add_child(cr2)
	tower_crane(cr2, Vector3.ZERO, 2.4, 40.0)
	var dt1 := Node3D.new()
	dt1.position = gp(c.x - 74.0, c.y + 40.0)
	B.add_child(dt1)
	dish_tower(dt1, Vector3.ZERO, 24.0, 6.0)
	var dt2 := Node3D.new()
	dt2.position = gp(c.x + 74.0, c.y + 36.0)
	B.add_child(dt2)
	dish_tower(dt2, Vector3.ZERO, 16.0, 4.0)
	for k in 10:
		var cn := Node3D.new()
		var q := c + Vector2(38.0 + (k % 5) * 6.6, -16.0 - (k / 5) * 3.2)
		cn.position = gp(q.x, q.y, 0.4)
		B.add_child(cn)
		box(cn, ["orange_mil", "kaki", "blinde", "danger", "kaki_clair"][k % 5], Vector3(0, 1.3, 0), Vector3(6.0, 2.6, 2.6))
		if k % 3 == 0:
			box(cn, ["kaki", "orange_mil", "blinde"][k % 3], Vector3(0, 3.9, 0), Vector3(6.0, 2.6, 2.6))
	var car := Node3D.new()
	car.position = gp(c.x + 10.0, c.y + 44.0, 0.3)
	car.rotation.y = 0.5
	B.add_child(car)
	for s: float in [-1.0, 1.0]:
		for w in 3:
			cyl(car, "noir", Vector3(-2.0 + w * 2.0, 0.8, s * 1.7), 0.8, 0.7, -1.0, Vector3(PI / 2, 0, 0), 12)
	box(car, "kaki", Vector3(0, 1.8, 0), Vector3(6.4, 1.6, 3.2))
	var cab := box(car, "kaki_clair", Vector3(0.8, 3.0, 0), Vector3(3.4, 1.2, 2.8))
	cab.rotation.z = -0.08
	box(car, "vert", Vector3(2.5, 3.0, 0), Vector3(0.05, 0.7, 2.4))
	sph(car, "rouge", Vector3(-1.0, 3.8, 0), 0.2)


# piste circulaire en béton, balisée de feux orange
func roads(B: Node3D) -> void:
	var n := 260
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var R := 135.0
		var p0 := gp(cos(a0) * R, sin(a0) * R, -0.02)
		var p1 := gp(cos(a1) * R, sin(a1) * R, -0.02)
		var mid := (p0 + p1) * 0.5
		var bs := Basis.looking_at(p1 - p0, up_at(mid))
		var rd := box(B, "beton", mid, Vector3(5.0, 0.12, p0.distance_to(p1) + 0.15))
		rd.basis = bs
		rd.set_meta("libre", true)
		if i % 3 == 0:
			var ln := box(B, "orange_mil", mid + up_at(mid) * 0.07, Vector3(0.14, 0.05, p0.distance_to(p1) * 0.7))
			ln.basis = bs
			ln.set_meta("libre", true)
	for k in 10:
		var a := TAU * k / 10.0
		var x := cos(a) * 139.0
		var z := sin(a) * 139.0
		box(B, "blinde", gp(x, z, 0.3), Vector3(0.8, 0.6, 0.8))
		cyl(B, "kaki", gp(x, z, 3.0), 0.14, 5.4)
		sph(B, "rouge", gp(x, z, 5.9), 0.22)
		lamp(B, gp(x, z, 5.6), Color("ffb35a"), 2.5, 18)


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
	var rcols := [Color(0.20, 0.20, 0.21), Color(0.15, 0.15, 0.16), Color(0.26, 0.255, 0.25), Color(0.20, 0.20, 0.21), Color(0.15, 0.15, 0.16), Color(0.30, 0.17, 0.09)]
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
	# appoint : opposé au soleil, décalé de côté pour que l'ombrage du relief ne soit pas symétrique
	var sp := sd.cross(Vector3.UP if absf(sd.y) < 0.99 else Vector3.RIGHT).normalized()
	var fd := (sd + sp * 0.6).normalized()
	fill_light.basis = Basis.looking_at(fd, Vector3.UP if absf(fd.y) < 0.99 else Vector3.FORWARD)
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
	if bridge != null:
		bridge.view_name = String(v.nom)
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


# verticale locale du point visé, et poids de la mise à niveau (0 en orbite, quand le pivot est près du centre)
func cam_up() -> Vector3:
	return up_at(target)


func cam_level_w() -> float:
	return smoothstep(RC * 0.45, RC * 0.75, (target + Vector3(0, RC, 0)).length())


# caméra sans roulis : son axe X reste dans le plan horizontal local, l'horizon ne penche jamais
func leveled(b: Basis, u: Vector3) -> Basis:
	var z := b.z.normalized()
	var x := u.cross(z)
	if x.length() < 0.02:
		x = b.x - u * b.x.dot(u)
	x = x.normalized()
	return Basis(x, z.cross(x), z)


func update_cam() -> void:
	cb = cb.orthonormalized()
	var lw := cam_level_w()
	if lw > 0.0:
		var lb := leveled(cb, cam_up())
		cb = Basis(cb.get_rotation_quaternion().slerp(lb.get_rotation_quaternion(), lw))
	cam.basis = cb
	cam.position = target + cb.z * dist
	# la caméra ne passe jamais sous le sol (verticale locale de la sphère)
	var ag := alt(cam.position)
	if ag < 1.2:
		cam.position += up_at(cam.position) * (1.2 - ag)


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		# zoom continu façon Planetary Annihilation : du sol à l'orbite et retour
		var ctr := Vector3(0, -RC, 0)
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			var cp := target + cb.z * dist
			dist = maxf(3.0, dist * 0.88)
			# en rapprochant depuis l'orbite, le pivot redescend sur la surface visée
			if target.distance_to(ctr) < RC * 0.9 and dist < RC * 2.2:
				var sp := surf_point((cp - ctr).normalized())
				var t := target.lerp(sp, 0.25)
				dist = maxf(3.0, cp.distance_to(t) * 0.88)
				target = t
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var cp := target + cb.z * dist
			dist = minf(60000.0, dist / 0.88)
			# en s'éloignant, le pivot glisse vers le centre : la caméra tourne alors autour de l'astéroïde
			if dist > RC * 0.6:
				var t := target.lerp(ctr, 0.18)
				dist = minf(60000.0, cp.distance_to(t) / 0.88)
				target = t
	elif e is InputEventMouseMotion:
		var m: int = e.button_mask
		var near := cam_level_w() > 0.5
		var u := cam_up()
		if m & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			if not near:
				target += (-cb.x * e.relative.x + cb.y * e.relative.y) * dist * 0.0013
			else:
				# déplacement le long du sol : le pivot glisse sur la surface, la caméra suit la courbure
				var right := (cb.x - u * cb.x.dot(u)).normalized()
				var fw := u.cross(right)
				var rel: Vector2 = e.relative
				var mv: Vector3 = (-right * rel.x + fw * rel.y) * dist * 0.0013
				var h := alt(target)
				var ctr := Vector3(0, RC, 0)
				var nd: Vector3 = (target + mv + ctr).normalized()
				target = nd * (surf_eval(nd).x + h) - ctr
				cb = Basis(Quaternion(u, up_at(target))) * cb
		elif m & MOUSE_BUTTON_MASK_LEFT:
			# rotation autour de la verticale locale (et non de l'axe Y du monde), inclinaison bornée
			cb = Basis(u if near else cb.y, -e.relative.x * 0.005) * cb
			var nb := Basis(cb.x, -e.relative.y * 0.005) * cb
			if not near or (nb.z.dot(u) < 0.995 and nb.z.dot(u) > -0.2):
				cb = nb
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
		elif e.keycode == KEY_ESCAPE and bridge != null and bridge.visible and bridge.focused != null:
			bridge.unfocus()
		elif e.keycode == KEY_ESCAPE:
			get_tree().quit()


func _process(delta: float) -> void:
	time += delta
	update_cam()
	var dt := minf(delta, 0.05)
	if shots_dir != "":
		tscale = 4.0
	if auto_test:
		auto_report()
	if verif_chars:
		verif_tanks()
	if not paused:
		var sdt := dt * tscale
		var n := int(ceil(sdt / 0.05))
		for k in n:
			war.step(sdt / n)
			colony.step(sdt / n)
			strategy.step(sdt / n)
			survival.step(sdt / n)
	war.render(dt)
	update_shield(dt * (0.0 if paused else tscale))
	update_harvesters(dt * (0.0 if paused else tscale))
	update_plumes(dt)
	update_siege(dt * (0.0 if paused else tscale))
	hud_t -= delta
	if hud_t <= 0:
		hud_t = 0.4
		update_hud()
	if shots_dir != "" and war.time < 45.0:
		return
	var on := fmod(time, 1.5) < 0.4
	for b in blinks:
		if is_instance_valid(b):
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


# mode de vérification (--verif-chars) : hauteur des 4 extrémités de chenilles au-dessus du sol, pour tous les chars
func verif_tanks() -> void:
	tscale = 8.0
	for F in war.FORM:
		if F.dead:
			continue
		# angle entre l'axe Y de l'unité et la normale réelle du sol (mesurée sur 3 m)
		var sh0: Vector3 = F.f_cache * ((F.s - F.s_cache) * war.RL)
		for i in F.alive:
			var ub: Basis
			var p0: Vector3
			if F.kind == "tank":
				ub = F.tanks[i].h.global_transform.basis
				p0 = F.tanks[i].h.global_position
			else:
				ub = F.mb[i]
				p0 = F.pos[i] + sh0
			var nn := ground_normal(p0, 3.0)
			var ang := rad_to_deg(acos(clampf(ub.y.normalized().dot(nn), -1.0, 1.0)))
			verif_amax = maxf(verif_amax, ang)
			verif_asum += ang
			verif_an += 1
		if F.kind != "tank":
			# fantassins : extrémités du corps couché (tête et pieds, ±1,0 m) au-dessus du sol
			var sh: Vector3 = F.f_cache * ((F.s - F.s_cache) * war.RL)
			for i in F.alive:
				var b: Basis = F.mb[i]
				for e in [1.0, -1.0]:
					var a := alt(F.pos[i] + sh + b.x * e)
					verif_imin = minf(verif_imin, a)
					verif_imax = maxf(verif_imax, a)
					verif_in += 1
			continue
		for i in F.alive:
			var h: Node3D = F.tanks[i].h
			for p in [Vector3(4.3, 0.1, 2.16), Vector3(4.3, 0.1, -2.16), Vector3(-4.3, 0.1, 2.16), Vector3(-4.3, 0.1, -2.16)]:
				var a := alt(h.global_transform * p)
				verif_min = minf(verif_min, a)
				verif_max = maxf(verif_max, a)
				verif_n += 1
	if war.time > 240.0 or (verif_n > 4000 and war.time > 90.0):
		print("VERIF CHARS : %d mesures, hauteur min %.2f m, max %.2f m (RC %.0f m)" % [verif_n, verif_min, verif_max, RC])
		print("VERIF FANTASSINS : %d mesures, hauteur min %.2f m, max %.2f m" % [verif_in, verif_imin, verif_imax])
		var dmin := INF
		var dmax := -INF
		for key in war.DEAD:
			for tf in war.DEAD[key].list:
				for e in [1.0, -1.0]:
					var a := alt((tf as Transform3D).origin + (tf as Transform3D).basis.x * 0.9 * e)
					dmin = minf(dmin, a)
					dmax = maxf(dmax, a)
		print("VERIF CORPS : hauteur min %.2f m, max %.2f m" % [dmin, dmax])
		print("VERIF ANGLE : %d mesures, moyenne %.1f deg, max %.1f deg (forme %s, RC %.0f)" % [verif_an, verif_asum / maxf(1.0, verif_an), verif_amax, SH_KIND, RC])
		get_tree().quit()


# ================================================================ construction en cours de partie (colony.gd)
# échafaudage de chantier sur un emplacement libre, pendant la construction
func scaffold(slot: Vector2) -> Node3D:
	var B := base_root
	var idx := B.get_child_count()
	var g := Node3D.new()
	g.position = gp(slot.x, slot.y)
	B.add_child(g)
	box(g, "beton", Vector3(0, 0.3, 0), Vector3(22, 0.6, 22))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			strut(g, "orange_mil", Vector3(sx * 9, 0, sz * 9), Vector3(sx * 9, 14, sz * 9), 0.25, 6)
	for y: float in [5.0, 10.0, 14.0]:
		for k in 4:
			var a := Vector3([-9, 9, 9, -9][k], y, [-9, -9, 9, 9][k])
			var b := Vector3([9, 9, -9, -9][k], y, [-9, 9, 9, -9][k])
			strut(g, "danger", a, b, 0.15, 4)
	tower_crane(g, Vector3(11, 0, 11), 2.0, 22.0)
	beacon(g, Vector3(0, 15, 0))
	place_new(B, idx)
	return g


# construit le modèle 3D d'un bâtiment terminé
func construct(t: String, slot: Vector2) -> Array:
	if t == "moissonneuse":
		add_harvester()
		return [harvesters[-1].n]
	var B := base_root
	var idx := B.get_child_count()
	var yaw := rng.randf() * TAU
	match t:
		"foreuse":
			drill_rig(B, slot, yaw)
		"raffinerie":
			refinery(B, slot, yaw)
		"smr":
			fission_smr(B, slot)
		"fusion":
			reactor(B, slot)
		"catapulte":
			mass_driver(B, slot, yaw)
		"silo":
			storage_silos(B, slot)
		"reservoir":
			tank_farm(B, slot)
		"radar":
			radar_tower(B, slot)
		"calcul":
			cryo_center(B, slot)
		"observatoire":
			observatory(B, slot)
		"archives":
			ice_core_drill(B, slot)
		"chantier_arche":
			ark_yard(B, slot)
		"tourelle":
			defense_turret(B, slot)
		_:
			return []
	return place_new(B, idx)


# tourelle canon de la colonie : canon double sur tourelle blindée
func defense_turret(B: Node3D, p: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y, -0.3)
	g.set_meta("socle", 6.0)
	B.add_child(g)
	cyl(g, "blinde", Vector3(0, 0.8, 0), 5.6, 1.6, 6.0, Vector3.ZERO, 8)
	cyl(g, "danger", Vector3(0, 1.7, 0), 5.0, 0.3, -1.0, Vector3.ZERO, 8)
	cyl(g, "kaki", Vector3(0, 3.0, 0), 3.4, 2.4, 4.2, Vector3.ZERO, 8)
	var hd := Node3D.new()
	hd.position = Vector3(0, 4.6, 0)
	hd.rotation = Vector3(0, rng.randf() * TAU, 0)
	g.add_child(hd)
	box(hd, "kaki_clair", Vector3(0, 0.8, 0), Vector3(5.0, 2.2, 4.0))
	box(hd, "visiere", Vector3(1.6, 1.4, 0), Vector3(1.2, 0.5, 3.0))
	for s: float in [-0.9, 0.9]:
		var gun := cyl(hd, "blinde", Vector3(4.6, 1.4, s), 0.3, 6.0, 0.4, Vector3(0, 0, PI / 2 - 0.35), 10)
		gun.position.y += 1.0
	sph(hd, "rouge", Vector3(-1.8, 2.1, 0), 0.25)


# ---- effets de la couche stratégique (strategy.gd)
# une navette décolle du spatioport (flotte ou satellite qui part)
func launch_fx() -> void:
	if rockets.is_empty():
		return
	var r: Dictionary = rockets.pick_random()
	if r.get("busy", false):
		return
	r.busy = true
	r.plume.visible = true
	r.smoke.visible = true
	var g: Node3D = r.g
	var tw := create_tween()
	tw.tween_property(g, "position", r.base + up_at(r.base) * 140.0, 7.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): g.visible = false)
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		g.position = r.base
		g.visible = true
		r.plume.visible = false
		r.smoke.visible = false
		r.busy = false)


# une flotte rentre : une navette se pose
func land_fx() -> void:
	if rockets.is_empty():
		return
	var r: Dictionary = rockets.pick_random()
	if r.get("busy", false):
		return
	r.busy = true
	var g: Node3D = r.g
	g.position = r.base + up_at(r.base) * 120.0
	r.plume.visible = true
	var tw := create_tween()
	tw.tween_property(g, "position", r.base, 6.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		r.plume.visible = false
		r.busy = false)


# siège : les vaisseaux pirates tournent autour du bouclier et le pilonnent
func siege_begin(ships: Dictionary) -> void:
	siege_end()
	var n := 0
	for u in ships:
		n += int(ships[u])
	for i in mini(n, 14):
		var g := MeshInstance3D.new()
		g.mesh = war.FIGHTM["rbig"] if i % 3 == 0 else war.FIGHTM["r"]
		add_child(g)
		siege.append({"g": g, "a": TAU * i / maxf(1.0, mini(n, 14)), "h": rng.randf_range(0.35, 0.9), "cool": rng.randf()})


func siege_end() -> void:
	for s in siege:
		if is_instance_valid(s.g):
			if rng.randf() < 0.3:
				war.boom(s.g.position, up_at(s.g.position), 1.2)
			s.g.queue_free()
	siege.clear()


func update_siege(dt: float) -> void:
	if siege.is_empty():
		return
	var u := up_at(SHD_C)
	var a0 := u.cross(Vector3.RIGHT).normalized()
	var b0 := u.cross(a0)
	for s in siege:
		s.a += dt * 0.12
		var R := SHD_R * 1.7
		var p: Vector3 = SHD_C + (a0 * cos(s.a) + b0 * sin(s.a)) * R + u * (SHD_R * s.h + 40.0)
		var g: MeshInstance3D = s.g
		g.position = p
		var fw := (SHD_C - p).normalized()
		g.basis = Basis.looking_at(fw, u)
		s.cool -= dt
		if s.cool <= 0.0:
			s.cool = rng.randf_range(0.2, 0.6)
			war.tracer(p, SHD_C + Vector3(rng.randf_range(-30, 30), rng.randf_range(0, 40), rng.randf_range(-30, 30)), "r", 520.0)


# invasion : barges de débarquement pirates près de la base
func invasion_fx(n: int) -> void:
	for i in clampi(n / 6, 2, 5):
		war.request_drop(randf_range(0.06, 0.2))


# le bouclier a cédé : jusqu'à n bâtiments construits en jeu ou moissonneuses sont détruits
func destroy_buildings(n: int, only := "") -> Array:
	var names: Array = []
	var cand: Array = []
	for x in colony.inst:
		if x.done and (x.has("nodes") or x.t == "moissonneuse") and (only == "" or x.t == only):
			cand.append(x)
	cand.shuffle()
	for x in cand.slice(0, n):
		var nodes: Array = x.get("nodes", [])
		if x.t == "moissonneuse" and nodes.is_empty() and harvesters.size() > 0:
			var h: Dictionary = harvesters.pop_back()
			nodes = [h.n]
		for nd in nodes:
			if is_instance_valid(nd):
				war.boom(nd.global_position, up_at(nd.global_position), 2.5)
				for hh in harvesters:
					if hh.n == nd:
						harvesters.erase(hh)
						break
				nd.queue_free()
		if x.get("slot", -1) >= 0:
			colony.slot_used.erase(x.slot)
		colony.inst.erase(x)
		names.append(colony.BLD[x.t].name)
	blinks = blinks.filter(func(b): return is_instance_valid(b))
	return names


# ================================================================ centre de commandement : bouclier du réacteur à hélium-3
# Activé au début de la partie. Le dôme ne laisse passer que les troupes au sol : tirs, obus et vaisseaux venant
# de l'extérieur s'y écrasent (les tirs partant de l'intérieur sortent librement).
const SHD_R := 110.0          # rayon du dôme (m)
var SHD_C := Vector3.ZERO     # centre : le poste de commandement
var SHD_E := 100.0            # énergie du bouclier (%) ; le réacteur la recharge
var SHD_DOWN := 0.0           # temps restant avant le rallumage après un effondrement (s)
var shd_mat: ShaderMaterial
var shd_node: MeshInstance3D
var shd_hits: Array = []      # [direction locale, âge] des derniers impacts (anneaux sur le dôme)
var HANGARS: Array = []


func build_shield() -> void:
	SHD_C = gp(0, 0)
	var sm := SphereMesh.new()
	sm.radius = SHD_R
	sm.height = SHD_R * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	shd_mat = ShaderMaterial.new()
	shd_mat.shader = load("res://shaders/shield.gdshader")
	shd_node = MeshInstance3D.new()
	shd_node.mesh = sm
	shd_node.material_override = shd_mat
	shd_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shd_node.position = SHD_C
	add_child(shd_node)
	for i in 8:
		shd_hits.append([Vector3.UP, 99.0])


func shield_up() -> bool:
	return SHD_DOWN <= 0.0 and war != null and war.time > 1.0


# point où le segment a → b entre dans le dôme (null si a est déjà dedans, ou si le segment ne le touche pas)
func shield_clip(a: Vector3, b: Vector3):
	if not shield_up():
		return null
	var f := a - SHD_C
	if f.length_squared() <= SHD_R * SHD_R:
		return null
	var d := b - a
	var A := d.dot(d)
	var Bq := 2.0 * f.dot(d)
	var Cq := f.dot(f) - SHD_R * SHD_R
	var disc := Bq * Bq - 4.0 * A * Cq
	if disc < 0.0 or A < 1e-6:
		return null
	var t := (-Bq - sqrt(disc)) / (2.0 * A)
	if t < 0.0 or t > 1.0:
		return null
	return a + d * t


# impact sur le dôme : anneau lumineux, perte d'énergie (le bouclier s'effondre 12 s s'il tombe à zéro)
func shield_hit(p: Vector3, cost := 0.35) -> void:
	var k := 0
	for i in shd_hits.size():
		if shd_hits[i][1] > shd_hits[k][1]:
			k = i
	shd_hits[k] = [(p - SHD_C).normalized(), 0.0]
	SHD_E -= cost
	if SHD_E <= 0.0:
		SHD_E = 0.0
		SHD_DOWN = 12.0


# un vaisseau ennemi ne peut pas entrer : il est repoussé à la surface du dôme (plus une marge)
func shield_push(p: Vector3, margin: float) -> Vector3:
	if not shield_up():
		return p
	var v := p - SHD_C
	var L := v.length()
	if L < SHD_R + margin and L > 0.01:
		return SHD_C + v / L * (SHD_R + margin)
	return p


func update_shield(dt: float) -> void:
	if shd_mat == null:
		return
	if SHD_DOWN > 0.0:
		SHD_DOWN -= dt
	# le réacteur à hélium-3 recharge le bouclier
	var fac: float = colony.shield_factor() if colony != null else 1.0
	SHD_E = minf(100.0, SHD_E + dt * (2.5 * fac if SHD_DOWN <= 0.0 else 6.0))
	var arr: Array = []
	for h in shd_hits:
		h[1] += dt
		arr.append(Vector4(h[0].x, h[0].y, h[0].z, h[1]))
	shd_mat.set_shader_parameter("hits", arr)
	# activation au début de la partie : le dôme monte depuis le sol
	var act := clampf((war.time - 1.0) / 4.0, 0.0, 1.0) if war != null else 0.0
	shd_mat.set_shader_parameter("act", act)
	shd_mat.set_shader_parameter("energy", 0.0 if SHD_DOWN > 0.0 else SHD_E / 100.0)


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
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(tr)
	screen_tex = tr
	screen_layer = cl
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
	get_viewport().size_changed.connect(layout_screen)


# ================================================================ interface façon bande dessinée
func bd_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.1, 0.78)
	sb.border_color = Color(0.37, 0.83, 1.0, 0.7)
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	return sb


func bd_label(size: int, col := Color("d8ecff"), bold := 600) -> Label:
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
	hud_root = root
	var title := Label.new()
	title.text = "K-240 · FRONT DE SURFACE"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffb84a"))
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
	var shd_txt := "EFFONDRÉ (%ds)" % int(ceil(SHD_DOWN)) if SHD_DOWN > 0.0 else ("ACTIVATION" if war.time < 5.0 else "%d %%" % int(SHD_E))
	lbl_stats.text = "IMAGES/S         %d\nASTÉROÏDE        Ø %.1f km\n                 (x%.1f le front)\nFORME            %s\nDENSITÉ          %.2f g/cm³\nGRAVITÉ          %.3f mm/s²\nLIBÉRATION       %.2f m/s\n\nCENTRE CMD.      ACTIF\nRÉACTEUR He-3    EN SERVICE\nBOUCLIER         %s\nNAVETTES PIRATES %d en vol\n                 %d abattues\n\nVAGUE            %d\nPERTES PIRATES   %d\nPERTES COLONIE   %d\nVITESSE          %s\n\nLIGNE DE FRONT\n%s" % [Engine.get_frames_per_second(), RC * 2.0 / 1000.0, TAILLE_K, SH_TYPE, SH_RHO / 1000.0, AST_G * 1000.0, AST_VESC, shd_txt, h.ds, h.ds_down, h.wave, h.kills.b, h.kills.r, spd, bar]


# ================================================================ passerelle de commandement (bridge.gd)
# place la vue 3D dans l'écran principal de la passerelle, ou en plein écran (Tab)
func layout_screen() -> void:
	if screen_tex == null:
		return
	var full := Vector2(get_viewport().size)
	var r := Rect2(Vector2.ZERO, full)
	var on: bool = bridge != null and bridge.visible
	# sur la passerelle, la vue 3D fait partie de l'écran principal (moniteur du cockpit, ou écran agrandi)
	if on:
		if screen_tex.get_parent() != bridge.center:
			screen_tex.reparent(bridge.center, false)
			bridge.center.move_child(screen_tex, 0)
		r = bridge.screen_rect_local()
		screen_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		if screen_tex.get_parent() != screen_layer:
			screen_tex.reparent(screen_layer, false)
		screen_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_tex.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen_tex.position = r.position
	screen_tex.size = r.size
	sv.size = Vector2i(maxi(64, int(r.size.x)), maxi(64, int(r.size.y)))
	post.set_shader_parameter("res", Vector2(sv.size))
	screen_tex.visible = not (on and bridge.map != null and bridge.map.visible)
	if style_lbl != null:
		style_lbl.visible = not on
	if hud_root != null:
		hud_root.visible = not on


func toggle_bridge() -> void:
	if bridge == null:
		return
	bridge.visible = not bridge.visible
	layout_screen()


# mode --autopilote : partie jouée par le pilote automatique à ×8, rapport chaque minute de jeu
func auto_report() -> void:
	tscale = 8.0
	if war.time < auto_next:
		return
	auto_next += 60.0
	var S = strategy
	var fl: Array = []
	for f in S.fleets:
		fl.append("%s[%s %s]" % [f.name, f.loc, S.ships_txt(f.ships)])
	print("T+%d min | santé %d | fer %d rég %d cr %d He3 %d glace %d | énergie %d/%d | moral %d pop %d | bât %d | tech %s | hangar %s | flottes %s | colonies %s | Kronos %s flotte %s def %d | raids %d | bouclier %d | %s" % [
		int(war.time / 60.0), survival.health, colony.stock.fer, colony.stock.regolithe, colony.stock.credits, colony.stock.he3, colony.stock.glace,
		colony.energy.p, colony.energy.c, colony.morale, colony.pop, colony.inst.size(), colony.tech_done.keys(),
		S.ships_txt(S.hangar), fl, S.col.keys(), "MORT" if S.E.dead else "vivant", S.ships_txt(S.E.fleet), S.E.bld.defense,
		S.E.atkN, SHD_E, S.bot_intent])
	if S.won or S.lost or war.time > 3600.0:
		print("FIN : ", "VICTOIRE" if S.won else ("DÉFAITE" if S.lost else "temps écoulé"), " à T+%d min" % int(war.time / 60.0))
		for l in S.combat_log:
			print("  ", l)
		get_tree().quit()


# ================================================================ bâtiments scientifiques et chantier interstellaire
# centre de calcul cryogénique : baies de serveurs dans un caisson blindé, radiateurs au froid du vide
func cryo_center(B: Node3D, p: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y, -0.3)
	g.set_meta("socle", 9.0)
	B.add_child(g)
	box(g, "beton", Vector3(0, 0.5, 0), Vector3(16, 1.0, 14))
	box(g, "gris_dep", Vector3(0, 3.6, 0), Vector3(12, 5.2, 9))
	box(g, "blinde", Vector3(0, 6.4, 0), Vector3(12.4, 0.5, 9.4))
	for k in 6:
		box(g, "bleu", Vector3(-5 + k * 2.0, 3.6, 4.55), Vector3(1.2, 3.6, 0.1))
	hazard_x(g, Vector3(0, 1.3, 4.6), 12.0)
	# radiateurs : grandes ailettes dressées vers le ciel noir
	for k in 5:
		var f := box(g, "tuyau", Vector3(-4 + k * 2.0, 10.0, -1.0), Vector3(0.15, 7.0, 5.0))
		f.rotation.x = -0.15
	for k in 3:
		cyl(g, "kaki", Vector3(-5.5 + k * 5.5, 1.8, -6.0), 1.0, 2.6, -1.0, Vector3.ZERO, 12)
	hose(g, Vector3(-5.5, 3.0, -6.0), Vector3(-4.0, 6.4, -3.5), -0.6, 0.2)
	beacon(g, Vector3(5.5, 7.2, 3.8))
	lamp(g, Vector3(0, 4, 7), Color("7fd6ff"), 2.5, 18)


# observatoire profond : coupole ouverte et grand télescope pointé vers l'univers
func observatory(B: Node3D, p: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y, -0.3)
	g.set_meta("socle", 8.0)
	B.add_child(g)
	cyl(g, "beton", Vector3(0, 0.6, 0), 7.5, 1.2, 8.0, Vector3.ZERO, 24)
	cyl(g, "gris_dep", Vector3(0, 3.4, 0), 5.5, 4.4, 5.8, Vector3.ZERO, 24)
	sph(g, "blanc", Vector3(0, 5.6, 0), 5.4, true)
	box(g, "noir", Vector3(0, 8.5, 0), Vector3(2.2, 6.0, 11.2))
	var tel := Node3D.new()
	tel.position = Vector3(0, 7.0, 0)
	tel.rotation = Vector3(0.55, 0.3, 0)
	g.add_child(tel)
	cyl(tel, "tuyau", Vector3(0, 3.0, 0), 1.0, 7.0, 1.3, Vector3.ZERO, 16)
	cyl(tel, "blinde", Vector3(0, 6.6, 0), 1.1, 0.4, -1.0, Vector3.ZERO, 16)
	cyl(g, "danger", Vector3(0, 1.6, 0), 5.85, 0.3, -1.0, Vector3.ZERO, 24)
	dish_tower(g, Vector3(9.0, 0, 3.0), 8.0, 2.4)
	lamp(g, Vector3(0, 3, 7), Color("ffd29a"), 2.0, 16)


# forage des archives : tour de carottage, carottes de glace stockées en râteliers
func ice_core_drill(B: Node3D, p: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y, -0.2)
	g.set_meta("socle", 6.0)
	B.add_child(g)
	box(g, "blinde", Vector3(0, 0.5, 0), Vector3(9, 1.0, 9))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			strut(g, "tuyau", Vector3(sx * 2.5, 1.0, sz * 2.5), Vector3(sx * 0.6, 14.0, sz * 0.6), 0.18, 6)
	cyl(g, "bleu", Vector3(0, 7.0, 0), 0.3, 12.0)
	box(g, "gris_dep", Vector3(0, 14.6, 0), Vector3(2.0, 1.2, 2.0))
	beacon(g, Vector3(0, 15.4, 0))
	# râteliers de carottes de glace bleutée
	for k in 8:
		var c := cyl(g, "bleu", Vector3(3.2 + (k % 2) * 0.7, 1.6, -2.8 + k * 0.7), 0.25, 1.8, -1.0, Vector3(0, 0, PI / 2), 8)
		c.scale = Vector3(1, 1, 1)
	box(g, "kaki", Vector3(-3.2, 2.2, 0), Vector3(2.4, 2.4, 3.6))
	box(g, "vert", Vector3(-1.98, 2.6, 0), Vector3(0.05, 0.6, 2.0))
	lamp(g, Vector3(0, 3, 5), Color("9fd8ff"), 2.0, 14)


# chantier interstellaire : portique géant en microgravité ; la coque du vaisseau-arche s'y allonge
func ark_yard(B: Node3D, p: Vector2) -> void:
	var g := Node3D.new()
	g.position = gp(p.x, p.y)
	B.add_child(g)
	var feet: Array = []
	for k in 6:
		var x := -30.0 + k * 12.0
		for s: float in [-1.0, 1.0]:
			strut(g, "orange_mil", Vector3(x, 0, s * 11), Vector3(x, 26, s * 11), 0.5, 8)
			feet.append(Vector3(x, 0, s * 11))
		strut(g, "orange_mil", Vector3(x, 26, -11), Vector3(x, 26, 11), 0.45, 8)
	strut(g, "orange_mil", Vector3(-30, 26, -11), Vector3(30, 26, -11), 0.45, 8)
	strut(g, "orange_mil", Vector3(-30, 26, 11), Vector3(30, 26, 11), 0.45, 8)
	g.set_meta("pieds", feet)
	tower_crane(g, Vector3(36, 0, 0), 1.2, 34.0)
	# coque de l'arche (sa longueur suit l'assemblage)
	ark_hull = Node3D.new()
	ark_hull.position = Vector3(-30, 13, 0)
	g.add_child(ark_hull)
	cyl(ark_hull, "blanc", Vector3(30, 0, 0), 6.0, 60.0, -1.0, Vector3(0, 0, PI / 2), 24)
	for k in 6:
		cyl(ark_hull, "blinde", Vector3(5 + k * 10.0, 0, 0), 6.3, 1.2, -1.0, Vector3(0, 0, PI / 2), 24)
	cyl(ark_hull, "noyau", Vector3(-1.0, 0, 0), 5.0, 1.0, -1.0, Vector3(0, 0, PI / 2), 24)
	ark_hull.scale = Vector3(0.02, 1, 1)
	for k in 4:
		lamp(g, Vector3(-24 + k * 16.0, 24, 0), Color("cfe6ff"), 3.0, 30)
	beacon(g, Vector3(0, 27, 0))


func ark_visual(progress: float) -> void:
	if ark_hull != null and is_instance_valid(ark_hull):
		ark_hull.scale = Vector3(maxf(0.02, progress / 100.0), 1, 1)
