## Kuiper Dawn — diplomatie, superviseurs et opérations spéciales (mécaniques inspirées des jeux de gestion
## d'astéroïdes des années 90 ; factions et univers originaux) :
## - 5 factions extraterrestres aux personnalités distinctes : relations, traités (commerce, paix, alliance, guerre),
##   cadeaux, marché, exigences et offres ; les factions en guerre lancent des raids, les alliées défendent K-240 ;
## - superviseurs : gérants des colonies (revenus accrus) et superviseur industriel de K-240 (gestion automatique) ;
## - sabotage de Kronos par des agents ; astéroïde-bélier précipité sur Kronos.
extends Node

var w  # main.gd
var C  # colony.gd
var S  # strategy.gd

# kind : marchand, savant, guerrier, isolationniste, opportuniste
const FAC := [
	{"id": "vashri", "name": "Marchands vashri", "kind": "marchand", "x": 28.0, "y": 64.0, "rel": 15.0, "color": Color("ffd76a"),
		"desc": "Commerçants nomades : bons prix, aiment les cadeaux et les accords commerciaux."},
	{"id": "ollen", "name": "Savants ollen", "kind": "savant", "x": 56.0, "y": 6.0, "rel": 10.0, "color": Color("7fd6ff"),
		"desc": "Érudits : vendent des connaissances qui accélèrent vos recherches, partagent leurs observations de Kronos."},
	{"id": "kethar", "name": "Clans kethar", "kind": "guerrier", "x": 97.0, "y": 14.0, "rel": -10.0, "color": Color("ff8a5a"),
		"desc": "Guerriers : exigent des tributs, respectent la force ; en guerre, ils lancent des raids."},
	{"id": "silence", "name": "Les Silencieux", "kind": "isolationniste", "x": 97.0, "y": 67.0, "rel": 0.0, "color": Color("b0a8ff"),
		"desc": "Isolationnistes : leurs relations reviennent toujours vers zéro ; une alliance est très difficile."},
	{"id": "myrr", "name": "Essaim myrr", "kind": "opportuniste", "x": 62.0, "y": 66.0, "rel": 0.0, "color": Color("9cff7a"),
		"desc": "Opportunistes : se rapprochent du plus fort ; si vous faiblissez, ils ravitaillent Kronos."},
]
const TREATY := {"commerce": {"name": "Accord commercial", "rel": 20.0}, "paix": {"name": "Pacte de non-agression", "rel": 35.0}, "alliance": {"name": "Alliance", "rel": 60.0}}
# marché : ressource, quantité d'un lot, prix d'achat de base (crédits), prix de vente de base
const MARKET := [["regolithe", 100, 40, 25], ["fer", 40, 70, 45], ["he3", 20, 90, 60], ["terres", 15, 110, 70], ["precieux", 10, 120, 80], ["uranium", 10, 80, 50]]
const SUP_COST := 120.0
const SUP_UPKEEP := 0.2
const IND_UPKEEP := 0.5
const SAB_COST := {"credits": 80, "precieux": 10}
const RAM_COST := {"fer": 300, "he3": 120, "credits": 200}

var fac := {}               # id -> état {rel, treaty, event, demand, offer, raid_t}
var sup := {}               # astéroïde colonisé -> {lvl, t}
var industrial := false     # superviseur industriel de K-240
var ind_t := 0.0
var ram = null              # astéroïde-bélier en route {from, p, dur}
var research_boost := 0.0   # durée restante du bonus de recherche (savants)
var log: Array = []


func setup(world, colony, strategy) -> void:
	w = world
	C = colony
	S = strategy
	for f in FAC:
		fac[f.id] = {"rel": f.rel, "treaty": "", "event": randf_range(60.0, 140.0), "demand": {}, "offer": {}, "raid_t": 200.0}


func F(id: String) -> Dictionary:
	for f in FAC:
		if f.id == id:
			return f
	return {}


func say(t: String) -> void:
	log.push_front(t)
	if log.size() > 8:
		log.pop_back()
	C.say(t)


func rel_txt(r: float) -> String:
	if r >= 60.0:
		return "amicale"
	if r >= 25.0:
		return "cordiale"
	if r > -25.0:
		return "neutre"
	if r > -60.0:
		return "tendue"
	return "hostile"


func treaty_txt(id: String) -> String:
	var t: String = fac[id].treaty
	if t == "":
		return "aucun traité"
	if t == "guerre":
		return "EN GUERRE"
	return TREATY[t].name


func my_power() -> float:
	var p: float = S.power(S.def_ships()) + S.power(S.hangar) + C.count_done("tourelle") * 1750.0
	return p


# ---------------------------------------------------------------- actions diplomatiques
func gift(id: String) -> void:
	if C.stock.credits < 50.0:
		say("Cadeau : il faut 50 crédits.")
		return
	C.stock.credits -= 50.0
	var k: String = F(id).kind
	var g: float = {"marchand": 10.0, "savant": 8.0, "guerrier": 6.0, "isolationniste": 3.0, "opportuniste": 7.0}[k]
	fac[id].rel = minf(100.0, fac[id].rel + g)
	say("%s : cadeau de 50 crédits reçu (relation +%d)." % [F(id).name, int(g)])


func propose(id: String, t: String) -> void:
	var st: Dictionary = fac[id]
	var need: float = TREATY[t].rel
	if F(id).kind == "isolationniste" and t == "alliance":
		need = 85.0
	# les guerriers ne s'allient qu'avec un voisin puissant
	if F(id).kind == "guerrier" and t == "alliance" and my_power() < 6000.0:
		say("%s : « Nous ne nous allions qu’aux forts. » (puissance militaire insuffisante)" % F(id).name)
		return
	if st.treaty == "guerre":
		say("%s : impossible, vous êtes en guerre. Proposez d’abord la paix." % F(id).name)
		return
	if st.rel < need:
		say("%s refuse : relation insuffisante (%d / %d requis)." % [F(id).name, int(st.rel), int(need)])
		return
	st.treaty = t
	say("%s : %s signé !" % [F(id).name, TREATY[t].name])


func make_peace(id: String) -> void:
	var st: Dictionary = fac[id]
	if st.treaty != "guerre":
		return
	var cost := 150.0
	if C.stock.credits < cost:
		say("Paix avec %s : il faut %d crédits de réparations." % [F(id).name, int(cost)])
		return
	C.stock.credits -= cost
	st.treaty = ""
	st.rel = maxf(st.rel, -20.0)
	say("%s accepte la paix contre %d crédits de réparations." % [F(id).name, int(cost)])


func declare_war(id: String) -> void:
	var st: Dictionary = fac[id]
	st.treaty = "guerre"
	st.rel = minf(st.rel - 40.0, -60.0)
	st.raid_t = randf_range(90.0, 150.0)
	say("Vous déclarez la guerre à %s !" % F(id).name)


func price_mult(id: String) -> float:
	var m: float = {"marchand": 0.8, "savant": 1.0, "guerrier": 1.2, "isolationniste": 1.3, "opportuniste": 1.05}[F(id).kind]
	if fac[id].treaty in ["commerce", "alliance"]:
		m -= 0.1
	return m


func can_trade(id: String) -> bool:
	var st: Dictionary = fac[id]
	return st.treaty != "guerre" and (st.treaty != "" or F(id).kind == "marchand") and st.rel > -25.0


func buy(id: String, i: int) -> void:
	var m: Array = MARKET[i]
	var price := float(m[2]) * price_mult(id)
	if not can_trade(id) or C.stock.credits < price:
		say("Achat impossible (%d crédits nécessaires, ou pas d’accès au marché)." % int(price))
		return
	C.stock.credits -= price
	C.stock[m[0]] = minf(C.caps()[m[0]], C.stock[m[0]] + float(m[1]))
	fac[id].rel = minf(100.0, fac[id].rel + 1.0)
	say("Acheté à %s : %d %s pour %d crédits." % [F(id).name, m[1], C.RES[m[0]].name, int(price)])


func sell(id: String, i: int) -> void:
	var m: Array = MARKET[i]
	var gain := float(m[3]) / price_mult(id)
	if not can_trade(id) or C.stock[m[0]] < float(m[1]):
		say("Vente impossible (il faut %d %s, ou pas d’accès au marché)." % [m[1], C.RES[m[0]].name])
		return
	C.stock[m[0]] -= float(m[1])
	C.stock.credits = minf(C.caps().credits, C.stock.credits + gain)
	fac[id].rel = minf(100.0, fac[id].rel + 1.0)
	say("Vendu à %s : %d %s pour %d crédits." % [F(id).name, m[1], C.RES[m[0]].name, int(gain)])


func answer(id: String, yes: bool) -> void:
	var st: Dictionary = fac[id]
	if not st.demand.is_empty():
		var d: Dictionary = st.demand
		st.demand = {}
		if yes and C.stock.credits >= d.amount:
			C.stock.credits -= d.amount
			st.rel = minf(100.0, st.rel + 6.0)
			say("Tribut de %d crédits versé à %s." % [int(d.amount), F(id).name])
		else:
			refuse_demand(id)
		return
	if not st.offer.is_empty():
		var o: Dictionary = st.offer
		st.offer = {}
		if not yes:
			say("Offre de %s déclinée." % F(id).name)
			return
		if not C.affordable(o.cost):
			say("Offre de %s : il manque %s." % [F(id).name, C.cost_txt(o.cost)])
			return
		for r in o.cost:
			C.stock[r] -= float(o.cost[r])
		match o.type:
			"lot":
				C.stock[o.res] = minf(C.caps()[o.res], C.stock[o.res] + float(o.qty))
			"savoir":
				research_boost = 90.0
		st.rel = minf(100.0, st.rel + 4.0)
		say("Offre de %s acceptée : %s." % [F(id).name, o.txt])


func refuse_demand(id: String) -> void:
	var st: Dictionary = fac[id]
	st.rel -= 25.0
	say("%s : tribut refusé. Les clans sont furieux (relation −25)." % F(id).name)
	if st.rel <= -40.0 and st.treaty != "guerre":
		st.treaty = "guerre"
		st.raid_t = randf_range(60.0, 120.0)
		say("⚠ %s vous déclarent la guerre !" % F(id).name)


# ---------------------------------------------------------------- superviseurs
func hire(aid: String) -> void:
	if sup.has(aid) or not S.col.has(aid):
		return
	if C.stock.credits < SUP_COST:
		say("Superviseur : il faut %d crédits." % int(SUP_COST))
		return
	C.stock.credits -= SUP_COST
	sup[aid] = {"lvl": 1, "t": 0.0}
	say("Superviseur nommé sur %s : il développe la colonie (revenus ×1,5)." % S.A(aid).name)


func income_mult(aid: String) -> float:
	return 1.0 + 0.5 * sup[aid].lvl if sup.has(aid) else 1.0


func toggle_industrial() -> void:
	industrial = not industrial
	say("Superviseur industriel de K-240 " + ("nommé : il gère l’énergie, le stockage, les raffineries et les moissonneuses." if industrial else "renvoyé."))


func industrial_step() -> void:
	var under := false
	for x in C.inst:
		if not x.done:
			under = true
	if under:
		return
	if C.energy.c > C.energy.p - 3.0:
		for t in ["fusion", "smr"]:
			if C.can_build(t) == "":
				C.build(t)
				return
		return
	var cap: Dictionary = C.caps()
	if C.stock.fer < 150.0 and C.stock.regolithe > 250.0 and C.count("raffinerie") < 4 and C.energy.p - C.energy.c >= 3.0 and C.can_build("raffinerie") == "":
		C.build("raffinerie")
	elif C.stock.fer > cap.fer * 0.9 and C.count("silo") < 3 and C.can_build("silo") == "":
		C.build("silo")
	elif C.count("moissonneuse") < 8 and C.energy.p - C.energy.c > 4.0 and C.can_build("moissonneuse") == "":
		C.build("moissonneuse")


# ---------------------------------------------------------------- opérations spéciales
func sabotage() -> void:
	if S.E.dead:
		return
	if S.sat_on().is_empty():
		say("Sabotage : il faut un satellite espion en orbite de Kronos pour guider l’agent.")
		return
	if not C.affordable(SAB_COST):
		say("Sabotage : il manque " + C.cost_txt(SAB_COST) + ".")
		return
	for r in SAB_COST:
		C.stock[r] -= float(SAB_COST[r])
	var chance := clampf(0.8 - 0.08 * S.E.bld.defense, 0.25, 0.8)
	if randf() > chance:
		S.E.hold = maxf(0.0, S.E.hold - 60.0)
		say("Sabotage échoué : l’agent a été capturé. Kronos est sur ses gardes.")
		return
	match randi() % 4:
		0:
			S.E.bld.mine = maxi(1, S.E.bld.mine - 1)
			say("Sabotage réussi : une mine de Kronos a sauté.")
		1:
			var us: Array = S.E.fleet.keys().filter(func(u): return S.E.fleet[u] > 0)
			if us.size() > 0:
				var u: String = us.pick_random()
				S.E.fleet[u] -= 1
				say("Sabotage réussi : un vaisseau pirate (%s) détruit à quai." % S.UNITS[u].name)
			else:
				S.E.q.clear()
				say("Sabotage réussi : le chantier naval de Kronos est paralysé.")
		2:
			S.E.hold = maxf(S.E.hold, S.E.t + 150.0)
			say("Sabotage réussi : les ordinateurs de Kronos sont infectés, pas d’attaque avant 2 min 30.")
		_:
			var st := minf(S.E.res, 80.0)
			S.E.res -= st
			C.stock.credits = minf(C.caps().credits, C.stock.credits + st)
			say("Sabotage réussi : %d crédits détournés des coffres de Kronos." % int(st))


func launch_ram(aid: String) -> void:
	if ram != null or S.E.dead:
		return
	if not C.tech_done.has("propulseurs"):
		say("Astéroïde-bélier : recherchez d’abord « Propulseurs d’astéroïde ».")
		return
	if not S.col.has(aid):
		return
	if not C.affordable(RAM_COST):
		say("Astéroïde-bélier : il manque " + C.cost_txt(RAM_COST) + ".")
		return
	for r in RAM_COST:
		C.stock[r] -= float(RAM_COST[r])
	var a: Dictionary = S.A(aid)
	var k: Dictionary = S.A("kronos")
	var d := Vector2(k.x - a.x, k.y - a.y).length()
	ram = {"from": aid, "p": 0.0, "dur": d / 1.2 * 2.0}
	S.col.erase(aid)
	sup.erase(aid)
	say("☄ %s est équipé de propulseurs et fonce sur Kronos : impact dans %d s !" % [a.name, int(ram.dur)])


func ram_impact() -> void:
	var a: Dictionary = S.A(ram.from)
	ram = null
	var deflect := clampf(S.power(S.E.fleet) / 500.0, 0.0, 0.6)
	if randf() < deflect:
		say("☄ La flotte de Kronos a dévié %s : l’astéroïde se perd dans le vide." % a.name)
		return
	S.E.bld.defense = 0
	S.E.bld.mine = maxi(1, S.E.bld.mine / 2)
	for u in S.E.fleet:
		S.E.fleet[u] = S.E.fleet[u] / 2
	S.E.res = 0.0
	S.E.q.clear()
	S.E.hold = maxf(S.E.hold, S.E.t + 240.0)
	S.log_combat("☄ IMPACT ! %s a percuté Kronos : tourelles rasées, mines et flotte réduites de moitié, coffres vides." % a.name)


# ---------------------------------------------------------------- simulation
func step(dt: float) -> void:
	# relations et événements
	var kp: float = S.power(S.E.fleet) + S.E.bld.defense * 360.0
	for f in FAC:
		var st: Dictionary = fac[f.id]
		match f.kind:
			"isolationniste":
				st.rel = move_toward(st.rel, 0.0, dt * 0.05)
			"opportuniste":
				st.rel = clampf(st.rel + dt * (0.04 if my_power() > kp else -0.04), -100.0, 100.0)
				if st.rel < -30.0 and not S.E.dead:
					S.E.res += dt * 0.4
		if st.treaty in ["commerce", "alliance"]:
			st.rel = minf(100.0, st.rel + dt * 0.01)
			C.stock.credits = minf(C.caps().credits, C.stock.credits + 0.75 * dt)
			C.rates.credits += 0.75
		if st.treaty == "guerre":
			st.raid_t -= dt
			if st.raid_t <= 0.0 and S.emoves.size() < 2 and S.blk == null:
				st.raid_t = randf_range(180.0, 260.0)
				var n := 2 + randi() % 3
				S.E.mid += 1
				var a := {"x": f.x, "y": f.y}
				var dur: float = Vector2(a.x - S.A("home").x, a.y - S.A("home").y).length() / 6.0 * 2.0
				S.emoves.append({"id": S.E.mid, "ships": {"chasseur": n}, "p": 0.0, "dur": dur, "fac": f.id})
				say("⚠ Raid des %s : %d chasseurs en route vers K-240 (arrivée dans %d s) !" % [f.name, n, int(dur)])
		st.event -= dt
		if st.event <= 0.0:
			st.event = randf_range(90.0, 170.0)
			fac_event(f)
		if not st.demand.is_empty():
			st.demand.t -= dt
			if st.demand.t <= 0.0:
				st.demand = {}
				refuse_demand(f.id)
		if not st.offer.is_empty():
			st.offer.t -= dt
			if st.offer.t <= 0.0:
				st.offer = {}
	# superviseurs des colonies : ils montent en niveau et coûtent un salaire
	for aid in sup:
		var s: Dictionary = sup[aid]
		s.t += dt
		if s.lvl < 3 and s.t >= 120.0 * s.lvl:
			s.lvl += 1
			say("Superviseur de %s : colonie développée (revenus ×%s)." % [S.A(aid).name, str(1.0 + 0.5 * s.lvl)])
		C.stock.credits = maxf(0.0, C.stock.credits - SUP_UPKEEP * dt)
		C.rates.credits -= SUP_UPKEEP
	if industrial:
		C.stock.credits = maxf(0.0, C.stock.credits - IND_UPKEEP * dt)
		C.rates.credits -= IND_UPKEEP
		ind_t -= dt
		if ind_t <= 0.0:
			ind_t = 4.0
			industrial_step()
	if research_boost > 0.0:
		research_boost -= dt
		if C.tech_cur != "":
			C.tech_p += dt * 0.5 * C.eff
	if ram != null:
		ram.p += dt
		if ram.p >= ram.dur:
			ram_impact()


func fac_event(f: Dictionary) -> void:
	var st: Dictionary = fac[f.id]
	if st.treaty == "guerre" or not st.demand.is_empty() or not st.offer.is_empty():
		return
	match f.kind:
		"guerrier":
			if st.treaty != "alliance" and st.treaty != "paix":
				var amt := float(80 + randi() % 4 * 40)
				st.demand = {"amount": amt, "t": 45.0}
				say("⚠ %s exigent un tribut de %d crédits (45 s pour répondre, onglet Diplomatie)." % [f.name, int(amt)])
		"marchand":
			var res: String = ["terres", "precieux", "he3", "uranium"].pick_random()
			var qty := 30 if res == "he3" else 15
			st.offer = {"type": "lot", "res": res, "qty": qty, "cost": {"credits": 90}, "t": 50.0, "txt": "%d %s pour 90 crédits" % [qty, C.RES[res].name]}
			say("%s proposent %d %s pour 90 crédits (onglet Diplomatie)." % [f.name, qty, C.RES[res].name])
		"savant":
			if st.rel >= 10.0:
				st.offer = {"type": "savoir", "cost": {"credits": 120}, "t": 50.0, "txt": "recherche accélérée de 50 % pendant 90 s"}
				say("%s proposent leurs connaissances : recherche +50 %% pendant 90 s pour 120 crédits." % f.name)
		"opportuniste":
			if st.rel > 20.0:
				var g := 60.0
				C.stock.credits = minf(C.caps().credits, C.stock.credits + g)
				say("%s, impressionnés par votre puissance, vous offrent %d crédits." % [f.name, int(g)])


# alliés : renforts pendant un siège de Kronos (ajoutés à la défense de K-240)
func allied_ships() -> Dictionary:
	var o := {}
	for f in FAC:
		if fac[f.id].treaty == "alliance":
			var n: int = {"guerrier": 4, "marchand": 1, "savant": 1, "isolationniste": 2, "opportuniste": 2}[f.kind]
			o["chasseur"] = o.get("chasseur", 0) + n
	return o


# les savants alliés ou en accord partagent leurs observations de Kronos (comme un satellite espion)
func ollen_intel() -> bool:
	return fac.ollen.treaty in ["commerce", "alliance"] and fac.ollen.rel >= 30.0
