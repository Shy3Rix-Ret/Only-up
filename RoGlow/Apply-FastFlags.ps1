#Requires -Version 5.1
<#
.SYNOPSIS
    Setzt Roblox-eigene Grafik-FastFlags - ausschliesslich solche, die auf
    Roblox' offizieller Allowlist stehen und damit tatsaechlich wirken.

.DESCRIPTION
    Roblox liest beim Start eine ClientAppSettings.json aus dem
    ClientSettings-Ordner der jeweiligen Version. Das sind Konfigurationswerte
    der Engine - kein fremder Code, keine Injection, kein Anti-Cheat-Konflikt.

    SEIT DEM 29.09.2025 GILT EINE ALLOWLIST.
    Roblox hat die lokal setzbaren FastFlags auf 18 Stueck begrenzt. Alles,
    was nicht auf der Liste steht, wird beim Start stillschweigend ignoriert.
    Genau daran scheitern die meisten kursierenden FastFlag-Listen: sie sind
    aelter als die Allowlist, und wer sie einträgt, aendert schlicht nichts.

    Dieses Script setzt nur allowlistete Flags. Der eingebaute Selbsttest
    bricht ab, falls ein Profil je ein Flag enthaelt, das nicht auf der Liste
    steht - damit kann hier nie wieder ein wirkungsloser Wert landen.

    Mit -Audit prueft das Script deine bestehende Konfiguration und sagt dir,
    welche deiner Flags noch wirken und welche tote Buchstaben sind.

    Die Allowlist gilt fuer den Roblox Player. Roblox Studio behaelt laut
    Roblox weiterhin die vollen FastFlags.

.PARAMETER Profile
    Quality     - maximale Optik (Default)
    Balanced    - hohe Qualitaet, guenstigeres MSAA und LOD
    Performance - auf FPS getrimmt
    Remove      - alle von diesem Script gesetzten Flags entfernen

.PARAMETER Audit
    Nur pruefen: zeigt fuer jede gefundene ClientAppSettings.json, welche
    Flags allowlistet sind und welche ignoriert werden. Schreibt nichts.

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
    .\Apply-FastFlags.ps1 -Audit
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
    [ValidateSet('Quality', 'Balanced', 'Performance', 'Remove')]
    [string] $FlagProfile = 'Quality',

    [switch] $Audit,
    [switch] $Bloxstrap,
    [switch] $Remove,
    [switch] $AllVersions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Remove) { $FlagProfile = 'Remove' }

$Script:SettingsName = 'ClientAppSettings.json'
$Script:BackupSuffix = '.roglow-backup'

function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "        $m" -ForegroundColor Gray }
function Write-Warn2{ param([string]$m) Write-Host "  !  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  X  $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Roblox' offizielle Allowlist (Stand 29.09.2025, 18 Flags)
#
# Default = der Wert, den Roblox ohne Eingriff verwendet. Alles, was hier
# nicht steht, ignoriert der Client - egal was in der JSON steht.
# ---------------------------------------------------------------------------
$Script:Allowlist = [ordered]@{
    'DFIntCSGLevelOfDetailSwitchingDistance'    = @{ Default = '250';  Note = 'Entfernung, ab der Teile auf LOD-Stufe 1 wechseln' }
    'DFIntCSGLevelOfDetailSwitchingDistanceL12' = @{ Default = '500';  Note = 'LOD-Wechsel Stufe 1 -> 2' }
    'DFIntCSGLevelOfDetailSwitchingDistanceL23' = @{ Default = '750';  Note = 'LOD-Wechsel Stufe 2 -> 3' }
    'DFIntCSGLevelOfDetailSwitchingDistanceL34' = @{ Default = '1000'; Note = 'LOD-Wechsel Stufe 3 -> 4' }
    'DFIntDebugFRMQualityLevelOverride'         = @{ Default = '0';    Note = 'Internes Qualitaetslevel 1-21 (0 = Automatik)' }
    'FIntDebugForceMSAASamples'                 = @{ Default = '0';    Note = 'Kantenglaettung: 0/1/2/4/8, ueber 4 gibt es Viewport-Fehler' }
    'DFFlagTextureQualityOverrideEnabled'       = @{ Default = 'False';Note = 'Schaltet die Texturqualitaets-Uebersteuerung ein' }
    'DFIntTextureQualityOverride'               = @{ Default = '3';    Note = 'Texturqualitaet 0-3, hoeher ist besser' }
    'FIntFRMMinGrassDistance'                   = @{ Default = '100';  Note = 'Ab welcher Entfernung Gras ausduennt' }
    'FIntFRMMaxGrassDistance'                   = @{ Default = '290';  Note = 'Ab welcher Entfernung Gras ganz verschwindet' }
    'FIntGrassMovementReducedMotionFactor'      = @{ Default = '5';    Note = 'Staerke der Grasbewegung' }
    'FFlagDebugGraphicsPreferD3D11'             = @{ Default = 'False';Note = 'Rendering-API auf Direct3D 11 festlegen' }
    'FFlagDebugGraphicsPreferVulkan'            = @{ Default = 'False';Note = 'Rendering-API auf Vulkan festlegen' }
    'FFlagDebugGraphicsPreferOpenGL'            = @{ Default = 'False';Note = 'Rendering-API auf OpenGL festlegen' }
    'DFFlagDebugPauseVoxelizer'                 = @{ Default = 'False';Note = 'True friert die Voxel-Beleuchtung ein (Qualitaetsverlust)' }
    'FFlagDebugSkyGray'                         = @{ Default = 'False';Note = 'True ersetzt den Himmel durch Grau (Qualitaetsverlust)' }
    'FFlagHandleAltEnterFullscreenManually'     = @{ Default = 'True'; Note = 'Alt+Enter-Vollbild selbst behandeln' }
    'DFFlagDisableDPIScale'                     = @{ Default = 'False';Note = 'Windows-DPI-Skalierung abschalten' }
}

# ---------------------------------------------------------------------------
# Profile - ausschliesslich aus allowlisteten Flags
# ---------------------------------------------------------------------------

# Rendering-API festnageln. Roblox kann D3D11, Vulkan und OpenGL; ein Wechsel
# kostet Bildqualitaet und Stabilitaet. In allen Profilen gleich.
$Script:FlagsApi = [ordered]@{
    'FFlagDebugGraphicsPreferD3D11'  = 'True'
    'FFlagDebugGraphicsPreferVulkan' = 'False'
    'FFlagDebugGraphicsPreferOpenGL' = 'False'
}

# Zwei Flags, die die Optik aktiv verschlechtern, wenn sie an sind. Sie stehen
# in vielen kursierenden "FPS-Boost"-Listen. Hier werden sie ausdruecklich auf
# False gesetzt, damit eine alte Konfiguration ueberschrieben wird.
$Script:FlagsNoDegrade = [ordered]@{
    'DFFlagDebugPauseVoxelizer' = 'False'
    'FFlagDebugSkyGray'         = 'False'
}

function Get-ProfileFlags {
    param([string] $Name)

    $f = [ordered]@{}
    foreach ($h in @($Script:FlagsApi, $Script:FlagsNoDegrade)) {
        foreach ($k in $h.Keys) { $f[$k] = $h[$k] }
    }

    switch ($Name) {
        'Quality' {
            # 21 ist das Maximum des internen Qualitaetsreglers und geht ueber
            # das hinaus, was die Roblox-UI zulaesst. Das ist der wirksamste
            # Einzelwert: er steuert intern Beleuchtung, Schatten und
            # Effektdichte gemeinsam.
            $f['DFIntDebugFRMQualityLevelOverride'] = '21'
            # 4x MSAA. 8 waere erlaubt, erzeugt aber bekannte Viewport-Fehler.
            $f['FIntDebugForceMSAASamples'] = '4'
            # Texturen auf Maximum, unabhaengig von der Automatik.
            $f['DFFlagTextureQualityOverrideEnabled'] = 'True'
            $f['DFIntTextureQualityOverride'] = '3'
            # LOD-Distanzen vervierfacht: Detailstufen wechseln erst weit
            # hinten, das sichtbare "Aufploppen" verschwindet praktisch.
            $f['DFIntCSGLevelOfDetailSwitchingDistance']    = '1000'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL12'] = '2000'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL23'] = '3000'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL34'] = '4000'
            # Gras deutlich weiter sichtbar statt kurz vor der Nase auszudünnen.
            $f['FIntFRMMinGrassDistance'] = '400'
            $f['FIntFRMMaxGrassDistance'] = '1000'
        }
        'Balanced' {
            $f['DFIntDebugFRMQualityLevelOverride'] = '21'
            # 2x statt 4x MSAA - der Sprung von 0 auf 2 bringt optisch am
            # meisten, von 2 auf 4 kostet nochmal spuerbar Fuellrate.
            $f['FIntDebugForceMSAASamples'] = '2'
            $f['DFFlagTextureQualityOverrideEnabled'] = 'True'
            $f['DFIntTextureQualityOverride'] = '3'
            # LOD nur verdoppelt.
            $f['DFIntCSGLevelOfDetailSwitchingDistance']    = '500'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL12'] = '1000'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL23'] = '1500'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL34'] = '2000'
            # Gras auf Roblox-Standard.
            $f['FIntFRMMinGrassDistance'] = '100'
            $f['FIntFRMMaxGrassDistance'] = '290'
        }
        'Performance' {
            # Level 10 statt 21: sichtbar reduziert, aber nicht die
            # Pappkarton-Optik von Level 1.
            $f['DFIntDebugFRMQualityLevelOverride'] = '10'
            $f['FIntDebugForceMSAASamples'] = '0'
            $f['DFFlagTextureQualityOverrideEnabled'] = 'False'
            $f['DFIntCSGLevelOfDetailSwitchingDistance']    = '250'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL12'] = '500'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL23'] = '750'
            $f['DFIntCSGLevelOfDetailSwitchingDistanceL34'] = '1000'
            # Gras ist einer der teuersten Posten bei Roblox.
            $f['FIntFRMMinGrassDistance'] = '0'
            $f['FIntFRMMaxGrassDistance'] = '0'
        }
    }
    return $f
}

function Get-ManagedFlagNames {
    <# Alle Namen, die dieses Script je schreibt - fuer sauberes -Remove. #>
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($p in @('Quality', 'Balanced', 'Performance')) {
        foreach ($k in (Get-ProfileFlags -Name $p).Keys) {
            if (-not $names.Contains($k)) { $names.Add($k) }
        }
    }
    return $names
}

function Assert-ProfilesAllowlisted {
    <#
      Selbsttest. Faellt auf, sobald jemand ein Flag in ein Profil schreibt,
      das Roblox nicht mehr akzeptiert - genau der Fehler, den die Allowlist
      sonst stumm verschluckt.
    #>
    $bad = @(Get-ManagedFlagNames | Where-Object { -not $Script:Allowlist.Contains($_) })
    if ($bad.Count -gt 0) {
        throw "Interner Fehler: nicht allowlistete Flags in den Profilen: $($bad -join ', ')"
    }
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

function Get-BloxstrapConfigPath {
    $root = Join-Path $env:LOCALAPPDATA 'Bloxstrap'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    $candidates = @(
        (Join-Path $root 'Modifications\ClientSettings\ClientAppSettings.json'),
        (Join-Path $root 'ClientSettings\ClientAppSettings.json')
    )
    $existing = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($existing) { return $existing }
    return $candidates[0]
}

# ---------------------------------------------------------------------------
# Lesen / Schreiben
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
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if ($Flags.Count -eq 0) {
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        return
    }
    # ConvertTo-Json auf einem OrderedDictionary erhaelt die Reihenfolge.
    ([pscustomobject]$Flags | ConvertTo-Json -Depth 3) |
        Set-Content -LiteralPath $Path -Encoding UTF8 -Force
}

function Show-InertFlags {
    <# Meldet Flags in einer bestehenden Konfiguration, die Roblox ignoriert. #>
    param($Flags, [string] $Label)

    $inert = @($Flags.Keys | Where-Object { -not $Script:Allowlist.Contains($_) })
    if ($inert.Count -eq 0) { return }

    Write-Warn2 "$Label - $($inert.Count) Flag(s) stehen nicht auf Roblox' Allowlist und werden ignoriert:"
    foreach ($k in $inert) { Write-Info "wirkungslos: $k = $($Flags[$k])" }
}

function Set-TargetFlags {
    param([string] $Dir)

    $path = Join-Path $Dir 'ClientSettings'
    $path = Join-Path $path $Script:SettingsName
    Write-Step (Split-Path -Leaf $Dir)

    $existing = Read-ExistingFlags -Path $path
    Show-InertFlags -Flags $existing -Label 'Bestehende Konfiguration'

    # Einmalige Sicherung, bevor wir das erste Mal hineinschreiben. Damit ist
    # -Remove auch dann verlustfrei, wenn vorher eigene Flags gesetzt waren.
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
    Write-Ok "$($wanted.Count) allowlistete Flag(s) gesetzt."
    foreach ($k in $wanted.Keys) {
        $def = $Script:Allowlist[$k].Default
        $marker = if ($wanted[$k] -eq $def) { ' (= Roblox-Standard)' } else { " (Standard: $def)" }
        Write-Info ("{0} = {1}{2}" -f $k, $wanted[$k], $marker)
    }
}

function Set-BloxstrapFlags {
    # Bloxstrap haelt seine FastFlags getrennt und ueberschreibt Roblox'
    # ClientAppSettings.json bei jedem Start. Wer Bloxstrap nutzt, muss also
    # dort schreiben, sonst ist alles nach dem naechsten Start wieder weg.
    $path = Get-BloxstrapConfigPath
    if (-not $path) {
        Write-Warn2 'Bloxstrap ist nicht installiert - uebersprungen.'
        return
    }

    Write-Step 'Bloxstrap'
    $existing = Read-ExistingFlags -Path $path
    Show-InertFlags -Flags $existing -Label 'Bloxstrap-Konfiguration'

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
    Write-Info 'Nachpruefbar unter "Fast Flags > Fast Flag Editor".'
}

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------

function Invoke-Audit {
    param([object[]] $Dirs)

    $paths = New-Object System.Collections.Generic.List[object]
    foreach ($d in $Dirs) {
        $p = Join-Path $d.FullName 'ClientSettings'
        $paths.Add([pscustomobject]@{ Label = $d.Name; Path = (Join-Path $p $Script:SettingsName) })
    }
    $bs = Get-BloxstrapConfigPath
    if ($bs) { $paths.Add([pscustomobject]@{ Label = 'Bloxstrap'; Path = $bs }) }

    $found = $false
    foreach ($entry in $paths) {
        if (-not (Test-Path -LiteralPath $entry.Path -PathType Leaf)) { continue }
        $found = $true
        Write-Step $entry.Label
        Write-Info $entry.Path

        $flags = Read-ExistingFlags -Path $entry.Path
        if ($flags.Count -eq 0) { Write-Info 'Datei ist leer.'; continue }

        $live = @($flags.Keys | Where-Object { $Script:Allowlist.Contains($_) })
        $dead = @($flags.Keys | Where-Object { -not $Script:Allowlist.Contains($_) })

        Write-Ok "$($live.Count) von $($flags.Count) Flag(s) wirken tatsaechlich."
        foreach ($k in $live) {
            $def = $Script:Allowlist[$k].Default
            if ($flags[$k] -eq $def) {
                Write-Info ("wirkt (aber = Standard): {0} = {1}" -f $k, $flags[$k])
            } else {
                Write-Host ("        wirkt: {0} = {1}   [Standard {2}]" -f $k, $flags[$k], $def) -ForegroundColor Green
            }
        }
        if ($dead.Count -gt 0) {
            Write-Warn2 "$($dead.Count) Flag(s) stehen nicht auf der Allowlist und werden ignoriert:"
            foreach ($k in $dead) { Write-Host ("        wirkungslos: {0} = {1}" -f $k, $flags[$k]) -ForegroundColor DarkYellow }
        }
    }

    if (-not $found) {
        Write-Info 'Keine ClientAppSettings.json gefunden - es sind aktuell keine FastFlags gesetzt.'
    }

    Write-Host ''
    Write-Step 'Roblox-Allowlist (18 Flags, Stand 29.09.2025)'
    foreach ($k in $Script:Allowlist.Keys) {
        Write-Host ("        {0,-42} Standard {1,-6} {2}" -f $k, $Script:Allowlist[$k].Default, $Script:Allowlist[$k].Note) -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------

function Main {
    Assert-ProfilesAllowlisted

    Write-Host ''
    Write-Host '  RoGlow FastFlags - Roblox-Grafik ohne Injection' -ForegroundColor White
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
    if ($Audit) {
        Write-Host '  Modus: Pruefung (es wird nichts geschrieben)' -ForegroundColor White
    } else {
        Write-Host "  Profil: $FlagProfile" -ForegroundColor White
    }
    Write-Host ''

    $dirs = @(Get-VersionDirs)
    if ($dirs.Count -eq 0) {
        throw 'Kein Roblox-Versionsordner gefunden. Starte Roblox einmal und versuche es erneut.'
    }

    if ($Audit) { Invoke-Audit -Dirs $dirs; Write-Host ''; return }

    $running = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Warn2 'Roblox laeuft - die Aenderungen greifen erst beim naechsten Start.'
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
