#!/usr/bin/env python3
"""
logdatum.py — Welcher Tag gehoert zu einer Serverlogzeile?

In den Zeilen des Serverprotokolls steht **kein Datum**, nur `[HH:MM:SS]`.
Das Datum muss also von aussen kommen, und dafuer gibt es zwei Faelle --
der zweite ist der, den man beim Nachbauen vergisst:

    Archiv ("2026-05-10-1.log.gz")   Der Dateiname nennt den ERSTEN Tag.
                                     -> vorwaerts rechnen

    latest.log                       Der Name sagt nichts. Die letzte
                                     AENDERUNG der Datei gehoert zur
                                     LETZTEN Zeile.  -> rueckwaerts rechnen

Laeuft ein Server ueber Mitternacht, springt die Uhrzeit zurueck. Das ist
das einzige Erkennungsmerkmal, das die Zeilen selbst hergeben -- vorwaerts
heisst das "Tag hoch", rueckwaerts "Tag runter".

WARUM DIESE DATEI EXISTIERT (21.09.2026): Die Logik stand nur in
tools/spielerprotokoll-nachtragen.py, wo sie am 01.09.2026 als W3 geprueft
wurde -- einschliesslich zweier synthetisch nachgestellter
Mitternachtsfaelle, weil es auf diesem Pi keinen echten gab. Der
Historien-Index (admin/historie.py) braucht genau dieselbe Herleitung. Sie
ein zweites Mal zu schreiben waere der Fehler gewesen, der in diesem
Projekt am haeufigsten Geld gekostet hat: ein zweiter Weg zur selben
Sache, der die Regel des ersten nicht kennt. Zwei Werkzeuge, die dieselbe
Zeile unterschiedlich datieren, erzeugen widersprueche Anzeigen, und
gemerkt haette man es erst Monate spaeter.

Die Funktionen sind deshalb WOERTLICH aus dem Werkzeug uebernommen; das
Werkzeug benutzt seitdem diese Datei. Wer hier etwas aendert, aendert es
fuer beide -- und genau das ist der Zweck.

Das Modul kommt ohne einstellungen.py und ohne Flask aus, damit die
Pruefung unter tests/ es einzeln laden kann.
"""

import re
from datetime import date, datetime, time, timedelta

# Aus "2026-08-31-2.log.gz" wird der 31.08.2026.
ARCHIVNAME = re.compile(r"^(\d{4})-(\d{2})-(\d{2})-\d+\.log(\.gz)?$")

# Der Zeitstempel am Anfang jeder Server-Logzeile: "[10:25:46] […"
LOGZEIT = re.compile(r"^\[(\d{2}):(\d{2}):(\d{2})\]")


def archivtag(dateiname):
    """Der erste Tag eines Archivs, oder None.

    None heisst "kein Archiv" -- das gilt fuer latest.log genauso wie fuer
    gc.log. Der Aufrufer entscheidet dann, ob er rueckwaerts datiert oder
    die Datei ueberhaupt nicht anfasst.
    """
    treffer = ARCHIVNAME.match(str(dateiname))
    if not treffer:
        return None
    return date(int(treffer.group(1)), int(treffer.group(2)),
                int(treffer.group(3)))


def ist_serverprotokoll(dateiname):
    """Ob diese Datei ueberhaupt Serverlogzeilen enthaelt.

    Im logs-Ordner liegt mehr als die Protokolle -- gc.log zum Beispiel,
    das Speicherbereinigungs-Protokoll der JVM. Es traegt keine
    Logzeilen in diesem Format und gehoert nicht ausgewertet.
    """
    name = str(dateiname)
    return name == "latest.log" or ARCHIVNAME.match(name) is not None


def zeiten_der_datei(zeilen):
    """Zu jeder Zeile die Uhrzeit, oder None. Reihenfolge bleibt erhalten.

    Die Reihenfolge ist nicht Nebensache: Das Ergebnis wird spaeter Zeile
    fuer Zeile mit den Eingabezeilen gepaart. Eine Zeile ohne Zeitstempel
    faellt deshalb NICHT weg, sie wird zu None.
    """
    aus = []
    for zeile in zeilen:
        treffer = LOGZEIT.match(zeile)
        aus.append(time(int(treffer.group(1)), int(treffer.group(2)),
                        int(treffer.group(3))) if treffer else None)
    return aus


def daten_vorwaerts(zeiten, start):
    """Datiert ein Archiv: Der Dateiname nennt den ERSTEN Tag.

    Springt die Uhrzeit zurueck, ist Mitternacht vergangen. Das ist das
    einzige Erkennungsmerkmal, das die Zeilen selbst hergeben.
    """
    tag, vorige, aus = start, None, []
    for zeit in zeiten:
        if zeit is None:
            aus.append(None)
            continue
        if vorige is not None and zeit < vorige:
            tag += timedelta(days=1)
        vorige = zeit
        aus.append(datetime.combine(tag, zeit))
    return aus


def daten_rueckwaerts(zeiten, ende):
    """Datiert latest.log: Die LETZTE Zeile liegt beim Aenderungszeitpunkt.

    Der Dateiname sagt hier nichts, also wird vom bekannten Ende her
    zurueckgerechnet — steigt die Uhrzeit beim Rueckwaertsgehen, liegt die
    fruehere Zeile einen Tag davor.

    Folge fuer jeden Aufrufer: latest.log laesst sich NICHT ab einer
    Lesemarke stueckweise auswerten. Das Datum der ersten Zeile haengt am
    Ende der Datei — wer nur den Zuwachs liest, kennt es nicht. Die Datei
    wird bei jedem Serverstart neu angelegt und ist entsprechend klein;
    sie wird ganz gelesen.
    """
    echte = [(i, z) for i, z in enumerate(zeiten) if z is not None]
    aus = [None] * len(zeiten)
    if not echte:
        return aus

    tag = ende.date()
    # Die letzte Zeile kann nicht in der Zukunft liegen. Ist ihre Uhrzeit
    # spaeter als die des Aenderungszeitpunkts, gehoert sie zum Vortag.
    if echte[-1][1] > ende.time():
        tag -= timedelta(days=1)

    naechste = None
    for i, zeit in reversed(echte):
        if naechste is not None and zeit > naechste:
            tag -= timedelta(days=1)
        naechste = zeit
        aus[i] = datetime.combine(tag, zeit)
    return aus


def datieren(pfad, zeilen, mtime=None):
    """Der bequeme Weg: waehlt die richtige Strategie selbst.

    `pfad` entscheidet -- ein Archivname fuehrt zu "vorwaerts", alles
    andere zu "rueckwaerts" ab `mtime`. So muss kein Aufrufer die beiden
    Faelle noch einmal auseinanderhalten; genau daran wuerde der zweite
    Aufrufer sonst scheitern.
    """
    from pathlib import Path

    pfad = Path(pfad)
    zeiten = zeiten_der_datei(zeilen)

    tag = archivtag(pfad.name)
    if tag is not None:
        return daten_vorwaerts(zeiten, tag)

    if mtime is None:
        mtime = datetime.fromtimestamp(pfad.stat().st_mtime)
    return daten_rueckwaerts(zeiten, mtime)
