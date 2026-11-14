@echo off
rem Build du jeu K-240 : voir readme.md (section Build). Les arguments sont transmis a build.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
if errorlevel 1 pause
