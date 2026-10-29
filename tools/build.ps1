# Builds FS25_FarmInventory.zip into "Testing_local" (move it to mods to test).
# Usage (from the project folder):  powershell -ExecutionPolicy Bypass -File tools\build.ps1
# Optional: -ConvertIcon   re-creates icon_farmInventory.dds from icon_farmInventory.png first.
param([switch]$ConvertIcon)
$ErrorActionPreference = 'Stop'

$project = Split-Path $PSScriptRoot -Parent
$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\FarmingSimulator2025\Testing_local\FS25_FarmInventory.zip'
$textureTool = 'C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.14\tools\textureTool.exe'
$files = 'modDesc.xml', 'icon_farmInventory.dds', 'scripts/FarmInventory.lua', 'scripts/SiloLoadFilter.lua', 'translations/l10n_en.xml'

if (Get-Process FarmingSimulator2025Game -ErrorAction SilentlyContinue) {
    throw 'Farming Simulator 25 is running and locks the mod zip. Quit the game first.'
}

if ($ConvertIcon) {
    & $textureTool (Join-Path $project 'icon_farmInventory.png')
    if ($LASTEXITCODE -ne 0) { throw "textureTool failed ($LASTEXITCODE)" }
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path $dest) { Remove-Item $dest -Confirm:$false }
$zip = [System.IO.Compression.ZipFile]::Open($dest, 'Create')
try {
    foreach ($rel in $files) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $project $rel), $rel)
    }
} finally {
    $zip.Dispose()
}
"Built $dest"
