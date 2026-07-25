# Tests

Automatisierte Browser-Prüfungen für die Transkriptions-App (Playwright + Chromium).

```bash
# im Repo-Wurzelverzeichnis
python3 -m http.server 8765          # Terminal 1 — liefert die App aus
npm i playwright                     # einmalig
node transcribe/tests/mockapi.mjs    # Terminal 2 — nachgebaute OpenAI-Endpunkte (Port 8766)

node transcribe/tests/test.mjs         # Oberfläche, Aufnahme, Export, Archiv, PWA
node transcribe/tests/test-pro.mjs     # Pro-Modus, KI-Funktionen, WAV-Stückelung
node transcribe/tests/test-engine.mjs  # Live-Erkennung, Mix-Auswahl, Offline, Backup
```

`CHROME_PATH` setzen, falls ein bestimmtes Chromium benutzt werden soll.

Hinweise:
- Container haben meist kein Audiogerät, deshalb ersetzen die Tests `getUserMedia`
  durch einen synthetischen Ton-Stream — `MediaRecorder` läuft damit echt.
- Die Browser-Spracherkennung braucht Googles Dienst; `test-engine.mjs` baut sie
  deshalb nach und prüft die eigene Logik (Mix-Auswahl, Auto-Neustart, Befehle).
- Der Pro-Modus wird gegen `mockapi.mjs` geprüft, es wird kein echter API-Key benötigt.
