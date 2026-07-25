Zwei Apps in diesem Repo:

- **[Flappy 3D](#flappy-3d-)** — das Spiel (`index.html`)
- **[Voice Notes](#voice-notes-️)** — Transkriptions-App für Deutsch, Englisch und gemischt (`transcribe/`)

---

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

# Voice Notes 🎙️

Sprich — die App schreibt mit. **Deutsch, Englisch oder beides gemischt**, ohne Installation,
ohne Konto, ohne Abhängigkeiten. Alles bleibt lokal im Browser.

**Öffnen:** `transcribe/` über https oder `http://localhost` aufrufen — z. B. GitHub Pages, oder lokal:

```bash
python3 -m http.server 8000   # dann http://localhost:8000/transcribe/
```

> Direkt per Doppelklick (`file://`) geht **nicht** — Browser geben das Mikrofon nur in
> sicheren Kontexten (https / localhost) frei.

## Sprachen

| Modus | Was passiert |
|---|---|
| 🇩🇪 **Deutsch** | Erkennung auf `de-DE` |
| 🇬🇧 **Englisch** | Erkennung auf `en-US` |
| 🌍 **Gemischt** | **Zwei Erkenner laufen parallel.** Pro gesprochenem Satz gewinnt das Ergebnis, das besser passt — bewertet aus der Erkennungssicherheit plus einer Wortschatz-Heuristik. Genau richtig für deutsche Sätze mit englischen Fachwörtern („Ich muss noch das *deployment* fertig machen"). Jedes Segment zeigt an, welche Sprache gewonnen hat. |

Umschalten geht auch mitten in der Aufnahme.

## Aufnahme-Modus

| Modus | Wofür |
|---|---|
| 🎧 **Audio + Text** | Standard: schneidet mit **und** schreibt live mit. Beste Wahl in Chrome/Edge. |
| ✍️ **Nur Text** | Live-Mitschrift ohne Audio-Mitschnitt. **Der Modus für iPhone/Safari** — dort blockiert ein offener Mikrofon-Mitschnitt oft die Spracherkennung. |
| 🔴 **Nur Audio** | Nimmt nur auf, das Transkript kommt danach per ✨ Pro. |

Die Aufnahme wird **immer** gespeichert — auch wenn die Live-Erkennung nichts liefert. In dem
Fall erklärt die App direkt im Transkript-Feld, was los ist, und bietet Pro-Transkript,
Nur-Text-Modus und eine **🔬 Diagnose** an (Mikrofon-Test mit Pegel, Browser-Fähigkeiten,
letzter Erkennungsfehler — zum Kopieren).

## Funktionen

**Aufnehmen**
- Live-Transkript beim Sprechen, Pause/Fortsetzen, Wellenform + Pegel, Timer, Wörter und Wörter/Minute
- 🔖 **Marken** während des Sprechens setzen — später ein Klick, und das Audio springt an die Stelle
- 👥 **Sprecherwechsel** für Notizen zu zweit (A/B, farblich getrennt)
- Absätze entstehen automatisch aus Sprechpausen, optionaler Auto-Stopp bei Stille
- Bildschirm bleibt während der Aufnahme an

**Text**
- Jedes Segment direkt antippen und korrigieren
- **Diktier-Befehle**: „Punkt", „Komma", „Fragezeichen", „neuer Absatz", „streich das" — genauso auf Englisch („period", „new paragraph", „scratch that")
- **Eigener Wortschatz**: Namen und Fachbegriffe eintragen, auch als `falsch => richtig`. Wird auf das Live-Transkript angewandt (auch bei knapp danebenliegender Schreibweise) und dem Pro-Modell als Hinweis mitgegeben
- Füllwörter-Filter (äh, ähm, halt, um, like …) — abschaltbar, das Original bleibt erhalten
- Automatische Groß-/Kleinschreibung und Satzzeichen

**Pro-Modus** (optional, eigener API-Key)
- Nach der Aufnahme hochgenau nachtranskribieren — spürbar besser bei Fachbegriffen, Zahlen und Namen
- Im Mix-Modus entscheidet das Modell selbst über die Sprache und trifft echtes Deutsch-Englisch-Gemisch
- Lange Aufnahmen werden automatisch in 16-kHz-Mono-Stücke zerlegt und nacheinander verarbeitet
- Live- und Pro-Fassung bleiben beide erhalten und sind umschaltbar

**KI-Nachbearbeitung** (mit Key)
- Text aufräumen · Zusammenfassung mit Stichpunkten und To-dos · in Notizen umwandeln · E-Mail-Entwurf · Übersetzung DE ↔ EN

**Danach**
- 🔊 Abspielen mit 0,75×–2× Tempo und **Karaoke-Hervorhebung** des gerade laufenden Satzes
- ⬇︎ Export als **TXT, Markdown, SRT, VTT, JSON**, mit Zeitstempeln, dazu die Audiodatei
- 📋 Kopieren und 📤 Teilen (Share-Sheet am Handy)
- 📚 **Archiv** mit Volltextsuche, Umbenennen, Anheften, Backup als JSON
- 📊 Statistik: Dauer, Wörter, W/min, Sprachverteilung, häufigste Wörter
- 🌓 Hell/Dunkel/Automatisch, installierbar als App (PWA), Tastenkürzel am Desktop (`Leertaste`, `M`, `P`, `E`, `/`)

## Datenschutz

Aufnahmen, Transkripte und der API-Key bleiben **in diesem Browser** (IndexedDB bzw. localStorage) —
es gibt keinen eigenen Server. Zwei Ausnahmen, die die App auch deutlich anzeigt:
die **Live-Erkennung** von Chrome überträgt Audio an Google, und der **Pro-Modus** schickt die
Aufnahme an den eingetragenen Anbieter. Ohne Key wird nichts an einen Anbieter gesendet.

## Browser

Am besten **Chrome oder Edge** (Desktop und Android) — dort funktioniert die Live-Erkennung
vollständig.

**iPhone/iPad:** Safari kann zwar live mitschreiben, verweigert das aber meist, solange
gleichzeitig Audio mitgeschnitten wird. Deshalb: Modus **„✍️ Nur Text"** wählen — dann läuft die
Live-Mitschrift. Wer den Mitschnitt braucht, nimmt mit „🔴 Nur Audio" auf und lässt danach
✨ Pro transkribieren (das liefert auf dem iPhone ohnehin die besseren Ergebnisse).
Die App startet die Erkennung bewusst direkt aus der Tipp-Geste, weil Safari sie sonst blockiert.

**Firefox** kennt keine Spracherkennung; die App erkennt das, erklärt es und schaltet auf reines
Aufnehmen um — mit Key liefert danach der Pro-Modus das Transkript.

## Tests

`transcribe/tests/` enthält automatisierte Browser-Prüfungen (Playwright), siehe
[transcribe/tests/README.md](transcribe/tests/README.md).
