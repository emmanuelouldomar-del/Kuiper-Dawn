# Kuiper Dawn — K-240

Bataille de surface sur l'astéroïde K-240 (ceinture de Kuiper), entre la colonie minière et les pirates de Kronos. Jeu **Godot 4.7.2** (GDScript, renderer GL Compatibility), au style minimaliste et géométrique.

## Lancer

1. Copiez `Godot_v4.7.2-stable_win64.exe` dans un dossier `Godot/` à la racine (il n'est pas versionné).
2. Double-cliquez sur **`Lancer le jeu.bat`**, ou sur `Ouvrir dans Godot.bat` pour ouvrir l'éditeur.

Vous pouvez aussi utiliser votre propre Godot 4.7 : `godot --path .`

## Build

Le build exporte le jeu en exécutable autonome, avec les données intégrées : il n'y a qu'un seul fichier à distribuer.

### Prérequis

- **Godot 4.7.2**. Le script le cherche dans cet ordre : paramètre `-Godot <chemin>`, variable d'environnement `GODOT`, dossier `Godot/` à la racine, `F:\Projet-K240\Godot\`, puis le `PATH`. De préférence, prenez la version *console* (`Godot_v4.7.2-stable_win64_console.exe`).
- **Modèles d'export Godot 4.7.2**, à installer une seule fois (environ 1 Go), au choix :
  - `.\build.ps1 -InstallTemplates`, qui les télécharge depuis GitHub et les installe dans `%APPDATA%\Godot\export_templates\4.7.2.stable\` ;
  - ou depuis l'éditeur Godot : *Éditeur > Gérer les modèles d'export > Télécharger et installer*.

### Commandes

Double-cliquez sur `build.bat`, ou lancez PowerShell à la racine :

| Commande | Résultat |
|---|---|
| `.\build.ps1` | Windows, release → `build\windows\K240.exe` + `dist\K240-<version>-windows.zip` |
| `.\build.ps1 -Platform linux` | Linux → `build\linux\K240.x86_64` + `dist\K240-<version>-linux.zip` |
| `.\build.ps1 -Platform all` | Windows et Linux |
| `.\build.ps1 -DebugBuild` | Export debug (avec la console de débogage, `K240.console.exe` sous Windows) |
| `.\build.ps1 -NoZip` | Sans l'archive dans `dist\` |
| `.\build.ps1 -Check` | Vérifie seulement que le projet se charge et tourne sans erreur de script (pas besoin des modèles) |
| `.\build.ps1 -Clean` | Supprime `build\` et `dist\` |

Selon le terminal, le script se lance différemment, avec toujours les mêmes arguments :

| Terminal | Commande |
|---|---|
| PowerShell | `.\build.ps1 -Platform all` |
| Invite de commandes (cmd) ou double-clic | `build.bat -Platform all` |
| Bash (Git Bash, MSYS2 UCRT64…) | `./build.sh -Platform all` |

Si PowerShell bloque les scripts, utilisez `build.bat` ou `build.sh`, qui passent `-ExecutionPolicy Bypass`.

### Configuration

- **Version du jeu** : `config/version` dans `project.godot`, reprise dans le nom des archives.
- **Préréglages d'export** : `export_presets.cfg`, avec les presets « Windows » et « Linux » (x86_64, données intégrées à l'exécutable). Les fichiers `terrain/*.bin` sont inclus explicitement, car ce ne sont pas des ressources Godot. `images/` est exclu.
- **Sorties** : `build/` et `dist/` ne sont pas versionnés.

## Commandes du jeu

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
