<#
.SYNOPSIS
  Build du jeu K-240 (export Godot) pour Windows et/ou Linux.

.EXAMPLE
  .\build.ps1                      # Windows, release, + archive zip dans dist/
  .\build.ps1 -Platform all        # Windows + Linux
  .\build.ps1 -DebugBuild          # export debug (console, erreurs visibles)
  .\build.ps1 -InstallTemplates    # telecharge les modeles d'export Godot si absents
  .\build.ps1 -Check               # verifie seulement que le projet se charge sans erreur
  .\build.ps1 -Clean               # supprime build/ et dist/
#>
[CmdletBinding()]
param(
    [ValidateSet("windows", "linux", "all")]
    [string]$Platform = "windows",
    [switch]$DebugBuild,
    [switch]$InstallTemplates,
    [switch]$NoZip,
    [switch]$Check,
    [switch]$Clean,
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

function Info($m) { Write-Host "[build] $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "[build] ERREUR : $m" -ForegroundColor Red; exit 1 }

if ($Clean) {
    foreach ($d in "build", "dist") { if (Test-Path "$Root\$d") { Remove-Item "$Root\$d" -Recurse -Force; Info "$d/ supprime" } }
    exit 0
}

# ---------------------------------------------------------------- moteur Godot
# ordre : -Godot, variable GODOT, ./Godot/, F:\Projet-K240\Godot, PATH
function Find-Godot {
    $cands = @()
    if ($Godot) { $cands += $Godot }
    if ($env:GODOT) { $cands += $env:GODOT }
    $cands += Get-ChildItem "$Root\Godot\Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName
    $cands += Get-ChildItem "$Root\Godot\Godot_v*_win64.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName
    $cands += Get-ChildItem "F:\Projet-K240\Godot\Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName
    foreach ($n in "godot", "godot4") { $c = Get-Command $n -ErrorAction SilentlyContinue; if ($c) { $cands += $c.Source } }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path } }
    return $null
}

$GodotExe = Find-Godot
if (-not $GodotExe) { Fail "Godot introuvable. Copiez Godot_v4.7.2-stable_win64(_console).exe dans .\Godot\ ou definissez `$env:GODOT." }

function Run-Godot([string[]]$GArgs) {
    # Start-Process evite que PowerShell 5.1 transforme la sortie d'erreur de Godot en exception
    $p = Start-Process -FilePath $GodotExe -ArgumentList $GArgs -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput "$env:TEMP\k240-godot-out.txt" -RedirectStandardError "$env:TEMP\k240-godot-err.txt"
    $out = (Get-Content "$env:TEMP\k240-godot-out.txt" -Raw) + (Get-Content "$env:TEMP\k240-godot-err.txt" -Raw)
    return @{ Code = $p.ExitCode; Out = $out }
}

$verRaw = (Run-Godot @("--version")).Out.Trim()
if ($verRaw -notmatch '^(\d+\.\d+(\.\d+)?)\.([a-z0-9]+)') { Fail "version de Godot illisible : '$verRaw'" }
$TplName = "$($Matches[1]).$($Matches[3])"        # ex. 4.7.2.stable
$TplTag = "$($Matches[1])-$($Matches[3])"         # ex. 4.7.2-stable
Info "Godot : $GodotExe ($verRaw)"

# version du jeu (project.godot -> config/version)
$GameVer = "0.0.0"
$m = Select-String -Path "$Root\project.godot" -Pattern '^config/version="([^"]+)"'
if ($m) { $GameVer = $m.Matches[0].Groups[1].Value }

# ---------------------------------------------------------------- import des ressources (cree .godot/)
Info "Import des ressources..."
$r = Run-Godot @("--headless", "--path", "`"$Root`"", "--import")
if ($r.Out -match "SCRIPT ERROR|Parse Error|Failed to load script") { Write-Host $r.Out; Fail "erreur de script pendant l'import" }

if ($Check) {
    Info "Verification : lancement de 120 images sans fenetre..."
    $r = Run-Godot @("--headless", "--path", "`"$Root`"", "--quit-after", "120")
    if ($r.Out -match "SCRIPT ERROR|Parse Error|Failed to load script|Invalid call") { Write-Host $r.Out; Fail "le jeu a signale des erreurs" }
    Info "OK : le projet se charge et tourne sans erreur de script."
    exit 0
}

# ---------------------------------------------------------------- modeles d'export
$TplDir = Join-Path $env:APPDATA "Godot\export_templates\$TplName"
$need = @()
if ($Platform -in "windows", "all") { $need += "windows_release_x86_64.exe", "windows_debug_x86_64.exe" }
if ($Platform -in "linux", "all") { $need += "linux_release.x86_64", "linux_debug.x86_64" }
$missing = $need | Where-Object { -not (Test-Path (Join-Path $TplDir $_)) }

if ($missing) {
    if (-not $InstallTemplates) {
        Fail ("modeles d'export Godot $TplName absents ($TplDir).`n" +
              "         Relancez avec -InstallTemplates (telechargement ~1 Go)`n" +
              "         ou installez-les depuis l'editeur : Editeur > Gerer les modeles d'export.")
    }
    $url = "https://github.com/godotengine/godot/releases/download/$TplTag/Godot_v${TplTag}_export_templates.tpz"
    $tmp = Join-Path $env:TEMP "godot_templates_$TplTag.zip"
    Info "Telechargement des modeles : $url"
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    $ext = Join-Path $env:TEMP "godot_templates_$TplTag"
    if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
    Expand-Archive -Path $tmp -DestinationPath $ext
    New-Item -ItemType Directory -Force $TplDir | Out-Null
    Copy-Item "$ext\templates\*" $TplDir -Recurse -Force
    Remove-Item $tmp, $ext -Recurse -Force
    Info "Modeles installes dans $TplDir"
}

# ---------------------------------------------------------------- export
$targets = @()
if ($Platform -in "windows", "all") { $targets += @{ Preset = "Windows"; Dir = "windows"; File = "K240.exe" } }
if ($Platform -in "linux", "all") { $targets += @{ Preset = "Linux"; Dir = "linux"; File = "K240.x86_64" } }
$mode = if ($DebugBuild) { "--export-debug" } else { "--export-release" }
$kind = if ($DebugBuild) { "debug" } else { "release" }

foreach ($t in $targets) {
    $outDir = Join-Path $Root "build\$($t.Dir)"
    # on vide le dossier sans le supprimer (il peut etre ouvert dans un terminal ou l'explorateur)
    New-Item -ItemType Directory -Force $outDir | Out-Null
    Get-ChildItem $outDir -Force | Remove-Item -Recurse -Force
    $outFile = Join-Path $outDir $t.File
    Info "Export $($t.Preset) ($kind) -> build\$($t.Dir)\$($t.File)"
    $r = Run-Godot @("--headless", "--path", "`"$Root`"", $mode, "`"$($t.Preset)`"", "`"$outFile`"")
    if (-not (Test-Path $outFile)) { Write-Host $r.Out; Fail "export $($t.Preset) echoue" }

    # test de l'executable produit (Windows uniquement) : 120 images sans fenetre
    if ($t.Dir -eq "windows") {
        try {
            $p = Start-Process -FilePath $outFile -ArgumentList "--headless", "--quit-after", "120" -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput "$env:TEMP\k240-exe-out.txt" -RedirectStandardError "$env:TEMP\k240-exe-err.txt"
        } catch { Write-Host $r.Out; Fail "l'executable exporte ne demarre pas : $($_.Exception.Message)" }
        $o = (Get-Content "$env:TEMP\k240-exe-out.txt" -Raw) + (Get-Content "$env:TEMP\k240-exe-err.txt" -Raw)
        if ($p.ExitCode -ne 0 -or $o -match "SCRIPT ERROR|Failed to load|Cannot open file|Can't open") { Write-Host $o; Fail "l'executable exporte signale des erreurs" }
        Info "Test de l'executable : OK"
    }

    if (-not $NoZip) {
        New-Item -ItemType Directory -Force "$Root\dist" | Out-Null
        $suffix = if ($DebugBuild) { "-debug" } else { "" }
        $zip = Join-Path $Root "dist\K240-$GameVer-$($t.Dir)$suffix.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -Path "$outDir\*" -DestinationPath $zip
        Info ("Archive : dist\{0} ({1:N1} Mo)" -f (Split-Path $zip -Leaf), ((Get-Item $zip).Length / 1MB))
    }
}
Info "Termine (version $GameVer)."
