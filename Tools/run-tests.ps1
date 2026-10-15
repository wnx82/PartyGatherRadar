<#
.SYNOPSIS
    Lance les tests hors jeu de PartyGatherRadar (Tests/run.lua).

.DESCRIPTION
    1. Utilise un interpréteur Lua 5.1 ou LuaJIT natif s'il est présent dans le PATH.
    2. Sinon, utilise Python et le paquet « lupa » (Lua 5.1 embarqué) installé dans un
       environnement virtuel local Tools\.venv (créé au premier lancement, accès réseau à PyPI requis).
    Compatible Windows PowerShell 5.1 et PowerShell 7.

.PARAMETER NoBootstrap
    N'installe rien : échoue si aucun interpréteur n'est disponible.
#>
param(
    [switch]$NoBootstrap
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'Tests\run.lua'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$env:PYTHONIOENCODING = 'utf-8'

# 1. Interpréteur natif
foreach ($name in @('lua5.1', 'lua51', 'luajit', 'lua')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $command) { continue }
    if ($name -eq 'lua') {
        $version = (& $command.Source -v 2>&1 | Out-String)
        if ($version -notmatch '5\.1') { continue }
    }
    Write-Host "Interpréteur : $($command.Source)"
    & $command.Source $runner $root
    exit $LASTEXITCODE
}

# 2. Python + lupa dans un environnement virtuel local
$venv = Join-Path $PSScriptRoot '.venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    if ($NoBootstrap) {
        Write-Error 'Aucun Lua 5.1/LuaJIT ni environnement Tools\.venv : tests NON exécutés.'
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $python) {
        Write-Error 'Ni Lua 5.1/LuaJIT ni Python trouvés : tests NON exécutés. Installez Lua 5.1 ou Python 3.'
    }
    Write-Host "Création de l'environnement de test $venv (lupa)..."
    & $python.Source -m venv $venv
    if ($LASTEXITCODE -ne 0) { Write-Error 'Création de Tools\.venv impossible.' }
    & $venvPython -m pip install --disable-pip-version-check --quiet 'lupa>=2.0,<3'
    if ($LASTEXITCODE -ne 0) { Write-Error 'Installation de lupa impossible : tests NON exécutés.' }
}

Write-Host "Interpréteur : Lua 5.1 embarqué (lupa) via $venvPython"
& $venvPython (Join-Path $PSScriptRoot 'run-tests.py') $root
exit $LASTEXITCODE
