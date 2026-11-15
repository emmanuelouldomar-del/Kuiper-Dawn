## Kuiper Dawn — économie et gestion de la colonie K-240 (portées du remake HTML « K-240 Remake »)
## Ressources, bâtiments de surface (production, consommation, énergie, stockage, pollution),
## construction sur des emplacements libres, recherche, population, moral et impôts.
## En surface : industrie polluante, extraction et stockage. La vie de la colonie est sous terre (chiffres seulement).
extends Node

var w  # main.gd

# ---------------------------------------------------------------- données du jeu (gamedata)
const RES := {
	"regolithe": {"name": "Régolithe", "start": 200.0, "cap": 500.0, "color": Color("5fb3a1")},
	"fer": {"name": "Fer-nickel", "start": 60.0, "cap": 300.0, "color": Color("b9c2cc")},
	"credits": {"name": "Crédits", "start": 120.0, "cap": 1000.0, "color": Color("ffa24a")},
	"glace": {"name": "Glace d’eau", "start": 60.0, "cap": 400.0, "color": Color("9fe3ff")},
	"he3": {"name": "Hélium-3", "start": 40.0, "cap": 200.0, "color": Color("c9a6ff")},
	"gaz": {"name": "Gaz rares", "start": 0.0, "cap": 200.0, "color": Color("7fd6c2")},
	"volatils": {"name": "Volatils", "start": 0.0, "cap": 300.0, "color": Color("d6c27f")},
	"precieux": {"name": "Métaux précieux", "start": 10.0, "cap": 150.0, "color": Color("ffd76a")},
	"uranium": {"name": "Combustible nucléaire", "start": 20.0, "cap": 120.0, "color": Color("9cff7a")},
	"terres": {"name": "Terres rares", "start": 0.0, "cap": 150.0, "color": Color("ff9ad5")},
}

# bâtiments de surface ; pollution : nuisance pour la population (moral)
const BLD := {
	"moissonneuse": {"name": "Moissonneuse-racleuse", "cost": {"regolithe": 80, "fer": 40}, "time": 10.0, "energy": -3.0,
		"produces": {"regolithe": 2.5, "he3": 0.12, "gaz": 0.15}, "pollution": 1.0, "mobile": true,
		"desc": "Racle le régolithe et le chauffe à 800 °C : Hélium-3 et gaz rares."},
	"foreuse": {"name": "Foreuse thermique", "cost": {"regolithe": 70, "fer": 30}, "time": 9.0, "energy": -3.0,
		"produces": {"glace": 1.2, "volatils": 0.6}, "pollution": 1.0,
		"desc": "Fait fondre la glace d’eau et de méthane, puis la pompe."},
	"raffinerie": {"name": "Raffinerie", "cost": {"regolithe": 120, "fer": 20}, "time": 12.0, "energy": -3.0,
		"consumes": {"regolithe": 2.0}, "produces": {"fer": 1.0, "terres": 0.06, "precieux": 0.04, "uranium": 0.02}, "pollution": 3.0,
		"desc": "Hauts fourneaux : fer-nickel, terres rares, métaux précieux et combustible. Très polluante."},
	"smr": {"name": "Réacteur à fission (SMR)", "cost": {"regolithe": 120, "fer": 80}, "time": 14.0, "energy": 14.0,
		"consumes": {"uranium": 0.04}, "pollution": 4.0,
		"desc": "Installé à l’écart, refroidi par la glace. Dangereux pour la population."},
	"fusion": {"name": "Centrale à fusion He-3/D", "cost": {"fer": 200, "terres": 40, "precieux": 20}, "time": 20.0, "energy": 40.0,
		"consumes": {"he3": 0.08, "glace": 0.1}, "pollution": 0.5, "requires": "fusion",
		"desc": "Autonomie énergétique grâce à l’Hélium-3 et au deutérium. Alimente le bouclier."},
	"catapulte": {"name": "Catapulte électromagnétique", "cost": {"fer": 180, "terres": 30}, "time": 16.0, "energy": -6.0,
		"consumes": {"precieux": 0.15, "he3": 0.04}, "produces": {"credits": 6.0}, "pollution": 1.0, "requires": "catapulte",
		"desc": "Expédie lingots et bonbonnes d’Hélium-3 vers les cargos en orbite."},
	"silo": {"name": "Silos de stockage", "cost": {"regolithe": 60, "fer": 20}, "time": 6.0,
		"storage": {"regolithe": 600, "fer": 400, "glace": 300, "volatils": 200, "terres": 100, "precieux": 100, "uranium": 80},
		"desc": "Quatre silos reliés par convoyeur."},
	"reservoir": {"name": "Réservoirs", "cost": {"regolithe": 50, "fer": 40}, "time": 8.0,
		"storage": {"he3": 150, "gaz": 150, "volatils": 100, "credits": 500},
		"desc": "Sphères sous pression pour l’Hélium-3 et les gaz."},
	"spatioport": {"name": "Spatioport", "cost": {"regolithe": 120, "fer": 60}, "time": 12.0, "energy": -2.0,
		"consumes": {"fer": 0.4}, "produces": {"credits": 1.6}, "unique": true,
		"desc": "Commerce avec les cargos de passage ; base des transports de la colonie."},
	"radar": {"name": "Station radar", "cost": {"regolithe": 60, "fer": 30}, "time": 8.0, "energy": -1.0,
		"desc": "Étend la portée du radar tactique."},
	"tourelle": {"name": "Tourelle canon", "cost": {"fer": 40, "credits": 20}, "time": 10.0, "energy": -1.0, "role": "defense",
		"desc": "Canon double : obus à fusée de proximité contre les vaisseaux pirates qui bombardent le bouclier."},
	# science : le froid de la ceinture de Kuiper est un atout
	"calcul": {"name": "Centre de calcul cryogénique", "cost": {"fer": 120, "terres": 20, "precieux": 10}, "time": 14.0, "energy": -2.0,
		"requires": "calcul", "research": 0.5,
		"desc": "Supercalculateurs refroidis gratuitement à 50 K par le vide : recherche +50 %."},
	"observatoire": {"name": "Observatoire profond", "cost": {"regolithe": 80, "fer": 60}, "time": 10.0, "energy": -1.0, "research": 0.25,
		"desc": "Loin de la lumière du Soleil, une fenêtre parfaite sur l’univers : recherche +25 %."},
	"archives": {"name": "Forage des archives", "cost": {"regolithe": 100, "fer": 40}, "time": 10.0, "energy": -2.0, "research": 0.15,
		"desc": "Carottes de glace intactes depuis 4,5 milliards d’années : recherche +15 % et découvertes ponctuelles."},
	# tremplin interstellaire
	"chantier_arche": {"name": "Chantier interstellaire", "cost": {"fer": 400, "terres": 60, "precieux": 40}, "time": 30.0, "energy": -6.0,
		"requires": "fusion_prop", "unique": true,
		"desc": "Chantier naval en microgravité : y assembler le vaisseau-arche vers Alpha du Centaure (seconde victoire)."},
}

const TECH := {
	"moisson": {"name": "Fours à 800 °C", "desc": "Moissonneuses : +50 % de production", "cost": {"regolithe": 150, "fer": 60}, "time": 25.0,
		"mult": {"moissonneuse": 1.5}},
	"metallurgie": {"name": "Métallurgie", "desc": "Raffinerie : +50 % de production", "cost": {"regolithe": 150, "fer": 30}, "time": 25.0,
		"mult": {"raffinerie": 1.5}},
	"forage": {"name": "Forage thermique profond", "desc": "Foreuses : +50 % de production", "cost": {"fer": 120, "credits": 60}, "time": 30.0,
		"mult": {"foreuse": 1.5}},
	"filtres": {"name": "Filtres anti-pollution", "desc": "Pollution des usines : −40 %", "cost": {"fer": 100, "gaz": 30, "credits": 50}, "time": 30.0},
	"fusion": {"name": "Fusion He-3/D", "desc": "Débloque la centrale à fusion", "requires": "forage", "cost": {"fer": 200, "he3": 20, "credits": 120}, "time": 45.0},
	"catapulte": {"name": "Catapulte électromagnétique", "desc": "Débloque l’exportation par mass driver", "cost": {"fer": 150, "terres": 20, "credits": 80}, "time": 35.0},
	"boucliers": {"name": "Bouclier renforcé", "desc": "Recharge du bouclier : +50 %", "requires": "metallurgie", "cost": {"fer": 160, "precieux": 20, "credits": 100}, "time": 40.0},
	"balistique": {"name": "Balistique", "desc": "Débloque le chasseur", "cost": {"fer": 60, "credits": 30}, "time": 30.0},
	"propulsion": {"name": "Propulsion ionique", "desc": "Débloque la corvette", "requires": "balistique", "cost": {"fer": 100, "credits": 60}, "time": 40.0},
	"espion": {"name": "Satellites espions", "desc": "Observation de Kronos depuis le spatioport", "requires": "balistique", "cost": {"fer": 80, "credits": 40}, "time": 25.0},
	"propulseurs": {"name": "Propulseurs d’astéroïde", "desc": "Débloque l’astéroïde-bélier (onglet Opérations)", "requires": "propulsion", "cost": {"fer": 200, "he3": 60, "credits": 120}, "time": 50.0},
	# survie à 40 UA du Soleil
	"recyclage": {"name": "Recyclage à 99,9 %", "desc": "Eau, air et volatils recyclés : besoins vitaux −90 %", "cost": {"fer": 80, "gaz": 20, "credits": 60}, "time": 30.0},
	"blindage_eau": {"name": "Blindage à l’eau", "desc": "Réservoirs d’eau autour des habitats : radiations −60 % (consomme de la glace)", "cost": {"fer": 100, "glace": 100}, "time": 30.0},
	"bouclier_mag": {"name": "Bouclier magnétique", "desc": "Champ magnétique artificiel : radiations −70 %", "requires": "boucliers", "cost": {"fer": 180, "terres": 30, "credits": 120}, "time": 45.0},
	"anneau": {"name": "Anneau centrifuge", "desc": "Gravité artificielle par rotation : fin de la perte osseuse", "cost": {"fer": 200, "credits": 100}, "time": 40.0},
	"fondations": {"name": "Fondations cryogéniques", "desc": "Aérogels et alliages cryogéniques : plus d’affaissements sous les bâtiments chauds", "cost": {"fer": 120, "terres": 15}, "time": 30.0},
	"harpons": {"name": "Ancrage par harpons", "desc": "Engins ancrés dans les gravats : séismes −80 %", "cost": {"fer": 90, "credits": 50}, "time": 25.0},
	"calcul": {"name": "Calcul cryogénique", "desc": "Débloque le centre de calcul cryogénique", "cost": {"fer": 100, "terres": 15, "credits": 80}, "time": 35.0},
	"fusion_prop": {"name": "Propulsion à fusion", "desc": "Débloque le chantier interstellaire et le vaisseau-arche", "requires": "fusion", "cost": {"fer": 250, "he3": 80, "credits": 200}, "time": 60.0},
}

const COLONY := {"startPop": 120.0, "housing": 400.0, "growth": 0.01, "taxIncome": 0.02, "baseMorale": 70.0, "taxMorale": 1.5,
	"deficitMorale": 20.0, "pollutionMorale": 0.9}

# emplacements libres de surface pour construire (coordonnées avant la réduction BSC)
const SLOTS := [Vector2(-150, -10), Vector2(-205, 40), Vector2(190, -25), Vector2(195, -100), Vector2(-115, -150), Vector2(115, -150), Vector2(-45, 105), Vector2(80, 110)]

# ---------------------------------------------------------------- état
var stock := {}
var rates := {}
var energy := {"p": 0.0, "c": 0.0}
var eff := 1.0
var inst: Array = []          # {t, done, p, s (état), slot}
var slot_used := {}
var tech_done := {}
var tech_cur := ""
var tech_p := 0.0
var pop := 120.0
var tax := 10.0
var morale := 65.0
var pollution := 0.0
var log: Array = []           # messages de la console
const SHIELD_DRAW := 10.0     # le générateur du bouclier consomme de l'énergie


func setup(world) -> void:
	w = world
	for r in RES:
		stock[r] = float(RES[r].start)
		rates[r] = 0.0
	pop = COLONY.startPop
	# bâtiments déjà présents en surface au début de la partie
	for t in ["fusion", "raffinerie", "smr", "catapulte", "silo", "reservoir", "spatioport", "radar"]:
		inst.append({"t": t, "done": true, "p": 0.0, "s": "ok"})
	for k in 4:
		inst.append({"t": "foreuse", "done": true, "p": 0.0, "s": "ok"})
	for k in 5:
		inst.append({"t": "moissonneuse", "done": true, "p": 0.0, "s": "ok"})
	tech_done["catapulte"] = true
	tech_done["fusion"] = true
	say("Centre de commandement activé. Réacteur à hélium-3 en service, bouclier en charge.")


func say(t: String) -> void:
	var m := int(w.war.time / 60.0) if w.war != null else 0
	var s := int(w.war.time) % 60 if w.war != null else 0
	log.push_front("[%02d:%02d] %s" % [m, s, t])
	if log.size() > 40:
		log.pop_back()


func caps() -> Dictionary:
	var c := {}
	for r in RES:
		c[r] = float(RES[r].cap)
	for x in inst:
		if x.done and BLD[x.t].has("storage"):
			for r in BLD[x.t].storage:
				c[r] += float(BLD[x.t].storage[r])
	return c


func count_done(t: String) -> int:
	var n := 0
	for x in inst:
		if x.t == t and x.done:
			n += 1
	return n


func count(t: String) -> int:
	var n := 0
	for x in inst:
		if x.t == t:
			n += 1
	return n


func mult(t: String) -> float:
	var m := 1.0
	for k in tech_done:
		if TECH.has(k) and TECH[k].has("mult") and TECH[k].mult.has(t):
			m *= float(TECH[k].mult[t])
	return m


func affordable(cost: Dictionary) -> bool:
	for r in cost:
		if stock.get(r, 0.0) < float(cost[r]):
			return false
	return true


func cost_txt(cost: Dictionary) -> String:
	var a: Array = []
	for r in cost:
		a.append("%d %s" % [int(cost[r]), RES[r].name])
	return ", ".join(a)


func requires_ok(d: Dictionary) -> bool:
	return not d.has("requires") or tech_done.has(d.requires)


# ---------------------------------------------------------------- construction
func can_build(t: String) -> String:
	var B: Dictionary = BLD[t]
	if not requires_ok(B):
		return "Requiert : " + TECH[B.requires].name
	if B.get("unique", false) and count(t) > 0:
		return "Déjà construit"
	if not B.get("mobile", false) and free_slot() < 0:
		return "Aucun emplacement libre"
	if not affordable(B.cost):
		return "Il manque des ressources"
	return ""


func free_slot() -> int:
	for i in SLOTS.size():
		if not slot_used.has(i):
			return i
	return -1


func build(t: String) -> void:
	var why := can_build(t)
	if why != "":
		say(BLD[t].name + " : " + why + ".")
		return
	var B: Dictionary = BLD[t]
	for r in B.cost:
		stock[r] -= float(B.cost[r])
	var x := {"t": t, "done": false, "p": 0.0, "s": "cons", "slot": -1}
	if not B.get("mobile", false):
		x.slot = free_slot()
		slot_used[x.slot] = true
		x.scaf = w.scaffold(SLOTS[x.slot])
	inst.append(x)
	say(B.name + " : construction lancée.")


func finish(x: Dictionary) -> void:
	x.done = true
	x.s = "ok"
	if x.has("scaf") and is_instance_valid(x.scaf):
		x.scaf.queue_free()
		w.blinks = w.blinks.filter(func(b): return is_instance_valid(b) and not x.scaf.is_ancestor_of(b))
	x.nodes = w.construct(x.t, SLOTS[x.slot] if x.slot >= 0 else Vector2.ZERO)
	say(BLD[x.t].name + " : construction terminée.")


# ---------------------------------------------------------------- recherche
func research(k: String) -> void:
	var t: Dictionary = TECH[k]
	if tech_done.has(k):
		return
	if tech_cur != "":
		say("Une recherche est déjà en cours.")
		return
	if not requires_ok(t):
		say(t.name + " : requiert " + TECH[t.requires].name + ".")
		return
	if not affordable(t.cost):
		say(t.name + " : il manque " + cost_txt(t.cost) + ".")
		return
	for r in t.cost:
		stock[r] -= float(t.cost[r])
	tech_cur = k
	tech_p = 0.0
	say(t.name + " : recherche lancée.")


# ---------------------------------------------------------------- simulation (par seconde de jeu)
func step(dt: float) -> void:
	var cap := caps()
	# construction
	for x in inst:
		if not x.done:
			x.p += dt
			if x.p >= float(BLD[x.t].time):
				finish(x)
	# énergie
	var p := 0.0
	var c := SHIELD_DRAW
	for x in inst:
		if not x.done:
			continue
		var B: Dictionary = BLD[x.t]
		var e := float(B.get("energy", 0.0))
		# bâtiment arrêté (affaissement du sol) : ni production ni consommation d'énergie
		if x.get("halt", 0.0) > 0.0:
			continue
		if e > 0.0:
			var fu := 1.0
			for r in B.get("consumes", {}):
				var need := float(B.consumes[r]) * dt
				if need > 0.0 and stock[r] < need:
					fu = minf(fu, stock[r] / need)
			p += e * fu
		else:
			c -= e
	energy = {"p": p, "c": c}
	eff = minf(1.0, p / c) if c > 0.0 else 1.0
	# production et consommation
	for r in RES:
		rates[r] = 0.0
	pollution = 0.0
	var pol_k := 0.6 if tech_done.has("filtres") else 1.0
	for x in inst:
		if not x.done:
			continue
		var B: Dictionary = BLD[x.t]
		if x.get("halt", 0.0) > 0.0:
			x.halt -= dt
			x.s = "affaissement"
			continue
		pollution += float(B.get("pollution", 0.0)) * pol_k
		if not B.has("produces") and not B.has("consumes"):
			x.s = "energie" if (float(B.get("energy", 0.0)) < 0.0 and eff < 1.0) else "ok"
			continue
		var f := eff if float(B.get("energy", 0.0)) < 0.0 else 1.0
		# blocus : les exportations (crédits) sont coupées
		var blocked: bool = w.strategy != null and w.strategy.blk != null and B.get("produces", {}).has("credits")
		x.s = "energie" if f < 1.0 else "ok"
		if blocked:
			f = 0.0
			x.s = "blocus"
		for r in B.get("consumes", {}):
			var need := float(B.consumes[r]) * dt
			if need > 0.0 and stock[r] < need * f:
				f = stock[r] / need
				x.s = "intrants"
		var outs: Array = B.get("produces", {}).keys()
		if outs.size() > 0:
			var full := true
			for r in outs:
				if stock[r] < cap[r] - 1e-6:
					full = false
			if full:
				f = 0.0
				x.s = "plein"
		for r in B.get("consumes", {}):
			stock[r] -= float(B.consumes[r]) * dt * f
			rates[r] -= float(B.consumes[r]) * f
		var m := mult(x.t)
		for r in B.get("produces", {}):
			stock[r] = minf(cap[r], stock[r] + float(B.produces[r]) * m * dt * f)
			rates[r] += float(B.produces[r]) * m * f
	# recherche (au centre de commandement)
	if tech_cur != "":
		tech_p += dt * eff * research_mult()
		# forage des archives : découverte ponctuelle (environ une par minute et par forage)
		if randf() < dt * count_done("archives") / 60.0:
			tech_p += float(TECH[tech_cur].time) * 0.1
			say("Archives glaciaires : une découverte fait avancer « %s »." % TECH[tech_cur].name)
		if tech_p >= float(TECH[tech_cur].time):
			tech_done[tech_cur] = true
			say(TECH[tech_cur].name + " : recherche terminée.")
			tech_cur = ""
			tech_p = 0.0
	# population (sous terre), moral, impôts
	var target := COLONY.baseMorale - tax * COLONY.taxMorale - pollution * COLONY.pollutionMorale
	if energy.c > energy.p:
		target -= COLONY.deficitMorale
	if w.SHD_DOWN > 0.0:
		target -= 10.0
	# santé de la population (radiations, microgravité, besoins vitaux)
	var hp: float = w.survival.health if w.survival != null else 80.0
	if w.survival != null:
		target -= w.survival.morale_malus()
	target = clampf(target, 0.0, 100.0)
	morale += (target - morale) * minf(1.0, dt * 0.05)
	var housing := COLONY.housing
	if pop < housing and morale >= 30.0 and hp >= 45.0:
		pop = minf(housing, pop + pop * COLONY.growth * dt * morale / 100.0)
	if morale < 25.0:
		pop -= pop * 0.003 * dt
	if hp < 30.0:
		pop -= pop * 0.004 * dt
	pop = maxf(0.0, pop)
	var inc := pop * tax / 100.0 * COLONY.taxIncome
	stock.credits = minf(cap.credits, stock.credits + inc * dt)
	rates.credits += inc


# vitesse de recherche : bâtiments scientifiques (calcul cryogénique, observatoire, archives)
func research_mult() -> float:
	var m := 1.0
	for x in inst:
		if x.done and x.get("halt", 0.0) <= 0.0:
			m += float(BLD[x.t].get("research", 0.0))
	return m


# facteur de recharge du bouclier : énergie disponible et recherche
func shield_factor() -> float:
	return eff * (1.5 if tech_done.has("boucliers") else 1.0)
