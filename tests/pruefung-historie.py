#!/usr/bin/env python3
"""Pruefungen rund um das Spielerprotokoll. Rueckgabewert 0 = alles gut.

Eigenstaendige Datei und KEIN Heredoc-Block in einem Shell-Skript: Solche
Bloecke sterben still mit einem Traceback, waehrend der Lauf weiter als
bestanden gilt. Am 01.09.2026 waren auf diesem Weg zwei Pruefbloecke zwei
Etappen lang tot, ohne dass es jemandem auffiel (siehe CLAUDE.md,
"Ein gruener Abnahmetest kann trotzdem nichts geprueft haben").

Aufruf:  python3 tests/pruefung-historie.py
"""

import importlib.util
import os
import re
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
fehler = []


def pruefe(bedingung, text):
    if not bedingung:
        fehler.append(text)


def lade(name, pfad):
    """Laedt ein Modul aus admin/ ohne den ganzen Flask-Aufbau.

    admin/ kommt in den Suchpfad, weil die Module sich untereinander mit
    flachen Namen importieren ("import logdatum") -- genau so laeuft auch
    die Anwendung. Ohne das liesse sich hier nur pruefen, was gar keine
    Nachbarn hat, und die Pruefung wuerde die interessanten Module meiden.

    Kein Blueprint und keine Route wird dabei geladen: Geprueft werden die
    Bausteine, nicht die Weboberflaeche.
    """
    admin = str(REPO / "admin")
    if admin not in sys.path:
        sys.path.insert(0, admin)
    spec = importlib.util.spec_from_file_location(name, pfad)
    modul = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modul)
    return modul


# ----------------------------------------------------------------------------
# Aufgabe 1 — das Hauptbuch gehoert in keine Rotationsregel
# ----------------------------------------------------------------------------
def logrotate_vorlage():
    """Der Block, den install.sh nach /etc/logrotate.d/picraft schreibt."""
    quelle = (REPO / "install.sh").read_text(encoding="utf-8")
    treffer = re.search(
        r"tee /etc/logrotate\.d/picraft.*?<<EOF\n(.*?)\nEOF", quelle, re.S)
    return treffer.group(1) if treffer else ""


def rotierte_pfade(vorlage):
    """Die Dateien, die der Block WIRKLICH rotiert.

    Kommentarzeilen zaehlen ausdruecklich nicht mit: Der Block erklaert
    selbst, warum das Hauptbuch dort fehlt, und nennt es dabei. Eine
    Pruefung auf das blosse Vorkommen der Zeichenkette wuerde diese
    Erklaerung als Fehler melden -- sie misst dann "erwaehnt" statt
    "rotiert". (Genau darauf ist sie am 21.09.2026 hereingefallen.)
    """
    pfade = []
    for zeile in vorlage.splitlines():
        zeile = zeile.strip()
        # Der Pfadteil endet an der oeffnenden Klammer der Optionen.
        if zeile == "{":
            break
        if not zeile or zeile.startswith("#"):
            continue
        pfade.append(zeile)
    return pfade


def pruefe_logrotate():
    vorlage = logrotate_vorlage()
    pruefe(vorlage != "",
           "In install.sh ist der logrotate-Block nicht mehr auffindbar — "
           "diese Pruefung misst dann gar nichts.")

    pfade = rotierte_pfade(vorlage)
    pruefe(pfade != [],
           "Der logrotate-Block rotiert gar keine Datei mehr — dann stimmt "
           "an der Vorlage etwas anderes nicht.")
    pruefe(not any("player_activity.log" in p for p in pfade),
           "install.sh rotiert player_activity.log immer noch. Das Hauptbuch "
           "gehoert in keine Rotationsregel: Die Weboberflaeche liest es als "
           "Ganzes, eine Rotation schneidet ihr genau diese Antwort weg.")

    # Und der Aufruestweg: Eine Korrektur nur in install.sh erreicht keine
    # bestehende Installation.
    deploy = (REPO / "deploy.sh").read_text(encoding="utf-8")
    pruefe("logrotate_hauptbuch_loesen" in deploy,
           "deploy.sh zieht die logrotate-Regel auf bestehenden "
           "Installationen nicht nach. Ohne eigenen Schritt bliebe sie dort "
           "stehen und die naechste Rotation leert das Hauptbuch wieder.")

    # Beide Wege muessen WORTGLEICH denselben Hinweis schreiben.
    #
    # Sonst faende deploy.sh auf einer frischen Installation seine Marke
    # nicht und schriebe eine zweite Erklaerung darueber -- und bei jedem
    # weiteren Lauf noch eine. Zwei Wege zur selben Datei, die die Regel
    # des jeweils anderen nicht kennen: das haeufigste Fehlermuster dieses
    # Projekts.
    hinweis = [
        re.search(r'LOGROTATE_MARKE="(.*)"', deploy),
        re.search(r'LOGROTATE_HINWEIS_2="(.*)"', deploy),
        re.search(r'LOGROTATE_HINWEIS_3="(.*)"', deploy),
    ]
    pruefe(all(hinweis),
           "In deploy.sh fehlen die LOGROTATE_-Hinweiszeilen — dann misst "
           "diese Pruefung den Gleichlauf gar nicht.")
    if all(hinweis):
        for treffer in hinweis:
            # In der Shell steht \" fuer ein Anfuehrungszeichen.
            zeile = treffer.group(1).replace('\\"', '"')
            pruefe(zeile in vorlage,
                   f"deploy.sh schreibt die Zeile {zeile!r} in die "
                   "logrotate-Regel, install.sh aber nicht (oder anders). "
                   "Auf einer frischen Installation ergaenzt deploy.sh "
                   "dann eine zweite Erklaerung — bei jedem Lauf eine mehr.")


# ----------------------------------------------------------------------------
# Aufgabe 2 — der Waechter gegen ein beschnittenes Hauptbuch
# ----------------------------------------------------------------------------
def pruefe_waechter(tmp):
    pp = lade("protokollpruefung", REPO / "admin" / "protokollpruefung.py")

    logs = tmp / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    (logs / "2026-03-14-1.log.gz").write_bytes(b"")
    (logs / "2026-09-20-1.log.gz").write_bytes(b"")

    hauptbuch = tmp / "player_activity.log"

    # 1) Der Zustand nach einer Rotation: Das Protokoll beginnt ein halbes
    #    Jahr nach dem aeltesten Serverlog.
    hauptbuch.write_text(
        "2026-09-14 10:00:00 | Spieler_A ist dem Spiel beigetreten\n",
        encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is not None,
           "Der Waechter meldet nichts, obwohl das Protokoll ein halbes "
           "Jahr nach dem aeltesten Serverlog beginnt.")

    # 2) Kein Fehlalarm bei vollstaendigem Protokoll.
    hauptbuch.write_text(
        "Spieler-Aktivitaetslog (PiCraft)\n"
        "------------------------------\n"
        "2026-03-14 21:26:29 | Spieler_A ist dem Spiel beigetreten\n",
        encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is None,
           "Der Waechter meldet einen Fehlalarm bei vollstaendigem "
           "Protokoll.")

    # 3) Der teuerste Fall: leeres Hauptbuch. Er sah zwei Wochen lang aus
    #    wie "war noch nie jemand da".
    hauptbuch.write_text("", encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is not None,
           "Der Waechter uebersieht ein LEERES Hauptbuch — genau der "
           "Zustand, der zwei Wochen lang unbemerkt blieb.")

    # 4) Die Kopfzeilen allein sind kein Protokollbeginn. Nach einem
    #    copytruncate legt log_player_activity.sh sie neu an, und die
    #    Datei ist dann nicht leer, aber trotzdem ohne Vergangenheit.
    hauptbuch.write_text(
        "Spieler-Aktivitaetslog (PiCraft)\n"
        "------------------------------\n",
        encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is not None,
           "Ein Hauptbuch mit NUR den Kopfzeilen gilt als vollstaendig — "
           "dabei ist es der Zustand direkt nach einer Rotation.")

    # 5) Ohne Serverprotokolle gibt es nichts zu vergleichen: dann lieber
    #    schweigen als raten (frische Installation).
    leer = tmp / "leere-logs"
    leer.mkdir(parents=True, exist_ok=True)
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, leer) is None,
           "Auf einer frischen Installation ohne Serverprotokolle darf der "
           "Waechter nichts melden.")

    # 6) Ein Tag Unterschied ist Alltag: Das Protokoll beginnt mit dem
    #    ersten Beitritt, nicht mit dem ersten Serverstart.
    hauptbuch.write_text(
        "2026-03-15 18:00:00 | Spieler_A ist dem Spiel beigetreten\n",
        encoding="utf-8")
    pruefe(pp.protokoll_lueckenhaft(hauptbuch, logs) is None,
           "Ein Tag Abstand zwischen erstem Serverstart und erstem "
           "Beitritt ist Alltag und darf kein Befund sein.")


# ----------------------------------------------------------------------------
# Aufgabe 5 — die Datumsherleitung, an EINER Stelle
# ----------------------------------------------------------------------------
# In den Serverlogzeilen steht kein Datum, nur [HH:MM:SS]. Es gibt ZWEI
# Strategien, und die zweite ist die, die man beim Nachbauen vergisst:
#
#   Archiv      der Dateiname nennt den ERSTEN Tag  -> vorwaerts rechnen
#   latest.log  die Aenderungszeit nennt die LETZTE Zeile -> rueckwaerts
#
# Beide standen bis zum 21.09.2026 nur in tools/spielerprotokoll-nachtragen.py.
# Der Historien-Index braucht sie auch -- nachgebaut waere das der teuerste
# Fehler dieses Projekts gewesen.
def pruefe_logdatum():
    from datetime import date, datetime, time

    ld = lade("logdatum", REPO / "admin" / "logdatum.py")

    # --- Der Tag aus dem Dateinamen -----------------------------------
    pruefe(ld.archivtag("2026-05-10-1.log.gz") == date(2026, 5, 10),
           "Der Tag wird nicht aus dem Archivnamen gelesen.")
    pruefe(ld.archivtag("2026-05-10-2.log") == date(2026, 5, 10),
           "Ein ungepacktes Archiv wird nicht erkannt.")
    pruefe(ld.archivtag("latest.log") is None,
           "latest.log darf keinen Tag aus dem Namen bekommen — dort zaehlt "
           "die Aenderungszeit.")
    pruefe(ld.archivtag("gc.log") is None,
           "gc.log ist kein Serverprotokoll und darf nicht mitgezaehlt werden.")

    # --- Uhrzeiten je Zeile -------------------------------------------
    zeilen = ["[23:58:00] [Server thread/INFO]: a",
              "ohne Zeitstempel",
              "[00:03:00] [Server thread/INFO]: b"]
    zeiten = ld.zeiten_der_datei(zeilen)
    pruefe(zeiten == [time(23, 58), None, time(0, 3)],
           "zeiten_der_datei liefert nicht je Zeile eine Uhrzeit oder None. "
           "Die Reihenfolge MUSS erhalten bleiben — sie wird spaeter mit den "
           "Zeilen gepaart.")

    # --- Vorwaerts: das Archiv ----------------------------------------
    vor = ld.daten_vorwaerts(zeiten, date(2026, 5, 10))
    pruefe(vor[0] == datetime(2026, 5, 10, 23, 58),
           "Die Zeile vor Mitternacht landet im Archiv auf dem falschen Tag.")
    pruefe(vor[1] is None,
           "Eine Zeile ohne Uhrzeit muss None bleiben, nicht wegfallen.")
    pruefe(vor[2] == datetime(2026, 5, 11, 0, 3),
           "Der Tageswechsel im Archiv wird nicht erkannt.")

    # --- Rueckwaerts: latest.log --------------------------------------
    # Genau der synthetische Fall aus W3 (01.09.2026): Aenderungszeit am
    # 12.05. um 00:20, Zeilen 23:50 -> 00:10.
    zeiten2 = ld.zeiten_der_datei(["[23:50:00] x", "[00:10:00] y"])
    zurueck = ld.daten_rueckwaerts(zeiten2, datetime(2026, 5, 12, 0, 20))
    pruefe(zurueck[0] == datetime(2026, 5, 11, 23, 50),
           "Rueckwaerts datiert: die fruehere Zeile gehoert auf den Vortag.")
    pruefe(zurueck[1] == datetime(2026, 5, 12, 0, 10),
           "Rueckwaerts datiert: die letzte Zeile gehoert zum "
           "Aenderungszeitpunkt.")

    # Die letzte Zeile kann nicht in der Zukunft liegen: Ist ihre Uhrzeit
    # spaeter als die der Aenderung, gehoert sie zum Vortag.
    zeiten3 = ld.zeiten_der_datei(["[23:00:00] z"])
    pruefe(ld.daten_rueckwaerts(zeiten3, datetime(2026, 5, 12, 0, 20))[0]
           == datetime(2026, 5, 11, 23, 0),
           "Eine Zeile, die spaeter als die Aenderungszeit steht, muss auf "
           "den Vortag — sonst laege sie in der Zukunft.")

    pruefe(ld.daten_rueckwaerts([None, None],
                                datetime(2026, 5, 12, 0, 20)) == [None, None],
           "Eine Datei ganz ohne Zeitstempel darf nicht stolpern.")

    # --- Und der Automat, den historie.py benutzt ---------------------
    pruefe(ld.ist_serverprotokoll("2026-05-10-1.log.gz")
           and ld.ist_serverprotokoll("latest.log")
           and not ld.ist_serverprotokoll("gc.log"),
           "ist_serverprotokoll unterscheidet Archive und latest.log nicht "
           "von fremden Dateien wie gc.log.")


def pruefe_kein_nachbau():
    """Das Werkzeug darf die Logik nicht ein zweites Mal enthalten."""
    werkzeug = (REPO / "tools" / "spielerprotokoll-nachtragen.py").read_text(
        encoding="utf-8")
    pruefe("import logdatum" in werkzeug,
           "tools/spielerprotokoll-nachtragen.py benutzt admin/logdatum.py "
           "nicht. Zwei Fassungen derselben Mitternachtslogik sind genau das "
           "Muster, das in diesem Projekt am teuersten war.")
    for name in ("def _daten_vorwaerts", "def _daten_rueckwaerts",
                 "def _zeiten_der_datei"):
        pruefe(name not in werkzeug,
               f"tools/spielerprotokoll-nachtragen.py hat '{name}' noch "
               "selbst — die Logik steht dann an zwei Stellen.")


# ----------------------------------------------------------------------------
# Aufgabe 6 — Sitzungen aus dem Hauptbuch
# ----------------------------------------------------------------------------
# Paper schreibt fuer EINE Trennung ZWEI Zeilen in derselben Sekunde:
# "hat das Spiel verlassen" und "hat die Verbindung verloren (Grund: …)".
# Am 21.09.2026 auf echten Daten nachgezaehlt: 350 solche Paare, dazu 7-mal
# nur die eine und 7-mal nur die andere Zeile. Der Grund steht ausschliesslich
# in der Verbindungszeile -- und er ist keine Formsache: Neben "Disconnected"
# (317) kamen "You have been idle for too long!" (19), "Server closed" (12),
# "Timed out" (6) und zweimal "You logged in from another location" vor.
#
# Die Reihenfolge der beiden Zeilen ist NICHT verlaesslich. Wer die erste
# gewinnen laesst, schreibt am Ende Sortierreihenfolge in die Datenbank und
# nennt sie Grund. Die Pruefung stellt deshalb beide Reihenfolgen nach.
_HAUPTBUCH = (
    "Spieler-Aktivitaetslog (PiCraft)\n"
    "------------------------------\n"
    "2026-05-10 20:00:00 | Spieler_A meldet sich an von 203.0.113.7:51234\n"
    "2026-05-10 20:00:00 | Spieler_A ist dem Spiel beigetreten\n"
    # Paar, Reihenfolge: erst verlassen, dann der Grund.
    "2026-05-10 21:30:00 | Spieler_A hat das Spiel verlassen\n"
    "2026-05-10 21:30:00 | Spieler_A hat die Verbindung verloren "
    "(Grund: Disconnected)\n"
    "2026-05-11 09:00:00 | Spieler_B ist dem Spiel beigetreten\n"
    # Paar, andere Reihenfolge: erst der Grund, dann verlassen.
    "2026-05-11 09:45:00 | Spieler_B hat die Verbindung verloren "
    "(Grund: Timed out)\n"
    "2026-05-11 09:45:00 | Spieler_B hat das Spiel verlassen\n"
    # Einzeln: nur die Verlassen-Zeile, kein Grund bekannt.
    "2026-05-11 11:00:00 | Spieler_C ist dem Spiel beigetreten\n"
    "2026-05-11 11:10:00 | Spieler_C hat das Spiel verlassen\n"
    # Paar UEBER eine Sekundengrenze, und in der gefaehrlichen Reihenfolge:
    # erst verlassen, eine Sekunde spaeter der Grund. Auf den echten Daten
    # ueberspannen 14 von 364 Paaren eine Sekunde -- dort kam zufaellig die
    # Verbindungszeile zuerst. Andersherum ginge der Grund verloren, wenn
    # der Nachtrag Gleichheit statt eines Fensters verlangt.
    "2026-05-11 14:00:00 | Spieler_D ist dem Spiel beigetreten\n"
    "2026-05-11 14:20:00 | Spieler_D hat das Spiel verlassen\n"
    "2026-05-11 14:20:01 | Spieler_D hat die Verbindung verloren "
    "(Grund: Timed out)\n"
    # Anmeldung von einem ZWEITEN Geraet. Woertlich nachgebaut aus dem
    # echten Verlauf vom 08.05.2026: Paper meldet ZUERST den neuen Beitritt
    # und wirft erst DANACH die alte Verbindung hinaus. Wer die
    # Abmeldezeilen der neuen Sitzung zuschlaegt, erzeugt eine Sitzung von
    # null Sekunden und laesst die echte ohne Dauer als "abbruch" stehen.
    "2026-05-11 16:00:00 | Spieler_E ist dem Spiel beigetreten\n"
    "2026-05-11 17:12:00 | Spieler_E ist dem Spiel beigetreten\n"
    "2026-05-11 17:12:00 | Spieler_E hat das Spiel verlassen\n"
    "2026-05-11 17:12:00 | Spieler_E hat die Verbindung verloren "
    "(Grund: You logged in from another location)\n"
    "2026-05-11 17:30:00 | Spieler_E hat das Spiel verlassen\n"
    # Beitritt ohne Ende -- Serverabsturz.
    "2026-05-12 10:00:00 | Spieler_A ist dem Spiel beigetreten\n"
    # Und eine, die noch laeuft.
    "2026-05-13 08:00:00 | Spieler_A ist dem Spiel beigetreten\n"
)


def pruefe_sitzungen(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")

    hauptbuch = tmp / "hauptbuch.log"
    hauptbuch.write_text(_HAUPTBUCH, encoding="utf-8")

    db = h.verbindung(tmp / "historie.db")
    anzahl = h.sitzungen_einlesen(hauptbuch, db)
    pruefe(anzahl == 8, f"Acht Sitzungen erwartet, {anzahl} eingelesen.")

    # Nachschlagen statt Zaehlen: Eine Pruefung, die ueber Listenplaetze
    # geht, verschiebt sich bei jedem neuen Fall und prueft dann klaglos
    # das Falsche.
    stand = {(s, b): (e, sek, g) for s, b, e, sek, g in db.execute(
        "SELECT spieler, beginn, ende, sekunden, grund FROM sitzung")}

    def sitzung(name, beginn, erwartet, was):
        haben = stand.get((name, beginn))
        pruefe(haben == erwartet,
               f"{was}\n      erwartet: {erwartet}\n      bekommen: {haben}")

    # 20:00 bis 21:30 sind anderthalb Stunden. Der Grund kommt aus der
    # Verbindungszeile, EGAL in welcher Reihenfolge die beiden Zeilen
    # stehen. Steht hier "verlassen", hat der Code die Sortierreihenfolge
    # aufgeschrieben und sie Grund genannt.
    sitzung("Spieler_A", "2026-05-10 20:00:00",
            ("2026-05-10 21:30:00", 5400, "Disconnected"),
            "Paar, Verlassen zuerst: Dauer und Grund muessen stimmen.")

    sitzung("Spieler_B", "2026-05-11 09:00:00",
            ("2026-05-11 09:45:00", 2700, "Timed out"),
            "Paar, Grund zuerst: derselbe Grund muss gewinnen.")

    # Ohne Verbindungszeile (7-mal in den echten Daten) ist "verlassen"
    # alles, was man weiss.
    sitzung("Spieler_C", "2026-05-11 11:00:00",
            ("2026-05-11 11:10:00", 600, "verlassen"),
            "Ohne Verbindungszeile bleibt nur 'verlassen'.")

    # Ueber eine Sekundengrenze hinweg, in der gefaehrlichen Reihenfolge.
    sitzung("Spieler_D", "2026-05-11 14:00:00",
            ("2026-05-11 14:20:00", 1200, "Timed out"),
            "Ein Paar ueber eine Sekundengrenze darf den Grund nicht "
            "verlieren — der Nachtrag darf nicht auf Sekundengleichheit "
            "bestehen.")

    # Anmeldung vom zweiten Geraet: Die ALTE Sitzung endet, wenn die neue
    # beginnt, und sie behaelt ihre volle Dauer. Steht hier (None, None,
    # 'abbruch'), sind die Abmeldezeilen der neuen Sitzung zugeschlagen
    # worden — dann steht daneben eine Sitzung von null Sekunden.
    sitzung("Spieler_E", "2026-05-11 16:00:00",
            ("2026-05-11 17:12:00", 4320, "You logged in from another location"),
            "Die abgeloeste Sitzung muss ihr Ende und ihre volle Dauer "
            "behalten.")
    sitzung("Spieler_E", "2026-05-11 17:12:00",
            ("2026-05-11 17:30:00", 1080, "verlassen"),
            "Die neue Sitzung nach der Abloesung laeuft bis zu IHREM Ende, "
            "nicht null Sekunden.")

    # DER PUNKT, an dem das Naheliegende falsch ist: ein Beitritt ohne
    # jedes Ende (Serverabsturz). Die Sitzung darf weder verworfen werden
    # (dann fehlte belegte Anwesenheit) noch ein geratenes Ende bekommen —
    # bis zum naechsten Beitritt waeren das hier zwei Tage.
    sitzung("Spieler_A", "2026-05-12 10:00:00", (None, None, "abbruch"),
            "Ein Beitritt ganz ohne Ende bleibt 'abbruch' ohne Dauer.")

    # Und die letzte: laeuft vielleicht noch.
    sitzung("Spieler_A", "2026-05-13 08:00:00", (None, None, None),
            "Die noch offene Sitzung darf kein erfundenes Ende und keinen "
            "Grund bekommen.")

    # Wiederholbar.
    pruefe(h.sitzungen_einlesen(hauptbuch, db) == 0,
           "Ein zweiter Lauf traegt Sitzungen doppelt ein.")

    # Und sie waechst mit: Kommt das Ende spaeter dazu, wird dieselbe
    # Sitzung ERGAENZT, nicht ein zweites Mal angelegt.
    hauptbuch.write_text(
        _HAUPTBUCH + "2026-05-13 08:30:00 | Spieler_A hat das Spiel "
                     "verlassen\n", encoding="utf-8")
    h.sitzungen_einlesen(hauptbuch, db)
    pruefe(db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0] == 8,
           "Eine nachtraeglich beendete Sitzung wird doppelt angelegt "
           "statt ergaenzt.")
    letzte = db.execute(
        "SELECT ende, sekunden, grund FROM sitzung ORDER BY beginn DESC "
        "LIMIT 1").fetchone()
    pruefe(letzte == ("2026-05-13 08:30:00", 1800, "verlassen"),
           f"Die offene Sitzung bekommt ihr Ende nicht nachgetragen: "
           f"{letzte}.")


# ----------------------------------------------------------------------------
# Aufgabe 7 — Chat und Befehle aus den Serverprotokollen
# ----------------------------------------------------------------------------
def pruefe_aeusserungen(tmp):
    import gzip

    h = lade("historie", REPO / "admin" / "historie.py")

    logs = tmp / "logs"
    logs.mkdir(parents=True, exist_ok=True)

    # Ein Archiv, das ueber Mitternacht laeuft.
    with gzip.open(logs / "2026-05-10-1.log.gz", "wt", encoding="utf-8") as f:
        f.write("[23:58:00] [Async Chat Thread - #0/INFO]: <Spieler_A> hallo\n")
        f.write("[23:59:00] [Server thread/INFO]: Spieler_A issued server "
                "command: /home\n")
        f.write("[00:03:00] [Async Chat Thread - #1/INFO]: <Spieler_B> "
                "gute nacht\n")
        f.write("[00:04:00] [Server thread/INFO]: Preparing spawn area: 12%\n")

    # gc.log liegt im selben Ordner und ist KEIN Serverprotokoll. Es traegt
    # Zeilen in einem ganz anderen Format; wer den Ordner ungefiltert
    # durchgeht, datiert sie trotzdem und traegt Unsinn ein.
    (logs / "gc.log").write_text(
        "[0.123s][info][gc] Using G1\n"
        "[12:00:00] [Server thread/INFO]: <nicht_echt> darf nicht "
        "auftauchen\n", encoding="utf-8")

    db = h.verbindung(tmp / "aeusserungen.db")
    anzahl = h.aeusserungen_einlesen(logs, db)
    pruefe(anzahl == 3, f"Drei Aeusserungen erwartet, {anzahl} gefunden.")

    zeilen = db.execute(
        "SELECT zeit, spieler, art, inhalt FROM aeusserung "
        "ORDER BY zeit").fetchall()
    pruefe(len(zeilen) == 3, f"Drei Zeilen erwartet, {len(zeilen)}.")
    if len(zeilen) != 3:
        return

    pruefe(zeilen[0] == ("2026-05-10 23:58:00", "Spieler_A", "chat", "hallo"),
           f"Chat vor Mitternacht falsch erfasst: {zeilen[0]}")
    pruefe(zeilen[1] == ("2026-05-10 23:59:00", "Spieler_A", "befehl",
                         "/home"),
           f"Serverbefehl falsch erfasst: {zeilen[1]}")
    # Der Tageswechsel MUSS erkannt sein -- sonst stuende die Nachricht
    # einen Tag zu frueh und die Historie waere in sich widerspruechlich.
    pruefe(zeilen[2] == ("2026-05-11 00:03:00", "Spieler_B", "chat",
                         "gute nacht"),
           f"Tageswechsel im Archiv nicht erkannt: {zeilen[2]}")

    pruefe(not any("nicht_echt" in z[1] for z in zeilen),
           "Eine Zeile aus gc.log ist in der Historie gelandet. gc.log ist "
           "kein Serverprotokoll und darf nicht ausgewertet werden.")

    # Ein fertiges Archiv wird nicht noch einmal gelesen.
    pruefe(h.aeusserungen_einlesen(logs, db) == 0,
           "Ein bereits ausgewertetes Archiv wird ein zweites Mal gelesen.")

    # latest.log dagegen waechst und wird JEDES Mal ganz gelesen -- es
    # laesst sich nicht ab einer Lesemarke auswerten, weil das Datum der
    # ersten Zeile am Ende der Datei haengt (Rueckwaertsdatierung).
    latest = logs / "latest.log"
    latest.write_text(
        "[10:00:00] [Async Chat Thread - #0/INFO]: <Spieler_A> moin\n",
        encoding="utf-8")
    os.utime(latest, (1778400000, 1778400000))   # 2026-05-10 ~ 12:40 MESZ
    pruefe(h.aeusserungen_einlesen(logs, db) == 1,
           "Eine neue Zeile in latest.log wird nicht erfasst.")

    latest.write_text(
        "[10:00:00] [Async Chat Thread - #0/INFO]: <Spieler_A> moin\n"
        "[10:05:00] [Async Chat Thread - #1/INFO]: <Spieler_B> auch moin\n",
        encoding="utf-8")
    os.utime(latest, (1778400600, 1778400600))
    pruefe(h.aeusserungen_einlesen(logs, db) == 1,
           "Beim erneuten Lesen von latest.log wird die schon bekannte "
           "Zeile doppelt eingetragen, oder die neue gar nicht.")

    # Und latest.log darf NICHT als fertig vermerkt werden -- sonst waere
    # es nach dem ersten Lauf fuer immer abgehakt und der Chat des
    # laufenden Servers erschiene nie wieder.
    vermerkt = {n for (n,) in db.execute("SELECT datei FROM quelle")}
    pruefe("latest.log" not in vermerkt,
           "latest.log ist als fertig vermerkt. Dann wuerde es nie wieder "
           "gelesen und der Chat des laufenden Servers fehlte dauerhaft.")
    pruefe("2026-05-10-1.log.gz" in vermerkt,
           "Das Archiv ist nicht als fertig vermerkt und wird bei jedem "
           "Aufruf neu entpackt.")


# ----------------------------------------------------------------------------
# Aufgabe 8 — die Abfragen hinter der Seite
# ----------------------------------------------------------------------------
def pruefe_abfragen(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")
    db = h.verbindung(tmp / "abfragen.db")

    db.executemany(
        "INSERT INTO sitzung (spieler, beginn, ende, sekunden, grund) "
        "VALUES (?, ?, ?, ?, ?)",
        [("Spieler_A", "2026-05-10 20:00:00", "2026-05-10 21:00:00",
          3600, "Disconnected"),
         ("Spieler_A", "2026-05-11 20:00:00", "2026-05-11 20:30:00",
          1800, "Disconnected"),
         ("Spieler_B", "2026-05-11 09:00:00", "2026-05-11 10:00:00",
          3600, "Timed out"),
         # Ohne bekanntes Ende: faellt aus jeder Summe heraus.
         ("Spieler_B", "2026-05-12 09:00:00", None, None, "abbruch")])
    db.executemany(
        "INSERT INTO aeusserung (zeit, spieler, art, inhalt) "
        "VALUES (?, ?, ?, ?)",
        [("2026-05-10 20:10:00", "Spieler_A", "chat", "hallo"),
         ("2026-05-10 20:11:00", "Spieler_A", "befehl", "/home"),
         ("2026-05-11 09:30:00", "Spieler_B", "chat", "moin")])
    db.commit()

    # Weit genug zurueck, damit die Pruefdaten von 2026-05 im Fenster
    # liegen -- sonst prueft das hier ab Juni 2026 stillschweigend nichts.
    WEIT = 36500

    alle = h.sitzungen(db)
    pruefe([s["beginn"] for s in alle] == sorted(
               (s["beginn"] for s in alle), reverse=True),
           "Sitzungen muessen neueste zuerst kommen.")

    pruefe(len(h.sitzungen(db, spieler="Spieler_A")) == 2,
           "Der Filter nach Spieler greift bei den Sitzungen nicht.")
    pruefe(len(h.sitzungen(db, ab="2026-05-11")) == 3,
           "Der Filter 'ab' greift bei den Sitzungen nicht.")
    pruefe(len(h.sitzungen(db, grenze=2)) == 2,
           "Die Obergrenze greift nicht — bei Jahren voller Sitzungen ginge "
           "sonst die ganze Tabelle an den Browser.")

    summen = {(s["tag"], s["spieler"]): s["sekunden"]
              for s in h.summen_je_tag(db, tage=WEIT)}
    pruefe(summen.get(("2026-05-11", "Spieler_A")) == 1800,
           f"Die Tagessumme je Spieler stimmt nicht: {summen}")
    pruefe(("2026-05-12", "Spieler_B") not in summen,
           "Eine Sitzung ohne bekanntes Ende taucht in den Summen auf. Sie "
           "hat keine Dauer — sie darf dort nicht als Null erscheinen.")

    je_spieler = {s["spieler"]: (s["sekunden"], s["sitzungen"])
                  for s in h.summen_je_spieler(db, tage=WEIT)}
    pruefe(je_spieler.get("Spieler_A") == (5400, 2),
           f"Summe je Spieler stimmt nicht: {je_spieler}")

    # Und die Zahl, die neben jeder Summe stehen MUSS: Ohne sie sieht eine
    # Summe, der Stunden fehlen, aus wie eine vollstaendige.
    pruefe(h.offene_sitzungen(db, tage=WEIT) == 1,
           "Die Zahl der Sitzungen ohne bekanntes Ende stimmt nicht.")

    pruefe(len(h.aeusserungen(db, art="befehl")) == 1,
           "Der Filter nach Art greift bei den Aeusserungen nicht.")
    pruefe(len(h.aeusserungen(db, spieler="Spieler_A")) == 2,
           "Der Filter nach Spieler greift bei den Aeusserungen nicht.")

    pruefe(h.spielerliste(db) == ["Spieler_A", "Spieler_B"],
           f"Die Spielerliste fuer den Filter stimmt nicht: "
           f"{h.spielerliste(db)}")

    # Ab wann die Historie ueberhaupt etwas weiss.
    #
    # Das ist keine Zierde: Die Spielerseite zeigt die Spielzeit aus den
    # Statistikdateien, und die reicht weiter zurueck als jedes
    # Serverprotokoll. Am 21.09.2026 gemessen: 545 h in der Statistik
    # gegen 92 h in der Historie. Ohne den Zeitraum daneben sieht das wie
    # ein Fehler aus -- oder schlimmer, man glaubt der kleineren Zahl.
    von, bis = h.zeitraum(db)
    pruefe(von == "2026-05-10" and bis == "2026-05-12",
           f"Der bekannte Zeitraum stimmt nicht: {von} bis {bis}")
    pruefe(h.zeitraum(h.verbindung(tmp / "leer.db")) == (None, None),
           "Eine leere Historie muss (None, None) liefern, nicht stolpern.")


def pruefe_aufruestweg():
    """Neue mcs.conf-Schluessel muessen auch auf BESTEHENDEN Installationen
    ankommen.

    install.sh richtet ein, deploy.sh rollt aus. Ein Schluessel nur in
    mcs.conf.beispiel erreicht keine bestehende Installation -- und eine
    Sammelbedingung ("wenn der erste Schluessel fehlt") laesst spaeter
    Hinzugekommenes stillschweigend liegen. Beides steht so in CLAUDE.md,
    beides ist hier schon passiert.
    """
    vorlage = (REPO / "mcs.conf.beispiel").read_text(encoding="utf-8")
    deploy = (REPO / "deploy.sh").read_text(encoding="utf-8")

    for schluessel in ("MCS_HISTORIE_DB", "MCS_HISTORIE_TAGE"):
        pruefe(f"{schluessel}=" in vorlage,
               f"{schluessel} fehlt in mcs.conf.beispiel — eine frische "
               "Installation kennt ihn dann nicht.")
        pruefe(schluessel in deploy,
               f"{schluessel} wird von deploy.sh nicht nachgetragen — "
               "bestehende Installationen bekommen ihn nie zu sehen.")

    # Und die eigene Abfrage, nicht als Anhaengsel einer fremden.
    pruefe("grep -q '^MCS_HISTORIE_DB=' \"$MCS_CONF\"" in deploy,
           "deploy.sh prueft nicht eigens auf MCS_HISTORIE_DB. Wer die "
           "aelteren Schluessel schon hat, bekaeme die neuen sonst nie.")


def pruefe_aufbewahrung_und_rechte(tmp):
    h = lade("historie", REPO / "admin" / "historie.py")

    # --- Rechte --------------------------------------------------------
    #
    # Die Datei enthaelt Chat-Inhalte und Spielernamen. Die Rechte gehoeren
    # VOR den Inhalt, nicht danach -- sonst steht der Chat einen Wimpernschlag
    # lang offen, und bei einem Abbruch dazwischen dauerhaft.
    frisch = tmp / "rechte.db"
    db_rechte = h.verbindung(frisch)
    modus = oct(os.stat(frisch).st_mode & 0o777)
    pruefe(modus == "0o600",
           f"historie.db wird mit {modus} angelegt statt 0o600. Sie enthaelt "
           "Chat-Inhalte und Spielernamen.")

    # Eine zu offen liegende Datei aus einer aelteren Installation wird
    # beim Oeffnen richtiggestellt.
    os.chmod(frisch, 0o644)
    h.verbindung(frisch)
    pruefe(oct(os.stat(frisch).st_mode & 0o777) == "0o600",
           "Eine zu offen liegende historie.db wird beim Oeffnen nicht "
           "richtiggestellt.")

    # Und die Nebendateien, die SQLite anlegt. Heute laeuft die Historie im
    # Standard-Journalmodus, dann gibt es keine dauerhaften -- aber wer
    # spaeter auf WAL umstellt (metrik.db tut das), legt ein -wal daneben,
    # und in dem stehen dieselben Chat-Inhalte.
    db_rechte.execute("INSERT INTO aeusserung VALUES "
                      "('2026-01-01 00:00:00','Spieler_A','chat','geheim')")
    db_rechte.commit()
    import glob
    for neben in glob.glob(str(frisch) + "?*"):
        neben_modus = oct(os.stat(neben).st_mode & 0o777)
        pruefe(neben_modus == "0o600",
               f"{os.path.basename(neben)} liegt mit {neben_modus} daneben. "
               "In den Nebendateien von SQLite stehen dieselben Inhalte.")

    # --- Aufbewahrung --------------------------------------------------
    db = h.verbindung(tmp / "aufraeumen.db")
    db.executemany(
        "INSERT INTO sitzung (spieler, beginn, ende, sekunden, grund) "
        "VALUES (?, ?, ?, ?, ?)",
        [("Spieler_A", "2020-01-01 10:00:00", "2020-01-01 11:00:00",
          3600, "Disconnected"),
         ("Spieler_A", "2026-09-01 10:00:00", "2026-09-01 11:00:00",
          3600, "Disconnected")])
    db.execute("INSERT INTO aeusserung VALUES (?, ?, ?, ?)",
               ("2020-01-01 10:30:00", "Spieler_A", "chat", "uralt"))
    db.commit()

    # DIE Falle: ${X:-standard} greift nicht bei einer ausdruecklichen 0.
    # Aus MCS_BACKUP_BEHALTEN=0 wurde hier einmal "behalte ab Zeile 1", und
    # ein Lauf raeumte beide Backup-Platten leer (31.08.2026).
    pruefe(h.aufraeumen(db, 0) == 0,
           "MCS_HISTORIE_TAGE=0 muss 'unbegrenzt' heissen und darf NICHTS "
           "loeschen.")
    pruefe(db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0] == 2,
           "Bei 0 duerfen keine Zeilen verschwinden.")

    # Und was keine Zahl ist, darf erst recht nichts loeschen.
    for unsinn in (None, "", "viele", -5):
        pruefe(h.aufraeumen(db, unsinn) == 0,
               f"aufraeumen({unsinn!r}) loescht etwas. Geloescht wird nie auf "
               "Grundlage eines Wertes, dem der Code nicht trauen kann.")
    pruefe(db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0] == 2,
           "Ein unbrauchbarer Wert hat Zeilen geloescht.")

    # Mit einer echten Frist verschwindet der alte Eintrag -- und die alte
    # Aeusserung mit ihm.
    weg = h.aufraeumen(db, 365)
    pruefe(weg == 2, f"Mit einer Frist muessen Sitzung UND Aeusserung "
                     f"verschwinden, geloescht wurden {weg}.")
    pruefe(db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0] == 1,
           "Der junge Eintrag ist mitgeloescht worden.")


# ----------------------------------------------------------------------------
# Aufgabe 8 — die Seiten antworten ueberhaupt
# ----------------------------------------------------------------------------
def pruefe_seiten(tmp):
    """Ruft jede Seite der Oberflaeche einmal auf.

    Warum ALLE und nicht nur die neue: Eine neue Blueprint, ein neuer
    Reiter in basis.html und eine neue Zeile in app.py koennen jede andere
    Seite mitreissen -- basis.html steckt in allen. `make` findet das
    nicht: Es prueft Python- und Shell-Syntax, nicht ob Jinja eine Vorlage
    findet oder ein Endpunkt existiert.

    In einem EIGENEN PROZESS, und das ist kein Umweg: einstellungen.py
    liest die MCS_*-Variablen beim Import. Wer sie danach setzt und die
    Module neu laedt, aendert damit nichts mehr -- der erste Versuch am
    21.09.2026 lief deshalb still gegen die echten Daten des Pi statt
    gegen die vorbereitete leere Historie und hielt das Ergebnis fuer
    einen Befund. Ein frischer Prozess prueft nebenbei, dass app.py
    ueberhaupt von null hochkommt.
    """
    import json
    import subprocess

    (tmp / "hauptbuch.log").write_text("", encoding="utf-8")
    (tmp / "logs").mkdir(parents=True, exist_ok=True)

    kind = tmp / "seitenprobe.py"
    kind.write_text(f'''
import json, sys
sys.path.insert(0, {str(REPO / "admin")!r})
import app as anwendung
anwendung.app.config["TESTING"] = True
ergebnis = {{"codes": {{}}, "leertext": False}}
with anwendung.app.test_client() as c:
    with c.session_transaction() as s:
        s["angemeldet"] = True
        s["token"] = "pruefung"
    for pfad in ("/", "/spieler", "/historie", "/leistung", "/karte",
                 "/backups", "/konfiguration", "/plugins",
                 "/teil/spielerliste", "/teil/historienliste",
                 "/historie?spieler=gibt_es_nicht"):
        antwort = c.get(pfad)
        ergebnis["codes"][pfad] = antwort.status_code
        if pfad == "/historie":
            ergebnis["leertext"] = (
                "Noch nichts aufgezeichnet" in antwort.get_data(as_text=True))
print("ERGEBNIS " + json.dumps(ergebnis))
''', encoding="utf-8")

    umgebung = dict(os.environ)
    umgebung.update({
        "MCS_HISTORIE_DB": str(tmp / "seiten.db"),
        "MCS_PLAYER_ACTIVITY_LOG": str(tmp / "hauptbuch.log"),
        "MCS_MINECRAFT_LOG": str(tmp / "logs" / "latest.log"),
    })

    lauf = subprocess.run([sys.executable, str(kind)], env=umgebung,
                          capture_output=True, text=True, timeout=120)

    if lauf.returncode != 0:
        # Laut sagen, wenn Flask fehlt -- aber nur dann. Jeder andere
        # Fehlschlag ist ein Befund und kein Grund zum Durchwinken.
        if "ModuleNotFoundError" in lauf.stderr and "flask" in lauf.stderr.lower():
            print("  !! UEBERSPRUNGEN: Flask ist hier nicht installiert — "
                  "die Seiten wurden NICHT aufgerufen.")
            return
        pruefe(False, "Die Oberflaeche liess sich nicht starten:\n"
                      + lauf.stderr.strip()[-1200:])
        return

    zeile = next((z for z in lauf.stdout.splitlines()
                  if z.startswith("ERGEBNIS ")), None)
    pruefe(zeile is not None,
           "Der Seitenlauf hat kein Ergebnis gemeldet — dann prueft er "
           "nichts, auch wenn er mit 0 endet.")
    if zeile is None:
        return

    ergebnis = json.loads(zeile[len("ERGEBNIS "):])
    for pfad, code in ergebnis["codes"].items():
        pruefe(code == 200, f"{pfad} antwortet mit {code} statt 200.")

    pruefe(ergebnis["leertext"],
           "Eine leere Historie zeigt keinen erklaerenden Text — dann sieht "
           "'noch nie jemand da' genauso aus wie 'kaputt'.")


# ----------------------------------------------------------------------------
# Auswertung
# ----------------------------------------------------------------------------
def main():
    pruefe_logrotate()
    with tempfile.TemporaryDirectory() as ordner:
        pruefe_waechter(Path(ordner))
    pruefe_logdatum()
    pruefe_kein_nachbau()
    pruefe_aufruestweg()
    with tempfile.TemporaryDirectory() as ordner:
        pruefe_sitzungen(Path(ordner))
    with tempfile.TemporaryDirectory() as ordner:
        pruefe_aeusserungen(Path(ordner))
    with tempfile.TemporaryDirectory() as ordner:
        pruefe_abfragen(Path(ordner))
    with tempfile.TemporaryDirectory() as ordner:
        pruefe_aufbewahrung_und_rechte(Path(ordner))
    # Zuletzt: Sie faelscht die Umgebung (MCS_*-Variablen) und laedt app.py.
    with tempfile.TemporaryDirectory() as ordner:
        pruefe_seiten(Path(ordner))

    for text in fehler:
        print(f"FEHLER: {text}")
    print(f"{len(fehler)} Fehler." if fehler else "Alle Pruefungen bestanden.")
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
