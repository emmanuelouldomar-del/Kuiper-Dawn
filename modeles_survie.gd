## Kuiper Dawn — modèles 3D des bâtiments de survie (capsule d'atterrissage, modules, électrolyseur, panneaux…),
## construits avec les primitives de main.gd (box, cyl, sph, strut…), dans le style de la base : métal gris,
## accents orange, vitres dorées. Coordonnées avant la réduction BSC (la base entière est réduite de moitié).
extends RefCounted

var w  # main.gd


func _init(world) -> void:
	w = world


func root(B: Node3D, p: Vector2, socle: float, yaw := 0.0) -> Node3D:
	var g := Node3D.new()
	g.position = w.gp(p.x, p.y, -0.2)
	g.rotation.y = yaw
	if socle > 0.0:
		g.set_meta("socle", socle)
	B.add_child(g)
	return g


# construit le modèle du bâtiment t ; faux si le type n'a pas de modèle ici
func build(B: Node3D, t: String, p: Vector2, yaw: float) -> bool:
	match t:
		"capsule":
			capsule(B, p, yaw)
		"sas":
			sas(B, p, yaw)
		"station_eau":
			station_eau(B, p, yaw)
		"electrolyseur":
			electrolyseur(B, p, yaw)
		"epurateur":
			epurateur(B, p, yaw)
		"solaire":
			solaire(B, p, yaw)
		"batterie":
			batterie(B, p, yaw)
		"radiateur":
			radiateur(B, p, yaw)
		"regulateur":
			regulateur(B, p, yaw)
		"foreuse_prof":
			foreuse_prof(B, p, yaw)
		"imprimante":
			imprimante(B, p, yaw)
		"serre":
			serre(B, p, yaw)
		"recycleur":
			recycleur(B, p, yaw)
		"infirmerie":
			infirmerie(B, p, yaw)
		"generateur_h2":
			generateur_h2(B, p, yaw)
		"drones":
			drones(B, p, yaw)
		"propulseurs":
			propulseurs(B, p, yaw)
		"laser":
			laser(B, p, yaw)
		_:
			return false
	return true


# capsule d'atterrissage : corps conique, bouclier thermique noirci, 4 jambes, panneaux, sas, antenne
func capsule(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 0.0, yaw)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var foot := Vector3(cos(a) * 9.0, 0.3, sin(a) * 9.0)
		w.strut(g, "kaki_clair", Vector3(cos(a) * 4.0, 4.0, sin(a) * 4.0), foot, 0.3, 6)
		w.cyl(g, "blinde", foot, 1.1, 0.4)
	w.cyl(g, "noir", Vector3(0, 3.2, 0), 5.2, 1.0, 5.6)
	w.cyl(g, "kaki", Vector3(0, 6.8, 0), 3.0, 6.2, 5.0)
	w.cyl(g, "kaki_clair", Vector3(0, 10.4, 0), 2.0, 1.2, 3.0)
	w.cyl(g, "blinde", Vector3(0, 11.5, 0), 1.2, 1.0, 2.0)
	w.box(g, "visiere", Vector3(4.2, 7.2, 0), Vector3(0.4, 1.4, 2.4), Vector3(0, 0, -0.5))
	w.box(g, "blinde", Vector3(0, 5.0, 4.3), Vector3(2.6, 3.2, 1.2))
	w.box(g, "orange_mil", Vector3(0, 6.9, 4.8), Vector3(2.8, 0.25, 0.3))
	for sd: float in [-1.0, 1.0]:
		w.strut(g, "acier_sombre", Vector3(sd * 3.5, 8.0, 0), Vector3(sd * 7.0, 8.4, 0), 0.12, 4)
		w.box(g, "solaire", Vector3(sd * 9.5, 8.4, 0), Vector3(5.0, 0.15, 3.2), Vector3(0.0, 0.0, sd * 0.25))
	w.cyl(g, "acier", Vector3(1.0, 13.8, 0), 0.06, 3.6)
	w.beacon(g, Vector3(1.0, 15.7, 0))
	w.lamp(g, Vector3(0, 6, 6), Color("ffd29a"), 1.5, 14)
	# traînée de l'atterrissage forcé : sillon de régolithe
	w.box(g, "beton", Vector3(-11, 0.1, 2), Vector3(16, 0.35, 5), Vector3(0, 0.2, 0))


# module pressurisé sous une butte de régolithe, sas à visière, tuyaux
func sas(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 9.0, yaw)
	w.cyl(g, "kaki_clair", Vector3(0, 3.5, 0), 3.4, 14.0, -1.0, Vector3(0, 0, PI / 2))
	for sd: float in [-1.0, 1.0]:
		w.sph(g, "kaki_clair", Vector3(sd * 7.0, 3.5, 0), 3.4)
	w.sph(g, "beton", Vector3(0, 2.0, 0), 6.5, true).scale = Vector3(1.45, 0.75, 0.9)
	w.box(g, "blinde", Vector3(9.8, 2.6, 0), Vector3(3.2, 4.4, 4.2))
	w.box(g, "visiere", Vector3(11.45, 2.6, 0), Vector3(0.2, 3.0, 2.6))
	w.box(g, "orange_mil", Vector3(9.8, 5.0, 0), Vector3(3.3, 0.3, 4.3))
	for k in 3:
		w.box(g, "visiere", Vector3(-4.0 + k * 4.0, 4.6, 3.4), Vector3(1.6, 0.8, 0.3))
	w.beacon(g, Vector3(9.8, 5.6, 1.6))


# station d'eau : fondoir de glace, réservoir sphérique blanc, tuyaux, lueur bleue
func station_eau(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 8.0, yaw)
	w.box(g, "blinde", Vector3(0, 0.5, 0), Vector3(15, 1.0, 11))
	w.sph(g, "blanc", Vector3(-3.5, 5.2, 0), 4.2)
	w.cyl(g, "gris_dep", Vector3(3.5, 3.5, -2.0), 2.0, 6.0)
	w.cyl(g, "bleu", Vector3(3.5, 6.7, -2.0), 1.6, 0.4)
	w.cyl(g, "kaki_clair", Vector3(4.0, 2.0, 3.0), 1.4, 3.0)
	w.hose(g, Vector3(-0.5, 5.0, 0), Vector3(2.2, 5.0, -2.0), 0.5)
	w.hose(g, Vector3(3.5, 1.5, 0.5), Vector3(4.0, 1.5, 2.0), 0.3)
	w.box(g, "orange_mil", Vector3(0, 1.1, 5.5), Vector3(15, 0.25, 0.3))


# électrolyseur : bloc de cellules à lueur bleue, réservoirs O2 (blanc) et H2 (orange)
func electrolyseur(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 8.0, yaw)
	w.box(g, "gris_dep", Vector3(0, 2.2, 0), Vector3(10, 4.4, 7))
	for k in 4:
		w.box(g, "bleu", Vector3(-3.6 + k * 2.4, 2.2, 3.55), Vector3(1.4, 2.6, 0.15))
	w.cyl(g, "blanc", Vector3(-3.0, 7.0, 0), 1.8, 6.0)
	w.sph(g, "blanc", Vector3(-3.0, 10.0, 0), 1.8)
	w.cyl(g, "orange_mil", Vector3(3.0, 6.0, 0), 1.4, 4.0)
	w.sph(g, "orange_mil", Vector3(3.0, 8.0, 0), 1.4)
	w.hose(g, Vector3(-3.0, 4.4, 1.0), Vector3(3.0, 4.4, 1.0), 0.4, 0.15)
	w.box(g, "danger", Vector3(0, 0.15, 0), Vector3(11, 0.3, 8))


# épurateur de CO2 : caisson, ventilateurs sur le toit, râteliers de cartouches
func epurateur(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 7.0, yaw)
	w.box(g, "kaki", Vector3(0, 2.5, 0), Vector3(9, 5, 7))
	for k in 2:
		w.cyl(g, "noir", Vector3(-2.2 + k * 4.4, 5.3, 0), 1.8, 0.6)
		w.cyl(g, "acier_sombre", Vector3(-2.2 + k * 4.4, 5.7, 0), 0.4, 0.4)
	for k in 5:
		w.cyl(g, "vert", Vector3(-3.2 + k * 1.6, 2.0, 3.8), 0.45, 2.6)
	w.box(g, "orange_mil", Vector3(0, 4.9, 3.55), Vector3(9.1, 0.25, 0.2))


# champ de panneaux solaires inclinés sur montants
func solaire(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 0.0, yaw)
	for i in 4:
		for j in 2:
			var c := Vector3(-9.0 + i * 6.0, 0, -3.5 + j * 7.0)
			w.cyl(g, "acier_sombre", c + Vector3(0, 1.4, 0), 0.18, 2.8)
			w.box(g, "solaire", c + Vector3(0, 3.0, 0), Vector3(5.4, 0.15, 6.0), Vector3(0.45, 0, 0))
			w.box(g, "kaki_clair", c + Vector3(0, 2.9, 0), Vector3(5.6, 0.1, 0.3), Vector3(0.45, 0, 0))


# batteries : rangée de cellules blindées à bandes vertes
func batterie(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 7.0, yaw)
	w.box(g, "beton", Vector3(0, 0.3, 0), Vector3(14, 0.6, 7))
	for k in 6:
		var x := -5.5 + k * 2.2
		w.box(g, "blinde", Vector3(x, 2.4, 0), Vector3(1.8, 3.6, 5.0))
		w.box(g, "vert", Vector3(x, 3.6, 2.55), Vector3(1.2, 0.3, 0.1))
	w.hose(g, Vector3(-6.5, 4.3, 0), Vector3(6.5, 4.3, 0), 0.6, 0.2)


# radiateurs : grandes ailettes blanches verticales sur cadre, base chaude
func radiateur(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 0.0, yaw)
	w.box(g, "blinde", Vector3(0, 0.6, 0), Vector3(14, 1.2, 3))
	w.box(g, "chaud", Vector3(0, 1.3, 0), Vector3(13, 0.2, 1.0))
	for k in 6:
		w.box(g, "blanc", Vector3(-6.0 + k * 2.4, 6.0, 0), Vector3(0.18, 9.0, 2.6))
	w.box(g, "kaki_clair", Vector3(0, 10.6, 0), Vector3(14, 0.3, 0.5))


# régulateur thermique : caisson, échangeurs, ventilateurs, lueur chaude
func regulateur(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 6.0, yaw)
	w.box(g, "kaki", Vector3(0, 2.4, 0), Vector3(8, 4.8, 6))
	w.box(g, "chaud", Vector3(0, 2.4, 3.05), Vector3(5, 1.0, 0.1))
	for k in 3:
		w.cyl(g, "tuyau", Vector3(-2.5 + k * 2.5, 6.0, 0), 0.6, 2.4)
	w.hose(g, Vector3(-4.0, 1.0, -2.0), Vector3(-7.0, 0.5, -4.0), 0.6, 0.25)


# foreuse de profondeur : derrick en treillis, puits lumineux, rampe d'accès aux galeries
func foreuse_prof(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 11.0, yaw)
	w.box(g, "beton", Vector3(0, 0.4, 0), Vector3(20, 0.8, 18))
	w.cyl(g, "noyau", Vector3(0, 0.9, 0), 2.4, 0.3)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			w.strut(g, "orange_mil", Vector3(sx * 4.5, 0.8, sz * 4.5), Vector3(sx * 0.8, 24.0, sz * 0.8), 0.28, 6)
	for y: float in [6.0, 12.0, 18.0]:
		var r := 4.5 - (y / 24.0) * 3.7
		for k in 4:
			var a := Vector3([-r, r, r, -r][k], y, [-r, -r, r, r][k])
			var b := Vector3([r, r, -r, -r][k], y, [-r, r, r, -r][k])
			w.strut(g, "kaki_clair", a, b, 0.14, 4)
	w.cyl(g, "acier", Vector3(0, 12.0, 0), 0.5, 22.0)
	w.box(g, "blinde", Vector3(0, 24.5, 0), Vector3(3, 1.5, 3))
	w.box(g, "beton", Vector3(-8.0, 0.2, 9.0), Vector3(6, 0.5, 10), Vector3(-0.18, 0, 0))
	w.box(g, "noir", Vector3(-8.0, 0.6, 13.5), Vector3(4.6, 3.0, 0.4))
	w.dust(g, Vector3(0, 2.0, 0), 5.0, 0.35)
	w.beacon(g, Vector3(0, 25.6, 0))


# imprimante 3D industrielle : halle à vitres, portique d'impression
func imprimante(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 9.0, yaw)
	w.box(g, "gris_dep", Vector3(0, 3.0, 0), Vector3(14, 6, 10))
	w.box(g, "vitre", Vector3(0, 3.6, 5.05), Vector3(10, 2.0, 0.1))
	for sd: float in [-1.0, 1.0]:
		w.strut(g, "orange_mil", Vector3(sd * 6.5, 6.0, -4.0), Vector3(sd * 6.5, 10.0, -4.0), 0.25, 6)
		w.strut(g, "orange_mil", Vector3(sd * 6.5, 6.0, 4.0), Vector3(sd * 6.5, 10.0, 4.0), 0.25, 6)
	w.box(g, "orange_mil", Vector3(0, 10.0, 0), Vector3(13.5, 0.5, 0.6))
	w.box(g, "blinde", Vector3(2.0, 9.3, 0), Vector3(1.4, 1.2, 1.4))


# serre hydroponique : demi-tunnel vitré doré, bacs de culture verts sous lampes
func serre(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 10.0, yaw)
	w.box(g, "beton", Vector3(0, 0.3, 0), Vector3(20, 0.6, 10))
	w.cyl(g, "visiere_verre", Vector3(0, 0.6, 0), 4.8, 18.0, -1.0, Vector3(0, 0, PI / 2), 16)
	for k in 7:
		w.cyl(g, "kaki_clair", Vector3(-9.0 + k * 3.0, 0.6, 0), 4.9, 0.25, -1.0, Vector3(0, 0, PI / 2), 16)
	for k in 3:
		w.box(g, "vert", Vector3(-6.0 + k * 6.0, 1.3, 0), Vector3(4.6, 0.8, 5.0))
	w.lamp(g, Vector3(0, 4.0, 0), Color("ffb0f0"), 1.5, 14)


# recycleur : trémie, broyeur, convoyeur
func recycleur(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 7.0, yaw)
	w.box(g, "kaki", Vector3(0, 2.5, 0), Vector3(8, 5, 8))
	w.cyl(g, "rouille", Vector3(0, 7.0, 0), 1.0, 4.0, 3.2)
	w.box(g, "acier_sombre", Vector3(7.0, 1.6, 0), Vector3(8, 0.5, 1.6), Vector3(0, 0, 0.25))
	w.box(g, "orange_mil", Vector3(0, 5.05, 0), Vector3(8.1, 0.2, 8.1))
	w.smoke_stack(g, Vector3(-3.0, 6.5, -3.0), 1, Color(0.45, 0.42, 0.38))


# infirmerie : module blanc, croix rouge lumineuse, sas
func infirmerie(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 8.0, yaw)
	w.cyl(g, "blanc", Vector3(0, 3.0, 0), 5.0, 6.0, -1.0, Vector3.ZERO, 8)
	w.cyl(g, "kaki_clair", Vector3(0, 6.3, 0), 4.0, 0.6, 5.0, Vector3.ZERO, 8)
	w.box(g, "rouge", Vector3(0, 3.6, 4.9), Vector3(2.4, 0.7, 0.1))
	w.box(g, "rouge", Vector3(0, 3.6, 4.9), Vector3(0.7, 2.4, 0.1))
	w.box(g, "blinde", Vector3(5.6, 2.0, 0), Vector3(2.4, 3.6, 3.0))


# générateur à hydrogène : réservoir couché, groupe électrogène, échappement
func generateur_h2(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 7.0, yaw)
	w.cyl(g, "blanc", Vector3(0, 2.4, -2.0), 2.0, 10.0, -1.0, Vector3(0, 0, PI / 2))
	for sd: float in [-1.0, 1.0]:
		w.sph(g, "blanc", Vector3(sd * 5.0, 2.4, -2.0), 2.0)
	w.box(g, "orange_mil", Vector3(0, 1.8, 3.0), Vector3(7, 3.6, 4))
	w.cyl(g, "acier_sombre", Vector3(3.0, 5.0, 3.0), 0.4, 3.0)
	w.box(g, "danger", Vector3(0, 0.15, 0), Vector3(12, 0.3, 10))


# hub de drones : aire balisée, mât, petits drones posés et en vol
func drones(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 8.0, yaw)
	w.cyl(g, "tarmac", Vector3(0, 0.25, 0), 8.0, 0.5, -1.0, Vector3.ZERO, 8)
	w.cyl(g, "danger", Vector3(0, 0.55, 0), 6.0, 0.1, -1.0, Vector3.ZERO, 8)
	w.cyl(g, "acier", Vector3(-6.0, 4.0, 0), 0.25, 8.0)
	w.beacon(g, Vector3(-6.0, 8.3, 0))
	for k in 3:
		var a := TAU * k / 3.0
		var d := Vector3(cos(a) * 3.0, 1.0 + (5.0 if k == 0 else 0.0), sin(a) * 3.0)
		w.box(g, "kaki_clair", d, Vector3(1.2, 0.4, 1.2))
		for s in 4:
			var b := TAU * s / 4.0 + PI / 4.0
			w.cyl(g, "noir", d + Vector3(cos(b) * 0.9, 0.3, sin(b) * 0.9), 0.45, 0.06)


# propulseur d'attitude : tuyère sur cardan, réservoirs d'hydrogène, bâti
func propulseurs(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 8.0, yaw)
	w.box(g, "blinde", Vector3(0, 1.5, 0), Vector3(9, 3, 9))
	for sd: float in [-1.0, 1.0]:
		w.sph(g, "blanc", Vector3(sd * 3.0, 4.6, -2.5), 1.8)
	w.cyl(g, "acier_sombre", Vector3(0, 6.0, 1.0), 1.2, 3.0, 2.6, Vector3(0.35, 0, 0))
	w.cyl(g, "noyau", Vector3(0, 7.5, 1.55), 2.3, 0.2, -1.0, Vector3(0.35, 0, 0))
	w.box(g, "orange_mil", Vector3(0, 3.05, 0), Vector3(9.1, 0.25, 9.1))


# tourelle laser : fût, tête tournante, émetteur lumineux
func laser(B: Node3D, p: Vector2, yaw: float) -> void:
	var g := root(B, p, 5.0, yaw)
	w.cyl(g, "beton", Vector3(0, 0.6, 0), 4.5, 1.2, 5.0, Vector3.ZERO, 8)
	w.cyl(g, "gris_dep", Vector3(0, 5.0, 0), 1.6, 8.0, 2.2)
	var hd := Node3D.new()
	hd.position = Vector3(0, 9.5, 0)
	hd.set_meta("laser_head", true)
	g.add_child(hd)
	w.box(hd, "blinde", Vector3(0, 0, 0), Vector3(3.6, 2.0, 2.6))
	w.cyl(hd, "acier_sombre", Vector3(2.8, 0.4, 0), 0.35, 3.0, -1.0, Vector3(0, 0, PI / 2))
	w.cyl(hd, "rouge", Vector3(4.35, 0.4, 0), 0.3, 0.15, -1.0, Vector3(0, 0, PI / 2))
	w.box(hd, "orange_mil", Vector3(0, 1.05, 0), Vector3(3.7, 0.15, 2.7))
