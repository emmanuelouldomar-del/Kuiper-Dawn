## Kuiper Dawn — économie et gestion de la colonie K-240 (portées du remake HTML « K-240 Remake »)
## Ressources, bâtiments de surface (production, consommation, énergie, stockage, pollution, chaleur),
## construction sur des emplacements libres, recherche, population, moral et impôts.
## Survie (2026-11-17) : la partie commence avec une capsule d'atterrissage endommagée et un équipage de 8 ;
## les bâtiments se débloquent par phases (« ph » : 2 stabilisation, 3 industrialisation, 4 expansion).
## Les flux vitaux (O2, CO2, eau, nourriture, chaleur), les phases et les menaces sont dans vie.gd.
extends Node

var w  # main.gd

# ---------------------------------------------------------------- données du jeu (gamedata)
const RES := {
	"regolithe": {"name": "Régolithe", "start": 200.0, "cap": 500.0, "color": Color("5fb3a1")},
	"fer": {"name": "Fer-nickel", "start": 60.0, "cap": 300.0, "color": Color("b9c2cc")},
	"credits": {"name": "Crédits", "start": 120.0, "cap": 1000.0, "color": Color("ffa24a")},
	"glace": {"name": "Glace d’eau", "start": 60.0, "cap": 400.0, "color": Color("9fe3ff")},
	"eau": {"name": "Eau", "start": 150.0, "cap": 300.0, "color": Color("4fb8ff")},
	"oxygene": {"name": "Oxygène", "start": 250.0, "cap": 400.0, "color": Color("bfefff")},
	"hydrogene": {"name": "Hydrogène", "start": 0.0, "cap": 200.0, "color": Color("ffc8f0")},
	"nourriture": {"name": "Nourriture", "start": 150.0, "cap": 300.0, "color": Color("9be36a")},
	"pieces": {"name": "Composants", "start": 20.0, "cap": 150.0, "color": Color("e0e0e0")},
	"beton": {"name": "Béton spatial", "start": 0.0, "cap": 300.0, "color": Color("a8a39a")},
	"titane": {"name": "Titane", "start": 0.0, "cap": 150.0, "color": Color("c8d6e8")},
	"he3": {"name": "Hélium-3", "start": 40.0, "cap": 200.0, "color": Color("c9a6ff")},
	"gaz": {"name": "Gaz rares", "start": 0.0, "cap": 200.0, "color": Color("7fd6c2")},
	"volatils": {"name": "Volatils", "start": 0.0, "cap": 300.0, "color": Color("d6c27f")},
	"precieux": {"name": "Métaux précieux", "start": 10.0, "cap": 150.0, "color": Color("ffd76a")},
	"uranium": {"name": "Combustible nucléaire", "start": 20.0, "cap": 120.0, "color": Color("9cff7a")},
	"terres": {"name": "Terres rares", "start": 0.0, "cap": 150.0, "color": Color("ff9ad5")},
}

# bâtiments ; ph : phase où ils se débloquent ; pollution : nuisance (moral) ; heat : chaleur dégagée en plus de l'énergie
# consommée ; housing : logement ; pressure : module pressurisé (une brèche y fait fuir l'oxygène) ; surface : arrêté en mode bunker
const BLD := {
	# --- la capsule d'atterrissage (présente au départ, non constructible)
	"capsule": {"name": "Capsule d’atterrissage", "cost": {}, "time": 1.0, "energy": 3.0, "ph": 99, "housing": 8.0, "pressure": true,
		"storage": {"oxygene": 100, "eau": 50, "nourriture": 50}, "desc": "Notre seul abri : générateur à radio-isotopes, recycleur d’air et rations."},
	# --- phase 2 : stabilisation
	"sas": {"name": "Module pressurisé et sas", "cost": {"regolithe": 50, "fer": 18}, "time": 12.0, "energy": -1.0, "ph": 2, "housing": 16.0, "pressure": true,
		"desc": "Habitat sous une butte de régolithe et sas de décompression : on entre et on sort sans vider l’air."},
	"station_eau": {"name": "Station de traitement d’eau", "cost": {"regolithe": 35, "fer": 12}, "time": 9.0, "energy": -2.0, "ph": 2,
		"consumes": {"glace": 0.8}, "produces": {"eau": 0.7}, "desc": "Fait fondre et purifie la glace extraite : eau potable."},
	"electrolyseur": {"name": "Électrolyseur d’eau", "cost": {"fer": 20, "regolithe": 20}, "time": 10.0, "energy": -4.0, "ph": 2,
		"consumes": {"eau": 0.12}, "produces": {"oxygene": 0.1, "hydrogene": 0.02}, "desc": "Sépare l’eau en oxygène (à respirer) et en hydrogène (carburant)."},
	"epurateur": {"name": "Épurateur de CO2", "cost": {"fer": 15, "regolithe": 20}, "time": 8.0, "energy": -2.0, "ph": 2, "scrub": 0.06,
		"desc": "Filtre le CO2 de l’air ; use des cartouches filtrantes (composants)."},
	"solaire": {"name": "Panneaux solaires", "cost": {"regolithe": 25, "fer": 8}, "time": 6.0, "energy": 5.0, "ph": 2, "solar": true,
		"desc": "Énergie gratuite, mais seulement le jour ; fragiles face aux micrométéorites."},
	"batterie": {"name": "Batteries haute capacité", "cost": {"fer": 12, "regolithe": 10}, "time": 6.0, "ph": 2, "battery": 250.0,
		"desc": "Stockent l’énergie pour la nuit ; elles peuvent griller pendant une éruption solaire."},
	"radiateur": {"name": "Radiateurs thermiques", "cost": {"fer": 10, "regolithe": 10}, "time": 6.0, "ph": 2, "cool": 10.0,
		"desc": "Le vide est un isolant : ces ailettes rayonnent la chaleur des machines."},
	"regulateur": {"name": "Régulateur thermique", "cost": {"fer": 15, "pieces": 3}, "time": 8.0, "energy": -2.0, "ph": 2, "heater": 10.0,
		"desc": "Chauffe la base la nuit, quand le froid du vide la gagne."},
	"foreuse": {"name": "Foreuse thermique", "cost": {"regolithe": 50, "fer": 20}, "time": 9.0, "energy": -3.0, "ph": 2, "surface": true,
		"produces": {"glace": 1.2, "volatils": 0.6}, "pollution": 1.0,
		"desc": "Fait fondre la glace d’eau et de méthane, puis la pompe."},
	"moissonneuse": {"name": "Moissonneuse-racleuse", "cost": {"regolithe": 60, "fer": 25}, "time": 10.0, "energy": -3.0, "ph": 2, "surface": true,
		"produces": {"regolithe": 2.5, "fer": 0.3, "he3": 0.12, "gaz": 0.15}, "pollution": 1.0, "mobile": true,
		"desc": "Racle le régolithe, en trie le fer et le chauffe à 800 °C : Hélium-3 et gaz rares."},
	# --- phase 3 : industrialisation
	"raffinerie": {"name": "Fonderie et raffinerie", "cost": {"regolithe": 120, "fer": 20}, "time": 12.0, "energy": -3.0, "ph": 3, "surface": true, "heat": 4.0,
		"consumes": {"regolithe": 1.2}, "reserve": {"regolithe": 80.0}, "produces": {"fer": 0.7, "beton": 0.3, "titane": 0.03, "terres": 0.05, "precieux": 0.03, "uranium": 0.015}, "pollution": 3.0,
		"desc": "Hauts fourneaux : lingots de fer et de titane, béton spatial, terres rares, métaux précieux et combustible."},
	"foreuse_prof": {"name": "Foreuse de profondeur", "cost": {"fer": 120, "beton": 40, "pieces": 10}, "time": 18.0, "energy": -8.0, "ph": 3, "heat": 3.0,
		"produces": {"titane": 0.08, "precieux": 0.05, "terres": 0.04, "glace": 0.5}, "housing": 40.0, "deep": true,
		"desc": "Creuse des galeries vers le noyau riche en métaux : abri contre radiations et météorites (+40 logements)."},
	"imprimante": {"name": "Imprimante 3D industrielle", "cost": {"fer": 60, "regolithe": 30}, "time": 10.0, "energy": -3.0, "ph": 3,
		"consumes": {"fer": 0.2, "terres": 0.01}, "produces": {"pieces": 0.1}, "desc": "Composants électroniques, pièces de rechange, cartouches, outils."},
	"serre": {"name": "Serre hydroponique", "cost": {"fer": 50, "regolithe": 40, "pieces": 3}, "time": 12.0, "energy": -3.0, "ph": 3, "pressure": true, "scrub": 0.01,
		"consumes": {"eau": 0.1, "volatils": 0.05}, "produces": {"nourriture": 0.06, "oxygene": 0.02}, "desc": "Nourriture sous lumière artificielle ; les plantes changent un peu de CO2 en oxygène."},
	"recycleur": {"name": "Recycleur", "cost": {"fer": 50, "pieces": 5}, "time": 10.0, "energy": -2.0, "ph": 3, "pressure": true,
		"produces": {"fer": 0.05}, "desc": "Broie déchets, vieux équipements et débris : besoins en eau et en air −30 %, un peu de fer."},
	"infirmerie": {"name": "Infirmerie", "cost": {"fer": 40, "pieces": 8}, "time": 10.0, "energy": -1.0, "ph": 3, "pressure": true, "heal": 0.06,
		"desc": "Soigne fractures, brûlures, mal des rayons et fatigue : la santé remonte plus vite."},
	"generateur_h2": {"name": "Générateur à hydrogène", "cost": {"fer": 40, "pieces": 4}, "time": 8.0, "ph": 3, "h2gen": 8.0, "heat": 2.0,
		"desc": "Courant de secours : brûle l’hydrogène de l’électrolyse quand l’énergie manque."},
	"drones": {"name": "Hub de drones", "cost": {"fer": 60, "pieces": 15}, "time": 12.0, "energy": -2.0, "ph": 3,
		"desc": "Des drones autonomes réparent les brèches et les dégâts de surface (2 composants par réparation)."},
	"commande": {"name": "Centre de commandement", "cost": {"fer": 100, "beton": 40, "pieces": 6}, "time": 20.0, "energy": -3.0, "ph": 3, "unique": true, "housing": 10.0, "pressure": true,
		"desc": "Bunker de commandement : recherche ×2 ; il porte le générateur du bouclier."},
	"propulseurs": {"name": "Propulseurs d’attitude", "cost": {"fer": 80, "titane": 8, "pieces": 6}, "time": 14.0, "ph": 3, "thrust": 0.08,
		"desc": "Corrigent la rotation et l’orbite quand le centre de gravité se déplace (brûlent de l’hydrogène)."},
	"laser": {"name": "Tourelle laser de défense", "cost": {"fer": 60, "titane": 15, "pieces": 10}, "time": 12.0, "energy": -6.0, "ph": 3,
		"desc": "Détruit les micrométéorites avant l’impact (−35 % de dégâts chacune). Très gourmande en énergie."},
	"silo": {"name": "Silos de stockage", "cost": {"regolithe": 60, "fer": 20}, "time": 6.0, "ph": 3,
		"storage": {"regolithe": 600, "fer": 400, "glace": 300, "volatils": 200, "terres": 100, "precieux": 100, "uranium": 80, "beton": 200, "titane": 100},
		"desc": "Quatre silos reliés par convoyeur."},
	"reservoir": {"name": "Réservoirs", "cost": {"regolithe": 50, "fer": 40}, "time": 8.0, "ph": 3,
		"storage": {"he3": 150, "gaz": 150, "volatils": 100, "credits": 500, "oxygene": 300, "hydrogene": 200, "eau": 200},
		"desc": "Sphères sous pression : oxygène, hydrogène, eau, Hélium-3 et gaz ; absorbent les pics de consommation."},
	"radar": {"name": "Radar et détecteur orbital", "cost": {"regolithe": 60, "fer": 30}, "time": 8.0, "energy": -1.0, "ph": 3,
		"desc": "Prévient bien à l’avance des pluies de météorites et des éruptions solaires ; étend le radar tactique."},
	"observatoire": {"name": "Observatoire profond", "cost": {"regolithe": 80, "fer": 60}, "time": 10.0, "energy": -1.0, "research": 0.25, "ph": 3,
		"desc": "Loin de la lumière du Soleil, une fenêtre parfaite sur l’univers : recherche +25 %."},
	"archives": {"name": "Forage des archives", "cost": {"regolithe": 100, "fer": 40}, "time": 10.0, "energy": -2.0, "research": 0.15, "ph": 3,
		"desc": "Carottes de glace intactes depuis 4,5 milliards d’années : recherche +15 % et découvertes ponctuelles."},
	# --- phase 4 : expansion
	"smr": {"name": "Réacteur à fission (SMR)", "cost": {"regolithe": 120, "fer": 80}, "time": 14.0, "energy": 14.0, "ph": 4, "heat": 6.0,
		"consumes": {"uranium": 0.04}, "pollution": 4.0,
		"desc": "Installé à l’écart, refroidi par radiateurs. Dangereux pour la population."},
	"fusion": {"name": "Centrale à fusion He-3/D", "cost": {"fer": 200, "terres": 40, "precieux": 20}, "time": 20.0, "energy": 40.0, "ph": 4, "heat": 10.0,
		"consumes": {"he3": 0.08, "glace": 0.1}, "pollution": 0.5, "requires": "fusion",
		"desc": "Énergie massive et continue grâce à l’Hélium-3 ; il faut beaucoup de radiateurs. Alimente le bouclier."},
	"catapulte": {"name": "Catapulte électromagnétique", "cost": {"fer": 180, "terres": 30}, "time": 16.0, "energy": -6.0, "ph": 4, "surface": true,
		"consumes": {"precieux": 0.15, "he3": 0.04}, "produces": {"credits": 6.0}, "pollution": 1.0, "requires": "catapulte",
		"desc": "Expédie lingots et bonbonnes d’Hélium-3 vers les cargos en orbite."},
	"spatioport": {"name": "Spatioport", "cost": {"regolithe": 120, "fer": 60}, "time": 12.0, "energy": -2.0, "ph": 4, "surface": true,
		"consumes": {"fer": 0.4}, "produces": {"credits": 1.6}, "unique": true, "colonists": 0.05,
		"desc": "Commerce avec les cargos de passage, arrivée de colons ; base des transports de la colonie."},
	"tourelle": {"name": "Tourelle canon", "cost": {"fer": 40, "credits": 20}, "time": 10.0, "energy": -1.0, "role": "defense", "ph": 4,
		"desc": "Canon double : obus à fusée de proximité contre les vaisseaux pirates qui bombardent le bouclier."},
	"calcul": {"name": "Centre de calcul cryogénique", "cost": {"fer": 120, "terres": 20, "precieux": 10}, "time": 14.0, "energy": -2.0, "ph": 4,
		"requires": "calcul", "research": 0.5,
		"desc": "Supercalculateurs refroidis gratuitement à 50 K par le vide : recherche +50 %."},
	"chantier_arche": {"name": "Chantier interstellaire", "cost": {"fer": 400, "terres": 60, "precieux": 40}, "time": 30.0, "energy": -6.0, "ph": 4,
		"requires": "fusion_prop", "unique": true,
		"desc": "Chantier naval en microgravité : y assembler le vaisseau-arche vers Alpha du Centaure (seconde victoire)."},
}

const TECH := {
	# phase 2
	"moisson": {"name": "Fours à 800 °C", "desc": "Moissonneuses : +50 % de production", "cost": {"regolithe": 150, "fer": 60}, "time": 25.0, "ph": 2,
		"mult": {"moissonneuse": 1.5}},
	"forage": {"name": "Forage thermique profond", "desc": "Foreuses : +50 % de production", "cost": {"fer": 80, "regolithe": 60}, "time": 30.0, "ph": 2,
		"mult": {"foreuse": 1.5}},
	"solaire_hr": {"name": "Cellules à haut rendement", "desc": "Panneaux solaires : +50 %", "cost": {"fer": 50, "regolithe": 40}, "time": 25.0, "ph": 2,
		"mult": {"solaire": 1.5}},
	"electrolyse": {"name": "Électrolyse haute pression", "desc": "Électrolyseurs : +50 %", "cost": {"fer": 50, "eau": 20}, "time": 25.0, "ph": 2,
		"mult": {"electrolyseur": 1.5}},
	"recyclage": {"name": "Recyclage à 99,9 %", "desc": "Eau et air recyclés : besoins vitaux −60 %", "cost": {"fer": 80, "pieces": 6}, "time": 30.0, "ph": 2},
	# phase 3
	"metallurgie": {"name": "Métallurgie", "desc": "Fonderie : +50 % de production", "cost": {"regolithe": 150, "fer": 30}, "time": 25.0, "ph": 3,
		"mult": {"raffinerie": 1.5}},
	"hydroponie": {"name": "Hydroponie avancée", "desc": "Serres : +50 %", "cost": {"fer": 60, "eau": 40}, "time": 30.0, "ph": 3, "mult": {"serre": 1.5}},
	"cartouches": {"name": "Cartouches régénérables", "desc": "Les épurateurs n’usent plus de composants", "cost": {"fer": 40, "pieces": 10}, "time": 25.0, "ph": 3},
	"filtres": {"name": "Filtres anti-pollution", "desc": "Pollution des usines : −40 %", "cost": {"fer": 100, "gaz": 30, "credits": 50}, "time": 30.0, "ph": 3},
	"blindage_eau": {"name": "Blindage à l’eau", "desc": "Réservoirs d’eau autour des habitats : radiations −60 % (consomme de la glace)", "cost": {"fer": 100, "glace": 100}, "time": 30.0, "ph": 3},
	"anneau": {"name": "Anneau centrifuge", "desc": "Gravité artificielle par rotation : fin de la perte osseuse", "cost": {"fer": 200, "credits": 100}, "time": 40.0, "ph": 3},
	"fondations": {"name": "Fondations cryogéniques", "desc": "Aérogels et alliages cryogéniques : plus d’affaissements sous les bâtiments chauds", "cost": {"fer": 120, "terres": 15}, "time": 30.0, "ph": 3},
	"harpons": {"name": "Ancrage par harpons", "desc": "Engins ancrés dans les gravats : séismes −80 %", "cost": {"fer": 90, "credits": 50}, "time": 25.0, "ph": 3},
	# phase 4
	"fusion": {"name": "Fusion He-3/D", "desc": "Débloque la centrale à fusion", "requires": "forage", "cost": {"fer": 200, "he3": 20, "credits": 120}, "time": 45.0, "ph": 4},
	"catapulte": {"name": "Catapulte électromagnétique", "desc": "Débloque l’exportation par mass driver", "cost": {"fer": 150, "terres": 20, "credits": 80}, "time": 35.0, "ph": 4},
	"boucliers": {"name": "Bouclier renforcé", "desc": "Recharge du bouclier : +50 %", "requires": "metallurgie", "cost": {"fer": 160, "precieux": 20, "credits": 100}, "time": 40.0, "ph": 4},
	"balistique": {"name": "Balistique", "desc": "Débloque le chasseur", "cost": {"fer": 60, "credits": 30}, "time": 30.0, "ph": 4},
	"propulsion": {"name": "Propulsion ionique", "desc": "Débloque la corvette", "requires": "balistique", "cost": {"fer": 100, "credits": 60}, "time": 40.0, "ph": 4},
	"espion": {"name": "Satellites espions", "desc": "Observation de Kronos depuis le spatioport", "requires": "balistique", "cost": {"fer": 80, "credits": 40}, "time": 25.0, "ph": 4},
	"propulseurs": {"name": "Propulseurs d’astéroïde", "desc": "Débloque l’astéroïde-bélier (onglet Opérations)", "requires": "propulsion", "cost": {"fer": 200, "he3": 60, "credits": 120}, "time": 50.0, "ph": 4},
	"bouclier_mag": {"name": "Bouclier magnétique", "desc": "Champ magnétique artificiel : radiations −70 %", "requires": "boucliers", "cost": {"fer": 180, "terres": 30, "credits": 120}, "time": 45.0, "ph": 4},
	"calcul": {"name": "Calcul cryogénique", "desc": "Débloque le centre de calcul cryogénique", "cost": {"fer": 100, "terres": 15, "credits": 80}, "time": 35.0, "ph": 4},
	"fusion_prop": {"name": "Propulsion à fusion", "desc": "Débloque le chantier interstellaire et le vaisseau-arche", "requires": "fusion", "cost": {"fer": 250, "he3": 80, "credits": 200}, "time": 60.0, "ph": 4},
}

const COLONY := {"startPop": 8.0, "growth": 0.01, "taxIncome": 0.02, "baseMorale": 70.0, "taxMorale": 1.5,
	"deficitMorale": 20.0, "pollutionMorale": 0.9}

# emplacements de surface pour construire (coordonnées avant la réduction BSC) : 8 près du centre, puis des anneaux
# plus loin, hors du secteur du front (+z). Les bâtiments dessinés dans la base (build_base) sont d'abord dévoilés
# à leur place (main.construct) ; les emplacements ne servent qu'aux exemplaires suivants.
var SLOTS: Array = [Vector2(-150, -10), Vector2(-205, 40), Vector2(190, -25), Vector2(195, -100), Vector2(-115, -150), Vector2(115, -150), Vector2(-45, 105), Vector2(80, 110)]

# ---------------------------------------------------------------- état
var stock := {}
var rates := {}
var energy := {"p": 0.0, "c": 0.0}
var eff := 1.0
var battery := 60.0           # énergie stockée (capsule + batteries)
var h2_out := 0.0             # puissance fournie par les générateurs à hydrogène
var inst: Array = []          # {t, done, p, s (état), slot, dmg (endommagé), halt (arrêt temporaire)}
var slot_used := {}
var tech_done := {}
var tech_cur := ""
var tech_p := 0.0
var pop := 8.0
var tax := 10.0
var morale := 65.0
var pollution := 0.0
var log: Array = []           # messages de la console
const SHIELD_DRAW := 10.0     # le générateur du bouclier consomme de l'énergie (en guerre seulement)


func setup(world, start_phase := 1) -> void:
	w = world
	for r in [280.0, 330.0, 380.0]:
		var n: int = int(TAU * r / 75.0)
		for i in n:
			var a: float = TAU * (i + 0.5 * (int(r) % 2)) / n
			var v: Vector2 = Vector2(sin(a), cos(a)) * r
			# pas dans le secteur du front (vers +z)
			if v.y > 0.0 and absf(v.x) < r * 0.62:
				continue
			SLOTS.append(v)
	for r in RES:
		stock[r] = float(RES[r].start)
		rates[r] = 0.0
	pop = COLONY.startPop
	inst.append({"t": "capsule", "done": true, "p": 0.0, "s": "ok", "slot": -1})
	if start_phase <= 1:
		# atterrissage : quelques réserves dans la capsule, le reste est à extraire à la main
		stock = {"regolithe": 20.0, "fer": 6.0, "credits": 50.0, "glace": 15.0, "eau": 120.0, "oxygene": 220.0, "hydrogene": 0.0,
			"nourriture": 140.0, "pieces": 20.0, "beton": 0.0, "titane": 0.0, "he3": 0.0, "gaz": 0.0, "volatils": 0.0,
			"precieux": 0.0, "uranium": 0.0, "terres": 0.0}
		say("Atterrissage forcé sur K-240 : la capsule est endommagée. L’équipage commence à miner à la main.")
		return
	# partie lancée à une phase plus avancée (--phase N) : la colonie a déjà fait les phases précédentes
	var pre := ["sas", "station_eau", "electrolyseur", "epurateur", "solaire", "solaire", "batterie", "regulateur", "radiateur", "foreuse", "moissonneuse"]
	if start_phase >= 3:
		pre += ["sas", "electrolyseur", "epurateur", "solaire", "solaire", "batterie", "foreuse", "moissonneuse", "silo", "reservoir"]
	if start_phase >= 4:
		pre += ["raffinerie", "foreuse_prof", "imprimante", "serre", "serre", "radiateur", "radiateur", "commande", "recycleur", "infirmerie",
			"radar", "propulseurs", "laser", "generateur_h2", "drones", "fusion", "smr", "catapulte", "spatioport", "foreuse", "foreuse",
			"moissonneuse", "moissonneuse", "moissonneuse", "electrolyseur", "epurateur"]
		tech_done["catapulte"] = true
		tech_done["fusion"] = true
		pop = 120.0
	for t in pre:
		inst.append({"t": t, "done": true, "p": 0.0, "s": "ok", "slot": -1})
	stock.oxygene = 300.0
	stock.eau = 200.0
	stock.nourriture = 250.0
	stock.pieces = 60.0
	stock.hydrogene = 60.0
	stock.beton = 80.0
	stock.titane = 30.0
	battery = 300.0


# dévoile en 3D les bâtiments déjà présents au départ (appelé par main une fois la base construite)
func reveal_start() -> void:
	for x in inst:
		if x.done and x.t != "capsule" and not x.has("nodes"):
			x.slot = -1
			if w.pool_left(x.t) <= 0 and not BLD[x.t].get("mobile", false):
				x.slot = free_slot()
				if x.slot >= 0:
					slot_used[x.slot] = true
			x.nodes = w.construct(x.t, SLOTS[x.slot] if x.slot >= 0 else Vector2.ZERO)


func say(t: String) -> void:
	var m := int(w.war.time / 60.0) if w.war != null else 0
	var s := int(w.war.time) % 60 if w.war != null else 0
	log.push_front("[%02d:%02d] %s" % [m, s, t])
	if log.size() > 40:
		log.pop_back()


func phase() -> int:
	return w.vie.phase if w.vie != null else 4


func caps() -> Dictionary:
	var c := {}
	for r in RES:
		c[r] = float(RES[r].cap)
	for x in inst:
		if x.done and BLD[x.t].has("storage"):
			for r in BLD[x.t].storage:
				c[r] += float(BLD[x.t].storage[r])
	return c


func bat_cap() -> float:
	var c := 60.0
	for x in inst:
		if x.done and not x.get("dmg", false):
			c += float(BLD[x.t].get("battery", 0.0))
	return c


func housing() -> float:
	var h := 0.0
	for x in inst:
		if x.done:
			h += float(BLD[x.t].get("housing", 0.0))
	return h


func count_done(t: String) -> int:
	var n := 0
	for x in inst:
		if x.t == t and x.done:
			n += 1
	return n


# bâtiments en service : terminés, ni endommagés ni arrêtés
func count_ok(t: String) -> int:
	var n := 0
	for x in inst:
		if x.t == t and x.done and not x.get("dmg", false) and x.get("halt", 0.0) <= 0.0:
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
	return (not d.has("requires") or tech_done.has(d.requires)) and int(d.get("ph", 1)) <= phase()


# ---------------------------------------------------------------- construction
func can_build(t: String) -> String:
	var B: Dictionary = BLD[t]
	if int(B.get("ph", 1)) > phase():
		return "Phase %d" % int(B.get("ph", 1)) if int(B.ph) < 99 else "Non constructible"
	if B.has("requires") and not tech_done.has(B.requires):
		return "Requiert : " + TECH[B.requires].name
	if B.get("unique", false) and count(t) > 0:
		return "Déjà construit"
	if not B.get("mobile", false) and w.pool_left(t) <= 0 and free_slot() < 0:
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
		# un bâtiment dessiné dans la base attend encore : le chantier s'installe à sa place
		var sp = w.pool_pos(t)
		if sp != null:
			x.scaf = w.scaffold(sp)
		else:
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
	if w.vie != null and not w.vie.capsule_ok:
		say("Il faut d’abord réparer l’ordinateur de la capsule.")
		return
	if tech_cur != "":
		say("Une recherche est déjà en cours.")
		return
	if int(t.get("ph", 1)) > phase():
		say(t.name + " : disponible en phase %d." % int(t.ph))
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


# arrêté : endommagé, affaissement, ou bâtiment de surface en mode bunker
func stopped(x: Dictionary) -> String:
	if x.get("dmg", false):
		return "endommagé"
	if x.get("halt", 0.0) > 0.0:
		return "affaissement"
	if w.vie != null and w.vie.bunker and BLD[x.t].get("surface", false):
		return "bunker"
	return ""


# ---------------------------------------------------------------- simulation (par seconde de jeu)
func step(dt: float) -> void:
	var cap := caps()
	var V = w.vie
	var day: float = V.daylight if V != null else 1.0
	var heat_k: float = V.heat_eff() if V != null else 1.0
	# construction
	for x in inst:
		if not x.done:
			x.p += dt
			if x.p >= float(BLD[x.t].time):
				finish(x)
	# énergie : producteurs (le solaire suit le jour), consommateurs, générateurs à hydrogène, batteries
	var p := 0.0
	var c := SHIELD_DRAW if (V == null or V.at_war()) and count_done("commande") + count_done("fusion") > 0 else 0.0
	var h2gen := 0.0
	for x in inst:
		if not x.done:
			continue
		var B: Dictionary = BLD[x.t]
		if x.get("halt", 0.0) > 0.0:
			x.halt -= dt
			continue
		if stopped(x) != "":
			continue
		var e := float(B.get("energy", 0.0))
		if x.t == "capsule" and V != null and not V.capsule_ok:
			e = 1.5
		if B.get("solar", false):
			e *= day * mult(x.t)
		h2gen += float(B.get("h2gen", 0.0))
		if e > 0.0:
			var fu := 1.0
			for r in B.get("consumes", {}):
				var need := float(B.consumes[r]) * dt
				if need > 0.0 and stock[r] < need:
					fu = minf(fu, stock[r] / need)
			p += e * fu
		else:
			c -= e
	# générateurs à hydrogène : seulement en cas de déficit
	h2_out = 0.0
	if c > p and h2gen > 0.0:
		var want := minf(c - p, h2gen)
		var need_h := want / 8.0 * 0.25 * dt
		if stock.hydrogene < need_h:
			want *= stock.hydrogene / need_h
			need_h = stock.hydrogene
		stock.hydrogene -= need_h
		rates.hydrogene = -need_h / maxf(dt, 1e-6)
		h2_out = want
		p += want
	# batteries : le surplus les charge, le déficit les vide
	var bc := bat_cap()
	if p > c:
		battery = minf(bc, battery + (p - c) * dt)
		energy = {"p": p, "c": c}
	else:
		var draw := minf((c - p) * dt, battery)
		battery -= draw
		energy = {"p": p + draw / maxf(dt, 1e-6), "c": c}
	battery = minf(battery, bc)
	eff = minf(1.0, energy.p / c) if c > 0.0 else 1.0
	eff *= heat_k
	# production et consommation
	for r in RES:
		if r != "hydrogene" or h2_out <= 0.0:
			rates[r] = 0.0
	pollution = 0.0
	var pol_k := 0.6 if tech_done.has("filtres") else 1.0
	for x in inst:
		if not x.done:
			continue
		var B: Dictionary = BLD[x.t]
		var why := stopped(x)
		if why != "":
			x.s = why
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
			# réserve : la fonderie laisse du régolithe pour construire
			var avail: float = stock[r] - float(B.get("reserve", {}).get(r, 0.0))
			if need > 0.0 and avail < need * f:
				f = maxf(0.0, avail) / need
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
	# recherche (ordinateur de la capsule, puis centre de commandement)
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
	# population (dans les modules et les galeries), moral, impôts
	var target := COLONY.baseMorale - tax * COLONY.taxMorale - pollution * COLONY.pollutionMorale
	if energy.c > energy.p:
		target -= COLONY.deficitMorale
	if w.SHD_DOWN > 0.0:
		target -= 10.0
	var hp: float = w.survival.health if w.survival != null else 80.0
	if w.survival != null:
		target -= w.survival.morale_malus()
	if V != null:
		target -= V.morale_malus()
	target = clampf(target, 0.0, 100.0)
	morale += (target - morale) * minf(1.0, dt * 0.05)
	var hs := housing()
	var vital_ok: bool = V == null or V.vital_ok()
	# la population ne grandit que si l'air est sain (pas avant les épurateurs) ; lentement avant la phase 3
	if pop < hs and morale >= 30.0 and hp >= 45.0 and vital_ok and (V == null or V.co2 < 1.2):
		var g := pop * COLONY.growth * dt * morale / 100.0 * (0.5 if phase() <= 2 else 1.0)
		# colons arrivés par le spatioport
		g += float(count_ok("spatioport")) * float(BLD.spatioport.colonists) * dt * 10.0
		pop = minf(hs, pop + g)
	if pop > hs + 0.5:
		pop -= (pop - hs) * 0.01 * dt
	if morale < 25.0:
		pop -= pop * 0.003 * dt
	if hp < 30.0:
		pop -= pop * 0.004 * dt
	pop = maxf(0.0, pop)
	var inc := pop * tax / 100.0 * COLONY.taxIncome
	stock.credits = minf(cap.credits, stock.credits + inc * dt)
	rates.credits += inc


# vitesse de recherche : ordinateur de la capsule (×0,5), centre de commandement (×1), bâtiments scientifiques
func research_mult() -> float:
	var m := 1.0 if count_ok("commande") > 0 else 0.5
	for x in inst:
		if x.done and x.get("halt", 0.0) <= 0.0 and not x.get("dmg", false):
			m += float(BLD[x.t].get("research", 0.0))
	return m


# facteur de recharge du bouclier : énergie disponible et recherche
func shield_factor() -> float:
	return eff * (1.5 if tech_done.has("boucliers") else 1.0)
