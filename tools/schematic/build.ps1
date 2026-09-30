# Rebuilds archive/pc/mod/MechsOfNightCity.archive: the HUD damage schematic.
#
# The Minotaur's meshes are exported from the game, rendered as a front-view wireframe
# (one white layer per part, hidden lines removed, the back pods ghosted), packed into
# one 1024x1024 atlas with an inkatlas naming the parts, and packed into the archive.
# Needs Python 3 (standard library only) and the WolvenKit CLI 8.17 with an
# appsettings.json that turns mesh materials off and imports UI textures uncompressed:
#   "XbmImportArgs": { "TextureGroup": "TEXG_Generic_UI", "IsGamma": false, "GenerateMipMaps": false,
#                      "IsStreamable": false, "Compression": "TCM_None", "RawFormat": "TRF_TrueColor" },
#   "MeshExportArgs": { "withMaterials": false, "isGLBinary": true, "LodFilter": true }
# If the part offsets change, update CMPilotHud.BuildParts from work\raw\layout.reds.txt.
param(
  [Parameter(Mandatory = $true)][string]$WolvenKit,   # WolvenKit.CLI.exe
  [Parameter(Mandatory = $true)][string]$Game,        # the Cyberpunk 2077 folder
  [Parameter(Mandatory = $true)][string]$Work,        # an empty scratch folder
  [string]$Python = "python"
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$content = Join-Path $Game "archive\pc\content"
New-Item -ItemType Directory -Force $Work | Out-Null

# 1. the meshes, and the game's turret HUD atlas as the inkatlas template
& $WolvenKit extract $content -o (Join-Path $Work "src") -r "mch_003__minotaur\\entities\\meshes\\mch_003__minotaur_(arm_l|arm_r|hands|legs|weapons_l|weapons_r|bags|body)_01\.mesh$"
& $WolvenKit extract $content -o (Join-Path $Work "src") -r "turret_hud\\turret_hud\.inkatlas$"
$meshes = Get-ChildItem (Join-Path $Work "src") -Recurse -Filter *.mesh | ForEach-Object FullName
& $WolvenKit export $meshes -o (Join-Path $Work "glb") -gp $Game
& $WolvenKit convert serialize (Get-ChildItem (Join-Path $Work "src") -Recurse -Filter turret_hud.inkatlas | Select-Object -First 1).FullName -o (Join-Path $Work "ref")

# 2. the layers (the sensor is the top of the body mesh)
$env:H = '768'; $env:ANG = '50'; $env:LW = '2.2'; $env:FILL = '0.16'; $env:SENSOR = '(-0.32, 0.32, 2.30, 9.0)'
& $Python (Join-Path $here "render.py") (Join-Path $Work "glb") (Join-Path $Work "parts") parts
& $Python (Join-Path $here "render.py") (Join-Path $Work "glb") (Join-Path $Work "parts") preview

# 3. atlas + inkatlas, then redengine files, then the archive
& $Python (Join-Path $here "pack.py") (Join-Path $Work "parts") (Join-Path $Work "ref\turret_hud.inkatlas.json") (Join-Path $Work "raw") "mnc/hud/minotaur_schematic"
$pack = Join-Path $Work "pack\MechsOfNightCity\mnc\hud"
New-Item -ItemType Directory -Force $pack | Out-Null
& $WolvenKit import (Join-Path $Work "raw\mnc\hud\minotaur_schematic.png") -o $pack
& $WolvenKit convert deserialize (Join-Path $Work "raw\mnc\hud\minotaur_schematic.inkatlas.json") -o $pack
& $WolvenKit pack (Join-Path $Work "pack\MechsOfNightCity") -o (Join-Path $Work "out")
Copy-Item (Join-Path $Work "out\MechsOfNightCity.archive") (Join-Path $here "..\..\archive\pc\mod\MechsOfNightCity.archive") -Force
Write-Host "archive rebuilt; preview at $(Join-Path $Work 'parts\preview.png')"
