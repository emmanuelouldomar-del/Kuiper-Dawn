# Agent.md — contexte du projet Kuiper Dawn (K-240)

Fichier de contexte pour les agents (Claude Code) qui travaillent sur ce dépôt. À relire en début de session et à tenir à jour. `CLAUDE.md` l'importe automatiquement (`@Agent.md`).

## 1. Le projet en bref

- **Jeu Godot 4.7.2** (GDScript), renderer **GL Compatibility**, fenêtre 1600×900, plafonné à 60 images/s.
- **Univers** : la colonie minière **K-240**, un astéroïde de la ceinture de Kuiper, et sa guerre contre les **pirates de Kronos**. Le jeu actuel montre une **bataille de surface sans fin** entre la colonie (camp `"b"`, vert/bleu) et les pirates (camp `"r"`, rouge), au pied de la base minière, sur un astéroïde sphérique.
- **Style visé** : minimaliste et géométrique, « façon Monument Valley ». Le nom interne est « K-240 Front de surface (BD) » : interface façon bande dessinée, massifs rocheux en dalles orange/rose/violet, touffes de cristaux bleu-vert.
- **Langue** : tout est en **français** (commentaires, interface, noms de variables comme `VUES`, `gp`, `surf_eval`, `soldiers`). Garder le français.
- **Ce n'est pas encore un jeu jouable** : c'est une simulation qu'on regarde. Le joueur ne donne pas d'ordres ; la caméra est libre et on peut changer de vue, de vitesse et de filtre.

## 2. Structure du dépôt

```
project.godot          config (nom, main_scene, GL Compatibility, 1600x900, ombres 2048)
main.tscn              scène minimale : un Node3D "Jeu" avec main.gd (tout est construit en code)
main.gd    (~2050 l.)  monde : surface de l'astéroïde, maillage cube-sphère, ciel, base, décor, caméra, vues, post-traitement, HUD
battle.gd  (~1460 l.)  simulation de bataille : formations, tirs, effets, aviation, rendu instancié
shaders/
  terrain.gdshader     roche grise de l'astéroïde pailletée d'orange et de rouge (couleur + éclairage en aplats ; AUCUN calcul de relief)
  toon.gdshader        décor (rochers, cailloux à facettes) : couleur de sommet + éclairage en aplats
  post.gdshader        filtre de style plein écran (13 modes, touche S)
  planet.gdshader      planète de fond (la « Terre »)
  plume.gdshader       panache des fusées
images/                captures des vues (k240_jeu_*, k240_grand_*, k240_petit_*, k240_mini_*, k240_style_*) ; non utilisées par le code
Lancer le jeu.bat      lance Godot\Godot_v4.7.2-stable_win64.exe --path .
Ouvrir dans Godot.bat  idem avec -e (éditeur)
Godot/                 (non versionné, .gitignore) : y copier l'exe Godot 4.7.2 pour que les .bat marchent
build.ps1 / build.bat  système de build (export Godot), voir §5 bis
export_presets.cfg     presets d'export « Windows » et « Linux »
build/, dist/          sorties du build (non versionnées)
```

## 3. `main.gd` — le monde

### L'astéroïde façon Planetary Annihilation (refonte du 2026-11-14)
- 1 unité = 1 m. Le front de bataille fait `FRONT_LEN = 340` m. Le centre de l'astéroïde est en `(0, -RC, 0)`, et la base est au pôle `(0, 0, 0)`.
- **Taille aléatoire à chaque partie** : `TAILLE_K ∈ [1.2, 3.0]`, `RC = TAILLE_K × FRONT_LEN × 0.5`, soit un rayon d'environ 200 à 510 m.
- **Forme d'un astéroïde réel** (`make_shape`, table `MODELES`), tirée au hasard. On garde les proportions réelles et la taille du jeu :

  | Modèle | Forme | Densité |
  |---|---|---|
  | Bennu | toupie : double cône arrondi + bourrelet équatorial, la base est posée sur le bourrelet | 1,19 |
  | Itokawa | cacahuète bilobée | 1,90 |
  | Arrokoth | bilobé aplati, ceinture de Kuiper | 0,24 |
  | Éros | allongé | 2,67 |
  | Kléopâtre | os | 3,40 |
  | Psyché | patate | 3,90 |

  - Repère du corps : `SH_ROT` (la base est sur +Y du monde). La forme est calculée par `shape_raw` (ellipsoïde `SH_ELL` ou superellipsoïde pour la toupie, plus 16 bosses `SH_BLOBS`).
  - Second lobe : un **corps séparé** (`LOBE_FUSED = false`), ellipsoïde `SH_LOBE_ELL × SH_LOBE_R`, maillé autour de son propre centre (`lobe_eval`, `lobe_center` tient compte de `SH_ROT`). Un lobe soudé dans le maillage principal donnait des mailles étirées et striées.
  - **Raccord doux entre les lobes** (2026-11-14) : chaque corps est maillé sur l'**union douce** des deux formes (`smin_k`, largeur `neck_k()` = 0,45 × rayon du lobe). `neck_solve` cherche par dichotomie, le long de chaque rayon, le point où l'union douce s'annule ; il est appelé par `radius_at` (corps principal) et `lobe_shape_r` / `lobe_eval` (lobe). Les distances approchées sont `main_sd` / `lobe_sd`, calculées sur les formes brutes `radius_raw` / `lobe_raw`. Dans le congé, dunes et cratères sont atténués (`neck_w`). Sans cela, la jonction était une arête franche.
  - Option de lancement `--forme <nom>` (ex. `cacahuete`, `arrokoth`, `os`, `toupie`, `eros`, `patate`, ou début du nom affiché) : impose la forme, utile pour les captures.
  - Seule une petite calotte autour de la base reste sphérique (`SH_TH0 = 170/RC`, limité à 0,25–0,75 rad, raccord sur 0,45 rad). Partout ailleurs, la forme reçoit de **grosses bosses irrégulières** (`NZ_LUMP`, bruit 3D sur la direction, fréquence 0,95, amplitude `LUMP_A` = 20 %), le lobe aussi : la silhouette n'est jamais une ellipsoïde parfaite (demande de l'utilisateur du 2026-11-14). Psyché suit ses vraies proportions (1 : 0,83 : 0,68).
- **Gravité réelle** (`make_gravity`, `grav_at`, `grav_up`) : volume de la forme par Monte-Carlo (plus le lobe) × densité → masse, puis g = G·M/r² vers le **centre de masse** `AST_COM` (centroïde de la forme, `3/4 · Σ r⁴ d / Σ r³`, combiné avec le lobe), qui est le point d'attraction (demande de l'utilisateur). Ordres de grandeur : 0,02 à 2 mm/s², vitesse de libération de 0,1 à 1,7 m/s. Affichées dans le panneau (densité, gravité, libération).
  - Débris (`deb`) et morceaux (`part`) de `battle.gd` utilisent `w.grav_at()` : en microgravité, les débris rapides partent dans l'espace.
  - **Unités soumises à la gravité** (2026-11-14) : debout, à genoux ou en marche, fantassins et robots sont droits selon `grav_up` (vers le centre de masse), pas selon la pente (`F.mg`, avec un petit relèvement `F.mgo` = pente × demi-pied pour ne pas enfoncer les pieds côté montée). Couchés (pose 8), corps et chars restent à plat sur le sol (`F.mb`, `tank_pose`). Elles restent posées au sol par le jeu : marcher à 2 m/s dépasse la vitesse de libération.
- **Zones aplanies** (`add_flat_zone`, `flatten`, appelé dans `surf_eval`), façon PA : le sol est aplani à la hauteur exacte de la base d'un objet fixe, avec un raccord doux (de 1 à 1,8 fois le rayon). Elles sont enregistrées pour les bâtiments à socle (après `settle`) et pour les 2 tourelles anti-aériennes (`battle.setup`, tourelles droites selon la verticale locale).
  - **Ordre de `_ready`** : `build_base()` → `war.setup()` → `build_terrain()`. Le maillage est construit en dernier pour intégrer les zones.
- **Pente des falaises** : `UV2.y = 1 − normale · normale de la forme lisse` (calculée dans `_face_task` avec `radius_at` / `lobe_shape_r`). Une forme allongée n'est donc pas coloriée en falaise. `UV` vaut 1e6 loin de la base (aucun chemin là-bas).
- **Relief** (`make_relief`), ajouté à la forme :
  - **dunes** : `NZ_DUNE`, bruit 3D, presque plates dans la base et le couloir ;
  - **cratères cellulaires** : bruit cellulaire `NZ_CD/NZ_CV` (cellule de 70 m) et `NZ_CD2/NZ_CV2` (22 m). Un germe par cellule, dont la taille et la présence sont tirées par cellule ; fonction `cell_crater` ;
  - **« brosses »** façon PA, posées hors de la base et du couloir : `BR_CRATER` (7 cratères géants avec rebord), `BR_MESA` (plateaux à falaises raides, bord irrégulier via `NZ_EDGE`), `BR_RIDGE` (4 crêtes). Elles sont stockées dans `BR_*`, avec un rejet rapide par `BR_COS`.
  - Le masque `relief_mask(x, z)` (1 loin de la base, 0 dans la base et le couloir) atténue cratères et brosses.
- **Source unique de vérité : `surf_eval(dir) -> Vector3(rayon, ombrage_cratère, masque)`**. Tout en dépend :
  - `gp(x, z, lift)` : point au sol à partir des coordonnées à plat (projection azimutale équidistante autour de la base) ;
  - `surf_point(dir)` : point au sol dans une direction ;
  - `alt(P)` : altitude d'un point 3D ; `up_at(P)` : verticale locale = normale de la forme lisse (`radius_at`, sans relief) ; radiale dans la calotte de la base, perpendiculaire au sol ailleurs, même sur une forme allongée ; `planar(P)` / `planar_of(dir)` : retour en (x, z) ;
  - `los_hit(a, b)` : ligne de vue, bloquée par le relief et les rochers (`cover_near`) ;
  - le maillage du sol (cube-sphère).

  Il n'y a **plus de calcul en double dans un shader** : le sol affiché et les collisions coïncident exactement, à la précision du maillage près (environ 4 m).
- **Maillage cube-sphère** (`build_terrain`, `planet_mesh`, `_face_task`) : un cube « sphérifié » (`cube_dir`) de 6 faces × `N`² mailles, avec `N = π/2·RC/4` limité à 80–190. Les faces sont calculées **en parallèle** (`WorkerThreadPool`, 6 tâches), avec une bordure d'un sommet pour des normales continues entre faces.
  - Attributs : `UV` = coordonnées à plat (m), 1e6 loin de la base ; `UV2.x` = ombrage des cratères ; `UV2.y` = pente du relief seul.
  - Triangles en sens horaire vu de l'extérieur (faces avant pour Godot).
- **Shader du sol `terrain.gdshader`** (roche grise façon PA ; avant le 2026-11-14 c'était un désert orangé, abandonné à la demande de l'utilisateur) :
  - plusieurs nuances de gris (plaques foncées, gris chaud, gris froid), fonds de cratère sombres et rebords clairs, zones de régolithe clair ;
  - **paillettes orange et rouges** (demande du 2026-11-14 : « léger brossage rouge et orange, comme pailleté, pas trop flash ») : éclats de 16 cm sur une grille 3D (`hash3`, hachage sans sinus), 0,6 à 3,5 % des cellules selon des plaques de bruit, opacité 0,6, émission 0,06 ; léger voile rouille (6 %). De loin, quand un éclat est plus petit qu'un pixel, il est remplacé par sa teinte moyenne (pas de scintillement). Historique : grandes veines de 8 m, puis 0,8 m, puis réseau de fissures (Voronoï), tout retiré au profit des paillettes.
  - chemins de la base en régolithe clair et du front (anneau r = 128 m, chemin sinueux vers les pirates), petits cailloux ;
  - **falaises en roche gris sombre à strates** selon la pente ;
  - éclairage en 3 aplats (`light()`), avec bruit projeté sur 3 axes depuis `float_noise_tex` (texture flottante raccordable : une texture 8 bits faisait des bords en escalier).
- **Calibrage des couleurs** : les teintes sont données directement en linéaire, avec un gris de base autour de (0,148 ; 0,150 ; 0,156), des paillettes orange (0,62 ; 0,16 ; 0,02) et rouges (0,45 ; 0,03 ; 0,015). Garder l'émission faible : avec le halo (glow), elle vire au jaune. La lumière en aplats utilise `LIGHT_COLOR * ATTENUATION * b / PI`. Pour le décor (`toon.gdshader`), les couleurs de sommet sont en sRGB et converties avec `pow(…, 2.2)`.
- **Zoom continu façon PA** (`_input`, molette) : en s'éloignant, le pivot glisse vers le centre de l'astéroïde, et la caméra tourne alors autour. En se rapprochant depuis l'orbite, le pivot revient sur la surface visée.
- **Caméra sans roulis** (`update_cam`, `leveled`, `cam_up`, `cam_level_w`) : près du sol, l'horizon est remis à niveau à chaque image selon `up_at(target)` ; la rotation (clic gauche) tourne autour de la verticale locale, avec une inclinaison bornée ; le déplacement (clic droit) fait glisser le pivot sur la surface et la caméra suit la courbure. En orbite (pivot près du centre), la rotation est libre. Avant (2026-11-14), la rotation se faisait autour de l'axe Y du monde : loin de la base, l'horizon penchait et les unités paraissaient de travers.

### Construction (`_ready`)
1. Tirage de la taille, de la forme et du relief (`dice.randomize()` : **différent à chaque lancement**). `rng.seed = 7` sert au ciel.
2. Ajout de deux vues absolues calculées : « Vue stratégique » (insérée en 1re position) et « L'astéroïde entier » (en dernier).
3. Création de la caméra (fov 50, far 40 000).
4. `build_pipeline()` : la scène est rendue dans un **SubViewport**, puis affichée dans un TextureRect avec le **shader `post`** (filtre de style), plus une étiquette de vue.
5. `build_sky()` : panorama étoilé généré, environnement ACES + glow, soleil directionnel avec ombres sur 2 cascades (320 m), lumière de « Terre » et planète de fond (sphère de 1400 m, shader `planet`). **Lumière d'appoint** `fill_light` (bleutée, énergie 1,4, sans ombre), orientée à l'opposé du soleil et décalée de côté (`apply_view`) : le relief reste lisible du côté nuit tout en restant nettement plus sombre. Attention : le filtre 12 remplace les pixels presque noirs (luminance < 0,035) par le dégradé du fond, une face trop sombre « disparaît » donc dans le ciel.
6. `build_terrain()` : le maillage cube-sphère (et celui du lobe éventuel), avec le shader du désert. Pas d'ombre portée du sol. Prend environ 1 s.
7. `build_base()` : la base, au pôle, **de style militaire** (refaite le 2026-11-14 d'après deux images de soldats en combinaison : kaki olive, plaques blindées, visières dorées, tuyaux annelés, feux rouges). Tous les anciens bâtiments (moyeu à parabole, tubes pressurisés, dôme de verre, habitats blancs, fusées, chantier naval, excavatrices, convoi) ont été supprimés :
   - `command_post` : poste de commandement, bunker octogonal à flancs blindés inclinés (`armor_plate`), fentes et coupole-visière dorées, mât, petit radar, porte blindée, tuyaux (`hose`).
   - `corridor` ×4 : couloirs blindés en tronçons de 2 m (kaki, bande orange, câble sur le toit, cadres tous les 4 tronçons, sas à visières).
   - `reactor` : réacteur à ailettes et cœur orange lumineux (matériau `noyau`), en bout du couloir est.
   - `tank_farm` : 3 réservoirs sphériques en cage (`fuel_tank`), reliés par des tuyaux, en bout du couloir ouest.
   - `barracks` ×5 : casernes, modules cylindriques couchés sur berceau blindé, bandes de visières, reliées par des tuyaux (`link` en `tuyau`).
   - `greenhouse` : serre en dôme géodésique (icosphère de fréquence 3) à vitres dorées (`visiere_verre`) et armature kaki, bacs de culture sous lampes.
   - `radar_tower` : tour radar à huit pans, plate-forme vitrée, antenne inclinée.
   - `pads` : 3 aires hexagonales à chevrons orange, avec une navette de débarquement chacune (`rocket` : coque kaki trapue, cockpit-visière, 4 réacteurs et pieds ; états `sol` / `decollage` / `feu`, panache inchangé).
   - `solar` ×2 : champs de panneaux sur cadres kaki.
   - `hangar` : voûte en arceaux kaki (demi-cylindre en panneaux), porte à chevrons orange ; posé avec `meta "pieds"`.
   - `drill_rig` ×4 : foreuses minières (tour en treillis, tige, trémie, poussière).
   - `roads` : piste circulaire en béton balisée d'orange et de feux rouges.
   - `rocks` : rochers, qui servent aussi de **couverture** pour la bataille (grille `bgrid`, `BCELL=8`).
   - Chaque bâtiment est redressé selon la verticale locale, puis **réduit de moitié** (`BSC = 0.5`, la base entière est ramenée vers son centre).
   - `peaks()` puis `decor()` : le décor du désert, en MultiMesh avec `toon.gdshader`. Il est placé hors de la base, du front et du lobe, sans chevauchement avec les abris de la bataille :
     - rochers « mesas » à facettes (`mesa_mesh`) : flancs gris, épaulement, sommet plat clair, avec ombres portées ;
     - cailloux et blocs gris à facettes (`rock_mesh`, 3 variantes + 1 pour les blocs à ombre portée). Ils remplacent depuis le 2026-11-14 les agaves et les cactus du désert, retirés à la demande de l'utilisateur ;
     - cailloux gris clair et gris foncé, et amas de pierres grises ; les rochers-abris de la bataille (`rocks`) sont gris, 8 % rouillés (zones de graviers).
8. `battle.gd` est instancié (`war.setup(self)`), puis `build_hud()`, puis `apply_view(0)`.

### Collisions avec le sol (ajout du 2026-11-14)
Aucun objet de la base ne doit traverser le terrain. Mécanisme dans `build_base`, en trois temps :
1. **Redressement** : chaque enfant direct de `B` est tourné pour que son axe Y suive la verticale locale (`up_at`). Font exception les pièces marquées `meta "libre"`, déjà orientées : `link`, `walkway`, routes.
2. **Réduction `BSC`**, inchangée.
3. **`settle(B)`** : pour chaque enfant direct, `collect_probes` sonde les maillages solides (anneaux pour cylindres, sphères et tores ; coins et milieux du dessous pour le reste). Si un point est sous le sol (`alt < 0`), l'objet est soulevé le long de la verticale. Ensuite :
   - `meta "socle"` (rayon) : ajoute un socle en béton qui descend jusque sous le point le plus bas du terrain. Utilisé pour le poste de commandement, le réacteur, les réservoirs, les casernes, la serre, la tour radar, les foreuses et les aires d'atterrissage.
   - `meta "pieds"` (liste de points locaux) : ajoute une fondation sous chaque pied. Utilisé pour le hangar.

   Sont ignorés : les MultiMesh, les lumières, les billboards et matériaux transparents ou shader, et les fusées (`meta "fusee"`), recalées ensuite sur leur aire (`r.pad`).

Règles pour tout nouvel élément de la base :
- **Jamais de longue pièce droite entre deux points du sol** : une corde passe sous une sphère. Utiliser `link()` (tube) ou `walkway()` (passerelle), qui découpent en tronçons de 4 m.
- **Les structures longues sont découpées en tronçons**, chacun étant un `Node3D` posé avec `gp()` : c'est le cas des tubes pressurisés, en tronçons de 2 m.
- **Positionner avec `gp(x, z, lift)`**, jamais avec `pos + Vector3(0, h, 0)`, car la verticale du monde n'est pas la verticale locale.

### Matériaux
`M(nom)` met en cache des StandardMaterial3D : `acier`, `acier_sombre`, `blanc`, `gris`, `beton`, `noir`, `or`, `orange`, `rouille`, `solaire`, `verre`, et des émissifs `vitre`, `chaud`, `bleu`, `rouge`, `anneau`. Primitives utilitaires : `box`, `cyl`, `sph`, `strut`, `hose` (tuyau souple), `armor_plate`, `lamp`, `beacon` (clignote), `dust`. Style militaire de la base : `kaki` (3b3b22), `kaki_clair` (57553a), `blinde` (25272a), `orange_mil` (c4600f), `tuyau` (a9a59a), `visiere` (doré, légèrement émissif), `visiere_verre` (doré transparent), `noyau` (orange émissif). Les teintes sont volontairement sombres : avec le soleil (2,4), l'exposition et le filtre 12, des teintes plus claires ressortent crème.

### Points de vue (`VUES`, touches 1 à 8)
1 Vue stratégique (calculée) · 2 Ligne de front · 3 Vue tactique · 4 La base · 5 La serre · 6 Aire d'atterrissage (une navette décolle) · 7 Côté pirates · 8 L'astéroïde entier (calculée).
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
- la branche `LOBE_FUSED`.

## 4. `battle.gd` — la bataille

- **Échelle réelle** : soldat 1,85 m, robot 2,4 m, char environ 9 m.
- **Front** : arc de grand cercle entre `BATTLE_A = (20,0,175)` (côté base) et `BATTLE_B = (20,0,515)` (côté pirates), 3 couloirs (`LANES = -48, 0, 48` m). La position le long du front s'exprime par `s ∈ [0,1]` ; voir `frame(s, lane)` et `ground(p)`.
- **Formations** (`KIND`) ; une unité est une formation :

| Type | Effectif | PV/membre | Vitesse | Portée | Notes |
|---|---|---|---|---|---|
| `rifle` fusiliers | 30 | 10 | 2,2 | 110 m | |
| `flame` lance-flammes | 12 | 14 | 2,3 | 28 m | gros dégâts à courte portée |
| `robot` robots de soutien | 6 | 90 | 1,8 | 120 m | |
| `tank` chars | 2 | 500 | 3,0 | 220 m | obus (`shell`) |
  Effectifs divisés par deux le 2026-11-14 (avant : 60, 24, 12, 4).

  `MULT[attaquant][cible]` donne l'efficacité contre chaque type : par exemple fusiliers ×0,03 contre les chars, chars ×1 contre les robots. Les valeurs de `KIND` font foi.
- **Apparition** : au plus 9 formations par camp. La probabilité d'apparition est biaisée par la position du front, ce qui rééquilibre la bataille. `mix()` tire le type. Une **vague** passe toutes les 60 s (`wave`).
- **IA d'une formation** : ciblage de l'ennemi le plus proche dans sa portée (toutes les 0,5 s), **ligne de vue réelle** (`los_frac`, à travers le relief et les rochers), et 3 états : `march` (avance), `crawl` (rampe, s'il y a un danger ou une cible sans ligne de vue) et `fight` (tire). Les membres s'écartent les uns des autres (`separate`), et les pertes se font une par une (`kill_one`, `damage`), avec démembrement (`dismember`).
- **Effets** : traceurs avec ricochets, obus, explosions (`boom`), fumée (`puff`, `tank_smoke`), sprites lumineux et épaves (`WR`).
- **Aviation** (`air`) : chasseurs des deux camps en orbite au-dessus du front (`FT`, `add_fighter`, `fpos`), et tourelles anti-aériennes (`TUR`).
- **Rendu** : modèles « cuits » en code (`b_begin`, `bx`, `cy`, `sp`, `b_end` → ArrayMesh), dessinés en **MultiMesh**. Les soldats ont 4 poses de marche + 1 pose arrêtée, plus une pose couchée (`prone`). Modèles : `trooper`, `robot`, `tank_hull/turret/barrel`, `fighter`, `turret_aa`.
- **Contact au sol** (2026-11-14) :
  - `frame()` utilise la verticale locale (`w.up_at`), jamais `Vector3.UP` ;
  - `ground(p)` projette radialement sur la surface (`w.surf_point`) ;
  - chaque char est posé par `tank_pose()` : il sonde le sol sous les 4 extrémités de ses chenilles (`TRACK_HL` = 4,2 m, `TRACK_HW` = 2,15 m), s'oriente sur ce plan, se relève si une bosse centrale le traverse, et lisse sa bascule par slerp (`t.q`).
  - fantassins et robots : à chaque `recompute()` (tous les 1,5 m de déplacement), chaque membre est reposé sur le sol réel et orienté par `ground_frame()`, qui sonde le sol sous la tête, les pieds et les côtés. Le résultat est stocké dans `F.mb[i]` et utilisé au rendu à la place de l'orientation commune de la formation. Les corps (`DEAD`) sont posés de la même façon.
  - Vérification sans fenêtre : `Godot --headless --path . -- --verif-chars` affiche l'écart min/max au sol des chenilles, des fantassins (tête et pieds) et des corps. Mesuré : chars −0,10 à +0,23 m, fantassins −0,17 à +0,17 m. Elle affiche aussi `VERIF ANGLE`, l'angle entre l'axe Y des unités et la normale réelle du sol (`ground_normal`) : moyenne 0,1 à 0,4°, max 1 à 13° selon la forme.
- **Interface avec `main.gd`** : `setup(world)` (garde la référence `w` pour utiliser `gp`, `alt`, `up_at`, `cover_near`…), `step(dt)`, `render(dt)`, `stats()`, `time`.

## 5. Conventions et précautions
- Tout est généré en code : ne pas chercher de scènes ou de ressources `.tres`.
- Toute modification de la forme ou de la hauteur du sol se fait **uniquement dans `surf_eval()`** (et `lobe_eval()` pour le lobe). Le shader du sol ne fait que la couleur.
- `surf_eval` est appelé depuis plusieurs threads (génération du maillage) : il doit rester **sans effet de bord**, en lecture seule sur les données.
- Pour vérifier un changement visuel : `Godot --path . -- --shots <dossier>` produit les captures des 8 vues en 15 s environ.
- **Garder l'éditeur Godot fermé pendant que Claude modifie les fichiers** (consigne du LISEZ-MOI d'origine), sinon l'éditeur risque d'écraser les changements.
- Pour vérifier qu'un script se charge sans erreur, sans fenêtre : `Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit` (la version console est dans `F:\Projet-K240\Godot\`).

## 5 bis. Build
- **`build.ps1`** (PowerShell 5.1 compatible, messages sans accents pour éviter les problèmes d'encodage) ; **`build.bat`** (cmd) et **`build.sh`** (bash) l'appellent avec `-ExecutionPolicy Bypass` et lui transmettent les arguments.
- L'utilisateur travaille souvent dans un terminal **MSYS2 UCRT64 (bash)** : lui donner les commandes en syntaxe bash (`./build.sh ...`), pas `.\build.ps1`.
- Paramètres : `-Platform windows|linux|all` (par défaut windows), `-DebugBuild`, `-InstallTemplates`, `-NoZip`, `-Check`, `-Clean`, `-Godot <exe>`.
- Étapes : recherche de Godot (`-Godot`, `$env:GODOT`, `.\Godot\`, `F:\Projet-K240\Godot\`, PATH), lecture de la version (`--version` → `4.7.2.stable`), `--headless --import` (crée `.godot/`), vérification des modèles d'export dans `%APPDATA%\Godot\export_templates\4.7.2.stable\` (téléchargement GitHub `.tpz` si `-InstallTemplates`), `--export-release|--export-debug "<preset>" build\<plateforme>\...`, puis zip dans `dist\K240-<config/version>-<plateforme>.zip`.
- `export_presets.cfg` : `embed_pck=true` (un seul exécutable), `exclude_filter` = images, build, dist, Godot, tools. Si un jour le jeu lit des fichiers non importés (via `FileAccess`), il faudra les ajouter à `include_filter`.
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

## 8. Règles de jeu (2026-11-14, demandées par l'utilisateur)
- **Centre de commandement** (`command_post`) : activé au début de la partie, il gère la colonie et a sa propre énergie, un **réacteur à hélium-3**.
- **Bouclier** (`build_shield`, `update_shield`, `shaders/shield.gdshader`) : dôme de 110 m (`SHD_R`) centré sur le centre de commandement. Il monte depuis le sol en 4 s au démarrage. **Seules les troupes au sol le franchissent.**
  - Tirs et obus venant de l'extérieur s'y écrasent : `shield_clip` dans `tracer()` et `shell()` de `battle.gd`, avec un éclair et un anneau d'impact (`shield_hit`, 8 impacts dans l'uniforme `hits`). Les tirs partant de l'intérieur sortent librement.
  - Les chasseurs pirates sont repoussés à sa surface (`shield_push`).
  - Énergie `SHD_E` (%) : coût de 0,08 par balle et de 1,2 par obus ; le réacteur recharge 2,5 %/s. À 0, le bouclier s'effondre 12 s (`SHD_DOWN`).
  - HUD : CENTRE CMD., RÉACTEUR He-3, BOUCLIER, NAVETTES PIRATES (en vol / abattues).
- **Défenseurs (colonie)** : ils déploient leurs unités depuis **2 hangars** (`hangar(B, c, yaw)`, `meta "hangar"`, portes listées dans `HANGARS`).
  - Une formation de renfort sort de la porte la plus proche et marche jusqu'à son couloir : état de transit `F.tr`, `tr_frame`, sans combattre, en formation resserrée.
  - Les chasseurs de la colonie décollent d'un hangar (`f.l`, `f.door`).
- **Attaquants (pirates)** : aucune apparition directe. Leurs renforts arrivent **uniquement par vaisseaux de débarquement** (`request_drop`, `DS`, au plus 3 en vol).
  - Les vaisseaux sont très fragiles (4 PV). Ils se posent au bout du front (s = 0,88 à 0,98), **à l'opposé de la zone défendue**, en arrivant du côté opposé à la base.
  - Ils débarquent une formation (`spawn(side, kind, s, lane)`), puis repartent.
  - Abattus avant le débarquement (`ds_destroyed`), ils perdent toute la formation à bord, comptée dans les pertes pirates.
  - Tourelles et chasseurs de la colonie les visent en priorité.

## 9. Surface industrielle et spatioport (2026-11-14, fusion avec le remake K-240)
- Source : gamedata du remake (artefact claude.ai « K-240 Remake », bâtiments `zone:"ext"`). **En surface : uniquement l'industrie polluante et dangereuse pour la population, l'extraction et le stockage.** Le jeu souterrain (habitats, casernes, salles) est mis de côté pour l'instant. Casernes, serre, anciennes aires de navettes et panneaux solaires ont été retirés de la surface.
- Bâtiments (`main.gd`, coordonnées avant la réduction BSC) :
  - `refinery` (raffinerie) : hauts fourneaux, 3 cheminées fumantes, cuves.
  - `fission_smr` (réacteur à fission SMR) : à l'écart, enceinte de confinement, tours de refroidissement à vapeur, clôture de zone interdite et panneau radioactif.
  - `mass_driver` (catapulte électromagnétique) : rampe inclinée de 90 m à bobines, posée sur `meta "pieds"`.
  - `storage_silos` : 4 silos reliés par convoyeur. `tank_farm` (réservoirs) reste pour l'Hélium-3.
  - `drill_rig` (foreuses thermiques) et `reactor` (fusion He-3, alimente le bouclier) restent.
  - **Moissonneuses-racleuses** (`harvester_mesh`) : 5 engins mobiles qui tournent sur des boucles autour de la base, en coordonnées planes du monde (`harvesters`, `update_harvesters`), avec poussière. Elles ne sont pas enfants de `B` (pas de `settle`).
- **Pollution** : `smoke_stack` crée des bouffées animées (`plumes`, `update_plumes`) qui montent et grossissent : fumée brune sur les cheminées, vapeur blanche sur les tours du SMR.
- **Spatioport** (`spaceport(B, Vector2(0, -175))`, du côté opposé au front), d'après l'image « Orion Military Depot » de l'utilisateur :
  - tarmac en dalles de 10 m posées sur la sphère ;
  - terminal de 112 m à 4 portes de hangar à chevrons, enseigne et tuyauteries (`meta "pieds"`) ;
  - tour de contrôle à cabine octogonale aux vitres vertes, antennes et feux ;
  - 3 plateformes octogonales surélevées, chacune avec un transport anguleux (`shuttle` : verrière rouge et verte, ailerons, réacteurs, panache de décollage) ;
  - passerelle surélevée, 2 grues à tour (`tower_crane`), 2 paraboles (`dish_tower`), conteneurs et un véhicule.
  - Les transports remplacent les anciennes fusées dans `rockets` (`pad_off`, `yaw`) ; la vue 6 « Spatioport » en fait décoller un.
- Matériaux ajoutés : `gris_dep`, `tarmac`, `tarmac2`, `danger` (jaune), `vert` et `rouge_vitre` (émissifs). Utilitaire `hazard_x` (bande jaune et noire).
- Vues : 5 « Zone industrielle », 6 « Spatioport » ; la vue 4 a été déplacée (elle était dans un hangar).

## 10. Passerelle de commandement et économie (2026-11-14, fusion avec le jeu du remake)
- **La partie se lance sur la passerelle**, plusieurs écrans comme dans le remake (`bridge.gd`, `CanvasLayer` de couche 0 sous la vue 3D) :
  - **à gauche, GESTION**, avec 3 onglets :
    - Colonie : 10 ressources avec stock, capacité et débit, énergie, bouclier, population sous terre, moral, pollution, curseur d'impôts ;
    - Construire : bâtiments de surface, avec coût, effets et raison s'ils sont indisponibles ;
    - Recherche : les technologies.
  - **au centre, la vue principale 3D**, entre l'en-tête « VUE PRINCIPALE · nom » et une rangée de boutons de vue 1 à 8.
    - `main.layout_screen()` place `screen_tex` (le TextureRect du filtre de style) dans `bridge.screen_rect()` et redimensionne `sv` à cette taille.
    - La souris ne pilote la caméra que sur cet écran (garde au début de `_input`).
  - **à droite, RADAR TACTIQUE** : vue de dessus, le front vers le haut, portée 560 m, avec balayage. On y voit le bouclier, les hangars, les moissonneuses, les formations (vert : colonie, rouge : pirates), les chasseurs et les navettes (triangles). En dessous : CONTACTS (navettes et leur phase, formations pirates, chasseurs) et EFFECTIFS AU SOL.
  - **en bas, la console** : les 4 derniers messages, la vitesse (pause, ×1 à ×8) et le bouton « Vue 3D plein écran ».
  - **Tab** bascule entre la passerelle et la vue 3D plein écran, où l'ancien HUD BD (`hud_root`, `style_lbl`) réapparaît.
  - En mode captures (`--shots`), la passerelle est masquée, sauf avec `--passerelle`.
- **Économie** (`colony.gd`, gamedata du remake adapté à la surface) :
  - Ressources : régolithe, fer-nickel, crédits, glace, Hélium-3, gaz rares, volatils, métaux précieux, combustible nucléaire, terres rares.
  - Bâtiments `BLD` : moissonneuse, foreuse, raffinerie, SMR, fusion, catapulte, silo, réservoir, spatioport, radar. Chacun a coût, temps, énergie, `produces` / `consumes` (par seconde), `storage` et `pollution`.
  - Simulation dans `step(dt)`, appelée avec `war.step` dans `_process` (temps de jeu) : bilan d'énergie et efficacité `eff` (le générateur du bouclier consomme 10), production limitée par les intrants et le stockage, états `ok` / `energie` / `intrants` / `plein`.
  - Population sous terre (logement fixe de 400) ; moral = 70 − impôts × 1,5 − pollution × 0,9 − 20 en cas de déficit d'énergie − 10 si le bouclier est effondré ; impôts → crédits.
  - **Construction** : `build(t)` paie et pose un échafaudage (`main.scaffold`) sur le premier emplacement libre de `SLOTS` (8 emplacements, coordonnées avant BSC). À la fin, `main.construct(t, slot)` construit le vrai modèle 3D, posé par `place_new` (redressement, BSC, `settle_node`).
    - La moissonneuse est mobile : `main.add_harvester()` ajoute un engin sur un nouveau champ (`HARV_FIELDS`).
    - Limite : les zones aplanies du terrain ne sont pas recalculées pour un bâtiment construit en jeu (le socle comble le vide).
  - **Recherche** `TECH` (menée au centre de commandement, vitesse × `eff`) : Fours à 800 °C, Métallurgie, Forage profond, Filtres anti-pollution, Fusion, Catapulte, Bouclier renforcé (`shield_factor()` multiplie la recharge du bouclier).
- Voir la section 11 pour la couche stratégique (flottes, carte, Kronos, pilote automatique).

## 11. Couche stratégique du remake v50 (2026-11-14) : `strategy.gd`
Portage du jeu complet du remake (artefact « K-240 Remake » version 50), adapté au jeu Godot.
- **Recherche en organigramme** (onglet Recherche, `bridge.draw_rtree`) : les technologies partent du centre de commandement, par profondeur de prérequis, avec des courbes de liaison.
  - États par couleur : acquise (vert), en cours (ambre, barre de progression), disponible (cyan, cliquable), trop chère, verrouillée (gris).
  - Chaque case indique ce que la recherche débloque.
  - Recherches ajoutées : Balistique (chasseur), Propulsion ionique (corvette), Satellites espions.
- **Usine spatiale** (au spatioport, onglet Flottes) : éclaireur, chasseur et corvette (`UNITS`, coûts et caractéristiques du remake). Les vaisseaux terminés vont au **hangar**.
- **Flottes** (`fleet_new/add/rem/del`, `fleet_order`) : seuls les vaisseaux en flotte reçoivent des ordres.
  - Ordres : défendre K-240 (patrouille ; chaque vaisseau en patrouille ajoute un chasseur de la colonie en vol dans la bataille 3D, 10 au plus), intercepter une flotte pirate, coloniser un astéroïde neutre (un vaisseau y reste en station), attaquer Kronos, rentrer à la base.
  - Combat par rounds (`mk` / `fight`, PV = 4 × blindage), comme le remake.
  - Décollages et retours : une navette du spatioport décolle ou se pose (`main.launch_fx` / `land_fx`).
- **Carte stratégique** (bouton « Carte stratégique » de l'écran principal, `bridge.draw_map`) : K-240, Alpha (+2 régolithe/s), Beta (+0,6 fer/s), Gamma (+1 crédit/s) et Kronos, avec flottes, raids et satellites en mouvement. Clic sur un astéroïde : informations.
- **IA de Kronos** (`E`, `en_think`, `en_launch`) : mines, laboratoire, recherches, chantier naval, tourelles (2 au départ), file de vaisseaux.
  - Raids lancés quand sa flotte dépasse le seuil `5 + 5 × attaques`, jamais avant 7 min (`EGRACE`).
  - Le raid fait un **siège** de 45 s : `main.siege_begin` fait tourner des vaisseaux pirates autour du bouclier, qui le pilonnent. `raid_sim` oppose la flotte pirate aux flottes en patrouille et aux **tourelles canon** (nouveau bâtiment `tourelle`, modèle `defense_turret`).
  - Si le bouclier cède :
    - jusqu'à 3 bâtiments sont détruits (`main.destroy_buildings` : bâtiments construits en jeu ou moissonneuses) ;
    - le bouclier tombe ;
    - **blocus** : les crédits d'exportation et de colonies sont coupés ;
    - **invasion** : barges pirates près de la base (`invasion_fx`) ; `inv_sim` compte les tourelles, la population, les soldats de la colonie au front et la milice souterraine.
    - Une invasion réussie fait perdre la partie.
- **Satellites espions** (onglet Rens., depuis le spatioport) : transit, puis 240 s d'observation de Kronos (ressources, bâtiments, flotte, recherches, menace, journal).
- **Fin de partie** : victoire si Kronos est conquis (les pirates n'envoient plus de renforts : `war.kronos_dead`) ; défaite si l'invasion atteint le centre de commandement. Les panneaux sont dans `bridge.show_end`, et « Nouvelle partie » recharge la scène.
- **Pilote automatique** (bouton « PILOTE AUTO » de la console, `bot_step` toutes les 2 s de jeu), avec ces priorités :
  1. une flotte « Défense » en patrouille ;
  2. face à une menace, des tourelles, des vaisseaux et une interception si elle est favorable ;
  3. les recherches dans l'ordre `RESO` ;
  4. l'énergie (il économise le fer s'il en manque) ;
  5. des raffineries quand le fer manque, puis des silos et des moissonneuses ;
  6. l'usine (des éclaireurs pour coloniser, puis des corvettes et des chasseurs) ;
  7. la colonisation des astéroïdes neutres ;
  8. un satellite espion ;
  9. l'assaut sur Kronos, seulement après observation par satellite et avec une flotte 1,8 fois plus forte.
- **Test sans fenêtre** : `Godot --headless --path . -- --autopilote` fait jouer le pilote à ×8 et affiche un rapport chaque minute de jeu, jusqu'à la victoire, la défaite ou 60 min.
  - Dernier résultat : colonisation d'Alpha, Beta et Gamma vers 4 min, toutes les recherches vers 8 min, raid repoussé, **victoire à 12 min**.
  - Kronos est donc probablement trop faible face à un joueur efficace : équilibrage à revoir.
- Pas encore portés : concepteur de vaisseaux (modules), avant-postes miniers sur les petits astéroïdes du radar, écran de communication avec l'équipage et voix, sauvegarde et chargement.

## 12. Poste de pilotage et répartition des écrans (2026-11-14)
D'après l'image de référence de l'utilisateur (cockpit avec moniteurs, accoudoirs-consoles, boule de commande).
- **Décor** (`bridge.gd`) :
  - salle sombre avec câbles qui pendent et bras articulés (`draw_room`) ;
  - chaque écran dans un **moniteur à cadre épais** (`bezel`, halo cyan, voyant vert, marque « K-240 · SYS ») avec des coins cyan (`draw_corners`) ;
  - **pupitre** en bas (`draw_desk`) : accoudoirs, clavier, boule de commande.
- **Chaque écran a son rôle** (demande de l'utilisateur : « la construction n'était pas sur le bon écran ») :
  - gauche, **GESTION DE LA COLONIE** : onglets Colonie (ressources, énergie, bouclier, population, moral, pollution, impôts) et Recherche (organigramme) ;
  - centre, **VUE PRINCIPALE** :
    - la vue de l'astéroïde avec, à sa gauche, le panneau **CONSTRUIRE EN SURFACE** (`build_side`, `SIDE_W` = 250) : on construit là où l'on voit les bâtiments ;
    - ou la carte stratégique (le panneau Construire est alors masqué) ;
    - les boutons de vue 1 à 8 en bas ;
  - droite en haut, **RADAR TACTIQUE** : radar, contacts et effectifs (côte à côte quand l'écran est agrandi) ;
  - droite en bas, **COMMANDEMENT SPATIAL** : onglets Usine (spatioport), Flottes et Renseignement (satellites, rapports de combat) ;
  - pupitre :
    - accoudoir gauche : boutons physiques de vitesse et « VUE 3D SEULE (Tab) » ;
    - centre : écran de messages vert ;
    - accoudoir droit : gros bouton ambre « PILOTE AUTO » et son intention.
- **Écran agrandi** :
  - un clic sur un écran latéral (calque `catcher`, curseur main) le déploie en plein écran avec une animation de 0,32 s (`focus_screen`, `animate_focus`, `fz_t`) ; les autres s'assombrissent (`dim`) ;
  - l'écran principal se déploie avec son bouton ⛶, car le clic dans la vue pilote la caméra ;
  - le bouton « ✕ RÉDUIRE L'ÉCRAN », la touche Échap ou un clic sur le fond assombri le ramènent.
  - Une fois agrandi, l'écran est utilisable normalement. La vue 3D (`screen_tex`, au-dessus de la passerelle) est cachée quand un autre écran est agrandi ou quand la carte est affichée (`main.layout_screen`).

## 13. Cockpit en 3D (2026-11-14) : `cockpit.gd`
Reconstruction fidèle de l'image de référence de l'utilisateur. Elle remplace le décor 2D de la section 12, mais la répartition des écrans reste la même.
- **Monde 3D séparé** (`cv`, SubViewport `own_world_3d`, à la taille de la fenêtre), affiché en fond de la passerelle (`bridge.setup`, TextureRect `view`). Il contient :
  - une salle sombre : baies informatiques constellées de voyants (MultiMesh), plafond, câbles en chaînette ;
  - un éclairage cyan au centre, magenta à droite, vert à gauche ; tonemap linéaire, halo, brouillard léger ;
  - une caméra au siège qui suit légèrement la souris (`update`).
- **8 moniteurs en arc** (`MON` : angle, hauteur, distance, taille, pixels/m, couleur du halo), chacun avec cadre, bras mécanique (au plafond ou au bureau), câble, voyant et lumière :
  - `center` : VUE PRINCIPALE ; `left` : GESTION DE LA COLONIE ; `right` (en haut à droite) : RADAR TACTIQUE ; `right2` : COMMANDEMENT SPATIAL ;
  - moniteurs secondaires dessinés en direct (`bridge.draw_deco`) : `sys` (jauges des systèmes), `lefttop` (flux de données), `energy` (énergie et bouclier), `alert` (alertes de la station, clignotantes en cas de menace).
  - Chaque écran est rendu dans un SubViewport (taille = largeur × pixels/m) appliqué sur un QuadMesh `unshaded`, sans brouillard (`disable_fog`). Une émission ou le tonemap ACES délavaient les écrans.
- **Bureau** avec deux claviers, souris, outils, boîtier lumineux ; **jambes du pilote** et assise.
- **Accoudoirs-consoles** :
  - gauche : boule de commande, boutons de vitesse (II, ×1, ×2, ×4, ×8, magenta) et bouton « 3D » (Tab), plus un petit écran incliné MESSAGES ;
  - droite : gros bouton ambre PILOTE AUTO, voyants animés et petit écran PILOTE AUTOMATIQUE.
  - Les boutons s'allument selon l'état (`set_lit`).
- **Interaction** (`bridge.pick_input`) :
  - un calque transparent `picker` lance un rayon (`cockpit.pick`, test rayon-quad pour les moniteurs, rayon-boîte pour les boutons) ; le curseur devient une main au survol.
  - Clic sur un moniteur de jeu : l'écran est sorti de son SubViewport (`reparent` vers `overlay`) et s'anime du rectangle projeté du moniteur (`project_rect`) au plein écran, le cockpit s'assombrit.
  - Échap, le bouton Réduire ou un clic sur le fond : retour animé dans le moniteur.
  - La caméra du jeu ne réagit à la souris que lorsque l'écran principal est agrandi (`bridge.screen_rect` vide sinon).
  - La vue 3D du jeu (`screen_tex`) est un enfant de l'écran principal (`main.layout_screen`, `screen_rect_local`) ; en mode Tab, elle revient dans son CanvasLayer (`screen_layer`).
- **Pièges rencontrés** :
  - sous un CanvasLayer, la passerelle avait une taille nulle : il faut lui donner explicitement la taille de la fenêtre ;
  - le balancement de la caméra divisait par cette taille nulle (NaN, erreurs « det == 0 », cockpit noir) ;
  - les écrans placés dans un SubViewport doivent recevoir une taille explicite.
- Performance : 60 images/s mesurées en fenêtre (RTX 3060) avec tous les SubViewport actifs.

## 14. Diplomatie, superviseurs, opérations spéciales (2026-11-14) : `factions.gd`
Mécaniques inspirées des jeux de gestion d'astéroïdes des années 90 (diplomatie, gérants, espionnage, astéroïde-bélier), proposées par l'utilisateur. **Factions, noms et univers sont originaux** : ne pas reprendre les races, noms ou contenus de jeux existants.
- **5 factions extraterrestres** (`FAC`, placées sur la carte stratégique en losanges colorés), chacune avec une personnalité :
  - marchands vashri : bons prix, offres de lots ;
  - savants ollen : vendent un bonus de recherche (+50 % pendant 90 s) ; avec un accord et une relation d'au moins 30, ils partagent leurs observations de Kronos, comme un satellite (`ollen_intel`, intégré à `strategy.sat_on`) ;
  - clans kethar : exigent des tributs ; un refus ou un délai dépassé coûte −25 de relation, et une guerre se déclare sous −40 ; ils ne s'allient qu'à un joueur puissant ;
  - Silencieux : relation qui revient vers 0, alliance à 85 ;
  - essaim myrr : se rapproche du plus fort ; sous −30, ils ravitaillent Kronos.
- **Actions** : cadeau (50 crédits) et traités.
  - Accord commercial (relation ≥ 20) : +0,75 crédit/s et accès au marché.
  - Pacte de non-agression (≥ 35) : plus de tributs.
  - Alliance (≥ 60) : des chasseurs alliés rejoignent la défense de K-240 pendant un siège (`allied_ships`, dans `raid_sim`).
  - Guerre : raids de chasseurs via `emoves` avec la clé `fac` ; leurs survivants ne rejoignent pas la flotte de Kronos.
  - Paix contre réparations (150 crédits) ; marché d'achat et de vente par lots (`MARKET`, prix selon la faction et le traité) ; réponse aux exigences et aux offres.
- **Superviseurs** (onglet Superviseurs de l'écran de gestion) :
  - par colonie (120 crédits, salaire 0,2 crédit/s) : revenus ×1,5, puis ×2 et ×2,5 (un niveau toutes les 2 min) ;
  - **superviseur industriel** de K-240 (0,5 crédit/s) : gère automatiquement l'énergie, les raffineries, les silos et les moissonneuses (`industrial_step`).
- **Sabotage** (onglet Renseignement) : 80 crédits et 10 métaux précieux, satellite actif requis. Réussite de 80 % moins 8 % par tourelle de Kronos.
  - Effets : une mine détruite, un vaisseau à quai détruit ou le chantier paralysé, pas d'attaque pendant 2 min 30, ou 80 crédits volés.
  - En cas d'échec, Kronos attaque plus tôt.
- **Astéroïde-bélier** (onglet Opérations, recherche « Propulseurs d'astéroïde » après Propulsion ionique) : 300 fer, 120 He-3, 200 crédits.
  - Une colonie fonce sur Kronos ; elle est visible sur la carte avec sa traînée, et la colonie est perdue.
  - La flotte de Kronos peut la dévier (jusqu'à 60 % selon sa puissance).
  - Impact : tourelles rasées, mines et flotte réduites de moitié, coffres vidés, pas d'attaque pendant 4 min.
- **Interface** : le moniteur en haut à gauche du cockpit (`lefttop`) est devenu l'écran **DIPLOMATIE** (cliquable), à la place du « flux de données » décoratif.
- **Pilote automatique** : il verse les tributs, signe les accords commerciaux possibles et nomme des superviseurs.
- Test `--autopilote` : un raid kethar repoussé, victoire à 11 min.

## 15. Survie à 40 UA, la Terre et le vaisseau-arche (2026-11-15) : `survival.gd`
Les motivations et les défis réels de la colonisation de la ceinture de Kuiper, transformés en mécaniques (texte fourni par l'utilisateur).
- **Santé de la population** (0–100, onglet Survie de l'écran de gestion) :
  - elle baisse avec les radiations : fond cosmique, plus des **tempêtes de rayons cosmiques galactiques** toutes les 4 à 6 min pendant 40 s. Le dôme du centre de commandement absorbe 40 % pendant une tempête ;
  - elle baisse aussi avec la microgravité, sauf avec la recherche **Anneau centrifuge**, et avec les pénuries d'eau ou de volatils : la population consomme de la glace (eau, oxygène) et des volatils (agriculture). **Recyclage à 99,9 %** réduit ces besoins de 90 % ;
  - elle remonte sans pénurie ni tempête.
  - Effets : moral −0,3 par point de santé manquant ; pas de croissance sous 45 de santé ; déclin sous 30.
  - Recherches de protection : **Blindage à l'eau** (radiations −60 %, consomme 0,3 glace/s), **Bouclier magnétique** (−70 %).
- **Sol glacé** : toutes les 2 min, la chaleur d'un SMR, d'une centrale à fusion ou d'une raffinerie peut faire fondre la glace sous ses fondations. Ce risque est plus élevé sur un astéroïde peu dense (`w.SH_RHO` < 1500).
  - Le bâtiment s'arrête 60 s (`x.halt` dans `colony.gd`, état « affaissement », plus d'énergie ni de production).
  - **Fondations cryogéniques** divisent le risque par 10 ; le pilote les recherche en premier sur un astéroïde glacé.
- **Tas de gravats** : au-delà de 6 engins de minage (astéroïde glacé) ou 10, un séisme peut engloutir une moissonneuse (`destroy_buildings(1, "moissonneuse")`). **Ancrage par harpons** réduit ce risque de 80 %.
- **Science** (bâtiments, `research` dans `BLD`, `colony.research_mult()`) :
  - **centre de calcul cryogénique** (recherche « Calcul cryogénique ») : +50 % ;
  - **observatoire profond** : +25 % ;
  - **forage des archives** : +15 %, plus des découvertes ponctuelles (+10 % de la recherche en cours, environ une par minute).
  - Modèles 3D : `cryo_center`, `observatory`, `ice_core_drill`.
- **La Terre** (onglet Terre) :
  - ses contrats arrivent avec une latence affichée de 4 à 7 heures-lumière (au jeu : 1 à 2 min de transit) ;
  - il faut livrer une ressource sous 5 min, par la catapulte ou le spatioport, contre une prime ; un contrat expiré fait baisser la réputation ;
  - à partir d'une réputation de 3, un convoi de ravitaillement arrive toutes les 5 min (combustible et métaux précieux).
- **Vaisseau-arche** (seconde victoire, onglet Opérations du commandement spatial) :
  - recherche **Propulsion à fusion** (après Fusion), puis le **chantier interstellaire** (bâtiment unique, `ark_yard` : portique orange, grue, coque dont la longueur suit l'assemblage via `ark_visual`) ;
  - l'assemblage consomme 2 fer, 0,5 He-3, 1 glace et 0,1 métaux précieux par seconde, pendant environ 10 min à plein régime ;
  - à 100 %, c'est la victoire « vers Alpha du Centaure » (`strategy.win_kind = "arche"`, texte dans `bridge.show_end`).
- **Pilote automatique** : il ajuste les impôts selon le moral (4 % sous 35, 10 % au-dessus de 55), recherche les fondations sur un astéroïde glacé, livre les contrats terriens et construit l'observatoire et le centre de calcul.
- **Équilibrage**, après le test `--autopilote` : les affaissements trop fréquents coupaient la centrale à fusion (énergie divisée par 4) et la population s'effondrait, car le seuil de croissance était à 40 de moral.
  - Correctifs : un tirage toutes les 2 min (au lieu de chaque minute), une probabilité de 3,5 % (au lieu de 8 %), et un seuil de croissance abaissé à 30.
  - Résultat : population à 400, santé à 100 %, 3 raids repoussés, victoire à 17 min.
  - Le pilote prend Kronos avant d'aller jusqu'au bout de l'arche : la victoire par l'arche n'a pas été vérifiée en jeu.
