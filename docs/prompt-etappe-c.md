# Prompt für die neue Sitzung (Etappe C)

Zum Kopieren in eine frische Claude-Code-Sitzung im Repo-Verzeichnis:

---

Wir bauen die Weboberfläche von PiCraft neu — Etappe C.

**Lies zuerst, in dieser Reihenfolge:**
1. `docs/lastenheft-minecraft-server.md` (Fassung 0.3) — das ist die
   Absprungbasis. Besonders **§3 Entscheidungen**, **die Korrekturen K1/K2**
   direkt danach, **§5.7 Weboberfläche** und dort vor allem **§5.7.0 „Was
   Etappe C bereits vorfindet"**.
2. `CLAUDE.md` — Projektregeln und die Fallen, bei denen das Naheliegende
   falsch ist.
3. `docs/pflichtenheft-etappe-b.md` — was gerade fertig geworden ist und
   warum es so aussieht.
4. `PRUEFEN-AUF-DEM-PI.md` — was noch auf echter Hardware geprüft werden muss.

**Stand:** Etappen A und B sind fertig, geprüft und auf `main` gepusht
(Commits `c0ae8f8` bis `538c5b4`). Das Repository läuft auf einem fremden Pi
mit beliebigem Benutzernamen, `mcs an`/`mcs aus` schaltet alles, RCON liefert
Antworten, und ein Sammler schreibt minütlich Messwerte nach SQLite.
`admin_ui/` besteht aus zehn Modulen; die Oberfläche selbst ist noch die
alte, unveränderte.

**Vorgehen wie bisher:** Erst ein Pflichtenheft nach
`docs/pflichtenheft-etappe-c.md` ableiten, mit mir abstimmen, dann umsetzen.
Nach jedem Schritt `make` und `tests/abnahme.sh` (braucht Docker). Nichts
committen, ohne dass beides grün ist. Annahmen über Paper-Verhalten nicht
raten, sondern im Container nachmessen — so sind in Etappe B die Korrekturen
K1 und K2 entstanden.

Fang mit dem Pflichtenheft an.

---

## Was Etappe C umfasst (Kurzfassung, Einzelheiten im Lastenheft §5.7)

Sieben Seiten: Startseite, Spieler, Konfiguration, Backups, Leistung,
Plugins, Weltkarte. Technik: Flask + Jinja + HTMX, kein Build-Schritt, kein
npm, kein CDN; uPlot für die Kurven; alles lokal ausgeliefert.

Gestaltung: Minecraft als Herkunft, nicht als Kostüm — eckig, die typische
Fase als Kante, Materialfarben statt Texturen, dunkel als Standard, und zwei
oder drei Stellen, an denen es richtig Minecraft ist. **Keine** Pixelschrift
im Fließtext, keine Steintexturen als Hintergrund.

## Drei Regeln, die in Etappe C gelten

1. **Paper schreibt seine Konfigurationsdateien beim Herunterfahren neu.**
   Editieren nur bei gestopptem Server — oder vormerken und beim nächsten
   Neustart anwenden, sichtbar angezeigt.
2. **Jeder neue Editor für eine Konfigurationsdatei** muss geprüft werden, ob
   dort ein Geheimnis stehen kann. Liste: `GEHEIME_SCHLUESSEL` in
   `admin_ui/routen.py` (Korrektur K2).
3. **RCON sparsam benutzen** — es läuft im Hauptthread des Servers. Eine
   Abfrage je Klick ist richtig, eine je Sekunde nicht. Für Schleifen
   `Rcon(...)` als Kontextmanager statt `rcon.befehl()` je Aufruf.

## Offene Entscheidungen für Etappe C

- Reihenfolge der Reiter (Lastenheft O2)
- Welche ~20 Werte auf die kuratierte Einstellungsseite kommen (O3)
- Konkrete Schriftarten für den Minecraft-Look, Lizenz beachten (O5)
