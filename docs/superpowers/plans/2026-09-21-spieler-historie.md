# Spieler-Historie — Umsetzungsplan (v1.2)

> **Für Agenten:** PFLICHT-UNTERSKILL: `superpowers:subagent-driven-development`
> (empfohlen) oder `superpowers:executing-plans`. Die Schritte tragen
> Checkboxen (`- [ ]`) zum Mitführen.

**Ziel:** Eine Seite in der Weboberfläche, die zeigt, wer wann wie lange
online war und was dabei im Chat geschrieben oder als Befehl abgesetzt
wurde — und davor die Reparatur des Spielerprotokolls, das diese Seite
speist.

**Aufbau:** Das Spielerprotokoll bleibt die Quelle für Sitzungen, die
Serverprotokolle (`logs/*.log.gz`, `logs/latest.log`) sind die Quelle für
Chat und Befehle. Beides wird in eine eigene SQLite-Datei
(`admin/historie.db`) indiziert — einmalig über ein Werkzeug, danach
fortlaufend und nur dann, wenn jemand die Seite öffnet. Kein Timer, kein
sechster Dienst, keine Hintergrundlast bei geschlossener Oberfläche
(Leitsatz 1 und 2).

**Technik:** Python 3, SQLite (stdlib `sqlite3`), Flask + Jinja + HTMX wie
im Bestand. Keine neue Abhängigkeit.

**Spezifikation:** `docs/pflichtenheft-v1.1.md` §5 „Was v1.1 nicht umfasst"
→ Absatz „Die Spieler-Historie (v1.2)". Dort sind zwei Entscheidungen als
offen benannt (Aufbewahrung, Umgang mit Namen und Chat-Inhalten); dieser
Plan trifft sie in Aufgabe 9 und begründet sie dort.

## Verbindliche Randbedingungen

Diese gelten für **jede** Aufgabe und werden nicht je Aufgabe wiederholt:

- **Sprache Deutsch**, auch Bezeichner. Umlaute in Code und Kommentaren als
  `ae/oe/ue`, im Fließtext der Markdown-Dateien nicht.
- **Kommentare erklären das WARUM.** Ein Kommentar, der eine Messung
  festhält, nennt Datum und Ergebnis.
- **Nichts Instanzspezifisches ins Repository** — keine echten
  Spielernamen, UUIDs, IP-Adressen, kein Weltname, keine Portnummern. Das
  gilt auch für Messbelege und für die Historie der Commits. Befunde, die
  nur diese eine Maschine betreffen, gehören nach
  `/home/pi/pi-manager-status.md`, nicht hierher.
- **Kein zweiter Weg zur selben Sache.** Wo dieser Plan etwas berechnet,
  das es schon gibt (Logmuster, Datumsherleitung), wird das Bestehende
  benutzt oder gemeinsam nutzbar gemacht — nicht nachgebaut. Das ist der
  Fehler, der in diesem Projekt am häufigsten Geld gekostet hat.
- **Vor der Abgabe:** `make` (Syntax, pyflakes, shellcheck, Konfigvorlagen).
  Ein grünes `make` ohne pyflakes sagt weniger als die GitHub Action.
- **Keine Python-Prüfblöcke in Shell-Heredocs.** Sie sterben still mit einem
  Traceback und der Lauf gilt weiter als bestanden — am 01.09.2026 waren
  zwei Blöcke deshalb zwei Etappen lang tot. Prüfungen dieses Plans sind
  eigenständige `.py`-Dateien mit eigenem Rückgabewert.
- **Häufig committen**, je Aufgabe mindestens einmal.

---

## Warum es diesen Plan gibt — der Befund vom 21.09.2026

Die Weboberfläche liest für „zuletzt gesehen" ausschließlich die Live-Datei
`player_activity.log` (`admin/spieler.py`, `protokoll_auswerten` →
`read_last_lines`). Dieselbe Datei steht in
`/etc/logrotate.d/pi-mcs` (angelegt von `install.sh`) mit `weekly`,
`rotate 8`, `copytruncate`.

Damit schneidet logrotate wöchentlich genau das weg, was die Oberfläche als
einzige Quelle liest. Auf der Beispielinstallation war die Live-Datei nach
der Rotation **0 Byte**; die Seite meldete für jeden Spieler „nicht
aufgezeichnet", auch für solche mit dreistelligen Stundenzahlen. Die
gesamte Historie lag unversehrt in `.1` und `.2.gz` — nur eben dort, wo
niemand sie liest.

Der Konstruktionsfehler ist nicht die Rotation an sich, sondern die
Einordnung: **`player_activity.log` ist ein Hauptbuch, kein Protokoll.**
Rotation hält Dateien klein, die wachsen dürfen und deren Vergangenheit
niemand braucht. Diese Datei ist das Gegenteil — sie wuchs in einem halben
Jahr auf 139 KB, und ihr einziger Zweck ist die Vergangenheit.

Erschwerend: Das Nachtragswerkzeug hatte die Historie am 01.09.2026
vollständig hergestellt. Die erste Rotation danach hat diese Arbeit wieder
unsichtbar gemacht — fünf Tage später, ohne eine einzige Fehlermeldung.
Das ist die teuerste Fehlerklasse dieses Projekts (stiller Ausfall), und
sie ist der Grund, warum Aufgabe 2 einen Wächter einzieht statt es bei der
Einzeilenkorrektur zu belassen.

---

# Etappe 1 — Reparatur

> ## ✅ Abgeschlossen am 21.09.2026
>
> Ausgerollt, auf dem Pi nachgemessen und im Container abgenommen. Die
> Belege stehen als **H1** in `PRUEFEN-AUF-DEM-PI.md`; ein Punkt dort ist
> offen und bleibt es, bis ein Mensch ihn abnimmt: **die Sichtprüfung im
> Browser**.
>
> **Wo die Umsetzung vom Plan abwich — und warum:**
>
> - **Aufgabe 3, Schritt 4 entfiel.** Nach dem Zurückführen von `.2.gz`
>   und `.1` meldete das Nachtragswerkzeug „Nachzutragen: 0" — die
>   Zusammenführung war bereits vollständig. Der Schritt hat damit seinen
>   Zweck erfüllt, nur andersherum als gedacht: als *Beleg*, dass nichts
>   fehlt, statt als Wiederherstellung.
> - **Der Hinweis in der Rotationsregel kam dazu.** Nach dem Löschen der
>   Zeile stand dort nur noch eine Lücke — eine Einladung, das Hauptbuch
>   gutgemeint wieder einzutragen. `install.sh` und `deploy.sh` schreiben
>   jetzt wortgleich dieselbe Begründung, und die Prüfung vergleicht beide
>   Wortlaute.
> - **Eingefügt wird mit `awk`, nicht mit `sed`.** Der Text beginnt selbst
>   mit `#` und kollidiert mit jedem naheliegenden sed-Trennzeichen. Der
>   erste Versuch endete mit `unknown option to 's'` — gefunden in einer
>   Sandbox, bevor er die Maschine erreichte.
> - **Der Warnhinweis steht auf der Spielerseite**, nicht nur in der
>   Statusantwort. Ein Befund, den niemand sieht, wäre genau der stille
>   Ausfall gewesen, um den es hier geht.
> - **Zwei Werkzeug-Lücken kamen mit heraus:** `make` prüfte `tests/*.py`
>   nicht, und `tests/abnahme-im-container.sh` konnte nur an einem
>   fehlgeschlagenen Installationslauf scheitern. Beides behoben.
>
> **Noch offen, bewusst nicht mitgemacht:** `player_activity.log` ist
> `rw-rw-r--` und enthält IP-Adressen. Auf einem Pi mit einem Benutzer
> folgenlos; wer es enger will, setzt `640` in `install.sh` **und** im
> laufenden System. Das ist eine eigene Entscheidung, kein Nebenprodukt
> dieser Reparatur.

Diese Etappe steht für sich und ist Voraussetzung für alles Weitere: Eine
Historie lässt sich nicht auf eine Datei stützen, die wöchentlich geleert
wird.

## Dateien dieser Etappe

- Ändern: `install.sh` (Funktion `logrotate_einrichten`)
- Ändern: `deploy.sh` (neuer Migrationsschritt)
- Ändern: `tools/spielerprotokoll-nachtragen.py` (Datumslogik auslagern)
- Anlegen: `admin/logdatum.py`
- Anlegen: `admin/protokollpruefung.py`
- Ändern: `admin/status.py` (Wächter in die Statuserhebung)
- Prüfung: `tests/pruefung-historie.py`

---

### Aufgabe 1: Das Hauptbuch aus der Rotation nehmen

**Dateien:**
- Ändern: `install.sh` — Funktion `logrotate_einrichten`, die
  `tee`-Vorlage für `/etc/logrotate.d/pi-mcs`
- Ändern: `deploy.sh` — neuer Schritt, der die Regel auf bestehenden
  Installationen nachzieht

**Schnittstellen:**
- Liefert: nichts, was andere Aufgaben aufrufen. Die Wirkung ist, dass
  `${MC_DIR}/player_activity.log` in keiner logrotate-Regel mehr vorkommt.

**Die Falle dabei — bitte nicht übergehen:** `install.sh` richtet ein,
`deploy.sh` rollt aus. Eine Korrektur nur in `install.sh` erreicht
**keine** bestehende Installation; dort bliebe die Regel stehen und würde
die Reparatur aus Aufgabe 3 beim nächsten Rotationslauf wieder zunichte
machen. Genau dieses Muster steht in `CLAUDE.md` unter „Der Aufrüstweg
kann weniger als die Frischinstallation".

- [x] **Schritt 1: Die Prüfung schreiben, die den Fehlzustand zeigt**

Anlegen: `tests/pruefung-historie.py`

```python
#!/usr/bin/env python3
"""Pruefungen zur Spieler-Historie. Rueckgabewert 0 = alles gut.

Eigenstaendige Datei und kein Heredoc-Block in einem Shell-Skript: Solche
Bloecke sterben still mit einem Traceback, waehrend der Lauf weiter als
bestanden gilt (gefunden 01.09.2026, zwei Bloecke waren zwei Etappen lang
tot).
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
fehler = []


def pruefe(bedingung, text):
    if not bedingung:
        fehler.append(text)


def logrotate_vorlage():
    """Der Block, den install.sh nach /etc/logrotate.d/pi-mcs schreibt."""
    quelle = (REPO / "install.sh").read_text(encoding="utf-8")
    treffer = re.search(
        r"tee /etc/logrotate\.d/pi-mcs.*?<<EOF\n(.*?)\nEOF", quelle, re.S)
    return treffer.group(1) if treffer else ""


pruefe("player_activity.log" not in logrotate_vorlage(),
       "install.sh rotiert player_activity.log immer noch — das Hauptbuch "
       "gehoert in keine Rotationsregel.")

for text in fehler:
    print(f"FEHLER: {text}")
print(f"{len(fehler)} Fehler." if fehler else "Alle Pruefungen bestanden.")
sys.exit(1 if fehler else 0)
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: `FEHLER: install.sh rotiert player_activity.log immer noch …`,
Rückgabewert 1.

- [x] **Schritt 3: Die Zeile aus `install.sh` entfernen**

In `logrotate_einrichten` die Zeile `${MC_DIR}/player_activity.log`
streichen und über dem Block begründen, warum sie fehlt:

```bash
  # Warum player_activity.log hier NICHT steht (21.09.2026):
  # Es ist ein Hauptbuch, kein Protokoll. Die Weboberflaeche liest es als
  # Ganzes, um "zuletzt gesehen" zu beantworten -- eine Rotation schneidet
  # ihr genau diese Antwort weg. Auf der Beispielinstallation stand die
  # Live-Datei nach der Rotation auf 0 Byte, und die Seite meldete fuer
  # Spieler mit hunderten Stunden Spielzeit "nicht aufgezeichnet".
  # Groessenordnung als Gegenprobe: rund 140 KB in sechs Monaten.
  sudo tee /etc/logrotate.d/pi-mcs >/dev/null <<EOF
```

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: `Alle Pruefungen bestanden.`, Rückgabewert 0.

- [x] **Schritt 5: Den Migrationsschritt in `deploy.sh` ergänzen**

Eine **eigene** Abfrage, keine Sammelbedingung. Sie muss auch dann
zuschlagen, wenn ein früherer Ausrollschritt bereits gelaufen ist:

```bash
# Nimmt player_activity.log aus einer bestehenden logrotate-Regel heraus.
#
# Eigener Schritt und keine Sammelbedingung: Eine Korrektur nur in
# install.sh erreicht keine bestehende Installation (siehe CLAUDE.md,
# "Der Aufruestweg kann weniger als die Frischinstallation"). Ohne diesen
# Schritt leert die naechste woechentliche Rotation das Hauptbuch wieder.
logrotate_hauptbuch_loesen() {
  local regel=/etc/logrotate.d/pi-mcs
  [ -f "$regel" ] || return 0
  grep -q "player_activity.log" "$regel" || return 0

  sudo sed -i '\#player_activity\.log#d' "$regel"
  echo "logrotate: player_activity.log aus $regel entfernt (Hauptbuch)."
}
```

Den Aufruf an der Stelle einhängen, an der `deploy.sh` seine übrigen
Migrationsschritte abarbeitet.

- [x] **Schritt 6: `make` laufen lassen**

Ausführen: `make`
Erwartet: grün. Wenn pyflakes oder shellcheck fehlen, sagt `make` das —
dann zählt erst die GitHub Action als Beleg.

- [x] **Schritt 7: Commit**

```bash
git add install.sh deploy.sh tests/pruefung-historie.py
git commit -m "fix: player_activity.log ist ein Hauptbuch und wird nicht rotiert

Die Weboberflaeche liest die Datei als Ganzes fuer 'zuletzt gesehen'.
Die woechentliche Rotation schnitt ihr genau diese Antwort weg; nach
einer Rotation meldete die Spielerseite fuer jeden Spieler 'nicht
aufgezeichnet'. deploy.sh zieht die Regel auf bestehenden
Installationen nach -- ohne eigenen Schritt bliebe sie dort stehen."
```

---

### Aufgabe 2: Der Wächter gegen den stillen Rückfall

**Dateien:**
- Anlegen: `admin/protokollpruefung.py`
- Ändern: `admin/status.py` — Funktion `_status_erheben`
- Ändern: `tests/pruefung-historie.py`

**Schnittstellen:**
- Liefert: `protokollpruefung.protokoll_lueckenhaft()` →
  `dict | None`. `None` heißt „nichts zu melden". Sonst
  `{"protokoll_beginn": "YYYY-MM-DD", "aeltestes_log": "YYYY-MM-DD",
    "text": str}`.
- Wird benutzt von: `admin/status.py` (Aufgabe 2), und später von der
  Historienseite (Aufgabe 8), damit dort derselbe Hinweis erscheint.

**Warum überhaupt ein Wächter:** Die Einzeilenkorrektur aus Aufgabe 1
behebt die Ursache, aber nicht die Fehlerklasse. Der Ausfall war zwei
Wochen lang unsichtbar, weil „keine Daten" auf dieser Seite genauso
aussieht wie „war noch nie da". Der Wächter vergleicht zwei Zahlen, die
sich widersprechen müssen, wenn etwas das Hauptbuch beschneidet: den
Beginn des Protokolls und das Datum des ältesten Serverprotokolls.

- [x] **Schritt 1: Die Prüfung schreiben**

In `tests/pruefung-historie.py` ergänzen:

```python
import importlib.util


def lade(name, pfad):
    spec = importlib.util.spec_from_file_location(name, pfad)
    modul = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modul)
    return modul


def pruefe_waechter(tmp):
    """Ein Protokoll, das spaeter beginnt als das aelteste Serverlog,
    muss gemeldet werden -- genau der Zustand nach einer Rotation."""
    pp = lade("protokollpruefung", REPO / "admin" / "protokollpruefung.py")

    logs = tmp / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    (logs / "2026-03-14-1.log.gz").write_bytes(b"")
    (logs / "2026-09-20-1.log.gz").write_bytes(b"")

    hauptbuch = tmp / "player_activity.log"
    hauptbuch.write_text("2026-09-14 10:00:00 | Spieler_A ist dem Spiel "
                         "beigetreten\n", encoding="utf-8")
    befund = pp.protokoll_lueckenhaft(hauptbuch, logs)
    pruefe(befund is not None,
           "Der Waechter meldet nichts, obwohl das Protokoll ein halbes "
           "Jahr nach dem aeltesten Serverlog beginnt.")

    hauptbuch.write_text("2026-03-14 21:26:29 | Spieler_A ist dem Spiel "
                         "beigetreten\n", encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is None,
           "Der Waechter meldet einen Fehlalarm bei vollstaendigem "
           "Protokoll.")

    hauptbuch.write_text("", encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is not None,
           "Der Waechter uebersieht ein LEERES Hauptbuch -- genau der "
           "Zustand, der zwei Wochen lang unbemerkt blieb.")
```

Und am Ende der Datei vor der Auswertung aufrufen:

```python
import tempfile
with tempfile.TemporaryDirectory() as ordner:
    pruefe_waechter(Path(ordner))
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: Fehlschlag, weil `admin/protokollpruefung.py` noch nicht
existiert (`FileNotFoundError`).

- [x] **Schritt 3: `admin/protokollpruefung.py` schreiben**

```python
#!/usr/bin/env python3
"""
protokollpruefung.py — Merkt, wenn dem Spielerprotokoll die Vergangenheit
fehlt.

Warum es diese Datei gibt (Befund 21.09.2026): Das Spielerprotokoll stand
in einer logrotate-Regel. Nach jeder Rotation war die Live-Datei leer, und
die Spielerseite meldete fuer jeden Spieler "nicht aufgezeichnet" -- auch
fuer solche mit hunderten Stunden Spielzeit. Zwei Wochen lang fiel das
niemandem auf, weil "keine Daten" auf dieser Seite genauso aussieht wie
"war noch nie da".

Die Ursache ist behoben. Diese Pruefung sorgt dafuer, dass ein Rueckfall
nicht wieder still bleibt: Beginnt das Protokoll deutlich spaeter als das
aelteste Serverprotokoll, fehlt etwas -- denn die Serverprotokolle sind
die Quelle, aus der sich das Hauptbuch nachtragen laesst.

Bewusst KEIN zweiter Leseweg auf das Hauptbuch: Die Oberflaeche liest
weiterhin nur die Live-Datei. Ein zweiter Weg zur selben Datei ist in
diesem Projekt mehrfach die Fehlerquelle gewesen. Diese Pruefung liest
nur den ERSTEN Zeitstempel und vergleicht ihn -- sie beantwortet keine
Fachfrage.
"""

import re
from datetime import date, timedelta
from pathlib import Path

# Ein Archiv heisst "2026-03-14-1.log.gz"; das Datum steht vorn.
_ARCHIVNAME = re.compile(r"^(\d{4})-(\d{2})-(\d{2})-\d+\.log(\.gz)?$")
_ZEITSTEMPEL = re.compile(r"^(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}:\d{2} \| ")

# Wie viel Vorsprung das aelteste Serverlog haben darf, ohne dass es ein
# Befund ist. Ein Tag Unterschied ist Alltag (das Protokoll beginnt mit
# dem ersten Beitritt, nicht mit dem ersten Serverstart); eine Woche ist
# es nicht mehr.
TOLERANZ_TAGE = 7


def _erster_protokolltag(hauptbuch):
    """Der erste datierte Tag im Hauptbuch, oder None bei leerer Datei."""
    try:
        with open(hauptbuch, "r", encoding="utf-8", errors="ignore") as f:
            for zeile in f:
                treffer = _ZEITSTEMPEL.match(zeile)
                if treffer:
                    return date.fromisoformat(treffer.group(1))
    except OSError:
        return None
    return None


def _aeltester_logtag(logordner):
    """Der Tag des aeltesten Serverprotokolls, oder None."""
    tage = []
    try:
        for eintrag in Path(logordner).iterdir():
            treffer = _ARCHIVNAME.match(eintrag.name)
            if treffer:
                tage.append(date(int(treffer.group(1)), int(treffer.group(2)),
                                 int(treffer.group(3))))
    except OSError:
        return None
    return min(tage) if tage else None


def protokoll_lueckenhaft(hauptbuch, logordner):
    """None = nichts zu melden. Sonst ein Befund mit beiden Datumsangaben.

    Gibt ausdruecklich auch dann einen Befund zurueck, wenn das Hauptbuch
    LEER ist und Serverprotokolle vorliegen: Das ist der Zustand nach
    einer Rotation, und er war der teuerste, weil er wie "noch nie jemand
    da" aussieht.
    """
    aeltestes = _aeltester_logtag(logordner)
    if aeltestes is None:
        # Ohne Serverprotokolle gibt es nichts zu vergleichen. Dann lieber
        # schweigen als raten.
        return None

    beginn = _erster_protokolltag(hauptbuch)
    if beginn is None:
        return {"protokoll_beginn": None,
                "aeltestes_log": aeltestes.isoformat(),
                "text": ("Das Spielerprotokoll ist leer, es liegen aber "
                         f"Serverprotokolle ab {aeltestes.isoformat()} vor. "
                         "Nachtragen mit tools/spielerprotokoll-nachtragen.py.")}

    if beginn - aeltestes <= timedelta(days=TOLERANZ_TAGE):
        return None

    return {"protokoll_beginn": beginn.isoformat(),
            "aeltestes_log": aeltestes.isoformat(),
            "text": (f"Das Spielerprotokoll beginnt erst am "
                     f"{beginn.isoformat()}, die Serverprotokolle reichen "
                     f"bis {aeltestes.isoformat()} zurueck. "
                     "Nachtragen mit tools/spielerprotokoll-nachtragen.py.")}
```

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: `Alle Pruefungen bestanden.`

- [x] **Schritt 5: Den Befund in die Statuserhebung hängen**

In `admin/status.py`, Funktion `_status_erheben`, den Wächter aufrufen und
das Ergebnis unter dem Schlüssel `protokoll_befund` mitliefern. Der Aufruf
ist billig (zwei Verzeichnisleseoperationen und eine Zeile), darf also im
bestehenden Takt mitlaufen.

```python
import protokollpruefung
from einstellungen import MINECRAFT_LOG, PLAYER_ACTIVITY_LOG

# ... in _status_erheben(), zum Ergebnis-dict hinzu:
"protokoll_befund": protokollpruefung.protokoll_lueckenhaft(
    PLAYER_ACTIVITY_LOG, Path(MINECRAFT_LOG).parent),
```

- [x] **Schritt 6: `make` und Commit**

```bash
make
git add admin/protokollpruefung.py admin/status.py tests/pruefung-historie.py
git commit -m "feat: Waechter meldet ein beschnittenes Spielerprotokoll

Beginnt das Hauptbuch deutlich spaeter als das aelteste Serverprotokoll
-- oder ist es leer, waehrend Serverprotokolle vorliegen --, fehlt die
Vergangenheit und laesst sich nachtragen. Der Ausfall vom September
blieb zwei Wochen unbemerkt, weil 'keine Daten' wie 'war noch nie da'
aussieht."
```

---

### Aufgabe 3: Die Historie auf der Maschine wiederherstellen

Diese Aufgabe ändert **kein Repository-Datei**, sondern die laufende
Installation. Sie gehört trotzdem in den Plan, weil ihre Reihenfolge
zählt.

**Reihenfolge, und warum sie so ist:** Erst die Rotation entfernen
(Aufgabe 1 ausrollen), dann nachtragen. Andersherum könnte der nächste
Rotationslauf die frisch hergestellte Historie sofort wieder wegschneiden.

- [x] **Schritt 1: Sicherung des Ist-Zustands**

```bash
cp -a ~/mcs/player_activity.log ~/mcs/player_activity.log.vor-reparatur
ls -la ~/mcs/player_activity.log*
```

- [x] **Schritt 2: Aufgabe 1 ausrollen und die Regel nachmessen**

```bash
cd ~/Pi-MCS && ./deploy.sh
grep -c player_activity /etc/logrotate.d/pi-mcs   # erwartet: 0
```

Erwartet: `0`. Steht dort noch eine `1`, hat der Migrationsschritt nicht
gegriffen — dann nicht weitermachen, sondern Aufgabe 1 Schritt 5 prüfen.

- [x] **Schritt 3: Die rotierten Stände zurückführen**

```bash
cd ~/mcs
zcat player_activity.log.2.gz >  zusammenfuehrung.txt
cat  player_activity.log.1    >> zusammenfuehrung.txt
cat  player_activity.log      >> zusammenfuehrung.txt
cp zusammenfuehrung.txt player_activity.log
```

- [x] **Schritt 4: Aus den Serverprotokollen nachtragen**

Das Werkzeug ist wiederholbar und führt sortiert und doppelfrei zusammen —
die Reihenfolge in Schritt 3 muss also nicht stimmen.

```bash
cd ~/Pi-MCS
python3 tools/spielerprotokoll-nachtragen.py --zeigen   # erst berichten
python3 tools/spielerprotokoll-nachtragen.py            # dann schreiben
```

- [x] **Schritt 5: Nachmessen — drei Belege, nicht einer**

```bash
# 1. Wiederholbarkeit: zweiter Lauf aendert nichts
md5sum ~/mcs/player_activity.log
python3 tools/spielerprotokoll-nachtragen.py
md5sum ~/mcs/player_activity.log        # muss gleich sein

# 2. Der Waechter schweigt
python3 -c "
import sys; sys.path.insert(0, 'admin')
import protokollpruefung as p
from pathlib import Path
print(p.protokoll_lueckenhaft(Path.home()/'mcs/player_activity.log',
                              Path.home()/'mcs/mc_server/logs'))"
# erwartet: None

# 3. Die Oberflaeche zeigt wieder Daten
cd ~/mcs/admin && python3 -c "
import spieler
for e in spieler.alle():
    print(e['name'], e['gesehen'], e['zuletzt'])"
```

Erwartet: gleiche Prüfsumme, `None`, und für jeden Spieler mit
Statistikdatei ein Datum statt `nicht_aufgezeichnet`.

- [x] **Schritt 6: Aufräumen, aber erst jetzt**

Die Sicherung aus Schritt 1 und die `zusammenfuehrung.txt` erst löschen,
wenn Schritt 5 durch ist. Die rotierten `.1`/`.2.gz` bleiben liegen — sie
kosten 13 KB und sind der einzige Beleg dafür, was vor der Reparatur da
war.

---

### Aufgabe 4: Die Doku nachziehen

**Dateien:**
- Ändern: `/home/pi/pi-manager-status.md` (nicht im Repo)
- Ändern: `CLAUDE.md` im Repo und `/home/pi/CLAUDE.md`

Die Doku-Pflicht dieses Projekts ist nicht verhandelbar, und hier steht
eine Aussage, die seit dem 06.09.2026 falsch ist.

- [x] **Schritt 1: Die falsche Aussage korrigieren**

In `/home/pi/pi-manager-status.md`, Abschnitt „✅ erledigt 2026-09-01:
Pi-MCS v1.1 umgesetzt und ausgerollt", steht:

> Das Spielerprotokoll reicht jetzt über die ganze Lebenszeit des Servers.

Das stimmte am 01.09. und war am 06.09. nicht mehr wahr. Nach dem Muster
dieser Datei korrigieren — den Satz stehen lassen und darunter einrücken,
was gemessen wurde, mit Datum. Nicht löschen: Man will später sehen, dass
geprüft wurde.

- [x] **Schritt 2: Einen offenen Punkt für die Historie anlegen**

Der Punkt existiert bisher nur als Fußnote in
`docs/pflichtenheft-v1.1.md` §5 („Was v1.1 nicht umfasst") und steht in
keiner der `🟡 OFFEN`-Überschriften. Genau deshalb war er nicht
auffindbar. Als eigener Abschnitt eintragen, mit Verweis auf diesen Plan.

- [x] **Schritt 3: Die Regel in beide `CLAUDE.md` aufnehmen**

Unter „Regeln, bei denen das Naheliegende falsch ist":

> - **`player_activity.log` ist ein Hauptbuch, kein Protokoll.** Es gehört
>   in keine logrotate-Regel. Die Oberfläche liest es als Ganzes, um
>   „zuletzt gesehen" zu beantworten — eine Rotation schneidet ihr genau
>   diese Antwort weg, und zwar lautlos: Nach der Rotation stand die
>   Live-Datei auf 0 Byte und die Spielerseite meldete für Spieler mit
>   hunderten Stunden Spielzeit „nicht aufgezeichnet". Gefunden am
>   21.09.2026, verursacht am 06.09., hergestellt worden war die Historie
>   am 01.09. — fünf Tage vorher. Merksatz: **Bevor eine Datei in eine
>   Rotationsregel kommt, fragen, ob irgendwer ihre Vergangenheit liest.**

- [x] **Schritt 4: Commit (nur die Repo-Datei)**

```bash
cd ~/Pi-MCS
git add CLAUDE.md docs/superpowers/plans/2026-09-21-spieler-historie.md
git commit -m "docs: Hauptbuch-Regel und Plan zur Spieler-Historie"
```

---

# Etappe 2 — Die Historie

> ## ✅ Abgeschlossen am 21.09.2026
>
> Ausgerollt, auf dem Pi gemessen, im Container abgenommen. Die Belege
> stehen als **H2** in `PRUEFEN-AUF-DEM-PI.md`; offen bleibt dort nur die
> Sichtprüfung im Browser, die ein Mensch abnehmen muss.
>
> **Wo die Umsetzung vom Plan abwich — und warum.** Alle vier Abweichungen
> kamen aus der Messung, nicht aus dem Entwurf:
>
> - **Der Plan kannte nur EINE Datumsherleitung.** Es gibt zwei: Ein
>   Archiv nennt im Dateinamen den ersten Tag (vorwärts), `latest.log`
>   trägt seine Änderungszeit zur *letzten* Zeile (rückwärts). Die
>   geplante `Tagesuhr` konnte das nicht abbilden; herausgelöst wurden
>   deshalb die vorhandenen Funktionen, wörtlich.
> - **Die geplante Byte-Lesemarke für `latest.log` ist unmöglich.** Das
>   Datum der ersten Zeile hängt am Ende der Datei. Die Datei wird jedes
>   Mal ganz gelesen — bei 216 KB kostet das 25 ms und spart die ganze
>   Buchführung.
> - **`grund` war im Entwurf ein Sortierartefakt.** Paper schreibt für
>   eine Trennung zwei Zeilen, nur eine trägt den Grund, die Reihenfolge
>   wechselt, und 14 von 364 Paaren überspannen eine Sekundengrenze.
> - **Der Fall „Anmeldung vom zweiten Gerät" fehlte ganz.** Er sah aus wie
>   ein Serverabsturz und erzeugte eine Sitzung von null Sekunden. Zwei
>   der drei vermeintlichen Abstürze auf diesem Pi waren das.
>
> **Dazugekommen, weil es beim Messen nötig wurde:** `zeitraum()` und die
> Zahl der Sitzungen ohne bekanntes Ende — beide stehen auf der Seite,
> weil sie sonst lügen würde (545 h Spielzeit gegen 92 h Historie). Dazu
> eine Regressionsprobe über **alle** Seiten, die es vorher nicht gab.

Ab hier ist das Spielerprotokoll verlässlich. Diese Etappe baut darauf die
Seite.

## Dateien dieser Etappe

- Anlegen: `admin/logdatum.py` — Datum zu einer Logzeile (gemeinsam
  genutzt)
- Anlegen: `admin/historie.py` — Schema, Index, Abfragen
- Anlegen: `admin/seite_historie.py` — Blueprint
- Anlegen: `admin/templates/historie.html` und
  `admin/templates/teile/historienliste.html`
- Anlegen: `tools/historie-aufbauen.py` — Erstaufbau
- Ändern: `tools/spielerprotokoll-nachtragen.py` — benutzt `logdatum.py`
- Ändern: `admin/app.py` — Blueprint registrieren
- Ändern: `admin/templates/basis.html` — Menüpunkt
- Ändern: `lib/dateien.sh` — die neuen Dateien in die gemeinsame Liste
- Ändern: `mcs.conf.beispiel` — `MCS_HISTORIE_TAGE`

---

### Aufgabe 5: Die Datumsherleitung gemeinsam nutzbar machen

**Dateien:**
- Anlegen: `admin/logdatum.py`
- Ändern: `tools/spielerprotokoll-nachtragen.py`
- Ändern: `tests/pruefung-historie.py`

**Schnittstellen:**
- Liefert: `logdatum.datum_fuer_datei(pfad) -> datetime.date` — der Tag,
  an dem die erste Zeile dieser Datei geschrieben wurde.
- Liefert: `logdatum.Tagesuhr(starttag)` mit Methode
  `.zeitpunkt(uhrzeit_text) -> datetime` — zählt den Tag hoch, sobald die
  Uhrzeit zurückspringt.

**Warum zuerst:** In den Serverlogzeilen steht **kein Datum**, nur
`[HH:MM:SS]`. Der Tag kommt beim Archiv aus dem Dateinamen, bei
`latest.log` aus der letzten Änderung, und bei einem Serverlauf über
Mitternacht erkennt man den Tageswechsel nur daran, dass die Uhrzeit
zurückspringt. Diese Logik existiert bereits in
`tools/spielerprotokoll-nachtragen.py` und ist dort geprüft (W3,
01.09.2026, einschließlich zweier synthetischer Mitternachtsfälle).

Sie ein zweites Mal zu schreiben wäre genau der Fehler, der in diesem
Projekt am teuersten war — „ein zweiter Weg zur selben Sache, der die
Regel des ersten nicht kennt". Deshalb wird sie **herausgelöst**, nicht
nachgebaut, und das vorhandene Werkzeug benutzt ab jetzt dieselbe Datei.

- [x] **Schritt 1: Die Prüfung schreiben**

In `tests/pruefung-historie.py` ergänzen:

```python
def pruefe_logdatum():
    """Die beiden Faelle aus W3 (01.09.2026), jetzt gegen das
    herausgeloeste Modul statt gegen das Werkzeug."""
    ld = lade("logdatum", REPO / "admin" / "logdatum.py")
    from datetime import date

    pruefe(ld.datum_fuer_datei(Path("2026-05-10-1.log.gz")) == date(2026, 5, 10),
           "Das Datum wird nicht aus dem Archivnamen gelesen.")

    uhr = ld.Tagesuhr(date(2026, 5, 10))
    erste = uhr.zeitpunkt("23:58:00")
    zweite = uhr.zeitpunkt("00:03:00")
    pruefe(erste.date() == date(2026, 5, 10),
           "Die Zeit vor Mitternacht landet auf dem falschen Tag.")
    pruefe(zweite.date() == date(2026, 5, 11),
           "Der Tageswechsel um Mitternacht wird nicht erkannt.")

    uhr2 = ld.Tagesuhr(date(2026, 5, 10))
    pruefe(uhr2.zeitpunkt("10:00:00") < uhr2.zeitpunkt("11:00:00"),
           "Eine aufsteigende Uhrzeit darf den Tag nicht hochzaehlen.")
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: Fehlschlag, `admin/logdatum.py` fehlt.

- [x] **Schritt 3: `admin/logdatum.py` schreiben**

Der Inhalt ist die vorhandene Logik aus
`tools/spielerprotokoll-nachtragen.py`, unverändert übernommen und in
zwei Bausteine geschnitten. **Nicht neu erfinden** — die dortige Fassung
ist gemessen, diese soll sich genauso verhalten.

```python
#!/usr/bin/env python3
"""
logdatum.py — Welcher Tag gehoert zu einer Serverlogzeile?

In den Logzeilen steht kein Datum, nur [HH:MM:SS]. Diese Datei loest das
an EINER Stelle, weil es zwei Leser gibt: das Nachtragswerkzeug
(tools/spielerprotokoll-nachtragen.py) und den Historien-Index
(admin/historie.py). Vorher stand die Logik nur im Werkzeug; ein
Nachbau im Index waere der Fehler gewesen, der in diesem Projekt am
haeufigsten aufgetreten ist -- ein zweiter Weg zur selben Sache, der die
Regel des ersten nicht kennt.

Zwei Regeln, beide am 01.09.2026 geprueft (W3), einschliesslich zweier
synthetisch nachgestellter Mitternachtsfaelle:

 1. Der Starttag kommt beim Archiv aus dem Dateinamen
    ("2026-05-10-1.log.gz"), bei latest.log aus der letzten Aenderung der
    Datei.
 2. Laeuft ein Server ueber Mitternacht, springt die Uhrzeit zurueck.
    Daran, und nur daran, ist der Tageswechsel zu erkennen.
"""

import re
from datetime import date, datetime, time, timedelta
from pathlib import Path

_ARCHIVNAME = re.compile(r"^(\d{4})-(\d{2})-(\d{2})-\d+\.log(\.gz)?$")


def datum_fuer_datei(pfad):
    """Der Tag, an dem die erste Zeile dieser Datei geschrieben wurde."""
    pfad = Path(pfad)
    treffer = _ARCHIVNAME.match(pfad.name)
    if treffer:
        return date(int(treffer.group(1)), int(treffer.group(2)),
                    int(treffer.group(3)))
    # latest.log: die letzte Aenderung ist der Tag der LETZTEN Zeile.
    # Der Starttag ergibt sich erst beim Lesen -- die Tagesuhr zaehlt
    # vorwaerts, also beginnt sie hier bewusst am selben Tag und wird vom
    # Aufrufer zurueckgesetzt, wenn er es besser weiss.
    return date.fromtimestamp(pfad.stat().st_mtime)


class Tagesuhr:
    """Macht aus "[23:58:00]", "[00:03:00]" zwei Zeitpunkte an zwei Tagen.

    Zustandsbehaftet und ABSICHTLICH nicht wiederverwendbar ueber
    Dateigrenzen hinweg: Je gelesener Logdatei eine eigene Uhr. Wer eine
    Uhr fuer zwei Dateien benutzt, zaehlt beim Dateiwechsel einen Tag zu
    viel.
    """

    def __init__(self, starttag):
        self._tag = starttag
        self._vorige = None

    def zeitpunkt(self, uhrzeit_text):
        stunde, minute, sekunde = (int(t) for t in uhrzeit_text.split(":"))
        jetzt = time(stunde, minute, sekunde)
        if self._vorige is not None and jetzt < self._vorige:
            self._tag += timedelta(days=1)
        self._vorige = jetzt
        return datetime.combine(self._tag, jetzt)
```

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`

- [x] **Schritt 5: Das Nachtragswerkzeug auf das Modul umstellen**

In `tools/spielerprotokoll-nachtragen.py` die eigene Datums- und
Mitternachtslogik entfernen und stattdessen `admin/logdatum.py` benutzen:

```python
import sys
from pathlib import Path

# Das Werkzeug liegt in tools/, das gemeinsame Modul in admin/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "admin"))
import logdatum  # noqa: E402
```

- [x] **Schritt 6: Nachmessen, dass sich nichts geändert hat**

Der entscheidende Beleg: Das umgestellte Werkzeug muss auf demselben
Datenbestand **dieselbe Datei** erzeugen wie vorher.

```bash
cd ~/Pi-MCS
md5sum ~/mcs/player_activity.log
python3 tools/spielerprotokoll-nachtragen.py
md5sum ~/mcs/player_activity.log     # muss unveraendert sein
```

- [x] **Schritt 7: `make` und Commit**

```bash
make && python3 tests/pruefung-historie.py
git add admin/logdatum.py tools/spielerprotokoll-nachtragen.py tests/pruefung-historie.py
git commit -m "refactor: Datumsherleitung aus dem Logdateinamen an eine Stelle

Der Historien-Index braucht dieselbe Logik wie das Nachtragswerkzeug.
Sie ein zweites Mal zu schreiben waere der Fehler gewesen, der in
diesem Projekt am haeufigsten Geld gekostet hat. Nachgemessen: Das
umgestellte Werkzeug erzeugt dieselbe Datei wie vorher."
```

---

### Aufgabe 6: Schema und Sitzungs-Index

**Dateien:**
- Anlegen: `admin/historie.py`
- Ändern: `tests/pruefung-historie.py`

**Schnittstellen:**
- Liefert: `historie.verbindung() -> sqlite3.Connection` (legt das Schema
  an, wenn es fehlt)
- Liefert: `historie.sitzungen_einlesen(hauptbuch, db) -> int` — Anzahl
  neu eingetragener Sitzungen, wiederholbar
- Wird benutzt von: Aufgabe 7 (Chat), Aufgabe 8 (Abfragen und Seite)

**Die Entscheidung, die hier fällt — offene Sitzungen.** Ein Beitritt ohne
zugehöriges Verlassen kommt vor: Serverabsturz, harter Neustart. Drei
Möglichkeiten, und die naheliegende ist die falsche:

| Umgang | Folge |
|---|---|
| Sitzung verwerfen | Spielzeit verschwindet, obwohl jemand nachweislich da war |
| Ende raten (z. B. +30 min) | Eine erfundene Zahl, die wie eine gemessene aussieht |
| **Ende = letzte Zeile dieses Serverlaufs, Grund `abbruch`** | **Untergrenze, belegt — und als solche gekennzeichnet** |

Gewählt ist die dritte. Sie sagt „mindestens so lange", und die Oberfläche
zeigt solche Sitzungen mit einem `≈`. Das ist Leitsatz 5: lieber melden,
dass etwas nicht genau bekannt ist, als es zu verstecken.

- [x] **Schritt 1: Die Prüfung schreiben**

```python
def pruefe_sitzungen(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")

    hauptbuch = tmp / "hauptbuch.log"
    hauptbuch.write_text(
        "Spieler-Aktivitaetslog (Pi-MCS)\n"
        "------------------------------\n"
        "2026-05-10 20:00:00 | Spieler_A ist dem Spiel beigetreten\n"
        "2026-05-10 21:30:00 | Spieler_A hat das Spiel verlassen\n"
        "2026-05-11 09:00:00 | Spieler_B ist dem Spiel beigetreten\n"
        "2026-05-11 09:45:00 | Spieler_B hat die Verbindung verloren "
        "(Grund: Disconnected)\n"
        "2026-05-12 10:00:00 | Spieler_A ist dem Spiel beigetreten\n"
        "2026-05-13 08:00:00 | Spieler_A ist dem Spiel beigetreten\n",
        encoding="utf-8")

    db = h.verbindung(tmp / "historie.db")
    anzahl = h.sitzungen_einlesen(hauptbuch, db)
    pruefe(anzahl == 4, f"Vier Sitzungen erwartet, {anzahl} eingelesen.")

    zeilen = db.execute(
        "SELECT spieler, beginn, ende, sekunden, grund FROM sitzung "
        "ORDER BY beginn").fetchall()

    pruefe(zeilen[0][3] == 5400,
           "Eine Sitzung von 20:00 bis 21:30 muss 5400 Sekunden ergeben.")
    pruefe(zeilen[1][4] == "verbindung",
           "Ein Verbindungsabbruch muss als Grund 'verbindung' stehen.")
    pruefe(zeilen[2][4] == "abbruch",
           "Ein Beitritt ohne Ende muss als 'abbruch' gelten, nicht "
           "verworfen werden.")
    pruefe(zeilen[3][2] is None and zeilen[3][3] is None,
           "Die letzte, noch offene Sitzung darf kein erfundenes Ende "
           "bekommen.")

    # Wiederholbarkeit: derselbe Lauf noch einmal aendert nichts.
    pruefe(h.sitzungen_einlesen(hauptbuch, db) == 0,
           "Ein zweiter Lauf traegt Sitzungen doppelt ein.")
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: Fehlschlag, `admin/historie.py` fehlt.

- [x] **Schritt 3: `admin/historie.py` mit Schema und Sitzungslesen**

```python
#!/usr/bin/env python3
"""
historie.py — Wer war wann online, und was wurde dabei gesagt.

Zwei Quellen, eine Ablage:

  Sitzungen  <- player_activity.log (das Hauptbuch)
  Chat und   <- mc_server/logs/*.log.gz und latest.log
  Befehle

Beides landet in admin/historie.db. Warum eine eigene Datei und nicht
metrik.db: Die Metriken sind Messwerte mit kurzer Halbwertszeit, die
Historie ist ein Archiv mit eigener Aufbewahrungsfrist -- und sie enthaelt
Chat-Inhalte, also etwas, das Menschen einander geschrieben haben. Das
gehoert hinter eigene Rechte (chmod 600, siehe Aufgabe 9) und nicht in
eine Datei, die daneben Temperaturkurven fuehrt.

Warum kein Timer und kein eigener Dienst: Der Index wird beim Oeffnen der
Seite fortgeschrieben, nicht im Hintergrund. Bei geschlossener Oberflaeche
kostet die Historie damit null Rechenzeit -- Leitsatz 1. Den ersten,
grossen Durchlauf uebernimmt tools/historie-aufbauen.py.
"""

import sqlite3
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS sitzung (
  spieler  TEXT    NOT NULL,
  beginn   TEXT    NOT NULL,          -- 'YYYY-MM-DD HH:MM:SS', Lokalzeit
  ende     TEXT,                      -- NULL = laeuft noch
  sekunden INTEGER,                   -- NULL, solange ende NULL ist
  grund    TEXT,                      -- verlassen | verbindung | abbruch
  PRIMARY KEY (spieler, beginn)
);
CREATE INDEX IF NOT EXISTS sitzung_beginn ON sitzung (beginn);

CREATE TABLE IF NOT EXISTS aeusserung (
  zeit    TEXT NOT NULL,
  spieler TEXT NOT NULL,
  art     TEXT NOT NULL,              -- chat | befehl
  inhalt  TEXT NOT NULL,
  PRIMARY KEY (zeit, spieler, art, inhalt)
);
CREATE INDEX IF NOT EXISTS aeusserung_zeit ON aeusserung (zeit);

-- Bis wohin eine Quelldatei gelesen wurde. "fertig" heisst: ein Archiv,
-- das sich nie wieder aendert. latest.log ist nie fertig -- dort zaehlt
-- "groesse" als Lesemarke, und "inode" verraet, ob Paper die Datei beim
-- Neustart ausgetauscht hat (dann von vorn lesen).
CREATE TABLE IF NOT EXISTS quelle (
  datei   TEXT PRIMARY KEY,
  inode   INTEGER,
  groesse INTEGER NOT NULL DEFAULT 0,
  fertig  INTEGER NOT NULL DEFAULT 0
);
"""

# Zeilenformat des Hauptbuchs:
#   2026-05-10 20:00:00 | Spieler_A ist dem Spiel beigetreten
import re  # noqa: E402  (bewusst hier, direkt ueber den Mustern)

_ZEILE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| (.+)$")
_BEITRITT = re.compile(r"^([A-Za-z0-9_]{1,16}) ist dem Spiel beigetreten$")
_VERLASSEN = re.compile(r"^([A-Za-z0-9_]{1,16}) hat das Spiel verlassen$")
_VERBINDUNG = re.compile(
    r"^([A-Za-z0-9_]{1,16}) hat die Verbindung verloren \(Grund: ")


def verbindung(pfad):
    """Oeffnet die Historien-Datenbank und legt das Schema an, wenn noetig."""
    db = sqlite3.connect(str(pfad))
    db.executescript(SCHEMA)
    db.commit()
    return db


def _sekunden(beginn, ende):
    from datetime import datetime
    form = "%Y-%m-%d %H:%M:%S"
    return int((datetime.strptime(ende, form)
                - datetime.strptime(beginn, form)).total_seconds())


def sitzungen_einlesen(hauptbuch, db):
    """Traegt alle Sitzungen des Hauptbuchs ein. Liefert die Anzahl NEUER.

    Wiederholbar: Der Primaerschluessel (spieler, beginn) faengt Doppelte
    ab, und offene Sitzungen werden bei jedem Lauf neu berechnet -- eine
    Sitzung, die beim letzten Mal noch lief, bekommt jetzt ihr Ende.

    Zum Grund "abbruch": Ein Beitritt ohne zugehoeriges Ende entsteht bei
    einem Serverabsturz. Die Sitzung wird NICHT verworfen (dann fehlte
    belegte Spielzeit) und ihr Ende NICHT geraten (das waere eine
    erfundene Zahl, die wie eine gemessene aussieht), sondern auf die
    letzte bekannte Zeile gesetzt und als Untergrenze gekennzeichnet.
    """
    offen = {}        # spieler -> beginn
    fertige = []      # (spieler, beginn, ende, sekunden, grund)
    letzte_zeit = None

    with open(hauptbuch, "r", encoding="utf-8", errors="ignore") as f:
        for zeile in f:
            treffer = _ZEILE.match(zeile.rstrip("\n"))
            if not treffer:
                continue
            zeit, text = treffer.group(1), treffer.group(2)
            letzte_zeit = zeit

            beitritt = _BEITRITT.match(text)
            if beitritt:
                name = beitritt.group(1)
                # Zweiter Beitritt ohne Ende dazwischen: Der Server ist
                # zwischendurch gestorben. Die vorige Sitzung endet mit
                # der letzten Zeile, die wir vor diesem Beitritt gesehen
                # haben.
                if name in offen:
                    fertige.append((name, offen[name], zeit,
                                    _sekunden(offen[name], zeit), "abbruch"))
                offen[name] = zeit
                continue

            for muster, grund in ((_VERLASSEN, "verlassen"),
                                  (_VERBINDUNG, "verbindung")):
                ende = muster.match(text)
                if not ende:
                    continue
                name = ende.group(1)
                if name in offen:
                    fertige.append((name, offen.pop(name), zeit,
                                    _sekunden(offen[name] if name in offen
                                              else zeit, zeit), grund))
                break

    # Was am Ende des Hauptbuchs noch offen ist, laeuft entweder gerade
    # oder der Server steht. Beides bekommt KEIN Ende -- "laeuft noch" und
    # "wissen wir nicht" sind ehrlicher als eine Zahl.
    for name, beginn in offen.items():
        fertige.append((name, beginn, None, None, None))

    vorher = db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0]
    db.executemany(
        "INSERT OR REPLACE INTO sitzung "
        "(spieler, beginn, ende, sekunden, grund) VALUES (?, ?, ?, ?, ?)",
        fertige)
    db.commit()
    nachher = db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0]
    return nachher - vorher
```

> **Hinweis für die Umsetzung:** Die Zeile mit
> `_sekunden(offen[name] if name in offen else zeit, zeit)` ist absichtlich
> hier als Stolperstelle markiert — `offen.pop(name)` hat den Eintrag zu
> diesem Zeitpunkt bereits entfernt. Vor dem `pop` in eine lokale Variable
> lesen und diese benutzen. Die Prüfung aus Schritt 1 fällt darauf herein,
> wenn es falsch gemacht wird (`zeilen[0][3] == 5400`).

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: alle Sitzungsprüfungen grün, insbesondere `5400` und die
Wiederholbarkeit.

- [x] **Schritt 5: `make` und Commit**

```bash
make && python3 tests/pruefung-historie.py
git add admin/historie.py tests/pruefung-historie.py
git commit -m "feat: Sitzungs-Index fuer die Spieler-Historie

Sitzungen aus dem Hauptbuch in admin/historie.db. Ein Beitritt ohne
Ende (Serverabsturz) wird als Untergrenze gefuehrt und gekennzeichnet,
statt verworfen oder geraten zu werden."
```

---

### Aufgabe 7: Chat und Befehle indizieren

**Dateien:**
- Ändern: `admin/historie.py`
- Ändern: `tests/pruefung-historie.py`

**Schnittstellen:**
- Verbraucht: `logdatum.datum_fuer_datei`, `logdatum.Tagesuhr` (Aufgabe 5);
  `historie.verbindung` (Aufgabe 6)
- Liefert: `historie.aeusserungen_einlesen(logordner, db) -> int`

**Woher die Muster kommen:** aus `tools/log-muster.sh` über
`protokoll.lade_log_muster()`. `MUSTER_BEFEHL` steht dort bereits;
`CHAT_RE` lebt in `admin/protokoll.py`, weil die Shell es nicht ausdrücken
kann. **Beide von dort importieren, keine dritte Liste anlegen** — die
Datei `log-muster.sh` existiert genau deshalb.

- [x] **Schritt 1: Die Prüfung schreiben**

```python
import gzip


def pruefe_aeusserungen(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")

    logs = tmp / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    with gzip.open(logs / "2026-05-10-1.log.gz", "wt", encoding="utf-8") as f:
        f.write("[23:58:00] [Server thread/INFO]: <Spieler_A> hallo\n")
        f.write("[23:59:00] [Server thread/INFO]: Spieler_A issued server "
                "command: /home\n")
        f.write("[00:03:00] [Server thread/INFO]: <Spieler_B> gute nacht\n")
        f.write("[00:04:00] [Server thread/INFO]: Nichts davon\n")

    db = h.verbindung(tmp / "historie2.db")
    anzahl = h.aeusserungen_einlesen(logs, db)
    pruefe(anzahl == 3, f"Drei Aeusserungen erwartet, {anzahl} gefunden.")

    zeilen = db.execute(
        "SELECT zeit, spieler, art, inhalt FROM aeusserung "
        "ORDER BY zeit").fetchall()
    pruefe(zeilen[0][0].startswith("2026-05-10 23:58"),
           "Die Zeile vor Mitternacht landet auf dem falschen Tag.")
    pruefe(zeilen[2][0].startswith("2026-05-11 00:03"),
           "Der Tageswechsel im Archiv wird nicht erkannt.")
    pruefe(zeilen[1][2] == "befehl" and zeilen[1][3] == "/home",
           "Ein Serverbefehl wird nicht als solcher erfasst.")
    pruefe(zeilen[0][2] == "chat" and zeilen[0][3] == "hallo",
           "Eine Chatnachricht wird nicht als solche erfasst.")

    pruefe(h.aeusserungen_einlesen(logs, db) == 0,
           "Ein fertiges Archiv wird ein zweites Mal gelesen.")
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`
Erwartet: `AttributeError: module 'historie' has no attribute
'aeusserungen_einlesen'`.

- [x] **Schritt 3: `aeusserungen_einlesen` schreiben**

```python
import gzip

import logdatum
from protokoll import CHAT_RE, COMMAND_RE


def _zeilen(pfad, ab_byte=0):
    """Liest eine Logdatei, gepackt oder nicht, ab einer Lesemarke.

    Kein "zcat | grep": Gepackte Protokolle und set -o pipefail sind in
    diesem Projekt schon einmal aufeinandergestossen (grep bricht ab, tar
    bekommt SIGPIPE, Rueckgabewert 141 trotz Treffer). In Python mit dem
    gzip-Modul gibt es diese Falle nicht.
    """
    if str(pfad).endswith(".gz"):
        with gzip.open(pfad, "rt", encoding="utf-8", errors="ignore") as f:
            for zeile in f:
                yield zeile.rstrip("\n")
        return
    with open(pfad, "r", encoding="utf-8", errors="ignore") as f:
        f.seek(ab_byte)
        for zeile in f:
            yield zeile.rstrip("\n")


# Aus einer Logzeile die Uhrzeit ziehen: "[23:58:00] [Server thread/INFO]:"
_UHRZEIT = re.compile(r"^\[(\d{2}:\d{2}:\d{2})\]")


def aeusserungen_einlesen(logordner, db):
    """Traegt Chat und Befehle aus den Serverprotokollen ein.

    Fortlaufend: Ein Archiv (*.log.gz) wird genau einmal gelesen und als
    "fertig" vermerkt. latest.log waechst und wird ab der letzten
    Lesemarke weitergelesen -- ausser die Inode hat sich geaendert, dann
    hat Paper die Datei beim Neustart ausgetauscht und es geht von vorn
    los.
    """
    logordner = Path(logordner)
    neu = 0

    stand = {datei: (inode, groesse, fertig) for datei, inode, groesse, fertig
             in db.execute("SELECT datei, inode, groesse, fertig FROM quelle")}

    dateien = sorted(p for p in logordner.iterdir()
                     if p.name.endswith((".log", ".log.gz")))

    for pfad in dateien:
        ist_archiv = pfad.name.endswith(".gz")
        info = pfad.stat()
        voriger = stand.get(pfad.name)

        if voriger and voriger[2]:          # fertiges Archiv
            continue

        ab_byte = 0
        if voriger and not ist_archiv:
            vorige_inode, vorige_groesse, _ = voriger
            # Gleiche Inode und nicht geschrumpft -> weiterlesen.
            if vorige_inode == info.st_ino and info.st_size >= vorige_groesse:
                ab_byte = vorige_groesse
            if ab_byte >= info.st_size:
                continue

        uhr = logdatum.Tagesuhr(logdatum.datum_fuer_datei(pfad))
        eintraege = []
        for zeile in _zeilen(pfad, ab_byte):
            zeit = _UHRZEIT.match(zeile)
            if not zeit:
                continue
            zeitpunkt = uhr.zeitpunkt(zeit.group(1))

            befehl = COMMAND_RE.match(zeile)
            if befehl:
                eintraege.append((zeitpunkt.strftime("%Y-%m-%d %H:%M:%S"),
                                  befehl.group(2), "befehl", befehl.group(3)))
                continue
            chat = CHAT_RE.search(zeile)
            if chat:
                eintraege.append((zeitpunkt.strftime("%Y-%m-%d %H:%M:%S"),
                                  chat.group(1), "chat", chat.group(2)))

        vorher = db.execute("SELECT COUNT(*) FROM aeusserung").fetchone()[0]
        db.executemany(
            "INSERT OR IGNORE INTO aeusserung (zeit, spieler, art, inhalt) "
            "VALUES (?, ?, ?, ?)", eintraege)
        db.execute(
            "INSERT OR REPLACE INTO quelle (datei, inode, groesse, fertig) "
            "VALUES (?, ?, ?, ?)",
            (pfad.name, info.st_ino, info.st_size, 1 if ist_archiv else 0))
        db.commit()
        neu += db.execute(
            "SELECT COUNT(*) FROM aeusserung").fetchone()[0] - vorher

    return neu
```

> **Zur Datumsherleitung bei `latest.log`:** `datum_fuer_datei` liefert
> dort den Tag der **letzten** Änderung, die Tagesuhr zählt aber vorwärts.
> Bei einem Serverlauf über Mitternacht liegt der Startteil damit einen Tag
> zu spät. Genau so verfährt bereits `spielerprotokoll-nachtragen.py`, und
> dort ist es am 01.09.2026 synthetisch geprüft worden. **Nicht
> abweichen** — zwei Werkzeuge, die dieselbe Datei unterschiedlich
> datieren, erzeugen widersprüchliche Anzeigen.

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`

- [x] **Schritt 5: `make` und Commit**

```bash
make && python3 tests/pruefung-historie.py
git add admin/historie.py tests/pruefung-historie.py
git commit -m "feat: Chat und Befehle in den Historien-Index

Archive werden einmal gelesen und als fertig vermerkt, latest.log ab
der Lesemarke weiter. Muster kommen aus tools/log-muster.sh, nicht aus
einer dritten Liste."
```

---

### Aufgabe 8: Abfragen, Seite und Menüpunkt

**Dateien:**
- Ändern: `admin/historie.py` — Abfragen
- Anlegen: `admin/seite_historie.py`
- Anlegen: `admin/templates/historie.html`
- Anlegen: `admin/templates/teile/historienliste.html`
- Ändern: `admin/app.py` — Blueprint registrieren
- Ändern: `admin/templates/basis.html` — Menüpunkt „Historie"
- Ändern: `lib/dateien.sh` — die neuen Dateien in die gemeinsame Liste

**Schnittstellen:**
- Liefert: `historie.sitzungen(db, spieler=None, ab=None, grenze=200)`
  → Liste von `dict` mit `spieler, beginn, ende, sekunden, grund`
- Liefert: `historie.summen_je_tag(db, tage=30)` → Liste von `dict` mit
  `tag, spieler, sekunden`
- Liefert: `historie.aeusserungen(db, spieler=None, ab=None, grenze=200)`
- Liefert: `historie.aktualisieren(db, hauptbuch, logordner) -> dict`
  mit `{"sitzungen": int, "aeusserungen": int}` — der Aufruf, den die
  Seite beim Öffnen macht

**Zur Last — die Regel dieses Projekts:** RCON läuft im Hauptthread des
Servers, eine Abfrage je Klick ist richtig, eine je Sekunde nicht. Hier
wird gar kein RCON gebraucht, aber dieselbe Haltung gilt für den Index:
`aktualisieren()` läuft beim **Seitenaufruf**, nicht in einem
HTMX-Intervall. Die Historienseite bekommt bewusst **kein**
`hx-trigger="every …"`.

- [x] **Schritt 1: Die Prüfung für die Abfragen schreiben**

```python
def pruefe_abfragen(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")
    db = h.verbindung(tmp / "historie3.db")
    db.executemany(
        "INSERT INTO sitzung (spieler, beginn, ende, sekunden, grund) "
        "VALUES (?, ?, ?, ?, ?)",
        [("Spieler_A", "2026-05-10 20:00:00", "2026-05-10 21:00:00",
          3600, "verlassen"),
         ("Spieler_A", "2026-05-11 20:00:00", "2026-05-11 20:30:00",
          1800, "verlassen"),
         ("Spieler_B", "2026-05-11 09:00:00", "2026-05-11 10:00:00",
          3600, "verlassen")])
    db.commit()

    alle = h.sitzungen(db)
    pruefe(alle[0]["beginn"] > alle[-1]["beginn"],
           "Sitzungen muessen neueste zuerst kommen.")

    nur_a = h.sitzungen(db, spieler="Spieler_A")
    pruefe(len(nur_a) == 2,
           "Der Filter nach Spieler greift nicht.")

    summen = {(s["tag"], s["spieler"]): s["sekunden"]
              for s in h.summen_je_tag(db, tage=3650)}
    pruefe(summen.get(("2026-05-11", "Spieler_A")) == 1800,
           "Die Tagessumme je Spieler stimmt nicht.")
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`

- [x] **Schritt 3: Die Abfragen in `admin/historie.py` ergänzen**

```python
def _als_dicts(zeilen, felder):
    return [dict(zip(felder, z)) for z in zeilen]


def sitzungen(db, spieler=None, ab=None, grenze=200):
    """Sitzungen, neueste zuerst. `ab` ist ein Tag als 'YYYY-MM-DD'."""
    frage = ("SELECT spieler, beginn, ende, sekunden, grund FROM sitzung "
             "WHERE 1=1")
    werte = []
    if spieler:
        frage += " AND spieler = ?"
        werte.append(spieler)
    if ab:
        frage += " AND beginn >= ?"
        werte.append(ab)
    frage += " ORDER BY beginn DESC LIMIT ?"
    werte.append(grenze)
    return _als_dicts(db.execute(frage, werte).fetchall(),
                      ("spieler", "beginn", "ende", "sekunden", "grund"))


def summen_je_tag(db, tage=30):
    """Spielzeit je Tag und Spieler -- die Grundlage der Balken."""
    from datetime import date, timedelta
    ab = (date.today() - timedelta(days=tage)).isoformat()
    zeilen = db.execute(
        "SELECT substr(beginn, 1, 10) AS tag, spieler, SUM(sekunden) "
        "FROM sitzung WHERE sekunden IS NOT NULL AND beginn >= ? "
        "GROUP BY tag, spieler ORDER BY tag DESC", (ab,)).fetchall()
    return _als_dicts(zeilen, ("tag", "spieler", "sekunden"))


def aeusserungen(db, spieler=None, ab=None, grenze=200):
    frage = "SELECT zeit, spieler, art, inhalt FROM aeusserung WHERE 1=1"
    werte = []
    if spieler:
        frage += " AND spieler = ?"
        werte.append(spieler)
    if ab:
        frage += " AND zeit >= ?"
        werte.append(ab)
    frage += " ORDER BY zeit DESC LIMIT ?"
    werte.append(grenze)
    return _als_dicts(db.execute(frage, werte).fetchall(),
                      ("zeit", "spieler", "art", "inhalt"))


def aktualisieren(db, hauptbuch, logordner):
    """Schreibt den Index fort. Wird beim Seitenaufruf gerufen, nie im Takt."""
    return {"sitzungen": sitzungen_einlesen(hauptbuch, db),
            "aeusserungen": aeusserungen_einlesen(logordner, db)}
```

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`

- [x] **Schritt 5: `admin/seite_historie.py` schreiben**

```python
#!/usr/bin/env python3
"""
seite_historie.py — Wer war wann online, wie lange, und was wurde gesagt.

Der Index wird beim Aufruf dieser Seite fortgeschrieben und NICHT in
einem Takt: Bei geschlossener Oberflaeche kostet die Historie dann null
Rechenzeit (Leitsatz 1). Deshalb hat diese Seite auch kein
hx-trigger="every ..." -- anders als die Startseite, die einen Zustand
zeigt. Eine Historie aendert sich nicht, waehrend man sie ansieht.
"""

from pathlib import Path

from flask import Blueprint, render_template, request

import historie as historiendaten
import protokollpruefung
from einstellungen import HISTORIE_DB, MINECRAFT_LOG, PLAYER_ACTIVITY_LOG
from sicherheit import auth_required

historie = Blueprint("historie", __name__)


def _seitendaten():
    db = historiendaten.verbindung(HISTORIE_DB)
    historiendaten.aktualisieren(db, PLAYER_ACTIVITY_LOG,
                                 Path(MINECRAFT_LOG).parent)
    gewaehlt = (request.args.get("spieler") or "").strip() or None
    return {
        "gewaehlt": gewaehlt,
        "sitzungen": historiendaten.sitzungen(db, spieler=gewaehlt),
        "summen": historiendaten.summen_je_tag(db, tage=30),
        "aeusserungen": historiendaten.aeusserungen(db, spieler=gewaehlt),
        # Derselbe Hinweis wie auf der Startseite: Fehlt dem Hauptbuch die
        # Vergangenheit, ist auch diese Seite unvollstaendig -- und das
        # muss dort stehen, wo jemand die Luecke sieht.
        "protokoll_befund": protokollpruefung.protokoll_lueckenhaft(
            PLAYER_ACTIVITY_LOG, Path(MINECRAFT_LOG).parent),
    }


@historie.get("/historie")
@auth_required
def index():
    return render_template("historie.html", **_seitendaten())


@historie.get("/teil/historienliste")
@auth_required
def teil_liste():
    return render_template("teile/historienliste.html", **_seitendaten())
```

- [x] **Schritt 6: `HISTORIE_DB` in `admin/einstellungen.py` ergänzen**

Nach dem Muster der vorhandenen Pfade, gelesen aus `mcs.conf` mit
Rückfallwert `<MCS_ADMIN_DIR>/historie.db`. **Anführungszeichen abnehmen** —
Python muss das selbst tun, Shell und systemd nicht (`CLAUDE.md`, der
Abschnitt über die drei Leser der `mcs.conf`).

- [x] **Schritt 7: Vorlagen, Menüpunkt, Blueprint**

- `admin/templates/historie.html` nach dem Muster von `spieler.html`:
  Rahmen mit `hx-get` auf `historie.teil_liste`, **ohne** `every`.
- `admin/templates/teile/historienliste.html`: drei Blöcke — Balken je Tag
  (Summen), Sitzungstabelle, Chat/Befehle. Eine Sitzung mit
  `grund == "abbruch"` bekommt ein `≈` vor der Dauer und einen `title`
  mit der Erklärung („Serverabsturz, Dauer ist eine Untergrenze").
  Eine Sitzung ohne `ende` zeigt „läuft noch".
- `admin/app.py`: `app.register_blueprint(historie)`.
- `admin/templates/basis.html`: Menüpunkt „Historie" neben „Spieler".
- `lib/dateien.sh`: die vier neuen Dateien eintragen — **dort und nur
  dort**, `install.sh` und `deploy.sh` arbeiten dieselbe Liste ab.

- [x] **Schritt 8: Im Browser ansehen**

`make` prüft kein JavaScript und kein Layout. Am 02.09.2026 hat ein `*/`
zu viel einen kompletten `<script>`-Block abgeschaltet, ohne dass eine
Prüfung rot wurde.

```bash
bash tests/oberflaeche-ansehen.sh
```

Erwartet: Die Seite lädt, die Balken sind da, die Tabelle ist gefüllt,
kein Fehler in der Browser-Konsole. **Diese Prüfung kann nur ein Mensch
abnehmen** — ein `curl`-Abruf beweist hier nichts.

- [x] **Schritt 9: `make` und Commit**

```bash
make && python3 tests/pruefung-historie.py
git add admin/historie.py admin/seite_historie.py admin/einstellungen.py \
        admin/app.py admin/templates/ lib/dateien.sh tests/pruefung-historie.py
git commit -m "feat: Seite 'Historie' -- Sitzungen, Spielzeit je Tag, Chat

Der Index wird beim Seitenaufruf fortgeschrieben, nicht im Takt: bei
geschlossener Oberflaeche kostet die Historie null Rechenzeit."
```

---

### Aufgabe 9: Erstaufbau, Aufbewahrung und Rechte

**Dateien:**
- Anlegen: `tools/historie-aufbauen.py`
- Ändern: `admin/historie.py` — `aufraeumen()`
- Ändern: `mcs.conf.beispiel` — `MCS_HISTORIE_TAGE`
- Ändern: `install.sh` — Rechte auf `historie.db`
- Ändern: `tests/pruefung-historie.py`

**Die beiden Entscheidungen, die das Pflichtenheft offengelassen hat:**

**Aufbewahrung.** Neuer Schlüssel `MCS_HISTORIE_TAGE` in `mcs.conf`,
Vorgabe `0` = **unbegrenzt**. Begründung: Sitzungen sind winzig (eine
Zeile je Besuch), und die Frage „wer war im letzten Sommer da" ist genau
die, wegen der man so eine Seite baut. Wer kürzer aufbewahren will, setzt
eine Zahl.

> **Falle, die hier schon einmal zugeschlagen hat:** `${X:-standard}`
> greift **nicht** bei einer ausdrücklichen `0`. Aus
> `MCS_BACKUP_BEHALTEN=0` wurde einmal `tail -n +1`, also *jede* Zeile —
> ein Lauf räumte beide Backup-Platten leer. `0` muss hier ausdrücklich
> „aus" heißen, und was keine Zahl ist, fällt laut gemeldet auf den
> Standard zurück. Die vorhandene `zahl_aus_conf` benutzen, nichts
> Eigenes.

**Namen und Chat-Inhalte.** Die Historie enthält, was Menschen einander
geschrieben haben, dazu Spielernamen. Sie bleibt auf dem Pi, in
`admin/historie.db` mit **`chmod 600`**, und verlässt ihn nie. Ins
Repository kommt davon nichts — auch nicht als Messbeleg; Platzhalter
(`Spieler_A`) beweisen dasselbe. Das ist keine neue Regel, sondern die
bestehende aus `CLAUDE.md` angewandt: Die Weboberfläche ist so mächtig wie
ein SSH-Zugang und gehört ins LAN.

- [x] **Schritt 1: Die Prüfung für die Aufbewahrung schreiben**

```python
def pruefe_aufbewahrung(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")
    db = h.verbindung(tmp / "historie4.db")
    db.executemany(
        "INSERT INTO sitzung (spieler, beginn, ende, sekunden, grund) "
        "VALUES (?, ?, ?, ?, ?)",
        [("Spieler_A", "2020-01-01 10:00:00", "2020-01-01 11:00:00",
          3600, "verlassen"),
         ("Spieler_A", "2026-09-01 10:00:00", "2026-09-01 11:00:00",
          3600, "verlassen")])
    db.commit()

    pruefe(h.aufraeumen(db, 0) == 0,
           "MCS_HISTORIE_TAGE=0 muss 'unbegrenzt' heissen und darf NICHTS "
           "loeschen -- genau diese Falle hat einmal beide Backup-Platten "
           "geleert.")
    pruefe(db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0] == 2,
           "Bei 0 duerfen keine Zeilen verschwinden.")

    pruefe(h.aufraeumen(db, 365) == 1,
           "Mit einer Frist muss der alte Eintrag verschwinden.")
```

- [x] **Schritt 2: Prüfung laufen lassen — sie muss fehlschlagen**

Ausführen: `python3 tests/pruefung-historie.py`

- [x] **Schritt 3: `aufraeumen()` schreiben**

```python
def aufraeumen(db, tage):
    """Loescht Eintraege aelter als `tage`. 0 heisst unbegrenzt.

    Die ausdrueckliche 0 ist hier kein Sonderfall aus Hoeflichkeit: In
    diesem Projekt wurde aus MCS_BACKUP_BEHALTEN=0 einmal "behalte ab
    Zeile 1", und ein Lauf raeumte beide Backup-Platten leer (31.08.2026).
    Seither heisst 0 ueberall ausdruecklich "aus", und geloescht wird nie
    auf Grundlage eines Wertes, dem der Code nicht trauen kann.
    """
    if not tage or tage <= 0:
        return 0
    from datetime import date, timedelta
    grenze = (date.today() - timedelta(days=int(tage))).isoformat()
    weg = db.execute("DELETE FROM sitzung WHERE beginn < ?",
                     (grenze,)).rowcount
    weg += db.execute("DELETE FROM aeusserung WHERE zeit < ?",
                      (grenze,)).rowcount
    db.commit()
    return weg
```

- [x] **Schritt 4: Prüfung wiederholen — sie muss bestehen**

Ausführen: `python3 tests/pruefung-historie.py`

- [x] **Schritt 5: `tools/historie-aufbauen.py` schreiben**

Nach dem Vorbild von `spielerprotokoll-nachtragen.py`: `--zeigen`
berichtet nur, ohne Argument wird geschrieben; wiederholbar. Vor dem
ersten Schreiben **`chmod 600`** auf die Datei setzen — die Rechte gehören
**vor** den Inhalt, nicht danach (`CLAUDE.md`, „ob sie *vor* dem Schreiben
gesetzt werden").

- [x] **Schritt 6: Ausrollen und auf der Maschine nachmessen**

```bash
cd ~/Pi-MCS && ./deploy.sh
python3 tools/historie-aufbauen.py --zeigen
python3 tools/historie-aufbauen.py
ls -l ~/mcs/admin/historie.db        # erwartet: -rw------- 
python3 tools/historie-aufbauen.py   # zweiter Lauf: 0 neue Eintraege
```

- [x] **Schritt 7: Die Seite im Browser abnehmen**

Anmelden, „Historie" öffnen. Erwartet: Sitzungen ab dem ältesten
Serverprotokoll, Tagesbalken, Chat und Befehle; Sitzungen mit `abbruch`
tragen ein `≈`. **Vom Menschen abnehmen lassen** — und dabei darauf
achten, ob die Seite spürbar hängt. Bleibt sie beim ersten Aufruf länger
als zwei Sekunden stehen, gehört der Erstaufbau in die Bedienanleitung als
Pflichtschritt, nicht als Angebot.

- [x] **Schritt 8: Doku und Commit**

- `README.md`: Abschnitt zur Historienseite, `MCS_HISTORIE_TAGE`, der
  Hinweis auf `chmod 600` und darauf, dass die Datei den Pi nicht verlässt.
- `docs/pflichtenheft-v1.1.md` §5: Der v1.2-Absatz wird als umgesetzt
  markiert, mit Verweis auf diesen Plan und den beiden hier getroffenen
  Entscheidungen.
- `PRUEFEN-AUF-DEM-PI.md`: die Punkte aus Schritt 6 und 7 als Prüfliste
  mit Datum.
- `/home/pi/pi-manager-status.md`: der offene Punkt aus Aufgabe 4 wandert
  von „OFFEN" nach „erledigt", nicht gelöscht.

```bash
make && python3 tests/pruefung-historie.py
git add -A
git commit -m "feat: Erstaufbau, Aufbewahrungsfrist und Rechte der Historie

MCS_HISTORIE_TAGE=0 heisst ausdruecklich unbegrenzt. historie.db traegt
chmod 600, gesetzt vor dem ersten Schreiben: Sie enthaelt Chat-Inhalte
und Spielernamen und verlaesst den Pi nicht."
```

- [x] **Schritt 9: Vor dem Push den Diff ansehen**

Die Suchmuster werden aus der **lokalen** Installation gelesen, nicht in
den Befehl geschrieben — sonst stünde der Weltname im Repository, um zu
prüfen, dass er nicht im Repository steht:

```bash
WELT=$(sed -n 's/^level-name=//p'  ~/mcs/mc_server/server.properties)
PORT=$(sed -n 's/^server-port=//p' ~/mcs/mc_server/server.properties)

git diff origin/main --stat
git diff origin/main | grep -nE "[0-9]{1,3}(\.[0-9]{1,3}){3}|${WELT}|${PORT}"
```

Erwartet: keine Treffer. Das Repository soll öffentlich werden, und was
einmal in der Historie steht, ist ab diesem Moment draußen — ein
Platzhalter nur im Endstand hilft nicht, weil `git show <commit>` jeden
alten Stand hergibt.

---

## Selbstprüfung des Plans

**Abdeckung gegen die Spezifikation** (`docs/pflichtenheft-v1.1.md` §5,
Absatz „Die Spieler-Historie (v1.2)"):

| Forderung der Spezifikation | Aufgabe |
|---|---|
| Wer war wann online | 6 (Sitzungs-Index), 8 (Anzeige) |
| Wie lange | 6 (`sekunden`), 8 (`summen_je_tag`) |
| Was wurde im Chat geschrieben | 7, 8 |
| Was wurde als Befehl ausgeführt | 7, 8 |
| „Braucht eine Datenhaltung, die es nicht gibt" | 6 (Schema in `historie.db`) |
| Entscheidung: wie lange aufbewahrt wird | 9 (`MCS_HISTORIE_TAGE`, Vorgabe unbegrenzt) |
| Entscheidung: Umgang mit Namen und Chat-Inhalten | 9 (`chmod 600`, bleibt auf dem Pi, Platzhalter im Repo) |
| „W3 arbeitet dieser Etappe zu" | 1–3 (W3 war zum Planzeitpunkt wieder zunichte gemacht) |

**Bezeichner, die über Aufgaben hinweg zusammenpassen müssen:**
`verbindung`, `sitzungen_einlesen`, `aeusserungen_einlesen`,
`aktualisieren`, `sitzungen`, `summen_je_tag`, `aeusserungen`,
`aufraeumen` (alle `admin/historie.py`); `datum_fuer_datei`, `Tagesuhr`
(`admin/logdatum.py`); `protokoll_lueckenhaft` (
`admin/protokollpruefung.py`). Spaltennamen: `spieler, beginn, ende,
sekunden, grund` und `zeit, spieler, art, inhalt`.

**Bewusst nicht in diesem Plan:**

- **Kein Timer und kein sechster Dienst.** Ein `mcs-historie.timer` müsste
  mit `WantedBy=mcs.target` **und** `PartOf=mcs.target` am Hauptschalter
  hängen, und `enable`-Verweise folgen dem `[Install]`-Abschnitt, der beim
  `systemctl enable` galt — eine bekannte Fußangel dieses Projekts. Der
  Index beim Seitenaufruf kommt ohne all das aus.
- **Keine Tabellen in `metrik.db`.** Getrennte Aufbewahrungsfristen,
  getrennte Rechte.
- **Keine Karten- oder Positionsdaten.** Nicht gefordert.
