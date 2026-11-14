# Kuiper Dawn — K-240

Bataille de surface sur l'astéroïde K-240 (ceinture de Kuiper), entre la colonie minière et les pirates de Kronos. Jeu **Godot 4.7.2** (GDScript, renderer GL Compatibility), au style minimaliste et géométrique.

## Lancer

1. Copiez `Godot_v4.7.2-stable_win64.exe` dans un dossier `Godot/` à la racine (il n'est pas versionné).
2. Double-cliquez sur **`Lancer le jeu.bat`**, ou sur `Ouvrir dans Godot.bat` pour ouvrir l'éditeur.

Vous pouvez aussi utiliser votre propre Godot 4.7 : `godot --path .`

## Commandes

| Touche | Action |
|---|---|
| 1 à 8 | Points de vue (1 = vue stratégique, 8 = astéroïde entier) |
| Clic gauche | Tourner |
| Clic droit ou molette enfoncée | Déplacer |
| Molette | Zoom |
| H | Recadrer |
| + / − | Vitesse |
| Espace | Pause |
| S | Changer de filtre |
| F | Plein écran |
| Échap | Quitter |

## Fichiers

- `main.gd` : le monde (astéroïde à forme aléatoire, terrain, base minière, caméra, vues, filtres, interface)
- `battle.gd` : la simulation de bataille (fusiliers, lance-flammes, robots, chars, chasseurs)
- `shaders/` : terrain, filtre de style, planète, lobe, panaches
- `terrain/` : cartes de hauteur et d'albédo (1024², float32)
- `images/` : captures d'écran

Le détail technique est dans [Agent.md](Agent.md).
