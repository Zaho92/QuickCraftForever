# Copies the addon from this repository into the game's AddOns folder, so the installed copy is never
# the working copy. Run it from anywhere:  pwsh tools/install.ps1
param(
    [string]$AddOns = 'D:\Games\World of Warcraft\_forever_\Interface\AddOns'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $AddOns 'QuickCraftForever'

if (-not (Test-Path -LiteralPath $AddOns)) {
    throw "AddOns folder not found: $AddOns"
}
if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Path $target | Out-Null
foreach ($file in 'QuickCraftForever.toc', 'QuickCraftForever.lua', 'LICENSE', 'CHANGELOG.md') {
    Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $target
}
foreach ($dir in 'Locales', 'Media') {
    Copy-Item -LiteralPath (Join-Path $repo $dir) -Destination $target -Recurse
}

Write-Host "Installed to $target. Type /reload in the game (a newly added addon needs one restart of the game)."
