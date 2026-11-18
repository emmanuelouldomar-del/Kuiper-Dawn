## Kuiper Dawn — couche stratégique (portée du remake « K-240 Remake » v50) :
## usine spatiale et hangar, flottes et leurs ordres, carte stratégique et colonisation d'astéroïdes,
## IA de la colonie pirate de Kronos (économie, recherche, chantier naval, raids), siège du bouclier,
## blocus et invasion, satellites espions, victoire et défaite, pilote automatique.
extends Node

var w  # main.gd
var C  # colony.gd

# ---------------------------------------------------------------- données
const UNITS := {
	"eclaireur": {"name": "Éclaireur", "cost": {"fer": 20}, "time": 8.0, "speed": 8.0, "armor": 2.0, "attack": 1.0},
	"chasseur": {"name": "Chasseur", "requires": "balistique", "cost": {"fer": 35, "credits": 10}, "time": 14.0, "speed": 6.0, "armor": 8.0, "attack": 5.0},
	"corvette": {"name": "Corvette", "requires": "propulsion", "cost": {"fer": 90, "credits": 40}, "time": 30.0, "speed": 5.0, "armor": 25.0, "attack": 12.0},
}
# carte du système (0–100 × 0–70)
const MAP := [
	{"id": "home", "name": "K-240", "x": 14.0, "y": 36.0, "owner": "player"},
	{"id": "alpha", "name": "Alpha", "x": 38.0, "y": 14.0, "owner": "neutral", "income": {"regolithe": 2.0}},
	{"id": "beta", "name": "Beta", "x": 42.0, "y": 56.0, "owner": "neutral", "income": {"fer": 0.6}},
	{"id": "gamma", "name": "Gamma", "x": 68.0, "y": 26.0, "owner": "neutral", "income": {"credits": 1.0}},
	{"id": "kronos", "name": "Kronos", "x": 87.0, "y": 50.0, "owner": "enemy"},
]
const EUNIT := {"eclaireur": {"c": 28.0, "t": 14.0, "s": 1.0}, "chasseur": {"c": 45.0, "t": 22.0, "s": 2.5, "r": "balistique"}, "corvette": {"c": 110.0, "t": 40.0, "s": 6.0, "r": "propulsion"}}
const ETECH := {"balistique": {"c": 80.0, "t": 50.0}, "propulsion": {"c": 140.0, "t": 70.0, "r": "balistique"}}
const EGRACE := 420.0        # pas d'attaque spatiale avant 7 min
const SIEGE := 45.0          # durée du bombardement du bouclier
const BLK_LAND := 12.0
const BLK_ENT := 40.0
const BLK_END := 68.0
const SATC := {"fer": 40, "credits": 30}
const SAT_LIFE := 240.0
const SAT_SP := 6.0
const RESO := ["moisson", "balistique", "metallurgie", "forage", "filtres", "propulsion", "espion", "fusion", "boucliers", "catapulte", "recyclage", "anneau", "blindage_eau", "fondations", "harpons", "calcul", "bouclier_mag", "fusion_prop"]

# ---------------------------------------------------------------- état
var hangar := {}             # vaisseaux inactifs
var queue: Array = []        # file de l'usine spatiale {u, p}
var fleets: Array = []       # {id, name, ships, ord ("idle"/"def"), loc ("home"/"away"), stay}
var fid := 0
var moves: Array = []        # déplacements de nos flottes {fid, to, kind, eid, ships, p, dur, back}
var col := {}                # astéroïdes colonisés
var E := {}                  # colonie pirate de Kronos
var emoves: Array = []       # flottes pirates en route {id, ships, p, dur, sg}
var blk = null               # blocus et invasion en cours
var sats: Array = []
var lost := false
var won := false
var lose_txt := ""         # cause de la défaite (survie : asphyxie, dérive…) ; vide = invasion pirate
var win_kind := "kronos"    # "kronos" (conquête) ou "arche" (vaisseau-arche vers Alpha du Centaure)
var combat_log: Array = []
var bot_on := false
var bot_t := 0.0
var bot_intent := ""
var siege_ships: Array = []  # vaisseaux pirates en 3D autour du bouclier pendant un siège


func setup(world, colony) -> void:
	w = world
	C = colony
	E = {"t": 0.0, "res": 120.0, "bld": {"mine": 1, "labo": 0, "usine": 0, "defense": 2}, "tech": {}, "cur": "", "cp": 0.0,
		"fleet": {}, "q": [], "think": 35.0, "atkN": 0, "hold": 0.0, "mid": 0, "dead": false, "log": []}


func A(id: String) -> Dictionary:
	for a in MAP:
		if a.id == id:
			return a
	return {}


func owner(a: Dictionary) -> String:
	if a.id == "home" or col.has(a.id):
		return "player"
	if a.id == "kronos" and E.dead:
		return "player"
	return a.owner


func dist(a: Dictionary) -> float:
	var h := A("home")
	return Vector2(a.x - h.x, a.y - h.y).length()


func ships_txt(o: Dictionary) -> String:
	var a: Array = []
	for u in o:
		if o[u] > 0:
			a.append("%d %s" % [o[u], UNITS[u].name if UNITS.has(u) else u])
	return ", ".join(a) if a.size() > 0 else "aucun"


func nships(o: Dictionary) -> int:
	var n := 0
	for u in o:
		n += int(o[u])
	return n


func slowest(o: Dictionary) -> float:
	var sp := 99.0
	for u in o:
		if o[u] > 0:
			sp = minf(sp, UNITS[u].speed)
	return sp if sp < 99.0 else 1.0


func log_combat(t: String) -> void:
	combat_log.push_front(t)
	if combat_log.size() > 8:
		combat_log.pop_back()
	C.say(t)


# ---------------------------------------------------------------- combat (comme le remake)
func mk(ships: Dictionary) -> Array:
	var L: Array = []
	for u in ships:
		for i in int(ships[u]):
			var d: Dictionary = UNITS.get(u, {"attack": 1.0, "armor": 1.0})
			L.append({"u": u, "atk": d.attack, "hp": d.armor * 4.0})
	return L


func hit(L: Array, d: float) -> void:
	while d > 0.0 and L.size() > 0:
		var x: Dictionary = L[0]
		if x.hp > d:
			x.hp -= d
			d = 0.0
		else:
			d -= x.hp
			L.pop_front()


func fight(A_: Array, B_: Array) -> void:
	for r in 40:
		if A_.is_empty() or B_.is_empty():
			return
		var da := 0.0
		for x in A_:
			da += x.atk
		var db := 0.0
		for x in B_:
			db += x.atk
		hit(B_, da * randf_range(0.8, 1.2))
		hit(A_, db * randf_range(0.8, 1.2))


func cnt_by(L: Array) -> Dictionary:
	var o := {}
	for x in L:
		if not String(x.u).begins_with("@"):
			o[x.u] = o.get(x.u, 0) + 1
	return o


func power(ships: Dictionary) -> float:
	var p := 0.0
	for u in ships:
		p += float(ships[u]) * UNITS[u].attack * UNITS[u].armor
	return p


# ---------------------------------------------------------------- usine spatiale (au spatioport)
func order(u: String) -> void:
	var d: Dictionary = UNITS[u]
	if d.has("requires") and not C.tech_done.has(d.requires):
		C.say(d.name + " : requiert " + C.TECH[d.requires].name + ".")
		return
	if C.count("spatioport") == 0:
		C.say("Il faut un spatioport pour construire des vaisseaux.")
		return
	if queue.size() >= 10:
		C.say("La file de l’usine spatiale est pleine (10 max).")
		return
	if not C.affordable(d.cost):
		C.say(d.name + " : il manque " + C.cost_txt(d.cost) + ".")
		return
	for r in d.cost:
		C.stock[r] -= float(d.cost[r])
	queue.append({"u": u, "p": 0.0})
	C.say(d.name + " ajouté à la file de l’usine spatiale.")


# ---------------------------------------------------------------- flottes
func fleet(id: int) -> Dictionary:
	for f in fleets:
		if f.id == id:
			return f
	return {}


func fleet_new() -> Dictionary:
	fid += 1
	var f := {"id": fid, "name": "Flotte %d" % fid, "ships": {}, "ord": "idle", "loc": "home", "stay": ""}
	fleets.append(f)
	C.say(f.name + " créée : incorporez-y des vaisseaux du hangar.")
	return f


func fleet_add(id: int, u: String) -> void:
	var f := fleet(id)
	if f.is_empty() or f.loc != "home":
		return
	var ks: Array = hangar.keys() if u == "*" else [u]
	for k in ks:
		var c: int = hangar.get(k, 0)
		if c <= 0:
			continue
		var take: int = c if u == "*" else 1
		hangar[k] = c - take
		f.ships[k] = f.ships.get(k, 0) + take


func fleet_rem(id: int) -> void:
	var f := fleet(id)
	if f.is_empty() or f.loc != "home":
		return
	for u in f.ships:
		hangar[u] = hangar.get(u, 0) + f.ships[u]
	f.ships = {}


func fleet_del(id: int) -> void:
	fleet_rem(id)
	fleets = fleets.filter(func(f): return f.id != id)


func def_ships() -> Dictionary:
	var o := {}
	for f in fleets:
		if f.ord == "def" and f.loc == "home":
			for u in f.ships:
				o[u] = o.get(u, 0) + f.ships[u]
	return o


func intercept_time(f: Dictionary, e: Dictionary) -> float:
	var kb := A("kronos")
	if e.has("sg"):
		return 3.0
	var sp := slowest(f.ships)
	var D0 := dist(kb)
	return maxf(3.0, D0 * (1.0 - e.p / e.dur) / (sp / 2.0 + D0 / e.dur))


# ordres : "def", "rtb", "int:<id>", "col:<astéroïde>", "atk:kronos"
func fleet_order(id: int, o: String) -> void:
	var f := fleet(id)
	if f.is_empty():
		return
	var parts := o.split(":")
	var op := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	if op == "rtb":
		for m in moves:
			if m.fid == f.id and not m.back:
				m.back = true
				m.kind = ""
				m.dur = maxf(2.0, m.p)
				m.p = 0.0
				C.say(f.name + " fait demi-tour.")
		return
	if f.loc != "home":
		C.say(f.name + " est en mission.")
		return
	if op == "def":
		f.ord = "idle" if f.ord == "def" else "def"
		C.say(f.name + (" patrouille autour de K-240 et défendra la colonie." if f.ord == "def" else " rentre au hangar."))
		return
	if nships(f.ships) == 0:
		C.say(f.name + " est vide : incorporez-y des vaisseaux du hangar.")
		return
	if C.count("spatioport") == 0:
		C.say("Il faut un spatioport pour faire décoller une flotte.")
		return
	var sp := slowest(f.ships)
	if op == "int":
		var e := {}
		for x in emoves:
			if x.id == int(arg):
				e = x
		if e.is_empty():
			C.say("Cette flotte ennemie n’est plus à portée.")
			return
		var t := intercept_time(f, e)
		moves.append({"fid": f.id, "kind": "int", "eid": e.id, "to": "home", "ships": f.ships, "p": 0.0, "dur": t, "back": false})
		C.say(f.name + " décolle pour intercepter la flotte ennemie (contact dans %d s)." % int(t))
	elif op == "col" or op == "atk":
		var a := A(arg)
		if a.is_empty() or owner(a) == "player":
			return
		if op == "col" and owner(a) != "neutral":
			return
		if op == "atk" and owner(a) != "enemy":
			return
		var dur := dist(a) / sp * 2.0
		moves.append({"fid": f.id, "kind": op, "to": a.id, "ships": f.ships, "p": 0.0, "dur": dur, "back": false})
		C.say(f.name + " décolle vers %s (%d s)." % [a.name, int(dur)])
	else:
		return
	f.ships = {}
	f.loc = "away"
	f.ord = "idle"
	w.launch_fx()


func arrive(m: Dictionary) -> void:
	var f := fleet(m.fid)
	var nm: String = f.name if not f.is_empty() else "La flotte"
	if m.back:
		if not f.is_empty():
			for u in m.ships:
				f.ships[u] = f.ships.get(u, 0) + m.ships[u]
			f.loc = "home"
		else:
			for u in m.ships:
				hangar[u] = hangar.get(u, 0) + m.ships[u]
		C.say(nm + " est de retour au spatioport.")
		w.land_fx()
		return
	var ret := func():
		if nships(m.ships) > 0:
			moves.append({"fid": m.fid, "kind": "ret", "to": "home", "ships": m.ships, "p": 0.0, "dur": maxf(3.0, m.dur), "back": true})
	if m.kind == "int":
		var e := {}
		for x in emoves:
			if x.id == m.eid:
				e = x
		if e.is_empty():
			log_combat(nm + " : cible perdue, retour à la base.")
			ret.call()
			return
		var att := mk(m.ships)
		var def := mk(e.ships)
		var a0 := ships_txt(m.ships)
		var d0 := ships_txt(e.ships)
		fight(att, def)
		m.ships = cnt_by(att)
		e.ships = cnt_by(def)
		var win := def.is_empty()
		if win:
			emoves.erase(e)
		elif e.has("sg"):
			e.sg.res = raid_sim(e)
		log_combat("Interception par %s : %s Vous : %s → %s. Ennemi : %s → %s." % [nm, "flotte ennemie détruite !" if win else "l’ennemi force le passage.", a0, ships_txt(m.ships), d0, "anéanti" if win else ships_txt(e.ships)])
		ret.call()
		return
	var a := A(m.to)
	if m.kind == "col" and owner(a) == "neutral":
		col[a.id] = true
		if not f.is_empty():
			f.stay = a.name
		for u in m.ships:
			if m.ships[u] > 0:
				m.ships[u] -= 1
				break
		C.say(a.name + " colonisée : un vaisseau y reste en station.")
		ret.call()
	elif m.kind == "atk" and owner(a) == "enemy":
		battle(m, a)
		ret.call()
	else:
		ret.call()


func fleet_sync() -> void:
	var keep: Array = []
	for f in fleets:
		var away := false
		for m in moves:
			if m.fid == f.id:
				away = true
		if f.loc == "away" and not away:
			if nships(f.ships) > 0:
				f.loc = "home"
			else:
				log_combat(f.name + (" est restée en station sur " + f.stay + "." if f.stay != "" else " a été anéantie."))
				continue
		keep.append(f)
	fleets = keep


# attaque de Kronos : flotte et tourelles ennemies
func battle(m: Dictionary, a: Dictionary) -> void:
	var att := mk(m.ships)
	var def := mk(E.fleet)
	var nT: int = E.bld.defense
	for i in nT:
		def.append({"u": "@def", "atk": 6.0, "hp": 60.0})
	var a0 := ships_txt(m.ships)
	var d0 := ships_txt(E.fleet) + (" + %d tourelles" % nT if nT > 0 else "")
	fight(att, def)
	m.ships = cnt_by(att)
	E.fleet = cnt_by(def)
	var win := def.is_empty()
	if win:
		E.dead = true
		emoves.clear()
		won = true
		w.war.kronos_dead = true
	log_combat("Attaque sur %s : %s Vous : %s → %s. Ennemi : %s → %s." % [a.name, "VICTOIRE, Kronos est conquis !" if win else "échec, retraite.", a0, ships_txt(m.ships), d0, "anéanti" if win else ships_txt(E.fleet)])


# ---------------------------------------------------------------- IA de Kronos
func en_str(f: Dictionary) -> float:
	var s := 0.0
	for u in f:
		s += float(f[u]) * EUNIT[u].s
	return s


func en_thr() -> float:
	return 5.0 + 5.0 * E.atkN


func en_log(t: String) -> void:
	E.log.push_front(t)
	if E.log.size() > 6:
		E.log.pop_back()


func en_think() -> void:
	if randf() < 0.3:
		return
	var b: Dictionary = E.bld
	var t: float = E.t
	var cm: float = 60.0 * (1.0 + 0.25 * b.mine)
	if t >= maxf(EGRACE, E.hold) and en_str(E.fleet) >= en_thr() and emoves.is_empty() and blk == null and randf() < 0.7:
		en_launch()
		return
	var opts: Array = []
	if b.mine < 2 + int(t / 200.0) and E.res >= cm:
		opts.append(func(): E.res -= cm; b.mine += 1; en_log("Nouvelle mine creusée"))
	if b.labo == 0 and t > 50.0 and E.res >= 90.0:
		opts.append(func(): E.res -= 90.0; b.labo = 1; en_log("Laboratoire construit"))
	if b.labo > 0 and E.cur == "":
		for k in ETECH:
			if not E.tech.has(k) and (not ETECH[k].has("r") or E.tech.has(ETECH[k].r)) and E.res >= ETECH[k].c:
				var kk: String = k
				opts.append(func(): E.res -= ETECH[kk].c; E.cur = kk; E.cp = 0.0; en_log("Recherche lancée : " + kk))
				break
	if b.usine == 0 and t > 100.0 and E.res >= 110.0:
		opts.append(func(): E.res -= 110.0; b.usine = 1; en_log("Chantier naval construit"))
	if b.defense < mini(6, 1 + E.atkN) and t > 150.0 and E.res >= 70.0:
		opts.append(func(): E.res -= 70.0; b.defense += 1; en_log("Tourelle installée"))
	if b.usine > 0 and E.q.size() < 2:
		var u := ""
		if E.tech.has("propulsion") and E.res >= 110.0 and randf() < 0.5:
			u = "corvette"
		elif E.tech.has("balistique") and E.res >= 45.0:
			u = "chasseur"
		elif E.res >= 28.0:
			u = "eclaireur"
		if u != "":
			opts.append(func(): E.res -= EUNIT[u].c; E.q.append({"u": u, "p": 0.0}))
	if opts.size() > 0:
		opts.pick_random().call()


func en_launch() -> void:
	var ships: Dictionary = E.fleet.duplicate()
	if nships(ships) == 0:
		return
	E.fleet = {}
	var dur := dist(A("kronos")) / slowest(ships) * 2.0
	E.atkN += 1
	E.mid += 1
	emoves.append({"id": E.mid, "ships": ships, "p": 0.0, "dur": dur})
	en_log("Flotte d’attaque lancée vers K-240")
	C.say("⚠ Une flotte pirate fonce sur K-240 : arrivée dans %d s !" % int(dur))


# bombardement du bouclier : nos défenses (flottes en patrouille, tourelles) contre la flotte pirate
func raid_sim(m: Dictionary) -> Dictionary:
	var DS := def_ships()
	var def := mk(DS)
	# renforts des factions alliées
	if w.factions != null:
		def.append_array(mk(w.factions.allied_ships()))
	var nd: int = C.count_done("tourelle")
	for i in nd:
		def.append({"u": "@def", "atk": 7.0, "hp": 250.0})
	var att := mk(m.ships)
	var a0 := ships_txt(m.ships)
	var d0 := ships_txt(DS) + " + %d tourelle(s)" % nd
	fight(def, att)
	return {"sv": cnt_by(att), "fl": cnt_by(def), "a0": a0, "d0": d0, "ok": att.is_empty()}


func inv_sim(sv: Dictionary) -> Dictionary:
	var N := 0
	for u in sv:
		N += int(sv[u]) * (6 if u == "corvette" else (2 if u == "eclaireur" else 1))
	N = clampi(N, 6, 30)
	# défense en surface : tourelles, soldats de la colonie présents sur le front, population ; sous terre : la milice
	var men := 0
	for F in w.war.FORM:
		if F.side == "b":
			men += F.alive.size()
	var defS: float = C.count_done("tourelle") * 4.0 + C.pop / 40.0 + 6.0 + men / 20.0
	var defI: float = 8.0 + C.pop / 40.0
	var kS := mini(N, int(round(defS * randf_range(0.7, 1.3) / 2.2)))
	var kI := mini(N - kS, int(round(defI * randf_range(0.7, 1.3) / 2.0)))
	return {"N": N, "kS": kS, "kI": kI, "win": kS + kI < N}


func raid_apply(m: Dictionary) -> void:
	var r: Dictionary = m.sg.res
	# pertes de nos flottes en patrouille
	var rem: Dictionary = r.fl.duplicate()
	for f in fleets:
		if f.ord != "def" or f.loc != "home":
			continue
		for u in f.ships:
			var k: int = mini(f.ships[u], rem.get(u, 0))
			rem[u] = rem.get(u, 0) - k
			f.ships[u] = k
	if r.ok:
		log_combat("Le bouclier a tenu, attaque repoussée ! Ennemi : %s → anéanti. Défenseurs : %s → %s." % [r.a0, r.d0, ships_txt(r.fl)])
		return
	var lostb: Array = w.destroy_buildings(3)
	w.SHD_DOWN = BLK_END + 5.0
	w.SHD_E = 0.0
	blk = {"t": 0.0, "sv": r.sv, "inv": inv_sim(r.sv), "said": false, "said2": false, "fac": m.get("fac", "")}
	log_combat("Le bouclier a cédé ! %d bâtiment(s) détruit(s) (%s). Blocus de K-240 : exportations coupées, débarquement dans %d s !" % [lostb.size(), ", ".join(lostb), int(BLK_LAND)])


# ---------------------------------------------------------------- satellites espions
func sat_on() -> Dictionary:
	# les savants ollen, liés par un accord, partagent leurs observations de Kronos
	if w.factions != null and w.factions.ollen_intel():
		return {"on": true, "life": 999.0, "p": 0.0, "dur": 1.0}
	for s in sats:
		if s.on and s.life > 0.0:
			return s
	return {}


func launch_sat() -> void:
	if not C.tech_done.has("espion"):
		C.say("Recherchez d’abord « Satellites espions ».")
		return
	if C.count_done("spatioport") == 0:
		C.say("Il faut un spatioport pour lancer un satellite.")
		return
	for s in sats:
		if not s.on:
			C.say("Un satellite est déjà en transit.")
			return
	if not C.affordable(SATC):
		C.say("Satellite espion : il manque " + C.cost_txt(SATC) + ".")
		return
	for r in SATC:
		C.stock[r] -= float(SATC[r])
	var dur: float = roundf(dist(A("kronos")) / SAT_SP * 2.0)
	sats = sats.filter(func(x): return x.on and x.life > 20.0)
	sats.append({"p": 0.0, "dur": dur, "on": false, "life": SAT_LIFE})
	C.say("Satellite espion lancé vers Kronos (arrivée dans %d s)." % int(dur))
	w.launch_fx()


func intel_txt() -> String:
	var on := sat_on()
	if E.dead:
		return "Kronos est conquis : plus aucune menace."
	if on.is_empty():
		for s in sats:
			if not s.on:
				return "Satellite en transit vers Kronos : arrivée dans %d s." % int(ceil(s.dur - s.p))
		return "Aucun satellite en orbite de Kronos : la colonie pirate est invisible. " + ("Lancez un satellite espion." if C.tech_done.has("espion") else "Recherchez « Satellites espions ».")
	var b: Dictionary = E.bld
	var r := en_str(E.fleet) / en_thr()
	var thr := "IMMINENTE" if r >= 1.0 else ("probable bientôt" if r >= 0.6 else "faible")
	if E.t < EGRACE:
		thr += " (pas avant %d min)" % int(ceil((EGRACE - E.t) / 60.0))
	return "KRONOS — ressources ≈ %d · %d mine(s) · laboratoire %s · chantier naval %s · %d tourelle(s).\nFlotte à quai : %s%s.\nRecherches : %s.\nMenace : %s.\nSatellite actif encore %d s.\nJournal : %s" % [
		int(E.res), b.mine, "actif" if b.labo else "absent", "actif" if b.usine else "absent", b.defense, ships_txt(E.fleet),
		(" (+%d en chantier)" % E.q.size()) if E.q.size() > 0 else "", ", ".join(E.tech.keys()) if E.tech.size() > 0 else "aucune",
		thr, int(on.life), " · ".join(E.log.slice(0, 3))]


func alert_txt() -> String:
	if lost:
		return "K-240 EST TOMBÉE."
	if won:
		return "VICTOIRE : Kronos est conquis."
	if blk != null:
		if blk.t < BLK_LAND:
			return "⚠ Blocus : débarquement dans %d s." % int(ceil(BLK_LAND - blk.t))
		if blk.t < BLK_ENT:
			return "⚠ Invasion : %d soldats marchent sur le centre de commandement (%d s)." % [blk.inv.N, int(ceil(BLK_ENT - blk.t))]
		return "⚠ Combats dans les galeries (%d s)." % int(maxf(0.0, ceil(BLK_END - blk.t)))
	for m in emoves:
		if m.has("sg"):
			return "⚠ Bombardement du bouclier (%s) : fin dans %d s." % [ships_txt(m.ships), int(maxf(0.0, ceil(SIEGE - m.sg.t)))]
		var who: String = "pirate" if not m.has("fac") else "ennemie (" + w.factions.F(m.fac).name + ")"
		return "⚠ Flotte %s en approche (%s) : arrivée dans %d s." % [who, ships_txt(m.ships), int(ceil(m.dur - m.p))]
	if w.survival != null:
		return w.survival.alert_txt()
	return ""


# ---------------------------------------------------------------- simulation
func step(dt: float) -> void:
	if lost:
		return
	# usine spatiale
	if queue.size() > 0:
		if C.count_done("spatioport") > 0:
			var q: Dictionary = queue[0]
			q.p += dt * C.eff
			if q.p >= UNITS[q.u].time:
				hangar[q.u] = hangar.get(q.u, 0) + 1
				queue.pop_front()
				C.say(UNITS[q.u].name + " terminé : il attend au hangar.")
	# revenus des colonies
	var cap: Dictionary = C.caps()
	for id in col:
		var a := A(id)
		for r in a.get("income", {}):
			if r == "credits" and blk != null:
				continue
			var im: float = w.factions.income_mult(id) if w.factions != null else 1.0
			C.stock[r] = minf(cap[r], C.stock[r] + float(a.income[r]) * im * dt)
			C.rates[r] += float(a.income[r]) * im
	# nos flottes en route
	for i in range(moves.size() - 1, -1, -1):
		var m: Dictionary = moves[i]
		m.p += dt
		if m.p >= m.dur:
			moves.remove_at(i)
			arrive(m)
	fleet_sync()
	# satellites
	for i in range(sats.size() - 1, -1, -1):
		var s: Dictionary = sats[i]
		if not s.on:
			s.p += dt
			if s.p >= s.dur:
				s.on = true
				C.say("Satellite espion en orbite de Kronos : renseignements disponibles.")
		else:
			s.life -= dt
			if s.life <= 0.0:
				sats.remove_at(i)
				C.say("Le satellite espion a été perdu : orbite décroissante.")
	# Kronos, les factions et les blocus n'existent qu'une fois la colonie repérée (phase 4 de la survie)
	if w.vie == null or w.vie.at_war():
		step_enemy(dt)
		if w.factions != null:
			w.factions.step(dt)
		step_blockade(dt)
	if bot_on:
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = 2.0
			bot_step()


func step_enemy(dt: float) -> void:
	if E.dead:
		return
	E.t += dt
	E.res += dt * (0.9 + 0.75 * E.bld.mine)
	if E.cur != "" and E.bld.labo > 0:
		E.cp += dt
		if E.cp >= ETECH[E.cur].t:
			E.tech[E.cur] = true
			en_log("Recherche achevée : " + E.cur)
			E.cur = ""
			E.cp = 0.0
	if E.q.size() > 0 and E.bld.usine > 0:
		var q: Dictionary = E.q[0]
		q.p += dt
		if q.p >= EUNIT[q.u].t:
			E.fleet[q.u] = E.fleet.get(q.u, 0) + 1
			E.q.pop_front()
	E.think -= dt
	if E.think <= 0.0:
		E.think = randf_range(20.0, 34.0)
		en_think()
	for i in range(emoves.size() - 1, -1, -1):
		var m: Dictionary = emoves[i]
		if not m.has("sg"):
			m.p = minf(m.dur, m.p + dt)
			if m.p >= m.dur:
				m.sg = {"t": 0.0, "res": raid_sim(m)}
				C.say("⚠ La flotte pirate se met en position de tir ! Bouclier à pleine puissance.")
				w.siege_begin(m.ships)
		else:
			m.sg.t += dt
			if m.sg.t >= SIEGE:
				emoves.remove_at(i)
				w.siege_end()
				raid_apply(m)


func step_blockade(dt: float) -> void:
	if blk == null:
		return
	blk.t += dt
	E.hold = maxf(E.hold, E.t + 90.0)
	if not blk.said and blk.t >= BLK_LAND:
		blk.said = true
		C.say("⚠ Débarquement : barges pirates sur K-240 !")
		w.invasion_fx(blk.inv.N)
	if not blk.said2 and blk.t >= BLK_ENT:
		blk.said2 = true
		var r: int = blk.inv.N - blk.inv.kS
		C.say("⚠ %d soldat(s) pirate(s) ont forcé le bunker d’accès et descendent le puits !" % r if r > 0 else "Tous les assaillants ont été abattus en surface.")
	if blk.t >= BLK_END:
		var iv: Dictionary = blk.inv
		var sv: Dictionary = blk.sv
		var from_fac: String = blk.get("fac", "")
		blk = null
		if iv.win:
			lost = true
			log_combat("K-240 est tombée : %d soldat(s) pirate(s) ont atteint le centre de commandement." % (iv.N - iv.kS - iv.kI))
		else:
			log_combat("Invasion repoussée : %d assaillants abattus en surface, %d dans les galeries. Le blocus est levé." % [iv.kS, iv.kI])
			for u in (sv if from_fac == "" else {}):
				E.fleet[u] = E.fleet.get(u, 0) + int(sv[u] / 2)


# ---------------------------------------------------------------- pilote automatique
func bot_toggle() -> void:
	bot_on = not bot_on
	bot_t = 0.0
	bot_intent = "Pilote automatique engagé" if bot_on else ""
	C.say("Pilote automatique " + ("engagé : l’IA prend les commandes." if bot_on else "désengagé."))


func threat() -> Dictionary:
	var f: Dictionary = E.fleet.duplicate()
	for q in E.q:
		f[q.u] = f.get(q.u, 0) + 1
	for m in emoves:
		for u in m.ships:
			f[u] = f.get(u, 0) + m.ships[u]
	return f


# nombre d'astéroïdes neutres pas encore visés par une flotte de colonisation
func col_needed() -> int:
	var n := 0
	for a in MAP:
		if owner(a) != "neutral":
			continue
		var busy := false
		for m in moves:
			if m.get("to", "") == a.id:
				busy = true
		if not busy:
			n += 1
	return n


func bot_step() -> void:
	if lost or won:
		bot_on = false
		bot_intent = "Partie terminée."
		return
	# survie d'abord : phases 1 à 3, puis les urgences vitales en phase 4
	if w.vie != null:
		var vi: String = w.vie.bot_step()
		if vi != "" and (w.vie.phase < 4 or not vi.begins_with("Attend")):
			bot_intent = vi
			return
	# moral : baisser les impôts quand il chute, les remonter quand il est bon
	C.tax = 4.0 if C.morale < 35.0 else (10.0 if C.morale > 55.0 else C.tax)
	# astéroïde glacé : les fondations cryogéniques passent avant tout (affaissements sous les réacteurs)
	if w.survival != null and w.survival.icy() and not C.tech_done.has("fondations") and C.tech_cur == "" and C.affordable(C.TECH.fondations.cost):
		C.research("fondations")
		bot_intent = "Lance la recherche : Fondations cryogéniques"
		return
	# Terre : livrer les contrats dès que possible ; science : calcul cryogénique et observatoire
	var SV = w.survival
	if SV != null:
		if SV.can_ship() == "":
			SV.ship()
			bot_intent = "Expédie une cargaison vers la Terre"
			return
		for t in ["observatoire", "calcul"]:
			if C.count(t) == 0 and C.can_build(t) == "":
				C.build(t)
				bot_intent = "Construit : " + C.BLD[t].name
				return
	# diplomatie : payer les tributs, signer les traités possibles, nommer des superviseurs
	var FX = w.factions
	if FX != null:
		for f in FX.FAC:
			var st: Dictionary = FX.fac[f.id]
			if not st.demand.is_empty() and C.stock.credits >= st.demand.amount:
				FX.answer(f.id, true)
				bot_intent = "Verse un tribut aux " + f.name
				return
			if st.treaty == "" and st.rel >= FX.TREATY.commerce.rel:
				FX.propose(f.id, "commerce")
				bot_intent = "Signe un accord commercial avec les " + f.name
				return
		for aid in col:
			if not FX.sup.has(aid) and C.stock.credits > 400.0:
				FX.hire(aid)
				bot_intent = "Nomme un superviseur sur " + A(aid).name
				return
	var home_def := def_ships()
	var thr := threat()
	var tw := 1e9
	for m in emoves:
		tw = minf(tw, m.dur - m.p)
	if emoves.is_empty():
		tw = maxf(0.0, EGRACE - E.t) + 30.0
	# 1. toujours une flotte de défense ; les vaisseaux du hangar la rejoignent
	var df := {}
	for f in fleets:
		if f.name == "Défense":
			df = f
	if df.is_empty() and nships(hangar) > 0:
		df = fleet_new()
		df.name = "Défense"
	# éclaireurs gardés au hangar pour coloniser les astéroïdes neutres encore libres
	var need_col := col_needed()
	if not df.is_empty() and df.loc == "home":
		for u in hangar:
			var keep: int = need_col if u == "eclaireur" else 0
			var n: int = hangar[u] - keep
			if n > 0:
				hangar[u] -= n
				df.ships[u] = df.ships.get(u, 0) + n
		if df.ord != "def" and nships(df.ships) > 0:
			fleet_order(df.id, "def")
	var safe: bool = power(home_def) + C.count_done("tourelle") * 7.0 * 250.0 >= power(thr) * 1.4
	# 2. menace : tourelles et vaisseaux
	if not safe and tw < 300.0:
		if C.can_build("tourelle") == "":
			C.build("tourelle")
			bot_intent = "Renforce la défense : tourelle"
			return
		if queue.size() < 3:
			var u := "corvette" if C.tech_done.has("propulsion") and C.affordable(UNITS.corvette.cost) else ("chasseur" if C.tech_done.has("balistique") and C.affordable(UNITS.chasseur.cost) else "")
			if u != "":
				order(u)
				bot_intent = "Renforce la défense : " + UNITS[u].name
				return
		# interception si elle est favorable
		for m in emoves:
			if not m.has("sg") and not df.is_empty() and df.loc == "home" and power(df.ships) > power(m.ships) * 1.6:
				fleet_order(df.id, "int:%d" % m.id)
				bot_intent = "Intercepte la flotte pirate"
				return
	# 3. recherche
	if C.tech_cur == "":
		for k in RESO:
			if C.TECH.has(k) and not C.tech_done.has(k) and C.requires_ok(C.TECH[k]) and C.affordable(C.TECH[k].cost):
				C.research(k)
				bot_intent = "Lance la recherche : " + C.TECH[k].name
				return
	# 4. énergie, stockage, extraction
	var under_cons := false
	for x in C.inst:
		if not x.done:
			under_cons = true
	if C.energy.c > C.energy.p - 3.0 and not under_cons:
		for t in ["fusion", "smr"]:
			if C.can_build(t) == "":
				C.build(t)
				bot_intent = "Produit de l’énergie : " + C.BLD[t].name
				return
		bot_intent = "Économise le fer-nickel pour une centrale (marge d’énergie faible)"
		return
	var cap: Dictionary = C.caps()
	# le fer-nickel est le goulot : une raffinerie de plus dès que le régolithe s'accumule
	if C.stock.fer < 150.0 and C.stock.regolithe > 250.0 and C.count("raffinerie") < 4 and C.energy.p - C.energy.c >= 3.0 and C.can_build("raffinerie") == "" and not under_cons:
		C.build("raffinerie")
		bot_intent = "Construit une raffinerie (fer-nickel)"
		return
	if (C.stock.fer > cap.fer * 0.9 or (C.stock.regolithe > cap.regolithe * 0.9 and C.count("raffinerie") >= 4)) and C.count("silo") < 3 and C.can_build("silo") == "" and not under_cons:
		C.build("silo")
		bot_intent = "Agrandit le stockage"
		return
	if C.count("moissonneuse") < 8 and C.can_build("moissonneuse") == "" and C.energy.p - C.energy.c > 4.0:
		C.build("moissonneuse")
		bot_intent = "Construit une moissonneuse"
		return
	if C.count("tourelle") < 2 and C.can_build("tourelle") == "":
		C.build("tourelle")
		bot_intent = "Construit une tourelle"
		return
	# 5. usine spatiale
	if queue.size() < 2 and C.count_done("spatioport") > 0:
		var in_q := 0
		for q in queue:
			if q.u == "eclaireur":
				in_q += 1
		var want_scout: bool = hangar.get("eclaireur", 0) + in_q < col_needed()
		var u := "eclaireur" if want_scout and C.affordable(UNITS.eclaireur.cost) else ("corvette" if C.tech_done.has("propulsion") and C.affordable(UNITS.corvette.cost) else ("chasseur" if C.tech_done.has("balistique") and C.affordable(UNITS.chasseur.cost) else ""))
		if u != "":
			order(u)
			bot_intent = "Usine spatiale : " + UNITS[u].name
			return
	# 6. colonisation avec une flotte d'éclaireurs
	if hangar.get("eclaireur", 0) > 0:
		for a in MAP:
			if owner(a) == "neutral":
				var busy := false
				for m in moves:
					if m.get("to", "") == a.id:
						busy = true
				if busy:
					continue
				var f := fleet_new()
				f.name = "Colonisation"
				hangar.eclaireur -= 1
				f.ships = {"eclaireur": 1}
				fleet_order(f.id, "col:" + a.id)
				bot_intent = "Colonise " + a.name
				return
	# 7. espionnage
	if C.tech_done.has("espion") and sat_on().is_empty() and C.affordable(SATC):
		var transit := false
		for s in sats:
			if not s.on:
				transit = true
		if not transit:
			launch_sat()
			bot_intent = "Lance un satellite espion"
			return
	# 8. assaut sur Kronos quand la flotte est nettement plus forte
	# on n'attaque Kronos qu'après l'avoir observé avec un satellite espion
	if not df.is_empty() and df.loc == "home" and emoves.is_empty() and blk == null and not sat_on().is_empty():
		var ep: float = power(E.fleet) + E.bld.defense * 6.0 * 60.0
		if power(df.ships) > ep * 1.8 and nships(df.ships) >= 6:
			fleet_order(df.id, "atk:kronos")
			bot_intent = "Lance l’assaut sur Kronos !"
			return
	bot_intent = "Surveille l’attaque…" if emoves.size() > 0 else ("Défend la colonie…" if blk != null else "Attend des ressources…")
