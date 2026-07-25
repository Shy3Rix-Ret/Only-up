#Requires -Version 5.1
<#
.SYNOPSIS
    Prueft die RoGlow-Presets gegen die tatsaechlich installierten Shader.

.DESCRIPTION
    Ein Preset ist eine Textdatei mit Namen darin. Wenn ein Shader-Repo einen
    Parameter umbenennt oder eine Technique anders heisst als erwartet, faellt
    das im Spiel nur dadurch auf, dass ein Effekt stumm nichts tut - ReShade
    ignoriert unbekannte Schluessel kommentarlos.

    Dieses Script liest die .fx-Dateien, zieht Technique-Namen, Uniform-Namen
    und deren ui_min/ui_max heraus und prueft:

      1. Jede aktive Technique existiert in der genannten Datei.
      2. Jede aktive Technique steht auch in TechniqueSorting.
      3. Jeder Parameter in jedem [Abschnitt] existiert als Uniform.
      4. Jeder Wert liegt innerhalb der Reglergrenzen des Shaders.
      5. Bericht, wo jeder Wert prozentual auf seinem Regler sitzt -
         damit sichtbar wird, ob ein Preset "alles auf Maximum" faehrt.

    Nach jedem Roblox-Update oder nach Install-RoGlow.ps1 ausfuehrbar.

.PARAMETER ShaderPath
    Ordner mit den .fx-Dateien. Default: der RoGlow-Cache
    (%LOCALAPPDATA%\RoGlow\cache\Shaders).

.PARAMETER PresetPath
    Ordner mit den RoGlow-*.ini. Default: .\presets neben diesem Script.

.PARAMETER ShowTable
    Gibt zusaetzlich die Reglerposition jedes aktiven Parameters aus.

.EXAMPLE
    .\Test-RoGlowPreset.ps1
.EXAMPLE
    .\Test-RoGlowPreset.ps1 -ShowTable
.EXAMPLE
    .\Test-RoGlowPreset.ps1 -ShaderPath "$env:LOCALAPPDATA\Roblox\Versions\version-abc\reshade-shaders\Shaders"
#>
[CmdletBinding()]
param(
    [string] $ShaderPath,
    [string] $PresetPath,
    [switch] $ShowTable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ShaderPath) { $ShaderPath = Join-Path $env:LOCALAPPDATA 'RoGlow\cache\Shaders' }
if (-not $PresetPath) { $PresetPath = Join-Path $root 'presets' }

function Write-Ok   { param([string]$m) Write-Host "  OK   $m" -ForegroundColor Green }
function Write-Bad  { param([string]$m) Write-Host "  X    $m" -ForegroundColor Red }
function Write-Note { param([string]$m) Write-Host "  ~    $m" -ForegroundColor Yellow }
function Write-Head { param([string]$m) Write-Host "`n$m" -ForegroundColor Cyan }

function Get-FirstNumber {
    param([string] $Text)
    if ($Text -match '-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?') { return [double]$Matches[0] }
    return $null
}

function Read-ShaderMetadata {
    <# Zieht Techniques und Uniforms samt Reglergrenzen aus einer .fx-Datei. #>
    param([string] $File)

    $src = Get-Content -LiteralPath $File -Raw

    $tech = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($src, '(?m)^\s*technique\s+([A-Za-z_]\w*)')) {
        [void]$tech.Add($m.Groups[1].Value)
    }

    $uni = @{}
    # uniform <typ> <name> < ...Annotationen... > = default;
    $pattern = 'uniform\s+\w+\s+([A-Za-z_]\w*)\s*<(.*?)>\s*(?:=\s*[^;]+)?;'
    foreach ($m in [regex]::Matches($src, $pattern, 'Singleline')) {
        $name = $m.Groups[1].Value
        $ann  = $m.Groups[2].Value

        $mn = $null; $mx = $null; $items = $null
        if ($ann -match 'ui_min\s*=\s*([^;]+);') { $mn = Get-FirstNumber $Matches[1] }
        if ($ann -match 'ui_max\s*=\s*([^;]+);') { $mx = Get-FirstNumber $Matches[1] }
        if ($ann -match 'ui_items\s*=\s*"(.*?)"\s*;') {
            $items = @($Matches[1] -split '\\0' | Where-Object { $_.Trim() }).Count
        }

        # Manche Shader deklarieren denselben Uniform in mehreren #if-Zweigen.
        # Dann gilt der weiteste Bereich, sonst melden wir falsche Fehler.
        if ($uni.ContainsKey($name)) {
            $old = $uni[$name]
            if ($null -ne $mn -and $null -ne $old.Min) { $mn = [Math]::Min($mn, $old.Min) }
            if ($null -ne $mx -and $null -ne $old.Max) { $mx = [Math]::Max($mx, $old.Max) }
            if ($null -eq $items) { $items = $old.Items }
        }
        $uni[$name] = [pscustomobject]@{ Min = $mn; Max = $mx; Items = $items }
    }

    return [pscustomobject]@{ Techniques = $tech; Uniforms = $uni }
}

function Read-Preset {
    param([string] $File)

    $techniques = @(); $sorting = @()
    $sections = [ordered]@{}
    $cur = $null

    foreach ($raw in (Get-Content -LiteralPath $File)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $cur = $line.Substring(1, $line.Length - 2)
            if (-not $sections.Contains($cur)) { $sections[$cur] = [ordered]@{} }
            continue
        }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $k = $line.Substring(0, $idx); $v = $line.Substring($idx + 1)

        if ($null -eq $cur) {
            switch ($k) {
                'Techniques'       { $techniques = @($v -split ',' | Where-Object { $_ }) }
                'TechniqueSorting' { $sorting    = @($v -split ',' | Where-Object { $_ }) }
            }
        } else {
            $sections[$cur][$k] = $v
        }
    }
    return [pscustomobject]@{ Techniques = $techniques; Sorting = $sorting; Sections = $sections }
}

# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  RoGlow Preset-Pruefung' -ForegroundColor White
Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Shader : $ShaderPath" -ForegroundColor Gray
Write-Host "  Presets: $PresetPath" -ForegroundColor Gray

if (-not (Test-Path -LiteralPath $ShaderPath -PathType Container)) {
    Write-Bad "Shader-Ordner nicht gefunden. Erst Install-RoGlow.ps1 ausfuehren."
    exit 1
}
if (-not (Test-Path -LiteralPath $PresetPath -PathType Container)) {
    Write-Bad "Preset-Ordner nicht gefunden: $PresetPath"
    exit 1
}

$shaderFiles = @(Get-ChildItem -LiteralPath $ShaderPath -Filter '*.fx' -File)
if ($shaderFiles.Count -eq 0) { Write-Bad 'Keine .fx-Dateien gefunden.'; exit 1 }

$meta = @{}
foreach ($f in $shaderFiles) { $meta[$f.Name] = Read-ShaderMetadata -File $f.FullName }
Write-Ok "$($shaderFiles.Count) Shader eingelesen."

$presets = @(Get-ChildItem -LiteralPath $PresetPath -Filter 'RoGlow-*.ini' -File)
if ($presets.Count -eq 0) { Write-Bad 'Keine RoGlow-*.ini gefunden.'; exit 1 }

$errors = New-Object System.Collections.Generic.List[string]
$notes  = New-Object System.Collections.Generic.List[string]
$rows   = New-Object System.Collections.Generic.List[object]
$valuesChecked = 0

foreach ($pf in $presets) {
    Write-Head "[$($pf.Name)]"
    $p = Read-Preset -File $pf.FullName
    $activeFiles = @()

    # --- Techniques ---
    foreach ($t in $p.Techniques) {
        if ($t -notmatch '^(.+)@(.+)$') { $errors.Add("$($pf.Name): Technique ohne @Datei: $t"); continue }
        $tn = $Matches[1]; $fn = $Matches[2]
        $activeFiles += $fn

        if (-not $meta.ContainsKey($fn)) {
            $errors.Add("$($pf.Name): aktive Technique '$t' - Datei $fn ist nicht installiert")
        } elseif (-not $meta[$fn].Techniques.Contains($tn)) {
            $have = ($meta[$fn].Techniques | Sort-Object) -join ', '
            $errors.Add("$($pf.Name): Technique '$tn' existiert nicht in $fn (vorhanden: $have)")
        }
        if ($p.Sorting -notcontains $t) {
            $errors.Add("$($pf.Name): aktive Technique $t fehlt in TechniqueSorting")
        }
    }
    Write-Ok "$($p.Techniques.Count) aktive Technique(s) geprueft."

    # --- Parameter + Wertebereiche ---
    foreach ($sec in $p.Sections.Keys) {
        if (-not $meta.ContainsKey($sec)) {
            $notes.Add("$($pf.Name): Abschnitt [$sec] gehoert zu keiner installierten Datei")
            continue
        }
        $uniforms = $meta[$sec].Uniforms
        foreach ($k in $p.Sections[$sec].Keys) {
            if (-not $uniforms.ContainsKey($k)) {
                $errors.Add("$($pf.Name): [$sec] unbekannter Parameter '$k'")
                continue
            }
            $u = $uniforms[$k]
            $valuesChecked++

            foreach ($part in ($p.Sections[$sec][$k] -split ',')) {
                $val = Get-FirstNumber $part
                if ($null -eq $val) { continue }
                if ($null -ne $u.Min -and $val -lt ($u.Min - 1e-9)) {
                    $errors.Add("$($pf.Name): [$sec] $k = $val liegt unter ui_min $($u.Min)")
                }
                if ($null -ne $u.Max -and $val -gt ($u.Max + 1e-9)) {
                    $errors.Add("$($pf.Name): [$sec] $k = $val liegt ueber ui_max $($u.Max)")
                }
                if ($null -ne $u.Items -and $val -gt ($u.Items - 1)) {
                    $errors.Add("$($pf.Name): [$sec] $k = $val, aber nur $($u.Items) Auswahleintraege (0..$($u.Items - 1))")
                }
            }

            # Reglerposition nur fuer aktive Effekte protokollieren
            if ($activeFiles -contains $sec -and $null -ne $u.Min -and $null -ne $u.Max -and $u.Max -gt $u.Min) {
                $val = Get-FirstNumber $p.Sections[$sec][$k]
                if ($null -ne $val) {
                    $frac = ($val - $u.Min) / ($u.Max - $u.Min)
                    $rows.Add([pscustomobject]@{
                        Preset = $pf.BaseName; Shader = $sec; Parameter = $k
                        Wert = $val; Bereich = "$($u.Min)..$($u.Max)"; Regler = [Math]::Round($frac * 100)
                    })
                }
            }
        }
    }
    Write-Ok "Parameter und Wertebereiche geprueft."
}

if ($ShowTable -and $rows.Count -gt 0) {
    Write-Head 'Reglerposition der aktiven Parameter'
    $rows | Sort-Object Preset, Shader, Parameter |
        Format-Table Preset, Shader, Parameter, Wert, Bereich, @{n='Regler%';e={$_.Regler}} -AutoSize |
        Out-String -Width 160 | Write-Host
}

Write-Host ''
Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Gepruefte Parameterwerte: $valuesChecked" -ForegroundColor White

if ($rows.Count -gt 0) {
    $avg = [Math]::Round((($rows | Measure-Object -Property Regler -Average).Average))
    Write-Host "  Durchschnittliche Reglerposition aktiver Effekte: $avg %" -ForegroundColor White
    $hot = @($rows | Where-Object { $_.Regler -gt 85 })
    if ($hot.Count -gt 0) {
        Write-Host ''
        Write-Note "$($hot.Count) Parameter ueber 85% des Reglers:"
        foreach ($h in $hot) { Write-Note ("  {0} [{1}] {2} = {3} ({4}%)" -f $h.Preset, $h.Shader, $h.Parameter, $h.Wert, $h.Regler) }
    }
}

foreach ($n in ($notes | Sort-Object -Unique)) { Write-Note $n }

if ($errors.Count -gt 0) {
    Write-Host ''
    foreach ($e in ($errors | Sort-Object -Unique)) { Write-Bad $e }
    Write-Host ''
    Write-Host "  FEHLGESCHLAGEN - $($errors.Count) Problem(e)." -ForegroundColor Red
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host '  Bestanden: alle Technique-Namen und Parameter existieren,' -ForegroundColor Green
Write-Host '  alle Werte liegen innerhalb der Shader-Grenzen.' -ForegroundColor Green
Write-Host ''
