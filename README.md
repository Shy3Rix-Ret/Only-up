# Flappy 3D 🐦

Flappy Bird — aber aus der **Ego-Perspektive des Vogels in 3D**! In der Lobby kann man jederzeit auf die **klassische 2D-Ansicht** umschalten.

**Spielen:** Einfach `index.html` im Browser öffnen (Handy oder Desktop). Keine Installation, keine Abhängigkeiten, läuft offline.

## Steuerung
- **Tippen / Klicken / Leertaste** = Flügelschlag
- In der Lobby: Modus wählen (3D Vogel-Perspektive oder 2D Klassisch) und START drücken

## Features
- 🐦 **3D-Ego-Perspektive**: Du siehst deine eigenen flatternden Flügel und den Schnabel, Röhren rasen mit Tiefenwirkung auf dich zu
- 🎮 **2D-Klassikmodus** mit Parallax-Hintergrund, in der Lobby umschaltbar
- 🌄 Ganz viele Hintergrund-Details: Sonne mit Glow, Wolken, zwei Bergketten, Stadt-Silhouette (abends leuchten die Fenster!), Windmühlen mit drehenden Flügeln, Heissluftballons, Vogelschwärme, Häuser mit Kaminrauch, Bäume, Büsche mit Beeren, Blumen, Felsen, Gras, Schmetterlinge
- 🌅 Sanfter Tag-/Abend-Farbwechsel je weiter du fliegst
- 🔊 Sound-Effekte (abschaltbar), Vibration beim Aufprall
- 🏆 Rekord wird gespeichert, Medaillen beim Game Over
- 📱 Für Handys optimiert: reines Canvas-2D-Rendering, ~60 FPS, begrenzte Pixeldichte, Objekt-Recycling — kein Lag

---

# Buckshot Roulette (Fan-Remake) 🔫

Eigene Datei: **`buckshot-roulette.html`** – einfach im Browser öffnen (Desktop oder Handy im Querformat). Braucht Internet für three.js (cdn.jsdelivr.net).

## Was drin ist
- **3D-Szene im Original-Look**: Low-Res-Pixel-Rendering mit begrenzter Farbpalette + Dithering, grüner Spieltisch mit Linien und Patronen-Leiste, zwei Bühnenscheinwerfer, Kabel, Backsteinwände, Deko (Geräte-Rack mit Überwachungskamera, Papierstapel, Kassettendeck, Feuerlöscher, Lautsprecher)
- **Dealer**: 3D-Modell aus `Dealer.fbx` (normal + „crushed“ bei Treffer), Kiefer bewegt sich beim Reden, schwebende Knochenhände. In den OPTIONS auf den eingebauten Kopf umschaltbar
- **Ablauf wie im Original**: Badezimmer-Intro, Waiver unterschreiben, Runde I (2 Ladungen, keine Items), Runde II (4 Ladungen, 2 Items/Ladung), Runde III (5 Ladungen, 4 Items, Defibrillator-Kabel werden bei ≤ 2 gekappt), Wiederbelebung in Runde I/II, Koffer mit $70,000, **Double or Nothing**, Endstatistik
- **36 Items**: die 5 Originale, die 4 aus Double or Nothing und 27 neue (z. B. X-Ray Goggles, Tarot Card, Whiskey, Kevlar Vest, Pocket Mirror, Lucky Coin, Devil's Die, Wire Cutters, Magnet, Duct Tape, Car Battery, Voodoo Doll, Rat Poison, Joker, Double Tap …) – alle mit eigenem 3D-Modell und Dealer-KI
- **Animationen**: Feder-Physik für Rückstoß und Kamera, Flinte mit Pump-Action, Rauchfahne und rausfliegenden Hülsen (echte Mini-Physik, prallen vom Tisch ab), Säge schneidet ein Laufstück ab, Dealer lädt die Flinte sichtbar Patrone für Patrone, Finger trommeln und greifen, er lacht, nickt und schaut sich um. Jedes Item hat eine eigene Animation (trinken, rauchen, Münze werfen, Würfel rollen, Karten umdrehen …), Handschellen und Klebeband bleiben sichtbar an den Händen, Treffer mit Umkippen, Blackout und Defibrillator
- **Sound**: alle Effekte und der Soundtrack „General Liability“ (dunkler Club-Track im Stil des Originals) werden live per WebAudio erzeugt

## Original-Soundtrack (optional, nur lokal)
Der Original-Song ist urheberrechtlich geschützt und deshalb **nicht** im Repo. Wer ihn besitzt, kann ihn so benutzen – er läuft dann lückenlos im Loop statt des eingebauten Tracks:
- **OPTIONS → LOAD MUSIC** und die MP3 auswählen (der Browser merkt sie sich), oder
- die Datei als `general-release.mp3` neben `buckshot-roulette.html` legen.

`*.mp3` steht in der `.gitignore`, damit sie nicht aus Versehen hochgeladen wird.

## Steuerung
- Maus / Touch: Items und Schrotflinte anklicken, dann **DEALER** oder **YOU** wählen
- Tastatur: `W`/`S` bzw. `↑`/`↓` zielen, `Leertaste` Flinte/Box, `1–8` Items, `ESC` Pause
- Handy: Item einmal antippen = Info, nochmal (oder USE) = benutzen

Fan-Projekt, nicht verbunden mit Mike Klubnika / CRITICAL REFLEX.
