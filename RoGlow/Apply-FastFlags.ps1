#Requires -Version 5.1
<#
.SYNOPSIS
    Setzt Roblox-eigene Grafik-FastFlags - der Weg zu besserer Optik OHNE
    DLL-Injection.

.DESCRIPTION
    Roblox liest beim Start eine ClientAppSettings.json aus dem
    ClientSettings-Ordner der jeweiligen Version. Darueber lassen sich interne
    Engine-Schalter setzen, die Roblox selbst benutzt - unter anderem die
    Beleuchtungstechnik, das interne Qualitaetslevel und MSAA.

    Das ist kein Hack und keine Injection: es sind Konfigurationswerte der
    Engine, dieselben, die Bloxstrap ueber seinen FastFlag-Editor schreibt.
    Hyperion blockiert das nicht, weil kein fremder Code geladen wird.

    Optisch ist es weniger spektakulaer als ReShade - kein Bloom, keine
    Reflexionen, keine Farbkorrektur. Was du bekommst: echte Schatten statt
    Voxel-Beleuchtung, hoehere interne Renderqualitaet und Kantenglaettung.
    Dafuer funktioniert es heute.

    FastFlag-Namen sind von Roblox nicht dokumentiert und koennen mit jedem
    Client-Update verschwinden. Unbekannte Flags werden von Roblox ignoriert -
    ein veraltetes Flag macht also nichts kaputt, es tut dann einfach nichts.

.PARAMETER Profile
    Quality   - maximale Optik (Default)
    Balanced  - Future-Lighting + Schatten, aber ohne MSAA
    Remove    - alle von diesem Script gesetzten Flags wieder entfernen

.PARAMETER Bloxstrap
    Schreibt zusaetzlich in Bloxstraps eigene FastFlag-Datei, damit die
    Einstellungen ein Roblox-Update ueberleben.

.PARAMETER Remove
    Kurzform fuer -Profile Remove.

.PARAMETER AllVersions
    In alle gefundenen version-* Ordner schreiben statt nur in den neuesten.

.EXAMPLE
    .\Apply-FastFlags.ps1
.EXAMPLE
    .\Apply-FastFlags.ps1 -Profile Balanced -Bloxstrap
.EXAMPLE
    .\Apply-FastFlags.ps1 -Remove
#>
[CmdletBinding()]
param(
    # Heisst intern FlagProfile, weil $Profile eine automatische PowerShell-
    # Variable ist (Pfad zum Profilskript). Der Alias haelt -Profile nutzbar.
    [Alias('Profile')]
    [ValidateSet('Quality', 'Balanced', 'Remove')]
    [string] $FlagProfile = 'Quality',

    [switch] $Bloxstrap,
    [switch] $Remove,
    [switch] $AllVersions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Remove) { $FlagProfile = 'Remove' }

$Script:ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:SettingsName = 'ClientAppSettings.json'
$Script:BackupSuffix = '.roglow-backup'

function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "        $m" -ForegroundColor Gray }
function Write-Warn2{ param([string]$m) Write-Host "  !  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  X  $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Flag-Profile
#
# Jeder Wert ist als String zu schreiben - Roblox erwartet das so, auch bei
# Zahlen und Booleans.
# ---------------------------------------------------------------------------

# Rendering-API festnageln. Roblox kann D3D11, D3D10-Feature-Level und Vulkan.
# Wenn es auf Vulkan oder FL10 ausweicht, faellt die Bildqualitaet ab - und
# eine dxgi.dll wuerde bei Vulkan ohnehin nie greifen.
$Script:FlagsApi = [ordered]@{
    'FFlagDebugGraphicsPreferD3D11'     = 'True'
    'FFlagDebugGraphicsPreferD3D11FL10' = 'False'
    'FFlagDebugGraphicsPreferVulkan'    = 'False'
}

# Das interne Qualitaetslevel entspricht dem 1-21-Regler im Spiel. 21 ist das
# Maximum und uebersteuert auch das, was der Regler in der Roblox-UI zulaesst.
$Script:FlagsQualityCore = [ordered]@{
    'DFIntDebugFRMQualityLevelOverride'   = '21'
    'FFlagDebugForceFutureIsBrightPhase3' = 'True'
    'FIntRenderShadowIntensity'           = '100'
}

# MSAA. Gueltig sind 0/1/2/4/8; Werte ueber 4 erzeugen bekannte
# Viewport-Fehler, deshalb bleibt es bei 4.
$Script:FlagsMsaa = [ordered]@{
    'FIntDebugForceMSAASamples' = '4'
}

function Get-ProfileFlags {
    param([string] $Name)
    $flags = [ordered]@{}
    foreach ($h in @($Script:FlagsApi, $Script:FlagsQualityCore)) {
        foreach ($k in $h.Keys) { $flags[$k] = $h[$k] }
    }
    if ($Name -eq 'Quality') {
        foreach ($k in $Script:FlagsMsaa.Keys) { $flags[$k] = $Script:FlagsMsaa[$k] }
    }
    return $flags
}

function Get-ManagedFlagNames {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($h in @($Script:FlagsApi, $Script:FlagsQualityCore, $Script:FlagsMsaa)) {
        foreach ($k in $h.Keys) { $names.Add($k) }
    }
    return $names
}

# ---------------------------------------------------------------------------
# Zielordner
# ---------------------------------------------------------------------------

function Get-VersionDirs {
    $dirs = New-Object System.Collections.Generic.List[object]
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Roblox\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Bloxstrap\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Fishstrap\Versions')
    )
    if ($env:ProgramFiles)        { $roots += (Join-Path $env:ProgramFiles 'Roblox\Versions') }
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions') }

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -Filter 'version-*' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'RobloxPlayerBeta.exe') } |
            ForEach-Object { $dirs.Add($_) }
    }
    return @($dirs | Sort-Object -Property LastWriteTimeUtc -Descending)
}

# ---------------------------------------------------------------------------
# Schreiben / Entfernen
# ---------------------------------------------------------------------------

function Read-ExistingFlags {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{} }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
        $obj = $raw | ConvertFrom-Json
        $out = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) { $out[$p.Name] = [string]$p.Value }
        return $out
    } catch {
        Write-Warn2 "Bestehende $Script:SettingsName ist kein gueltiges JSON - wird gesichert und neu angelegt."
        Copy-Item -LiteralPath $Path -Destination "$Path.broken" -Force -ErrorAction SilentlyContinue
        return [ordered]@{}
    }
}

function Save-Flags {
    param([string] $Path, $Flags)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if ($Flags.Count -eq 0) {
        # Leere Datei statt geloeschter Datei waere okay, aber sauberer ist weg.
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        return
    }

    # ConvertTo-Json auf einem OrderedDictionary erhaelt die Reihenfolge.
    $json = [pscustomobject]$Flags | ConvertTo-Json -Depth 3
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -Force
}

function Set-TargetFlags {
    param([string] $Dir)

    $path = Join-Path $Dir "ClientSettings\$Script:SettingsName"
    Write-Step (Split-Path -Leaf $Dir)

    $existing = Read-ExistingFlags -Path $path

    # Einmalige Sicherung der urspruenglichen Datei, bevor wir das erste Mal
    # hineinschreiben. Damit ist -Remove auch dann verlustfrei, wenn der Nutzer
    # vorher schon eigene Flags hatte.
    $backup = "$path$Script:BackupSuffix"
    if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $path -Destination $backup -Force
        Write-Info 'Bestehende Konfiguration gesichert.'
    }

    if ($FlagProfile -eq 'Remove') {
        $managed = Get-ManagedFlagNames
        $kept = [ordered]@{}
        $dropped = 0
        foreach ($k in $existing.Keys) {
            if ($managed -contains $k) { $dropped++ } else { $kept[$k] = $existing[$k] }
        }
        Save-Flags -Path $path -Flags $kept
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
        Write-Ok "$dropped Flag(s) entfernt, $($kept.Count) fremde Flag(s) unangetastet."
        return
    }

    $wanted = Get-ProfileFlags -Name $FlagProfile
    $merged = [ordered]@{}
    foreach ($k in $existing.Keys) { $merged[$k] = $existing[$k] }   # Fremdes zuerst
    foreach ($k in $wanted.Keys)   { $merged[$k] = $wanted[$k] }     # unseres gewinnt

    Save-Flags -Path $path -Flags $merged
    Write-Ok "$($wanted.Count) Flag(s) gesetzt -> ClientSettings\$Script:SettingsName"
    foreach ($k in $wanted.Keys) { Write-Info ("{0} = {1}" -f $k, $wanted[$k]) }
}

function Set-BloxstrapFlags {
    # Bloxstrap haelt seine FastFlags getrennt von Roblox' Ordnern - und
    # ueberschreibt Roblox' ClientAppSettings.json bei jedem Start. Wer
    # Bloxstrap nutzt, muss also dort schreiben, sonst ist alles nach dem
    # naechsten Start wieder weg.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Bloxstrap\Modifications\ClientSettings\ClientAppSettings.json'),
        (Join-Path $env:LOCALAPPDATA 'Bloxstrap\ClientSettings\ClientAppSettings.json')
    )

    $root = Join-Path $env:LOCALAPPDATA 'Bloxstrap'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-Warn2 'Bloxstrap ist nicht installiert - uebersprungen.'
        return
    }

    $path = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $path) { $path = $candidates[0] }

    Write-Step 'Bloxstrap'
    $existing = Read-ExistingFlags -Path $path

    if ($FlagProfile -eq 'Remove') {
        $managed = Get-ManagedFlagNames
        $kept = [ordered]@{}
        foreach ($k in $existing.Keys) { if ($managed -notcontains $k) { $kept[$k] = $existing[$k] } }
        Save-Flags -Path $path -Flags $kept
        Write-Ok 'Bloxstrap-Flags bereinigt.'
        return
    }

    $wanted = Get-ProfileFlags -Name $FlagProfile
    $merged = [ordered]@{}
    foreach ($k in $existing.Keys) { $merged[$k] = $existing[$k] }
    foreach ($k in $wanted.Keys)   { $merged[$k] = $wanted[$k] }
    Save-Flags -Path $path -Flags $merged
    Write-Ok "Bloxstrap-Flags aktualisiert: $path"
    Write-Info 'In Bloxstrap unter "Fast Flags > Fast Flag Editor" nachpruefbar.'
}

function Main {
    Write-Host ''
    Write-Host '  RoGlow FastFlags - Roblox-Grafik ohne Injection' -ForegroundColor White
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host "  Profil: $FlagProfile" -ForegroundColor White
    Write-Host ''

    $running = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Warn2 'Roblox laeuft - die Aenderungen greifen erst beim naechsten Start.'
    }

    $dirs = @(Get-VersionDirs)
    if ($dirs.Count -eq 0) {
        throw 'Kein Roblox-Versionsordner gefunden. Starte Roblox einmal und versuche es erneut.'
    }

    $targets = if ($AllVersions) { $dirs } else { @($dirs[0]) }
    Write-Info "$($dirs.Count) Version(en) gefunden, schreibe in $($targets.Count)."
    Write-Host ''

    foreach ($d in $targets) { Set-TargetFlags -Dir $d.FullName }

    if ($Bloxstrap) { Set-BloxstrapFlags }

    Write-Host ''
    if ($FlagProfile -eq 'Remove') {
        Write-Host '  FastFlags entfernt. Roblox laeuft wieder mit Standardgrafik.' -ForegroundColor Green
    } else {
        Write-Host '  Fertig. Roblox neu starten, damit die Flags gelesen werden.' -ForegroundColor Green
        Write-Host ''
        Write-Info 'Danach im Spiel: Esc > Einstellungen > Grafikmodus auf Manuell'
        Write-Info 'und den Regler nach ganz rechts - sonst ueberschreibt die'
        Write-Info 'Automatik das erzwungene Qualitaetslevel wieder.'
        Write-Host ''
        Write-Warn2 'Ohne Bloxstrap setzt Roblox die Datei bei jedem Client-Update'
        Write-Warn2 'zurueck. Dann dieses Script einfach erneut ausfuehren.'
    }
    Write-Host ''
}

try {
    Main
} catch {
    Write-Host ''
    Write-Fail $_.Exception.Message
    Write-Host ''
    exit 1
}
