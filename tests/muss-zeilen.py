#!/usr/bin/env python3
"""Wertet die "(muss … sein)"-Zeilen eines Abnahme-Protokolls aus.

Warum es diese Datei gibt (23.09.2026): Der Abnahmetest schreibt rund
fuenfzig Pruefungen im Stil

    Treffer in mcs.conf: 0 (muss 0 sein)

Die Wache in tests/abnahme.sh (seit 70cf307, "alle Inhaltspruefungen
werden verbindlich") sucht aber nur nach dem Wort FEHLER. Stand dort
"Treffer in mcs.conf: 1 (muss 0 sein)", blieb der Test gruen — genau die
Sorte stiller Ausfall, die ein Test verhindern soll.

Verglichen wird der Wert unmittelbar vor "(muss" mit dem Sollwert. Was
sich nicht vergleichen laesst, wird NICHT durchgewunken, sondern als "nicht
maschinell geprueft" gezaehlt und ausgegeben (Leitsatz 5).

Aufruf:  python3 tests/muss-zeilen.py PROTOKOLL     (0 = alles gut)
"""

import re
import sys

EINHEIT = r"(?:\s+(?:Treffer|Zeichen|Eintrag/Einträge))?"
# "sein" oder "bleiben", dahinter optional ein Nachsatz nach Komma oder
# Gedankenstrich: "(muss 7 bleiben)", "(muss pi sein, NICHT root)",
# "(muss 1 sein — Versand schlug fehl)". Bis zum 23.09.2026 kannte das Muster
# nur "(muss X sein)"; die anderen Formen landeten bei "offen" und liessen
# den Lauf gruen — darunter die Pruefung, dass nicht als pi installiert wird
# (gefunden von der Zweitmeinung zu Durchgang 1).
ZEILE = re.compile(r"(\S+)" + EINHEIT +
                   r"\s+\(muss (.+?) (?:sein|bleiben)(?:\s*[,—–-][^)]*)?\)")
GEWACHSEN = re.compile(r"(\d+) -> (\d+)\s+\(muss um (\d+) gewachsen sein\)")


def pruefen(zeile):
    """Liefert eine Liste von (ergebnis, text): ergebnis ok|falsch|offen."""
    aus = []
    for treffer in GEWACHSEN.finditer(zeile):
        vorher, nachher, um = map(int, treffer.groups())
        aus.append(("ok" if nachher - vorher == um else "falsch", zeile))
    for treffer in ZEILE.finditer(zeile):
        ist, soll = treffer.group(1).rstrip(",;"), treffer.group(2)
        # "view-distance=12 (muss 12 bleiben)": verglichen wird der Wert.
        ist = ist.rsplit("=", 1)[-1]
        if soll.startswith("um ") and soll.endswith("gewachsen"):
            continue                      # oben schon erledigt
        if soll.startswith("wieder "):
            soll = soll[len("wieder "):]
        if soll.lower() == "leer":
            gut = ist in ('""', "''")
        elif soll.startswith("ungleich "):
            gut = ist != soll[len("ungleich "):]
        elif " " in soll:
            # Sollwert aus mehreren Woertern ("Mon..Fri 05:17:00"): Der Text
            # vor "(muss" muss darauf enden.
            gut = zeile[:treffer.start(2) - len("(muss ")].rstrip().endswith(soll)
        else:
            gut = ist == soll
        aus.append(("ok" if gut else "falsch", zeile))
    # Eine Muss-Zeile, auf die kein Muster passt, darf nicht still wegfallen.
    return aus or [("offen", zeile)]


def main(pfad):
    with open(pfad, encoding="utf-8", errors="replace") as datei:
        zeilen = [z.rstrip("\n") for z in datei if "(muss " in z]
    # Ueberschriften ("--- Cronjob (muss LEER sein) ---") tragen ihren
    # Istwert in den Zeilen darunter; verglichen wuerde sonst das Wort
    # "Cronjob" mit "LEER" — ein Fehlalarm. Sie werden deshalb nicht
    # verglichen, aber als "offen" gemeldet: Bis zum 23.09.2026 fielen sie
    # ganz weg, und die Cronjob-Pruefung verschwand spurlos (Zweitmeinung
    # zu Durchgang 2).
    ergebnisse = [e for z in zeilen
                  for e in ([("offen", z)] if z.lstrip().startswith("---")
                            else pruefen(z))]
    falsch = [t for e, t in ergebnisse if e == "falsch"]
    offen = [t for e, t in ergebnisse if e == "offen"]
    ok = sum(1 for e, _ in ergebnisse if e == "ok")
    print(f"Muss-Zeilen: {ok} passen, {len(falsch)} weichen ab, "
          f"{len(offen)} nicht maschinell geprueft.")
    for t in offen:
        print(f"  (von Hand ansehen) {t.strip()}")
    for t in falsch:
        print(f"  ABWEICHUNG: {t.strip()}", file=sys.stderr)
    return 1 if falsch else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
