## Kuiper Dawn — survie à 40 UA du Soleil : les défis réels de la colonisation de la ceinture de Kuiper en mécaniques de jeu.
## - santé de la population : rayons cosmiques galactiques (tempêtes), microgravité, besoins vitaux (eau, volatils) ;
## - sol glacé : la chaleur des réacteurs et des raffineries fait fondre les fondations (affaissements) ;
## - astéroïde en « tas de gravats » : un minage trop intense le fragmente (séismes) ;
## - isolement : contrats de la Terre transmis avec des heures de latence, ravitaillement ;
## - tremplin interstellaire : le vaisseau-arche vers Alpha du Centaure, seconde voie de victoire.
extends Node

var w  # main.gd
var C  # colony.gd

var health := 80.0           # santé de la population (0–100)
var dose := 0.0              # exposition actuelle aux radiations
var storm_t := 300.0         # prochaine tempête de rayons cosmiques
var storm := 0.0             # durée restante de la tempête en cours
var short_water := false
var short_vol := false
var melt_t := 120.0
var quake_t := 90.0
var log: Array = []
# Terre
var contract := {}           # contrat en cours {res, qty, t, reward, sent}
var incoming := 45.0         # message de la Terre en transit (latence)
var latency_h := 5.5         # heures-lumière affichées
var rep := 0                 # réputation auprès de la Terre
var supply_t := 300.0
# vaisseau-arche
var ark := 0.0               # progression (0–100 %)
var ark_on := false
var ark_won := false
const ARK_NEED := {"fer": 2.0, "he3": 0.5, "glace": 1.0, "precieux": 0.1}
const ARK_TIME := 600.0


func setup(world, colony) -> void:
	w = world
	C = colony


func say(t: String) -> void:
	log.push_front(t)
	if log.size() > 8:
		log.pop_back()
	C.say(t)


func icy() -> bool:
	return w.SH_RHO < 1500.0


func morale_malus() -> float:
	return (100.0 - health) * 0.3


# ---------------------------------------------------------------- simulation
func step(dt: float) -> void:
	var T: Dictionary = C.tech_done
	# besoins vitaux : eau (et oxygène) tirée de la glace, volatils pour l'agriculture hydroponique
	var rec := 0.1 if T.has("recyclage") else 1.0
	var nw: float = C.pop * 0.003 * rec
	var nv: float = C.pop * 0.0015 * rec
	short_water = C.stock.glace < nw * dt
	short_vol = C.stock.volatils < nv * dt
	C.stock.glace = maxf(0.0, C.stock.glace - nw * dt)
	C.stock.volatils = maxf(0.0, C.stock.volatils - nv * dt)
	C.rates.glace -= nw
	C.rates.volatils -= nv
	# radiations : fond cosmique, tempêtes ; blindage à eau, bouclier magnétique, dôme du centre de commandement
	if storm > 0.0:
		storm -= dt
		if storm <= 0.0:
			say("Fin de la tempête de rayons cosmiques.")
	else:
		storm_t -= dt
		if storm_t <= 0.0:
			storm_t = randf_range(260.0, 380.0)
			storm = 40.0
			say("⚠ Tempête de rayons cosmiques galactiques : la population se réfugie sous la glace (40 s).")
	dose = 0.2 + (3.0 if storm > 0.0 else 0.0)
	if T.has("blindage_eau"):
		var g := 0.3 * dt
		if C.stock.glace >= g:
			C.stock.glace -= g
			C.rates.glace -= 0.3
			dose *= 0.4
	if T.has("bouclier_mag"):
		dose *= 0.3
	if storm > 0.0 and w.SHD_DOWN <= 0.0:
		dose *= 0.6
	var dh := -dose * 0.05
	if not T.has("anneau"):
		dh -= 0.03          # microgravité : perte osseuse et musculaire
	if short_water:
		dh -= 0.3
	if short_vol:
		dh -= 0.15
	if not short_water and not short_vol and storm <= 0.0:
		dh += 0.06
	health = clampf(health + dh * dt, 0.0, 100.0)
	# sol glacé : affaissements sous les bâtiments chauds
	melt_t -= dt
	if melt_t <= 0.0:
		melt_t = 120.0
		var p := 0.035 * (1.5 if icy() else 0.7) * (0.1 if T.has("fondations") else 1.0)
		for x in C.inst:
			if x.done and x.t in ["smr", "fusion", "raffinerie"] and x.get("halt", 0.0) <= 0.0 and randf() < p:
				x.halt = 60.0
				say("⚠ Affaissement : la chaleur de « %s » a fait fondre la glace sous ses fondations (arrêt 60 s)." % C.BLD[x.t].name)
				break
	# tas de gravats : séismes si le minage est trop intense
	quake_t -= dt
	if quake_t <= 0.0:
		quake_t = 90.0
		var mining: int = C.count_done("moissonneuse") + C.count_done("foreuse")
		var lim := 6 if icy() else 10
		if mining > lim and randf() < 0.25 * (0.2 if T.has("harpons") else 1.0):
			var lostb: Array = w.destroy_buildings(1, "moissonneuse")
			if lostb.size() > 0:
				say("⚠ Séisme : l’astéroïde, un tas de gravats, s’est fragmenté sous le minage. Une moissonneuse a été engloutie.")
	step_earth(dt)
	step_ark(dt)


# ---------------------------------------------------------------- liaison avec la Terre (latence de plusieurs heures)
func step_earth(dt: float) -> void:
	if contract.is_empty():
		incoming -= dt
		if incoming <= 0.0:
			var opts := [["he3", 60, 260], ["glace", 150, 160], ["terres", 25, 240], ["precieux", 20, 280], ["volatils", 120, 170]]
			var o: Array = opts.pick_random()
			latency_h = randf_range(4.0, 7.0)
			contract = {"res": o[0], "qty": o[1], "reward": o[2], "t": 300.0}
			say("Message de la Terre (émis il y a %d h %02d) : livrez %d %s sous 5 min, prime %d crédits." % [int(latency_h), int(fmod(latency_h, 1.0) * 60), o[1], C.RES[o[0]].name, o[2]])
	else:
		contract.t -= dt
		if contract.t <= 0.0:
			rep -= 1
			say("Contrat terrien expiré : la Terre est déçue (réputation %d)." % rep)
			contract = {}
			incoming = randf_range(60.0, 110.0)
	# ravitaillement terrien pour une colonie fiable
	if rep >= 3:
		supply_t -= dt
		if supply_t <= 0.0:
			supply_t = 300.0
			var cap: Dictionary = C.caps()
			C.stock.uranium = minf(cap.uranium, C.stock.uranium + 20.0)
			C.stock.precieux = minf(cap.precieux, C.stock.precieux + 15.0)
			say("Convoi de ravitaillement de la Terre arrivé (après 3 ans de voyage) : +20 combustible, +15 métaux précieux.")


func can_ship() -> String:
	if contract.is_empty():
		return "Aucun contrat en cours."
	if C.count_done("catapulte") == 0 and C.count_done("spatioport") == 0:
		return "Il faut une catapulte ou un spatioport."
	if C.stock[contract.res] < float(contract.qty):
		return "Stock insuffisant."
	return ""


func ship() -> void:
	var why := can_ship()
	if why != "":
		say("Expédition vers la Terre : " + why)
		return
	C.stock[contract.res] -= float(contract.qty)
	C.stock.credits = minf(C.caps().credits, C.stock.credits + float(contract.reward))
	rep += 1
	say("Cargaison expédiée vers la Terre : prime de %d crédits (réputation %d)." % [contract.reward, rep])
	contract = {}
	incoming = randf_range(60.0, 110.0)
	w.launch_fx()


# ---------------------------------------------------------------- vaisseau-arche vers Alpha du Centaure
func ark_toggle() -> void:
	if C.count_done("chantier_arche") == 0:
		say("Construisez d’abord le chantier interstellaire.")
		return
	ark_on = not ark_on
	say("Assemblage du vaisseau-arche " + ("lancé." if ark_on else "suspendu."))


func step_ark(dt: float) -> void:
	if not ark_on or ark_won or C.count_done("chantier_arche") == 0:
		return
	var f := 1.0
	for r in ARK_NEED:
		var need: float = ARK_NEED[r] * dt
		if C.stock[r] < need:
			f = minf(f, C.stock[r] / need)
	for r in ARK_NEED:
		C.stock[r] -= ARK_NEED[r] * dt * f
		C.rates[r] -= ARK_NEED[r] * f
	var old := ark
	ark = minf(100.0, ark + dt * f * 100.0 / ARK_TIME)
	w.ark_visual(ark)
	if int(old / 25.0) != int(ark / 25.0) and ark < 100.0:
		say("Vaisseau-arche : assemblage à %d %%." % int(ark))
	if ark >= 100.0:
		ark_won = true
		ark_on = false
		say("Le vaisseau-arche s’élance vers Alpha du Centaure : la ceinture de Kuiper a servi de tremplin à l’humanité !")
		w.strategy.won = true
		w.strategy.win_kind = "arche"


func alert_txt() -> String:
	if storm > 0.0:
		return "⚠ Tempête de rayons cosmiques (%d s)" % int(ceil(storm))
	if short_water:
		return "⚠ Pénurie d’eau : la population souffre"
	return ""
