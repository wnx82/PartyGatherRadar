<#
.SYNOPSIS
    Empaquette PartyGatherRadar en ZIP prêt à installer (dist\PartyGatherRadar-<version>.zip).

.DESCRIPTION
    - lit la version dans PartyGatherRadar.toc (## Version) ;
    - vérifie que chaque fichier listé dans le TOC existe ;
    - copie uniquement les fichiers utiles au jeu et la documentation (pas Tests, Tools, fichiers Visual Studio) ;
    - crée une archive dont la racine est le dossier PartyGatherRadar\ (chemins avec "/").
    Avec -Install, copie aussi le dossier dans le répertoire AddOns indiqué (remplace l'ancienne version).
    Compatible Windows PowerShell 5.1 et PowerShell 7.

.PARAMETER Install
    Copie l'addon dans -AddOnsPath après l'empaquetage.

.PARAMETER AddOnsPath
    Dossier AddOns de destination (par défaut celui de la bêta WoW Forever).
#>
param(
    [switch]$Install,
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$root = Split-Path -Parent $PSScriptRoot
$addonName = 'PartyGatherRadar'
$tocPath = Join-Path $root "$addonName.toc"

# Version et fichiers du TOC
$tocLines = Get-Content -LiteralPath $tocPath -Encoding UTF8
$versionLine = $tocLines | Where-Object { $_ -match '^##\s*Version:\s*(\S+)' } | Select-Object -First 1
if (-not $versionLine) { throw 'Version introuvable dans le TOC.' }
$version = ([regex]::Match($versionLine, '^##\s*Version:\s*(\S+)')).Groups[1].Value
$tocFiles = $tocLines | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
foreach ($file in $tocFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "Fichier du TOC absent : $file" }
}

# Contenu du paquet
$folders = @('Core', 'Detection', 'Communication', 'Map', 'UI', 'Localization', 'Media')
$documents = @("$addonName.toc", 'README.md', 'CHANGELOG.md', 'TECHNICAL-LIMITATIONS.md', 'LICENSE')

$dist = Join-Path $root 'dist'
$staging = Join-Path $dist 'staging'
$stagedAddon = Join-Path $staging $addonName
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stagedAddon | Out-Null

foreach ($document in $documents) {
    $source = Join-Path $root $document
    if (-not (Test-Path -LiteralPath $source)) { throw "Fichier requis absent : $document" }
    Copy-Item -LiteralPath $source -Destination $stagedAddon
}
foreach ($folder in $folders) {
    $source = Join-Path $root $folder
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $stagedAddon -Recurse
    }
}

# Archive (System.IO.Compression : séparateurs "/" quelle que soit la version de PowerShell)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $dist "$addonName-$version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $prefixLength = $staging.Length + 1
    Get-ChildItem -LiteralPath $stagedAddon -Recurse -File | Sort-Object FullName | ForEach-Object {
        $entryName = $_.FullName.Substring($prefixLength).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

$count = (Get-ChildItem -LiteralPath $stagedAddon -Recurse -File).Count
Write-Host "Paquet créé : $zipPath ($count fichiers, version $version)"

if ($Install) {
    if (-not (Test-Path -LiteralPath $AddOnsPath)) { throw "Dossier AddOns introuvable : $AddOnsPath" }
    $target = Join-Path $AddOnsPath $addonName
    if (Test-Path -LiteralPath $target) {
        # un lien (jonction ou lien symbolique vers l'espace de travail) ne doit jamais être vidé récursivement
        if ((Get-Item -LiteralPath $target -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "$target est un lien : installation annulée pour ne pas toucher à sa cible."
        }
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    Copy-Item -LiteralPath $stagedAddon -Destination $AddOnsPath -Recurse
    Write-Host "Addon installé dans : $target (faire /reload ou relancer le jeu)"
}

Remove-Item -LiteralPath $staging -Recurse -Force
