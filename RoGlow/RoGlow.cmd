@echo off
REM ---------------------------------------------------------------------------
REM  RoGlow - Doppelklick-Starter
REM  Umgeht die PowerShell-Ausfuehrungsrichtlinie nur fuer diesen einen Aufruf;
REM  es wird nichts an den Systemeinstellungen geaendert.
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

echo.
echo   RoGlow
echo   ==============================================================
echo     1  Installieren            (ReShade + Preset, Standard)
echo     2  Reparieren              (nach einem Roblox-Update)
echo     3  Pruefen                 (hat ReShade geladen?)
echo     4  FastFlags setzen        (ohne Injection - funktioniert heute)
echo     5  Deinstallieren
echo     6  Presets testen
echo     0  Abbrechen
echo   ==============================================================
echo.

set "choice="
set /p choice="  Auswahl: "

if "%choice%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1"
if "%choice%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1" -Repair
if "%choice%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1" -CheckLog
if "%choice%"=="4" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Apply-FastFlags.ps1"
if "%choice%"=="5" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Uninstall-RoGlow.ps1"
if "%choice%"=="6" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Test-RoGlowPreset.ps1" -ShowTable
if "%choice%"=="0" goto :end

echo.
pause
:end
endlocal
