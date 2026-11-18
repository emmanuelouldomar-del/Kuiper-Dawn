## Kuiper Dawn — survie sur l'astéroïde (document de gameplay de l'utilisateur du 2026-11-17).
## - 4 phases : 1 survie immédiate (capsule endommagée, minage à la main), 2 stabilisation (sas, eau, oxygène,
##   solaire, batteries), 3 industrialisation (galeries, fonderie, imprimante, serres), 4 expansion (réacteurs,
##   spatioport… et l'arrivée des pirates de Kronos : la guerre ne commence qu'en phase 4) ;
## - flux en circuit fermé : oxygène, CO2, eau, nourriture, chaleur (jour et nuit rapides), énergie (colony.gd) ;
## - menaces : pluies de micrométéorites (dégâts, brèches), éruptions solaires (survival.gd : surtensions, radiations,
##   mode bunker), séismes dans les galeries ;
## - mécanique signature : le centre de gravité se déplace avec le minage et les stocks, l'astéroïde devient instable ;
##   les propulseurs d'attitude corrigent, sinon il dérive hors de sa zone habitable (défaite).
extends Node

var w  # main.gd
var C  # colony.gd

var phase := 1
var capsule_ok := false
var capsule_p := -1.0          # réparation en cours (s), -1 si pas commencée
const CAPSULE_COST := {"regolithe": 60, "fer": 30}
const CAPSULE_TIME := 20.0
var mining := true             # équipe de minage manuel (combinaisons, à la main)
var bunker := false            # mode bunker : surface arrêtée, population abritée
var repairing := false         # l'équipage répare à la main les dégâts
var repair_t := 0.0
var drone_t := 0.0
var co2 := 0.4                 # CO2 dans l'air de la base (%)
var temp := 18.0               # température de la base (°C)
var day_t := 12.0
const DAY := 240.0             # rotation de l'astéroïde : un jour et une nuit en 4 min de jeu
var daylight := 1.0            # 0 la nuit, 1 en plein jour
var sun_el := 40.0             # hauteur du soleil au-dessus de la base (degrés)
var meteor_t := 420.0          # prochaine pluie de micrométéorites
var meteor := 0.0              # durée restante de la pluie en cours
var meteor_warned := false
var hit_acc := 0.0
var quake_t := 150.0
var instab := 0.0              # instabilité de la rotation (0–100)
var drift := 0.0               # dérive hors de la zone habitable (100 : défaite)
var short_o2 := false
var short_water := false
var short_food := false
var log: Array = []
var war_on := false


func setup(world, colony, start_phase := 1) -> void:
	w = world
	C = colony
	phase = start_phase
	capsule_ok = start_phase > 1
	mining = start_phase <= 2
	if start_phase >= 4:
		war_on = true


func say(t: String) -> void:
	log.push_front(t)
	if log.size() > 8:
		log.pop_back()
	C.say(t)


func at_war() -> bool:
	return war_on


# ---------------------------------------------------------------- objectifs des phases
func objectives() -> Array:
	match phase:
		1:
			return [["Réparer la capsule d’atterrissage (%s)" % C.cost_txt(CAPSULE_COST), capsule_ok]]
		2:
			return [["Module pressurisé et sas", C.count_done("sas") >= 1], ["Station de traitement d’eau", C.count_done("station_eau") >= 1],
				["Électrolyseur d’eau", C.count_done("electrolyseur") >= 1], ["Épurateur de CO2", C.count_done("epurateur") >= 1],
				["2 panneaux solaires", C.count_done("solaire") >= 2], ["Batteries", C.count_done("batterie") >= 1]]
		3:
			return [["Foreuse de profondeur (galeries)", C.count_done("foreuse_prof") >= 1], ["Fonderie et raffinerie", C.count_done("raffinerie") >= 1],
				["Imprimante 3D industrielle", C.count_done("imprimante") >= 1], ["Serre hydroponique", C.count_done("serre") >= 1],
				["Radiateurs thermiques", C.count_done("radiateur") >= 1], ["Centre de commandement", C.count_done("commande") >= 1],
				["30 habitants", C.pop >= 30.0]]
	return []


const PHASE_NAME := {1: "Survie immédiate", 2: "Stabilisation", 3: "Industrialisation", 4: "Expansion"}


func check_phase() -> void:
	if phase >= 4:
		return
	for o in objectives():
		if not o[1]:
			return
	phase += 1
	match phase:
		2:
			say("PHASE 2 — Stabilisation : la capsule est réparée. Construisez un sas, automatisez l’eau et l’oxygène, installez panneaux et batteries.")
		3:
			say("PHASE 3 — Industrialisation : creusez l’astéroïde pour vous abriter, raffinez les métaux, cultivez sous serre.")
		4:
			say("PHASE 4 — Expansion : réacteurs, spatioport, commerce… La colonie est désormais visible : les pirates de Kronos l’ont repérée !")
			start_war()


func start_war() -> void:
	war_on = true
	w.on_war()


# ---------------------------------------------------------------- actions du joueur
func can_repair_capsule() -> String:
	if capsule_ok:
		return "Capsule réparée."
	if capsule_p >= 0.0:
		return "Réparation en cours."
	if not C.affordable(CAPSULE_COST):
		return "Il manque " + C.cost_txt(CAPSULE_COST) + "."
	return ""


func repair_capsule() -> void:
	var why := can_repair_capsule()
	if why != "":
		say("Capsule : " + why)
		return
	for r in CAPSULE_COST:
		C.stock[r] -= float(CAPSULE_COST[r])
	capsule_p = 0.0
	say("L’équipage répare la capsule (%d s)." % int(CAPSULE_TIME))


func toggle_mining() -> void:
	mining = not mining
	say("Minage à la main " + ("repris." if mining else "arrêté : l’équipage reste à l’abri."))


func toggle_bunker() -> void:
	bunker = not bunker
	say("MODE BUNKER " + ("activé : la surface est arrêtée, tout le monde s’abrite." if bunker else "levé : reprise des activités de surface."))


func toggle_repair() -> void:
	repairing = not repairing
	say("Réparations à la main " + ("lancées (%s par bâtiment)." % C.cost_txt(REPAIR_COST) if repairing else "suspendues."))


const REPAIR_COST := {"fer": 2, "regolithe": 8}


func damaged() -> Array:
	var a: Array = []
	for x in C.inst:
		if x.done and x.get("dmg", false):
			a.append(x)
	return a


func breaches() -> int:
	var n := 0
	for x in damaged():
		if C.BLD[x.t].get("pressure", false):
			n += 1
	return n


func fix(x: Dictionary) -> void:
	x.dmg = false
	x.s = "ok"
	w.damage_fx(x, false)


# ---------------------------------------------------------------- effets sur la colonie
func heat_eff() -> float:
	return 0.7 if temp > 45.0 else 1.0


func vital_ok() -> bool:
	return not short_o2 and not short_water and not short_food and co2 < 2.0 and temp > 0.0 and temp < 38.0


func morale_malus() -> float:
	var m := 0.0
	if co2 > 2.0:
		m += 10.0
	if temp < 10.0 or temp > 30.0:
		m += 8.0
	if breaches() > 0:
		m += 5.0
	return m


func shelter() -> float:
	# part de la population à l'abri des radiations : galeries creusées, mode bunker
	var s := 0.0
	if C.count_ok("foreuse_prof") > 0:
		s += 0.5
	if bunker:
		s += 0.3
	return minf(0.85, s)


# ---------------------------------------------------------------- simulation
func step(dt: float) -> void:
	if w.strategy != null and (w.strategy.lost or w.strategy.won):
		return
	step_day(dt)
	step_capsule(dt)
	step_flows(dt)
	step_heat(dt)
	step_threats(dt)
	step_repairs(dt)
	step_stability(dt)
	check_phase()
	# tout l'équipage est mort
	if C.pop < 1.0 and w.strategy != null and not w.strategy.lost:
		w.strategy.lost = true
		w.strategy.lose_txt = "Plus personne ne répond sur K-240. Le dernier journal de bord parle d’oxygène, de froid et d’un ciel plein d’étoiles."
		say("La colonie a péri.")


func step_day(dt: float) -> void:
	day_t = fmod(day_t + dt, DAY)
	var ph := TAU * day_t / DAY
	sun_el = 50.0 * sin(ph) + 35.0
	daylight = clampf(sun_el / 20.0, 0.0, 1.0)


func step_capsule(dt: float) -> void:
	if capsule_p >= 0.0 and not capsule_ok:
		capsule_p += dt
		if capsule_p >= CAPSULE_TIME:
			capsule_ok = true
			say("Capsule réparée : son ordinateur et ses panneaux remarchent.")


func step_flows(dt: float) -> void:
	var T: Dictionary = C.tech_done
	var crew: float = minf(C.pop, 8.0)
	var eva := mining and not bunker and not repairing
	# minage à la main : lent, coûteux en oxygène de combinaison, exposé aux radiations
	if eva:
		var k: float = crew / 8.0
		var cap: Dictionary = C.caps()
		var hand := {"regolithe": 0.7, "fer": 0.32, "glace": 0.3}
		for r in hand:
			var v: float = float(hand[r]) * k
			C.stock[r] = minf(cap[r], C.stock[r] + v * dt)
			C.rates[r] += v
	# besoins vitaux (recycleurs, recyclage)
	var rec := 1.0 - 0.3 * minf(2.0, float(C.count_ok("recycleur")))
	if T.has("recyclage"):
		rec *= 0.4
	var o2: float = C.pop * 0.0025 * rec + (crew * 0.004 if eva else 0.0)
	var water: float = C.pop * 0.002 * rec
	var food: float = C.pop * 0.0012
	# fuites : la capsule et les modules perdent un peu d'air, chaque brèche beaucoup
	var leak := (0.03 if C.count_done("sas") == 0 else 0.01) + float(breaches()) * 0.3
	o2 += leak
	short_o2 = C.stock.oxygene < o2 * dt
	short_water = C.stock.eau < water * dt
	short_food = C.stock.nourriture < food * dt
	C.stock.oxygene = maxf(0.0, C.stock.oxygene - o2 * dt)
	C.stock.eau = maxf(0.0, C.stock.eau - water * dt)
	C.stock.nourriture = maxf(0.0, C.stock.nourriture - food * dt)
	C.rates.oxygene -= o2
	C.rates.eau -= water
	C.rates.nourriture -= food
	# CO2 : produit par la population, filtré par la capsule, les épurateurs (cartouches) et les serres
	var scrub := 0.015 if capsule_ok else 0.008
	var cart := T.has("cartouches")
	for x in C.inst:
		if x.done and C.stopped(x) == "" and C.BLD[x.t].has("scrub"):
			var s: float = float(C.BLD[x.t].scrub) * C.eff
			if x.t == "epurateur" and not cart:
				var need := 0.0015 * dt
				if C.stock.pieces >= need:
					C.stock.pieces -= need
					C.rates.pieces -= 0.0015
				else:
					s *= 0.5
			scrub += s
	co2 = clampf(co2 + (C.pop * 0.0015 - scrub) * dt, 0.04, 10.0)
	# santé (s'ajoute à celle des radiations et de la microgravité, survival.gd)
	var dh := 0.0
	if short_o2:
		dh -= 1.5
		C.pop -= C.pop * 0.01 * dt
	if co2 > 4.0:
		dh -= 0.5
	elif co2 > 2.0:
		dh -= 0.1
	if short_water:
		dh -= 0.3
	if short_food:
		dh -= 0.2
	if temp < -10.0 or temp > 50.0:
		dh -= 0.4
	elif temp < 0.0 or temp > 38.0:
		dh -= 0.12
	for x in C.inst:
		if x.done and C.stopped(x) == "" and C.BLD[x.t].has("heal"):
			dh += float(C.BLD[x.t].heal)
	if w.survival != null:
		w.survival.health = clampf(w.survival.health + dh * dt, 0.0, 100.0)


func step_heat(dt: float) -> void:
	# chaleur : machines (énergie consommée), réacteurs et fours, population, soleil ; le vide n'évacue la chaleur
	# que par rayonnement (radiateurs) ; la nuit, le froid gagne et les régulateurs chauffent
	var q_in: float = C.pop * 0.03 + daylight * 4.0
	var q_out := 5.0
	var heating := 12.0 if capsule_ok else 6.0
	for x in C.inst:
		if not x.done or C.stopped(x) != "":
			continue
		var B: Dictionary = C.BLD[x.t]
		q_in += maxf(0.0, -float(B.get("energy", 0.0))) * 0.2 + float(B.get("heat", 0.0))
		q_out += float(B.get("cool", 0.0))
		heating += float(B.get("heater", 0.0)) * minf(1.0, C.eff)
	q_in += C.h2_out * 0.2
	var target: float = 20.0 + (q_in - q_out) * 1.2 - (1.0 - daylight) * 22.0
	if target < 20.0:
		target = minf(20.0, target + heating)
	temp += (target - temp) * minf(1.0, dt * 0.04)


func step_threats(dt: float) -> void:
	if phase < 2:
		return
	# pluie de micrométéorites
	var warn := 45.0 if C.count_ok("radar") > 0 else 10.0
	if meteor > 0.0:
		meteor -= dt
		var lasers := 0.0
		for x in C.inst:
			if x.t == "laser" and x.done and C.stopped(x) == "":
				lasers += 0.35 * minf(1.0, C.eff)
		var cover := minf(0.85, lasers)
		hit_acc += dt * 0.15
		while hit_acc >= 1.0:
			hit_acc -= 1.0
			if randf() < cover:
				w.meteor_fx(null, true)
			else:
				meteor_hit()
		if meteor <= 0.0:
			say("Fin de la pluie de micrométéorites.")
	else:
		meteor_t -= dt
		if meteor_t <= warn and not meteor_warned:
			meteor_warned = true
			say("⚠ Radar : pluie de micrométéorites dans %d s !" % int(meteor_t))
		if meteor_t <= 0.0:
			meteor = 20.0
			meteor_t = randf_range(220.0, 340.0)
			meteor_warned = false
			say("⚠ PLUIE DE MICROMÉTÉORITES : les structures de surface sont touchées.")
	# éruption solaire (survival.storm) : surtensions sur le réseau si la base n'est pas en mode bunker
	if w.survival != null and w.survival.storm > 0.0 and not bunker:
		for x in C.inst:
			if x.done and not x.get("dmg", false) and (x.t == "solaire" or x.t == "batterie") and randf() < dt * 0.012:
				x.dmg = true
				w.damage_fx(x, true)
				say("⚠ Surtension : « %s » a grillé (éruption solaire)." % C.BLD[x.t].name)
	# séismes dans les galeries creusées
	if C.count_done("foreuse_prof") > 0:
		quake_t -= dt
		if quake_t <= 0.0:
			quake_t = 150.0
			var p := (0.2 + instab / 200.0) * (0.2 if C.tech_done.has("harpons") else 1.0)
			if randf() < p:
				C.stock.eau = maxf(0.0, C.stock.eau - 15.0)
				C.stock.oxygene = maxf(0.0, C.stock.oxygene - 10.0)
				for x in C.inst:
					if x.t == "foreuse_prof" and x.done:
						x.halt = 30.0
				w.quake_fx()
				say("⚠ Séisme : des parois des galeries se fissurent, des conduites sont coupées (−15 eau, −10 oxygène).")


func meteor_hit() -> void:
	var cand: Array = []
	for x in C.inst:
		if x.done and not x.get("dmg", false) and not C.BLD[x.t].get("deep", false):
			cand.append(x)
			if x.t == "solaire":
				cand.append(x)
	if cand.is_empty():
		w.meteor_fx(null, false)
		return
	var x: Dictionary = cand.pick_random()
	x.dmg = true
	w.meteor_fx(x, false)
	w.damage_fx(x, true)
	if C.BLD[x.t].get("pressure", false):
		say("⚠ Impact : brèche dans « %s », l’oxygène fuit !" % C.BLD[x.t].name)
	else:
		say("Impact : « %s » est endommagé." % C.BLD[x.t].name)


func step_repairs(dt: float) -> void:
	var d := damaged()
	if d.is_empty():
		repairing = false
		return
	# drones : une réparation toutes les 12 s par hub (2 composants)
	var hubs: int = C.count_ok("drones")
	if hubs > 0:
		drone_t += dt * hubs
		if drone_t >= 12.0 and C.stock.pieces >= 2.0:
			drone_t = 0.0
			C.stock.pieces -= 2.0
			var x: Dictionary = d[0]
			for y in d:
				if C.BLD[y.t].get("pressure", false):
					x = y
					break
			fix(x)
			say("Les drones ont réparé « %s »." % C.BLD[x.t].name)
	# réparations à la main par l'équipage (une toutes les 6 s)
	if repairing and not bunker:
		repair_t += dt
		if repair_t >= 6.0:
			repair_t = 0.0
			if C.affordable(REPAIR_COST):
				for r in REPAIR_COST:
					C.stock[r] -= float(REPAIR_COST[r])
				var x: Dictionary = d[0]
				for y in d:
					if C.BLD[y.t].get("pressure", false):
						x = y
						break
				fix(x)
				say("L’équipage a réparé « %s »." % C.BLD[x.t].name)
			else:
				repairing = false
				say("Réparations suspendues : il manque " + C.cost_txt(REPAIR_COST) + ".")


func step_stability(dt: float) -> void:
	# le minage et les stocks lourds déplacent le centre de gravité ; les propulseurs le compensent
	var mass := 0.0
	for r in ["regolithe", "fer", "beton", "titane", "glace"]:
		mass += float(C.stock[r])
	var gain := 0.003 * float(C.count_done("moissonneuse") + C.count_done("foreuse")) + 0.012 * float(C.count_done("foreuse_prof")) + mass / 50000.0
	var corr := 0.0
	var fuel_need := 0.0
	for x in C.inst:
		if x.t == "propulseurs" and x.done and C.stopped(x) == "":
			corr += float(C.BLD.propulseurs.thrust)
			fuel_need += 0.08
	if instab > 0.0 and corr > 0.0:
		var f := 1.0
		if C.stock.hydrogene < fuel_need * dt:
			f = C.stock.hydrogene / maxf(1e-6, fuel_need * dt)
		C.stock.hydrogene -= fuel_need * dt * f
		C.rates.hydrogene -= fuel_need * f
		corr *= f
	var old := instab
	instab = clampf(instab + (gain - corr) * dt, 0.0, 100.0)
	if old < 60.0 and instab >= 60.0:
		say("⚠ La rotation de l’astéroïde devient instable : construisez des propulseurs d’attitude (hydrogène).")
	if instab > 60.0:
		var od := drift
		drift = minf(100.0, drift + (instab - 60.0) * 0.0015 * dt)
		if od < 50.0 and drift >= 50.0:
			say("⚠ L’astéroïde dérive hors de sa zone habitable : %d %% !" % int(drift))
		if drift >= 100.0 and w.strategy != null and not w.strategy.lost:
			w.strategy.lost = true
			w.strategy.lose_txt = "Déséquilibré par le minage, l’astéroïde a quitté sa zone habitable. K-240 file vers le froid absolu, hors de portée de tout secours."
			say("L’astéroïde a quitté sa zone habitable.")
	else:
		drift = maxf(0.0, drift - 0.02 * dt)


func alert_txt() -> String:
	if short_o2:
		return "⚠ PLUS D’OXYGÈNE : la colonie suffoque"
	if meteor > 0.0:
		return "⚠ Pluie de micrométéorites (%d s)" % int(ceil(meteor))
	if breaches() > 0:
		return "⚠ %d brèche(s) : l’oxygène fuit" % breaches()
	if co2 > 2.0:
		return "⚠ CO2 à %.1f %% : construisez des épurateurs" % co2
	if temp < 0.0:
		return "⚠ Froid : %d °C dans la base" % int(temp)
	if temp > 38.0:
		return "⚠ Surchauffe : %d °C, ajoutez des radiateurs" % int(temp)
	if drift >= 30.0:
		return "⚠ Dérive orbitale : %d %%" % int(drift)
	return ""


# ---------------------------------------------------------------- pilote automatique (phases 1 à 3, et survie en phase 4)
func bot_try(t: String) -> String:
	if C.can_build(t) == "":
		C.build(t)
		return "Construit : " + C.BLD[t].name
	return ""


func building() -> bool:
	for x in C.inst:
		if not x.done:
			return true
	return false


func bot_step() -> String:
	# urgences
	var ws: Variant = w.survival
	if ws != null and ws.storm > 0.0 and not bunker and phase >= 2:
		toggle_bunker()
		return "Mode bunker pendant l’éruption solaire"
	if bunker and (ws == null or ws.storm <= 0.0):
		toggle_bunker()
		return "Lève le mode bunker"
	if damaged().size() > 0 and C.count_ok("drones") == 0 and not repairing and C.affordable(REPAIR_COST):
		toggle_repair()
		return "Répare les dégâts à la main"
	if phase == 1:
		if not mining:
			toggle_mining()
		if can_repair_capsule() == "":
			repair_capsule()
			return "Répare la capsule"
		return "Mine à la main pour réparer la capsule"
	if C.tax > 6.0 and phase < 4:
		C.tax = 4.0
	var busy := building()
	var r := ""
	# l'extraction d'abord : sans moissonneuses, ni régolithe ni fer
	if C.count("moissonneuse") < 2 + (phase - 2) * 2 and C.count("sas") > 0:
		r = bot_try("moissonneuse")
		if r != "":
			return r
		if C.stock.oxygene > 120.0 and co2 < 1.5:
			return "Économise pour une moissonneuse (régolithe et fer)"
	# vital : oxygène, CO2, eau, chaleur, énergie
	if C.stock.oxygene < 180.0 and C.rates.oxygene < 0.05 and C.count("electrolyseur") <= C.count_done("electrolyseur") and C.count("electrolyseur") < 2 + int(C.pop / 40.0):
		r = bot_try("electrolyseur")
		if r != "":
			return r
	if C.count("foreuse") < C.count("station_eau") + C.count("electrolyseur") and C.stock.glace < 100.0 and C.rates.glace < 0.3:
		r = bot_try("foreuse")
		if r != "":
			return r
	if C.stock.eau < 80.0 and C.count("station_eau") <= C.count_done("station_eau") and C.stock.glace > 20.0:
		r = bot_try("station_eau")
		if r != "":
			return r
	# cartouches filtrantes : imprimante 3D (puis cartouches régénérables) avant d'en manquer
	if phase >= 3 and C.stock.pieces < 12.0 and C.count("imprimante") == 0:
		r = bot_try("imprimante")
		if r != "":
			return r
		if C.affordable(C.BLD.imprimante.cost) == false and C.count("raffinerie") > 0:
			return "Économise pour l’imprimante 3D (cartouches filtrantes)"
	if co2 > 1.0 and C.count("epurateur") <= C.count_done("epurateur"):
		r = bot_try("epurateur")
		if r != "":
			return r
	if temp > 32.0 and C.count("radiateur") <= C.count_done("radiateur"):
		r = bot_try("radiateur")
		if r != "":
			return r
	if temp < 10.0 and C.count("regulateur") <= C.count_done("regulateur"):
		r = bot_try("regulateur")
		if r != "":
			return r
	# énergie : le jour, les panneaux doivent couvrir la consommation et recharger les batteries ;
	# les batteries doivent tenir la nuit (environ 100 s)
	if not busy:
		var cons: float = C.energy.c
		var day_prod: float = 3.0 + float(C.count("solaire")) * 5.0 * C.mult("solaire") + float(C.count("generateur_h2")) * 4.0
		if day_prod < cons * 1.4 + 3.0:
			r = bot_try("solaire")
		elif C.bat_cap() + 250.0 * float(C.count("batterie") - C.count_done("batterie")) < cons * 50.0 and C.count("batterie") < C.count("solaire"):
			r = bot_try("batterie")
		if r != "":
			return r
	if C.stock.nourriture < 80.0 and C.count("serre") <= C.count_done("serre"):
		r = bot_try("serre")
		if r != "":
			return r
	if C.pop >= C.housing() - 2.0 and not busy:
		r = bot_try("foreuse_prof") if C.count("foreuse_prof") == 0 and phase >= 3 else bot_try("sas")
		if r != "":
			return r
	if instab > 30.0 and C.count("propulseurs") < 1 + int(instab / 25.0):
		r = bot_try("propulseurs")
		if r != "":
			return r
	if phase >= 3 and C.count("laser") < 2 and C.count_done("radar") > 0:
		r = bot_try("laser")
		if r != "":
			return r
	# objectifs de la phase
	var order := {2: ["sas", "foreuse", "station_eau", "electrolyseur", "epurateur", "solaire", "solaire", "batterie", "regulateur", "moissonneuse"],
		3: ["raffinerie", "imprimante", "moissonneuse", "radiateur", "foreuse_prof", "serre", "commande", "drones", "radar", "silo", "reservoir", "generateur_h2", "infirmerie", "recycleur"]}
	if order.has(phase) and not busy:
		var need := {}
		for t in order[phase]:
			need[t] = need.get(t, 0) + 1
			if C.count(t) < need[t]:
				r = bot_try(t)
				if r != "":
					return r
				break
	# recherche
	if C.tech_cur == "" and capsule_ok:
		for k in ["cartouches", "electrolyse", "solaire_hr", "recyclage", "forage", "moisson", "metallurgie", "hydroponie", "fondations", "harpons", "blindage_eau", "anneau"]:
			if not C.tech_done.has(k) and C.requires_ok(C.TECH[k]) and C.affordable(C.TECH[k].cost):
				C.research(k)
				return "Lance la recherche : " + C.TECH[k].name
	# production
	if not busy and C.stock.regolithe < 60.0 and C.count("moissonneuse") < 6 + phase:
		r = bot_try("moissonneuse")
		if r != "":
			return r
	if not busy and C.count("moissonneuse") < 3 + phase:
		r = bot_try("moissonneuse")
		if r != "":
			return r
	if not busy and C.stock.pieces < 15.0 and C.count("imprimante") < 2:
		r = bot_try("imprimante")
		if r != "":
			return r
	if phase < 4:
		return "Attend des ressources (phase %d)…" % phase
	return ""
