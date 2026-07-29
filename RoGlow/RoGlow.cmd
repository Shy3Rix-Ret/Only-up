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
echo     1  ReShade in STUDIO       (Effekte werden hier sichtbar)
echo     2  ReShade in Player+Studio
echo     3  Reparieren              (nach einem Roblox-Update)
echo     4  Pruefen                 (hat ReShade geladen?)
echo     5  FastFlags setzen        (Player-Grafik ohne Injection)
echo     6  FastFlags pruefen       (welche wirken noch? schreibt nichts)
echo     7  FastFlags entfernen
echo     8  ReShade deinstallieren
echo     9  Presets testen
echo     0  Abbrechen
echo   ==============================================================
echo.

set "choice="
set /p choice="  Auswahl: "

if "%choice%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1" -Target Studio
if "%choice%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1" -Target Both
if "%choice%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1" -Repair
if "%choice%"=="4" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Install-RoGlow.ps1" -CheckLog
if "%choice%"=="5" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Apply-FastFlags.ps1"
if "%choice%"=="6" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Apply-FastFlags.ps1" -Audit
if "%choice%"=="7" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Apply-FastFlags.ps1" -Remove
if "%choice%"=="8" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Uninstall-RoGlow.ps1"
if "%choice%"=="9" powershell -NoProfile -ExecutionPolicy Bypass -File ".\Test-RoGlowPreset.ps1" -ShowTable
if "%choice%"=="0" goto :end

echo.
pause
:end
endlocal
