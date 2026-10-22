#!/usr/bin/env python3
"""
spielerprotokoll-nachtragen.py — Die Vergangenheit ins Spielerprotokoll holen.

Das Spielerprotokoll (`player_activity.log`) entsteht erst, seit
`mcs-playerlog` laeuft. Alles davor fehlt darin — obwohl es laengst
aufgeschrieben ist: Paper schreibt jede An- und Abmeldung nach `logs/`, und
die alten Laeufe liegen dort gepackt.

Die Folge war eine Oberflaeche, die "war noch nie da" ueber jemanden schrieb,
der hunderte Stunden gespielt hat. Genau das ist gemeint mit "ehrlich statt
bequem": Eine Anzeige darf "nicht feststellbar" sagen, sie darf nicht das
Gegenteil behaupten.

Dieses Werkzeug liest `logs/*.log.gz` und `logs/latest.log` und traegt die
dort verzeichneten Ereignisse im Format des Spielerprotokolls nach.

    python3 tools/spielerprotokoll-nachtragen.py            # nachtragen
    python3 tools/spielerprotokoll-nachtragen.py --zeigen   # nur berichten

Es ist WIEDERHOLBAR: Ein zweiter Lauf aendert nichts. Verglichen wird der
fertige Text jeder Zeile, und geschrieben wird eine sortierte, doppelfreie
Zusammenfuehrung aus Altbestand und Nachtrag.

Zwei Dinge, bei denen das Naheliegende hier falsch ist:

 1. **In den Logzeilen steht kein Datum**, nur `[HH:MM:SS]`. Das Datum kommt
    beim Archiv aus dem Dateinamen (`2026-08-31-2.log.gz`), bei `latest.log`
    aus der letzten Aenderung der Datei. Laeuft der Server ueber Mitternacht,
    springt die Uhrzeit zurueck — daran, und nur daran, ist der Tageswechsel
    zu erkennen.
 2. **Gepackte Protokolle und `set -o pipefail`** sind in diesem Projekt
    schon einmal aufeinandergestossen: `zcat … | grep -q` endet mit 141,
    sobald grep vor dem Erzeuger fertig ist, und zwar erst ab einer gewissen
    Dateigroesse — im Container also oft nie. Deshalb ist das hier Python
    mit dem `gzip`-Modul und keine Pipeline.

Die Ausgabe gehoert NICHT ins Repository: Im Spielerprotokoll stehen echte
Namen und Heimnetzadressen. Wer einen Messbeleg braucht, nimmt Platzhalter.
"""

import argparse
import gzip
import os
import re
import sys
from datetime import datetime
from pathlib import Path

_ADMIN = Path(__file__).resolve().parent.parent / "admin"
sys.path.insert(0, str(_ADMIN))

import logdatum  # noqa: E402
from einstellungen import (MINECRAFT_LOG,  # noqa: E402
                           PLAYER_ACTIVITY_LOG, lade_mcs_conf)
from protokoll import lade_log_muster  # noqa: E402

lade_mcs_conf()

# Die Suchmuster kommen aus log-muster.sh — derselben Datei, die das
# Live-Skript und die Weboberflaeche lesen. Ein drittes Musterpaar hier
# waere genau der Fehler, den diese Datei in ihrem Kopf beschreibt:
# Aendert Paper sein Logformat, faende der Nachtrag stillschweigend nichts.
_MUSTER = lade_log_muster() or lade_log_muster(
    str(Path(__file__).with_name("log-muster.sh")))

if not _MUSTER:
    print("Fehler: log-muster.sh nicht gefunden — ohne die Suchmuster kann "
          "dieses Werkzeug nichts erkennen.", file=sys.stderr)
    raise SystemExit(1)


def _re(name):
    return re.compile(_MUSTER[name])


# Je Ereignisart: das Muster, ein Rang fuer die Sortierung innerhalb einer
# Sekunde, und wie die Zeile im Spielerprotokoll lautet. Die Texte sind
# woertlich die aus log_player_activity.sh — steht hier ein anderer, gaebe
# es zwei Schreibweisen desselben Ereignisses und der Abgleich fiele aus.
EREIGNISSE = [
    (_re("MUSTER_UUID"), 0,
     lambda t: f"Spieler {t[1]} meldet sich an (UUID: {t[2]})"),
    (_re("MUSTER_ANMELDUNG"), 1,
     lambda t: f"{t[1]} meldet sich an von {t[2]}"),
    # Beitritt und Verlassen: Name in t[2], nicht t[1] — seit Paper 26.3
    # kann "System chat: " davorstehen (siehe Kopf von log-muster.sh).
    (_re("MUSTER_BEITRITT"), 2,
     lambda t: f"{t[2]} ist dem Spiel beigetreten"),
    (_re("MUSTER_VERLASSEN"), 3,
     lambda t: f"{t[2]} hat das Spiel verlassen"),
    (_re("MUSTER_VERBINDUNG_WEG"), 3,
     lambda t: f"{t[1]} hat die Verbindung verloren (Grund: {t[2]})"),
    (_re("MUSTER_ABGELEHNT"), 4,
     lambda t: f"Verbindung von {t[1]} [{t[2]}] abgelehnt: {t[3]}"),
]

# Eine Zeile des Spielerprotokolls: "2026-08-28 15:41:03 | Kaya ist dem …"
_EINTRAG = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| (.+)$")

# Der Zeitstempel am Anfang jeder Server-Logzeile steht seit dem
# 21.09.2026 als logdatum.LOGZEIT im gemeinsamen Modul.

def _rang(text):
    """Wohin eine Zeile innerhalb derselben Sekunde gehoert.

    Anmeldung vor Beitritt vor Austritt — sonst stuende in der sortierten
    Datei, jemand sei dem Spiel beigetreten, bevor er sich angemeldet hat.
    Fuer Zeilen aus dem Altbestand wird der Rang am Text erkannt.
    """
    if text.startswith("Spieler ") and "(UUID:" in text:
        return 0
    if " meldet sich an von " in text:
        return 1
    if text.endswith(" ist dem Spiel beigetreten"):
        return 2
    if text.startswith("Verbindung von "):
        return 4
    return 3


def _datei_auswerten(pfad):
    """Liefert {(zeitpunkt, rang, text)} fuer eine Server-Logdatei.

    Die Datierung uebernimmt admin/logdatum.py und waehlt selbst zwischen
    vorwaerts (Archiv) und rueckwaerts (latest.log). Seit dem 21.09.2026
    steht diese Logik dort und nicht mehr hier -- der Historien-Index
    braucht sie genauso, und zwei Fassungen waeren der teuerste Fehler
    dieses Projekts.
    """
    oeffnen = gzip.open if str(pfad).endswith(".gz") else open
    try:
        with oeffnen(pfad, "rt", encoding="utf-8", errors="ignore") as f:
            zeilen = f.read().splitlines()
    except (OSError, EOFError) as fehler:
        # Ein abgebrochenes Archiv ist kein Grund, den ganzen Nachtrag
        # aufzugeben — aber auch keiner, es zu verschweigen.
        print(f"  ! {Path(pfad).name} liess sich nicht lesen: {fehler}")
        return set()

    zeitpunkte = logdatum.datieren(pfad, zeilen)

    gefunden = set()
    for zeile, zeitpunkt in zip(zeilen, zeitpunkte):
        if zeitpunkt is None:
            continue
        for muster, rang, bauen in EREIGNISSE:
            treffer = muster.match(zeile)
            if treffer:
                gefunden.add((zeitpunkt, rang, bauen(treffer.groups())))
                break
    return gefunden


def serverlogs_lesen(logordner):
    """Alle Ereignisse aus logs/*.log.gz und logs/latest.log."""
    ordner = Path(logordner)
    if not ordner.is_dir():
        print(f"Fehler: {ordner} gibt es nicht.", file=sys.stderr)
        return None, 0

    alles = set()
    dateien = 0

    # Archive: sortiert, damit die Meldungen in Reihenfolge kommen.
    for pfad in sorted(ordner.iterdir()):
        if logdatum.archivtag(pfad.name) is None:
            continue          # gc.log, latest.log und alles Fremde
        alles |= _datei_auswerten(pfad)
        dateien += 1

    # latest.log deckt die Zeit seit dem letzten Serverstart ab. Sie steht
    # meist schon im Protokoll — aber nur, wenn mcs-playerlog durchgehend
    # lief. Eine Luecke waere sonst genau dann da, wenn der Dienst mal aus war.
    latest = ordner / "latest.log"
    if latest.is_file():
        alles |= _datei_auswerten(latest)
        dateien += 1

    return alles, dateien


def protokoll_lesen(pfad):
    """Liest das vorhandene Spielerprotokoll.

    Liefert (kopfzeilen, eintraege). Ein Eintrag ist
    (zeitpunkt, rang, text, [anhaengende Zeilen]).

    Zeilen ohne Zeitstempel gehen NICHT verloren: Die am Anfang sind der
    Kopf der Datei, spaetere haengen an ihrem Eintrag und wandern mit ihm
    durch die Sortierung. Hier wird die einzige dauerhafte Aufzeichnung
    darueber neu geschrieben, wer wann da war — was hier verschwindet, ist
    weg.
    """
    if not Path(pfad).is_file():
        return [], []

    kopf, eintraege = [], []
    with open(pfad, "r", encoding="utf-8", errors="ignore") as f:
        for zeile in f.read().splitlines():
            treffer = _EINTRAG.match(zeile)
            if treffer:
                zeit = datetime.strptime(treffer.group(1), "%Y-%m-%d %H:%M:%S")
                eintraege.append([zeit, _rang(treffer.group(2)),
                                  treffer.group(2), []])
            elif eintraege:
                eintraege[-1][3].append(zeile)
            else:
                kopf.append(zeile)
    return kopf, eintraege


def main():
    p = argparse.ArgumentParser(
        description="Traegt fruehere Besuche aus den Serverprotokollen nach.")
    p.add_argument("--zeigen", action="store_true",
                   help="Nur berichten, was nachzutragen waere. Aendert nichts.")
    p.add_argument("--protokoll", default=None, help="Abweichendes Spielerprotokoll.")
    p.add_argument("--logs", default=None, help="Abweichender logs/-Ordner.")
    args = p.parse_args()

    protokoll = args.protokoll or PLAYER_ACTIVITY_LOG
    logordner = args.logs or str(Path(MINECRAFT_LOG).parent)

    print(f"Serverprotokolle: {logordner}")
    print(f"Spielerprotokoll: {protokoll}")

    aus_logs, dateien = serverlogs_lesen(logordner)
    if aus_logs is None:
        return 1

    kopf, vorhanden = protokoll_lesen(protokoll)
    bekannt = {(e[0], e[2]) for e in vorhanden}
    neu = [[z, r, t, []] for (z, r, t) in aus_logs if (z, t) not in bekannt]

    print(f"\n{dateien} Serverprotokolle gelesen, {len(aus_logs)} Ereignisse darin.")
    print(f"Im Spielerprotokoll bereits: {len(vorhanden)}")
    print(f"Nachzutragen:                {len(neu)}")

    if not neu:
        # Der wiederholte Lauf landet hier. Nichts zu tun heisst: nicht
        # anfassen — auch nicht "sicherheitshalber neu sortieren".
        print("\nNichts nachzutragen. Die Datei bleibt unberuehrt.")
        return 0

    alle = vorhanden + neu
    alle.sort(key=lambda e: (e[0], e[1], e[2]))
    print(f"Danach insgesamt:            {len(alle)}")
    print(f"Zeitraum: {alle[0][0]:%d.%m.%Y} bis {alle[-1][0]:%d.%m.%Y}")

    if args.zeigen:
        print("\n--zeigen: Es wurde nichts geaendert.")
        return 0

    # Sicherung zuerst. Das Spielerprotokoll ist die einzige dauerhafte
    # Aufzeichnung darueber, wer wann da war — es gibt keine zweite Kopie.
    if Path(protokoll).is_file():
        sicherung = f"{protokoll}.vor-nachtrag"
        try:
            with open(protokoll, "rb") as quelle, open(sicherung, "wb") as ziel:
                ziel.write(quelle.read())
            os.chmod(sicherung, 0o600)
        except OSError as fehler:
            print(f"\nFEHLER: Sicherung fehlgeschlagen: {fehler}", file=sys.stderr)
            print("Es wurde NICHTS geaendert.", file=sys.stderr)
            return 1
        print(f"\nSicherung angelegt: {sicherung}")

    # Erst daneben schreiben, dann umbenennen: Ein Abbruch mitten im
    # Schreiben hinterlaesst sonst ein halbes Protokoll, und das saehe aus
    # wie ein vollstaendiges.
    zwischen = f"{protokoll}.neu"
    try:
        with open(zwischen, "w", encoding="utf-8") as f:
            for zeile in kopf:
                f.write(zeile + "\n")
            for zeit, _, text, anhang in alle:
                f.write(f"{zeit:%Y-%m-%d %H:%M:%S} | {text}\n")
                for zusatz in anhang:
                    f.write(zusatz + "\n")
        # Dieselben Rechte wie bei log_player_activity.sh: Darin stehen
        # IP-Adressen und UUIDs (seit 21.10.2026, vorher rw-rw-r--).
        os.chmod(zwischen, 0o600)
        os.replace(zwischen, protokoll)
    except OSError as fehler:
        print(f"\nFEHLER beim Schreiben: {fehler}", file=sys.stderr)
        print(f"Das bisherige Protokoll steht unveraendert in {protokoll}.",
              file=sys.stderr)
        return 1

    # Nachzaehlen statt annehmen.
    _, jetzt = protokoll_lesen(protokoll)
    print(f"Erledigt. {len(neu)} Eintraege nachgetragen, "
          f"{len(jetzt)} stehen jetzt darin.")
    if len(jetzt) != len(alle):
        print("! Die Nachzaehlung passt nicht — bitte die Sicherung ansehen.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
