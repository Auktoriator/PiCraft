#!/usr/bin/env python3
"""
metrik.py — Verlaufsdaten sammeln: CPU, RAM, Platte, Temperatur, TPS, Spieler.

Warum überhaupt? Die Weboberfläche zeigt bisher nur den Augenblick. Die Frage,
die man wirklich stellt, lautet aber: "Gestern Abend hat es geruckelt — was war
da los?" Dafür braucht es einen Verlauf.

Womit? Mit SQLite. Das ist in Python eingebaut, besteht aus einer einzigen
Datei und braucht keinen laufenden Dienst. Prometheus, InfluxDB oder Grafana
wären für sieben Tage Messwerte von einem Bastelserver ein eigenes
Rechenzentrum — und würden dem Minecraft-Server genau die Ressourcen wegnehmen,
die er zum Spielen braucht.

Wie oft? Einmal pro Minute. Sekundengenau kostet das Sechzigfache und zeigt
nichts, was man sehen will: Ein Ruckler von einer halben Sekunde ist in keiner
Auflösung als Punkt erkennbar, wohl aber am Einbruch der TPS-Kurve.

Wie lange? Sieben Tage, also rund 10.000 Zeilen. Die Datei bleibt damit unter
einem Megabyte und muss nie von Hand aufgeräumt werden.

EINE ALTLAST IN DER CPU-SPALTE
-----------------------------
Bis v1.1 (01.09.2026) teilten sich dieser Sammler und die Kacheln der
Startseite EINE /proc/stat-Probe. Wer sie liest, setzt sie zurück: Bei
geöffneter Oberfläche maß der Sammler deshalb nicht seine Minute, sondern die
Restspanne seit dem letzten Seitenaufruf — mitunter Millisekunden, und über so
kurze Spannen ist die Auslastung beliebig. Gemessen über 24 Stunden: 394
Sprünge über 30 Punkte bei durchgehend 20,0 TPS. Es war Rauschen, keine Last.

Behoben ist es dort, wo es entstand: `system.cpu_auslastung` hält je Aufrufer
eine eigene Probe (siehe `aufrufer=` in `status.current_status`). Die
betroffenen Altwerte wurden einmalig auf NULL gesetzt — eine Lücke in der
Kurve sieht man, eine erfundene Zahl glaubt man. Das Werkzeug dafür ist nach
dem Lauf entfernt worden (02.09.2026); wer eine Datenbank von vor v1.1 in die
Hand bekommt, weiß mit diesem Absatz, was die CPU-Kurve dort wert ist.
"""

import logging
import os
import re
import sqlite3
import threading
import time

# Der Sammler laeuft in einem Hintergrund-Thread ohne Anfrage, an der eine
# Meldung haengen koennte. Sein Weg nach draussen ist das Journal des Dienstes:
#   journalctl -u mcs-admin.service | grep Metrik
_log = logging.getLogger("mcs.metrik")

try:
    from . import rcon
except ImportError:  # als eigenständiges Modul geladen (mcs, Tests)
    import rcon


# ----------------------------------------------------------------------------
# Wo die Datenbank liegt
# ----------------------------------------------------------------------------
def datenbank_pfad():
    admin_dir = os.getenv(
        "MCS_ADMIN_DIR",
        os.path.join(os.path.expanduser("~"), "mcs", "admin"))
    return os.getenv("MCS_METRIK_DB", os.path.join(admin_dir, "metrik.db"))


# Wie lange Messwerte aufgehoben werden.
AUFBEWAHRUNG_TAGE = float(os.getenv("MCS_METRIK_TAGE", "7"))

SCHEMA = """
CREATE TABLE IF NOT EXISTS messwerte (
    zeit    INTEGER PRIMARY KEY,   -- Unixzeit, auf die volle Minute abgerundet
    cpu     REAL,                  -- Auslastung in Prozent
    ram     REAL,                  -- belegt in Prozent
    platte  REAL,                  -- belegt in Prozent
    temp    REAL,                  -- Grad Celsius (None, wenn nicht lesbar)
    tps     REAL,                  -- Ticks pro Sekunde, vom Server
    mspt    REAL,                  -- Millisekunden je Tick, Mittel der letzten Minute
    spieler INTEGER
);
"""


# SQLite-Verbindungen sind NICHT threadsicher. Der Sammler läuft in einem
# eigenen Thread, die Weboberfläche beantwortet Anfragen in weiteren — eine
# geteilte Verbindung führt zu Abstürzen, die nur unter Last auftreten und
# sich deshalb kaum nachstellen lassen. Also je Thread eine eigene.
_lokal = threading.local()


def verbindung():
    """Die Verbindung dieses Threads (wird beim ersten Aufruf angelegt)."""
    vorhanden = getattr(_lokal, "db", None)
    if vorhanden is not None:
        return vorhanden

    pfad = datenbank_pfad()
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    db = sqlite3.connect(pfad, timeout=10.0)
    db.row_factory = sqlite3.Row
    # WAL: Lesen und Schreiben blockieren sich nicht mehr gegenseitig. Ohne
    # das würde der Sammler beim Schreiben die Oberfläche kurz aussperren —
    # jede Minute, für jeden Betrachter.
    db.execute("PRAGMA journal_mode=WAL")
    # NORMAL statt FULL: Bei einem Stromausfall kann die letzte Minute
    # fehlen. Das ist ein Messwert, kein Backup — dafür entfällt ein
    # Festplatten-Sync pro Minute.
    db.execute("PRAGMA synchronous=NORMAL")
    db.executescript(SCHEMA)
    db.commit()
    _lokal.db = db
    return db


# ----------------------------------------------------------------------------
# Was der Server über sich selbst sagt
# ----------------------------------------------------------------------------
# Paper faerbt seine Antworten mit Steuerzeichen ein: "§a20.0" ist ein gruenes
# "20.0". Das Zeichen und das eine danach muessen weg, sonst scheitert jede
# Zahlenerkennung.
_FARBE = re.compile("§.")


def _ohne_farben(text):
    return _FARBE.sub("", text or "")


def tps_lesen(antwort):
    """Holt die 1-Minuten-TPS aus der Antwort von `tps`.

    Gemessen mit Paper 26.2 Build 119:
        §6TPS from last 1m, 5m, 15m: §a20.0§r, §a20.0§r, §a20.0
    ohne Farben:
        TPS from last 1m, 5m, 15m: 20.0, 20.0, 20.0

    Die erste Zahl NACH dem Doppelpunkt ist der Wert der letzten Minute. Vor
    dem Doppelpunkt stehen die Zahlen 1, 5 und 15 — wer einfach die erste
    Zahl im Text nimmt, misst nichts als die Ziffer 1.
    """
    text = _ohne_farben(antwort)
    # Erst prüfen, ob das überhaupt eine TPS-Antwort ist. Ohne diese Zeile
    # nähme der Parser jede Zahl aus jeder Antwort — auch die aus einer
    # Fehlermeldung. Ein erfundener Messwert ist schlimmer als gar keiner:
    # Er landet unbemerkt in der Kurve und man sucht später ein Problem,
    # das es nie gab.
    if "TPS" not in text.upper() or ":" not in text:
        return None
    zahlen = re.findall(r"-?\d+(?:[.,]\d+)?", text.split(":", 1)[1])
    if not zahlen:
        return None
    try:
        wert = float(zahlen[0].replace(",", "."))
    except ValueError:
        return None
    # Paper deckelt bei 20 Ticks je Sekunde. Alles darüber (oder Negatives)
    # kann kein gemessener Wert sein.
    return wert if 0.0 <= wert <= 20.5 else None


def mspt_lesen(antwort):
    """Holt die durchschnittliche Tickdauer der letzten Minute aus `mspt`.

    Gemessen mit Paper 26.2 Build 119, ohne Farben:
        Server tick times (avg/min/max) from last 5s, 10s, 1m:
        ◴ 1.6/0.6/11.1, 1.6/0.6/11.1, 2.0/0.5/40.8

    Drei Gruppen zu je avg/min/max, in der Reihenfolge 5s, 10s, 1m. Gebraucht
    wird der Durchschnitt der letzten MINUTE — also die erste Zahl der DRITTEN
    Gruppe (hier 2.0). Sie passt zum Messtakt dieses Moduls; die 5-Sekunden-
    Werte schwankten zwischen zwei Messungen viel zu stark, um eine
    brauchbare Kurve zu ergeben.
    """
    text = _ohne_farben(antwort)
    # Wie bei tps_lesen: erst feststellen, dass es die erwartete Antwort ist.
    if "tick times" not in text.lower() or ":" not in text:
        return None
    gruppen = re.findall(r"(-?\d+(?:[.,]\d+)?)/(-?\d+(?:[.,]\d+)?)/(-?\d+(?:[.,]\d+)?)",
                         text.split(":", 1)[1])
    if len(gruppen) < 3:
        # Weniger Gruppen als erwartet: lieber nichts melden als den
        # 5-Sekunden-Wert als Minutenwert ausgeben.
        return None
    try:
        wert = float(gruppen[2][0].replace(",", "."))
    except ValueError:
        return None
    # Ein Tick dauert im Normalfall unter 50 ms. Werte über einer Minute je
    # Tick sind kein Messwert, sondern ein Lesefehler.
    return wert if 0.0 <= wert <= 60000.0 else None


# Zwischenspeicher fuer TPS und MSPT.
#
# Warum eigens dafuer? Die Weboberflaeche erneuert ihre Kacheln alle fuenf
# Sekunden, und jede Erneuerung fragte bis zum 28.08.2026 zwei RCON-Befehle
# ab — vierundzwanzig Anfragen je Minute, an den Hauptthread des Servers,
# also genau dorthin, wo Ruckler entstehen. Das Lastenheft sagt dazu (5.7.0,
# Regel 3): "Eine Abfrage je Klick ist richtig, eine je Sekunde nicht."
#
# Das Beste daran: Es war nicht einmal ein Genauigkeitsgewinn. "tps" liefert
# den Durchschnitt der letzten MINUTE und "mspt" ebenso — zwischen zwei
# Abfragen im Abstand von fuenf Sekunden steht neunzig Prozent derselben
# Messung. Zwanzig Sekunden Gueltigkeit kosten also nichts und sparen zwei
# Drittel der Anfragen.
#
# Der Sammler misst im Minutentakt und bekommt dadurch weiterhin frische
# Werte: 60 Sekunden sind mehr als die 20 hier.
_server_stand = {"zeit": 0.0, "werte": (None, None)}
_server_sperre = threading.Lock()

SERVER_WERTE_GUELTIG = 20.0


def server_werte(hoechstens_alt=None):
    """Fragt TPS und MSPT über RCON ab. Liefert (tps, mspt), notfalls (None, None).

    Ist RCON nicht eingerichtet oder der Server nicht erreichbar, wird das
    nicht als Fehler behandelt: Der Verlauf soll trotzdem weiterlaufen und
    CPU, RAM und Temperatur festhalten.

    `hoechstens_alt` sagt, wie alt ein zwischengespeicherter Wert höchstens
    sein darf (Sekunden). 0 erzwingt eine frische Abfrage.
    """
    grenze = SERVER_WERTE_GUELTIG if hoechstens_alt is None else hoechstens_alt

    with _server_sperre:
        if grenze > 0 and (time.time() - _server_stand["zeit"]) < grenze:
            return _server_stand["werte"]

        if not rcon.verfuegbar():
            werte = (None, None)
        else:
            try:
                # Zwei Aufrufe, zwei Verbindungen — und das ist richtig so:
                # Auf einer geteilten Verbindung kann ein einzelner Befehl
                # die ganze Verbindung mitreissen (Korrektur K4 im
                # Lastenheft). Hier sind es zwei Befehle je zwanzig
                # Sekunden; die gesparte Verbindung waere kein Gewinn.
                werte = (tps_lesen(rcon.befehl("tps")),
                         mspt_lesen(rcon.befehl("mspt")))
            except rcon.RconFehler:
                werte = (None, None)

        _server_stand["zeit"] = time.time()
        _server_stand["werte"] = werte
        return werte


# ----------------------------------------------------------------------------
# Schreiben und Lesen
# ----------------------------------------------------------------------------
def volle_minute(zeitpunkt=None):
    """Rundet auf die volle Minute ab — das ist der Schlüssel je Datensatz."""
    return int((zeitpunkt if zeitpunkt is not None else time.time()) // 60 * 60)


def schreiben(werte, zeitpunkt=None):
    """Legt einen Messwert ab (oder ersetzt den der laufenden Minute).

    "INSERT OR REPLACE": Läuft der Sammler doppelt oder wird eine Minute
    zweimal erfasst, entsteht kein zweiter Datensatz — die volle Minute ist
    der Primärschlüssel.
    """
    db = verbindung()
    db.execute(
        "INSERT OR REPLACE INTO messwerte "
        "(zeit, cpu, ram, platte, temp, tps, mspt, spieler) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (volle_minute(zeitpunkt),
         werte.get("cpu"), werte.get("ram"), werte.get("platte"),
         werte.get("temp"), werte.get("tps"), werte.get("mspt"),
         werte.get("spieler")))
    db.commit()


def aufraeumen():
    """Löscht Messwerte, die älter sind als AUFBEWAHRUNG_TAGE."""
    db = verbindung()
    grenze = int(time.time() - AUFBEWAHRUNG_TAGE * 86400)
    db.execute("DELETE FROM messwerte WHERE zeit < ?", (grenze,))
    db.commit()


def verlauf(stunden=24, hoechstens=1500):
    """Liefert die Messwerte der letzten Stunden, älteste zuerst.

    `hoechstens` begrenzt die Menge für die Anzeige: Sieben Tage sind rund
    10.000 Punkte, und mehr Punkte als Bildschirmspalten zu zeichnen kostet
    nur Zeit. Ausgedünnt wird gleichmäßig, damit die Kurvenform erhalten
    bleibt.
    """
    db = verbindung()
    ab = int(time.time() - stunden * 3600)
    zeilen = db.execute(
        "SELECT * FROM messwerte WHERE zeit >= ? ORDER BY zeit", (ab,)).fetchall()
    if len(zeilen) > hoechstens:
        schritt = len(zeilen) / float(hoechstens)
        zeilen = [zeilen[int(i * schritt)] for i in range(hoechstens)]
    return [dict(z) for z in zeilen]


def anzahl():
    """Wie viele Messwerte liegen vor? (Für Statusanzeigen und Tests.)"""
    return verbindung().execute("SELECT COUNT(*) FROM messwerte").fetchone()[0]


# ----------------------------------------------------------------------------
# Der Sammler
# ----------------------------------------------------------------------------
# Wie oft aufgeräumt wird: nicht bei jedem Schreiben. Ein DELETE je Minute
# wäre reine Beschäftigung — einmal pro Stunde reicht vollkommen.
_AUFRAEUM_TAKT = 60


def sammler_starten(werte_holen, laeuft_pruefen, takt=60.0):
    """Startet den Hintergrundthread, der jede Minute einen Messwert ablegt.

    `werte_holen`    liefert ein dict mit cpu/ram/platte/temp/spieler
    `laeuft_pruefen` sagt, ob der Minecraft-Server gerade läuft

    Warum die zweite Funktion? Läuft der Server nicht, gibt es nichts zu
    messen, was mit Minecraft zu tun hätte. Ohne diese Prüfung füllte sich
    die Datenbank über eine Sommerpause hinweg mit Zehntausenden Zeilen
    voller Nullen — und die Kurve zeigte hinterher eine flache Linie, wo
    schlicht nichts lief.

    Der Thread läuft als daemon: Er hält das Programm beim Beenden nicht auf.
    """
    def schleife():
        runde = 0
        fehler_hintereinander = 0
        while True:
            try:
                if laeuft_pruefen():
                    werte = dict(werte_holen() or {})
                    # TPS und MSPT nur selbst holen, wenn der Aufrufer sie
                    # nicht schon mitliefert. Die Weboberflaeche kennt sie
                    # aus ihrer Statusabfrage — ein zweiter RCON-Aufruf je
                    # Minute waere Arbeit im Hauptthread des Servers, also
                    # genau dort, wo Ruckler entstehen.
                    if "tps" not in werte or "mspt" not in werte:
                        werte["tps"], werte["mspt"] = server_werte()
                    schreiben(werte)
                    runde += 1
                    if runde % _AUFRAEUM_TAKT == 0:
                        aufraeumen()
                    fehler_hintereinander = 0
            except Exception as fehler:
                # Ein Messwert ist nichts, wofür die Weboberfläche sterben
                # darf. Fehler werden übersprungen; beim nächsten Takt wird
                # es erneut versucht.
                #
                # Bis zum 2026-08-31 stand hier nur "pass". Das ist fuer EINEN
                # ausgefallenen Messwert richtig und fuer einen dauerhaft
                # kaputten Sammler falsch: Ein umbenannter Statusschluessel
                # oder eine schreibgeschuetzte Datenbank wurde bei jedem Takt
                # aufs Neue verschluckt, ohne eine Zeile irgendwo. Sichtbar
                # war das nur als Verlaufskurve, die aufhoert zu wachsen —
                # und das sieht genauso aus wie ein ruhiger Server.
                #
                # Nach dem ersten Fehlschlag eine Meldung, danach nur noch bei
                # jedem hundertsten: Ein kaputter Sammler soll auffallen, aber
                # nicht das Journal fuellen (bei 60 s Takt eine Zeile je Stunde).
                fehler_hintereinander += 1
                if fehler_hintereinander == 1 or fehler_hintereinander % 100 == 0:
                    _log.warning(
                        "Metrik-Sammler: %s (%d. Fehlschlag hintereinander) — "
                        "die Verlaufskurve waechst nicht weiter.",
                        fehler, fehler_hintereinander)
            time.sleep(takt)

    thread = threading.Thread(target=schleife, name="mcs-metrik", daemon=True)
    thread.start()
    return thread
