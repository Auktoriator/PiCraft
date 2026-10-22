#!/usr/bin/env python3
"""
historie-aufbauen.py — Den Historien-Index in einem Rutsch aufbauen.

Die Historienseite schreibt ihren Index beim Oeffnen selbst fort. Der
ERSTE Aufbau ist aber der teuerste: Er liest jedes Serverprotokoll, das je
geschrieben wurde. Auf der Beispielinstallation waren das am 21.09.2026
229 Archive mit 17 MB und rund eine Sekunde -- das ist verschmerzbar, aber
es ist unnoetig, dass der erste Besucher der Seite darauf wartet.

    python3 tools/historie-aufbauen.py --zeigen   # nur berichten
    python3 tools/historie-aufbauen.py            # aufbauen

Es ist WIEDERHOLBAR: Ein zweiter Lauf liest nur latest.log nach und
aendert sonst nichts. Ein Archiv wird genau einmal ausgewertet.

Zwei Dinge, bei denen das Naheliegende hier falsch ist:

 1. **latest.log laesst sich nicht stueckweise lesen.** Es wird rueckwaerts
    datiert (die Aenderungszeit gehoert zur letzten Zeile), das Datum der
    ersten Zeile haengt also am Ende der Datei. Eine Byte-Lesemarke waere
    damit unvereinbar. Die Datei wird bei jedem Serverstart neu angelegt
    und ist entsprechend klein; sie wird jedes Mal ganz gelesen.
 2. **Die Rechte setzt nicht dieses Werkzeug**, sondern
    `historie.verbindung()` -- und zwar vor dem ersten Schreiben. Es gibt
    drei Wege in diese Datei, und ein chmod nur hier waere der zweite Weg
    zur selben Sache, der die Regel des ersten nicht kennt.

Die Ausgabe gehoert NICHT ins Repository: In der Historie stehen echte
Namen und Chat-Nachrichten. Wer einen Messbeleg braucht, nimmt Platzhalter.
"""

import argparse
import os
import sys
from pathlib import Path

_ADMIN = Path(__file__).resolve().parent.parent / "admin"
sys.path.insert(0, str(_ADMIN))

import historie  # noqa: E402
from einstellungen import (HISTORIE_DB, HISTORIE_TAGE,  # noqa: E402
                           MINECRAFT_LOG, PLAYER_ACTIVITY_LOG, lade_mcs_conf)

lade_mcs_conf()


def zahlen(db):
    return (db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0],
            db.execute("SELECT COUNT(*) FROM aeusserung").fetchone()[0])


def main():
    zerleger = argparse.ArgumentParser(
        description="Baut den Historien-Index aus Hauptbuch und "
                    "Serverprotokollen auf.")
    zerleger.add_argument("--zeigen", action="store_true",
                          help="nur berichten, nichts schreiben")
    args = zerleger.parse_args()

    logordner = Path(MINECRAFT_LOG).parent

    print(f"Hauptbuch:        {PLAYER_ACTIVITY_LOG}")
    print(f"Serverprotokolle: {logordner}")
    print(f"Historie:         {HISTORIE_DB}")
    print()

    if not Path(PLAYER_ACTIVITY_LOG).is_file():
        print("Fehler: Das Spielerprotokoll gibt es nicht.", file=sys.stderr)
        return 1
    if not logordner.is_dir():
        print(f"Fehler: {logordner} gibt es nicht.", file=sys.stderr)
        return 1

    if args.zeigen:
        # Auch der Bericht braucht die Datenbank -- sonst wuesste er nicht,
        # was schon drinsteht. Gibt es sie noch nicht, steht nichts drin, und
        # das laesst sich sagen, ohne sie anzulegen. Bis zum 23.09.2026 legte
        # --zeigen sie an (verbindung() erzeugt Datei und Schema) und schrieb
        # darunter "Es wurde nichts geschrieben" (nachgestellt, 36 KB).
        if not Path(HISTORIE_DB).is_file():
            print("Den Index gibt es noch nicht. Anlegen mit:")
            print(f"  python3 {Path(__file__).resolve()}")
            print()
            print("Es wurde nichts geschrieben (--zeigen).")
            return 0
        db = historie.verbindung(HISTORIE_DB)
        sitzungen, aeusserungen = zahlen(db)
        archive = sum(1 for p in logordner.iterdir()
                      if p.name.endswith(".log.gz"))
        fertig = db.execute("SELECT COUNT(*) FROM quelle").fetchone()[0]
        print(f"Im Index: {sitzungen} Sitzungen, {aeusserungen} "
              f"Aeusserungen.")
        print(f"Archive:  {archive} vorhanden, {fertig} davon ausgewertet.")
        von, bis = historie.zeitraum(db)
        print(f"Zeitraum: {von or '—'} bis {bis or '—'}")
        print()
        print("Es wurde nichts geschrieben (--zeigen).")
        return 0

    db = historie.verbindung(HISTORIE_DB)
    vorher = zahlen(db)

    neu = historie.aktualisieren(db, PLAYER_ACTIVITY_LOG, logordner)
    nachher = zahlen(db)

    print(f"Sitzungen:    {nachher[0]} im Index ({neu['sitzungen']:+d})")
    print(f"Aeusserungen: {nachher[1]} im Index ({neu['aeusserungen']:+d})")

    if HISTORIE_TAGE:
        weg = historie.aufraeumen(db, HISTORIE_TAGE)
        print(f"Aufbewahrung: {HISTORIE_TAGE} Tage — {weg} Eintrag/Eintraege "
              f"entfernt.")
    else:
        print("Aufbewahrung: unbegrenzt (MCS_HISTORIE_TAGE=0).")

    von, bis = historie.zeitraum(db)
    print(f"Zeitraum:     {von or '—'} bis {bis or '—'}")

    modus = oct(os.stat(HISTORIE_DB).st_mode & 0o777)
    print(f"Rechte:       {modus} (muss 0o600 sein — Chat-Inhalte)")

    if vorher == nachher:
        print("\nNichts Neues. Die Datei ist unveraendert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
