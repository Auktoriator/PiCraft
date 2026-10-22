#!/usr/bin/env python3
"""
protokoll.py — Was im Server-Log steht.

Wer ist online, wer hat was in den Chat geschrieben, welche Fehler gab es?
Alles kommt aus derselben Datei: latest.log. Die Suchmuster dafuer stehen
ausserhalb des Codes (log-muster.sh), damit sie sich anpassen lassen, wenn
eine neue Minecraft-Version ihre Meldungen umformuliert.
"""

import os
import re
import threading
from datetime import datetime
from pathlib import Path

from einstellungen import (ACTION_LOG, BACKUP_DIR, MCS_DIR, MINECRAFT_LOG,
                           PLAYER_ACTIVITY_LOG)
from system import read_last_lines

# ----------------------------------------------------------------------------
# Suchmuster für das Server-Log
# ----------------------------------------------------------------------------
# Der Minecraft-Server schreibt sein Log auf Englisch — diese Muster
# erkennen die relevanten Zeilen (Beitritt, Austritt, Chat, Fehler, ...).
#
# Die Muster, die AUCH das Shell-Skript log_player_activity.sh braucht,
# stehen zentral in tools/log-muster.sh. Vorher gab es zwei getrennte
# Listen; ändert Paper sein Logformat, hätte man das an zwei Stellen
# merken müssen — und gemerkt hätte man es erst, wenn eine der beiden
# Auswertungen stillschweigend nichts mehr findet.
def lade_log_muster(pfad=None):
    """Liest die gemeinsamen Suchmuster aus tools/log-muster.sh.

    Die Datei ist so geschrieben, dass die Shell sie direkt einlesen kann
    (NAME='ausdruck'). Hier wird sie schlicht zeilenweise gelesen.
    """
    kandidaten = [pfad] if pfad else [
        os.getenv("MCS_LOG_MUSTER", ""),
        str(Path(__file__).with_name("log-muster.sh")),
        f"{MCS_DIR}/log-muster.sh",
    ]
    muster = {}
    for kandidat in kandidaten:
        if not kandidat or not Path(kandidat).is_file():
            continue
        with open(kandidat, "r", encoding="utf-8") as f:
            for zeile in f:
                zeile = zeile.strip()
                if not zeile.startswith("MUSTER_") or "=" not in zeile:
                    continue
                name, wert = zeile.split("=", 1)
                muster[name.strip()] = wert.strip().strip("'")
        break
    return muster


_MUSTER = lade_log_muster()

# Fallback, falls log-muster.sh (noch) nicht ausgerollt ist: dieselben
# Ausdrücke, damit die Oberfläche in jedem Fall funktioniert.
JOIN_RE = re.compile(_MUSTER.get(
    "MUSTER_BEITRITT",
    r"^\[([^]]+)\] \[[^]]*\]: (System chat: )?([A-Za-z0-9_]{1,16}) joined the game$"))
UUID_RE = re.compile(_MUSTER.get(
    "MUSTER_UUID",
    r"^\[([^]]+)\] \[[^]]*\]: UUID of player ([A-Za-z0-9_]{1,16}) is ([0-9a-fA-F-]+)$"))
LOGIN_RE = re.compile(_MUSTER.get(
    "MUSTER_ANMELDUNG",
    r"^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16})\[/([^]]*)\] logged in with entity id"))
COMMAND_RE = re.compile(_MUSTER.get(
    "MUSTER_BEFEHL",
    r"^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16}) issued server command: (.*)$"))

# "Weg" fasst beide Fälle zusammen (regulär verlassen ODER Verbindung
# verloren). Der Name steht nicht überall in derselben Gruppe — seit Paper
# 26.3 kann vor "left the game" ein "System chat: " stehen. Darum holt ihn
# _spielername() heraus, statt eine Gruppennummer anzunehmen.
LEAVE_RE = re.compile("(?:%s)|(?:%s)" % (
    _MUSTER.get("MUSTER_VERLASSEN",
                r"^\[([^]]+)\] \[[^]]*\]: (System chat: )?([A-Za-z0-9_]{1,16}) left the game$"),
    _MUSTER.get("MUSTER_VERBINDUNG_WEG",
                r"^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16}) lost connection: (.*)$"),
))

# Diese beiden bleiben hier: Sie werden nur von der Oberfläche gebraucht,
# und die Shell könnte sie gar nicht ausdrücken (bash kennt weder
# nicht-fangende Gruppen noch Groß-/Kleinschreibung-egal).
CHAT_RE = re.compile(r"]:\s(?:\[Not Secure\]\s)?<([^>]+)>\s(.*)$")
ERROR_RE = re.compile(r"(ERROR|WARN|Exception|Traceback|failed|Could not)", re.IGNORECASE)


def _spielername(treffer):
    """Holt den Spielernamen aus einem Treffer.

    Die gemeinsamen Muster legen ihn meist in Gruppe 2 ab, Beitritt und
    Verlassen seit Paper 26.3 in Gruppe 3 (davor steht "System chat: " oder
    nichts). Bei LEAVE_RE sind zwei Muster zusammengeschaltet. Darum wird
    die erste Gruppe genommen, die wie ein Name aussieht — "System chat: "
    tut das nicht (Leerzeichen, Doppelpunkt), die Uhrzeit auch nicht.
    """
    for gruppe in treffer.groups():
        if gruppe and re.fullmatch(r"[A-Za-z0-9_]{1,16}", gruppe):
            return gruppe
    return None


# Merkzettel für die Spielerliste: Wie weit im Server-Log wurde schon
# gelesen, und wer war zu diesem Zeitpunkt online?
_spieler_stand = {"inode": None, "offset": 0, "spieler": set()}
_spieler_sperre = threading.Lock()


def online_players():
    """Ermittelt die aktuell verbundenen Spieler aus dem Server-Log.

    Idee: latest.log beginnt bei jedem Serverstart leer. Wer seitdem
    'joined' hat und noch nicht 'left'/'lost connection' ist, ist online.

    Gelesen wird nur der Teil, der seit dem letzten Aufruf dazugekommen ist.
    Vorher wurde bei JEDEM Statusabruf die komplette latest.log Zeile für
    Zeile durchgegangen — alle fünf Sekunden, je geöffnetem Browserfenster.
    Auf einem Server, der wochenlang läuft, wird diese Datei zweistellig
    megabytegroß; das waren dann Dutzende Megabyte Lesearbeit pro Minute
    auf einer Platte, die sich mit dem Time-Machine-Dienst teilt.
    """
    log_path = Path(MINECRAFT_LOG)
    if not log_path.exists():
        return []

    with _spieler_sperre:
        try:
            stat = log_path.stat()
        except OSError:
            return []

        # Neue Datei (Serverstart) oder kürzer geworden (Log-Rotation)?
        # Dann von vorn anfangen.
        if stat.st_ino != _spieler_stand["inode"] or stat.st_size < _spieler_stand["offset"]:
            _spieler_stand["inode"] = stat.st_ino
            _spieler_stand["offset"] = 0
            _spieler_stand["spieler"] = set()

        if stat.st_size > _spieler_stand["offset"]:
            # Nur VOLLSTAENDIGE Zeilen verarbeiten, und die Lesemarke nur bis
            # hinter das letzte Zeilenende vorruecken. Bis zum 23.09.2026
            # ruckte sie ans Dateiende: Traf die Abfrage eine Zeile, die Paper
            # gerade erst halb geschrieben hatte ("Anna jo"), war der Beitritt
            # verloren, und Anna galt die ganze Sitzung als offline
            # (nachgestellt). Binaer gelesen, weil nur Bytezahlen als Marke
            # taugen.
            with open(log_path, "rb") as f:
                f.seek(_spieler_stand["offset"])
                roh = f.read()
            ende = roh.rfind(b"\n") + 1
            _spieler_stand["offset"] += ende
            if ende:
                for line in roh[:ende].decode("utf-8", errors="ignore").splitlines():
                    match = JOIN_RE.search(line)
                    if match:
                        name = _spielername(match)
                        if name:
                            _spieler_stand["spieler"].add(name)
                        continue
                    match = LEAVE_RE.search(line)
                    if match:
                        name = _spielername(match)
                        if name:
                            _spieler_stand["spieler"].discard(name)

        return sorted(_spieler_stand["spieler"])


# ----------------------------------------------------------------------------
# Log-Ansichten
# ----------------------------------------------------------------------------
def chat_lines(max_lines=150):
    """Nur die Chat-Nachrichten aus dem Server-Log."""
    lines = []
    for line in read_last_lines(MINECRAFT_LOG, max_lines=4000):
        if CHAT_RE.search(line):
            lines.append(line)
    return lines[-max_lines:]


def activity_lines(max_lines=150):
    """Spieler-Aktivität (Beitritte, Austritte, Befehle, Chat) aus dem Log."""
    lines = []
    for line in read_last_lines(MINECRAFT_LOG, max_lines=5000):
        if (UUID_RE.search(line) or JOIN_RE.search(line) or LEAVE_RE.search(line)
                or LOGIN_RE.search(line) or COMMAND_RE.search(line) or CHAT_RE.search(line)):
            lines.append(line)
    return lines[-max_lines:]


def error_lines(max_lines=150):
    """Nur Fehler und Warnungen aus dem Server-Log."""
    lines = [line for line in read_last_lines(MINECRAFT_LOG, max_lines=1200) if ERROR_RE.search(line)]
    return lines[-max_lines:]


# ----------------------------------------------------------------------------
# Die Ereignisleiste der Startseite
# ----------------------------------------------------------------------------
# Leitfrage der Startseite: "Was will ich in fünf Sekunden vom Handy aus
# wissen?" Ein Teil der Antwort ist nicht der aktuelle Zustand, sondern was
# zuletzt geschehen ist — ist jemand beigetreten, kam das Backup durch,
# wurde der Server neu gestartet?
#
# Diese Angaben stehen in drei verschiedenen Protokollen, in drei
# verschiedenen Schreibweisen. Hier werden sie zusammengeführt, nach Zeit
# sortiert und auf die letzten paar eingedampft.
#
# Bewusst kein viertes Protokoll und keine eigene Datenbank: Alle drei
# Dateien entstehen ohnehin, und ein Ereignisspeicher, den nur die
# Oberfläche füllt, wäre ein Bauteil mehr, das man pflegen und aufräumen
# muss.

# Zeitstempel am Zeilenanfang: "2026-08-28 14:03:11 | Text"
# So schreiben sowohl log_player_activity.sh als auch minecraft-backup.sh.
_STRICH_ZEILE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| (.+)$")

# Und so schreibt system.run_background ins Aktionsprotokoll:
# "[2026-08-28T14:05:02] START backup_now: /usr/bin/bash ..."
_AKTION_ZEILE = re.compile(r"^\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})\] START ([a-z_]+):")

# Aus dem Backup-Protokoll ist das meiste Ablaufbeschreibung ("Prüfe das
# Archiv...") und gehört nicht auf die Startseite. Nur diese drei Sorten
# Zeilen sind ein Ereignis.
_BACKUP_WICHTIG = ("Backup geprüft und in Ordnung", "FEHLER", "WARNUNG")

# Deutsche Namen für die Aktionen aus dem Aktionsprotokoll.
_AKTION_NAMEN = {
    "backup_now": "Backup von Hand gestartet",
    "update_paper": "Paper-Update ausgelöst",
    "plugin_abgeschaltet": "Plugin abgeschaltet",
    "plugin_eingeschaltet": "Plugin eingeschaltet",
    "plugin_installiert": "Plugin installiert",
}


def _zeit_lesen(datum, uhrzeit):
    try:
        return datetime.strptime(f"{datum} {uhrzeit}", "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def letzte_ereignisse(anzahl=5):
    """Die letzten Vorgänge aus Spieler-, Backup- und Aktionsprotokoll.

    Liefert eine Liste von dicts mit `zeit` (datetime), `text` und `art`
    ("spieler", "backup", "aktion") — `art` bestimmt in der Oberfläche nur
    die Farbe, nicht den Inhalt.

    Behalten wird je Datei nur der Schwanz — GELESEN wird sie aber ganz:
    read_last_lines geht jede Zeile durch und behält die letzten N. Hier
    stand bis zum 23.09.2026, es werde nur der Schwanz gelesen. Gemessen
    ist das harmlos (Spielerprotokoll 140 KB nach einem halben Jahr, alle
    30 s von der Startseite); wird das Hauptbuch je gross, ist hier der
    Ort, von hinten zu lesen.
    """
    ereignisse = []

    # 1) Spieler kommen und gehen.
    for zeile in read_last_lines(PLAYER_ACTIVITY_LOG, max_lines=60):
        treffer = _STRICH_ZEILE.match(zeile)
        if not treffer:
            continue
        zeit = _zeit_lesen(*treffer.group(1).split(" ", 1))
        if zeit:
            ereignisse.append({"zeit": zeit, "text": treffer.group(2), "art": "spieler"})

    # 2) Backups.
    for zeile in read_last_lines(f"{BACKUP_DIR}/backup.log", max_lines=120):
        treffer = _STRICH_ZEILE.match(zeile)
        if not treffer or not any(w in treffer.group(2) for w in _BACKUP_WICHTIG):
            continue
        zeit = _zeit_lesen(*treffer.group(1).split(" ", 1))
        if not zeit:
            continue
        text = treffer.group(2)
        # Die Erfolgsmeldung enthält Dateinamen, Größe und Dauer. Für die
        # Startseite reicht, DASS es geklappt hat.
        if text.startswith("Backup geprüft und in Ordnung"):
            text = "Backup fertig und geprüft"
        ereignisse.append({"zeit": zeit, "text": text, "art": "backup"})

    # 3) Was über die Oberfläche angestoßen wurde.
    for zeile in read_last_lines(ACTION_LOG, max_lines=60):
        treffer = _AKTION_ZEILE.match(zeile)
        if not treffer:
            continue
        zeit = _zeit_lesen(treffer.group(1), treffer.group(2))
        if zeit:
            name = treffer.group(3)
            ereignisse.append({"zeit": zeit,
                               "text": _AKTION_NAMEN.get(name, name),
                               "art": "aktion"})

    ereignisse.sort(key=lambda e: e["zeit"], reverse=True)
    return ereignisse[:anzahl]
