#Requires -Version 5.1
<#
.SYNOPSIS
    RoGlow - installiert ReShade + ein abgestimmtes Shader-Preset fuer den
    Roblox-Windows-Client (DirectX 11).

.DESCRIPTION
    Findet die aktuelle Roblox-Version (Registry zuerst, dann Dateisystem),
    installiert die ReShade-Runtime als dxgi.dll, laedt die benoetigten
    .fx-Shader aus den offiziellen Upstream-Repos und schreibt eine fertige
    ReShade.ini samt Preset und Toggle-Hotkey.

    Jede geschriebene Datei wird in roglow-manifest.json protokolliert.
    Uninstall-RoGlow.ps1 entfernt exakt diese Dateien - es wird nie ein
    Verzeichnis pauschal geloescht.

    WICHTIG - bitte vorher lesen:
    Roblox' Anti-Tamper-Schicht "Hyperion" (Byfron) unterdrueckt seit 2023 das
    ReShade-Overlay im Roblox *Player*. Die dxgi.dll wird geladen, aber Menue
    und Effekte werden geblockt. Es gibt bis heute keine Whitelist. Dieses
    Script umgeht Hyperion NICHT und versucht es auch nicht - es installiert
    ReShade auf dem normalen, dokumentierten Weg. Ob etwas sichtbar wird,
    entscheidet allein Roblox.
    Fuer einen Weg, der heute funktioniert, siehe Apply-FastFlags.ps1.

.PARAMETER Preset
    Performance | Balanced | Quality. Default: Balanced.

.PARAMETER ToggleKey
    Taste zum Ein-/Ausschalten aller Effekte im Spiel. Default: F8.

.PARAMETER RobloxPath
    Manueller Pfad zu RobloxPlayerBeta.exe oder zum version-* Ordner.
    Ueberspringt die automatische Erkennung.

.PARAMETER AllVersions
    Installiert in alle gefundenen version-* Ordner statt nur in den neuesten.

.PARAMETER Repair
    Installiert erneut aus dem lokalen Cache, ohne Netzwerkzugriff.
    Das ist der schnelle Weg nach einem Roblox-Update.

.PARAMETER CheckLog
    Wertet ReShade.log im Zielordner aus und beendet sich. Zeigt, ob ReShade
    geladen wurde und ob alle Shader kompiliert haben.

.PARAMETER ReShadeVersion
    Feste ReShade-Version statt der automatisch ermittelten, z.B. "6.7.3".

.PARAMETER ExpectedHash
    Erwarteter SHA256 des ReShade-Setups. Bei Abweichung bricht das Script ab.

.PARAMETER Yes
    Beantwortet die Sicherheitsabfrage automatisch mit Ja.

.PARAMETER Force
    Installiert auch, wenn Roblox gerade laeuft, und ueberschreibt bestehende
    RoGlow-Dateien.

.EXAMPLE
    .\Install-RoGlow.ps1
.EXAMPLE
    .\Install-RoGlow.ps1 -Preset Performance -ToggleKey F7
.EXAMPLE
    .\Install-RoGlow.ps1 -Repair          # nach einem Roblox-Update
.EXAMPLE
    .\Install-RoGlow.ps1 -CheckLog        # hat ReShade geladen?
#>
[CmdletBinding()]
param(
    [ValidateSet('Performance', 'Balanced', 'Quality')]
    [string] $Preset = 'Balanced',

    [ValidatePattern('^(F([1-9]|1[0-2])|HOME|END|INSERT|DELETE|PAUSE|SCROLL)$')]
    [string] $ToggleKey = 'F8',

    [string] $RobloxPath,
    [switch] $AllVersions,
    [switch] $Repair,
    [switch] $CheckLog,
    [string] $ReShadeVersion,
    [string] $ExpectedHash,
    [switch] $Yes,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------------
$Script:ToolName       = 'RoGlow'
$Script:ToolVersion    = '1.0.0'
$Script:FallbackReShade = '6.7.3'   # Stand 2026-02-28, wird online geprueft
$Script:ScriptRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:StateDir       = Join-Path $env:LOCALAPPDATA 'RoGlow'
$Script:CacheDir       = Join-Path $Script:StateDir  'cache'
$Script:ShaderCacheDir = Join-Path $Script:CacheDir  'Shaders'
$Script:InstallIndex   = Join-Path $Script:StateDir  'installs.json'
$Script:ManifestName   = 'roglow-manifest.json'

# Shader-Quellen. Bewusst nur Dateien, die ohne zusaetzliche Texturen
# kompilieren - UIMask.fx z.B. braucht eine UIMask.png und wuerde sonst
# garantiert einen Compile-Fehler werfen.
$Script:ShaderSources = @(
    @{ Repo = 'crosire/reshade-shaders'; Ref = 'slim'; Path = 'Shaders'
       Files = @('ReShade.fxh', 'ReShadeUI.fxh', 'Macros.fxh', 'Blending.fxh',
                 'TriDither.fxh', 'DrawText.fxh', 'DisplayDepth.fx') }

    @{ Repo = 'crosire/reshade-shaders'; Ref = 'legacy'; Path = 'Shaders'
       Files = @('ReflectiveBumpMapping.fx') }

    @{ Repo = 'martymcmodding/qUINT'; Ref = 'master'; Path = 'Shaders'
       Files = @('qUINT_common.fxh', 'qUINT_bloom.fx', 'qUINT_mxao.fx',
                 'qUINT_ssr.fx', 'qUINT_dof.fx', 'qUINT_sharp.fx') }

    @{ Repo = 'CeeJayDK/SweetFX'; Ref = 'master'; Path = 'Shaders/SweetFX'
       Files = @('Tonemap.fx', 'Vibrance.fx', 'Curves.fx', 'CAS.fx',
                 'LumaSharpen.fx', 'LiftGammaGain.fx') }
)

# Virtual-Key-Codes fuer die Hotkey-Zeilen in ReShade.ini
$Script:VirtualKeys = @{
    'F1' = 112; 'F2' = 113; 'F3' = 114; 'F4' = 115; 'F5' = 116; 'F6' = 117
    'F7' = 118; 'F8' = 119; 'F9' = 120; 'F10' = 121; 'F11' = 122; 'F12' = 123
    'HOME' = 36; 'END' = 35; 'INSERT' = 45; 'DELETE' = 46
    'PAUSE' = 19; 'SCROLL' = 145
}

# Bootstrapper, die statt Roblox selbst im Protocol-Handler stehen koennen
$Script:BootstrapperNames = @('Bloxstrap', 'Fishstrap', 'Voidstrap', 'Lexstrap')

# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------
function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "        $m" -ForegroundColor Gray }
function Write-Warn2{ param([string]$m) Write-Host "  !  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  X  $m" -ForegroundColor Red }

function Show-Banner {
    Write-Host ''
    Write-Host "  $Script:ToolName $Script:ToolVersion - ReShade fuer Roblox (DirectX 11)" -ForegroundColor White
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Roblox-Erkennung
# ---------------------------------------------------------------------------

function Get-QuotedExePath {
    <# Zieht den Programmpfad aus einem Registry-Kommandostring wie
       "C:\...\RobloxPlayerBeta.exe" --app -t %1 #>
    param([string] $CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    if ($CommandLine -match '^\s*"([^"]+)"') { return $Matches[1] }
    if ($CommandLine -match '^\s*(\S+\.exe)')  { return $Matches[1] }
    return $null
}

function Get-RegistryValue {
    param([string] $Path, [string] $Name)
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch { return $null }
}

function New-RobloxCandidate {
    param([string] $ExePath, [string] $Source)

    if ([string]::IsNullOrWhiteSpace($ExePath)) { return $null }
    try { $ExePath = [System.IO.Path]::GetFullPath($ExePath) } catch { return $null }
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { return $null }
    if ([System.IO.Path]::GetFileName($ExePath) -ne 'RobloxPlayerBeta.exe') { return $null }

    # Microsoft-Store-/UWP-Installation: WindowsApps ist schreibgeschuetzt und
    # signaturgepruefft - dort kann und soll nichts abgelegt werden.
    if ($ExePath -like '*\WindowsApps\*') {
        Write-Warn2 "Microsoft-Store-Version uebersprungen (nicht beschreibbar): $ExePath"
        return $null
    }

    $dir = Split-Path -Parent $ExePath
    [pscustomobject]@{
        Exe      = $ExePath
        Dir      = $dir
        Version  = Split-Path -Leaf $dir
        Source   = $Source
        Modified = (Get-Item -LiteralPath $ExePath).LastWriteTimeUtc
    }
}

function Resolve-RobloxPlayer {
    <#
      Reihenfolge nach Verlaesslichkeit:
        1. laufender Prozess  - kann gar nicht falsch sein
        2. Registry           - der von Roblox selbst gepflegte Zeiger
        3. Dateisystem-Scan   - Fallback, deckt auch Mehrfachversionen ab
    #>
    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]

    function Add-Candidate {
        param($Exe, $Source)
        $c = New-RobloxCandidate -ExePath $Exe -Source $Source
        if ($null -eq $c) { return }
        if ($seen.Add($c.Exe.ToLowerInvariant())) { $candidates.Add($c) }
    }

    # 1. laufender Prozess
    try {
        foreach ($p in @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)) {
            if ($p.Path) { Add-Candidate $p.Path 'laufender Prozess' }
        }
    } catch { }

    # 2a. Roblox' eigener Environment-Key
    $clientExe = Get-RegistryValue 'HKCU:\Software\ROBLOX Corporation\Environments\roblox-player' 'clientExe'
    if ($clientExe) { Add-Candidate $clientExe 'Registry (Environments)' }

    # 2b. Protocol-Handler roblox-player://
    $cmdKeys = @(
        'HKCU:\Software\Classes\roblox-player\shell\open\command',
        'HKLM:\Software\Classes\roblox-player\shell\open\command'
    )
    foreach ($key in $cmdKeys) {
        $cmd = Get-RegistryValue $key '(default)'
        if (-not $cmd) { continue }
        $exe = Get-QuotedExePath $cmd
        if (-not $exe) { continue }

        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($exe)
        if ($Script:BootstrapperNames -contains $leaf) {
            # Bloxstrap & Co. haengen sich in den Protocol-Handler. Sie starten
            # aber weiterhin die normale RobloxPlayerBeta.exe - der Dateiscan
            # unten findet sie.
            Write-Info "Bootstrapper erkannt ($leaf) - Protocol-Handler zeigt nicht direkt auf Roblox."
            continue
        }
        Add-Candidate $exe 'Registry (Protocol-Handler)'
    }

    # 2c. Uninstall-Eintrag
    foreach ($u in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Roblox',
                     'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RobloxPlayer')) {
        $loc = Get-RegistryValue $u 'InstallLocation'
        if ($loc) { Add-Candidate (Join-Path $loc 'RobloxPlayerBeta.exe') 'Registry (Uninstall)' }
    }

    # 3. Dateisystem. Roblox legt bei JEDEM Update einen neuen version-<hex>
    #    Ordner an, der alte bleibt oft noch eine Weile liegen.
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Roblox\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Bloxstrap\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Fishstrap\Versions')
    )
    if ($env:ProgramFiles)        { $roots += (Join-Path $env:ProgramFiles 'Roblox\Versions') }
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions') }

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        try {
            Get-ChildItem -LiteralPath $root -Directory -Filter 'version-*' -ErrorAction Stop |
                ForEach-Object { Add-Candidate (Join-Path $_.FullName 'RobloxPlayerBeta.exe') 'Dateisystem' }
        } catch {
            Write-Warn2 "Ordner nicht lesbar: $root"
        }
    }

    # Neueste zuerst
    return @($candidates | Sort-Object -Property Modified -Descending)
}

# ---------------------------------------------------------------------------
# Download-Helfer
# ---------------------------------------------------------------------------

function Initialize-Tls {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    } catch {
        Write-Warn2 'TLS-Protokoll konnte nicht gesetzt werden - Downloads koennten scheitern.'
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][string] $Destination,
        [int] $Retries = 4
    )
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $tmp = "$Destination.part"
    $delay = 2
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 60 `
                              -UserAgent "$Script:ToolName/$Script:ToolVersion" -ErrorAction Stop
            if ((Get-Item -LiteralPath $tmp).Length -eq 0) { throw 'Leere Datei empfangen.' }
            Move-Item -LiteralPath $tmp -Destination $Destination -Force
            return
        } catch {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            if ($attempt -eq $Retries) {
                throw "Download fehlgeschlagen nach $Retries Versuchen: $Url`n$($_.Exception.Message)"
            }
            Write-Warn2 "Versuch $attempt fehlgeschlagen, neuer Versuch in ${delay}s ..."
            Start-Sleep -Seconds $delay
            $delay = $delay * 2
        }
    }
}

function Get-LatestReShadeVersion {
    if ($ReShadeVersion) {
        Write-Info "ReShade-Version manuell vorgegeben: $ReShadeVersion"
        return $ReShadeVersion
    }
    try {
        $html = (Invoke-WebRequest -Uri 'https://reshade.me/' -UseBasicParsing -TimeoutSec 20 `
                                   -UserAgent 'Mozilla/5.0').Content
        $matchesFound = [regex]::Matches($html, 'ReShade_Setup_(\d+\.\d+\.\d+)\.exe')
        if ($matchesFound.Count -gt 0) {
            $versions = $matchesFound | ForEach-Object { [version]$_.Groups[1].Value }
            $newest = ($versions | Sort-Object -Descending)[0].ToString()
            Write-Ok "Aktuelle ReShade-Version von reshade.me: $newest"
            return $newest
        }
        Write-Warn2 'Versionsnummer auf reshade.me nicht gefunden.'
    } catch {
        Write-Warn2 "reshade.me nicht erreichbar: $($_.Exception.Message)"
    }
    Write-Warn2 "Fallback auf bekannte Version $Script:FallbackReShade"
    return $Script:FallbackReShade
}

function Get-ReShadeSetup {
    param([string] $Version)

    $file  = "ReShade_Setup_$Version.exe"
    $local = Join-Path $Script:CacheDir $file

    if (Test-Path -LiteralPath $local) {
        Write-Ok "ReShade-Setup aus Cache: $file"
    } else {
        if ($Repair) { throw "Repair-Modus, aber $file liegt nicht im Cache ($Script:CacheDir)." }
        $url = "https://reshade.me/downloads/$file"
        Write-Info "Lade $url"
        Invoke-Download -Url $url -Destination $local
        Write-Ok "Heruntergeladen: $file"
    }

    $hash = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash
    Write-Info "SHA256: $hash"
    if ($ExpectedHash -and $hash -ne $ExpectedHash.ToUpperInvariant()) {
        Remove-Item -LiteralPath $local -Force
        throw "SHA256 stimmt nicht mit -ExpectedHash ueberein. Datei wurde geloescht."
    }

    # Signaturpruefung: ReShade-Setups sind authenticode-signiert.
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $local
        if ($sig.Status -eq 'Valid') {
            Write-Ok "Signatur gueltig: $($sig.SignerCertificate.Subject)"
        } else {
            Write-Warn2 "Signaturstatus: $($sig.Status). Datei stammt evtl. nicht von reshade.me."
            if (-not $Force -and -not $Yes) {
                throw 'Abbruch wegen ungueltiger Signatur. Mit -Force ueberspringen.'
            }
        }
    } catch [System.Management.Automation.RuntimeException] {
        throw
    } catch {
        Write-Warn2 'Signatur konnte nicht geprueft werden.'
    }

    return $local
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

function Install-ReShadeRuntime {
    <#
      Nutzt den offiziellen Headless-Modus des ReShade-Setups:
          ReShade_Setup.exe "<spiel.exe>" --api dxgi --headless
      dxgi statt d3d11, weil Roblox ueber DXGI praesentiert - eine d3d11.dll
      wuerde zwar existieren, aber nie geladen werden.
    #>
    param(
        [Parameter(Mandatory)][object] $Target,
        [string] $SetupExe
    )

    $dll = Join-Path $Target.Dir 'dxgi.dll'
    $cachedDll = Join-Path $Script:CacheDir 'dxgi.dll'

    if ($Repair) {
        if (-not (Test-Path -LiteralPath $cachedDll)) {
            throw "Repair-Modus, aber keine dxgi.dll im Cache ($cachedDll). Einmal ohne -Repair laufen lassen."
        }
        Copy-Item -LiteralPath $cachedDll -Destination $dll -Force
        Write-Ok 'dxgi.dll aus Cache wiederhergestellt.'
        return 'dxgi.dll'
    }

    if ([string]::IsNullOrWhiteSpace($SetupExe)) {
        throw 'Interner Fehler: kein ReShade-Setup verfuegbar.'
    }

    Write-Info 'Starte ReShade-Setup im Headless-Modus ...'
    $argLine = '"{0}" --api dxgi --headless' -f $Target.Exe
    $proc = Start-Process -FilePath $SetupExe -ArgumentList $argLine -Wait -PassThru

    if (-not (Test-Path -LiteralPath $dll)) {
        throw @"
Das ReShade-Setup hat keine dxgi.dll angelegt (Exit-Code $($proc.ExitCode)).
Manueller Weg:
  1. $SetupExe doppelklicken
  2. "Select game" -> $($Target.Exe)
  3. Rendering-API "DirectX 10/11/12" waehlen
  4. Danach dieses Script erneut mit -Repair starten
"@
    }

    $ver = (Get-Item -LiteralPath $dll).VersionInfo.FileVersion
    Write-Ok "dxgi.dll installiert (Dateiversion $ver)"

    # Fuer -Repair nach dem naechsten Roblox-Update aufheben
    Copy-Item -LiteralPath $dll -Destination $cachedDll -Force
    return 'dxgi.dll'
}

function Sync-ShaderCache {
    if ($Repair) {
        if (-not (Test-Path -LiteralPath $Script:ShaderCacheDir)) {
            throw "Repair-Modus, aber kein Shader-Cache unter $Script:ShaderCacheDir."
        }
        Write-Ok 'Shader aus Cache (kein Netzwerkzugriff).'
        return
    }

    if (-not (Test-Path -LiteralPath $Script:ShaderCacheDir)) {
        New-Item -ItemType Directory -Path $Script:ShaderCacheDir -Force | Out-Null
    }

    $total = ($Script:ShaderSources | ForEach-Object { $_.Files.Count } | Measure-Object -Sum).Sum
    $i = 0
    foreach ($src in $Script:ShaderSources) {
        foreach ($f in $src.Files) {
            $i++
            $dest = Join-Path $Script:ShaderCacheDir $f
            $url  = 'https://raw.githubusercontent.com/{0}/{1}/{2}/{3}' -f $src.Repo, $src.Ref, $src.Path, $f
            if ((Test-Path -LiteralPath $dest) -and -not $Force) {
                Write-Info ("[{0}/{1}] {2} (Cache)" -f $i, $total, $f)
                continue
            }
            Write-Info ("[{0}/{1}] {2} <- {3}@{4}" -f $i, $total, $f, $src.Repo, $src.Ref)
            Invoke-Download -Url $url -Destination $dest
        }
    }
    Write-Ok "$total Shader-Dateien bereit."
}

function Install-Shaders {
    param([Parameter(Mandatory)][object] $Target)

    $shaderDir  = Join-Path $Target.Dir 'reshade-shaders\Shaders'
    $textureDir = Join-Path $Target.Dir 'reshade-shaders\Textures'
    foreach ($d in @($shaderDir, $textureDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # Nur .fx/.fxh kopieren - ein abgebrochener Download hinterlaesst zwar
    # nichts, aber im Shader-Ordner hat trotzdem nichts anderes zu suchen.
    $written = New-Object System.Collections.Generic.List[string]
    $cached = @(Get-ChildItem -LiteralPath $Script:ShaderCacheDir -File |
                Where-Object { $_.Extension -in @('.fx', '.fxh') })
    if ($cached.Count -eq 0) { throw "Keine Shader im Cache: $Script:ShaderCacheDir" }
    foreach ($file in $cached) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $shaderDir $file.Name) -Force
        $written.Add("reshade-shaders\Shaders\$($file.Name)")
    }
    Write-Ok "$($written.Count) Shader nach reshade-shaders\Shaders kopiert."
    return $written
}

function Install-Presets {
    param([Parameter(Mandatory)][object] $Target)

    $presetSrc = Join-Path $Script:ScriptRoot 'presets'
    if (-not (Test-Path -LiteralPath $presetSrc)) {
        throw "Preset-Ordner nicht gefunden: $presetSrc"
    }

    $written = New-Object System.Collections.Generic.List[string]
    foreach ($p in (Get-ChildItem -LiteralPath $presetSrc -Filter 'RoGlow-*.ini' -File)) {
        Copy-Item -LiteralPath $p.FullName -Destination (Join-Path $Target.Dir $p.Name) -Force
        $written.Add($p.Name)
    }
    Write-Ok "$($written.Count) Presets kopiert (aktiv: RoGlow-$Preset.ini)."
    return $written
}

function Write-ReShadeIni {
    param([Parameter(Mandatory)][object] $Target)

    $toggleVk = $Script:VirtualKeys[$ToggleKey.ToUpperInvariant()]
    $iniPath  = Join-Path $Target.Dir 'ReShade.ini'

    # PerformanceMode=1 backt die Uniform-Werte als Konstanten in die Shader
    # und spart den Uniform-Update-Pfad pro Frame. Kostet nichts optisch, ist
    # aber genau die Art Gratis-Performance, die man mitnehmen sollte.
    # Live-Regler funktionieren erst wieder, wenn man den Haken in der
    # ReShade-UI entfernt.
    $ini = @"
; Erzeugt von $Script:ToolName $Script:ToolVersion - nicht von Hand editieren,
; Aenderungen gehen beim naechsten Lauf von Install-RoGlow.ps1 verloren.

[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\**
TextureSearchPaths=.\reshade-shaders\Textures\**
PresetPath=.\RoGlow-$Preset.ini
PerformanceMode=1
PresetTransitionDuration=1000
NoDebugInfo=0
NoEffectCache=0
NoReloadOnInit=0

[INPUT]
; $ToggleKey schaltet alle Effekte an/aus
KeyEffects=$toggleVk,0,0,0
; Pos1/Home oeffnet das ReShade-Menue
KeyOverlay=36,0,0,0
; F9 laedt die Shader neu (nach Datei-Aenderungen)
KeyReload=120,0,0,0
; F6/F7 blaettern durch RoGlow-Performance / -Balanced / -Quality
KeyPreviousPreset=117,0,0,0
KeyNextPreset=118,0,0,0
KeyScreenshot=44,0,0,0
InputProcessing=2

[SCREENSHOT]
SavePath=%userprofile%\Pictures\RoGlow
FileFormat=1
SaveBeforeShot=0
SaveOverlayShot=0

[OVERLAY]
; Tutorial ueberspringen - das Preset ist bereits eingerichtet
TutorialProgress=4
ShowClock=0
ShowFPS=0
ShowFrameTime=0
ShowScreenshotMessage=1

[DEPTH]
; Roblox raeumt den Depth-Buffer vor dem Present auf. Ohne diese Kopie
; bekommen MXAO/SSR/DoF nichts zu sehen.
DepthCopyBeforeClears=1
DepthCopyAtClearIndex=0
UseAspectRatioHeuristics=1

[APP]
ForceVsync=0
ForceWindowed=0
ForceFullscreen=0
"@

    Set-Content -LiteralPath $iniPath -Value $ini -Encoding ASCII -Force
    Write-Ok "ReShade.ini geschrieben - Toggle-Hotkey: $ToggleKey"
    return 'ReShade.ini'
}

function Write-Manifest {
    param(
        [Parameter(Mandatory)][object] $Target,
        [Parameter(Mandatory)][string[]] $Files,
        [Parameter(Mandatory)][string] $ReShadeVer
    )

    $manifest = [ordered]@{
        tool            = $Script:ToolName
        toolVersion     = $Script:ToolVersion
        installedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        reshadeVersion  = $ReShadeVer
        preset          = $Preset
        toggleKey       = $ToggleKey
        targetDir       = $Target.Dir
        robloxVersion   = $Target.Version
        detectedVia     = $Target.Source
        files           = @($Files)
        directories     = @('reshade-shaders\Shaders', 'reshade-shaders\Textures', 'reshade-shaders')
    }

    $path = Join-Path $Target.Dir $Script:ManifestName
    ($manifest | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8 -Force
    Write-Ok "Manifest: $Script:ManifestName ($($Files.Count) Dateien protokolliert)"

    # Globaler Index, damit der Uninstaller alle Ziele findet
    $index = @()
    if (Test-Path -LiteralPath $Script:InstallIndex) {
        try { $index = @(Get-Content -LiteralPath $Script:InstallIndex -Raw | ConvertFrom-Json) } catch { $index = @() }
    }
    $index = @($index | Where-Object { $_ -and $_ -ne $Target.Dir })
    $index += $Target.Dir
    ($index | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $Script:InstallIndex -Encoding UTF8 -Force
}

# ---------------------------------------------------------------------------
# Log-Auswertung
# ---------------------------------------------------------------------------

function Invoke-CheckLog {
    param([object[]] $Targets)

    $any = $false
    foreach ($t in $Targets) {
        $log = Join-Path $t.Dir 'ReShade.log'
        Write-Step "Log-Pruefung: $($t.Version)"

        if (-not (Test-Path -LiteralPath $log)) {
            Write-Warn2 'Keine ReShade.log vorhanden. Starte Roblox einmal und versuche es erneut.'
            Write-Info  "Erwartet unter: $log"
            continue
        }
        $any = $true

        # @() erzwingen: eine einzeilige Logdatei waere sonst ein String und
        # .Count wuerde unter StrictMode werfen.
        $lines   = @(Get-Content -LiteralPath $log)
        $loaded  = @($lines | Select-String -Pattern 'Initialized|Loading config|ReShade \d+\.\d+' -SimpleMatch:$false)
        $errors  = @($lines | Select-String -Pattern 'error|failed to compile|Failed to create' -SimpleMatch:$false)
        $effects = @($lines | Select-String -Pattern 'Successfully compiled' -SimpleMatch:$false)

        Write-Info "Zeilen gesamt: $($lines.Count)"
        if ($loaded.Count -gt 0) {
            Write-Ok 'ReShade wurde in den Prozess geladen.'
        } else {
            Write-Fail 'Kein Initialisierungseintrag - dxgi.dll wurde offenbar nicht geladen.'
            Write-Info 'Pruefen: liegt dxgi.dll direkt neben RobloxPlayerBeta.exe im AKTUELLEN version-Ordner?'
        }

        Write-Info "Erfolgreich kompilierte Effekte: $($effects.Count)"
        if ($errors.Count -gt 0) {
            Write-Warn2 "$($errors.Count) Fehlerzeilen - die ersten 10:"
            $errors | Select-Object -First 10 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
        }

        if ($loaded.Count -gt 0 -and $effects.Count -gt 0) {
            Write-Host ''
            Write-Warn2 'ReShade laedt und kompiliert - wenn im Spiel trotzdem nichts sichtbar ist,'
            Write-Warn2 'ist das das erwartete Hyperion-Verhalten und kein Fehler dieses Tools.'
            Write-Info  'Siehe Apply-FastFlags.ps1 fuer den Weg ohne Injection.'
        }
    }
    if (-not $any) { Write-Warn2 'Keine einzige ReShade.log gefunden.' }
}

# ---------------------------------------------------------------------------
# Hauptablauf
# ---------------------------------------------------------------------------

function Confirm-Risk {
    if ($Yes) { return }

    Write-Host ''
    Write-Host '  ACHTUNG - bitte lesen' -ForegroundColor Yellow
    Write-Host '  -------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Roblox schuetzt den Player mit Hyperion (Byfron). Hyperion' -ForegroundColor Yellow
    Write-Host '  unterdrueckt das ReShade-Overlay seit 2023. Die dxgi.dll wird' -ForegroundColor Yellow
    Write-Host '  geladen, Menue und Effekte bleiben aber sehr wahrscheinlich' -ForegroundColor Yellow
    Write-Host '  unsichtbar. Es existiert keine Whitelist.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Dieses Script umgeht Hyperion nicht und versucht es nicht.' -ForegroundColor Yellow
    Write-Host '  Fremde DLLs neben dem Client sind ein Eingriff, den Roblox in' -ForegroundColor Yellow
    Write-Host '  seinen Nutzungsbedingungen untersagen kann - das Risiko fuer' -ForegroundColor Yellow
    Write-Host '  deinen Account traegst du.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Alles wieder loswerden:  .\Uninstall-RoGlow.ps1' -ForegroundColor Gray
    Write-Host '  Weg ohne Injection:      .\Apply-FastFlags.ps1' -ForegroundColor Gray
    Write-Host ''

    $answer = Read-Host '  Fortfahren? [j/N]'
    if ($answer -notmatch '^(j|ja|y|yes)$') {
        Write-Host '  Abgebrochen.' -ForegroundColor Gray
        exit 1
    }
}

function Main {
    Show-Banner
    Initialize-Tls

    foreach ($d in @($Script:StateDir, $Script:CacheDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # --- Ziel bestimmen ---
    Write-Step 'Suche Roblox ...'
    if ($RobloxPath) {
        $exe = $RobloxPath
        if (Test-Path -LiteralPath $RobloxPath -PathType Container) {
            $exe = Join-Path $RobloxPath 'RobloxPlayerBeta.exe'
        }
        $c = New-RobloxCandidate -ExePath $exe -Source 'manuell (-RobloxPath)'
        if ($null -eq $c) { throw "Kein gueltiger RobloxPlayerBeta.exe-Pfad: $RobloxPath" }
        $targets = @($c)
    } else {
        # @() erzwingen: bei genau einem Treffer wuerde PowerShell das Array
        # sonst zu einem Einzelobjekt aufloesen und .Count schlaegt fehl.
        $all = @(Resolve-RobloxPlayer)
        if ($all.Count -eq 0) {
            throw @"
Roblox wurde nicht gefunden.
Gesucht wurde in Registry (Environments, Protocol-Handler, Uninstall) und unter:
  %LOCALAPPDATA%\Roblox\Versions\version-*
  %ProgramFiles%\Roblox\Versions\version-*
Starte Roblox einmal, damit es sich installiert, oder gib den Pfad direkt an:
  .\Install-RoGlow.ps1 -RobloxPath "C:\...\version-xxxx"
"@
        }
        foreach ($c in $all) { Write-Info ("{0}  [{1}]" -f $c.Version, $c.Source) }
        if ($AllVersions) {
            $targets = $all
            Write-Ok "$($all.Count) Version(en) gefunden - installiere in alle."
        } else {
            $targets = @($all[0])
            Write-Ok "Neueste Version: $($all[0].Version)  (Erkennung: $($all[0].Source))"
            if ($all.Count -gt 1) { Write-Info "$($all.Count - 1) weitere Version(en) vorhanden - mit -AllVersions einbeziehen." }
        }
    }

    # --- Nur Log pruefen? ---
    if ($CheckLog) { Invoke-CheckLog -Targets $targets; return }

    # --- Laeuft Roblox? ---
    $running = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0 -and -not $Force) {
        throw 'Roblox laeuft gerade - dxgi.dll waere gesperrt. Bitte Roblox schliessen (oder -Force).'
    }

    Confirm-Risk

    # --- ReShade holen ---
    $reshadeVer = $null
    $setup = $null
    if (-not $Repair) {
        Write-Step 'Ermittle ReShade-Version ...'
        $reshadeVer = Get-LatestReShadeVersion
        Write-Step 'Hole ReShade-Setup ...'
        $setup = Get-ReShadeSetup -Version $reshadeVer
    } else {
        $reshadeVer = 'aus Cache'
        Write-Step 'Repair-Modus: kein Netzwerkzugriff.'
    }

    # --- Shader holen ---
    Write-Step 'Hole Shader ...'
    Sync-ShaderCache

    # --- Pro Ziel installieren ---
    foreach ($t in $targets) {
        Write-Host ''
        Write-Step "Installiere nach $($t.Version)"
        Write-Info $t.Dir

        $files = New-Object System.Collections.Generic.List[string]

        $files.Add((Install-ReShadeRuntime -Target $t -SetupExe $setup))

        foreach ($f in (Install-Shaders -Target $t)) { $files.Add($f) }
        foreach ($f in (Install-Presets -Target $t)) { $files.Add($f) }
        $files.Add((Write-ReShadeIni -Target $t))

        Write-Manifest -Target $t -Files $files.ToArray() -ReShadeVer $reshadeVer
    }

    # --- Abschluss ---
    Write-Host ''
    Write-Host '  Fertig.' -ForegroundColor Green
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host "  Preset       : RoGlow-$Preset" -ForegroundColor White
    Write-Host "  Effekte an/aus: $ToggleKey" -ForegroundColor White
    Write-Host '  ReShade-Menue : Pos1 / Home' -ForegroundColor White
    Write-Host '  Preset wechseln: F6 / F7' -ForegroundColor White
    Write-Host '  Shader neu laden: F9' -ForegroundColor White
    Write-Host ''
    Write-Host '  Naechste Schritte:' -ForegroundColor Gray
    Write-Host '    1. Roblox starten und ein Spiel betreten' -ForegroundColor Gray
    Write-Host '    2. .\Install-RoGlow.ps1 -CheckLog    (hat ReShade geladen?)' -ForegroundColor Gray
    Write-Host '    3. Nach einem Roblox-Update: .\Install-RoGlow.ps1 -Repair' -ForegroundColor Gray
    Write-Host ''
    Write-Warn2 'Wenn im Spiel nichts sichtbar wird, ist das der erwartete'
    Write-Warn2 'Hyperion-Block - nicht ein Fehler der Installation.'
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
