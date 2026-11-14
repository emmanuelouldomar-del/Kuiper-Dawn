# Agent.md — contexte du projet Kuiper Dawn (K-240)

Fichier de contexte pour les agents (Claude Code) qui travaillent sur ce dépôt. À relire en début de session et à tenir à jour. `CLAUDE.md` l'importe automatiquement (`@Agent.md`).

## 1. Le projet en bref

- **Jeu Godot 4.7.2** (GDScript), renderer **GL Compatibility**, fenêtre 1600×900, plafonné à 60 images/s.
- **Univers** : la colonie minière **K-240**, un astéroïde de la ceinture de Kuiper, et sa guerre contre les **pirates de Kronos**. Le jeu actuel montre une **bataille de surface sans fin** entre la colonie (camp `"b"`, vert/bleu) et les pirates (camp `"r"`, rouge), au pied de la base minière, sur un astéroïde sphérique.
- **Style visé** : minimaliste et géométrique, « façon Monument Valley ». Le nom interne est « K-240 Front de surface (BD) » : interface façon bande dessinée, massifs rocheux en dalles orange/rose/violet, touffes de cristaux bleu-vert.
- **Langue** : tout est en **français** (commentaires, interface, noms de variables comme `VUES`, `gp`, `hdisp`, `soldiers`). Garder le français.
- **Ce n'est pas encore un jeu jouable** : c'est une simulation qu'on regarde. Le joueur ne donne pas d'ordres ; la caméra est libre et on peut changer de vue, de vitesse et de filtre.

## 2. Structure du dépôt

```
project.godot          config (nom, main_scene, GL Compatibility, 1600x900, ombres 2048)
main.tscn              scène minimale : un Node3D "Jeu" avec main.gd (tout est construit en code)
main.gd    (~1670 l.)  monde : astéroïde, terrain, ciel, base, rochers, caméra, vues, post-traitement, HUD
battle.gd  (~1460 l.)  simulation de bataille : formations, tirs, effets, aviation, rendu instancié
shaders/
  terrain.gdshader     terrain enroulé sur la sphère (même calcul de hauteur que main.gd)
  post.gdshader        filtre de style plein écran (13 modes, touche S)
  planet.gdshader      planète de fond (la « Terre »)
  lobe.gdshader        second lobe d'un astéroïde binaire
  plume.gdshader       panache des fusées
terrain/
  height.bin           hauteurs 1024×1024 float32 (4 Mo), tuile périodique
  albedo.bin           albédo 1024×1024 float32 (4 Mo)
images/                captures des vues (k240_jeu_*, k240_grand_*, k240_petit_*, k240_mini_*, k240_style_*) ; non utilisées par le code
Lancer le jeu.bat      lance Godot\Godot_v4.7.2-stable_win64.exe --path .
Ouvrir dans Godot.bat  idem avec -e (éditeur)
Godot/                 (non versionné, .gitignore) : y copier l'exe Godot 4.7.2 pour que les .bat marchent
build.ps1 / build.bat  système de build (export Godot), voir §5 bis
export_presets.cfg     presets d'export « Windows » et « Linux »
build/, dist/          sorties du build (non versionnées)
```

## 3. `main.gd` — le monde

### Échelle et forme de l'astéroïde
- 1 unité = 1 m. Le front de bataille fait `FRONT_LEN = 340` m.
- **Taille aléatoire à chaque partie** : `TAILLE_K ∈ [1.2, 3.0]`, `RC = TAILLE_K × FRONT_LEN × 0.5`, soit un rayon d'environ 200 à 510 m.
- **Forme aléatoire** (`make_shape`) : `"patate"`, `"allongé"` ou `"binaire"`. Elle est définie par un ellipsoïde `SH_ELL`, 16 bosses gaussiennes (`SH_BLOBS`), et pour le binaire un second lobe : une sphère séparée (`LOBE_FUSED = false`, shader `lobe`). La calotte autour de la base et du front (angle `SH_TH0`) reste parfaitement sphérique, de rayon `RC`.
- **Grand relief** (`make_relief`) : 10 cratères géants (seuls les 3 premiers sont creusés), 4 canyons et 3 falaises. Les canyons et les falaises sont **désactivés** (profondeur et hauteur forcées à 0). Le masque `relief_mask` exclut la zone de la base et du front.
- **Projection** : le plan (x, z) est enroulé sur la sphère. La fonction clé est **`gp(x, z, lift)`**, qui renvoie la position 3D d'un point au sol (+ hauteur). Le centre de l'astéroïde est en `(0, -RC, 0)`, et la base est au pôle `(0, 0, 0)`.
  - `hdisp(x,z)` : petit relief issu de `height.bin` (2 échelles, `TILE=512`, `BIG=5.7`), très atténué pour le style cartoon.
  - `alt(P)` : altitude d'un point 3D au-dessus du sol ; `up_at(P)` : verticale locale ; `planar(P)` : retour en (x, z).
  - `los_hit(a,b)` : ligne de vue, bloquée par le relief et les rochers (`cover_near`).
  - **Ces calculs doivent rester identiques à ceux de `terrain.gdshader`**, sinon les objets flottent ou s'enfoncent.

### Construction (`_ready`)
1. Tirage de la taille, de la forme et du relief (`dice.randomize()` : **différent à chaque lancement**). `rng.seed = 7` sert au ciel.
2. Ajout de deux vues absolues calculées : « Vue stratégique » (insérée en 1re position) et « L'astéroïde entier » (en dernier).
3. Chargement de `terrain/*.bin` et création de la caméra (fov 50, far 40 000).
4. `build_pipeline()` : la scène est rendue dans un **SubViewport**, puis affichée dans un TextureRect avec le **shader `post`** (filtre de style), plus une étiquette de vue.
5. `build_sky()` : panorama étoilé généré, environnement ACES + glow, soleil directionnel avec ombres sur 2 cascades (320 m), lumière de « Terre » et planète de fond (sphère de 1400 m, shader `planet`).
6. `build_terrain()` : **un seul PlaneMesh** de côté `TAU×RC×1.02` (400 à 800 subdivisions), enroulé par le shader. Pas d'ombre portée du sol.
7. `build_base()` : la base minière, au pôle :
   - `hub_and_dish` : moyeu, pylône en treillis et parabole.
   - `pipes` : 4 tubes pressurisés avec modules et passerelles, plus 3 modules terminaux.
   - `geodome` : dôme géodésique en icosphère de fréquence 3.
   - `habitats`.
   - `pads` : pas de tir et fusées (`rockets`, états `sol` / `decollage` / `feu`).
   - `solar` ×2 : champs de panneaux solaires.
   - `shipyard` : chantier naval.
   - `excavator` ×4, avec poussière.
   - `roads`, `convoy`.
   - `rocks` : rochers, qui servent aussi de **couverture** pour la bataille (grille `bgrid`, `BCELL=8`).
   - Chaque bâtiment est redressé selon la verticale locale, puis **réduit de moitié** (`BSC = 0.5`, la base entière est ramenée vers son centre).
   - `peaks()` : massifs en dalles inclinées (MultiMesh) et `tufts()` : touffes de cristaux (MultiMesh). Ils sont placés hors de la base, du front et du lobe, sans chevauchement.
8. `battle.gd` est instancié (`war.setup(self)`), puis `build_hud()`, puis `apply_view(0)`.

### Matériaux
`M(nom)` met en cache des StandardMaterial3D : `acier`, `acier_sombre`, `blanc`, `gris`, `beton`, `noir`, `or`, `orange`, `rouille`, `solaire`, `verre`, et des émissifs `vitre`, `chaud`, `bleu`, `rouge`, `anneau`. Primitives utilitaires : `box`, `cyl`, `sph`, `strut`, `tube_x/z`, `lamp`, `beacon` (clignote), `dust`.

### Points de vue (`VUES`, touches 1 à 8)
1 Vue stratégique (calculée) · 2 Ligne de front · 3 Vue tactique · 4 La base · 5 Le dôme · 6 Pas de tir (une fusée décolle) · 7 Côté pirates · 8 L'astéroïde entier (calculée).
Chaque vue définit `cam`, `look` (en coordonnées planes, sauf `abs`), l'élévation et l'azimut du soleil (`el`, `az`), la direction de la Terre, l'état des fusées (`fus`), le mode de filtre (`mode`, 12 par défaut) et la teinte du terrain (`tint`). Le brouillard (`fog`) est optionnel.

### Commandes (`_input`)
1 à 8 : vues · clic gauche : tourner · clic droit ou molette enfoncée : déplacer · molette : zoom (3 m à 60 km) · H ou Origine : recadrer · Espace : pause · + / − : vitesse ×0,25 à ×8 · S : filtre suivant (13 modes) · F : plein écran · Échap : quitter. La caméra ne descend jamais sous 1,2 m au-dessus du sol.
*(Le README d'origine mentionnait un double-clic pour centrer, mais il n'est pas implémenté dans `_input`.)*

### Boucle (`_process`)
Simulation à pas fixe ≤ 0,05 s × `tscale` (`war.step`), puis rendu `war.render(dt)`, HUD toutes les 0,4 s, balises qui clignotent et panaches des fusées.

### Mode captures automatiques
`Godot --path . -- --shots <dossier>` : vitesse ×4, attente de 45 s de simulation, puis capture de chaque vue en `k240_jeu_NN.png` et arrêt du jeu. C'est ce qui a produit `images/`.

### HUD (`build_hud` / `update_hud`)
Panneaux façon bande dessinée (`bd_panel`, `bd_label`) : statistiques de la bataille et effectifs, via `war.stats()`.

### Code mort
Nettoyé le 2026-11-14 :
- dans `main.gd`, l'ancienne bataille statique (`battle`, `tank`, `explosion`, `soldiers`, `tracer_line`, `team_mat`) et `tube_z` ;
- dans `battle.gd`, `turret_aa` et les variables `A`, `ARC`, `unit_mesh`.

Les en-têtes des deux fichiers ont été corrigés.

Restent volontairement, car ce sont des réglages désactivés et non du code mort :
- les canyons et falaises de `make_relief`, de profondeur et hauteur 0, calculés aussi dans `terrain.gdshader` ;
- la branche `LOBE_FUSED`.

Les supprimer demande de modifier le shader en même temps.

## 4. `battle.gd` — la bataille

- **Échelle réelle** : soldat 1,85 m, robot 2,4 m, char environ 9 m.
- **Front** : arc de grand cercle entre `BATTLE_A = (20,0,175)` (côté base) et `BATTLE_B = (20,0,515)` (côté pirates), 3 couloirs (`LANES = -48, 0, 48` m). La position le long du front s'exprime par `s ∈ [0,1]` ; voir `frame(s, lane)` et `ground(p)`.
- **Formations** (`KIND`) ; une unité est une formation :

| Type | Effectif | PV/membre | Vitesse | Portée | Notes |
|---|---|---|---|---|---|
| `rifle` fusiliers | 60 | 10 | 2,2 | 110 m | |
| `flame` lance-flammes | 24 | 14 | 2,3 | 28 m | gros dégâts à courte portée |
| `robot` robots de soutien | 12 | 90 | 1,8 | 120 m | |
| `tank` chars | 4 | 500 | 3,0 | 220 m | obus (`shell`) |

  `MULT[attaquant][cible]` donne l'efficacité contre chaque type : par exemple fusiliers ×0,03 contre les chars, chars ×1 contre les robots. Les valeurs de `KIND` font foi.
- **Apparition** : au plus 9 formations par camp. La probabilité d'apparition est biaisée par la position du front, ce qui rééquilibre la bataille. `mix()` tire le type. Une **vague** passe toutes les 60 s (`wave`).
- **IA d'une formation** : ciblage de l'ennemi le plus proche dans sa portée (toutes les 0,5 s), **ligne de vue réelle** (`los_frac`, à travers le relief et les rochers), et 3 états : `march` (avance), `crawl` (rampe, s'il y a un danger ou une cible sans ligne de vue) et `fight` (tire). Les membres s'écartent les uns des autres (`separate`), et les pertes se font une par une (`kill_one`, `damage`), avec démembrement (`dismember`).
- **Effets** : traceurs avec ricochets, obus, explosions (`boom`), fumée (`puff`, `tank_smoke`), sprites lumineux et épaves (`WR`).
- **Aviation** (`air`) : chasseurs des deux camps en orbite au-dessus du front (`FT`, `add_fighter`, `fpos`), et tourelles anti-aériennes (`TUR`).
- **Rendu** : modèles « cuits » en code (`b_begin`, `bx`, `cy`, `sp`, `b_end` → ArrayMesh), dessinés en **MultiMesh**. Les soldats ont 4 poses de marche + 1 pose arrêtée, plus une pose couchée (`prone`). Modèles : `trooper`, `robot`, `tank_hull/turret/barrel`, `fighter`, `turret_aa`.
- **Interface avec `main.gd`** : `setup(world)` (garde la référence `w` pour utiliser `gp`, `alt`, `up_at`, `cover_near`…), `step(dt)`, `render(dt)`, `stats()`, `time`.

## 5. Conventions et précautions
- Tout est généré en code : ne pas chercher de scènes ou de ressources `.tres`.
- Toute modification de la forme ou de la hauteur du sol doit être faite **à la fois** dans `main.gd` (`hdisp`, `gp`, `shape_raw`, `relief_m`…) et dans `shaders/terrain.gdshader`.
- **Garder l'éditeur Godot fermé pendant que Claude modifie les fichiers** (consigne du LISEZ-MOI d'origine), sinon l'éditeur risque d'écraser les changements.
- Pour vérifier qu'un script se charge sans erreur, sans fenêtre : `Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit` (la version console est dans `F:\Projet-K240\Godot\`).

## 5 bis. Build
- **`build.ps1`** (PowerShell 5.1 compatible, messages sans accents pour éviter les problèmes d'encodage) ; **`build.bat`** (cmd) et **`build.sh`** (bash) l'appellent avec `-ExecutionPolicy Bypass` et lui transmettent les arguments.
- L'utilisateur travaille souvent dans un terminal **MSYS2 UCRT64 (bash)** : lui donner les commandes en syntaxe bash (`./build.sh ...`), pas `.\build.ps1`.
- Paramètres : `-Platform windows|linux|all` (par défaut windows), `-DebugBuild`, `-InstallTemplates`, `-NoZip`, `-Check`, `-Clean`, `-Godot <exe>`.
- Étapes : recherche de Godot (`-Godot`, `$env:GODOT`, `.\Godot\`, `F:\Projet-K240\Godot\`, PATH), lecture de la version (`--version` → `4.7.2.stable`), `--headless --import` (crée `.godot/`), vérification des modèles d'export dans `%APPDATA%\Godot\export_templates\4.7.2.stable\` (téléchargement GitHub `.tpz` si `-InstallTemplates`), `--export-release|--export-debug "<preset>" build\<plateforme>\...`, puis zip dans `dist\K240-<config/version>-<plateforme>.zip`.
- `export_presets.cfg` : `embed_pck=true` (un seul exécutable), `include_filter="terrain/*.bin"` (**indispensable** : ces fichiers sont lus par `FileAccess` et non importés comme ressources), `exclude_filter` = images, build, dist, Godot, tools.
- Version du jeu : `config/version` dans `project.godot` (0.1.0 au départ).
- Après l'export Windows, le script **lance l'exécutable produit** (`--headless --quit-after 120`) et échoue en cas d'erreur.
- **Piège connu** : `application/modify_resources=true` (écriture de l'icône et des infos de version dans l'exe) produisait un exe **invalide** (« n'est pas une application Win32 valide »), sans pack de données intégré. Ce réglage est donc à `false`. Pour ajouter une icône plus tard, il faudra tester à nouveau.
- État au 2026-11-14 : modèles d'export 4.7.2 installés dans `%APPDATA%\Godot\export_templates\4.7.2.stable\`. Build Windows release **testé de bout en bout** : `build\windows\K240.exe` (≈ 112 Mo, pack intégré), qui démarre sans erreur, et `dist\K240-0.1.0-windows.zip` (≈ 42 Mo). Le preset Linux n'a pas été testé.

## 6. Historique et origine
- Le projet a été développé côté **Claude Desktop** dans `F:\Projet-K240` (sans git) : jeu `K240-jeu` + prototypes `K240-v2` (petite planète, style Planetary Annihilation), `K240-coupe` (vue en coupe cartoon), `K240-base` (base réaliste, 10 vues), `K240-styles` (10 styles graphiques), `K240-Godot` (1re version). Le moteur s'y trouve aussi : `F:\Projet-K240\Godot\Godot_v4.7.2-stable_win64.exe` (+ `_console.exe`).
- Avant Godot, une série de prototypes HTML/three.js existait sous forme d'artefacts claude.ai (galerie de l'utilisateur : « K-240 Remake », jeu de gestion complet ; « Front de surface », « Assaut », « Bataille », « en coupe », « 16 bits », « cartoon », « Constructions », « Organigramme »). Ils ont été **retirés du dépôt** le 2026-11-14 et existent toujours sur claude.ai. Le Remake contient un gamedata riche (27 bâtiments, ressources, technologies, flottes) qui peut servir de référence pour la suite du jeu Godot.
- 2026-11-14 : le dépôt ne contient plus que le jeu Godot (copie de `F:\Projet-K240\K240-jeu` faite vers 11 h). Si l'utilisateur modifie encore `F:\Projet-K240`, il faut recopier ou fixer une source unique.

## 7. Environnement de travail
- Windows 11 ; dépôt `f:\fGitHub\Kuiper-Dawn` ; branche de travail **`dev`**, branche principale **`main`**.
- `git` n'est pas dans le PATH de PowerShell mais il est installé : `& "C:\Program Files\Git\cmd\git.exe"`. Ne commiter que sur demande.
- PowerShell 5.1 affiche mal l'UTF-8 (mojibake) : les fichiers sont corrects, c'est seulement l'affichage.
- L'utilisateur écrit en français : lui répondre en français.
