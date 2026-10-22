#!/usr/bin/env python3
"""
protokollpruefung.py — Merkt, wenn dem Spielerprotokoll die Vergangenheit
fehlt.

Warum es diese Datei gibt (Befund 21.09.2026): Das Spielerprotokoll stand
in der logrotate-Regel aus install.sh. Nach jeder Rotation war die
Live-Datei leer, und die Spielerseite meldete fuer JEDEN Spieler "nicht
aufgezeichnet" -- auch fuer solche mit dreistelligen Stundenzahlen. Zwei
Wochen lang fiel das niemandem auf, weil "keine Daten" auf dieser Seite
genauso aussieht wie "war noch nie da".

Die Ursache ist behoben (das Hauptbuch wird nicht mehr rotiert). Diese
Pruefung sorgt dafuer, dass ein Rueckfall nicht wieder still bleibt:
Beginnt das Protokoll deutlich spaeter als das aelteste Serverprotokoll,
fehlt etwas -- denn die Serverprotokolle sind die Quelle, aus der sich das
Hauptbuch mit tools/spielerprotokoll-nachtragen.py wiederherstellen laesst.

Zwei Entscheidungen, die hier bewusst so getroffen sind:

 1. **Kein zweiter Leseweg auf das Hauptbuch.** Die Oberflaeche liest
    weiterhin nur die Live-Datei; diese Pruefung liest nur deren ERSTEN
    Zeitstempel und vergleicht ihn. Sie beantwortet keine Fachfrage. Ein
    zweiter Weg zur selben Datei, der die Regel des ersten nicht kennt,
    ist in diesem Projekt mehrfach die Fehlerquelle gewesen.
 2. **Ohne Serverprotokolle wird geschwiegen.** Auf einer frischen
    Installation gibt es nichts zu vergleichen, und "nicht feststellbar"
    ist dann die richtige Antwort -- nicht ein Alarm ins Blaue.

Das Modul kommt ohne einstellungen.py aus, damit die Pruefung unter
tests/ es einzeln laden kann, ohne die ganze Anwendung mitzuziehen.
"""

import re
from datetime import date, timedelta
from pathlib import Path

# Welcher Tag zu einem Serverprotokoll gehoert, weiss logdatum.py — und nur
# dort steht es. Hier stand bis zum 23.09.2026 eine eigene Kopie des
# Namensmusters: Dieses Modul entstand am 21.09. wenige Stunden VOR dem
# Umbau, der die Datumsherleitung an eine Stelle holte (be7de8d), und wurde
# dabei uebersehen. logdatum kommt ebenfalls ohne einstellungen.py aus.
from logdatum import archivtag

# Eine Zeile des Hauptbuchs beginnt mit "YYYY-MM-DD HH:MM:SS | ".
# Die beiden Kopfzeilen ("Spieler-Aktivitaetslog (PiCraft)" und die
# Strichlinie) tragen keinen Zeitstempel und zaehlen deshalb nicht als
# Protokollbeginn -- wichtig, weil log_player_activity.sh sie nach einem
# copytruncate neu anlegt: Die Datei ist dann nicht leer, aber ohne
# Vergangenheit.
_ZEITSTEMPEL = re.compile(r"^(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}:\d{2} \| ")

# Wie viel Vorsprung das aelteste Serverprotokoll haben darf, ohne dass es
# ein Befund ist. Ein Tag Unterschied ist Alltag -- das Protokoll beginnt
# mit dem ersten Beitritt, nicht mit dem ersten Serverstart. Eine Woche ist
# es nicht mehr.
TOLERANZ_TAGE = 7


def _erster_protokolltag(hauptbuch):
    """Der erste datierte Tag im Hauptbuch, oder None.

    None heisst "die Datei sagt nichts ueber die Vergangenheit" -- sei sie
    leer, nur mit Kopfzeilen versehen oder gar nicht vorhanden.
    """
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
            tag = archivtag(eintrag.name)
            if tag is not None:
                tage.append(tag)
    except OSError:
        return None
    return min(tage) if tage else None


def protokoll_lueckenhaft(hauptbuch, logordner):
    """None = nichts zu melden. Sonst ein Befund mit beiden Datumsangaben.

    Der Befund ist ein dict mit den Schluesseln `protokoll_beginn`,
    `aeltestes_log` und `text`. `protokoll_beginn` ist None, wenn das
    Hauptbuch keinen einzigen datierten Eintrag enthaelt.
    """
    aeltestes = _aeltester_logtag(logordner)
    if aeltestes is None:
        return None

    beginn = _erster_protokolltag(hauptbuch)

    if beginn is None:
        return {
            "protokoll_beginn": None,
            "aeltestes_log": aeltestes.isoformat(),
            "text": ("Das Spielerprotokoll enthält keinen einzigen Eintrag, "
                     "es liegen aber Serverprotokolle ab "
                     f"{aeltestes.isoformat()} vor. Die Vergangenheit lässt "
                     "sich daraus wiederherstellen: "
                     "python3 tools/spielerprotokoll-nachtragen.py"),
        }

    if beginn - aeltestes <= timedelta(days=TOLERANZ_TAGE):
        return None

    return {
        "protokoll_beginn": beginn.isoformat(),
        "aeltestes_log": aeltestes.isoformat(),
        "text": (f"Das Spielerprotokoll beginnt erst am {beginn.isoformat()}, "
                 f"die Serverprotokolle reichen bis {aeltestes.isoformat()} "
                 "zurück. Die Lücke lässt sich schließen: "
                 "python3 tools/spielerprotokoll-nachtragen.py"),
    }


# ----------------------------------------------------------------------------
# Zweite Pruefung: Erkennen die Muster die Beitritte noch? (21.10.2026)
# ----------------------------------------------------------------------------
# Vom 14. bis zum 21.10.2026 fand MUSTER_BEITRITT keinen einzigen Beitritt,
# weil Paper 26.3 vor "joined the game" ein "System chat: " setzt. Folge:
# 0 Spieler in der Oberflaeche, keine Sitzung in der Historie, keine
# Vorwarnung vor einem Neustart -- und nirgends eine Meldung, denn "nichts
# gefunden" ist fuer jede dieser Auswertungen ein gueltiges Ergebnis.
#
# Darum zaehlt diese Pruefung Zeugen, die von den gemeinsamen Mustern
# UNABHAENGIG sind: Zeilen, die auf "joined the game" oder "logged in with
# entity id" enden bzw. diesen Text enthalten. Beides schreibt Paper fuer
# jeden Beitritt, und beides ist absichtlich lose gesucht -- ein Zeuge, der
# am selben Muster haengt wie das, was er bewacht, faellt mit ihm aus. Gibt
# es seit dem letzten Serverstart Zeugen, aber keinen erkannten Beitritt,
# sieht die Spielerzaehlung nichts mehr.
#
# Eine Chatzeile ("<Anna> Bob joined the game") ist kein Zeuge. Und ein
# Zeuge zaehlt erst, wenn hinter ihm noch eine Zeile steht: Bis Paper 26.2
# kam "logged in" VOR "joined", seit 26.3 danach. Wer genau dazwischen
# liest, saehe sonst fuenf Minuten lang einen Fehler, den es nicht gibt.
_ZEUGEN = (
    re.compile(r"\]: [A-Za-z0-9_]{1,16}\[/[^]]*\] logged in with entity id"),
    re.compile(r"\]: (?!<|\[Not Secure\] <).*joined the game$"),
)

def _neuer_stand(inode=None):
    return {"inode": inode, "offset": 0, "zeugen": [0] * len(_ZEUGEN),
            "offen": [0] * len(_ZEUGEN), "beitritte": 0}


# Lesestand: latest.log beginnt bei jedem Serverstart neu (neue Inode) und
# wird nur angehaengt. Gelesen wird deshalb nur, was dazukam.
_beitritt_stand = _neuer_stand()


def beitritte_unerkannt(logdatei, beitritt_re, stand=None):
    """None = nichts zu melden. Sonst ein Befund mit `zeugen`, `kurz`, `text`.

    `beitritt_re` ist das kompilierte MUSTER_BEITRITT (aus protokoll.py),
    also genau das, was Oberflaeche, Spielerprotokoll und Historie benutzen.
    `stand` nur fuer Tests; im Betrieb gilt der Lesestand dieses Moduls.
    """
    stand = _beitritt_stand if stand is None else stand
    try:
        info = Path(logdatei).stat()
    except OSError:
        return None

    if info.st_ino != stand["inode"] or info.st_size < stand["offset"]:
        stand.update(_neuer_stand(info.st_ino))

    if info.st_size > stand["offset"]:
        try:
            with open(logdatei, "rb") as f:
                f.seek(stand["offset"])
                roh = f.read()
        except OSError:
            return None
        # Nur vollstaendige Zeilen, wie in protokoll.online_players().
        ende = roh.rfind(b"\n") + 1
        stand["offset"] += ende
        for zeile in roh[:ende].decode("utf-8", errors="ignore").splitlines():
            for i, zeuge in enumerate(_ZEUGEN):
                stand["zeugen"][i] += stand["offen"][i]
                stand["offen"][i] = 1 if zeuge.search(zeile) else 0
            if beitritt_re.search(zeile):
                stand["beitritte"] += 1

    # Jeder Beitritt hinterlaesst BEIDE Zeugen; gemeldet wird deshalb die
    # groessere Zahl, nicht die Summe.
    zeugen = max(stand["zeugen"])
    if stand["beitritte"] or not zeugen:
        return None

    return {
        "zeugen": zeugen,
        "kurz": ("Spieler melden sich an, aber kein Beitritt wird erkannt — "
                 "die Spielerzählung ist blind. Details auf der Seite Spieler."),
        "text": (f"Seit dem letzten Serverstart stehen {zeugen} "
                 "Beitritte im Serverprotokoll, aber MUSTER_BEITRITT erkennt "
                 "keinen davon. Vermutlich hat eine neue Paper-Version das "
                 "Format geändert (am 14.10.2026 kam so „System chat: “ "
                 "dazu). Bis das behoben ist, zeigt die Oberfläche 0 Spieler, "
                 "die Historie bekommt keine Sitzungen, und vor einem Neustart "
                 "warnt niemand. Abhilfe: das Muster in tools/log-muster.sh "
                 "anpassen, mit make muster prüfen, danach "
                 "python3 tools/spielerprotokoll-nachtragen.py"),
    }
