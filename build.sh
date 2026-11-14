#!/usr/bin/env bash
# Build du jeu K-240 depuis bash (Git Bash, MSYS2...) : relaie vers build.ps1 avec les memes arguments.
# Exemple : ./build.sh -InstallTemplates   |   ./build.sh -Platform all
cd "$(dirname "$0")" || exit 1
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 "$@"
