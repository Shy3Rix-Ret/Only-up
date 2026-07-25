# RoGlow

ReShade-Installer und abgestimmtes Shader-Preset für den Roblox-Windows-Client
(DirectX 11). Findet Roblox automatisch, installiert die ReShade-Runtime als
`dxgi.dll`, lädt die Shader aus den offiziellen Upstream-Repos und legt ein
fertig konfiguriertes Preset samt Toggle-Hotkey ab.

---

## ⚠️ Zuerst lesen: der aktuelle Stand

**ReShade funktioniert im Roblox *Player* derzeit nicht.**

Roblox schützt den Client seit 2023 mit **Hyperion** (in der Community als
„Byfron" bekannt). Hyperion erkennt das ReShade-Overlay und unterdrückt es.
Der Ablauf in der Praxis: die `dxgi.dll` wird geladen, ReShade initialisiert
sich, die Shader kompilieren sauber — und im Spiel ist trotzdem weder das
Menü noch ein Effekt zu sehen.

Das ist kein Bug dieses Tools und lässt sich von außen nicht beheben. Der
RoShade-Autor (Zeal) hat Roblox um eine Whitelist für ReShades
Code-Signatur gebeten; das ist bis heute nicht passiert. Das Original-Repo
[`bituq/Roshade`](https://github.com/bituq/Roshade) ist seit **20.10.2023
archiviert**.

**Was dieses Tool deshalb ausdrücklich nicht tut:** Hyperion umgehen,
verstecken, patchen oder täuschen. Es installiert ReShade auf dem normalen,
vom ReShade-Setup selbst vorgesehenen Weg. Ob das Ergebnis sichtbar wird,
entscheidet allein Roblox.

**Risiko:** Eine fremde DLL neben dem Client ist ein Eingriff, den Roblox in
seinen Nutzungsbedingungen untersagen kann. Es sind keine Bannwellen wegen
ReShade dokumentiert — aber das ist keine Zusage. Das Risiko für deinen
Account trägst du.

### Was funktioniert

Zwei Wege, beide ohne Anti-Cheat-Konflikt:

| | Was du bekommst | |
|---|---|---|
| **Roblox Studio** | Das **komplette Preset**: Bloom, Reflexionen, Ambient Occlusion, Tonemapping, Schärfen. Studio ist ein Entwicklerwerkzeug und trägt keine Hyperion-Schicht. | `.\Install-RoGlow.ps1 -Target Studio` |
| **Player via FastFlags** | Maximales internes Qualitätslevel, MSAA, mehr Sichtweite. Kein Bloom, keine Reflexionen. | `.\Apply-FastFlags.ps1` |

Wenn du den „glossy" Look tatsächlich sehen willst, ist **Studio** der Weg.
Es ist kostenlos auf [create.roblox.com](https://create.roblox.com/) und
öffnet jedes Erlebnis, das man auch spielen kann — mit `F5` startest du
darin einen normalen Playtest.

---

## Inhalt

| Datei | Zweck |
|---|---|
| `Install-RoGlow.ps1` | Installer: Roblox finden, ReShade + Shader + Preset einrichten |
| `Uninstall-RoGlow.ps1` | Entfernt exakt die installierten Dateien wieder |
| `Apply-FastFlags.ps1` | Grafik-Verbesserung ohne Injection (funktioniert heute), inkl. `-Audit` |
| `Test-RoGlowPreset.ps1` | Prüft Presets gegen die echten Shader (Namen + Wertebereiche) |
| `RoGlow.cmd` | Doppelklick-Starter, umgeht die PowerShell-Ausführungsrichtlinie |
| `presets/RoGlow-Performance.ini` | ~0.5 ms — Laptop / iGPU |
| `presets/RoGlow-Balanced.ini` | ~3–5 ms — Standard, 1080p Mittelklasse |
| `presets/RoGlow-Quality.ini` | ~8–11 ms — RTX 4070+, für Screenshots |
| `config/fastflags-quality.json` | Das Quality-Profil als reine JSON zum Import in Bloxstrap |

---

## Installation

Voraussetzung: Windows 10/11, PowerShell 5.1 (ist ab Werk dabei), Roblox
mindestens einmal gestartet. **Keine Adminrechte nötig** — es wird nur in dein
eigenes Benutzerprofil geschrieben.

### Der einfache Weg

Roblox schließen, dann `RoGlow.cmd` doppelklicken. Punkt **1** ist die
Studio-Installation — die, bei der du etwas siehst.

### Der Weg über PowerShell

```powershell
cd <Ordner mit RoGlow>
powershell -ExecutionPolicy Bypass -File .\Install-RoGlow.ps1 -Target Studio
```

`-Target` steuert, wohin installiert wird:

| Wert | Wirkung |
|---|---|
| `Studio` | Nur Roblox Studio. Effekte sind sichtbar. Keine Rückfrage, kein Hyperion. |
| `Player` | Nur der Player. Korrekt installiert, Sichtbarkeit unwahrscheinlich. |
| `Both` | Beides (Default). Pro Anwendung wird die jeweils neueste Version genommen. |

Nützliche Schalter:

```powershell
.\Install-RoGlow.ps1 -Target Studio -Preset Quality   # Studio + starkes Preset
.\Install-RoGlow.ps1 -Preset Performance             # leichteres Preset
.\Install-RoGlow.ps1 -ToggleKey F7                   # anderer Toggle-Hotkey
.\Install-RoGlow.ps1 -AllVersions                    # in alle version-* Ordner
.\Install-RoGlow.ps1 -RobloxPath "C:\...\version-abc123"   # Pfad manuell
.\Install-RoGlow.ps1 -Repair                         # aus Cache, ohne Netzwerk
.\Install-RoGlow.ps1 -CheckLog                       # hat ReShade geladen?
```

### Was dabei passiert

1. **Roblox finden** — in dieser Reihenfolge, weil die Verlässlichkeit abnimmt:
   1. laufender `RobloxPlayerBeta`-Prozess (kann nicht falsch sein)
   2. `HKCU\Software\ROBLOX Corporation\Environments\roblox-player` → `clientExe`
   3. Protocol-Handler `HKCU\Software\Classes\roblox-player\shell\open\command`
   4. Uninstall-Eintrag in der Registry
   5. Dateisystem: `%LOCALAPPDATA%\Roblox\Versions\version-*`, dazu
      Bloxstrap-, Fishstrap- und Program-Files-Pfade

   Ist ein Bootstrapper (Bloxstrap & Co.) im Protocol-Handler eingetragen,
   wird das erkannt und übersprungen — der Dateiscan findet die echte
   `RobloxPlayerBeta.exe` trotzdem. Microsoft-Store-Installationen unter
   `WindowsApps` werden bewusst ausgelassen: der Ordner ist
   schreibgeschützt und signaturgeprüft.

2. **ReShade holen** — die aktuelle Versionsnummer wird von `reshade.me`
   gelesen (Fallback: 6.7.3, Stand 28.02.2026). Die Datei wird per SHA256
   protokolliert und ihre Authenticode-Signatur geprüft; bei ungültiger
   Signatur bricht der Installer ab.

3. **Als `dxgi.dll` installieren** — über den offiziellen Headless-Modus:
   `ReShade_Setup.exe "<pfad>\RobloxPlayerBeta.exe" --api dxgi --headless`

   **Warum `dxgi.dll` und nicht `d3d11.dll`:** Roblox erzeugt seine
   Swapchain über DXGI. Windows lädt eine Proxy-DLL nur, wenn der Prozess
   sie auch tatsächlich anfordert — eine `d3d11.dll` läge zwar im Ordner,
   würde aber nie geladen. Das ist der klassische Fehler in alten
   Anleitungen.

4. **Shader laden** — 19 Dateien, direkt von den Upstream-Repos
   (siehe [Shader-Quellen](#shader-quellen-und-lizenzen)). Nichts wird in
   diesem Repo mitgeliefert, damit keine Lizenz verletzt wird und du immer
   die gepflegte Fassung bekommst.

5. **Preset + `ReShade.ini` schreiben**, inklusive Hotkeys.

6. **Manifest schreiben** — `roglow-manifest.json` listet jede geschriebene
   Datei. Der Uninstaller entfernt exakt diese und nichts anderes.

---

## Roblox Studio benutzen

Der Ablauf, wenn du die Effekte sehen willst:

1. `.\Install-RoGlow.ps1 -Target Studio`
2. Roblox Studio starten und ein Erlebnis öffnen
3. **Pos1 / Home** drücken — das ReShade-Menü muss erscheinen. Tut es das,
   funktioniert alles.
4. **F5** startet den Playtest. Jetzt siehst du das Erlebnis wie im Spiel,
   inklusive Preset.
5. **F8** schaltet die Effekte an und aus — so vergleichst du direkt.

**Warum Studio funktioniert und der Player nicht:** Hyperion ist die
Anti-Tamper-Schicht des *Players*. Studio ist Roblox' Entwicklerwerkzeug für
Creator und trägt diese Schicht nicht. Es ist derselbe Renderer, dieselbe
DirectX-11-Ausgabe, dasselbe Preset — nur ohne die Sperre. Dieselbe Trennung
gilt bei den FastFlags: die 18er-Allowlist betrifft den Player, Studio behält
laut Roblox die vollen Flags.

Drei Dinge, die du wissen solltest:

- **Die Studio-Oberfläche bekommt die Effekte mit ab.** ReShade arbeitet auf
  dem gesamten Fenster, nicht nur auf dem Viewport. Ribbon, Explorer und
  Properties leuchten also mit. Für saubere Bilder: `F5` für den Playtest und
  dann *Ansicht → Vollbild* (oder `F11`).
- **Studio zeichnet nur bei Bedarf neu.** Steht die Kamera still, bleibt die
  Bildrate niedrig — das ist Studio, nicht das Preset.
- **Zum Spielen ist das kein Ersatz.** Du bist im Studio-Playtest, nicht auf
  einem echten Server mit anderen Spielern.

---

## Hotkeys

| Taste | Funktion |
|---|---|
| **F8** | Alle Effekte an/aus (mit `-ToggleKey` änderbar) |
| **Pos1** / Home | ReShade-Menü öffnen |
| **F6** / **F7** | Voriges / nächstes Preset (Performance ↔ Balanced ↔ Quality) |
| **F9** | Shader neu laden |
| **Druck** / PrintScreen | Screenshot nach `Bilder\RoGlow` |

Über F6/F7 kannst du die drei Presets im Spiel direkt vergleichen, ohne
etwas neu zu installieren.

---

## Presets und Performance

`PerformanceMode=1` ist in der `ReShade.ini` voreingestellt: ReShade backt
die Preset-Werte als Konstanten in die Shader und spart den
Uniform-Update-Pfad pro Frame. Optisch identisch, ein paar Prozent
geschenkt. Wenn du Regler live verschieben willst, entferne den Haken im
ReShade-Menü unter *Settings → Performance Mode*.

### Performance — ~0.5–0.8 ms

Bloom, Tonemap, Vibrance, Curves, CAS. Bewusst **ohne** Ambient Occlusion
und Reflexionen: beide brauchen den Depth-Buffer und machen zusammen über
80 % der Kosten von Balanced aus. Was bleibt, sind reine
Full-Screen-Pixeloperationen — die kosten fast nichts und liefern trotzdem
den größten Teil des sichtbaren Unterschieds.

### Balanced — ~3–5 ms (Standard)

| Effekt | Shader | Kosten |
|---|---|---|
| Ambient Occlusion | `qUINT_mxao` @ 0.71× Renderskala | ~1.5–2.5 ms |
| Reflexionen | `ReflectiveBumpMapping` | ~1 ms |
| Bloom | `qUINT_bloom` | ~1–2 ms |
| Tonemap + Vibrance + Curves | SweetFX | <0.3 ms |
| Schärfen | `CAS` (FidelityFX) | ~0.15 ms |

Bei 100 FPS bleiben rund 85–90 FPS.

### Quality — ~8–11 ms

Echtes raymarched `qUINT_ssr` statt Reflective Bump Mapping, MXAO auf voller
Auflösung mit Indirect Lighting, Depth of Field an. Für Screenshots und
ruhige Spielmodi — nicht für Obbys oder PvP.

**Wichtig:** SSR und RBM laufen hier bewusst *nicht* zusammen. Beide
gleichzeitig legt zwei Reflexionsschichten übereinander — genau das ist der
Grund, warum das originale „RoShade High" so überzogen aussieht.

---

## Wie die Werte zustande gekommen sind

Die Werte sind nicht geraten. Ausgangspunkt war das Original-Preset
`RoShade High.ini` aus dem archivierten RoShade-Repo — community-erprobt,
aber auf maximale Wirkung getrimmt statt auf ein spielbares Bild. Jeder
übernommene Wert wurde begründet angepasst; die Begründung steht als
Kommentar direkt in der jeweiligen `.ini`.

### Die wichtigsten Korrekturen gegenüber RoShade

| Parameter | RoShade | RoGlow | Warum |
|---|---|---|---|
| `MXAO_SAMPLE_RADIUS` | 5.0 | **2.0** | 5.0 erzeugt großflächige dunkle Höfe, die auf Roblox' Klotzgeometrie wie Dreck aussehen. 2.0 gibt Kontaktschatten in Ecken — der Effekt, den man eigentlich will. |
| `MXAO_SSAO_AMOUNT` | 1.0+ | **0.65** | Der am häufigsten übertriebene Wert überhaupt. Ab 1.0 wird jede Ecke schwarz. |
| `MXAO_SSIL_AMOUNT` | 0.5–5.15 | **0.0** | Indirect Lighting verdoppelt die MXAO-Kosten und erzeugt auf flach schattierten Roblox-Flächen vor allem Farbrauschen. |
| `BLOOM_INTENSITY` | 1.2 | **0.60** | Roblox ist von Haus aus hell. Doppelte Intensität auf hellem Bild = Milchglas. |
| `BLOOM_CURVE` | 1.5 | **2.20** | Höhere Kurve = nur wirklich helle Pixel blühen. Unterschied zwischen „Highlights glühen" und „der Bildschirm leuchtet". |
| `BLOOM_LAYER_MULT_5` | 0.50 | **0.06** | Layer 5 ist ein bildschirmbreiter Halo. Gewicht liegt jetzt auf den engen Layern 1–3 → knackiger Glow statt Dunst. |
| Bloom-Shader | 3 gleichzeitig | **1** | RoShade fuhr BloomingHDR + MagicBloom + AmbientLight parallel. Da kommt der ausgewaschene Look her. |
| `Curves Contrast` | 0.65 | **0.30** | Curves läuft *nach* MXAO, das die Schatten schon abgedunkelt hat. Die Effekte multiplizieren sich. |
| `Vibrance` | 0.403 @ RGB 2/1/1 | **0.15 @ 1/1/1** | 0.403 clippt; die RGB-Balance 2/1/1 legt einen Rotstich über alles. |
| `fRBM_FresnelReflectance` | 0.232 | **0.18** | 0.232 sieht nass aus, 0.18 liest sich als „polierter Kunststoff". |
| DoF `ShapeRadius` | 50 | **14** (und aus) | Radius 50 ist Vaseline auf der Linse und in einem Spiel, in dem man sich ständig bewegt, unspielbar. |
| Auto-Belichtung | an | **aus** | Sonst pulsiert die Bildhelligkeit beim Kameraschwenk. |

Bewusst **nicht** übernommen: `RadiantGI` / `qUINT_rtgi` (8+ ms),
`PPFX_SSDO` (redundant zu MXAO), `EyeAdaption`, `FilmGrain`,
`ChromaticAberration` (verwischt UI-Kanten).

### Nachprüfbar statt behauptet

`Test-RoGlowPreset.ps1` liest die echten `.fx`-Dateien, zieht Technique-Namen,
Uniform-Namen und deren `ui_min`/`ui_max` heraus und prüft die Presets
dagegen:

```powershell
.\Test-RoGlowPreset.ps1 -ShowTable
```

Aktueller Stand: **266 Parameterwerte geprüft, alle innerhalb der
Shader-Grenzen.** Die durchschnittliche Reglerposition der aktiven Effekte
liegt bei **29 %** — das Gegenteil von „alles auf Maximum".

Sechs Werte stehen bei 100 %, alle absichtlich:

- `fRBM_ColorMask_Cyan` / `_Blue` = 1.0 — Blau und Cyan (Wasser, Glas,
  himmelsbeleuchtete Flächen) sollen voll glänzen, warme und organische Töne
  nur halb. Das bildet nach, dass raue Materialien real weniger spiegeln.
- In Quality: `MXAO_GLOBAL_RENDER_SCALE` = 1.0 (volle Auflösung ist der Sinn
  des Presets), `SSR_RELIEF_SCALE`, `fADOF_ShapeAnamorphRatio` und
  `fADOF_RenderResolutionMult` = 1.0 — das sind **Neutralwerte**, nicht
  Maximalwerte.

Der Test ist außerdem der Frühwarnmechanismus für den Fall, dass ein
Shader-Repo einen Parameter umbenennt: ReShade ignoriert unbekannte Schlüssel
kommentarlos, ein Effekt täte dann einfach stumm nichts.

Zwei echte Fehler hat der Test während der Entwicklung gefunden:
ein nicht existierendes `bUIEnabled` in `DisplayDepth.fx` und ein
`iRBM_SampleCount=12` unterhalb des Shader-Minimums von 16.

---

## Nach einem Roblox-Update

Roblox legt bei **jedem** Update einen neuen Ordner
`%LOCALAPPDATA%\Roblox\Versions\version-<hex>\` an. Die alte Version bleibt
oft noch eine Weile liegen. Deine `dxgi.dll` steht dann im alten Ordner und
wird nicht mehr geladen — die Effekte sind weg.

Lösung: erneut ausführen. Der Repair-Modus nimmt alles aus dem lokalen Cache
unter `%LOCALAPPDATA%\RoGlow\cache`, braucht kein Netzwerk und ist in ein
paar Sekunden durch:

```powershell
.\Install-RoGlow.ps1 -Repair
```

Willst du dem Umzug zuvorkommen, installiere in alle vorhandenen
Versionsordner:

```powershell
.\Install-RoGlow.ps1 -AllVersions
```

Prüfen, wohin installiert wurde:

```powershell
Get-Content "$env:LOCALAPPDATA\RoGlow\installs.json"
```

---

## Deinstallation

```powershell
.\Uninstall-RoGlow.ps1
```

Vorher anschauen, was passieren würde:

```powershell
.\Uninstall-RoGlow.ps1 -Scan -WhatIf
```

Der Uninstaller arbeitet die `roglow-manifest.json` jedes Zielordners ab und
löscht **ausschließlich** die dort protokollierten Dateien. Es wird nie ein
Verzeichnis pauschal entfernt — Roblox' eigene Dateien liegen im selben
Ordner.

Zusätzlich abgeräumt: Dateien, die ReShade selbst zur Laufzeit anlegt
(`ReShade.log`, `ReShadePreset.ini`, Effekt-Cache) und deshalb nicht im
Manifest stehen. Vor dem Löschen einer `dxgi.dll` wird deren
Versionsinformation geprüft — ist es keine ReShade-DLL, bleibt sie liegen.

Weitere Schalter:

```powershell
.\Uninstall-RoGlow.ps1 -KeepCache    # Downloads für später behalten
.\Uninstall-RoGlow.ps1 -Scan         # auch Reste ohne Manifest suchen
.\Uninstall-RoGlow.ps1 -RobloxPath "C:\...\version-abc"   # nur diesen Ordner
```

FastFlags werden davon **nicht** berührt. Die entfernst du getrennt:

```powershell
.\Apply-FastFlags.ps1 -Remove
```

---

## Weg ohne Injection: FastFlags

Roblox liest beim Start eine `ClientAppSettings.json` aus dem
`ClientSettings`-Ordner der jeweiligen Version. Darüber lassen sich interne
Engine-Schalter setzen — dieselben, die Bloxstrap über seinen
FastFlag-Editor schreibt. Kein fremder Code, keine DLL, kein
Anti-Cheat-Konflikt.

### Seit 29.09.2025 gilt eine Allowlist

Roblox hat die lokal setzbaren FastFlags auf **18 Stück** begrenzt
([offizielle Ankündigung](https://devforum.roblox.com/t/allowlist-for-local-client-configuration-via-fast-flags/3966569)).
Alles, was nicht auf der Liste steht, wird beim Start **stillschweigend
ignoriert** — keine Fehlermeldung, keine Wirkung.

Genau daran scheitern fast alle FastFlag-Listen, die im Netz kursieren: sie
sind älter als die Allowlist. Wer sie einträgt, ändert schlicht nichts und
merkt es nicht.

Dieses Script setzt ausschließlich allowlistete Flags. Ein eingebauter
Selbsttest bricht ab, falls je ein nicht-allowlistetes Flag in ein Profil
gerät — dieselbe Prüfung hat drei Flags aus der ersten Fassung dieses Tools
als wirkungslos entlarvt, darunter `FFlagDebugForceFutureIsBrightPhase3` und
`FIntRenderShadowIntensity`.

Die Allowlist gilt für den **Player**. Roblox Studio behält laut Roblox
weiterhin die vollen FastFlags.

### Prüfen, was bei dir überhaupt noch wirkt

```powershell
.\Apply-FastFlags.ps1 -Audit
```

Schreibt nichts. Liest jede gefundene `ClientAppSettings.json` (auch die von
Bloxstrap) und teilt jedes Flag ein in *wirkt* / *wird ignoriert*, dazu die
vollständige Allowlist mit Roblox' Standardwerten. Wenn du irgendwann eine
FastFlag-Liste aus dem Netz übernommen hast, sagt dir das hier in fünf
Sekunden, wie viel davon noch etwas tut.

### Setzen

```powershell
.\Apply-FastFlags.ps1                          # Profil Quality
.\Apply-FastFlags.ps1 -Profile Balanced        # MSAA 2x, LOD 2x
.\Apply-FastFlags.ps1 -Profile Performance     # auf FPS getrimmt
.\Apply-FastFlags.ps1 -Bloxstrap               # zusätzlich in Bloxstrap
.\Apply-FastFlags.ps1 -Remove                  # rückgängig
```

| Flag | Quality | Balanced | Performance | Wirkung |
|---|---|---|---|---|
| `DFIntDebugFRMQualityLevelOverride` | `21` | `21` | `10` | Internes Qualitätslevel (1–21). Der wirksamste Einzelwert — steuert intern Beleuchtung, Schatten und Effektdichte gemeinsam und geht über das hinaus, was der Regler in der Roblox-UI zulässt. |
| `FIntDebugForceMSAASamples` | `4` | `2` | `0` | Kantenglättung. Erlaubt sind 0/1/2/4/8, über 4 gibt es bekannte Viewport-Fehler. Der Sprung von 0 auf 2 bringt optisch am meisten. |
| `DFFlagTextureQualityOverrideEnabled` | `True` | `True` | `False` | Schaltet die Texturqualitäts-Übersteuerung ein |
| `DFIntTextureQualityOverride` | `3` | `3` | — | Texturqualität 0–3, höher ist besser |
| `DFIntCSGLevelOfDetailSwitchingDistance` *(+L12/L23/L34)* | 4× | 2× | Standard | Entfernungen, ab denen Teile auf gröbere Detailstufen wechseln. Höher = das sichtbare „Aufploppen" verschwindet. Standard ist 250/500/750/1000. |
| `FIntFRMMinGrassDistance` / `MaxGrassDistance` | `400`/`1000` | `100`/`290` | `0`/`0` | Wie weit Gras gerendert wird. Gras ist einer der teuersten Posten bei Roblox. |
| `FFlagDebugGraphicsPreferD3D11` | `True` | `True` | `True` | Rendering-API auf D3D11 festnageln |
| `FFlagDebugGraphicsPreferVulkan` / `PreferOpenGL` | `False` | `False` | `False` | Kein Wechsel auf eine andere API |
| `DFFlagDebugPauseVoxelizer` | `False` | `False` | `False` | Ausdrücklich aus: `True` friert die Voxel-Beleuchtung ein |
| `FFlagDebugSkyGray` | `False` | `False` | `False` | Ausdrücklich aus: `True` ersetzt den Himmel durch Grau |

Die letzten beiden werden bewusst explizit auf `False` gesetzt statt
weggelassen — sie stehen in vielen kursierenden „FPS-Boost"-Listen, und so
wird eine alte Konfiguration überschrieben statt stehengelassen.

Optisch ist das weniger spektakulär als ReShade — kein Bloom, keine
Reflexionen, keine Farbkorrektur. Dafür wirkt es.

**Nach dem Setzen:** im Spiel *Esc → Einstellungen → Grafikmodus* auf
**Manuell** stellen und den Regler ganz nach rechts. Sonst überschreibt die
Automatik das erzwungene Qualitätslevel wieder.

Zwei Einschränkungen:

- Ohne Bloxstrap setzt Roblox die Datei bei jedem Client-Update zurück. Mit
  `-Bloxstrap` wird zusätzlich in Bloxstraps eigene Konfiguration geschrieben,
  die Updates überlebt.
- Für `DFFlagTextureQualityOverrideEnabled` gibt es
  [einen offenen Bloxstrap-Bugreport](https://github.com/bloxstraplabs/bloxstrap/issues/4173),
  wonach die Texturübersteuerung seit Bloxstrap 2.8.0 nicht greift. Das Flag
  ist allowlistet und korrekt gesetzt; ob es ankommt, zeigt dir der
  Sichtvergleich.

Bestehende, nicht von RoGlow stammende Flags bleiben beim Setzen *und* beim
Entfernen unangetastet; die ursprüngliche Datei wird einmalig als
`.roglow-backup` gesichert.

Wer lieber selbst in Bloxstrap importiert: `config/fastflags-quality.json`
enthält das Quality-Profil als reine JSON für *Fast Flags → Fast Flag Editor →
Import JSON*.

---

## Fehlersuche

**Kein ReShade-Menü, keine Effekte.**
Erst prüfen, ob überhaupt geladen wurde:

```powershell
.\Install-RoGlow.ps1 -CheckLog
```

- *Kein Initialisierungseintrag* → die `dxgi.dll` liegt im falschen Ordner.
  Roblox hat vermutlich aktualisiert: `-Repair` ausführen.
- *Geladen, Effekte kompiliert, im **Player** trotzdem nichts* → das ist der
  Hyperion-Block. Kein Fehler der Installation, und von außen nicht zu
  beheben. Nimm Studio.
- *Geladen, Effekte kompiliert, im **Studio** nichts* → hier liegt ein echtes
  Problem vor. Prüfe, ob Pos1 das Menü öffnet; wenn ja, ist nur der
  Effekt-Toggle aus (F8). Wenn nein, läuft eine andere Overlay-Software
  (Discord, GeForce Experience, MSI Afterburner) dazwischen — die einmal
  beenden und Studio neu starten.

**Ambient Occlusion / SSR / DoF tun nichts, der Rest funktioniert.**
Dann fehlt der Depth-Buffer. Im ReShade-Menü `DisplayDepth` aktivieren:

- Nahe Objekte müssen **schwarz** sein, ferne weiß.
- Sind sie umgekehrt → in der Preset-Datei
  `RESHADE_DEPTH_INPUT_IS_REVERSED` auf `0` setzen, dann **F9**.
- Ist das Bild komplett schwarz oder weiß → im ReShade-Menü unter
  *Add-ons → Generic depth* einen anderen Buffer wählen.

**Es ruckelt.**
Mit **F6** auf `RoGlow-Performance` schalten. Wenn das reicht, aber du mehr
willst: in Balanced als Erstes `MXAO_GLOBAL_RENDER_SCALE` auf `0.5` senken —
das ist der größte Einzelposten. Danach `iRBM_SampleCount`.

**„Die Datei kann nicht geladen werden, da die Ausführung von Skripten auf
diesem System deaktiviert ist."**
Entweder `RoGlow.cmd` benutzen oder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-RoGlow.ps1
```

**„Roblox läuft gerade."**
Der Installer schreibt nicht, solange die `dxgi.dll` gesperrt ist. Roblox
komplett schließen (auch aus dem Infobereich der Taskleiste).

**Roblox wurde nicht gefunden.**
Einmal Roblox starten, damit es sich installiert. Sonst Pfad direkt angeben:

```powershell
.\Install-RoGlow.ps1 -RobloxPath "C:\Users\<du>\AppData\Local\Roblox\Versions\version-xxxx"
```

---

## Shader-Quellen und Lizenzen

Es werden **keine Shader in diesem Repo mitgeliefert.** Der Installer lädt
sie zur Laufzeit direkt von den Original-Repos — so bekommst du immer die
gepflegte Fassung, und es wird keine Lizenz verletzt.

| Quelle | Branch | Dateien |
|---|---|---|
| [`crosire/reshade-shaders`](https://github.com/crosire/reshade-shaders) | `slim` | `ReShade.fxh`, `ReShadeUI.fxh`, `Macros.fxh`, `Blending.fxh`, `TriDither.fxh`, `DrawText.fxh`, `DisplayDepth.fx` |
| [`crosire/reshade-shaders`](https://github.com/crosire/reshade-shaders) | `legacy` | `ReflectiveBumpMapping.fx` |
| [`martymcmodding/qUINT`](https://github.com/martymcmodding/qUINT) | `master` | `qUINT_common.fxh`, `qUINT_bloom.fx`, `qUINT_mxao.fx`, `qUINT_ssr.fx`, `qUINT_dof.fx`, `qUINT_sharp.fx` |
| [`CeeJayDK/SweetFX`](https://github.com/CeeJayDK/SweetFX) | `master` | `Tonemap.fx`, `Vibrance.fx`, `Curves.fx`, `CAS.fx`, `LumaSharpen.fx`, `LiftGammaGain.fx` |

qUINT steht unter „Copyright (c) Pascal Gilcher / Marty McFly. All rights
reserved." — deshalb wird ausschließlich zur Laufzeit vom Original-Repo
geladen und nichts weiterverteilt.

ReShade selbst kommt von [reshade.me](https://reshade.me) und wird über das
offizielle, signierte Setup installiert.

`UIMask.fx` ist bewusst nicht dabei: es braucht eine mitzuliefernde
`UIMask.png` und würde sonst garantiert einen Compile-Fehler werfen.

---

## Was dieses Tool nicht tut

- Kein Umgehen, Verstecken oder Patchen von Hyperion oder irgendeinem
  Anti-Cheat.
- Kein Eingriff in Roblox' eigene Dateien. Es werden nur zusätzliche Dateien
  danebengelegt, die der Uninstaller vollständig wieder entfernt.
- Kein Spielvorteil. ReShade ist reine Nachbearbeitung des fertigen Bildes —
  es sieht nichts, was du nicht ohnehin schon auf dem Bildschirm hast.
- Keine Adminrechte, keine Hintergrunddienste, keine Autostart-Einträge,
  keine Telemetrie.
