#Requires -Version 5.1
<#
.SYNOPSIS
    Entfernt RoGlow und ReShade restlos aus allen Roblox-Versionsordnern.

.DESCRIPTION
    Liest roglow-manifest.json aus jedem Zielordner und loescht ausschliesslich
    die dort protokollierten Dateien. Es wird niemals ein Verzeichnis pauschal
    geloescht - Roblox' eigene Dateien liegen im selben Ordner.

    Zusaetzlich werden die Dateien entfernt, die ReShade selbst zur Laufzeit
    anlegt (ReShade.log, ReShadePreset.ini, Effekt-Cache) - diese stehen naemlich
    nicht im Manifest, weil der Installer sie nicht geschrieben hat.

    Ordner werden nur dann entfernt, wenn sie danach leer sind.

.PARAMETER RobloxPath
    Nur diesen Ordner aufraeumen statt aller registrierten Installationen.

.PARAMETER KeepCache
    Den Download-Cache unter %LOCALAPPDATA%\RoGlow behalten. Sinnvoll, wenn du
    spaeter erneut installieren willst, ohne neu herunterzuladen.

.PARAMETER Scan
    Zusaetzlich alle version-* Ordner durchsuchen, auch ohne Manifest. Faengt
    Reste ein, deren Manifest verlorengegangen ist.

.PARAMETER WhatIf
    Nur anzeigen, was geloescht wuerde.

.EXAMPLE
    .\Uninstall-RoGlow.ps1
.EXAMPLE
    .\Uninstall-RoGlow.ps1 -Scan -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $RobloxPath,
    [switch] $KeepCache,
    [switch] $Scan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:StateDir     = Join-Path $env:LOCALAPPDATA 'RoGlow'
$Script:InstallIndex = Join-Path $Script:StateDir 'installs.json'
$Script:ManifestName = 'roglow-manifest.json'

# Dateien, die ReShade zur Laufzeit selbst anlegt und die deshalb nie im
# Manifest stehen. Nur exakte Namen - keine Wildcards, die Fremdes treffen.
$Script:RuntimeArtifacts = @(
    'ReShade.log', 'ReShade.ini', 'ReShadePreset.ini',
    'dxgi.log', 'd3d11.log', 'ReShade64.json', 'ReShade.json'
)

# Alle DLL-Namen, unter denen ReShade sich einklinken kann. Falls jemand
# frueher manuell mit einer anderen API installiert hat.
$Script:ReShadeDllNames = @('dxgi.dll', 'd3d11.dll', 'd3d10.dll', 'd3d9.dll', 'opengl32.dll')

function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "        $m" -ForegroundColor Gray }
function Write-Warn2{ param([string]$m) Write-Host "  !  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  X  $m" -ForegroundColor Red }

function Test-IsReShadeDll {
    <#
      Sicherheitsnetz: nur loeschen, wenn die DLL wirklich ReShade ist.
      Manche Spiele/Tools legen legitime dxgi.dll-Proxies ab - die wollen wir
      nicht mitreissen.
    #>
    param([string] $Path)
    try {
        $vi = (Get-Item -LiteralPath $Path).VersionInfo
        $blob = "$($vi.ProductName) $($vi.FileDescription) $($vi.CompanyName) $($vi.LegalCopyright)"
        return ($blob -match 'ReShade')
    } catch {
        return $false
    }
}

function Get-InstallTargets {
    $targets = New-Object System.Collections.Generic.List[string]

    if ($RobloxPath) {
        $p = $RobloxPath
        if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -Parent $p }
        $targets.Add($p)
        return $targets
    }

    if (Test-Path -LiteralPath $Script:InstallIndex) {
        try {
            foreach ($d in @(Get-Content -LiteralPath $Script:InstallIndex -Raw | ConvertFrom-Json)) {
                if ($d) { $targets.Add([string]$d) }
            }
            Write-Info "$($targets.Count) Eintrag/Eintraege aus installs.json"
        } catch {
            Write-Warn2 'installs.json ist unlesbar - weiter mit Ordnerscan.'
        }
    }

    if ($Scan -or $targets.Count -eq 0) {
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
                ForEach-Object {
                    if (-not $targets.Contains($_.FullName)) { $targets.Add($_.FullName) }
                }
        }
    }

    return $targets
}

function Remove-OneFile {
    param([string] $Path, [ref] $Counter)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    if ($PSCmdlet.ShouldProcess($Path, 'Loeschen')) {
        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            $Counter.Value++
            Write-Info "geloescht: $(Split-Path -Leaf $Path)"
        } catch {
            Write-Fail "nicht loeschbar: $Path  ($($_.Exception.Message))"
        }
    } else {
        Write-Info "wuerde loeschen: $Path"
    }
}

function Clear-Target {
    param([string] $Dir)

    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        Write-Info "Ordner existiert nicht mehr (Roblox-Update?): $Dir"
        return 0
    }

    Write-Step "Raeume auf: $(Split-Path -Leaf $Dir)"
    Write-Info $Dir

    $removed = 0
    $counter = [ref] $removed
    $manifestPath = Join-Path $Dir $Script:ManifestName
    $dirsToTry = New-Object System.Collections.Generic.List[string]

    # --- 1. Manifest abarbeiten ---
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            foreach ($rel in @($m.files)) {
                Remove-OneFile -Path (Join-Path $Dir $rel) -Counter $counter
            }
            foreach ($d in @($m.directories)) { $dirsToTry.Add((Join-Path $Dir $d)) }
            Write-Ok "Manifest abgearbeitet ($(@($m.files).Count) Eintraege)."
        } catch {
            Write-Warn2 "Manifest unlesbar, nutze Standardliste: $($_.Exception.Message)"
        }
        Remove-OneFile -Path $manifestPath -Counter $counter
    } else {
        Write-Info 'Kein Manifest - nutze Standardliste.'
    }

    # --- 2. ReShade-DLLs (mit Herkunftspruefung) ---
    foreach ($dllName in $Script:ReShadeDllNames) {
        $dll = Join-Path $Dir $dllName
        if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { continue }
        if (Test-IsReShadeDll -Path $dll) {
            Remove-OneFile -Path $dll -Counter $counter
        } else {
            Write-Warn2 "$dllName ist nicht von ReShade - bleibt liegen."
        }
    }

    # --- 3. Laufzeit-Artefakte und Presets ---
    foreach ($name in $Script:RuntimeArtifacts) {
        Remove-OneFile -Path (Join-Path $Dir $name) -Counter $counter
    }
    Get-ChildItem -LiteralPath $Dir -Filter 'RoGlow-*.ini' -File -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-OneFile -Path $_.FullName -Counter $counter }

    # --- 4. Shader-Ordner ---
    $shaderRoot = Join-Path $Dir 'reshade-shaders'
    if (Test-Path -LiteralPath $shaderRoot -PathType Container) {
        if ($PSCmdlet.ShouldProcess($shaderRoot, 'Shader-Ordner loeschen')) {
            try {
                Remove-Item -LiteralPath $shaderRoot -Recurse -Force -ErrorAction Stop
                Write-Info 'geloescht: reshade-shaders\'
                $removed++
            } catch {
                Write-Fail "reshade-shaders\ nicht loeschbar: $($_.Exception.Message)"
            }
        } else {
            Write-Info "wuerde loeschen: $shaderRoot"
        }
    }

    # --- 5. Leere Ordner aus dem Manifest ---
    foreach ($d in ($dirsToTry | Sort-Object -Property Length -Descending)) {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
        if (@(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) {
            Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
        }
    }

    if ($removed -eq 0) { Write-Info 'Nichts zu entfernen.' } else { Write-Ok "$removed Eintrag/Eintraege entfernt." }
    return $removed
}

function Main {
    Write-Host ''
    Write-Host '  RoGlow deinstallieren' -ForegroundColor White
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray

    $running = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw 'Roblox laeuft gerade - dxgi.dll ist gesperrt. Bitte Roblox schliessen.'
    }

    $targets = @(Get-InstallTargets)
    if ($targets.Count -eq 0) {
        Write-Warn2 'Keine Installation gefunden. Nichts zu tun.'
        return
    }

    $total = 0
    foreach ($t in $targets) { $total += (Clear-Target -Dir $t) }

    # Index aufraeumen
    if (-not $RobloxPath -and (Test-Path -LiteralPath $Script:InstallIndex)) {
        if ($PSCmdlet.ShouldProcess($Script:InstallIndex, 'Loeschen')) {
            Remove-Item -LiteralPath $Script:InstallIndex -Force -ErrorAction SilentlyContinue
        }
    }

    # Cache
    if (-not $KeepCache -and (Test-Path -LiteralPath $Script:StateDir)) {
        if ($PSCmdlet.ShouldProcess($Script:StateDir, 'Cache loeschen')) {
            try {
                Remove-Item -LiteralPath $Script:StateDir -Recurse -Force -ErrorAction Stop
                Write-Ok "Cache entfernt: $Script:StateDir"
            } catch {
                Write-Warn2 "Cache nicht vollstaendig entfernbar: $($_.Exception.Message)"
            }
        }
    } elseif ($KeepCache) {
        Write-Info "Cache bleibt erhalten: $Script:StateDir"
    }

    Write-Host ''
    Write-Host "  Fertig - $total Eintrag/Eintraege entfernt." -ForegroundColor Green
    Write-Host '  Roblox startet ab sofort wieder unveraendert.' -ForegroundColor Gray
    Write-Host ''
    Write-Info 'Hinweis: FastFlags werden hiervon NICHT beruehrt.'
    Write-Info 'Die entfernst du mit:  .\Apply-FastFlags.ps1 -Remove'
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
